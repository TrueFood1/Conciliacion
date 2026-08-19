#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Chequeo de ESQUEMA: ¿existe en Supabase todo lo que el código consulta?

Por qué existe: el 17-ago se publicó a `main` código que dependía de
ENTREGAS_ETAPAS.sql sin pegar. Andrea lo descubrió el 18 registrando entregas
reales, con tres errores encadenados en producción. `loadcheck.py` no podía
cazarlo — corre el JS con un DOM falso y nunca toca la red — y el checklist de
cierre no mencionaba la palabra Supabase ni una vez.

Cómo funciona: saca los `from('tabla')` del index.html y pide 1 fila de cada uno
con la anon key (que es pública por diseño). No lee datos: solo distingue

    PGRST205  -> el objeto NO existe
    []        -> existe (vacío o filtrado por RLS; no importa cuál)

Uso:
    python3 esquema_check.py          # sale 1 si falta algo
"""
import re, sys, json, urllib.request, urllib.error

HTML = 'index.html'
src = open(HTML, encoding='utf-8').read()

m = re.search(r"https://([a-z0-9]+)\.supabase\.co", src)
if not m: sys.exit('[FALTA] no encontré la URL de Supabase en ' + HTML)
BASE = 'https://%s.supabase.co/rest/v1/' % m.group(1)

k = re.search(r"eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}", src)
if not k: sys.exit('[FALTA] no encontré la anon key en ' + HTML)
KEY = k.group(0)

objetos = sorted(set(re.findall(r"from\('([a-z_][a-z0-9_]*)'\)", src)))
if not objetos: sys.exit('[FALTA] no encontré ninguna llamada from(...) en ' + HTML)

faltan, ok, raros = [], [], []
for t in objetos:
    req = urllib.request.Request(BASE + t + '?select=*&limit=1',
                                 headers={'apikey': KEY, 'Authorization': 'Bearer ' + KEY})
    try:
        body = urllib.request.urlopen(req, timeout=20).read().decode('utf-8', 'replace')
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8', 'replace')
    except Exception as e:
        raros.append((t, '%s: %s' % (type(e).__name__, str(e)[:80]))); continue
    if 'PGRST205' in body:      faltan.append(t)
    elif body.lstrip().startswith('['): ok.append(t)
    else:
        try:   msg = json.loads(body).get('message', body)[:80]
        except Exception: msg = body[:80]
        raros.append((t, msg))

print('Objetos que el código consulta: %d' % len(objetos))
for t in ok:    print('   existe   %s' % t)
for t, e in raros: print('   ?        %-38s %s' % (t, e))
for t in faltan: print('   FALTA    %s' % t)

if raros:
    print('\n⚠ %d objeto(s) sin respuesta clara — revisar a mano antes de publicar.' % len(raros))
if faltan:
    print('\n✗ FALTAN %d objeto(s) en Supabase. NO publicar a main hasta pegarlos.' % len(faltan))
    print('  Buscá cuál .sql los crea:  grep -l "%s" *.sql' % faltan[0])
    sys.exit(1)
print('\n✓ todo lo que el código consulta existe en Supabase')
