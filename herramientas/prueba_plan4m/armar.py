#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Arma el .js de la prueba del plan a 4 meses: RECORTA las funciones reales de un
index.html (no las reescribe) y les pone delante el andamio minimo (sbClient,
console). Mismo patron que prueba_unidades/armar.py. Sin datos de produccion:
los casos son sinteticos y viven en casos.js, para poder commitearlos."""
import io, re, sys, json

SRC, SALIDA = sys.argv[1], sys.argv[2]
s = io.open(SRC, encoding="utf-8").read()

def bloque(nombre):
    """Desde `function NAME(` hasta su llave de cierre, contando llaves (respeta strings y
    comentarios //). Asi tambien sale entera una funcion de UNA linea."""
    m = re.compile(r"^(?:async\s+)?function\s+%s\s*\(" % re.escape(nombre), re.M).search(s)
    if not m: return None
    j = s.find("{", s.find(")", m.start())); prof = 0; q = None
    while j < len(s):
        ch = s[j]
        if q:
            if ch == "\\": j += 2; continue
            if ch == q: q = None
        elif ch in "'\"`": q = ch
        elif ch == "/" and s[j+1] == "/": j = s.find("\n", j); continue
        elif ch == "{": prof += 1
        elif ch == "}":
            prof -= 1
            if prof == 0: return s[m.start():j+1] + "\n"
        j += 1
    return None

def constante(nombre):
    m = re.compile(r"^(?:const|let|var)\s+%s\s*=" % re.escape(nombre), re.M).search(s)
    if not m: return None
    i = m.start(); prof = 0; j = i; q = None
    while j < len(s):
        ch = s[j]
        if q:
            if ch == "\\": j += 2; continue
            if ch == q: q = None
        elif ch in "'\"`": q = ch
        elif ch in "{[(": prof += 1
        elif ch in "}])": prof -= 1
        elif ch == ";" and prof == 0: return s[i:j+1]
        j += 1
    return None

CONSTS = ["NIV_PROD","NIV_INFO","NIV_CFG_DEF","_rzN","NIV_CAP","_rzPersonas","FERIADOS","CIERRE_RESPALDO",
          "CIERRE","CIERRE_BORDES_PRODUCEN","_calFer","_calFuente","_calHasta","_calFinAnioOk","CIERRE_ANIO_MIN_DIAS","_ritmoAviso","_calFerObl","_planTemp","_tempCache",
          "NIV_HORNO","NIV_DERRAME_MIN","RAMPA_DIAS_SEM","_rzCierreMeta","RAMPA_PERS_BASE",
          "_DOW","_MESAB","_planCierre","_MESNOM2","_rzPicIdx"]
FUNCS  = ["_capDe","_personasDe","_esFeriado","_cierreCubre","_enCierre","_enCierreAnio","_sinVenta","_calCoberturaAviso","_ritmoVentana","_ritmoBloque","_calDesdeFilas","_calAplicar","_calRespaldo","nivCalendario",
          "_esProductivo","_diaSig","_isoWk","_ymd","_cierreShift","_mondayProd","_nomCorto","_rzBP",
          "_monKey","_planFinHorizonte","_planNSem","_semAbiertos","_semCierreMs","_bajoMetaCierre","_temporadaSem",
          "_planSalidaCierre","_planSem","_planRestarSalida","_layoutCerrado","_habilesMes","_temporadaCalc",
          "_rampaDe","_rampaDeudaUds","_rampaEstado","_weekLayout","_semanaBatches","nivLevel","nivProyeccion",
          "_weekDays","_ovItems","_mismosBatches","rzCeldas","_rzVolverRango","_esBloqueAnio","_calFinAnioAviso","_semCierreSuelto","_planProdCeldas","cierreCargarMeta","_aplicarPicado","planProyeccionOv","_nivStockDecision","_fechaCierreTxt","_planTagsMes"]
piezas, faltan = [], []
for c in CONSTS:
    t = constante(c)
    (piezas.append("/* real: %s */\n%s" % (c, t)) if t else faltan.append("const "+c))
for f in FUNCS:
    t = bloque(f)
    (piezas.append("/* real: %s */\n%s" % (f, t)) if t else faltan.append("function "+f))
cab = """// == PRUEBA DEL PLAN A 4 MESES · generada por armar.py, no escrita a mano ==
// Funciones RECORTADAS de %s, tal cual.
var FALTAN = %s;
// Andamio (lo que pone el navegador). Ninguno esta bajo prueba.
var console = {log:function(){}, warn:function(){}};
var _SB = null; function sbClient(){ return _SB; }
// Estado del Plan que en index.html se declara en una sola linea con otros (no se recorta suelto).
var _planReal = {}, _planInputs = null, _rzOverrides = {};
""" % (SRC, json.dumps(faltan))
io.open(SALIDA, "w", encoding="utf-8").write(cab + "\n\n".join(piezas) + "\n")
print("armado %s · %d piezas · faltan: %s" % (SALIDA, len(piezas), faltan or "ninguna"))
