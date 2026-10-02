-- ═══════════════════════════════════════════════════════════════════════════
-- COMPRA_PEDIDO_ODOO.sql  ·  2-oct-2026  ·  T-28 · «Pedir a BIO» / «Registrar pedido»
-- ⚠ ESCRITO, NO PEGADO. Antes de pegar: correr ENSAYO_COMPRA_PEDIDO_ODOO.sql (no deja nada).
-- Para saber si está aplicado, mirar la base: `select to_regclass('public.compra_propuesta')`.
--
-- QUÉ HACE
--   Dos tablas, las dos append-only (nadie edita ni borra; RLS sin update/delete):
--
--   compra_propuesta    lo que la socia ARMÓ en la tarjeta "Pedido con día fijo": por
--                       línea, lo que calculó Truefie y lo que ella decidió pedir. Es lo
--                       ÚNICO que lee el servicio de escritura: el navegador no le manda
--                       cantidades, le manda el id de una fila de acá ({propuesta_id,
--                       confirmar}). Corregir = otra propuesta.
--   compra_pedido_odoo  el RASTRO: qué orden de compra se creó en Odoo desde Truefie, para
--                       qué propuesta, quién y cuándo. Una por propuesta, una por orden, y
--                       UNA por proveedor y día de entrega (no se pide dos veces lo mismo).
--
--   Las dos se insertan CON EL TOKEN DE LA USUARIA (como ent_odoo_traslado): la base exige
--   socia y que `creado_por` sea el correo del token. El servicio no tiene llave propia
--   de Supabase.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$ begin
  if to_regclass('public.compra_propuesta') is not null or to_regclass('public.compra_pedido_odoo') is not null then
    raise exception 'compra_propuesta / compra_pedido_odoo ya existen: este archivo no se vuelve a pegar';
  end if;
end $$;

create table public.compra_propuesta (
  id            bigint generated always as identity primary key,
  proveedor_id  integer not null check (proveedor_id > 0),
  proveedor     text,
  modo          text not null check (modo in ('pedir', 'registrar')),
  pedido_dia    date not null,                       -- P: cuándo se pidió / se pide
  entrega_dia   date not null,                       -- E: cuándo llega
  uso_dia       date,                                -- U: desde cuándo se puede usar (dato, no cerca)
  -- [{producto_id, nombre, uom, calculado, pedido, empaques, empaque_lab, empaque_peso, empaque_unidad}]
  -- `pedido` y `calculado` en la UoM DEL PRODUCTO (la de stock.quant: kg, o g la levadura).
  lineas        jsonb not null check (jsonb_typeof(lineas) = 'array' and jsonb_array_length(lineas) > 0),
  creado_por    text not null,
  creado_en     timestamptz not null default now(),
  constraint compra_propuesta_fechas check (entrega_dia >= pedido_dia and entrega_dia <= pedido_dia + 14)
);

create table public.compra_pedido_odoo (
  id            bigint generated always as identity primary key,
  propuesta_id  bigint not null references public.compra_propuesta(id),
  proveedor_id  integer not null check (proveedor_id > 0),
  entrega_dia   date not null,
  po_id         integer not null,
  po_nombre     text not null check (length(btrim(po_nombre)) > 0),
  lineas        jsonb not null check (jsonb_typeof(lineas) = 'array' and jsonb_array_length(lineas) > 0),
  creado_por    text not null,
  creado_en     timestamptz not null default now(),
  constraint compra_pedido_odoo_propuesta_un unique (propuesta_id),
  constraint compra_pedido_odoo_po_un unique (po_id),
  constraint compra_pedido_odoo_ciclo_un unique (proveedor_id, entrega_dia)
);

alter table public.compra_propuesta enable row level security;
alter table public.compra_pedido_odoo enable row level security;
revoke all on public.compra_propuesta, public.compra_pedido_odoo from anon, authenticated;
grant select, insert on public.compra_propuesta, public.compra_pedido_odoo to authenticated;

create policy compra_propuesta_sel on public.compra_propuesta
  for select to authenticated using (true);
create policy compra_propuesta_ins on public.compra_propuesta
  for insert to authenticated
  with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));
create policy compra_pedido_odoo_sel on public.compra_pedido_odoo
  for select to authenticated using (true);
create policy compra_pedido_odoo_ins on public.compra_pedido_odoo
  for insert to authenticated
  with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));

-- Verificación: 2 tablas con RLS · 4 políticas · 0 grants a anon · select,insert a authenticated
select (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname in ('compra_propuesta', 'compra_pedido_odoo') and c.relrowsecurity) as tablas_con_rls,
       (select count(*) from pg_policy where polrelid in ('public.compra_propuesta'::regclass, 'public.compra_pedido_odoo'::regclass)) as politicas,
       (select count(*) from information_schema.role_table_grants
         where table_name in ('compra_propuesta', 'compra_pedido_odoo') and grantee = 'anon') as grants_anon,
       (select string_agg(distinct privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
         where table_name in ('compra_propuesta', 'compra_pedido_odoo') and grantee = 'authenticated') as grants_authenticated;
commit;
