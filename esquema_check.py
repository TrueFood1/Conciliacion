#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Chequeo de ESQUEMA: ¿existe en Supabase todo lo que el código consulta?

Por qué existe: el 17-ago se publicó a `main` código que dependía de
ENTREGAS_ETAPAS.sql sin pegar. Andrea lo descubrió el 18 registrando entregas
reales, con tres errores encadenados en producción. `loadcheck.py` no podía
cazarlo — corre el JS con un DOM falso y nunca toca la red.

BLOQUEA vs AVISA. Un chequeo que falla siempre se ignora, y entonces no sirve
para nada. Por eso distingue dos cosas distintas:

  · BLOQUEA (sale 1) si el objeto que falta es una dependencia NUEVA — está en
    el árbol de trabajo y NO en `main`. Ese es exactamente el caso de b20: se
    publicó código que estrenaba una tabla sin pegar.
  · AVISA (sale 0) si el objeto que falta YA estaba en `main`. Publicar no lo
    empeora; la deuda es anterior y se arrastra hasta que se pegue el .sql. Se
    lista aparte, con fecha, para que se vea que está reconocida y no olvidada.

Cómo lo mide: pide 1 fila de cada objeto con la anon key (pública por diseño).
No lee datos, solo distingue PGRST205 (no existe) de [] (existe, vacío o
filtrado por RLS — da igual cuál).

Uso:
    python3 esquema_check.py            # compara contra main
    python3 esquema_check.py --base X   # compara contra otra rama/commit
"""
import re, sys, json, subprocess, urllib.request, urllib.error

# Deuda reconocida: objetos que faltan en Supabase y que YA estaban en main.
# Se anota con fecha para que quede claro desde cuándo y por qué no bloquea.
DEUDA = {
    'ent_salida':                             '18-ago-2026 · ENTREGAS_ETAPAS.sql sin pegar',
    'v_ent_pedido_estado':                    '18-ago-2026 · ENTREGAS_ETAPAS.sql sin pegar',
    'ent_salido_del_congelador_desde_ancla':  '18-ago-2026 · ENTREGAS_ETAPAS.sql sin pegar',
}

HTML='index.html'
base='main'
if '--base' in sys.argv: base=sys.argv[sys.argv.index('--base')+1]

def objetos_de(txt): return set(re.findall(r"from\('([a-z_][a-z0-9_]*)'\)", txt))

src=open(HTML,encoding='utf-8').read()
aqui=objetos_de(src)
if not aqui: sys.exit('[FALTA] no encontré ninguna llamada from(...) en '+HTML)

try:
    en_base=objetos_de(subprocess.run(['git','show',base+':'+HTML],capture_output=True,
                                      text=True,check=True).stdout)
except Exception:
    en_base=set(); print('[aviso] no pude leer %s:%s — trato todo como dependencia nueva'%(base,HTML))
nuevos = aqui - en_base

m=re.search(r"https://([a-z0-9]+)\.supabase\.co", src)
k=re.search(r"eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}", src)
if not m or not k: sys.exit('[FALTA] no encontré la URL o la anon key en '+HTML)
BASE='https://%s.supabase.co/rest/v1/'%m.group(1); KEY=k.group(0)

falta_nuevo, falta_viejo, ok, raros = [], [], [], []
for t in sorted(aqui):
    req=urllib.request.Request(BASE+t+'?select=*&limit=1',
                               headers={'apikey':KEY,'Authorization':'Bearer '+KEY})
    try: body=urllib.request.urlopen(req,timeout=20).read().decode('utf-8','replace')
    except urllib.error.HTTPError as e: body=e.read().decode('utf-8','replace')
    except Exception as e: raros.append((t,'%s: %s'%(type(e).__name__,str(e)[:70]))); continue
    if 'PGRST205' in body:
        (falta_nuevo if t in nuevos else falta_viejo).append(t)
    elif body.lstrip().startswith('['): ok.append(t)
    else:
        try: msg=json.loads(body).get('message',body)[:70]
        except Exception: msg=body[:70]
        raros.append((t,msg))

print('Objetos consultados: %d  ·  dependencias nuevas respecto de %s: %d'%(len(aqui),base,len(nuevos)))
print('   existen: %d'%len(ok))
for t,e in raros: print('   ?        %-38s %s'%(t,e))

if falta_viejo:
    print('\n⚠ DEUDA CONOCIDA — faltan en Supabase, pero ya estaban en %s (no bloquea):'%base)
    for t in falta_viejo:
        print('     %-38s %s'%(t, DEUDA.get(t,'sin anotar — anotala en DEUDA con fecha')))
    sin_anotar=[t for t in falta_viejo if t not in DEUDA]
    if sin_anotar:
        print('   ✗ %d sin anotar en DEUDA. Anotalas con fecha y motivo.'%len(sin_anotar))
        sys.exit(1)

if raros:
    print('\n⚠ %d objeto(s) sin respuesta clara — revisar a mano antes de publicar.'%len(raros))

if falta_nuevo:
    print('\n✗ BLOQUEA — %d dependencia(s) NUEVA(S) sin esquema en Supabase:'%len(falta_nuevo))
    for t in falta_nuevo: print('     %s'%t)
    print('  Este código no existe en %s todavía. Pegá el .sql que los crea ANTES de publicar.'%base)
    print('  Buscá cuál: grep -l "%s" *.sql'%falta_nuevo[0])
    sys.exit(1)

print('\n✓ ninguna dependencia nueva sin esquema — se puede publicar')
