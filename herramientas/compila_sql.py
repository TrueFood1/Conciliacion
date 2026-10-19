#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
compila_sql.py — pasa un .sql por EL PARSER DE VERDAD de PostgreSQL (libpg_query,
via pglast) y además por el parser de plpgsql cada cuerpo de función y cada
bloque DO.

POR QUE EXISTE. Un error de sintaxis en un pegado se descubre, hoy, pegándolo en
produccion: no hay Postgres ni Docker en esta maquina. Esto usa el MISMO parser
que el servidor, sin servidor, asi que los errores de sintaxis salen aca.

QUE SI PRUEBA
  · sintaxis de cada sentencia SQL, con el parser oficial;
  · sintaxis de cada cuerpo plpgsql (bloques DO y cuerpos de funcion), con el
    parser oficial de plpgsql — que es el que caza un `end if` de menos.

QUE NO PRUEBA, y hay que decirlo: nada semantico. No resuelve nombres de tabla,
de columna ni de funcion, no verifica tipos, no corre nada. Un `select columna_que_no_existe`
pasa limpio. No reemplaza al ensayo contra la base.

Uso:  python3 herramientas/compila_sql.py archivo.sql [...]
"""
import re, sys
import pglast
from pglast.parser import ParseError

def linea_de(texto, pos):
    return texto.count('\n', 0, max(0, pos)) + 1

def cuerpos_plpgsql(s):
    """(descripcion, linea, sql_a_parsear) de cada DO y cada funcion plpgsql.

    ⚠️ LA FIRMA DE LA FUNCION SE CONSERVA, y no es un detalle. La primera version
    de esto envolvia TODO cuerpo en un `create function ... returns void`, y
    entonces `rrhh_cancelar_solicitud`, que es `returns table (...)`, salia como
    «cannot use RETURN QUERY in a non-SETOF function»: un error inventado por la
    herramienta. Una herramienta que da falsos positivos es peor que no tenerla,
    porque enseña a ignorarla. Las funciones se pasan TAL CUAL; solo los bloques
    DO se envuelven, y ahi `returns void` es la equivalencia correcta: un DO no
    devuelve nada.
    """
    out = []
    for m in re.finditer(r'\bdo\s+(\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$)', s, re.I):
        tag = m.group(1); j = s.find(tag, m.end())
        if j < 0: continue
        out.append(('bloque DO %s' % tag, linea_de(s, m.start()),
                    'create function zz_compila() returns void language plpgsql as '
                    '$compila$' + s[m.end():j] + '$compila$;'))
    for m in re.finditer(r'\bcreate\s+(?:or\s+replace\s+)?function\b', s, re.I):
        # El final de la sentencia es el cierre de su propio $tag$.
        mt = re.search(r'\bas\s+(\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$)', s[m.start():], re.I | re.S)
        if not mt: continue
        tag = mt.group(1)
        ini_cuerpo = m.start() + mt.end()
        j = s.find(tag, ini_cuerpo)
        if j < 0: continue
        sent = s[m.start():j + len(tag)] + ';'
        if not re.search(r'language\s+plpgsql', sent, re.I): continue
        nom = re.search(r'function\s+([\w.]+)', sent, re.I)
        out.append(('funcion %s' % (nom.group(1) if nom else '?'),
                    linea_de(s, m.start()), sent))
    return out

def revisar(path):
    s = open(path, encoding='utf-8').read()
    errores = []

    # 1 · EL ARCHIVO ENTERO, con el parser de SQL.
    try:
        arbol = pglast.parse_sql(s)
        n_sent = len(arbol)
    except ParseError as e:
        n_sent = None
        errores.append(('SQL', getattr(e, 'location', None), str(e)))

    # 2 · CADA CUERPO plpgsql, con el parser de plpgsql. Se envuelve en un
    #     `create function` minimo porque es lo que el parser espera recibir.
    n_cuerpos = 0
    for desc, ln, sent in cuerpos_plpgsql(s):
        n_cuerpos += 1
        try:
            pglast.parse_plpgsql(sent)
        except Exception as e:
            errores.append(('plpgsql · %s (linea %d del archivo)' % (desc, ln), None, str(e)))
    return n_sent, n_cuerpos, errores

malo = 0
for path in sys.argv[1:]:
    n_sent, n_cuerpos, errores = revisar(path)
    print('── %s' % path)
    print('   sentencias SQL: %s · cuerpos plpgsql: %d'
          % ('%d ✓' % n_sent if n_sent is not None else 'NO COMPILA', n_cuerpos))
    for donde, loc, msg in errores:
        malo += 1
        print('   ❌ %s%s' % (donde, (' · posicion %s' % loc) if loc else ''))
        print('      %s' % msg.strip().replace('\n', ' ')[:300])
    if not errores:
        print('   ✓ sintaxis correcta, con el parser de PostgreSQL')
print()
print('TOTAL: %d archivo(s) con errores de sintaxis' % malo)
print('⚠️ Esto es SOLO sintaxis. No resuelve nombres ni tipos: no reemplaza al ensayo.')
sys.exit(1 if malo else 0)
