-- ═══════════════════════════════════════════════════════════════════════════
-- ENTREGAS_VALIDACION_ODOO.sql  ·  30-sep-2026  ·  NO SE CORRIÓ TODAVÍA
-- El RASTRO del carril de escritura (fase 1): quién validó en Odoo, desde
-- Truefie, qué albarán, de qué pedido y cuándo.
--
-- ⚠️ Este encabezado se cambia a "APLICADO" SOLO después de ver la fila de
--    control del final con los números esperados. Un "Success" no vale.
--
-- QUÉ CREA
--   ent_odoo_validacion — append-only: se inserta y se lee; no se edita ni se
--   borra (sin grant de update/delete). Una fila por albarán validado.
--   La escribe el servidor del carril (escritura/servidor.py) CON EL TOKEN DE LA
--   SOCIA que tocó el botón, así que la base decide, no el servidor:
--     · solo una socia (acceso_es_socia());
--     · y solo con SU nombre: validado_por = el correo del token.
--   anon no tiene ningún grant (memoria "anon: grants pendientes").
--
-- ANTES: correr ENSAYO_VALIDACION_ODOO.sql. Tiene que dar todas las filas ok.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$ begin
  if to_regclass('public.ent_odoo_validacion') is not null then
    raise exception 'ent_odoo_validacion ya existe: este archivo no se vuelve a pegar';
  end if;
end $$;

-- ▼▼▼ BLOQUE DDL (el ensayo lo repite byte a byte) ▼▼▼
create table public.ent_odoo_validacion (
  id              bigint generated always as identity primary key,
  pedido_id       bigint not null references public.ent_pedido(id),
  factura_id      integer not null,
  picking_id      integer not null,
  picking_nombre  text not null check (length(btrim(picking_nombre)) > 0),
  lineas          jsonb not null check (jsonb_typeof(lineas) = 'array' and jsonb_array_length(lineas) > 0),
  validado_por    text not null,
  validado_en     timestamptz not null default now(),
  constraint ent_odoo_validacion_picking_un unique (picking_id)
);
create index ent_odoo_validacion_pedido_idx on public.ent_odoo_validacion (pedido_id);

alter table public.ent_odoo_validacion enable row level security;
revoke all on public.ent_odoo_validacion from anon, authenticated;
grant select, insert on public.ent_odoo_validacion to authenticated;

create policy ent_odoo_validacion_sel on public.ent_odoo_validacion
  for select to authenticated using (true);
create policy ent_odoo_validacion_ins on public.ent_odoo_validacion
  for insert to authenticated
  with check (acceso_es_socia() and validado_por = (auth.jwt() ->> 'email'));
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

-- CONTROL, adentro de la transacción y antes del commit.
select (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname = 'ent_odoo_validacion' and c.relrowsecurity) as tabla_con_rls,
       (select count(*) from pg_policy where polrelid = 'public.ent_odoo_validacion'::regclass) as politicas,
       (select count(*) from information_schema.role_table_grants
         where table_name = 'ent_odoo_validacion' and grantee = 'anon') as grants_anon,
       (select string_agg(privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
         where table_name = 'ent_odoo_validacion' and grantee = 'authenticated') as grants_authenticated;
-- ESPERADO: 1 · 2 · 0 · INSERT,SELECT

commit;
