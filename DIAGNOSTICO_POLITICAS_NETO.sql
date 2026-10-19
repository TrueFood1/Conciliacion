-- SOLO LECTURA · DIAGNOSTICO_POLITICAS_NETO.sql
-- ════════════════════════════════════════════════════════════════════════
-- QUE HAY HOY EN LAS DOS TABLAS NUEVAS DEL PEGADO 10
-- Una sola consulta. Ni un insert, ni un update, ni un delete, ni un drop:
-- solo lee pg_class, pg_namespace y pg_policies. No toca nada.
--
-- PARA QUE: el candado del pegado 10 se planto diciendo «hay N politicas en las
-- dos tablas nuevas, tenian que ser 4». Esto muestra CUALES son, para saber que
-- sobra y de donde salio.
--
-- COMO LEERLA:
--   · una fila por politica. Si una tabla no tiene ninguna, igual sale una fila
--     con «(ninguna)»: las tablas sin politica no se pueden esconder;
--   · `total_que_cuenta_el_candado` repite en todas las filas el mismo numero, y
--     es exactamente el que el candado compara contra 4;
--   · `permisiva_o_restrictiva` importa mas de lo que parece. Las PERMISIVAS del
--     mismo comando se SUMAN (basta que una diga si), las RESTRICTIVAS se
--     exigen todas. Una permisiva de mas ABRE la puerta; no la cierra.
-- ════════════════════════════════════════════════════════════════════════

select t.tabla                                              as tabla,
       coalesce(c.esquema, '—')                              as esquema,
       case when c.esquema is null              then 'NO EXISTE'
            when c.esquema <> 'public'          then 'existe en OTRO esquema'
            when c.rls                          then 'existe · RLS prendida'
            else                                     'existe · RLS APAGADA' end
                                                            as estado_de_la_tabla,
       coalesce(p.policyname, '(ninguna)')                   as politica,
       coalesce(p.cmd, '—')                                  as comando,
       coalesce(p.permissive, '—')                           as permisiva_o_restrictiva,
       coalesce(array_to_string(p.roles, ', '), '—')         as roles,
       coalesce(p.qual, '—')                                 as condicion_para_leer,
       coalesce(p.with_check, '—')                           as condicion_para_escribir,
       count(p.policyname) over ()                           as total_que_cuenta_el_candado
  from (values ('rrhh_neto_quincena'), ('rrhh_feriado_trabajado')) as t(tabla)
  -- La tabla se busca en TODOS los esquemas, no solo en public: «no existe» y
  -- «existe en otro lado» son dos respuestas distintas y la segunda explicaria
  -- por que las politicas no aparecen donde se las espera.
  left join lateral (
    select n.nspname as esquema, k.relrowsecurity as rls
      from pg_class k join pg_namespace n on n.oid = k.relnamespace
     where k.relname = t.tabla and k.relkind = 'r'
     order by (n.nspname = 'public') desc, n.nspname
     limit 1) c on true
  left join pg_policies p
    on p.schemaname = coalesce(c.esquema, 'public') and p.tablename = t.tabla
 order by t.tabla, p.cmd nulls first, p.policyname;
