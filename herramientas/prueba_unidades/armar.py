#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Arma el .js de la prueba: saca las funciones REALES de un index.html (las
recorta del archivo, no las reescribe) y las junta con un PostgREST de mentira
alimentado con filas reales de produccion QUE RESPETA LA PROYECCION.

La leccion de b63: un fixture escrito a mano le da al guarda justo el campo que
la lectura real no trae. Aca, si el codigo no pide una columna en su .select(),
no la recibe -- igual que PostgREST."""
import io, re, sys, json, os

SRC   = sys.argv[1]                      # index.html a probar
SALIDA= sys.argv[2]
BASE  = os.path.dirname(os.path.abspath(__file__))
s = io.open(SRC, encoding="utf-8").read()

def bloque(nombre, tipo="function"):
    """Recorta desde `function NAME(` hasta la primera llave de cierre en columna 0."""
    pat = re.compile(r"^(?:async\s+)?%s\s+%s\s*\(" % (tipo, re.escape(nombre)), re.M)
    m = pat.search(s)
    if not m: return None
    fin = s.find("\n}\n", m.start())
    if fin < 0: return None
    return s[m.start():fin+3]

def constante(nombre):
    pat = re.compile(r"^(?:const|let|var)\s+%s\s*=" % re.escape(nombre), re.M)
    m = pat.search(s)
    if not m: return None
    # hasta el `;` que cierra en columna 0 o fin de linea equilibrada
    i = m.start(); prof = 0; j = i
    while j < len(s):
        ch = s[j]
        if ch in "{[(": prof += 1
        elif ch in "}])": prof -= 1
        elif ch == ";" and prof == 0: return s[i:j+1]
        j += 1
    return None

FUNCS = ["_uomCajaU","uomLineaMal","uomBarrerFacturas","_uomNombreDe","uomTextoAviso",
         "uomFactores","uomFac","_despFacCorta","esc"]
CONSTS= ["NIV_INFO","UOM_OK","ENT_PROD","_rzN","_uomFac"]

piezas, faltan = [], []
for c in CONSTS:
    t = constante(c)
    if t: piezas.append("/* const real: %s */\n%s" % (c, t))
    else: faltan.append("const "+c)
for f in FUNCS:
    t = bloque(f)
    if t: piezas.append("/* funcion real: %s */\n%s" % (f, t))
    else: faltan.append("function "+f)

datos = io.open(os.path.join(BASE,"datos.json"), encoding="utf-8").read()

cabecera = """// ══ PRUEBA DE LA DETECCION DE UNIDADES · generada, no escrita a mano ══
// Las funciones de abajo estan RECORTADAS de %s, tal cual.
// Los datos son filas REALES de produccion.
var DATOS = %s;
var FALTAN = %s;


// Lo que el navegador pone y aca no hay. NINGUNO esta bajo prueba: si alguno
// apareciera en una assertion, la prueba estaria midiendo el andamio.
""" % (os.path.relpath(SRC), datos, json.dumps(faltan))

io.open(SALIDA,"w",encoding="utf-8").write(cabecera+"\n\n"+"\n\n".join(piezas)+"\n")
print("armado %s · %d piezas · faltan: %s" % (os.path.basename(SALIDA), len(piezas), faltan or "ninguna"))
