#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verificar_instinct.py — prueba a Instinct con SU sesión real (13-oct-2026).

Lo corre Andrea, no Claude: lee el correo y la contraseña de `instinct.env` (al lado del repo,
ignorado por git) y NUNCA imprime la contraseña ni el token. Claude solo ve la tabla de abajo.

Qué prueba, con el interruptor ENCENDIDO (ENCENDER_ASISTENTE.sql):
  · Supabase: entra con la cuenta de Instinct; es asistente; el proxy lo deja leer.
  · Lee pedidos y tarifas de compra; NO ve Personal (rrhh_*).
  · NO escribe: un insert en ent_pedido (tabla con INSERT abierto) tiene que dar 42501. La fila va
    vacía a propósito: si el candado fallara, la base la rechaza igual por NOT NULL (23502) y no
    queda nada escrito; por eso un 23502 se marca como FALLA del candado, no como éxito.
  · Proxy de lectura (Odoo): le lee.
  · Servicio de escritura: no es socia → 403 en /quien y en /insumo.

    python3 herramientas/verificar_instinct.py            # con el interruptor encendido
    python3 herramientas/verificar_instinct.py --apagado  # después de APAGAR_ASISTENTE.sql (espera bloqueos)
"""
import json, os, re, sys, urllib.request, urllib.error

AQUI = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(AQUI)
SUPA = "https://tomijkqnmpjcraaoeviq.supabase.co"
PROXY = "https://truefood-proxy-lectura.onrender.com"
ESCRITURA = "https://truefie-escritura.onrender.com"


def env():
    ruta = os.path.join(REPO, "instinct.env")
    if not os.path.exists(ruta):
        sys.exit("Falta %s (INSTINCT_EMAIL e INSTINCT_PASS)." % ruta)
    d = {}
    for linea in open(ruta, encoding="utf-8"):
        if "=" in linea:
            k, v = linea.rstrip("\n").split("=", 1)
            d[k.strip()] = v
    if not d.get("INSTINCT_EMAIL") or not d.get("INSTINCT_PASS"):
        sys.exit("instinct.env no tiene INSTINCT_EMAIL e INSTINCT_PASS.")
    return d["INSTINCT_EMAIL"], d["INSTINCT_PASS"]


def anon():
    # La anon key es pública por diseño: la misma de index.html.
    m = re.search(r"const SUPA_ANON\s*=\s*'([^']+)'", open(os.path.join(REPO, "index.html"), encoding="utf-8").read())
    if not m:
        sys.exit("No encontré SUPA_ANON en index.html.")
    return m.group(1)


def pedir(metodo, url, cuerpo=None, cab=None):
    data = json.dumps(cuerpo).encode() if cuerpo is not None else None
    req = urllib.request.Request(url, data=data, method=metodo, headers=dict({"Content-Type": "application/json"}, **(cab or {})))
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            t = r.read().decode()
            try:   # las funciones de Supabase devuelven valores sueltos (true, "asistente"): también son JSON
                dato = json.loads(t) if t else t
            except ValueError:
                dato = t
            return r.status, dato, dict(r.headers)
    except urllib.error.HTTPError as e:
        t = e.read().decode(errors="replace")
        try:
            return e.code, json.loads(t), dict(e.headers)
        except ValueError:
            return e.code, t[:200], dict(e.headers)


def main():
    apagado = "--apagado" in sys.argv
    correo, clave = env()
    ak = anon()
    st, js, _ = pedir("POST", SUPA + "/auth/v1/token?grant_type=password", {"email": correo, "password": clave}, {"apikey": ak})
    del clave
    if st != 200 or not isinstance(js, dict) or not js.get("access_token"):
        sys.exit("No pude entrar con la cuenta de Instinct (HTTP %s). Revisá instinct.env." % st)
    tok = js["access_token"]
    sb = {"apikey": ak, "Authorization": "Bearer " + tok}
    filas, fallas = [], 0

    def ver(nombre, esperado, obtenido, ok):
        nonlocal fallas
        fallas += (not ok)
        filas.append(("✓" if ok else "✗", nombre, str(esperado), str(obtenido)))

    def contar(tabla):
        st, js, hd = pedir("GET", SUPA + "/rest/v1/%s?select=*&limit=1" % tabla, cab=dict(sb, Prefer="count=exact"))
        if st not in (200, 206):
            return "HTTP %s %s" % (st, (js or {}).get("code") if isinstance(js, dict) else "")
        rng = hd.get("Content-Range") or hd.get("content-range") or "*/?"
        return int(rng.split("/")[-1]) if rng.split("/")[-1].isdigit() else rng

    def rpc(fn):
        st, js, _ = pedir("POST", SUPA + "/rest/v1/rpc/" + fn, {}, sb)
        return js if st == 200 else "HTTP %s" % st

    ver("entra con su cuenta (Supabase Auth)", "sí", "sí", True)
    a = rpc("acceso_es_asistente")
    ver("acceso_es_asistente()", True, a, a is True)
    b = rpc("asistente_bloqueado")
    ver("asistente_bloqueado() (¿el proxy lo frena?)", apagado, b, b is apagado)
    n = contar("ent_pedido")
    ver("lee pedidos", "0" if apagado else "> 0", n, (n == 0) if apagado else (isinstance(n, int) and n > 0))
    n = contar("compra_tarifa_odoo")
    ver("lee tarifas de compra", "0" if apagado else "> 0", n, (n == 0) if apagado else (isinstance(n, int) and n > 0))
    for t in ("rrhh_persona", "rrhh_salario"):
        n = contar(t)
        ver("NO ve Personal (%s)" % t, "0 o sin permiso", n, n == 0 or (isinstance(n, str) and ("42501" in n or "HTTP 401" in n or "HTTP 403" in n)))
    st2, js2, _ = pedir("POST", SUPA + "/rest/v1/rpc/acceso_perfil", {}, sb)
    ver("acceso_perfil()", "asistente", js2 if st2 == 200 else st2, js2 == "asistente")
    st, js, _ = pedir("POST", SUPA + "/rest/v1/ent_pedido", {}, dict(sb, Prefer="return=minimal"))
    cod = js.get("code") if isinstance(js, dict) else None
    ver("NO inserta pedidos (fila vacía a propósito)", "42501", "%s %s" % (st, cod), cod == "42501")
    st, js, _ = pedir("POST", PROXY + "/", {"model": "res.partner", "method": "search_count", "args": [[["supplier_rank", ">", 0]]]},
                      {"Authorization": "Bearer " + tok})
    if apagado:
        ver("proxy de lectura (Odoo)", "403 asistente apagado", "%s %s" % (st, js.get("error") if isinstance(js, dict) else js), st == 403)
    else:
        ver("proxy de lectura (Odoo): cuenta proveedores", "200 + número", "%s %s" % (st, js.get("result") if isinstance(js, dict) else js),
            st == 200 and isinstance(js, dict) and isinstance(js.get("result"), int))
    st, js, _ = pedir("GET", ESCRITURA + "/quien", cab={"Authorization": "Bearer " + tok})
    ver("servicio de escritura /quien (no es socia)", "403 sin_rol", "%s %s" % (st, (js or {}).get("motivo") if isinstance(js, dict) else ""),
        st == 403 and isinstance(js, dict) and js.get("motivo") == "sin_rol")
    st, js, _ = pedir("POST", ESCRITURA + "/insumo", {"propuesta_id": 1}, {"Authorization": "Bearer " + tok})
    ver("servicio de escritura /insumo", "403 sin_rol", "%s %s" % (st, (js or {}).get("motivo") if isinstance(js, dict) else ""),
        st == 403 and isinstance(js, dict) and js.get("motivo") == "sin_rol")

    print("\nInstinct · %s · %d pruebas\n" % ("APAGADO" if apagado else "ENCENDIDO", len(filas)))
    print("| | prueba | esperado | obtenido |\n|---|---|---|---|")
    for f in filas:
        print("| %s | %s | %s | %s |" % f)
    print("\n%s" % ("TODO COMO SE ESPERABA" if not fallas else "%d FALLAS" % fallas))
    sys.exit(1 if fallas else 0)


if __name__ == "__main__":
    main()
