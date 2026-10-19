#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
lint_sql_ensayo.py — revisa un .sql de ensayo buscando las trampas que ya
nos costaron una vuelta cada una.

POR QUE EXISTE. El 7-oct-2026 el mismo ensayo fallo DOS veces seguidas en
Supabase, las dos por cosas que un chequeo mecanico habria cazado antes de
pegarlo:

  1. ERROR 21000 · `(select id from rrhh_persona where nombre ilike 'daniel%')`
     devolvia DOS filas, porque el equipo tiene a Daniel y a Daniela y el %
     es un prefijo. Peor: un `limit 1` lo habria "arreglado" cargandole los
     dias a la persona equivocada.
  2. ERROR 22P02 · `current_setting(...)::int` sobre un valor que venia de una
     columna NUMERIC ('2.0'). Y de la misma raiz salia un segundo bug que NO
     reventaba: `'2.0' = '2'` como TEXTO da false, asi que una asercion habria
     dicho FALLA para siempre sin que nadie supiera por que.

NO ES UN VERIFICADOR DE TIPOS. No hay Postgres en esta Mac (ni psql, ni docker),
asi que no se puede validar de verdad contra un motor. Esto es un LINT de
patrones: caza las formas que ya fallaron, no garantiza que el SQL corra.
Decirlo asi importa — un lint que se presenta como validador es peor que no
tenerlo.

⚠️ FALSOS POSITIVOS CONOCIDOS, Y UNO DONDE SEGUIR EL CONSEJO SERIA PEOR.
  El lint no sabe de donde VIENE cada valor, asi que marca toda comparacion de
  texto contra un numero. Medido el 7-oct en PRUEBAS_RESOLVER.sql: sus 6
  hallazgos ALTO son todos falsos positivos — los settings salen de `count(*)`
  (entero), nunca de una columna NUMERIC.
  Y en cuatro de ellos la comparacion de TEXTO es la CORRECTA: esos settings
  pueden valer 'ERROR 42501 · ...' cuando el escenario falla a proposito, asi que
  un `::numeric` los haria reventar con 22P02. Antes de "arreglar" un hallazgo,
  hay que mirar de donde sale el valor; si puede ser no numerico, texto esta bien.

QUE MIRA
  · casts a entero (::int / ::integer) sobre current_setting -> el 22P02
  · comparaciones de texto contra un literal numerico        -> el bug silencioso
  · `ilike '...%'` como criterio de unicidad                 -> el 21000
  · `limit 1` sobre un conjunto que deberia ser unico
  · subconsultas escalares sin un guardia de conteo antes
  · redondeos en una asercion (round/trunc/floor/ceil)
  · que cierre en rollback y no en commit
  · bool_and/bool_or (dan NULL sobre conjunto vacio -> OK vacio)

USO
    python3 herramientas/lint_sql_ensayo.py PRUEBAS_*.sql
"""
import re, sys

NUM = {'numeric','decimal','real','double'}

def revisar(path):
    s = open(path, encoding='utf-8').read()
    t = re.sub(r'--[^\n]*', '', s)                      # fuera comentarios de linea
    tq = re.sub(r"'(?:[^']|'')*'", "''", t)             # fuera literales
    hall = []

    for m in re.finditer(r"current_setting\([^)]*\)\s*(?:::\s*)?(?:\)\s*)?::\s*int(?:eger)?\b", t):
        hall.append(('ALTO', '::int sobre current_setting — si el origen es NUMERIC da 22P02',
                     t[:m.start()].count('\n')+1))
    for m in re.finditer(r"current_setting\([^)]*\)\s*(?:=|<>)\s*'[0-9]", t):
        hall.append(('ALTO', "texto comparado contra literal numerico — '2.0' = '2' da false, en silencio",
                     t[:m.start()].count('\n')+1))
    for m in re.finditer(r"ilike\s*'[^']*%'", t):
        hall.append(('ALTO', "ilike con % como criterio de unicidad — 'daniel%' matchea Daniela",
                     t[:m.start()].count('\n')+1))
    for m in re.finditer(r'\blimit\s+1\b', tq):
        hall.append(('MEDIO', 'limit 1 — ¿esta probado que el conjunto es unico, o elige a ciegas?',
                     tq[:m.start()].count('\n')+1))
    for m in re.finditer(r'\b(round|trunc|floor|ceil)\s*\(', tq):
        hall.append(('MEDIO', 'redondeo dentro del archivo — ¿no esta tapando una diferencia?',
                     tq[:m.start()].count('\n')+1))
    for m in re.finditer(r'\bbool_(and|or)\s*\(', tq):
        hall.append(('MEDIO', 'bool_and/bool_or — da NULL sobre conjunto vacio: un OK que no midio nada',
                     tq[:m.start()].count('\n')+1))

    l = [x.strip() for x in tq.splitlines() if x.strip()]
    estruct = []
    if l:
        estruct.append(('rollback' if l[-1] == 'rollback;' else
                        'commit' if l[-1] == 'commit;' else l[-1]))
    nb, nc, nr = l.count('begin;'), l.count('commit;'), l.count('rollback;')
    par = (tq.count('('), tq.count(')'))

    print('── %s' % path)
    print('   begin %d · commit %d · rollback %d · ultima sentencia: %s'
          % (nb, nc, nr, estruct[0] if estruct else '?'))
    print('   parentesis balanceados: %s (%d/%d)' % (par[0]==par[1], par[0], par[1]))
    if not hall:
        print('   ✓ ninguno de los patrones conocidos')
    else:
        for nivel, qué, ln in sorted(hall, key=lambda x: (x[0] != 'ALTO', x[2])):
            print('   %-5s linea %-4d %s' % (nivel, ln, qué))
    return sum(1 for h in hall if h[0] == 'ALTO')

if __name__ == '__main__':
    objetivos = sys.argv[1:]
    if not objetivos:
        sys.exit('uso: lint_sql_ensayo.py <archivo.sql> ...')
    altos = sum(revisar(p) for p in objetivos)
    print()
    print('hallazgos ALTO en total: %d' % altos)
    sys.exit(1 if altos else 0)
