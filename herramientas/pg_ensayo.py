#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pg_ensayo.py — corre UN ENSAYO contra la base de Truefie y lo deshace. Nada más (19-oct-2026).

POR QUE EXISTE
  Andrea pidió (19-oct) que CC corra él mismo los ensayos con ROLLBACK. pg_lector no sirve para eso a
  propósito: envuelve todo en `begin transaction read only` (su candado 2). Este script es la ÚNICA puerta
  de escritura de CC, y solo para ensayos: la escritura existe adentro de una transacción que siempre se
  deshace.

LOS CANDADOS (antes de mandar una sola letra)
  1. El archivo, sin comentarios ni cuerpos $$…$$, tiene que EMPEZAR con `begin;` y TERMINAR con
     `rollback;`, y no puede tener `commit`, `end;` suelto, `end transaction` ni `release`.
  2. Se manda el archivo y, pase lo que pase (error, corte, éxito), se manda otro `rollback;`.
  3. Después se pregunta `txid_current_if_assigned()`: tiene que dar vacío (no quedó transacción abierta).
  Lo que NO hace: pegar. Un PEGADO (con commit) lo pega Andrea en el editor, siempre.

    python3 herramientas/pg_ensayo.py ENSAYO_X.sql
"""
import re, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pg_lector import Lector, clave, tabla                       # noqa: E402


def limpio(sql):
    sql = re.sub(r"\$([A-Za-z_]*)\$.*?\$\1\$", " $$ ", sql, flags=re.S)       # cuerpos $$…$$ / $f$…$f$
    sql = re.sub(r"--[^\n]*", "", sql)
    sql = re.sub(r"'(?:[^']|'')*'", "''", sql)                                 # textos
    return sql


def revisar(sql):
    s = limpio(sql).strip().lower()
    if not s.startswith("begin;"):
        return "no empieza con begin;"
    if not s.endswith("rollback;"):
        return "no termina con rollback;"
    for prohibido in (r"\bcommit\b", r"\bend\s*;", r"\bend\s+transaction\b", r"\brelease\b", r"\bend\s+work\b"):
        if re.search(prohibido, s):
            return "tiene %s" % prohibido
    if s.count("rollback;") != 1:
        return "tiene más de un rollback (o un rollback en el medio)"
    return None


def main():
    ruta = sys.argv[1]
    sql = open(ruta, encoding="utf-8").read()
    motivo = revisar(sql)
    if motivo:
        sys.exit("🔒 NO ES UN ENSAYO (%s): no se manda nada." % motivo)
    c, origen = clave()
    with Lector(c) as db:
        try:
            res = db._crudo(sql)
            error = None
        except RuntimeError as e:
            res, error = [], str(e)
        finally:
            try:
                db._crudo("rollback;")
            except RuntimeError:
                pass
        abierta = db._crudo("select coalesce(txid_current_if_assigned()::text, 'ninguna')")[-1][1][0][0]
    print("ensayo: %s · transacción abierta después: %s" % (os.path.basename(ruta), abierta))
    if error:
        print("❌ el ensayo rebotó (y se deshizo): %s" % error)
        sys.exit(1)
    if res:
        cols, filas = res[-1]
        print(tabla(cols, filas, max_ancho=110))
        oks = [f[-1] for f in filas]
        if cols and cols[-1] == "ok":
            n = sum(1 for x in oks if x in ("t", "true"))
            print("\n%d de %d con ok = true" % (n, len(oks)))
            sys.exit(0 if n == len(oks) else 1)


if __name__ == "__main__":
    main()
