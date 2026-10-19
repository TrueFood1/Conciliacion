#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
armar_ensayo_pago_asistente.py — arma PRUEBAS_PAGO_ASISTENTE.sql pegando el CUERPO REAL del
pegado 11 seguido de las pruebas, todo en una transaccion que termina en ROLLBACK.

Camino A, igual que los otros dos ensayos: el cuerpo se EXTRAE del archivo que se
va a pegar, por estructura (el unico begin; y el unico commit;). Asi lo que se
prueba es byte a byte lo que entra, y no una copia que se desincroniza.

⚠️ ESTE ENSAYO NECESITA EL PEGADO 10 YA APLICADO. El cuerpo del 11 usa
`pago_obligatorio`, `rrhh_feriado_paga_doble()`, `rrhh_es_dia_descontable()` y
`rrhh_neto_quincena`, que los crea el pegado 10. Contra una base sin el 10, esto
falla en la primera linea — y esta bien que falle.

USO
    python3 herramientas/ensayos/armar_ensayo_pago_asistente.py
"""
import os, sys, re, hashlib

RAIZ   = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PEGADO = os.path.join(RAIZ, 'PERSONAL_PAGO_ASISTENTE.sql')
CUERPO = os.path.join(RAIZ, 'herramientas', 'ensayos', 'pruebas_pago_asistente_cuerpo.sql')
SALIDA = os.path.join(RAIZ, 'PRUEBAS_PAGO_ASISTENTE.sql')

def sin_comentarios(t):
    return re.sub(r"'(?:[^']|'')*'", "''", re.sub(r'--[^\n]*', '', t))

def cuerpo_del_pegado(path):
    L = open(path, encoding='utf-8').read().splitlines()
    b = [i for i, l in enumerate(L) if l.strip() == 'begin;']
    c = [i for i, l in enumerate(L) if l.strip() == 'commit;']
    if len(b) != 1 or len(c) != 1 or b[0] > c[0]:
        sys.exit('[ABORTA] el pegado tiene %d `begin;` y %d `commit;`; tiene que haber uno de '
                 'cada, y el commit despues. No se extrae a ciegas.' % (len(b), len(c)))
    cuerpo = '\n'.join(L[b[0] + 1:c[0]])
    limpio = sin_comentarios(cuerpo)
    if re.search(r'\brollback\b', limpio, re.I):
        sys.exit('[ABORTA] el cuerpo del pegado trae un `rollback`.')
    if re.search(r'^\s*(begin|commit)\s*;', limpio, re.I | re.M):
        sys.exit('[ABORTA] quedo un begin/commit dentro del cuerpo extraido.')
    # La fila de control del pegado sale: devuelve otro resultado y el editor de
    # Supabase muestra solo el ultimo, asi que taparia la tabla de veredictos.
    L2 = cuerpo.splitlines()
    k = [i for i, l in enumerate(L2) if l.strip().startswith('-- ── 6 · LA FILA DE CONTROL')]
    if len(k) != 1:
        sys.exit('[ABORTA] no encontre la fila de control para sacarla (encontre %d).' % len(k))
    return '\n'.join(L2[:k[0]])

def main():
    cuerpo  = cuerpo_del_pegado(PEGADO)
    pruebas = open(CUERPO, encoding='utf-8').read()
    md5c    = hashlib.md5(cuerpo.encode()).hexdigest()

    for nombre, txt in (('el cuerpo del pegado', cuerpo), ('las pruebas', pruebas)):
        malos = re.findall(r'\b\d{5,}\b', re.sub(r'\b(19|20)\d\d\b', '', sin_comentarios(txt)))
        if malos:
            sys.exit('[ABORTA] %s trae numeros de 5 cifras o mas: %s. El repo es PUBLICO.'
                     % (nombre, malos[:8]))

    cab = (
"-- SOLO ENSAYO · PRUEBAS_PAGO_ASISTENTE.sql · termina en ROLLBACK, no deja nada\n"
"-- ════════════════════════════════════════════════════════════════════════\n"
"-- ENSAYO · el cierre de planta en cinco tramos · CON EL PEGADO 11 ADENTRO\n"
"-- GENERADO por herramientas/ensayos/armar_ensayo_pago_asistente.py — no editar a mano:\n"
"-- se regenera y se pierde. Para cambiar las pruebas, editar\n"
"-- herramientas/ensayos/pruebas_pago_asistente_cuerpo.sql y volver a correrlo.\n"
"--\n"
"-- ⚠️ ADENTRO VA EL CUERPO REAL DE PERSONAL_PAGO_ASISTENTE.sql, extraido del\n"
"-- archivo por estructura (sin su fila de control, que taparia la tabla de\n"
"-- veredictos). md5 del cuerpo extraido: " + md5c + "\n"
"--\n"
"-- ⚠️ NECESITA EL PEGADO 10 YA APLICADO. Usa `pago_obligatorio`,\n"
"-- `rrhh_feriado_paga_doble()`, `rrhh_es_dia_descontable()` y\n"
"-- `rrhh_neto_quincena`, que los crea PERSONAL_NETO_QUINCENA.sql. Contra una base\n"
"-- sin el 10 falla en la primera linea, y esta bien que falle.\n"
"--\n"
"-- ⚠️ TERMINA EN `rollback;`. El cierre de planta vuelve a ser UNA fila del\n"
"-- 18-dic al 11-ene, como estaba. No deja ni una fila ni un objeto.\n"
"--\n"
"-- ⚠️ TOCA UNA FILA QUE YA EXISTE, y es el unico ensayo del modulo que lo hace:\n"
"-- encoge el cierre de planta sembrado por PERSONAL_CALENDARIO.sql. El rollback\n"
"-- lo devuelve, pero si la corrida se cortara a la mitad hay que verificar que el\n"
"-- cierre siga entero — la consulta esta al final del archivo.\n"
"--\n"
"-- ⚠️ LOS MONTOS SON INVENTADOS: 1200 y 1100, elegidos redondos para que el valor\n"
"-- del dia salga exacto (1200÷12 y 1100÷11 = 100). No se parecen a ningun sueldo.\n"
"-- ════════════════════════════════════════════════════════════════════════\n"
"\n"
"begin;\n"
"\n"
"-- ╔══════════════════════════════════════════════════════════════════════╗\n"
"-- ║  CUERPO DE PERSONAL_PAGO_ASISTENTE.sql — pegado tal cual               ║\n"
"-- ╚══════════════════════════════════════════════════════════════════════╝\n")

    med = ("\n-- ╔══════════════════════════════════════════════════════════════════════╗\n"
           "-- ║  FIN DEL CUERPO DEL PEGADO · desde aca, las PRUEBAS                    ║\n"
           "-- ╚══════════════════════════════════════════════════════════════════════╝\n\n")

    pie = ("\nrollback;\n\n"
"-- ── DESPUES DEL ROLLBACK ────────────────────────────────────────────────\n"
"-- El cierre tiene que haber vuelto a ser UNA sola fila, y no tiene que quedar\n"
"-- nada del ensayo:\n"
"--   select (select count(*) from rrhh_feriado\n"
"--            where fecha between date '2026-12-18' and date '2027-01-11') as tramos,\n"
"--          (select count(*) from rrhh_feriado where creado_por = 'pegado-11')  as del_pegado,\n"
"--          (select count(*) from rrhh_persona where creado_por = 'ensayo-cierre') as personas,\n"
"--          (select count(*) from rrhh_permiso where creado_por = 'ensayo-cierre') as permisos,\n"
"--          (select count(*) from information_schema.tables where table_schema='public'\n"
"--            and table_name = 'zz_res')                                      as sobras;\n"
"--   -- ESPERADO: 1 · 0 · 0 · 0 · 0\n"
"--\n"
"-- ⚠️ Si `tramos` no da 1, el rollback NO corrio y el cierre quedo partido en la\n"
"-- base de verdad. En ese caso NO pegar nada mas y avisar.\n")

    salida = cab + cuerpo + med + pruebas + pie
    open(SALIDA, 'w', encoding='utf-8').write(salida)

    l = [x.strip() for x in sin_comentarios(salida).splitlines() if x.strip()]
    print('cuerpo del pegado : %d lineas · md5 %s' % (len(cuerpo.splitlines()), md5c))
    print('pruebas           : %d lineas' % len(pruebas.splitlines()))
    print('PRUEBAS_PAGO_ASISTENTE.sql: %d bytes · %d lineas'
          % (len(salida.encode()), len(salida.splitlines())))
    print('begin %d · commit %d · rollback %d · ultima sentencia %r'
          % (l.count('begin;'), l.count('commit;'), l.count('rollback;'), l[-1]))
    if l.count('commit;') or l.count('rollback;') != 1 or l[-1] != 'rollback;':
        sys.exit('[ABORTA] el archivo generado no cierra en un unico rollback.')
    print('✓ generado')

if __name__ == '__main__':
    main()
