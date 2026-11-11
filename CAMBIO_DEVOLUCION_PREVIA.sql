-- ═══════════════════════════════════════════════════════════════════════════
-- CAMBIO_DEVOLUCION_PREVIA.sql  ·  11-nov-2026  ·  APLICADO en producción por Andrea (11-nov)
-- ✅ Control 2 · 1 · YES · 2 · 1 · 0. Verificado desde afuera (pg_lector): 2 columnas, pedido_id
--    NULL-able, check ent_devolucion_origen_ok, las dos vistas con security_invoker=true, 1
--    devolución vigente y 0 excesos como antes; REST con la anon key lee factura_id (200).
-- Devoluciones de entregas ANTERIORES A TRUEFIE: la devolucion cuelga de una
-- FACTURA de Odoo en vez de una entrega (ent_pedido).
--
-- EL CASO: Megasuper Escazu devuelve el 11-nov producto de la factura 3287 (Odoo
-- 36280, 11-may-2026). Esa entrega es de antes de Truefie: no tiene pedido ni
-- lotes en ent_alisto_lote, y `ent_devolucion.pedido_id` es NOT NULL. Sin esto
-- Daniel no tiene donde registrarla, y el producto (que se reempaca con 9 meses
-- para venderlo a restaurantes) quedaria en el congelador sin existir para el saldo.
--
-- QUE CAMBIA (medido contra produccion el 11-nov con pg_lector):
--   1. ent_devolucion.pedido_id pasa a NULL-able, y se agregan factura_id y
--      factura_nombre. Un CHECK exige EXACTAMENTE UNO de los dos origenes:
--      o pedido (como hoy) o factura (la previa). Las 2 filas que hay (ids 12 y
--      68) tienen pedido y no factura: pasan el check.
--   2. ent_devolucion_vigente agrega factura_id y factura_nombre AL FINAL (las
--      vistas que dependen de ella nombran columnas: no cambian).
--   3. v_ent_devolucion_exceso deja afuera las previas. Compara lo que volvio
--      contra lo que SALIO en ent_alisto_lote, y una previa no tiene salida en
--      Truefie: sin este filtro TODA previa saldria marcada como exceso. El tope
--      de una previa se mira en pantalla, contra las lineas de la factura de Odoo.
--   ent_devuelto_desde_ancla (la cuarta punta del saldo) y ent_reemplazo_desde_ancla NO cambian: suma por
--   (producto, lote) sin mirar el origen, que es justo lo que se quiere (las dos nombran columnas).
--   ent_odoo_pendiente (la NC) NO cambia: pedido_id ya es NULL-able y su CHECK de
--   'nota_credito' pide devolucion_id + factura_id + cliente_id, que la previa trae.
--   ent_anular_pedido NO cambia: busca devoluciones POR pedido_id, y una previa
--   no tiene pedido que anular.
--
-- CONTROL (la ultima fila antes del commit). ESPERADO:
--   2 · 1 · YES · 2 · 1 · 0
-- Si el editor dice "Success. No rows returned", no llego al final y no vale.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$ begin
  if exists (select 1 from information_schema.columns
             where table_name='ent_devolucion' and column_name='factura_id') then
    raise exception 'ent_devolucion.factura_id ya existe: este archivo no se vuelve a pegar';
  end if;
end $$;

alter table public.ent_devolucion alter column pedido_id drop not null;
alter table public.ent_devolucion
  add column factura_id     integer check (factura_id > 0),
  add column factura_nombre text;
alter table public.ent_devolucion add constraint ent_devolucion_origen_ok check (
     (pedido_id is not null and factura_id is null and factura_nombre is null)
  or (pedido_id is null and factura_id is not null
      and coalesce(length(btrim(factura_nombre)), 0) > 0));

create or replace view public.ent_devolucion_vigente with (security_invoker = true) as
 select d.id as devolucion_id,
    d.fecha,
    d.recibido_en,
    d.cliente_id,
    d.cliente_nombre,
    d.nota,
    d.creado_en,
    d.creado_por,
    d.pedido_id,
    d.causa,
    d.resolucion,
    d.factura_id,
    d.factura_nombre
   from public.ent_devolucion d
  where not (exists ( select 1
           from public.ent_anulacion x
          where x.entidad = 'devolucion'::text and x.entidad_id = d.id));

create or replace view public.v_ent_devolucion_exceso with (security_invoker = true) as
 with salio as (
         select av.pedido_id,
            li.producto_id,
            al.lote,
            sum(al.cant_uds) as uds_salio
           from public.ent_alisto_vigente av
             join public.ent_alisto_linea li on li.alisto_id = av.alisto_id
             join public.ent_alisto_lote al on al.linea_id = li.id
          group by av.pedido_id, li.producto_id, al.lote
        ), volvio as (
         select dv.pedido_id,
            dl.producto_id,
            dl.lote,
            sum(dl.cant_uds) as uds_volvio
           from public.ent_devolucion_vigente dv
             join public.ent_devolucion_linea dl on dl.devolucion_id = dv.devolucion_id
          where dv.pedido_id is not null
          group by dv.pedido_id, dl.producto_id, dl.lote
        )
 select v.pedido_id,
    v.producto_id,
    v.lote,
    v.uds_volvio,
    coalesce(s.uds_salio, 0::numeric) as uds_salio,
    v.uds_volvio - coalesce(s.uds_salio, 0::numeric) as uds_exceso
   from volvio v
     left join salio s on s.pedido_id = v.pedido_id and s.producto_id = v.producto_id and s.lote = v.lote
  where v.uds_volvio > coalesce(s.uds_salio, 0::numeric);

-- CONTROL · ESPERADO: 2 · 1 · YES · 2 · 1 · 0
select (select count(*) from information_schema.columns
         where table_name='ent_devolucion' and column_name in ('factura_id','factura_nombre')) as columnas_nuevas,
       (select count(*) from pg_constraint where conname='ent_devolucion_origen_ok') as check_nuevo,
       (select is_nullable from information_schema.columns
         where table_name='ent_devolucion' and column_name='pedido_id') as pedido_nullable,
       (select count(*) from information_schema.columns
         where table_name='ent_devolucion_vigente' and column_name in ('factura_id','factura_nombre')) as vigente_factura,
       (select count(*) from pg_views where viewname='v_ent_devolucion_exceso'
         and definition ilike '%pedido_id IS NOT NULL%') as exceso_sin_previas,
       (select count(*) from public.ent_devolucion where pedido_id is null) as previas_todavia;

commit;
