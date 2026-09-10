-- MEDICIONES previas a ENTREGAS_EXCEPCIONES_LINEA.sql
-- Solo lectura. Se corre con:
--     python3 herramientas/pg_lector.py --clave --archivo MEDICION_EXCEPCIONES.sql
-- OJO al editar: pg_lector parte el archivo por el punto y coma, asi que
-- ningun comentario puede llevar uno.

-- M1 · los objetos del 8-sep estan aplicados de verdad, no citados
select c.relname as objeto,
       case c.relkind when 'r' then 'tabla' when 'v' then 'vista' else c.relkind::text end as clase
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public'
   and c.relname in ('ent_alisto_lote_correccion','ent_alisto_lote_efectivo',
                     'v_ent_indeterminado_pendiente','acceso_usuario',
                     'ent_alisto_linea','ent_conteo_linea','ent_pedido_valida')
 order by c.relname;

-- M2 · los dos candados del 8-sep sobre ent_alisto_lote, y si estan validados
select conname, convalidated
  from pg_constraint
 where conrelid = 'ent_alisto_lote'::regclass
   and conname in ('ent_alisto_lote_lote_forma','ent_alisto_lote_motivo_ok')
 order by conname;

-- M3 · acceso_es_socia() existe. La politica RLS nueva la llama
select p.proname, pg_get_function_result(p.oid) as devuelve, p.prosecdef as security_definer
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('acceso_es_socia','acceso_perfil')
 order by p.proname;

-- M4 · hay socias activas que puedan autorizar. SIN correos, solo el conteo
select perfil, count(*) as personas
  from v_acceso_usuario where activo group by perfil order by perfil;

-- M5 · las columnas de ent_alisto_linea que toca el CHECK nuevo
select column_name, data_type, is_nullable, column_default
  from information_schema.columns
 where table_schema = 'public' and table_name = 'ent_alisto_linea'
 order by ordinal_position;

-- M6 · 0a · cuantas lineas de alisto hay, y cuantas tienen cant_uom nula
select count(*) as lineas_totales,
       count(*) filter (where cant_uom is null) as sin_cant_uom,
       count(*) filter (where cant_uds = 0)     as en_cero
  from ent_alisto_linea;

-- M7 · 0b · el CHECK de §4 va VALID solo si esto da CERO
select count(*) as conteo_lineas_indeterminado
  from ent_conteo_linea where lote = 'NO DETERMINADO';

-- M8 · 0c · el candado de FORMA de ent_conteo_linea, que va DESPUES y aparte
select count(*) as filas_invalidas, count(distinct lote) as cadenas_distintas
  from ent_conteo_linea
 where lote !~ '^\d{1,3} / \d{1,2}-\d{2}$' and lote <> 'NO DETERMINADO';

-- M9 · 0d · y cuales son exactamente, para no decidir a ciegas
select id, conteo_id, producto_id, '[' || lote || ']' as cadena_exacta, uds
  from ent_conteo_linea
 where lote !~ '^\d{1,3} / \d{1,2}-\d{2}$' and lote <> 'NO DETERMINADO'
 order by conteo_id, id;

-- M10 · el ancla vigente HOY. Es la foto contra la que se mide todo lo demas
select id, fecha, (corte at time zone 'America/Costa_Rica') as corte_cr
  from ent_ancla;

-- M11 · el ANTES de la verificacion 7f: cuantos pendientes ve la vista vieja
select count(*) as indeterminado_pendiente_hoy from v_ent_indeterminado_pendiente;

-- M12 · el balde del alisto hoy, en unidad de VENTA
with pres(producto_id, nombre, div, rotulo) as (values
  (451,'Pan Blanco',      1, 'unidades'),
  (452,'Pan de Semillas', 1, 'unidades'),
  (453,'Pan Frances',     4, 'paquetes'),
  (472,'Pizza Crust',     2, 'paquetes'),
  (503,'Buns',            4, 'paquetes'),
  (519,'Galletas',        1, 'unidades'))
select pres.nombre as producto, s.lote,
       round(sum(s.uds) / pres.div, 3) as cantidad, pres.rotulo as unidad
  from ent_salido_del_congelador_desde_ancla s
  join pres on pres.producto_id = s.producto_id
 where s.lote = 'NO DETERMINADO'
 group by pres.nombre, pres.rotulo, pres.div, s.lote
 order by pres.nombre;

-- M13 · las siete filas historicas de forma invalida en ent_alisto_lote, para
--       confirmar que el candado NOT VALID del 8-sep no dejo entrar nuevas
select count(*) as filas_invalidas, count(distinct lote) as cadenas_distintas
  from ent_alisto_lote
 where lote !~ '^\d{1,3} / \d{1,2}-\d{2}$' and lote <> 'NO DETERMINADO';
