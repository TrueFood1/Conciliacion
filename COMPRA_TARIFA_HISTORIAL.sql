-- ═══════════════════════════════════════════════════════════════════════════
-- COMPRA_TARIFA_HISTORIAL.sql  ·  21-oct-2026  ·  Tarifas que se actualizan solas (opción A, umbral 25 %)
-- ⛔ NO APLICADO. Lo autoriza una socia después de ver el ensayo en seco de la revisión diaria.
--    Probado en Postgres local (espejo del respaldo del 21-oct): ENSAYO_COMPRA_TARIFA_HISTORIAL.sql
--    todo ok, y este archivo + DESHACER_COMPRA_TARIFA_HISTORIAL.sql de ida y vuelta.
-- Para saber si está aplicado, mirar la base: `select to_regclass('public.compra_tarifa_historial')`.
--
-- QUÉ HACE
--   compra_tarifa_historial  el historial propio de Truefie de cada cambio de tarifa de proveedor
--                            (product.supplierinfo) que hace el servicio de escritura: producto,
--                            proveedor, precio anterior y nuevo, la factura de origen y la ANTERIOR
--                            con la que se comparó, fecha, y si fue automático o con clic. Odoo no
--                            guarda ese historial. Append-only: nadie edita ni borra.
--
--   origen 'automatico'  la revisión diaria: la última factura cambia hasta 25 % contra la factura
--                        ANTERIOR del mismo proveedor y producto. La base lo vuelve a exigir (CHECK):
--                        sin factura anterior, o con más de 25 %, no entra.
--          'clic'        la tarjeta de Compras (más de 25 %, o sin factura anterior). Si hay anterior,
--                        la banda de cordura 0,5×–2× se mide contra ella, NO contra la tarifa vigente:
--                        así entra el azúcar (₡1.871 → ₡823,01 = 0,44× de la tarifa, 0 % de la anterior).
--
--   QUIÉN ESCRIBE
--     · clic: la socia, con SU token (como compra_tarifa_odoo): creado_por = su correo.
--     · automático: un rol propio, `truefie_tarifa_auto`, que SOLO puede insertar filas 'automatico'
--       firmadas 'revision-automatica' y leer la fila compras_config de plan_config. Se crea NOLOGIN:
--       entra recién cuando una socia pega, aparte, la línea `alter role … login password 'SCRAM…'`
--       (la revisión diaria corre en GitHub Actions, decisión de Andrea 22-oct).
--     · lo leen solo las socias (precios de compra). Instinct, por las políticas automáticas.
--
--   Las 5 políticas del asistente y el RLS los pone sola la base al crear la tabla (event triggers
--   asistente_politicas y ensure_rls): este archivo NO las escribe y las CUENTA en el control.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$ begin
  if to_regclass('public.compra_tarifa_historial') is not null then
    raise exception 'compra_tarifa_historial ya existe: este archivo no se vuelve a pegar';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'truefie_tarifa_auto') then
    create role truefie_tarifa_auto nologin noinherit;
  end if;
end $$;

create table public.compra_tarifa_historial (
  id               bigint generated always as identity primary key,
  origen           text not null check (origen in ('automatico', 'clic')),
  proveedor_id     integer not null check (proveedor_id > 0),
  supplierinfo_id  integer not null check (supplierinfo_id > 0),     -- la tarifa en Odoo
  producto_tmpl_id integer not null check (producto_tmpl_id > 0),
  producto         text not null check (length(btrim(producto)) > 0),
  unidad           text,                                             -- la de la tarifa (kg, g, carton 30…)
  precio_antes     numeric(14,4) not null check (precio_antes > 0),
  precio_nuevo     numeric(14,4) not null check (precio_nuevo > 0),
  factura_id       integer not null check (factura_id > 0),          -- la factura de origen (account.move)
  factura_nombre   text not null check (length(btrim(factura_nombre)) > 0),
  factura_fecha    date,
  linea_id         integer not null check (linea_id > 0),            -- su línea (account.move.line)
  anterior_id      integer check (anterior_id > 0),                  -- la factura ANTERIOR, si hubo
  anterior_nombre  text check (length(btrim(anterior_nombre)) > 0),
  precio_anterior  numeric(14,4) check (precio_anterior > 0),        -- en la unidad de la tarifa
  huella           text not null check (length(huella) between 1 and 64),
  creado_por       text not null check (length(btrim(creado_por)) > 0),
  creado_en        timestamptz not null default now(),
  constraint compra_tarifa_historial_cambia check (precio_nuevo <> precio_antes),
  constraint compra_tarifa_historial_anterior check (
    (anterior_id is null) = (precio_anterior is null) and (anterior_id is null) = (anterior_nombre is null)),
  -- automático: hasta 25 % contra la factura anterior, que tiene que existir
  constraint compra_tarifa_historial_automatico check (
    origen <> 'automatico'
    or (precio_anterior is not null and precio_nuevo between precio_anterior * 0.75 and precio_anterior * 1.25)),
  -- clic: la banda de cordura, contra la factura anterior cuando la hay
  constraint compra_tarifa_historial_clic check (
    origen <> 'clic' or precio_anterior is null
    or precio_nuevo between precio_anterior * 0.5 and precio_anterior * 2)
);
create index compra_tarifa_historial_tarifa on public.compra_tarifa_historial (supplierinfo_id, creado_en desc);

alter table public.compra_tarifa_historial enable row level security;   -- ya lo prende ensure_rls; no estorba
revoke all on public.compra_tarifa_historial from anon, authenticated;
grant select, insert on public.compra_tarifa_historial to authenticated;
grant usage on schema public to truefie_tarifa_auto;
grant insert on public.compra_tarifa_historial to truefie_tarifa_auto;
-- La revisión diaria necesita saber qué insumos son de Compras: SOLO la fila compras_config (22-oct).
grant select on public.plan_config to truefie_tarifa_auto;
create policy plan_config_tarifa_auto on public.plan_config
  for select to truefie_tarifa_auto using (clave = 'compras_config');

create policy compra_tarifa_historial_sel on public.compra_tarifa_historial
  for select to authenticated using (acceso_es_socia());
create policy compra_tarifa_historial_clic on public.compra_tarifa_historial
  for insert to authenticated
  with check (acceso_es_socia() and origen = 'clic' and creado_por = (auth.jwt() ->> 'email'));
create policy compra_tarifa_historial_auto on public.compra_tarifa_historial
  for insert to truefie_tarifa_auto
  with check (origen = 'automatico' and creado_por = 'revision-automatica');

-- Control: 1 · 8 · 0 · INSERT,SELECT · INSERT · f · 1 · 1
--   tabla con RLS · políticas (5 automáticas del asistente + 3 propias) · grants a anon ·
--   grants a authenticated · grants a truefie_tarifa_auto · el rol entra (tiene que ser f) · índice ·
--   la política de lectura de compras_config
select (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname = 'compra_tarifa_historial' and c.relrowsecurity) as tabla_con_rls,
       (select count(*) from pg_policy where polrelid = 'public.compra_tarifa_historial'::regclass) as politicas,
       (select count(*) from information_schema.role_table_grants
         where table_name = 'compra_tarifa_historial' and grantee = 'anon') as grants_anon,
       (select string_agg(distinct privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
         where table_name = 'compra_tarifa_historial' and grantee = 'authenticated') as grants_authenticated,
       (select string_agg(distinct privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
         where table_name = 'compra_tarifa_historial' and grantee = 'truefie_tarifa_auto') as grants_auto,
       (select rolcanlogin from pg_roles where rolname = 'truefie_tarifa_auto') as rol_entra,
       (select count(*) from pg_indexes where tablename = 'compra_tarifa_historial'
         and indexname = 'compra_tarifa_historial_tarifa') as indice,
       (select count(*) from pg_policy where polrelid = 'public.plan_config'::regclass
         and polname = 'plan_config_tarifa_auto') as lee_compras_config;
commit;
