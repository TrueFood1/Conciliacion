#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
armar_ensayo_cancelar.py — arma PRUEBAS_CANCELAR.sql pegando el CUERPO REAL del
pegado 9 seguido de las pruebas, todo en una transaccion que termina en ROLLBACK.

POR QUE EXISTE (camino A). Un ensayo que prueba "lo mismo que el pegado" escrito
a mano prueba una COPIA, y la copia se desincroniza: se arregla el pegado y el
ensayo sigue validando la version vieja — en verde. Aca el cuerpo se EXTRAE del
archivo que se va a pegar, asi que lo que se prueba es byte a byte lo que entra.

COMO EXTRAE EL CUERPO
  Por ESTRUCTURA, no por numero de linea (regla de CLAUDE.md): el unico `begin;`
  y el unico `commit;` que estan solos en su linea. Aborta si no hay exactamente
  uno de cada, y aborta si el cuerpo trae un `rollback` adentro.

LO QUE EL ENSAYO SI PRUEBA DEL PEGADO, por venir el cuerpo de verdad:
  · que el `do $$` que busca el CHECK viejo por su definicion lo encuentre;
  · que el CHECK nuevo acepte 'cancelado';
  · que el `do $candado$` pase (es el mismo candado del pegado);
  · que los dos triggers no rompan los inserts normales del armado.

LO QUE NO PRUEBA, y conviene decirlo: los GRANTS y el `revoke ... from anon` se
aplican igual, pero el rollback los deshace. Que `anon` no pueda ejecutar la
funcion se prueba en el escenario 12, llamandola como anon dentro de la misma
transaccion — ahi si vale.

USO
    python3 herramientas/ensayos/armar_ensayo_cancelar.py
    -> escribe PRUEBAS_CANCELAR.sql en la raiz del repo
"""
import os, sys, re, hashlib

RAIZ   = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PEGADO = os.path.join(RAIZ, 'PERSONAL_CANCELAR_SOLICITUD.sql')
CUERPO = os.path.join(RAIZ, 'herramientas', 'ensayos', 'pruebas_cancelar_cuerpo.sql')
SALIDA = os.path.join(RAIZ, 'PRUEBAS_CANCELAR.sql')

def cuerpo_del_pegado(path):
    txt = open(path, encoding='utf-8').read()
    lineas = txt.splitlines()
    b = [i for i, l in enumerate(lineas) if l.strip() == 'begin;']
    c = [i for i, l in enumerate(lineas) if l.strip() == 'commit;']
    if len(b) != 1 or len(c) != 1:
        sys.exit('[ABORTA] el pegado tiene %d `begin;` y %d `commit;`; tiene que haber '
                 'exactamente uno de cada. No se extrae a ciegas.' % (len(b), len(c)))
    if b[0] > c[0]:
        sys.exit('[ABORTA] el `commit;` esta antes del `begin;`.')
    cuerpo = '\n'.join(lineas[b[0] + 1:c[0]])
    # Fuera de comentarios y literales, no puede haber un rollback adentro.
    limpio = re.sub(r'--[^\n]*', '', cuerpo)
    limpio = re.sub(r"'(?:[^']|'')*'", "''", limpio)
    if re.search(r'\brollback\b', limpio, re.I):
        sys.exit('[ABORTA] el cuerpo del pegado trae un `rollback`.')
    if re.search(r'^\s*(begin|commit)\s*;', limpio, re.I | re.M):
        sys.exit('[ABORTA] quedo un begin/commit dentro del cuerpo extraido.')
    return cuerpo

def main():
    cuerpo = cuerpo_del_pegado(PEGADO)
    pruebas = open(CUERPO, encoding='utf-8').read()
    md5c = hashlib.md5(cuerpo.encode()).hexdigest()

    cab = (
"-- SOLO ENSAYO · PRUEBAS_CANCELAR.sql · termina en ROLLBACK, no deja nada\n"
"-- ════════════════════════════════════════════════════════════════════════\n"
"-- ENSAYO · cancelar lo propio + anti repetidas · CON EL PEGADO 9 ADENTRO\n"
"-- GENERADO por herramientas/ensayos/armar_ensayo_cancelar.py — NO editar a\n"
"-- mano: se regenera y se pierde. Para cambiar las pruebas, editar\n"
"-- herramientas/ensayos/pruebas_cancelar_cuerpo.sql y volver a correrlo.\n"
"--\n"
"-- ⚠️ ADENTRO VA EL CUERPO REAL DE PERSONAL_CANCELAR_SOLICITUD.sql, extraido\n"
"-- del archivo por estructura (el unico begin; y el unico commit;, sin\n"
"-- incluirlos). md5 del cuerpo extraido: " + md5c + "\n"
"-- O sea que esto NO prueba una copia: prueba byte a byte lo que se va a pegar.\n"
"-- Un ensayo que valida una copia se desincroniza en silencio — se arregla el\n"
"-- pegado, el ensayo sigue validando lo viejo, y da verde.\n"
"--\n"
"-- ⚠️ TERMINA EN `rollback;`. Crea y deshace TODO: el esquema del pegado (el\n"
"-- CHECK nuevo, la funcion, los dos triggers) y los datos ficticios. No deja\n"
"-- ni una fila ni un objeto.\n"
"--\n"
"-- ⚠️ CUENTAS FICTICIAS. Crea dos empleados y una socia en rrhh_persona y\n"
"-- acceso_usuario con correos @example.invalid: no depende de que exista tal\n"
"-- cuenta real y no escribe nada a nombre de ninguna persona de verdad.\n"
"--\n"
"-- ⚠️ SOBRE LA CARRERA: una carrera real necesita DOS sesiones concurrentes y\n"
"-- una transaccion no puede tenerlas. Lo que se prueba es su CONSECUENCIA\n"
"-- determinista —el segundo encuentra el estado ya cambiado y recibe el mensaje\n"
"-- claro—, que es lo que el lock garantiza. No se afirma haber probado\n"
"-- concurrencia real.\n"
"-- ════════════════════════════════════════════════════════════════════════\n"
"\n"
"begin;\n"
"\n"
"-- ╔══════════════════════════════════════════════════════════════════════╗\n"
"-- ║  CUERPO DE PERSONAL_CANCELAR_SOLICITUD.sql — pegado tal cual         ║\n"
"-- ╚══════════════════════════════════════════════════════════════════════╝\n")

    med = ("\n-- ╔══════════════════════════════════════════════════════════════════════╗\n"
           "-- ║  FIN DEL CUERPO DEL PEGADO · desde aca, las PRUEBAS                  ║\n"
           "-- ╚══════════════════════════════════════════════════════════════════════╝\n\n")

    pie = ("\nrollback;\n\n"
"-- ── DESPUES DEL ROLLBACK ────────────────────────────────────────────────\n"
"-- No tiene que quedar NADA, ni datos ni esquema:\n"
"--   select count(*) from acceso_usuario where nota = 'ensayo-cancelar';      -- 0\n"
"--   select count(*) from rrhh_persona  where creado_por = 'ensayo-cancelar'; -- 0\n"
"--   select count(*) from rrhh_evento   where creado_por = 'ensayo-cancelar'; -- 0\n"
"--   select count(*) from rrhh_permiso  where creado_por = 'ensayo-cancelar'; -- 0\n"
"--   select count(*) from pg_proc where proname = 'rrhh_cancelar_solicitud';  -- 0\n"
"--   select count(*) from pg_constraint where conname='rrhh_permiso_estado_ok'; -- 0\n"
"--   select count(*) from pg_trigger where tgname like 'rrhh_%_no_repetida_tg'; -- 0\n")

    salida = cab + cuerpo + med + pruebas + pie
    open(SALIDA, 'w', encoding='utf-8').write(salida)

    l = [x.strip() for x in re.sub(r"'(?:[^']|'')*'", "''",
            re.sub(r'--[^\n]*', '', salida)).splitlines() if x.strip()]
    print('cuerpo del pegado : %d lineas · md5 %s' % (len(cuerpo.splitlines()), md5c))
    print('pruebas           : %d lineas' % len(pruebas.splitlines()))
    print('PRUEBAS_CANCELAR.sql: %d bytes · %d lineas'
          % (len(salida.encode()), len(salida.splitlines())))
    print('begin %d · commit %d · rollback %d · ultima sentencia %r'
          % (l.count('begin;'), l.count('commit;'), l.count('rollback;'), l[-1]))
    if l.count('commit;') or l.count('rollback;') != 1 or l[-1] != 'rollback;':
        sys.exit('[ABORTA] el archivo generado no cierra en un unico rollback.')
    print('✓ generado')

if __name__ == '__main__':
    main()
