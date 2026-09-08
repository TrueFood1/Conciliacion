#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
probar_conexion.py — probar la cadena de conexion de Supabase desde la Mac.

COMO SE USA
    python3 probar_conexion.py --clave      <- el camino recomendado
        Copia SOLO la contrasena de la base al portapapeles (desde el gestor
        de contrasenas) y corre esto. El script arma la cadena el mismo, con
        el host, el puerto, el usuario y la base correctos, y codifica los
        simbolos de la contrasena como manda una URL. Asi "cadena mal armada"
        y "usuario mal escrito" dejan de ser causas posibles: lo unico que se
        esta probando es la contrasena.

    python3 probar_conexion.py --pegar
        Igual, pero en el portapapeles va la cadena ENTERA (postgresql://...).

    python3 probar_conexion.py --stdin
        Lee la cadena de la entrada estandar. Para tuberias y automatizacion.

    python3 probar_conexion.py --clave --copiar
        Si la contrasena sirve, deja la cadena YA ARMADA en el portapapeles,
        lista para pegar en el campo del secret de GitHub. Nadie la teclea ni
        la edita dentro del campo: se pega entera y se reemplaza todo. Ese
        era el punto ciego.

  NO usa getpass. getpass lee del teclado directo (/dev/tty): ignora el
  redirect de archivo y en la terminal de Andrea levanta el dialogo de
  llavero de macOS, que bloquea el pegado. Medido el 7-sep-2026.

  La contrasena NUNCA se escribe en disco, NUNCA va como argumento (no
  aparece en `ps`), NUNCA queda en el historial del shell y NUNCA se imprime:
  de ella solo se muestran el largo y que clases de caracteres tiene.

QUE HACE
  1. Desarma la cadena y muestra un informe CENSURADO: usuario, host, puerto
     y base se ven; la contrasena NUNCA — solo su largo y que tipo de
     caracteres tiene.
  2. Se conecta de verdad: TCP, TLS y autenticacion SCRAM-SHA-256, que es
     lo mismo que hace pg_dump. Reporta el error textual de Postgres.

  Asi separa las dos causas posibles: si la cadena esta mal armada, o si la
  contrasena no es la que la base espera.

Solo necesita Python 3. No instala nada.
"""

import base64
import hashlib
import hmac
import os
import re
import socket
import ssl
import struct
import sys
import urllib.parse


def sha256(b):
    return hashlib.sha256(b).digest()


def hmac256(key, msg):
    return hmac.new(key, msg, hashlib.sha256).digest()


def prueba_scram(password, salt, iteraciones, primer_cliente, primer_servidor, final_sin_proof):
    """SCRAM-SHA-256 segun RFC 5802/7677. Devuelve el ClientProof en base64."""
    salted = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iteraciones)
    client_key = hmac256(salted, b"Client Key")
    stored_key = sha256(client_key)
    auth_msg = (primer_cliente + "," + primer_servidor + "," + final_sin_proof).encode()
    client_sig = hmac256(stored_key, auth_msg)
    proof = bytes(a ^ b for a, b in zip(client_key, client_sig))
    return base64.b64encode(proof).decode()


# ── protocolo de Postgres ────────────────────────────────────────────────
def leer_exacto(s, n):
    buf = b""
    while len(buf) < n:
        c = s.recv(n - len(buf))
        if not c:
            raise IOError("el servidor cerro la conexion")
        buf += c
    return buf


def leer_mensaje(s):
    tipo = leer_exacto(s, 1)
    largo = struct.unpack("!I", leer_exacto(s, 4))[0]
    return tipo, leer_exacto(s, largo - 4)


def paquete(tipo, cuerpo):
    return tipo + struct.pack("!I", len(cuerpo) + 4) + cuerpo


def error_legible(cuerpo):
    campos = {}
    for parte in cuerpo.split(b"\x00"):
        if len(parte) > 1:
            campos[chr(parte[0])] = parte[1:].decode("utf-8", "replace")
    return campos.get("S", "ERROR"), campos.get("C", "?"), campos.get("M", "(sin mensaje)")


def conectar(host, puerto, usuario, base, password):
    """Prueba la conexion y la CIERRA. Devuelve None si autentico, o el error."""
    s, fallo = abrir(host, puerto, usuario, base, password)
    if s is not None:
        s.sendall(paquete(b"X", b""))
        s.close()
    return fallo


def abrir(host, puerto, usuario, base, password):
    """Conecta y autentica, y DEJA EL SOCKET ABIERTO para poder consultar.

    Devuelve (socket, None) si autentico, o (None, "texto del error").
    pg_lector.py lo importa de aca para no duplicar el SCRAM.
    """
    cru = socket.create_connection((host, puerto), timeout=25)
    # pedir TLS
    cru.sendall(struct.pack("!II", 8, 80877103))
    if leer_exacto(cru, 1) != b"S":
        return None, "el servidor rechazo TLS"
    # Cifrar SIN verificar el certificado, que es lo que hace libpq con su
    # sslmode por defecto ('prefer'). El pooler de Supabase presenta una
    # cadena autofirmada: verificar aca daria un fallo que pg_dump no tiene.
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    s = ctx.wrap_socket(cru, server_hostname=host)

    inicio = b"".join([b"user\x00", usuario.encode(), b"\x00",
                       b"database\x00", base.encode(), b"\x00\x00"])
    s.sendall(struct.pack("!II", len(inicio) + 8, 196608) + inicio)

    while True:
        tipo, cuerpo = leer_mensaje(s)
        if tipo == b"E":
            sev, cod, msg = error_legible(cuerpo)
            return None, "%s %s: %s" % (sev, cod, msg)
        if tipo != b"R":
            continue
        codigo = struct.unpack("!I", cuerpo[:4])[0]
        if codigo == 0:
            return s, None                   # autenticado, socket abierto
        if codigo == 3:                      # contrasena en claro
            s.sendall(paquete(b"p", password.encode() + b"\x00"))
        elif codigo == 10:                   # SASL
            mecs = [m.decode() for m in cuerpo[4:].split(b"\x00") if m]
            if "SCRAM-SHA-256" not in mecs:
                return None, "el servidor no ofrece SCRAM-SHA-256, ofrece: " + ", ".join(mecs)
            nonce = base64.b64encode(os.urandom(18)).decode()
            primer_cliente = "n=,r=" + nonce
            ini = b"SCRAM-SHA-256\x00" + struct.pack("!I", len(primer_cliente) + 3) + b"n,," + primer_cliente.encode()
            s.sendall(paquete(b"p", ini))
            tipo, cuerpo = leer_mensaje(s)
            if tipo == b"E":
                sev, cod, msg = error_legible(cuerpo)
                return None, "%s %s: %s" % (sev, cod, msg)
            primer_servidor = cuerpo[4:].decode()
            d = dict(p.split("=", 1) for p in primer_servidor.split(","))
            final_sin_proof = "c=biws,r=" + d["r"]
            proof = prueba_scram(password, base64.b64decode(d["s"]), int(d["i"]),
                                 primer_cliente, primer_servidor, final_sin_proof)
            s.sendall(paquete(b"p", (final_sin_proof + ",p=" + proof).encode()))
        elif codigo in (11, 12):
            continue
        else:
            return None, "el servidor pide un metodo de autenticacion que este script no cubre (codigo %d)" % codigo


# ── de donde sale la contrasena ──────────────────────────────────────────
# Partes NO secretas de la conexion. El ref del proyecto ya es publico: esta
# en index.html, que se sirve desde GitHub Pages. Lo secreto es la clave.
REF     = "tomijkqnmpjcraaoeviq"
HOST    = "aws-0-us-east-1.pooler.supabase.com"
PUERTO  = 5432
USUARIO = "postgres." + REF          # Supavisor exige el sufijo del proyecto
BASE    = "postgres"


def del_portapapeles():
    """Lee el portapapeles de macOS. Nada toca el disco ni el historial."""
    import subprocess
    try:
        r = subprocess.run(["pbpaste"], capture_output=True, timeout=10)
    except FileNotFoundError:
        sys.exit("[FALTA] pbpaste no existe (esto es solo para macOS). Usa --stdin.")
    if r.returncode != 0:
        sys.exit("[PORTAPAPELES] pbpaste fallo con codigo %d" % r.returncode)
    return r.stdout.decode("utf-8", "replace")


def al_portapapeles(texto):
    import subprocess
    p = subprocess.Popen(["pbcopy"], stdin=subprocess.PIPE)
    p.communicate(texto.encode("utf-8"))
    return p.returncode == 0


def informe_de_clave(clave):
    """Describe la clave SIN imprimirla. Es lo que caza el caracter de mas."""
    avisos = []
    print("  largo       : %d caracteres" % len(clave))
    clases = []
    if any(c.islower() for c in clave): clases.append("minusculas")
    if any(c.isupper() for c in clave): clases.append("MAYUSCULAS")
    if any(c.isdigit() for c in clave): clases.append("digitos")
    simbolos = sorted({c for c in clave if not c.isalnum()})
    if simbolos: clases.append("%d simbolo(s) distintos" % len(simbolos))
    print("  composicion : %s" % (", ".join(clases) or "?"))
    if simbolos:
        # NO se imprimen los simbolos en si: aunque parezcan inocuos, achican
        # el espacio de busqueda de la clave y esta conversacion queda escrita.
        # Lo unico que importa para el diagnostico es cuantos hay que codificar.
        peligrosos = [c for c in simbolos if c in "@:/?#[]&=+ %"]
        print("  simbolos    : %d distinto(s); %d de ellos rompen una URL si "
              "van sin codificar" % (len(simbolos), len(peligrosos)))
    if clave != clave.strip():
        avisos.append("tiene espacios o saltos de linea alrededor — eso viaja al secret")
    if "\n" in clave or "\r" in clave or "\t" in clave:
        avisos.append("tiene un salto de linea o un tabulador ADENTRO")
    for c in "[]":
        if c in clave:
            avisos.append("contiene %r — quedo un pedazo de la plantilla [YOUR-PASSWORD]" % c)
    if "YOUR-PASSWORD" in clave.upper() or "TU-CLAVE" in clave.upper():
        avisos.append("sigue siendo el texto de ejemplo, no la reemplazaste")
    return avisos


# Sal fija y NO secreta (vive en el repo). Sirve para que la huella no sea un
# hash pelado de la contrasena: es un hash de la cadena entera, salada, cortada
# a 12 hex. Alcanza de sobra para comparar dos cadenas sin exponer ninguna.
SAL = "truefie-respaldo-2026"


def huella(cadena):
    return hashlib.sha256((SAL + cadena).encode()).hexdigest()[:12]


def armar_cadena(clave):
    """postgresql://usuario:clave@host:puerto/base, con la clave codificada."""
    return "postgresql://%s:%s@%s:%d/%s" % (
        urllib.parse.quote(USUARIO, safe=""),
        urllib.parse.quote(clave, safe=""),
        HOST, PUERTO, BASE)


def main():
    args   = sys.argv[1:]
    copiar = "--copiar" in args
    modos  = [a for a in args if a in ("--clave", "--pegar", "--stdin")]
    if len(modos) != 1:
        print(__doc__.strip())
        print("\nElegi UN modo: --clave (recomendado), --pegar o --stdin.")
        return
    modo = modos[0]

    print(__doc__.split("COMO SE USA")[0].strip())

    if modo == "--stdin":
        crudo = sys.stdin.read()
    else:
        crudo = del_portapapeles()

    if not crudo.strip():
        print("\n  ⚠ no habia nada (%s vino vacio). Copia y volve a correr."
              % ("el portapapeles" if modo != "--stdin" else "la entrada"))
        return

    if modo == "--clave":
        # Lo que hay es SOLO la contrasena. La cadena la arma el script, asi
        # que el usuario, el host, el puerto y la codificacion dejan de ser
        # variables: lo unico bajo prueba es la clave.
        print("\n" + "=" * 64)
        print("  LA CONTRASENA QUE LEI (censurada — nunca se imprime)")
        print("=" * 64)
        clave  = crudo.strip("\r\n")          # el gestor suele pegar con \n final

        # ── Cordura ANTES de intentar conectar ───────────────────────────
        # Si el portapapeles trae otra cosa (un texto, una pagina, codigo),
        # el pooler responde 28P01 igual que con una clave equivocada, y el
        # consejo "reseteala en Supabase" seria FALSO y costaria un reseteo
        # al pedo. Paso el 7-sep-2026: el portapapeles tenia 7.386 caracteres.
        # Una clave de Supabase anda por los 16-40 caracteres.
        if len(clave) > 100 or "\n" in clave or "\r" in clave:
            print("\n  ⚠ ESTO NO PARECE UNA CONTRASENA — no intento conectar.")
            print("     largo: %d caracteres%s" % (
                len(clave), " y tiene saltos de linea" if "\n" in clave or "\r" in clave else ""))
            print("     Una clave de la base anda por los 16-40 caracteres y va")
            print("     en una sola linea. En el portapapeles quedo otra cosa.")
            print("\n     NO es que la clave este mal: es que no la lei.")
            print("     Copiala del gestor de contrasenas y volve a correr esto.")
            return

        avisos_clave = informe_de_clave(clave)
        if clave != clave.strip():
            print("\n  ⚠ Hay espacios alrededor. Los quito para la prueba, pero")
            print("    revisa que en el gestor no esten guardados asi.")
            clave = clave.strip()
        if avisos_clave:
            print("\n  AVISOS SOBRE LA CLAVE")
            for a in avisos_clave: print("   ⚠ " + a)
        cadena = armar_cadena(clave)
        print("\n  Cadena armada por el script (host, puerto, usuario y base")
        print("  fijos; los simbolos de la clave, codificados para URL).")
    else:
        cadena = crudo.strip()

    # ── informe censurado ────────────────────────────────────────────────
    print("\n" + "=" * 64)
    print("  COMO QUEDO INTERPRETADA LA CADENA")
    print("=" * 64)

    avisos = []
    if cadena != cadena.strip() or "\n" in cadena or "\r" in cadena:
        avisos.append("tiene espacios o saltos de linea alrededor — al pegarla en el secret eso viaja")
    if cadena[:1] in ("'", '"') or cadena[-1:] in ("'", '"'):
        avisos.append("empieza o termina con comillas: se copiaron de mas")
    if cadena.lower().startswith(("psql ", "pg_dump ")):
        avisos.append("empieza con un comando; la cadena es solo la parte postgresql://...")
    for c in "[]":
        if c in cadena:
            avisos.append("contiene %r — quedo un pedazo de la plantilla [YOUR-PASSWORD]" % c)

    # urlparse tira ValueError("Invalid IPv6 URL") si hay un corchete en la
    # cadena — el caso mas probable de "quedo un caracter de mas".
    try:
        u = urllib.parse.urlparse(cadena)
    except ValueError as e:
        print("  ⚠ la cadena no se puede desarmar: %s" % e)
        print("  ⚠ casi seguro trae un corchete suelto de la plantilla [YOUR-PASSWORD]")
        for a in avisos: print("  ⚠ " + a)
        return
    if u.scheme not in ("postgres", "postgresql"):
        print("  ⚠ no parece una URL de Postgres (esquema: %r)" % u.scheme)
        for a in avisos: print("  ⚠ " + a)
        return

    usuario = urllib.parse.unquote(u.username or "")
    password = urllib.parse.unquote(u.password or "")
    base = (u.path or "/").lstrip("/") or "(vacia)"
    puerto = u.port or 5432

    print("  usuario : %s" % (usuario or "(vacio)"))
    print("  host    : %s" % (u.hostname or "(vacio)"))
    print("  puerto  : %s" % puerto)
    print("  base    : %s" % base)
    if password:
        clases = []
        if any(c.islower() for c in password): clases.append("minusculas")
        if any(c.isupper() for c in password): clases.append("MAYUSCULAS")
        if any(c.isdigit() for c in password): clases.append("digitos")
        simbolos = [c for c in password if not c.isalnum()]
        if simbolos: clases.append("%d simbolo(s)" % len(simbolos))
        print("  clave   : %d caracteres (%s) — no se imprime" % (len(password), ", ".join(clases) or "?"))
        if simbolos:
            avisos.append("la clave tiene simbolos: en una URL hay que escribirlos codificados (@ -> %40, etc.)")
        if "YOUR-PASSWORD" in password.upper() or "TU-" in password.upper():
            avisos.append("la clave sigue siendo el texto de ejemplo, no la reemplazaste")
    else:
        avisos.append("la cadena NO trae contrasena")

    # avisos propios de Supabase
    host = u.hostname or ""
    if "pooler.supabase.com" in host:
        if "." not in usuario:
            avisos.append("host del POOLER pero usuario sin el sufijo del proyecto: "
                          "tiene que ser postgres.<ref>, no postgres")
        if puerto == 6543:
            avisos.append("puerto 6543 es el pooler de TRANSACCION; pg_dump necesita el de SESION (5432)")
    elif host.startswith("db.") and host.endswith(".supabase.co"):
        avisos.append("esta es la conexion DIRECTA, que es IPv6. Los runners de GitHub no tienen IPv6: "
                      "para el workflow hace falta la del Session pooler")

    if avisos:
        print("\n  AVISOS")
        for a in avisos: print("   ⚠ " + a)

    # ── conexion de verdad ───────────────────────────────────────────────
    print("\n" + "=" * 64)
    print("  CONEXION REAL (TCP + TLS + SCRAM, lo mismo que hace pg_dump)")
    print("=" * 64)
    try:
        fallo = conectar(u.hostname, puerto, usuario, base if base != "(vacia)" else "postgres", password)
    except Exception as e:
        fallo = "%s: %s" % (type(e).__name__, e)

    if fallo is None:
        print("\n  ✅ CONECTO Y AUTENTICO BIEN.")
        print("  La cadena sirve. Si el workflow igual falla, el problema esta")
        print("  en como quedo pegada en el secret de GitHub, no en la cadena.")
        print("\n  HUELLA de la cadena — para cotejar contra la que le llega al")
        print("  workflow, sin revelar ninguna de las dos:")
        print("     largo   : %d caracteres" % len(cadena))
        print("     huella  : %s" % huella(cadena))
        print("  El workflow imprime estas dos mismas lineas. Si coinciden, el")
        print("  secret tiene exactamente estos bytes. Si no, sobra o falta algo.")
        if copiar:
            if al_portapapeles(cadena):
                print("\n  📋 La cadena QUEDO EN EL PORTAPAPELES, ya armada.")
                print("     Pegala entera en el campo del secret (Cmd-A y despues")
                print("     Cmd-V, para reemplazar todo lo que haya). No la edites")
                print("     adentro del campo: editar ahi fue el punto ciego.")
                print("     Cuando termines, copia cualquier otra cosa para que no")
                print("     se quede en el portapapeles.")
            else:
                print("\n  ⚠ no se pudo copiar al portapapeles")
    else:
        print("\n  ❌ NO CONECTO:")
        print("     %s" % fallo)
        bajo = fallo.lower()
        if "password authentication failed" in bajo:
            print("\n  Eso es la contrasena, no el formato: el pooler encontro el")
            print("  proyecto y rechazo la clave. Reseteala en Supabase")
            print("  (Settings -> Database -> Reset database password) y volve a probar.")
        elif "not found" in bajo and ("tenant" in bajo or "enotfound" in bajo):
            print("\n  ESTE si es el error de usuario mal escrito: falta el sufijo")
            print("  del proyecto. El usuario tiene que ser postgres.<ref>.")
    print()


if __name__ == "__main__":
    main()
