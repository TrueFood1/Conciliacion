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

────────────────────────────────────────────────────────────────────────────
SEGUNDA PREGUNTA, DESDE EL 26-ago: ¿está CERRADO lo que tiene que estarlo?

Este chequeo nació preguntando "¿existe?". El 24-ago quedó claro que esa no
es la única pregunta que importa. `v_acceso_usuario` existía, contestaba, y
le devolvía a la ANON KEY —que va publicada dentro de index.html en GitHub
Pages— las cinco filas con nombre, perfil y correo, tres de ellos personales.
Le faltaba `security_invoker`, así que la vista corría con los permisos de su
dueño y esquivaba la RLS de la tabla. Puerta con llave, ventana abierta.

Este chequeo daba ✓ mientras eso pasaba, y habría seguido dándolo. Peor: para
un objeto SENSIBLE, el `[]` que acá significaba "todo bien" es exactamente la
señal de que la anon key llegó a la tabla.

Por eso los objetos sensibles se leen AL REVÉS:

    permission denied  →  ✓  cerrado, que es lo que se espera
    [] o filas         →  ✗  FUGA: la anon key llega. BLOQUEA.
    PGRST205           →     no existe (igual que cualquier otro objeto)

Y una fuga bloquea SIEMPRE, sea dependencia nueva o vieja. Que la ventana
lleve tiempo abierta no la hace menos ventana.

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

# QUÉ ES SENSIBLE. Todo lo que guarda datos de PERSONAS: salarios, incapacidades
# médicas, correos personales. Es lo único de Truefie que la anon key no debe ver
# ni vacío.
#
# Van dos reglas y no una a propósito:
#   · el PREFIJO cubre solo lo que todavía no existe — una tabla `rrhh_` nueva nace
#     vigilada sin que nadie se acuerde de anotarla acá;
#   · la LISTA cubre lo que no lleva el prefijo, que hoy son las dos de accesos.
# Un objeto sensible con otro nombre y sin anotar se escapa de las dos: si nace uno,
# va a la lista. Es la parte que sigue dependiendo de alguien.
SENSIBLE_PREFIJOS = ('rrhh_', 'v_rrhh_')
SENSIBLE_LISTA    = {'acceso_usuario', 'v_acceso_usuario'}
def es_sensible(t):
    return t in SENSIBLE_LISTA or t.startswith(SENSIBLE_PREFIJOS)

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
cerrados, fugas = [], []

# LOS SENSIBLES DE LA LISTA SE SONDEAN AUNQUE EL CÓDIGO NO LOS LLAME, y esto no es
# un detalle: es la corrección del punto ciego que CLAUDE.md ya tenía anotado. Este
# chequeo saca los objetos de los `from('tabla')` del index.html, o sea que solo ve
# lo que el código consulta. La fuga del 24-ago fue en `v_acceso_usuario`, que
# index.html TODAVÍA no consulta —el lobby sigue con la lista quemada en el HTML—,
# así que mirar solo lo llamado la habría dejado pasar de nuevo, con el chequeo
# recién escrito para cazarla.
# Los del PREFIJO no se pueden forzar igual: no hay forma de enumerar el esquema con
# la anon key, así que esos aparecen recién cuando el código los usa.
objetivos = sorted(aqui | SENSIBLE_LISTA)
for t in objetivos:
    req=urllib.request.Request(BASE+t+'?select=*&limit=1',
                               headers={'apikey':KEY,'Authorization':'Bearer '+KEY})
    try: body=urllib.request.urlopen(req,timeout=20).read().decode('utf-8','replace')
    except urllib.error.HTTPError as e: body=e.read().decode('utf-8','replace')
    except Exception as e: raros.append((t,'%s: %s'%(type(e).__name__,str(e)[:70]))); continue
    try: js=json.loads(body)
    except Exception: js=None
    # Postgres devuelve 42501 (insufficient_privilege) cuando la RLS o la falta de
    # grant frenan la lectura. Se mira el código y no el texto porque el mensaje
    # nombra la tabla de abajo, no la que se pidió: la fuga de v_acceso_usuario
    # habría dicho "permission denied for table acceso_usuario".
    negado = isinstance(js,dict) and (js.get('code')=='42501'
                                      or 'permission denied' in str(js.get('message','')))
    lista  = body.lstrip().startswith('[')

    if 'PGRST205' in body:
        # Un sensible forzado que no existe no le falta a nadie: nadie lo consulta.
        if t in aqui: (falta_nuevo if t in nuevos else falta_viejo).append(t)
    elif es_sensible(t):
        # AL REVÉS que el resto: acá el `[]` es la mala noticia. Vacío no es seguro
        # —significa que la anon key ATRAVESÓ y que hoy no había filas—, y mañana
        # las hay.
        if negado:  cerrados.append(t)
        elif lista:
            n = len(js) if isinstance(js,list) else 0
            fugas.append((t, ('LEE DATOS con la anon key (%d fila en la primera página)'%n)
                             if n else 'la anon key atraviesa — devolvió lista vacía, no un rechazo'))
        else:
            raros.append((t, (str(js.get('message',body))[:70] if isinstance(js,dict) else body[:70])))
    elif lista: ok.append(t)
    elif negado:
        # No sensible y sin grant. No es fuga ni falta: es un objeto que el código
        # consulta y la anon key no puede leer. Se dice, no se calla.
        raros.append((t,'sin permiso para la anon key — ¿le falta grant o le sobra RLS?'))
    else:
        raros.append((t, (str(js.get('message',body))[:70] if isinstance(js,dict) else body[:70])))

print('Objetos consultados: %d  ·  dependencias nuevas respecto de %s: %d'%(len(aqui),base,len(nuevos)))
print('   existen: %d'%len(ok))
for t in cerrados: print('   ✓ cerrado %-37s la anon key no puede leerlo'%t)
for t,e in fugas:  print('   ✗ FUGA    %-37s %s'%(t,e))
for t,e in raros:  print('   ?        %-38s %s'%(t,e))

# LA FUGA VA PRIMERA Y BLOQUEA SIEMPRE. No entra en la lógica de "nuevo vs viejo":
# esa distingue deuda tolerable de riesgo recién introducido, y una tabla de salarios
# abierta al público no es tolerable por vieja. Se sale acá mismo, antes de imprimir
# nada más, para que sea lo último que quede en pantalla.
if fugas:
    print('\n✗ BLOQUEA — %d objeto(s) SENSIBLE(S) que la anon key puede leer:'%len(fugas))
    for t,e in fugas: print('     %-38s %s'%(t,e))
    print('  La anon key es PÚBLICA: va dentro de index.html y GitHub Pages la sirve.')
    print('  Que hoy devuelva vacío no es protección — significa que la consulta LLEGÓ.')
    print('  Revisá dos cosas, en este orden:')
    print('    1) que la vista lleve `with (security_invoker = true)` — sin eso corre')
    print('       con los permisos de su dueño y esquiva la RLS (pasó el 24-ago);')
    print('    2) que exista el `revoke all on <objeto> from anon`.')
    sys.exit(1)

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
