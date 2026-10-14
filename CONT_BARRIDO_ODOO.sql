-- ═══════════════════════════════════════════════════════════════════════════
-- CONT_BARRIDO_ODOO.sql · 14-oct-2026 · el rastro del barrido mensual de 1103030
-- ⚠️ SIN PEGAR. Va antes de encender BARRIDO_ENCENDIDO, con su ensayo en rollback.
--
-- Sexto carril del servicio de escritura (truefie-escritura, rama `barrido-1103030`):
-- POST /barrido {mes} deja UNA fila por mes barrido, insertada CON EL TOKEN de la
-- socia (como compra_tarifa_odoo). La fila es además el segundo candado contra barrer
-- dos veces el mismo mes (el primero es el asiento en Odoo con la misma referencia).
--
-- Las 5 políticas del asistente y el RLS los pone la base sola (event triggers
-- `asistente_politicas` y `ensure_rls`): acá NO se escriben (42710, 14-oct). Se
-- comprueban en el control: 2 propias + 5 del asistente = 7.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ═══ DDL · DESDE ACA (ENSAYO_CONT_BARRIDO_ODOO.sql copia este bloque tal cual) ═══

do $$ begin
  if to_regclass('public.cont_barrido_odoo') is not null then
    raise exception 'cont_barrido_odoo ya existe: este archivo no se vuelve a pegar';
  end if;
end $$;

create table public.cont_barrido_odoo (
  id              bigint generated always as identity primary key,
  mes             text not null check (mes ~ '^\d{4}-(0[1-9]|1[0-2])$' and mes >= '2026-10'),
  asiento_id      integer not null check (asiento_id > 0),          -- account.move en Odoo
  asiento_nombre  text not null check (length(btrim(asiento_nombre)) > 0),
  fecha           date not null,                                     -- el último día del mes
  lineas          integer not null check (lineas > 0),              -- residuos barridos
  monto           numeric(14,2) not null,                            -- neto a 6106022 (puede ser negativo)
  excluidos       integer not null default 0 check (excluidos >= 0),  -- más que el umbral: a mano
  huella          text not null check (length(huella) between 1 and 64),
  creado_por      text not null,
  creado_en       timestamptz not null default now(),
  constraint cont_barrido_odoo_mes_un unique (mes)
);

alter table public.cont_barrido_odoo enable row level security;   -- ya lo hizo ensure_rls
revoke all on public.cont_barrido_odoo from anon, authenticated;
grant select, insert on public.cont_barrido_odoo to authenticated;

create policy cont_barrido_odoo_sel on public.cont_barrido_odoo
  for select to authenticated using (acceso_es_socia());
create policy cont_barrido_odoo_ins on public.cont_barrido_odoo
  for insert to authenticated
  with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));

-- ═══ DDL · HASTA ACA ═══

-- CONTROL, adentro de la transacción y justo antes del commit.
select (select relrowsecurity from pg_class where oid = 'public.cont_barrido_odoo'::regclass)        as rls,
       (select count(*) from pg_policy where polrelid = 'public.cont_barrido_odoo'::regclass)        as politicas,
       (select count(*) from information_schema.role_table_grants
         where table_name = 'cont_barrido_odoo' and grantee = 'anon')                               as grants_anon,
       (select string_agg(distinct privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
         where table_name = 'cont_barrido_odoo' and grantee = 'authenticated')                      as grants_authenticated;
-- ESPERADO: true · 7 · 0 · INSERT,SELECT
commit;

-- ═══ ESTA ES LA TABLA QUE VAS A VER · ya con el commit hecho ═══
select (select relrowsecurity from pg_class where oid = 'public.cont_barrido_odoo'::regclass)        as rls,
       (select count(*) from pg_policy where polrelid = 'public.cont_barrido_odoo'::regclass)        as politicas,
       (select count(*) from information_schema.role_table_grants
         where table_name = 'cont_barrido_odoo' and grantee = 'anon')                               as grants_anon,
       (select string_agg(distinct privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
         where table_name = 'cont_barrido_odoo' and grantee = 'authenticated')                      as grants_authenticated;
-- ESPERADO: true · 7 · 0 · INSERT,SELECT
