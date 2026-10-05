# Chequeo de CARGA (no solo de sintaxis): ejecuta el script de nivel superior con un DOM
# de mentira y reporta el PRIMER error de ejecución. Caza cosas que `new Function` no ve,
# como usar un const antes de declararlo (TDZ) — el bug del 11-ago.
import re, subprocess, os, sys
JSC='/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc'
# El archivo temporal NO se escribe en el repo: la primera versión lo dejaba al lado de
# loadcheck.py y `git add -A` se lo llevó a un repo PÚBLICO (11-ago). Va a un temporal.
import tempfile
SP=tempfile.mkdtemp(prefix='tf_loadcheck_')
s=open('index.html',encoding='utf-8').read()
body=max(re.findall(r'<script(?![^>]*src=)[^>]*>(.*?)</script>', s, re.S), key=len)   # el bloque grande; el del <head> es el arranque del tema
stub = r'''
var _noop=function(){return _el();};
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
open(SP+'/_load.js','w',encoding='utf-8').write(stub+body)
r=subprocess.run([JSC,SP+'/_load.js'],capture_output=True,text=True)
out=(r.stdout+r.stderr).strip()
# También los SyntaxError de EJECUCIÓN (los de parseo no llegan acá): una
# redeclaración `let` mata el bloque entero igual que un TDZ, y sin esta línea
# el chequeo imprimía ✓ con el script muerto — pasó el 25-ago con `_el`.
tdz=[l for l in out.splitlines()
     if 'before initialization' in l or 'ReferenceError' in l or 'SyntaxError' in l]
if tdz:
    print('✗ ERROR DE CARGA:'); [print('   '+l) for l in tdz[:6]]; sys.exit(1)
print('✓ el script corre de arriba a abajo sin errores de carga')
if out: print('  (ruido esperado del DOM falso, no bloquea):', out.splitlines()[0][:110])

# ── CERCA: LA CAJA SE NOMBRA EN UNIDAD DE VENTA (30-sep-2026) ─────────────
# Francés y Buns: "caja de 6 paq · paq de 4 u"; Pizza: "caja de 6 paq · paq de 2 u".
# Nunca "caja de 24" ni "caja de 12 u": es el error que Andrea vio en b76 y que ya
# estaba escrito a mano en más de un lugar. Dos capas:
#  1. ESTÁTICA: ningún texto del código (fuera de comentarios) lo dice.
#  2. EN EJECUCIÓN: los rótulos que arma la app para 453/503/472 no lo dicen.
MAL = re.compile(r'caja de (24|12 ?u\b|12 ?uds)', re.I)
def _sin_comentarios(js):
    js = re.sub(r'/\*.*?\*/', '', js, flags=re.S)
    return '\n'.join(re.sub(r'(^|[^:\\\'"])//.*$', r'\1', l) for l in js.splitlines())
malos = [l.strip()[:110] for l in _sin_comentarios(body).splitlines() if MAL.search(l)]
if malos:
    print('✗ CAJA EN UNIDADES SUELTAS escrita en el código:'); [print('   '+l) for l in malos[:6]]; sys.exit(1)
open(SP+'/_rotulos.js','w',encoding='utf-8').write(r'''
var _r=[453,503,472].map(function(p){ return [p,_presRotulo(p),_cajaRotulo(p),_cajaNombreUom(p),
  _cnPresTerm(INV_TERM.find(function(t){return t.id===p;}))]; });
print('ROTULOS '+JSON.stringify(_r));
''')
r2=subprocess.run([JSC,SP+'/_load.js',SP+'/_rotulos.js'],capture_output=True,text=True)
lin=[l for l in (r2.stdout+r2.stderr).splitlines() if l.startswith('ROTULOS ')]
if not lin:
    print('✗ la cerca de rótulos no pudo correr (¿cambió el nombre de _presRotulo/_cajaRotulo?)'); sys.exit(1)
import json
rot=json.loads(lin[0][8:])
peor=[x for x in rot if any(MAL.search(str(v)) for v in x[1:])]
if peor or any(not str(x[1]).startswith('caja de 6 paq') for x in rot):
    print('✗ ROTULO DE CAJA MAL para un producto en paquete:', peor or rot); sys.exit(1)
print('✓ rótulo de caja en unidad de venta:', ' | '.join('%d %s' % (x[0], x[1]) for x in rot))
