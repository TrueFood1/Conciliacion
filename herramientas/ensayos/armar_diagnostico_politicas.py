#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
armar_diagnostico_politicas.py — arma DIAGNOSTICO_POLITICAS_ENSAYO.sql: corre el
cuerpo del pegado 10 dentro de una transaccion, lista TODAS las politicas de las
dos tablas nuevas antes y despues, y termina en rollback.

POR QUE EXISTE. El candado del pegado dijo «hay 14 politicas, tenian que ser 4» y
abortó, asi que la lista nunca se vio. Leyendo el archivo las politicas son
CUATRO —las conte a mano, y ninguna version del pegado uso otros nombres—, asi
que la lectura no explica el 14 y hay que mirarlo corriendo.

⚠️ ESTE ARCHIVO SACA EL CANDADO, Y ESO LO VUELVE INUTIL COMO PRUEBA.
Es un diagnostico, no un ensayo de aceptacion: muestra lo que hay y se va. Que
corra «bien» NO dice que el pegado se pueda aplicar. Para eso esta
PRUEBAS_NETO_QUINCENA.sql, que lleva el candado entero.

El candado se saca POR ESTRUCTURA (el unico `do $candado$` y su cierre), y el
generador verifica que lo unico que se quito sea ese bloque: reconstruye el
cuerpo original juntando las dos partes y compara md5. Si no coincide, aborta.

USO
    python3 herramientas/ensayos/armar_diagnostico_politicas.py
"""
import os, sys, re, hashlib

RAIZ   = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PEGADO = os.path.join(RAIZ, 'PERSONAL_NETO_QUINCENA.sql')
SALIDA = os.path.join(RAIZ, 'DIAGNOSTICO_POLITICAS_ENSAYO.sql')
TABLAS = "'rrhh_neto_quincena','rrhh_feriado_trabajado'"
DECLARADAS = ("'rrhh_neto_quincena_sel','rrhh_neto_quincena_ins',"
              "'rrhh_feriado_trabajado_sel','rrhh_feriado_trabajado_ins'")

def cuerpo_sin_candado(path):
    txt = open(path, encoding='utf-8').read()
    L = txt.splitlines()
    b = [i for i, l in enumerate(L) if l.strip() == 'begin;']
    c = [i for i, l in enumerate(L) if l.strip() == 'commit;']
    if len(b) != 1 or len(c) != 1 or b[0] > c[0]:
        sys.exit('[ABORTA] el pegado no tiene exactamente un begin; y un commit;.')
    cuerpo = L[b[0] + 1:c[0]]
    ini = [i for i, l in enumerate(cuerpo) if l.strip() == 'do $candado$']
    if len(ini) != 1:
        sys.exit('[ABORTA] encontre %d `do $candado$`; tenia que ser 1. No se corta a '
                 'ciegas.' % len(ini))
    fin = [i for i, l in enumerate(cuerpo) if i > ini[0] and l.strip() == '$candado$;']
    if not fin:
        sys.exit('[ABORTA] el `do $candado$` no tiene cierre `$candado$;`.')
    j = fin[0]
    quitado = cuerpo[ini[0]:j + 1]
    resto   = cuerpo[:ini[0]] + cuerpo[j + 1:]
    # Lo unico que se saco es ese bloque: se reconstruye y se compara.
    rearmado = cuerpo[:ini[0]] + quitado + cuerpo[j + 1:]
    if hashlib.md5('\n'.join(rearmado).encode()).hexdigest() != \
       hashlib.md5('\n'.join(cuerpo).encode()).hexdigest():
        sys.exit('[ABORTA] al sacar el candado se movio algo mas. No se publica un '
                 'diagnostico que no sea el pegado menos el candado.')
    # Y la fila de control del pegado tambien sale: devuelve otro resultado y el
    # editor de Supabase muestra solo el ultimo.
    k = [i for i, l in enumerate(resto) if l.strip().startswith('-- ── 9 · LA FILA DE CONTROL')]
    if len(k) == 1:
        resto = resto[:k[0]]
    return '\n'.join(resto), '\n'.join(quitado)

def main():
    cuerpo, candado = cuerpo_sin_candado(PEGADO)
    limpio = re.sub(r"'(?:[^']|'')*'", "''", re.sub(r'--[^\n]*', '', cuerpo))
    if re.search(r'\b(commit|rollback)\b', limpio, re.I):
        sys.exit('[ABORTA] quedo un commit o un rollback dentro del cuerpo.')
    if re.search(r'do\s+\$candado\$', cuerpo):
        sys.exit('[ABORTA] el candado sigue adentro.')

    cab = """-- SOLO DIAGNOSTICO · DIAGNOSTICO_POLITICAS_ENSAYO.sql · termina en ROLLBACK
-- ════════════════════════════════════════════════════════════════════════
-- ⚠️ ESTE ARCHIVO NO ES UNA PRUEBA, Y NO SIRVE PARA DECIDIR SI PEGAR.
-- Le SACARON EL CANDADO a proposito: el candado aborta antes de poder mostrar la
-- lista de politicas, que es justamente lo que hay que ver. Que esto corra «bien»
-- no dice nada sobre si el pegado 10 se puede aplicar. Para eso esta
-- PRUEBAS_NETO_QUINCENA.sql, que lo lleva entero.
--
-- QUE HACE. Dentro de UNA transaccion: saca una foto de las politicas que hay
-- hoy en las dos tablas nuevas, corre el cuerpo del pegado 10 (sin el candado y
-- sin su fila de control), vuelve a sacar la foto, muestra las dos juntas y
-- DESHACE TODO con un rollback. No deja ni una tabla, ni una politica, ni una fila.
--
-- GENERADO por herramientas/ensayos/armar_diagnostico_politicas.py — no editar a
-- mano. El cuerpo del pegado va byte a byte: el generador reconstruye el original
-- juntando lo que saco con lo que dejo y compara md5, asi que lo unico que falta
-- es el candado y nada mas.
--
-- COMO LEER LA TABLA QUE SALE:
--   · `momento` = «1 · ANTES» son las politicas que YA ESTABAN en la base. Si no
--     sale ninguna fila de ANTES, las tablas no existian y todo lo que aparezca
--     en DESPUES lo creo el pegado.
--   · `cuantas_en_este_momento` repite el total de ese momento. El numero de
--     DESPUES es el que el candado compara contra 4.
--   · `la_declara_el_pegado` dice si esa politica es una de las cuatro que el
--     pegado escribe. Un «NO» en DESPUES es una regla de seguridad que salio de
--     otro lado.
--   · ⚠️ `permisiva_o_restrictiva`: las PERMISIVAS del mismo comando se SUMAN
--     (basta que una diga si), las RESTRICTIVAS se exigen todas. Una permisiva de
--     mas ABRE la puerta.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- LA FOTO DE ANTES. Tabla normal y no temporal: las mediciones de abajo no
-- cambian de rol, pero una tabla creada dentro de la transaccion se borra con el
-- rollback igual que una temporal, y sin depender del esquema temporal.
create table zz_antes as
select p.tablename::text as tabla, p.policyname::text as politica,
       p.cmd::text as comando, p.permissive::text as permisiva,
       array_to_string(p.roles, ', ') as roles,
       coalesce(p.qual, '—') as cond_leer,
       coalesce(p.with_check, '—') as cond_escribir
  from pg_policies p
 where p.schemaname = 'public' and p.tablename in (__TABLAS__);

-- Y si las tablas existian o no, que es distinto de «no tenian politicas».
create table zz_antes_tablas as
select t.tabla::text as tabla,
       (select count(*) from pg_class k join pg_namespace n on n.oid = k.relnamespace
         where k.relname = t.tabla and n.nspname = 'public' and k.relkind = 'r') as existia
  from (values ('rrhh_neto_quincena'), ('rrhh_feriado_trabajado')) as t(tabla);


-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  CUERPO DE PERSONAL_NETO_QUINCENA.sql, SIN EL CANDADO                ║
-- ╚══════════════════════════════════════════════════════════════════════╝
"""
    med = """

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  FIN DEL CUERPO · desde aca, la lista                                 ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- Un solo resultado, porque el editor de Supabase muestra nada mas el ultimo.
select 0                                         as orden,
       '0 · existia la tabla?'                   as momento,
       t.tabla                                   as tabla,
       case when t.existia > 0 then 'LA TABLA YA EXISTIA en public'
            else 'la tabla NO existia' end       as politica,
       '—'::text as comando, '—'::text as permisiva_o_restrictiva,
       '—'::text as roles, '—'::text as condicion_para_leer,
       '—'::text as condicion_para_escribir,
       '—'::text as la_declara_el_pegado,
       null::bigint                              as cuantas_en_este_momento
  from zz_antes_tablas t

union all

select 1, '1 · ANTES del pegado', a.tabla, a.politica, a.comando, a.permisiva,
       a.roles, a.cond_leer, a.cond_escribir,
       case when a.politica in (__DECLARADAS__) then 'si' else 'NO' end,
       count(*) over (partition by 1)
  from zz_antes a

union all

select 2, '2 · DESPUES del pegado', p.tablename::text, p.policyname::text,
       p.cmd::text, p.permissive::text,
       array_to_string(p.roles, ', '),
       coalesce(p.qual, '—'), coalesce(p.with_check, '—'),
       case when p.policyname in (__DECLARADAS__) then 'si' else 'NO' end,
       count(*) over (partition by 2)
  from pg_policies p
 where p.schemaname = 'public' and p.tablename in (__TABLAS__)

 order by 1, 3, 5, 4;

rollback;

-- ── DESPUES DEL ROLLBACK ────────────────────────────────────────────────
-- No tiene que quedar nada. En una sola corrida:
--   select (select count(*) from information_schema.tables where table_schema='public'
--            and table_name in ('rrhh_neto_quincena','rrhh_feriado_trabajado',
--                               'zz_antes','zz_antes_tablas'))                as tablas,
--          (select count(*) from information_schema.columns where table_schema='public'
--            and table_name='rrhh_feriado' and column_name='pago_obligatorio') as columna;
--   -- ESPERADO: 0 · 0
"""
    salida = (cab + cuerpo + med).replace('__TABLAS__', TABLAS).replace('__DECLARADAS__', DECLARADAS)
    open(SALIDA, 'w', encoding='utf-8').write(salida)

    l = [x.strip() for x in re.sub(r"'(?:[^']|'')*'", "''",
            re.sub(r'--[^\n]*', '', salida)).splitlines() if x.strip()]
    print('cuerpo sin candado : %d lineas' % len(cuerpo.splitlines()))
    print('candado quitado    : %d lineas · md5 %s'
          % (len(candado.splitlines()), hashlib.md5(candado.encode()).hexdigest()))
    print('create policy en el archivo: %d  (tienen que ser 4)'
          % len(re.findall(r'^create policy', salida, re.M)))
    print('%s: %d bytes · %d lineas' % (os.path.basename(SALIDA),
          len(salida.encode()), len(salida.splitlines())))
    print('begin %d · commit %d · rollback %d · ultima sentencia %r'
          % (l.count('begin;'), l.count('commit;'), l.count('rollback;'), l[-1]))
    if l.count('commit;') or l.count('rollback;') != 1 or l[-1] != 'rollback;':
        sys.exit('[ABORTA] el archivo generado no cierra en un unico rollback.')
    print('✓ generado')

if __name__ == '__main__':
    main()
