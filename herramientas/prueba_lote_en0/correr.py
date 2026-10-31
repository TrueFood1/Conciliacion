# Corre prueba.js sobre el index.html entero con jsc (el mismo DOM falso de loadcheck.py).
import re, subprocess, os, sys, tempfile
AQUI=os.path.dirname(os.path.abspath(__file__)); RAIZ=os.path.dirname(os.path.dirname(AQUI))
JSC='/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc'
src=open(os.path.join(RAIZ,'loadcheck.py'),encoding='utf-8').read()
stub=re.search(r"stub = r'''(.*?)'''", src, re.S).group(1)
s=open(os.path.join(RAIZ,'index.html'),encoding='utf-8').read()
body=max(re.findall(r'<script(?![^>]*src=)[^>]*>(.*?)</script>', s, re.S), key=len)
SP=tempfile.mkdtemp(prefix='tf_en0_'); open(SP+'/_load.js','w',encoding='utf-8').write(stub+body)
r=subprocess.run([JSC,SP+'/_load.js',os.path.join(AQUI,'prueba.js')],capture_output=True,text=True)
lin=[l for l in (r.stdout+r.stderr).splitlines() if l.startswith(('OK','MAL','RESULTADO'))]
print('\n'.join(lin)); sys.exit(0 if lin and lin[-1].startswith('RESULTADO') and not any(l.startswith('MAL') for l in lin) else 1)
