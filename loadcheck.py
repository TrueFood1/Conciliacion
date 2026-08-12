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
body=re.findall(r'<script(?![^>]*src=)[^>]*>(.*?)</script>', s, re.S)[0]
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
tdz=[l for l in out.splitlines() if 'before initialization' in l or 'ReferenceError' in l]
if tdz:
    print('✗ ERROR DE CARGA:'); [print('   '+l) for l in tdz[:6]]; sys.exit(1)
print('✓ el script corre de arriba a abajo sin errores de carga')
if out: print('  (ruido esperado del DOM falso, no bloquea):', out.splitlines()[0][:110])
