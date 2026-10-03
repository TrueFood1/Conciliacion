#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
sonda_columnas.py — verificar COLUMNAS reales por REST, con la anon key.

POR QUE EXISTE
  Para auditar el esquema de verdad hace falta pg_lector.py, que pide la clave
  de `postgres`. Cuando esa clave no esta a mano, el unico acceso es la anon
  key — y sobre una tabla cerrada la anon key devuelve `permission denied` y
  parece no servir para nada.

  Si sirve. PostgREST resuelve los NOMBRES DE COLUMNA antes de chocar con el
  permiso, asi que el codigo del error distingue tres cosas:

      42501  permission denied  ->  la tabla y la columna EXISTEN, y esta cerrada
      42703  does not exist     ->  la columna NO existe
      PGRST205                  ->  la TABLA no existe

  Medido el 3-oct-2026 contra rrhh_permiso y rrhh_salario: confirmo las 11 y
  las 7 columnas del esquema, y que `horas`, `dias`, `duracion` y
  `modalidad_descuento` NO existian. Es lo que evito disenar el pago de
  quincena sobre una columna supuesta.

LO QUE NO HACE
  · No enumera: hay que PREGUNTAR por un nombre. No hay forma de listar el
    esquema con la anon key. Para eso sigue haciendo falta pg_lector.py.
  · No lee datos. Sobre una tabla cerrada toda respuesta es un error, y por eso
    es seguro correrla contra la tabla de salarios: no imprime ni un monto.
  · Un `42501` NO prueba que la columna tenga el tipo que uno cree.

  ⚠️ Y si una tabla sensible contesta con una LISTA en vez de un error, eso no
  es un exito de la sonda: es una FUGA, y la sonda lo dice con esa palabra.
  Es la misma lectura al revés que hace esquema_check.py.

COMO SE USA
    python3 herramientas/sonda_columnas.py rrhh_permiso id persona_id horas
    python3 herramientas/sonda_columnas.py --nuevas
        (el juego de columnas que agrego PERSONAL_PAGO_QUINCENA.sql)
"""
import re, sys, json, os, urllib.request, urllib.error

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HTML = os.path.join(RAIZ, 'index.html')

NUEVAS = {
    'rrhh_permiso':       ['modalidad_descuento', 'horas'],
    'rrhh_ajuste_manual': ['id', 'persona_id', 'fecha', 'monto', 'nota',
                           'creado_por', 'creado_en'],
    'v_rrhh_permiso_dia': ['permiso_id', 'persona_id', 'dia', 'quincena', 'habil'],
    'v_rrhh_pago_detalle':['quincena', 'persona_id', 'concepto', 'monto', 'nota'],
    'v_rrhh_pago':        ['quincena', 'persona_id', 'base', 'descuentos',
                           'ajustes', 'final'],
}

def conexion():
    src = open(HTML, encoding='utf-8').read()
    m = re.search(r"https://([a-z0-9]+)\.supabase\.co", src)
    k = re.search(r"eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}", src)
    if not m or not k:
        sys.exit('[FALTA] no encontre la URL o la anon key en index.html')
    return 'https://%s.supabase.co/rest/v1/' % m.group(1), k.group(0)

def sondear(base, key, tabla, col):
    req = urllib.request.Request(base + tabla + '?select=' + col + '&limit=1',
        headers={'apikey': key, 'Authorization': 'Bearer ' + key})
    try:
        body = urllib.request.urlopen(req, timeout=20).read().decode('utf-8', 'replace')
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8', 'replace')
    except Exception as e:
        return 'ERR', '%s: %s' % (type(e).__name__, str(e)[:60])
    try:
        js = json.loads(body)
    except Exception:
        return '??', body[:60]
    if isinstance(js, list):
        return 'FUGA', 'la anon key ATRAVESO y devolvio una lista (%d fila/s)' % len(js)
    code = js.get('code', '?')
    msg  = str(js.get('message', ''))[:70]
    if code == '42501' or 'permission denied' in msg:
        return '42501', ''
    return code, msg

LEE = {'42501': 'EXISTE · cerrada a anon', '42703': 'no existe',
       'PGRST205': 'TABLA no existe', 'FUGA': '✗ FUGA'}

def main():
    base, key = conexion()
    if '--nuevas' in sys.argv:
        casos = NUEVAS
    elif len(sys.argv) >= 3:
        casos = {sys.argv[1]: sys.argv[2:]}
    else:
        sys.exit(__doc__.strip().split('COMO SE USA')[1])
    fugas = 0
    for tabla, cols in casos.items():
        print('── %s' % tabla)
        for c in cols:
            code, msg = sondear(base, key, tabla, c)
            if code == 'FUGA':
                fugas += 1
            print('   %-24s %-26s %s' % (c, LEE.get(code, code), msg))
    if fugas:
        print('\n✗ %d FUGA(S): la anon key es PUBLICA (va dentro de index.html).' % fugas)
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
