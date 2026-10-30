#!/bin/bash
# Prueba de la calculadora de precios (b128): costo por receta (taza con gramos, insumo sin precio
# = incompleto, no ₡0), las tres casillas enlazadas (margen · factura · PVP), Automercado y Fresh
# Market frío, comisión Uber, la ventana con techo «Automercado + 5 %», el catálogo de Odoo por
# factor de UoM y las recetas guardadas (payload y versión siguiente).
# Corre el script ENTERO de index.html (como loadcheck.py) con un DOM de mentira y despues los
# casos. Casos sinteticos: no lee Odoo ni Supabase. El .js armado va a un temporal.
#   herramientas/prueba_calculadora/correr.sh
set -e
D="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$D/../.." && pwd)"
JSC=/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc
T="$(mktemp -d -t tf_calculadora)"
python3 - "$R/index.html" "$T/app.js" <<'PY'
import re, sys
s=open(sys.argv[1],encoding='utf-8').read()
body=max(re.findall(r'<script(?![^>]*src=)[^>]*>(.*?)</script>', s, re.S), key=len)
stub=r'''
var _RealDate = Date, _AHORA = new _RealDate(2026, 9, 25, 10, 0, 0).getTime();
Date = class extends _RealDate { constructor(...a){ if(a.length===0) super(_AHORA); else super(...a); } static now(){ return _AHORA; } };
function _el(){ return new Proxy(function(){}, {
  get:function(t,k){ if(k==='style'||k==='classList'||k==='dataset') return _el();
    if(k==='length') return 0; if(k==='textContent'||k==='innerHTML'||k==='value') return '';
    if(k===Symbol.toPrimitive||k==='toString') return function(){return '';};
    if(k==='forEach'||k==='map'||k==='filter') return function(){return [];};
    return _el(); },
  set:function(){return true;}, apply:function(){return _el();}, has:function(){return true;} });
}
var document=_el(), window=_el(), localStorage=_el(), navigator=_el(), location=_el();
var setTimeout=function(){}, setInterval=function(){}, matchMedia=function(){return {matches:false,addListener:function(){}};};
var fetch=function(){return {then:function(){return this;},catch:function(){return this;}};};
'''
open(sys.argv[2],'w',encoding='utf-8').write(stub+body)
PY
"$JSC" "$T/app.js" "$D/casos.js"
