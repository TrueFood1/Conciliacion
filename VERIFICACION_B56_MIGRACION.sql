-- ══ A · ¿existen los objetos que crea ENTREGAS_INDETERMINADO.sql?
select t.nombre, t.clase,
       coalesce((select count(*) from information_schema.tables i
                  where i.table_schema='public' and i.table_name=t.nombre),0) as existe
  from (values ('ent_alisto_lote_correccion','tabla'),
               ('ent_alisto_lote_efectivo','vista'),
               ('v_ent_indeterminado_pendiente','vista')) as t(nombre, clase)
 order by t.nombre;

-- ══ A2 · el trigger del freno y los checks nuevos.
select tgname as trigger from pg_trigger
 where tgrelid = 'ent_alisto_lote_correccion'::regclass and not tgisinternal;

-- ══ A3 · las columnas nuevas de ent_alisto_lote y el check del motivo.
select conname, convalidated from pg_constraint
 where conrelid = 'ent_alisto_lote'::regclass and contype = 'c'
 order by conname;

-- ══ B · ¿LA MIGRACION LANDO? Cuantas filas de correccion hay y de que tipo.
select lote, motivo, count(*) as filas, min(creado_por) as firma
  from ent_alisto_lote_correccion
 group by lote, motivo
 order by lote, motivo;

-- ══ C1 · PREGUNTA 3 · el conteo EXACTO DE FILAS (no de grupos) de la tabla BASE
--    que no pasarian el candado. Es lo que mide el paso 1 de CANDADO_FORMA.
select count(*) as filas_totales_invalidas
  from ent_alisto_lote alt
 where alt.lote !~ '^\d{1,3} / \d{1,2}-\d{2}$'
   and alt.lote <> 'NO DETERMINADO';

-- ══ C2 · y el desglose fila por fila, para que no quede duda de cual es cual.
select alt.id as alisto_lote_id, a.pedido_id, ali.producto_id,
       '[' || alt.lote || ']' as cadena_exacta, alt.cant_uds,
       (select count(*) from ent_alisto_lote_correccion c
         where c.alisto_lote_id = alt.id) as tiene_correccion
  from ent_alisto_lote alt
  join ent_alisto_linea ali on ali.id = alt.linea_id
  join ent_alisto a on a.id = ali.alisto_id
 where alt.lote !~ '^\d{1,3} / \d{1,2}-\d{2}$'
   and alt.lote <> 'NO DETERMINADO'
 order by a.pedido_id, alt.id;

-- ══ D · PREGUNTA 1 · lo que dice la VISTA EFECTIVA. Si aca sale 'sin lote', la
--    migracion no llego. Si sale NO DETERMINADO, llego y lo que viste era el
--    paso 1 (la consulta previa, que lee la tabla base a proposito).
select al.lote, count(*) as filas, sum(al.cant_uds) as uds_individuales
  from ent_alisto_lote_efectivo al
 where al.lote !~ '^\d{1,3} / \d{1,2}-\d{2}$'
 group by al.lote
 order by al.lote;
