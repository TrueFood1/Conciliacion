-- ═══════════════════════════════════════════════════════════════════════════
-- PROD_ORDEN_ODOO.sql  ·  4-nov-2026  ·  El rastro de las órdenes de producción creadas desde Truefie
-- ⛔ NO SE CORRIÓ. Lo pega Andrea en el editor SQL de Supabase. El header y la bitácora se tocan DESPUÉS de
--    verificar (la fila de control de abajo, y desde afuera con pg_lector), nunca antes.
-- Para saber si está aplicado, mirar la base: `select to_regclass('public.prod_orden_odoo')`.
--
-- QUÉ HACE
--   Una tabla append-only (nadie edita ni borra: solo SELECT e INSERT):
--
--   prod_orden_odoo   qué orden de producción (mrp.production, EN BORRADOR) creó el séptimo carril del servicio
--                     de escritura (POST /produccion, rama carril-produccion) para qué producto, lote y fecha, con
--                     la huella de la vista previa que vio la socia, la merma y el sobrante con su unidad, el
--                     desecho (stock.scrap en borrador) y los adjuntos (nombre, tipo, sha256 y bytes; el contenido
--                     queda en Odoo, no acá). Si algo falló DESPUÉS de crear la orden, la fila va igual, con
--                     `problema` escrito: sin ella, otro clic la crearía de nuevo.
--
--   El servicio la lee antes de crear (`ordenes_registradas`): una orden del mismo producto y lote, ±40 días, que
--   no esté cancelada en Odoo, frena con 409 «orden_repetida» aunque su chatter no tenga el lote.
--
--   Los CHECK repiten las cercas del servidor (los seis terminados, lote 1–999, batches 1–50, unidades
--   u/paquete/desconocida, hasta 7 adjuntos): si un error de código las saltara, la base no lo acepta.
--
--   La insertan las socias CON SU TOKEN: la base exige socia y que `creado_por` sea el correo del token. La leen
--   solo las socias (el asistente no: ninguna política permisiva para él). El disparador `asistente_politicas`
--   (ASISTENTE_ROL.sql §7) le pone sus cuatro políticas restrictivas al crearla.
--
-- QUIÉN LA VA A LEER (regla de esquema_check: si el contador no sube, el esquema está muerto)
--   El servicio truefie-escritura (TruefieREST.ordenes_registradas / registrar_produccion), por REST: esquema_check
--   NO lo ve, porque mira el index.html. Lo ve recién cuando la pantalla «Órdenes de Producción» la consulte.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$ begin
  if to_regclass('public.prod_orden_odoo') is not null then
    raise exception 'prod_orden_odoo ya existe: este archivo no se vuelve a pegar';
  end if;
end $$;

create table public.prod_orden_odoo (
  id                bigint generated always as identity primary key,
  producto_id       integer not null constraint po_producto check (producto_id in (451, 452, 453, 503, 472, 519)),
  lote              integer not null constraint po_lote check (lote between 1 and 999),     -- el día juliano
  fecha             date not null,                                                         -- de producción, hora CR
  batches           integer not null constraint po_batches check (batches between 1 and 50),
  mo_id             integer not null unique constraint po_mo_id check (mo_id > 0),         -- mrp.production en Odoo
  mo_nombre         text constraint po_mo_nombre check (mo_nombre is null or mo_nombre ~ '^WH/MO/[0-9]{5}$'),
  premezcla_mos     text[] not null default '{}',
  merma_cantidad    numeric(10,2) not null default 0 constraint po_merma check (merma_cantidad >= 0),
  merma_unidad      text not null default 'u' constraint po_merma_unidad check (merma_unidad in ('u', 'paquete', 'desconocida')),
  sobrante_cantidad numeric(10,2) not null default 0 constraint po_sobrante check (sobrante_cantidad >= 0),
  sobrante_unidad   text not null default 'u' constraint po_sobrante_unidad check (sobrante_unidad in ('u', 'paquete', 'desconocida')),
  scrap_id          integer constraint po_scrap check (scrap_id is null or scrap_id > 0),  -- stock.scrap en borrador
  adjuntos          jsonb not null default '[]'::jsonb
                    constraint po_adjuntos check (jsonb_typeof(adjuntos) = 'array' and jsonb_array_length(adjuntos) <= 7),
  huella            text not null constraint po_huella check (length(huella) between 1 and 64),
  problema          text constraint po_problema check (problema is null or length(problema) <= 500),
  creado_por        text not null constraint po_creado_por check (length(btrim(creado_por)) > 0),
  creado_en         timestamptz not null default now()
);
create index prod_orden_odoo_producto_lote on public.prod_orden_odoo (producto_id, lote, fecha);

alter table public.prod_orden_odoo enable row level security;
revoke all on public.prod_orden_odoo from anon, authenticated;
grant select, insert on public.prod_orden_odoo to authenticated;

create policy prod_orden_odoo_sel on public.prod_orden_odoo
  for select to authenticated using (acceso_es_socia());
create policy prod_orden_odoo_ins on public.prod_orden_odoo
  for insert to authenticated with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));

-- CONTROL, adentro de la transacción y justo antes del commit. ESPERADO: una fila
--   1 · 2 · 4 · 0 · INSERT,SELECT · 14 · 1 · 0
--   (4 = las restrictivas del asistente que pone el disparador; si sale 0, el disparador no está y hay que avisar
--    ANTES de seguir. 14 = los CHECK con nombre po_*. 1 = el unique de mo_id. 0 = filas.)
--   Si el editor dice «Success. No rows returned», NO corrió hasta acá.
select (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname = 'prod_orden_odoo' and c.relrowsecurity) as tabla_con_rls,
       (select count(*) from pg_policy where polrelid = 'public.prod_orden_odoo'::regclass and polpermissive) as politicas_propias,
       (select count(*) from pg_policy where polrelid = 'public.prod_orden_odoo'::regclass and not polpermissive) as restrictivas_asistente,
       (select count(*) from information_schema.role_table_grants
         where table_name = 'prod_orden_odoo' and grantee = 'anon') as grants_anon,
       (select string_agg(distinct privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
         where table_name = 'prod_orden_odoo' and grantee = 'authenticated') as grants_authenticated,
       (select count(*) from pg_constraint where conrelid = 'public.prod_orden_odoo'::regclass and contype = 'c'
         and conname like 'po\_%') as checks,
       (select count(*) from pg_constraint where conrelid = 'public.prod_orden_odoo'::regclass and contype = 'u') as unicos,
       (select count(*) from public.prod_orden_odoo) as filas;
commit;
