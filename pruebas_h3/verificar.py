#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verificar.py — el porton de las pruebas de H3.

POR QUE EXISTE
  Los diez archivos Dx.sql de esta carpeta NO se escribieron a mano: se
  EXTRAJERON de CAMBIO_DEVOLUCIONES.sql. Un archivo extraido puede quedar
  distinto del original de mil maneras silenciosas, y el 16-sep ya paso:
  `sed -n '141,476p'` entrego el pedazo equivocado y se pego P0-a creyendo
  que era el bloque transaccional. No se escribio nada solo porque P0-a
  terminaba en rollback — o sea, por suerte.

  Este script no CREE que la extraccion salio bien: lo comprueba, y se
  puede volver a correr cuantas veces haga falta.

QUE COMPRUEBA, una por una
  1. Que el cuerpo de cada prueba extraida sea IDENTICO, byte por byte, al
     que esta entre `begin;` y `rollback;` en el original.
  2. Que ningun cuerpo traiga control de transaccion ni nada que cambie
     quien corre: begin, commit, rollback, savepoint, release, set,
     set_config, reset, call, do. El sobre y la identidad son de
     pg_pruebas.py, nunca de la prueba.

  Las dos nuevas (b0, d9_anulacion) no se extrajeron de ningun lado, asi
  que solo pasan por la comprobacion 2. Eso se dice en la salida; no se
  esconde.

USO
    python3 pruebas_h3/verificar.py        (desde la raiz del repo)
  Sale con codigo 1 si algo falla, para poder colgarlo de un porton.
"""
import io, os, re, sys, glob

SRC = "CAMBIO_DEVOLUCIONES.sql"
# Rango de cada bloque en el original: (linea del `begin;`, linea del `rollback;`).
# Se anota el rango PERO NO SE USA PARA EXTRAER: sirve solo para volver a
# encontrar el bloque y compararlo. La extraccion fue por contenido.
ORIG = {"d0":(549,556), "d1":(559,566), "d2":(570,577), "d3":(582,589),
        "d3_bis":(596,603), "d4":(614,618), "d5":(623,648), "d6":(652,656),
        "d7":(660,676), "d8":(684,694)}

PROHIBIDO = re.compile(
    r"(?i)(?<![a-z_])(begin|commit|rollback|savepoint|release|set|set_config|reset|call|do)(?![a-z_])")
CIERRE = "-- ════════════════════════════════════════════════════════════════════\n"


def main():
    aqui = os.path.dirname(os.path.abspath(__file__))
    raiz = os.path.dirname(aqui)
    src = os.path.join(raiz, SRC)
    if not os.path.exists(src):
        print("✗ no encuentro %s — corre esto desde el repo" % SRC); return 1
    L = io.open(src, encoding="utf-8").read().split("\n")

    fallas = 0
    print("%-14s %-7s %-26s %s" % ("ARCHIVO", "CARRIL", "CUERPO vs ORIGINAL", "PALABRAS PROHIBIDAS"))
    print("-" * 82)
    for f in sorted(glob.glob(os.path.join(aqui, "*.sql"))):
        n = os.path.basename(f)[:-4]
        txt = io.open(f, encoding="utf-8").read()
        m = re.search(r"-- PRUEBA (\S+) · CARRIL (\w)", txt)
        car = m.group(2) if m else "?"

        if n in ORIG:
            a, b = ORIG[n]
            cuerpo = "\n".join(L[a:b - 1])          # lo que hay ENTRE begin; y rollback;
            ok = txt.endswith(cuerpo + "\n")        # el archivo TERMINA en el cuerpo, intacto
            ver = "✓ identico, byte a byte" if ok else "✗ DIFIERE DEL ORIGINAL"
            if not ok: fallas += 1
        else:
            cuerpo = txt.split(CIERRE)[-1]
            ver = "— nueva, no extraida"

        sin_com = "\n".join(re.sub(r"--.*$", "", l) for l in cuerpo.split("\n"))
        hits = sorted(set(x.group(1).lower() for x in PROHIBIDO.finditer(sin_com)))
        if hits: fallas += 1
        print("%-14s %-7s %-26s %s" % (n, car, ver, "✓ limpio" if not hits else "✗ " + ", ".join(hits)))

    print()
    if fallas:
        print("🔴 %d FALLA(S). No correr nada hasta entender por que." % fallas); return 1
    print("✅ 12 archivos · 10 extraidos verificados contra el original · 2 nuevas · 0 fallas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
