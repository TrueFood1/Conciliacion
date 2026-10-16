#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
armar_ensayo_neto.py — arma PRUEBAS_NETO_QUINCENA.sql pegando el CUERPO REAL del
pegado 10 seguido de las pruebas, todo en una transaccion que termina en ROLLBACK.

POR QUE EXISTE (camino A). Un ensayo que prueba "lo mismo que el pegado" escrito
a mano prueba una COPIA, y la copia se desincroniza: se arregla el pegado y el
ensayo sigue validando la version vieja — en verde. Aca el cuerpo se EXTRAE del
archivo que se va a pegar, asi que lo que se prueba es byte a byte lo que entra.

COMO EXTRAE EL CUERPO
  Por ESTRUCTURA, no por numero de linea (regla de CLAUDE.md): el unico `begin;`
  y el unico `commit;` que estan solos en su linea. Aborta si no hay exactamente
  uno de cada, y aborta si el cuerpo trae un `rollback` adentro.

LO QUE EL ENSAYO SI PRUEBA DEL PEGADO, por venir el cuerpo de verdad:
  · que el `do $candado$` pase — es el mismo candado, con el divisor medido
    contra el calendario real de la base;
  · que las cuatro funciones de regla devuelvan lo que dicen;
  · que las tres vistas reescritas compilen y den los montos esperados;
  · que el trigger del feriado trabajado rechace lo que no califica.

LO QUE NO PRUEBA, y conviene decirlo: los GRANTS y el `revoke ... from anon` se
aplican igual, pero el rollback los deshace. Que `anon` no llegue se prueba en la
fila 33, llamando de verdad como anon dentro de la misma transaccion — ahi si vale.

NO PRUEBA TAMPOCO los montos reales: el ensayo usa netos ficticios redondos
(1100 y 1200). El cuadre contra lo que Lorena transfiere de verdad va aparte, en
PEGADO_NETO_QUINCENA.sql, que NO entra al repo.

USO
    python3 herramientas/ensayos/armar_ensayo_neto.py
    -> escribe PRUEBAS_NETO_QUINCENA.sql en la raiz del repo
"""
import os, sys, re, hashlib

RAIZ   = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PEGADO = os.path.join(RAIZ, 'PERSONAL_NETO_QUINCENA.sql')
CUERPO = os.path.join(RAIZ, 'herramientas', 'ensayos', 'pruebas_neto_cuerpo.sql')
SALIDA = os.path.join(RAIZ, 'PRUEBAS_NETO_QUINCENA.sql')

def sin_comentarios(txt):
    t = re.sub(r'--[^\n]*', '', txt)
    return re.sub(r"'(?:[^']|'')*'", "''", t)

def cuerpo_del_pegado(path):
    lineas = open(path, encoding='utf-8').read().splitlines()
    b = [i for i, l in enumerate(lineas) if l.strip() == 'begin;']
    c = [i for i, l in enumerate(lineas) if l.strip() == 'commit;']
    if len(b) != 1 or len(c) != 1:
        sys.exit('[ABORTA] el pegado tiene %d `begin;` y %d `commit;`; tiene que haber '
                 'exactamente uno de cada. No se extrae a ciegas.' % (len(b), len(c)))
    if b[0] > c[0]:
        sys.exit('[ABORTA] el `commit;` esta antes del `begin;`.')
    cuerpo = '\n'.join(lineas[b[0] + 1:c[0]])
    limpio = sin_comentarios(cuerpo)
    if re.search(r'\brollback\b', limpio, re.I):
        sys.exit('[ABORTA] el cuerpo del pegado trae un `rollback`.')
    if re.search(r'^\s*(begin|commit)\s*;', limpio, re.I | re.M):
        sys.exit('[ABORTA] quedo un begin/commit dentro del cuerpo extraido.')
    return cuerpo

def main():
    cuerpo  = cuerpo_del_pegado(PEGADO)
    pruebas = open(CUERPO, encoding='utf-8').read()
    md5c    = hashlib.md5(cuerpo.encode()).hexdigest()

    # NINGUN MONTO REAL, NI EN EL PEGADO NI EN LAS PRUEBAS. El repo es PUBLICO.
    # Se buscan numeros de 5 cifras o mas, descontando los años.
    for nombre, txt in (('el cuerpo del pegado', cuerpo), ('las pruebas', pruebas)):
        sospechosos = re.findall(r'\b\d{5,}\b', re.sub(r'\b(19|20)\d\d\b', '', sin_comentarios(txt)))
        if sospechosos:
            sys.exit('[ABORTA] %s trae numeros de 5 cifras o mas: %s. El repo es PUBLICO y '
                     'no va ni un salario real.' % (nombre, sospechosos[:8]))

    cab = (
"-- SOLO ENSAYO · PRUEBAS_NETO_QUINCENA.sql · termina en ROLLBACK, no deja nada\n"
"-- ════════════════════════════════════════════════════════════════════════\n"
"-- ENSAYO · neto fijo de quincena · CON EL PEGADO 10 ADENTRO\n"
"-- GENERADO por herramientas/ensayos/armar_ensayo_neto.py — NO editar a mano:\n"
"-- se regenera y se pierde. Para cambiar las pruebas, editar\n"
"-- herramientas/ensayos/pruebas_neto_cuerpo.sql y volver a correrlo.\n"
"--\n"
"-- ⚠️ ADENTRO VA EL CUERPO REAL DE PERSONAL_NETO_QUINCENA.sql, extraido del\n"
"-- archivo por estructura (el unico begin; y el unico commit;, sin incluirlos).\n"
"-- md5 del cuerpo extraido: " + md5c + "\n"
"-- O sea que esto NO prueba una copia: prueba byte a byte lo que se va a pegar.\n"
"-- Un ensayo que valida una copia se desincroniza en silencio — se arregla el\n"
"-- pegado, el ensayo sigue validando lo viejo, y da verde.\n"
"--\n"
"-- ⚠️ TERMINA EN `rollback;`. Crea y deshace TODO: las dos tablas nuevas, la\n"
"-- columna pago_obligatorio, las cuatro funciones, las tres vistas reescritas,\n"
"-- los parametros nuevos y los datos ficticios. No deja ni una fila ni un objeto.\n"
"--\n"
"-- ⚠️ LOS MONTOS SON INVENTADOS. Netos ficticios 1100 y 1200, elegidos redondos\n"
"-- para que el valor del dia salga exacto (1100÷11 = 100, 1200÷12 = 100,\n"
"-- 1100÷10 = 110) y cada esperado se verifique a mano. No se parecen a ningun\n"
"-- sueldo de nadie. El cuadre contra lo que Lorena transfiere de verdad va en\n"
"-- PEGADO_NETO_QUINCENA.sql, que no entra al repo porque el repo es PUBLICO.\n"
"--\n"
"-- ⚠️ CUENTAS Y PERSONAS FICTICIAS, con correos @example.invalid (un TLD que la\n"
"-- RFC 2606 reserva y que no puede existir). No depende de ninguna cuenta real y\n"
"-- no escribe nada a nombre de ninguna persona de verdad.\n"
"--\n"
"-- ⚠️ TRES FILAS DEPENDEN DE REGLAS SIN CONFIRMAR y pueden cambiar de esperado\n"
"-- cuando contesten: la 10 (una ausencia sobre un feriado no descuenta — es una\n"
"-- suposicion de Andrea), las 13/16/19 (el patrono paga el 50% los primeros 3\n"
"-- dias de incapacidad) y la 23 (un feriado obligatorio en sabado no suma). Van\n"
"-- marcadas «SIN CONFIRMAR» o «PENDIENTE» en el texto de cada escenario.\n"
"-- ════════════════════════════════════════════════════════════════════════\n"
"\n"
"begin;\n"
"\n"
"-- ╔══════════════════════════════════════════════════════════════════════╗\n"
"-- ║  CUERPO DE PERSONAL_NETO_QUINCENA.sql — pegado tal cual              ║\n"
"-- ╚══════════════════════════════════════════════════════════════════════╝\n")

    med = ("\n-- ╔══════════════════════════════════════════════════════════════════════╗\n"
           "-- ║  FIN DEL CUERPO DEL PEGADO · desde aca, las PRUEBAS                   ║\n"
           "-- ╚══════════════════════════════════════════════════════════════════════╝\n\n")

    pie = ("\nrollback;\n\n"
"-- ── DESPUES DEL ROLLBACK ────────────────────────────────────────────────\n"
"-- No tiene que quedar NADA, ni datos ni esquema. Las siete en una sola corrida:\n"
"--   select (select count(*) from acceso_usuario where nota = 'ensayo-neto')        as cuentas,\n"
"--          (select count(*) from rrhh_persona  where creado_por = 'ensayo-neto')   as personas,\n"
"--          (select count(*) from rrhh_permiso  where creado_por = 'ensayo-neto')   as permisos,\n"
"--          (select count(*) from rrhh_feriado  where creado_por = 'ensayo-neto')   as feriados,\n"
"--          (select count(*) from information_schema.tables where table_schema='public'\n"
"--            and table_name in ('rrhh_neto_quincena','rrhh_feriado_trabajado'))    as tablas,\n"
"--          (select count(*) from pg_proc where proname like 'rrhh_es_dia%'\n"
"--            or proname in ('rrhh_dias_divisor','rrhh_feriado_paga_doble','zz_n','zz_pago')) as funciones,\n"
"--          (select count(*) from information_schema.columns where table_schema='public'\n"
"--            and table_name='rrhh_feriado' and column_name='pago_obligatorio')     as columna;\n"
"--   -- ESPERADO: 0 · 0 · 0 · 0 · 0 · 0 · 0\n"
"--\n"
"-- ⚠️ Si `columna` o `tablas` dan distinto de 0, el rollback NO corrio y el\n"
"-- esquema quedo a medias. En ese caso NO pegar nada mas y avisar.\n")

    salida = cab + cuerpo + med + pruebas + pie
    open(SALIDA, 'w', encoding='utf-8').write(salida)

    l = [x.strip() for x in sin_comentarios(salida).splitlines() if x.strip()]
    print('cuerpo del pegado   : %d lineas · md5 %s' % (len(cuerpo.splitlines()), md5c))
    print('pruebas             : %d lineas' % len(pruebas.splitlines()))
    print('PRUEBAS_NETO_QUINCENA.sql: %d bytes · %d lineas'
          % (len(salida.encode()), len(salida.splitlines())))
    print('begin %d · commit %d · rollback %d · ultima sentencia %r'
          % (l.count('begin;'), l.count('commit;'), l.count('rollback;'), l[-1]))
    if l.count('commit;') or l.count('rollback;') != 1 or l[-1] != 'rollback;':
        sys.exit('[ABORTA] el archivo generado no cierra en un unico rollback.')
    pr = len(re.findall(r'^insert into zz_res', pruebas, re.M)) \
       + len(re.findall(r'^\s+insert into zz_res values', pruebas, re.M))
    print('inserts a la tabla de resultados: %d' % pr)
    print('✓ generado')

if __name__ == '__main__':
    main()
