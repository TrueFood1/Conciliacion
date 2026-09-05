#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
probar_conexion.py — probar la cadena de conexion de Supabase desde la Mac.

COMO SE USA
    python3 probar_conexion.py
  Pide la cadena con la escritura OCULTA. No va como argumento (no aparece
  en `ps`), no se escribe en disco, y no queda en el historial del shell:
  lo unico que queda en el historial es el nombre del script.

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
import getpass
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
    cru = socket.create_connection((host, puerto), timeout=25)
    # pedir TLS
    cru.sendall(struct.pack("!II", 8, 80877103))
    if leer_exacto(cru, 1) != b"S":
        return "el servidor rechazo TLS"
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
            return "%s %s: %s" % (sev, cod, msg)
        if tipo != b"R":
            continue
        codigo = struct.unpack("!I", cuerpo[:4])[0]
        if codigo == 0:
            s.sendall(paquete(b"X", b""))
            return None                      # autenticado
        if codigo == 3:                      # contrasena en claro
            s.sendall(paquete(b"p", password.encode() + b"\x00"))
        elif codigo == 10:                   # SASL
            mecs = [m.decode() for m in cuerpo[4:].split(b"\x00") if m]
            if "SCRAM-SHA-256" not in mecs:
                return "el servidor no ofrece SCRAM-SHA-256, ofrece: " + ", ".join(mecs)
            nonce = base64.b64encode(os.urandom(18)).decode()
            primer_cliente = "n=,r=" + nonce
            ini = b"SCRAM-SHA-256\x00" + struct.pack("!I", len(primer_cliente) + 3) + b"n,," + primer_cliente.encode()
            s.sendall(paquete(b"p", ini))
            tipo, cuerpo = leer_mensaje(s)
            if tipo == b"E":
                sev, cod, msg = error_legible(cuerpo)
                return "%s %s: %s" % (sev, cod, msg)
            primer_servidor = cuerpo[4:].decode()
            d = dict(p.split("=", 1) for p in primer_servidor.split(","))
            final_sin_proof = "c=biws,r=" + d["r"]
            proof = prueba_scram(password, base64.b64decode(d["s"]), int(d["i"]),
                                 primer_cliente, primer_servidor, final_sin_proof)
            s.sendall(paquete(b"p", (final_sin_proof + ",p=" + proof).encode()))
        elif codigo in (11, 12):
            continue
        else:
            return "el servidor pide un metodo de autenticacion que este script no cubre (codigo %d)" % codigo


def main():
    print(__doc__.split("COMO SE USA")[0].strip())
    print("\nPega la cadena de conexion. NO se va a ver mientras escribis.")
    print("(Ctrl-C para salir)\n")
    try:
        cadena = getpass.getpass("cadena: ").strip()
    except KeyboardInterrupt:
        print("\ncancelado"); return
    if not cadena:
        print("no pegaste nada"); return

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

    u = urllib.parse.urlparse(cadena)
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
