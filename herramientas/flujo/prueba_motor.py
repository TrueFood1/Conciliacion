#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
prueba_motor.py — corre el motor del flujo de caja (index.html) bajo jsc, sin navegador.

  python3 herramientas/flujo/prueba_motor.py                 casos sintéticos (casos_motor.js)
  python3 herramientas/flujo/prueba_motor.py OTRO.js [...]   además, otros archivos (p. ej. una
                                                             reproducción con datos privados que
                                                             vive FUERA del repo)

El motor se saca de index.html por sus marcas (« FLUJO DE CAJA · MOTOR » … « FIN FLUJO DE CAJA »),
no por número de línea. Si las marcas no están exactamente una vez, no corre.
El archivo armado va a un temporal, nunca al repo (la lección de loadcheck del 11-ago).
Sale con error si algún caso dice FALLA.
"""
import os, re, subprocess, sys, tempfile
JSC = '/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc'
AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(os.path.dirname(AQUI))
html = open(os.path.join(RAIZ, 'index.html'), encoding='utf-8').read()
ini = [m.start() for m in re.finditer(r'// ══ FLUJO DE CAJA · MOTOR', html)]
fin = [m.end() for m in re.finditer(r'// ══ FIN FLUJO DE CAJA · MOTOR[^\n]*\n', html)]
if len(ini) != 1 or len(fin) != 1 or fin[0] < ini[0]:
    sys.exit('marcas del motor: %d de inicio y %d de fin (tiene que haber una de cada)' % (len(ini), len(fin)))
motor = html[ini[0]:fin[0]]
# Lo que el motor usa de afuera solo en flujoLeerCartera (async, no se llama en las pruebas).
stub = "var _cobData={cobrar:null,pagar:null}; function cobLoad(){ throw new Error('sin Odoo en la prueba'); }\n"
archivos = [os.path.join(AQUI, 'casos_motor.js')] + sys.argv[1:]
sp = tempfile.mkdtemp(prefix='tf_flujo_')
falla = False
for a in archivos:
    js = stub + motor + '\n' + open(a, encoding='utf-8').read()
    p = os.path.join(sp, 'prueba.js'); open(p, 'w', encoding='utf-8').write(js)
    r = subprocess.run([JSC, p], capture_output=True, text=True)
    out = (r.stdout + r.stderr).strip()
    print('── %s' % os.path.basename(a)); print(out)
    if r.returncode != 0 or 'FALLA' in out or 'Exception' in out or 'Error' in out.split('\n')[-1]:
        falla = True
sys.exit(1 if falla else 0)
