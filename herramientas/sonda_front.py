#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
sonda_front.py — cruzar LO QUE EL FRONT-END PIDE contra LO QUE EXISTE en Supabase.

POR QUE EXISTE
  El 20-oct-2026, con la cuenta de una empleada, «Mis solicitudes» no cargaba:

      column v_rrhh_permiso.incapacidad_origen does not exist

  La columna existe en la TABLA `rrhh_permiso` y en la vista `v_rrhh_permiso_dia`,
  pero NUNCA estuvo en `v_rrhh_permiso`, y el index.html se la pedia a esa vista.
  La lista no cargaba, asi que el boton de Cancelar quedaba inalcanzable.

  Los tres chequeos que ya existian no podian verlo, y conviene saber por que:
    · esquema_check.py pide `?select=*&limit=1`. `select=*` NO NOMBRA ninguna
      columna: verifica que el OBJETO exista y este cerrado a anon, nada mas.
    · sonda_columnas.py si distingue 42703 de 42501, pero su lista esta QUEMADA
      en el codigo (las columnas del pegado 5) y `v_rrhh_permiso` no estaba ahi.
      La herramienta servia; nunca se la apunto a esto.
    · las pruebas de render corren los render de verdad pero NO TOCAN LA BASE.
      El bug estaba en la consulta, antes del render.
  O sea: nada comparaba las dos listas. Esta herramienta hace exactamente eso.

COMO FUNCIONA
  PostgREST resuelve los NOMBRES DE COLUMNA antes de chocar con el permiso, asi
  que con la anon key —que ya va publicada dentro de index.html— alcanza:
      42501     permission denied  -> la columna EXISTE y esta cerrada
      42703     does not exist     -> la columna NO existe
      PGRST205                     -> el OBJETO no existe
      una lista                    -> ✗ FUGA: la anon key atraveso

  Pide TODAS las columnas de un objeto en UN pedido. Solo si ese pedido contesta
  42703 baja a columna por columna, para nombrar todas las que faltan y no solo
  la primera. 53 pedidos en vez de 311.

LO QUE NO HACE, Y HAY QUE DECIRLO
  · No lee datos: sobre un objeto cerrado toda respuesta es un error. Es seguro
    contra las tablas con salario: no imprime ni un monto.
  · Un 42501 no prueba que la columna tenga el tipo que uno cree.
  · No entiende los selects que se arman en tiempo de ejecucion ni los payloads
    que llegan en una variable. Esos NO SE SALTAN EN SILENCIO: salen listados
    como «no pude leer», con archivo y linea, para que se revisen a mano. Un
    chequeo que se saltea lo que no entiende da verde y no sirve.

USO
    python3 herramientas/sonda_front.py                  # el index.html del repo
    python3 herramientas/sonda_front.py otro/index.html  # el que se va a publicar
    python3 herramientas/sonda_front.py --solo rrhh      # solo Personal
  Sale con codigo 1 si falta una columna o un objeto, o si hay una fuga.
"""
import re, sys, json, os, urllib.request, urllib.error

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ── 1 · LEER EL index.html QUE SE VA A PUBLICAR ───────────────────────────────

def conexion(src):
    m = re.search(r"https://([a-z0-9]+)\.supabase\.co", src)
    k = re.search(r"eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}", src)
    if not m or not k:
        sys.exit('[FALTA] no encontre la URL o la anon key en el archivo')
    return 'https://%s.supabase.co/rest/v1/' % m.group(1), k.group(0)

def bloque_llaves(txt, i):
    """Devuelve el texto del objeto literal que empieza en la `{` de la posicion i,
    balanceando llaves. None si no cierra (y entonces se reporta, no se adivina)."""
    if i >= len(txt) or txt[i] != '{':
        return None
    n = 0
    for j in range(i, min(len(txt), i + 4000)):
        if   txt[j] == '{': n += 1
        elif txt[j] == '}':
            n -= 1
            if n == 0:
                return txt[i:j+1]
    return None

def analizar(src):
    """-> (pedidos {objeto: set(columnas)}, huecos [(linea, objeto, motivo, texto)])"""
    pedidos, huecos = {}, []
    linea_de = lambda pos: src[:pos].count('\n') + 1
    renglon  = lambda pos: src.split('\n')[linea_de(pos)-1].strip()[:110]

    for m in re.finditer(r"\.from\(\s*'([a-z_][a-z0-9_]*)'\s*\)", src):
        obj   = m.group(1)
        resto = src[m.end():m.end()+600]
        # que le hacen al objeto, salteando espacios y saltos de linea
        sel = re.match(r"\s*\.select\(\s*'([^']*)'", resto)
        esc = re.match(r"\s*\.(insert|upsert|update)\(\s*", resto)
        if sel:
            cols = [c.strip() for c in sel.group(1).split(',')]
            cols = [c for c in cols if c and c != '*' and re.fullmatch(r'[a-z_][a-z0-9_]*', c)]
            raras = [c for c in sel.group(1).split(',')
                     if c.strip() and not re.fullmatch(r'[a-z_][a-z0-9_]*', c.strip())]
            if raras:
                huecos.append((linea_de(m.start()), obj,
                               'select con sintaxis que no se cruza (embebido o alias): %s'
                               % ', '.join(x.strip()[:28] for x in raras), renglon(m.start())))
            if cols:
                pedidos.setdefault(obj, set()).update(cols)
            elif not raras:
                huecos.append((linea_de(m.start()), obj, 'select sin columnas nombradas (trae todo)',
                               renglon(m.start())))
        elif esc:
            # el `\s*` del regex ya consumio los espacios: esc.end() ES el primer
            # caracter del argumento. Con un -1 aca apuntaba al parentesis y TODO
            # payload literal salia como «no se puede leer» — un falso negativo que
            # ademas se veia prolijo, que es la peor clase.
            ini = m.end() + esc.end()
            cuerpo = bloque_llaves(src, ini)
            if cuerpo is None:
                huecos.append((linea_de(m.start()), obj,
                               '%s con el payload en una variable o sin cerrar: no se puede leer'
                               % esc.group(1), renglon(m.start())))
            else:
                claves = set(re.findall(r"(?:^|[{,\s])([a-z_][a-z0-9_]*)\s*:", cuerpo, re.M))
                # las claves van sobre la TABLA; un objeto con `v_` adelante no se escribe
                if claves:
                    pedidos.setdefault(obj, set()).update(claves)
                else:
                    huecos.append((linea_de(m.start()), obj,
                                   '%s sin claves legibles' % esc.group(1), renglon(m.start())))
        else:
            # delete(), rpc encadenado, o una cadena que sigue en otra forma
            que = re.match(r"\s*\.([a-z]+)", resto)
            huecos.append((linea_de(m.start()), obj,
                           'no es select ni escritura con payload literal (.%s)'
                           % (que.group(1) if que else '?'), renglon(m.start())))
    return pedidos, huecos

# ── 2 · SONDEAR ───────────────────────────────────────────────────────────────

def sondear(base, key, obj, cols):
    req = urllib.request.Request(base + obj + '?select=' + ','.join(cols) + '&limit=1',
        headers={'apikey': key, 'Authorization': 'Bearer ' + key})
    try:
        body = urllib.request.urlopen(req, timeout=25).read().decode('utf-8', 'replace')
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8', 'replace')
    except Exception as e:
        return 'ERR', '%s: %s' % (type(e).__name__, str(e)[:70])
    try:
        js = json.loads(body)
    except Exception:
        return '??', body[:70]
    if isinstance(js, list):
        return 'FUGA', 'la anon key ATRAVESO y devolvio una lista (%d fila/s)' % len(js)
    code = js.get('code', '?')
    msg  = str(js.get('message', ''))[:90]
    if code == '42501' or 'permission denied' in msg:
        return '42501', ''
    return code, msg

def main():
    argv = sys.argv[1:]
    solo, args, i = None, [], 0
    while i < len(argv):
        if argv[i] == '--solo' and i + 1 < len(argv):
            solo = argv[i+1]; i += 2; continue        # el VALOR no es una ruta
        if not argv[i].startswith('--'): args.append(argv[i])
        i += 1
    ruta = args[0] if args else os.path.join(RAIZ, 'index.html')
    if not os.path.exists(ruta):
        sys.exit('[FALTA] no existe %s' % ruta)
    src = open(ruta, encoding='utf-8').read()
    base, key = conexion(src)

    pedidos, huecos = analizar(src)
    if solo:
        pedidos = {k: v for k, v in pedidos.items() if solo in k}
        huecos  = [h for h in huecos if solo in h[1]]

    rel = os.path.relpath(ruta, RAIZ)
    print('sonda_front.py · %s' % (ruta if rel.startswith('..') else rel))
    print('  %d objetos · %d columnas pedidas%s'
          % (len(pedidos), sum(len(v) for v in pedidos.values()),
             ('  (filtro: %s)' % solo) if solo else ''))
    print('')

    faltan, abiertos, raros = [], [], []
    for obj in sorted(pedidos):
        cols = sorted(pedidos[obj])
        code, msg = sondear(base, key, obj, cols)
        if code == '42501':
            print('  ✓ %-28s %2d columnas · todas existen, cerrado a anon' % (obj, len(cols)))
        elif code == 'FUGA':
            # Una lista significa que las columnas EXISTEN: para este chequeo, pasa.
            # Si ese objeto DEBERIA estar cerrado a anon es otra pregunta y la
            # contesta esquema_check.py, que tiene la lista curada de lo sensible y
            # de lo que esta abierto a proposito. Aca se informa, no se juzga:
            # duplicar ese criterio con peor informacion daria rojo todos los dias
            # y el rojo de todos los dias no lo mira nadie.
            print('  ✓ %-28s %2d columnas · todas existen · abierto a anon (lo juzga esquema_check.py)'
                  % (obj, len(cols)))
            abiertos.append(obj)
        elif code == 'PGRST205':
            print('  ✗ %-28s EL OBJETO NO EXISTE' % obj); faltan.append((obj, '(el objeto)'))
        elif code == '42703':
            # bajar a columna por columna para nombrar TODAS las que faltan
            malas = []
            for c in cols:
                c2, _ = sondear(base, key, obj, [c])
                if c2 == '42703': malas.append(c)
            if malas:
                print('  ✗ %-28s NO EXISTE: %s' % (obj, ', '.join(malas)))
                for c in malas: faltan.append((obj, c))
            else:
                print('  ? %-28s 42703 en conjunto pero ninguna sola: %s' % (obj, msg))
                raros.append((obj, msg))
        else:
            print('  ? %-28s %s %s' % (obj, code, msg)); raros.append((obj, msg))

    if huecos:
        print('')
        print('  ── NO PUDE LEER %d lugar/es · revisar a mano (no se saltean en silencio) ──'
              % len(huecos))
        for linea, obj, motivo, txt in sorted(huecos):
            print('     linea %-6d %-24s %s' % (linea, obj, motivo))
            print('                   %s' % txt)

    print('')
    print('  ── RESUMEN ──')
    print('     columnas que no existen : %d' % len(faltan))
    print('     abiertos a anon         : %d  (no es falla de este chequeo)' % len(abiertos))
    print('     respuestas raras        : %d' % len(raros))
    print('     lugares no leidos       : %d' % len(huecos))
    if faltan:
        print('')
        print('  ✗ EL FRONT-END PIDE COSAS QUE NO EXISTEN. No se publica:')
        for obj, c in faltan: print('       %s.%s' % (obj, c))
        return 1
    print('')
    print('  ✓ 0 faltantes: cada columna que el front-end pide existe en la base.')
    return 0

if __name__ == '__main__':
    sys.exit(main())
