#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
turno.py — el turno para cerrar (protocolo de cierre, decisión de Andrea 21-oct-2026).

Antes de /listo o de /cierre-dia, la sesión toma una MARCA local con su origen y la hora.
Si ya hay otra marca, espera y avisa. Si la marca tiene más de 30 minutos, la da por
abandonada, la quita y avisa. La marca NO va a git: vive en `Practica CC/.turno_cierre.json`.

Por qué (20-oct): seis sesiones en paralelo cerraron a la vez, con cuatro ESTADOS el mismo
día y un choque de BUILD b114/b115.

    python3 turno.py tomar  --origen "Retomar 21-oct" [--que listo|cierre-dia]
    python3 turno.py soltar --origen "Retomar 21-oct"
    python3 turno.py ver
Salida: 0 = turno tomado / soltado · 3 = OCUPADO por otra sesión (esperar) · 2 = error de uso.
`--archivo` cambia dónde vive la marca (los ensayos usan una propia).
"""
import json, os, sys, time

PRACTICA = "/Users/andrea/Desktop/Practica CC"
ARCHIVO = os.path.join(PRACTICA, ".turno_cierre.json")
VENCE_MIN = 30


def _arg(nombre, defecto=None):
    return sys.argv[sys.argv.index(nombre) + 1] if nombre in sys.argv else defecto


def _hora(t):
    return time.strftime("%d-%m %H:%M", time.localtime(t))


def leer(archivo):
    try:
        return json.load(open(archivo, encoding="utf-8"))
    except (OSError, ValueError):
        return None


def tomar(archivo, origen, que, ahora=None):
    ahora = ahora or time.time()
    marca = {"origen": origen, "que": que, "desde": ahora, "pid": os.getppid()}
    for _ in range(2):
        try:
            fd = os.open(archivo, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)   # atómico: gana uno solo
        except FileExistsError:
            m = leer(archivo) or {}
            edad = (ahora - float(m.get("desde") or 0)) / 60
            if m.get("origen") == origen:
                print("✓ el turno ya era tuyo (desde %s)." % _hora(m["desde"])); return 0
            if edad > VENCE_MIN:
                os.remove(archivo)
                print("⚠ había una marca de «%s» (%s) desde %s, hace %d min: más de %d → la doy por ABANDONADA y la quito."
                      % (m.get("origen", "?"), m.get("que", "?"), _hora(m.get("desde") or 0), edad, VENCE_MIN))
                continue
            print("⏳ OCUPADO: «%s» está cerrando (%s) desde %s, hace %d min. Esperá a que termine y volvé a pedir el turno."
                  % (m.get("origen", "?"), m.get("que", "?"), _hora(m.get("desde") or 0), edad))
            return 3
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(marca, f, ensure_ascii=False)
        print("✓ turno tomado por «%s» (%s) a las %s." % (origen, que, _hora(ahora)))
        return 0
    return 3


def soltar(archivo, origen):
    m = leer(archivo)
    if not m:
        print("· no había marca."); return 0
    if m.get("origen") != origen and "--forzar" not in sys.argv:
        print("✗ la marca es de «%s», no de «%s»: no la quito (--forzar si de verdad corresponde)." % (m.get("origen"), origen))
        return 2
    os.remove(archivo)
    print("✓ turno soltado (era de «%s»)." % m.get("origen")); return 0


def ver(archivo):
    m = leer(archivo)
    if not m:
        print("· sin marca: el turno está libre."); return 0
    edad = (time.time() - float(m.get("desde") or 0)) / 60
    print("%s «%s» (%s) desde %s, hace %d min%s." % ("⚠" if edad > VENCE_MIN else "·", m.get("origen"), m.get("que"),
          _hora(m.get("desde") or 0), edad, " → COLGADA (más de %d min)" % VENCE_MIN if edad > VENCE_MIN else ""))
    return 0


if __name__ == "__main__":
    archivo = _arg("--archivo", ARCHIVO)
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "tomar" and _arg("--origen"):
        sys.exit(tomar(archivo, _arg("--origen"), _arg("--que", "listo")))
    if cmd == "soltar" and _arg("--origen"):
        sys.exit(soltar(archivo, _arg("--origen")))
    if cmd == "ver":
        sys.exit(ver(archivo))
    print(__doc__); sys.exit(2)
