#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
oauth_drive.py — autorizar UNA sola vez el respaldo de Truefie contra Google Drive.

QUE HACE
  1. Abre el navegador para que Andrea autorice con su cuenta de Gmail.
  2. Se queda con el refresh token (el permiso que no vence y que va a usar
     GitHub Actions cada semana, sin que nadie tenga que estar presente).
  3. Crea la carpeta "Respaldo Entregas Truefie" en su Drive.
  4. Sube un archivo de prueba y lo borra, para demostrar que el permiso
     sirve de verdad ANTES de cargar nada en GitHub.
  5. Deja los cuatro valores en un archivo local, con permisos 600.

QUE NO HACE
  - No imprime el refresh token en pantalla. Va a un archivo, para que no
    quede en el historial de la terminal ni se pegue por chat sin querer.
  - No toca el repo. El archivo de salida vive FUERA de Conciliacion/.

POR QUE EL SCOPE ES drive.file Y NO drive
  drive.file da acceso SOLO a los archivos que esta app crea. Aunque alguien
  robara los secrets de GitHub, no podria leer el resto del Drive de Andrea.
  Es scope no sensible: no necesita verificacion de Google.
  Consecuencia a tener presente: la app NO PUEDE VER una carpeta creada a
  mano desde el navegador. Por eso la carpeta la crea este script.

REQUISITO PREVIO — SIN ESTO EL TOKEN DURA 7 DIAS
  La pantalla de consentimiento tiene que estar en PRODUCCION, no en prueba.
  En modo "Testing" Google emite refresh tokens que vencen a los 7 dias y el
  respaldo moriria en silencio. Ver las instrucciones que acompanan a este
  script. El script avisa igual al final.

SOLO NECESITA PYTHON 3 (probado en 3.9). No instala nada.
"""

import base64
import hashlib
import http.server
import json
import os
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from datetime import datetime

CARPETA = "Respaldo Entregas Truefie"
SCOPE = "https://www.googleapis.com/auth/drive.file"
BASE = os.path.expanduser("~/Desktop/truefie-respaldo")
SALIDA = os.path.join(BASE, "SECRETS_PARA_GITHUB.txt")

AUTH_URI = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URI = "https://oauth2.googleapis.com/token"
API = "https://www.googleapis.com/drive/v3/files"
UPLOAD = "https://www.googleapis.com/upload/drive/v3/files"


def morir(msg):
    print("\n  ERROR: " + msg + "\n")
    sys.exit(1)


def http_json(url, token=None, method="GET", data=None, headers=None):
    h = dict(headers or {})
    if token:
        h["Authorization"] = "Bearer " + token
    cuerpo = data
    if isinstance(data, dict) and "Content-Type" not in h:
        cuerpo = json.dumps(data).encode("utf-8")
        h["Content-Type"] = "application/json; charset=UTF-8"
    req = urllib.request.Request(url, data=cuerpo, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            crudo = r.read().decode("utf-8")
            return json.loads(crudo) if crudo.strip() else {}
    except urllib.error.HTTPError as e:
        detalle = e.read().decode("utf-8", "replace")[:600]
        morir("Google respondio %s en %s\n\n  %s" % (e.code, url.split("?")[0], detalle))


def leer_cliente():
    """Toma el JSON del cliente OAuth que Andrea bajo de Google Cloud."""
    if not os.path.isdir(BASE):
        morir("no existe la carpeta %s\n  Creala y pone ahi el JSON que bajaste de Google Cloud." % BASE)
    candidatos = [f for f in sorted(os.listdir(BASE)) if f.endswith(".json")]
    if not candidatos:
        morir("no hay ningun .json en %s\n  Ahi va el archivo que bajaste al crear el cliente OAuth." % BASE)
    if len(candidatos) > 1:
        print("  Hay varios .json; uso el primero: " + candidatos[0])
    ruta = os.path.join(BASE, candidatos[0])
    with open(ruta, "r", encoding="utf-8") as fh:
        d = json.load(fh)
    nodo = d.get("installed") or d.get("web")
    if not nodo:
        morir("%s no parece un cliente OAuth de escritorio (falta la clave 'installed')." % ruta)
    if "web" in d:
        morir("ese cliente es de tipo 'Aplicacion web'. Hace falta uno de tipo 'Aplicacion de escritorio'.")
    return nodo["client_id"], nodo["client_secret"], os.path.basename(ruta)


class Recibidor(http.server.BaseHTTPRequestHandler):
    resultado = None

    def do_GET(self):
        q = urllib.parse.urlparse(self.path).query
        p = urllib.parse.parse_qs(q)
        Recibidor.resultado = p
        ok = "code" in p
        cuerpo = (
            "<html><head><meta charset='utf-8'><title>Truefie</title></head>"
            "<body style='font-family:system-ui;padding:3rem;text-align:center'>"
            + ("<h2>Listo.</h2><p>Ya podes cerrar esta pestana y volver a la terminal.</p>"
               if ok else
               "<h2>No se autorizo.</h2><p>Volve a la terminal y mira el mensaje.</p>")
            + "</body></html>"
        ).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(cuerpo)))
        self.end_headers()
        self.wfile.write(cuerpo)

    def log_message(self, *a):
        pass


def autorizar(client_id, client_secret):
    verifier = base64.urlsafe_b64encode(secrets.token_bytes(64)).decode().rstrip("=")
    challenge = base64.urlsafe_b64encode(
        hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
    estado = secrets.token_urlsafe(16)

    srv = http.server.HTTPServer(("127.0.0.1", 0), Recibidor)
    srv.timeout = 300
    redirect = "http://127.0.0.1:%d" % srv.server_address[1]

    url = AUTH_URI + "?" + urllib.parse.urlencode({
        "client_id": client_id,
        "redirect_uri": redirect,
        "response_type": "code",
        "scope": SCOPE,
        "access_type": "offline",     # sin esto no hay refresh token
        "prompt": "consent",          # fuerza que lo emita aunque ya hubiera autorizado
        "state": estado,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    })

    print("\n  Se abre el navegador. Entra con la cuenta de Gmail de Andrea")
    print("  y aceptá el permiso.")
    print("\n  Si no se abre solo, pegá esta direccion en el navegador:\n")
    print("  " + url + "\n")
    try:
        webbrowser.open(url)
    except Exception:
        pass

    srv.handle_request()
    res = Recibidor.resultado
    if not res:
        morir("no llego respuesta del navegador (pasaron 5 minutos). Corré el script de nuevo.")
    if "error" in res:
        morir("Google devolvio: %s" % res["error"][0])
    if res.get("state", [None])[0] != estado:
        morir("el 'state' no coincide. Por seguridad no sigo. Corré el script de nuevo.")

    tok = http_json(TOKEN_URI, method="POST",
                    data=urllib.parse.urlencode({
                        "client_id": client_id,
                        "client_secret": client_secret,
                        "code": res["code"][0],
                        "code_verifier": verifier,
                        "grant_type": "authorization_code",
                        "redirect_uri": redirect,
                    }).encode(),
                    headers={"Content-Type": "application/x-www-form-urlencoded"})
    if not tok.get("refresh_token"):
        morir("Google no devolvio refresh token.\n"
              "  Suele pasar si la app ya estaba autorizada. Quitá el acceso en\n"
              "  https://myaccount.google.com/permissions y corré el script otra vez.")
    return tok["refresh_token"], tok["access_token"]


def carpeta_id(access):
    """Busca la carpeta entre lo que creo esta app; si no esta, la crea."""
    q = ("mimeType='application/vnd.google-apps.folder' and trashed=false and name='%s'"
         % CARPETA.replace("'", "\\'"))
    hallado = http_json(API + "?" + urllib.parse.urlencode({"q": q, "fields": "files(id,name)"}), access)
    files = hallado.get("files", [])
    if files:
        print("  Ya existia la carpeta creada por esta app; la reuso.")
        return files[0]["id"], False
    nueva = http_json(API + "?fields=id", access, "POST",
                      {"name": CARPETA, "mimeType": "application/vnd.google-apps.folder"})
    return nueva["id"], True


def prueba_de_extremo_a_extremo(access, cid):
    """Sube un archivo y lo borra. Si esto pasa, GitHub tambien va a poder."""
    b = "truefie" + secrets.token_hex(8)
    meta = json.dumps({"name": "_prueba_de_permiso.txt", "parents": [cid]})
    contenido = ("Prueba de permiso del respaldo de Truefie — %s\n"
                 % datetime.now().strftime("%Y-%m-%d %H:%M")).encode("utf-8")
    cuerpo = (
        ("--%s\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n%s\r\n" % (b, meta)).encode()
        + ("--%s\r\nContent-Type: text/plain\r\n\r\n" % b).encode()
        + contenido
        + ("\r\n--%s--\r\n" % b).encode()
    )
    sub = http_json(UPLOAD + "?uploadType=multipart&fields=id", access, "POST", cuerpo,
                    {"Content-Type": "multipart/related; boundary=%s" % b})
    http_json(API + "/" + sub["id"], access, "DELETE")
    return True


def main():
    print("\n" + "=" * 68)
    print("  Respaldo Truefie — autorizacion de Google Drive (una sola vez)")
    print("=" * 68)

    cid_oauth, secreto, archivo = leer_cliente()
    print("\n  Cliente OAuth leido de: %s" % archivo)

    refresh, access = autorizar(cid_oauth, secreto)
    print("\n  Autorizado.")

    carpeta, creada = carpeta_id(access)
    print("  Carpeta '%s': %s" % (CARPETA, "creada" if creada else "reusada"))
    print("  https://drive.google.com/drive/folders/%s" % carpeta)

    prueba_de_extremo_a_extremo(access, carpeta)
    print("  Prueba de escritura: subio y borro un archivo. El permiso sirve.")

    with open(SALIDA, "w", encoding="utf-8") as fh:
        fh.write("Secrets para GitHub — repo TrueFood1/Conciliacion\n")
        fh.write("Generado %s\n" % datetime.now().strftime("%Y-%m-%d %H:%M"))
        fh.write("\nNO subir este archivo a ningun lado. NO pegarlo por chat.\n")
        fh.write("Cuando los cuatro esten cargados en GitHub, borralo.\n\n")
        fh.write("GDRIVE_CLIENT_ID\n%s\n\n" % cid_oauth)
        fh.write("GDRIVE_CLIENT_SECRET\n%s\n\n" % secreto)
        fh.write("GDRIVE_REFRESH_TOKEN\n%s\n\n" % refresh)
        fh.write("GDRIVE_FOLDER_ID\n%s\n" % carpeta)
    os.chmod(SALIDA, 0o600)

    print("\n" + "-" * 68)
    print("  Los CUATRO valores quedaron en:")
    print("  %s" % SALIDA)
    print("\n  Ese archivo es una credencial. No lo pegues por chat ni lo subas")
    print("  al repo. Borralo cuando esten cargados en GitHub.")
    print("-" * 68)
    print("\n  RECORDATORIO: si la pantalla de consentimiento sigue en modo")
    print("  PRUEBA, este token vence en 7 dias. Tiene que estar en PRODUCCION.")
    print()


if __name__ == "__main__":
    main()
