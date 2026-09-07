#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pg_lector.py — consultar la base de Truefie (Supabase) en SOLO LECTURA.

POR QUE EXISTE
  En la Mac no hay psql, ni pg_dump, ni brew, ni gh. Lo unico que hay es el
  python3 del sistema. Este lector habla el protocolo de Postgres directo, con
  stdlib nada mas, reusando el SCRAM-SHA-256 que ya estaba probado en
  respaldo/probar_conexion.py. No instala nada.

  Entra como `postgres` por el pooler, o sea SUPERUSUARIO: ve por encima del
  RLS. Eso es justamente lo que hace falta para auditar (la anon key devuelve
  cero filas y eso no prueba nada), y es exactamente lo que lo hace peligroso.
  De ahi los dos candados.

LOS DOS CANDADOS (defensa en profundidad, igual que odoo_read.py)
  1. Allowlist deny-by-default en Python: la consulta tiene que empezar con
     SELECT o WITH. Todo lo demas se rechaza antes de salir de la Mac.
  2. Candado del lado del SERVIDOR: cada consulta viaja envuelta en
     BEGIN TRANSACTION READ ONLY / COMMIT. Aunque el candado 1 se pase por
     alto, Postgres niega toda escritura. Este es el que manda; el 1 es red.

  El candado 1 solo es una lista de Python — la leccion del 2-sep-2026 con
  Odoo, donde lo unico que impedia escribir en produccion era una lista
  citada. Por eso existe el 2.

LA CONTRASENA
  Nunca en disco, nunca como argumento (no sale en `ps`), nunca en el
  historial del shell, nunca impresa. Entra por el portapapeles o por stdin,
  vive en memoria y se va con el proceso.

COMO SE USA
    python3 pg_lector.py --clave "select 1"
        Toma la contrasena del portapapeles (copiala del gestor primero).

    python3 pg_lector.py --clave --archivo consultas.sql
        Varias consultas separadas por ';' en un archivo, una sola conexion.

    Como modulo, que es para lo que se escribio:
        from pg_lector import Lector
        with Lector(clave_del_portapapeles()) as db:
            filas = db.consulta("select ...")
"""

import os
import re
import struct
import sys

_AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_AQUI, "respaldo"))
from probar_conexion import (          # noqa: E402
    abrir, paquete, leer_mensaje, error_legible,
    del_portapapeles, armar_cadena, HOST, PUERTO, USUARIO, BASE,
)

# Candado 1. Deny-by-default: si no empieza con esto, no sale de la Mac.
LECTURA_OK = ("select", "with", "table", "values", "explain", "show")


def clave_del_portapapeles():
    """La contrasena, tal como quedo en el portapapeles. No se imprime."""
    return del_portapapeles().strip("\r\n").strip()


def _sin_comentarios(sql):
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    sql = re.sub(r"--[^\n]*", " ", sql)
    return sql.strip()


def revisar(sql):
    """Candado 1. Devuelve None si pasa, o el motivo del rechazo."""
    limpio = _sin_comentarios(sql)
    if not limpio:
        return "la consulta esta vacia"
    primera = limpio.split(None, 1)[0].lower().lstrip("(")
    if primera not in LECTURA_OK:
        return ("empieza con %r y solo se permiten %s"
                % (primera, "/".join(LECTURA_OK).upper()))
    # ';' intermedio = varias sentencias encadenadas; solo se tolera al final.
    if ";" in limpio.rstrip().rstrip(";"):
        return "trae mas de una sentencia (';' en el medio)"
    return None


class Lector:
    """Una conexion abierta. Se usa con `with`, para que siempre se cierre."""

    def __init__(self, clave, host=HOST, puerto=PUERTO, usuario=USUARIO, base=BASE):
        self.s, fallo = abrir(host, puerto, usuario, base, clave)
        if fallo:
            raise ConnectionError(fallo)
        self._hasta_listo()          # drenar hasta el primer ReadyForQuery

    # ── protocolo ────────────────────────────────────────────────────────
    def _hasta_listo(self):
        while True:
            tipo, cuerpo = leer_mensaje(self.s)
            if tipo == b"Z":
                return
            if tipo == b"E":
                sev, cod, msg = error_legible(cuerpo)
                raise RuntimeError("%s %s: %s" % (sev, cod, msg))

    def _crudo(self, sql):
        """Manda un Query y junta los resultados hasta ReadyForQuery."""
        self.s.sendall(paquete(b"Q", sql.encode("utf-8") + b"\x00"))
        resultados, cols, filas, error = [], None, [], None
        while True:
            tipo, cuerpo = leer_mensaje(self.s)
            if tipo == b"T":                                  # RowDescription
                n = struct.unpack("!H", cuerpo[:2])[0]
                cols, pos = [], 2
                for _ in range(n):
                    fin = cuerpo.index(b"\x00", pos)
                    cols.append(cuerpo[pos:fin].decode("utf-8", "replace"))
                    pos = fin + 1 + 18
                filas = []
            elif tipo == b"D":                                # DataRow
                n = struct.unpack("!H", cuerpo[:2])[0]
                fila, pos = [], 2
                for _ in range(n):
                    largo = struct.unpack("!i", cuerpo[pos:pos + 4])[0]
                    pos += 4
                    if largo == -1:
                        fila.append(None)
                    else:
                        fila.append(cuerpo[pos:pos + largo].decode("utf-8", "replace"))
                        pos += largo
                filas.append(fila)
            elif tipo == b"C":                                # CommandComplete
                if cols is not None:
                    resultados.append((cols, filas))
                cols, filas = None, []
            elif tipo == b"E":
                sev, cod, msg = error_legible(cuerpo)
                error = "%s %s: %s" % (sev, cod, msg)
            elif tipo == b"Z":
                break
        if error:
            raise RuntimeError(error)
        return resultados

    # ── lo que se usa desde afuera ───────────────────────────────────────
    def consulta(self, sql):
        """Corre UNA consulta de lectura. Devuelve (columnas, filas)."""
        motivo = revisar(sql)
        if motivo:
            raise PermissionError("🔒 SOLO LECTURA — rechazada: %s" % motivo)
        # Candado 2: el servidor mismo niega cualquier escritura acá adentro.
        envuelta = "begin transaction read only;\n%s;\ncommit;" % sql.rstrip().rstrip(";")
        resultados = self._crudo(envuelta)
        if not resultados:
            return [], []
        return resultados[-1]

    def valor(self, sql):
        """El primer campo de la primera fila, o None."""
        _, filas = self.consulta(sql)
        return filas[0][0] if filas and filas[0] else None

    def cerrar(self):
        try:
            self.s.sendall(paquete(b"X", b""))
            self.s.close()
        except Exception:
            pass

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.cerrar()


# ── impresion legible ────────────────────────────────────────────────────
def tabla(cols, filas, max_ancho=42):
    if not cols:
        return "(sin resultados)"
    if not filas:
        return "  (0 filas)"
    def corto(v):
        t = "" if v is None else str(v)
        return t if len(t) <= max_ancho else t[:max_ancho - 1] + "…"
    anchos = [len(c) for c in cols]
    for f in filas:
        for i, v in enumerate(f):
            anchos[i] = max(anchos[i], len(corto(v)))
    out = ["  " + " | ".join(c.ljust(anchos[i]) for i, c in enumerate(cols)),
           "  " + "-+-".join("-" * a for a in anchos)]
    for f in filas:
        out.append("  " + " | ".join(corto(v).ljust(anchos[i]) for i, v in enumerate(f)))
    out.append("  (%d fila%s)" % (len(filas), "" if len(filas) == 1 else "s"))
    return "\n".join(out)


def main():
    args = sys.argv[1:]
    if "--clave" not in args:
        print(__doc__.strip()); return
    resto = [a for a in args if a != "--clave"]
    if "--archivo" in resto:
        i = resto.index("--archivo")
        sqls = [q for q in open(resto[i + 1], encoding="utf-8").read().split(";") if q.strip()]
    elif resto:
        sqls = [" ".join(resto)]
    else:
        print("falta la consulta (o --archivo)"); return

    clave = clave_del_portapapeles()
    if not clave:
        print("el portapapeles esta vacio: copia la contrasena y volve a correr"); return
    print("clave leida del portapapeles: %d caracteres (no se imprime)" % len(clave))
    try:
        with Lector(clave) as db:
            print("✅ conectado como %s\n" % USUARIO)
            for sql in sqls:
                print("── %s" % " ".join(sql.split())[:90])
                cols, filas = db.consulta(sql)
                print(tabla(cols, filas)); print()
    except ConnectionError as e:
        print("❌ no conecto: %s" % e)
    except PermissionError as e:
        print("%s" % e)


if __name__ == "__main__":
    main()
