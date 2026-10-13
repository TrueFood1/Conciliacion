-- ═══════════════════════════════════════════════════════════════════════════
-- COMPRA_TARIFA_ODOO.sql  ·  12-oct-2026  ·  Tarifas de BIO que se mantienen solas desde Truefie
-- ✅ APLICADO el 12-oct-2026 por Andrea en producción, después del ensayo 18/18. Fila de control:
--    1 tabla con RLS · 2 políticas · 0 grants a anon · INSERT,SELECT a authenticated · 1 índice.
--    VERIFICADO desde afuera: REST con la anon key → 42501 (existe y anon no entra). NO VOLVER A CORRER.
-- Para saber si está aplicado, mirar la base: `select to_regclass('public.compra_tarifa_odoo')`.
--
-- QUÉ HACE
--   Una tabla append-only (nadie edita ni borra; RLS sin update/delete):
--
--   compra_tarifa_odoo  el RASTRO del cuarto carril del servicio de escritura (POST /tarifas):
--                       qué tarifa de proveedor de BIO (product.supplierinfo) se cambió en Odoo,
--                       de qué precio a qué precio, con qué factura de BIO como testigo, quién
--                       y cuándo. Una fila por tarifa cambiada.
--
--   motivo  'correccion_inicial'  el atraso histórico, UNA vez por tarifa (índice único parcial):
--                                 se aplica al encender el carril, con ensayo en seco aprobado.
--           'factura_nueva'       la tarjeta de Compras, cuando entra una factura con otro precio.
--   Sin ninguna fila 'correccion_inicial' del proveedor, el servidor no deja aplicar la tarjeta
--   y no le devuelve líneas: la tarjeta nunca muestra el atraso histórico (Andrea, 12-oct).
--
--   La banda de cordura (0,5× a 2×) también está acá, como CHECK: el servidor ya no aplica
--   nada fuera de banda, y si un error de código lo intentara, el rastro no lo acepta.
--
--   Se inserta CON EL TOKEN DE LA USUARIA (como compra_pedido_odoo): la base exige socia y que
--   `creado_por` sea el correo del token. La leen solo las socias (los precios de compra no
--   son para todo el equipo). El servicio no tiene llave propia de Supabase.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$ begin
  if to_regclass('public.compra_tarifa_odoo') is not null then
    raise exception 'compra_tarifa_odoo ya existe: este archivo no se vuelve a pegar';
  end if;
end $$;

create table public.compra_tarifa_odoo (
  id               bigint generated always as identity primary key,
  motivo           text not null check (motivo in ('correccion_inicial', 'factura_nueva')),
  proveedor_id     integer not null check (proveedor_id > 0),
  supplierinfo_id  integer not null check (supplierinfo_id > 0),     -- la tarifa en Odoo
  producto_tmpl_id integer not null check (producto_tmpl_id > 0),
  producto         text not null check (length(btrim(producto)) > 0),
  unidad           text,                                             -- la de compra del insumo (kg)
  precio_antes     numeric(14,4) not null check (precio_antes > 0),
  precio_nuevo     numeric(14,4) not null check (precio_nuevo > 0),
  factura_id       integer not null check (factura_id > 0),          -- la factura de BIO testigo
  factura_nombre   text not null check (length(btrim(factura_nombre)) > 0),
  factura_fecha    date,
  linea_id         integer not null check (linea_id > 0),            -- su línea (account.move.line)
  huella           text not null check (length(huella) between 1 and 64),   -- la de la vista previa
  creado_por       text not null,
  creado_en        timestamptz not null default now(),
  constraint compra_tarifa_odoo_cambia check (precio_nuevo <> precio_antes),
  constraint compra_tarifa_odoo_banda check (precio_nuevo between precio_antes * 0.5 and precio_antes * 2)
);
-- La corrección inicial, una sola vez por tarifa.
create unique index compra_tarifa_odoo_inicial_un on public.compra_tarifa_odoo (supplierinfo_id)
  where motivo = 'correccion_inicial';

alter table public.compra_tarifa_odoo enable row level security;
revoke all on public.compra_tarifa_odoo from anon, authenticated;
grant select, insert on public.compra_tarifa_odoo to authenticated;

create policy compra_tarifa_odoo_sel on public.compra_tarifa_odoo
  for select to authenticated using (acceso_es_socia());
create policy compra_tarifa_odoo_ins on public.compra_tarifa_odoo
  for insert to authenticated
  with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));

-- Verificación: 1 tabla con RLS · 2 políticas · 0 grants a anon · INSERT,SELECT a authenticated · 1 índice único parcial
select (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname = 'compra_tarifa_odoo' and c.relrowsecurity) as tabla_con_rls,
       (select count(*) from pg_policy where polrelid = 'public.compra_tarifa_odoo'::regclass) as politicas,
       (select count(*) from information_schema.role_table_grants
         where table_name = 'compra_tarifa_odoo' and grantee = 'anon') as grants_anon,
       (select string_agg(distinct privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
         where table_name = 'compra_tarifa_odoo' and grantee = 'authenticated') as grants_authenticated,
       (select count(*) from pg_indexes where tablename = 'compra_tarifa_odoo'
         and indexname = 'compra_tarifa_odoo_inicial_un') as indice_inicial;
commit;
