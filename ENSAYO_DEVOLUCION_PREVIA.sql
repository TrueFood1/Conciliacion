-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_DEVOLUCION_PREVIA.sql  ·  11-nov-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- ✅ CORRIDO en producción el 11-nov-2026 por Andrea: 9 de 9 ok = true (7, 8 y 9 con 23514).
--    Rollback verificado desde afuera (pg_lector): sin columnas de factura, pedido_id NOT NULL,
--    sin el check nuevo y cero filas de ensayo.
-- Aplica CAMBIO_DEVOLUCION_PREVIA.sql, lo prueba con filas de mentira y lo deshace
-- todo (rollback).
--
-- CÓMO SE LEE
--   Una tabla con TODAS las filas en ok = true (son 9). Un RECHAZA da ok solo si el
--   SQLSTATE es 23514 (check). Si el editor dice "Success. No rows returned", no
--   llegó al final y no vale.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE DDL (copia de CAMBIO_DEVOLUCION_PREVIA.sql, sin begin/commit ni el control) ▼▼▼
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
-- ▲▲▲ FIN DEL BLOQUE DDL ▲▲▲

create temp table _r (n int, prueba text, ok boolean, detalle text) on commit drop;

-- Lote de mentira que no existe en ningun lado: '999 / 1-27'. Producto Pan Blanco 451.
do $$
declare v_id bigint; v_pen bigint; v_estado text; v_ok boolean;
begin
  -- 1 · las devoluciones que ya existen siguen pasando el check
  insert into _r select 1, 'filas existentes pasan el check nuevo',
    not exists (select 1 from ent_devolucion
                 where not ((pedido_id is not null and factura_id is null and factura_nombre is null)
                         or (pedido_id is null and factura_id is not null))), '';

  -- 2 · una previa (factura, sin pedido) ENTRA
  insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, factura_id, factura_nombre,
                              causa, nota, resolucion, creado_por)
  values (current_date, 1224, 'ENSAYO', null, 36280, 'ENSAYO-3287', 'otro', 'ensayo previa', 'devolucion', 'ensayo')
  returning id into v_id;
  insert into _r values (2, 'previa con factura y sin pedido entra', v_id is not null, coalesce(v_id::text,''));

  insert into ent_devolucion_linea (devolucion_id, producto_id, lote, cant_uds, uom_id, uom_nombre, cant_uom, uom_factor)
  values (v_id, 451, '999 / 1-27', 19, 0, 'Unidades', 19, 1);

  -- 3 · suma al saldo (cuarta punta)
  insert into _r select 3, 'la previa suma en ent_devuelto_desde_ancla',
    coalesce((select uds from ent_devuelto_desde_ancla where producto_id=451 and lote='999 / 1-27'),0)=19, '';

  -- 4 · NO sale como exceso
  insert into _r select 4, 'la previa no sale en v_ent_devolucion_exceso',
    not exists (select 1 from v_ent_devolucion_exceso where lote='999 / 1-27'), '';

  -- 5 · la vigente trae la factura
  insert into _r select 5, 'ent_devolucion_vigente trae factura_nombre',
    exists (select 1 from ent_devolucion_vigente where devolucion_id=v_id and factura_nombre='ENSAYO-3287'), '';

  -- 6 · la alerta de NC entra sin pedido
  insert into ent_odoo_pendiente (tipo, pedido_id, devolucion_id, fecha, cliente_id, cliente_nombre,
                                  factura_id, factura_nombre, creado_por)
  values ('nota_credito', null, v_id, current_date, 1224, 'ENSAYO', 36280, 'ENSAYO-3287', 'ensayo')
  returning id into v_pen;
  insert into _r select 6, 'la NC pendiente de una previa entra y se ve en v_ent_odoo_pendiente',
    exists (select 1 from v_ent_odoo_pendiente where id=v_pen), '';

  -- 7 · RECHAZA sin pedido y sin factura
  begin
    insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, causa, nota, resolucion, creado_por)
    values (current_date, 1224, 'ENSAYO', null, 'otro', 'ensayo nada', 'devolucion', 'ensayo');
    insert into _r values (7, 'RECHAZA sin pedido ni factura', false, 'entró');
  exception when others then
    insert into _r values (7, 'RECHAZA sin pedido ni factura', sqlstate='23514', sqlstate);
  end;

  -- 8 · RECHAZA con pedido Y factura
  begin
    insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, factura_id, factura_nombre,
                                causa, nota, resolucion, creado_por)
    values (current_date, 1224, 'ENSAYO', 89, 36280, 'ENSAYO-3287', 'otro', 'ensayo las dos', 'devolucion', 'ensayo');
    insert into _r values (8, 'RECHAZA con pedido y factura a la vez', false, 'entró');
  exception when others then
    insert into _r values (8, 'RECHAZA con pedido y factura a la vez', sqlstate='23514', sqlstate);
  end;

  -- 9 · RECHAZA factura sin nombre
  begin
    insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, factura_id, factura_nombre,
                                causa, nota, resolucion, creado_por)
    values (current_date, 1224, 'ENSAYO', null, 36280, '  ', 'otro', 'ensayo sin nombre', 'devolucion', 'ensayo');
    insert into _r values (9, 'RECHAZA factura sin nombre', false, 'entró');
  exception when others then
    insert into _r values (9, 'RECHAZA factura sin nombre', sqlstate='23514', sqlstate);
  end;
end $$;

select n, prueba, ok, detalle from _r order by n;

rollback;
