-- ═══════════════════════════════════════════════════════════════════════════
-- ENTREGAS_TRASLADO_ODOO.sql  ·  1-oct-2026  ·  APLICADO (1-oct-2026)
-- ✅ Pegado por Andrea en Supabase producción el 1-oct, después del ensayo
--    (ENSAYO_TRASLADO_ODOO.sql: 14 de 14 ok = true, con el texto esperado en
--    cada rechazo). Fila de control vista: 1 · 2 · 5 · 0 · INSERT,SELECT.
--    NO SE VUELVE A PEGAR (y si se pega, frena solo: la tabla ya existe).
-- El RASTRO del traslado interno automático: quién creó en Odoo, desde Truefie,
-- qué traslado, de qué salida sin factura, a dónde y cuándo.
--
-- ⚠️ Este encabezado se cambia a "APLICADO" SOLO después de ver la fila de
--    control del final con los números esperados. Un "Success" no vale.
--
-- QUÉ CREA
--   ent_odoo_traslado — append-only: se inserta y se lee; no se edita ni se borra.
--   UNA fila por salida (unique pedido_id: nunca dos traslados para la misma
--   salida) y UNA por traslado de Odoo (unique picking_id).
--   Los CHECK repiten las decisiones de Andrea del 1-oct, para que la base las
--   sostenga aunque el servidor tuviera un error:
--     · motivo: regalia, degustacion, consumo_interno, reposicion;
--     · destino: [19] Mercadeo y Muestras o [16] Desecho;
--     · contacto: los genéricos 1260 a 1263.
--   La escribe el servidor del repo privado TrueFood1/truefie-escritura (POST
--   /trasladar) CON EL TOKEN DE LA SOCIA que tocó el botón: la base exige socia
--   y que `creado_por` sea el correo del token. anon no tiene ningún grant.
--
-- ANTES: correr ENSAYO_TRASLADO_ODOO.sql. Tiene que dar las 14 filas ok.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$ begin
  if to_regclass('public.ent_odoo_traslado') is not null then
    raise exception 'ent_odoo_traslado ya existe: este archivo no se vuelve a pegar';
  end if;
end $$;

-- ▼▼▼ BLOQUE DDL (el ensayo lo repite byte a byte) ▼▼▼
create table public.ent_odoo_traslado (
  id              bigint generated always as identity primary key,
  pedido_id       bigint not null references public.ent_pedido(id),
  picking_id      integer not null,
  picking_nombre  text not null check (length(btrim(picking_nombre)) > 0),
  motivo          text not null check (motivo in ('regalia','degustacion','consumo_interno','reposicion')),
  destino_id      integer not null check (destino_id in (16, 19)),
  contacto_id     integer not null check (contacto_id in (1260, 1261, 1262, 1263)),
  lineas          jsonb not null check (jsonb_typeof(lineas) = 'array' and jsonb_array_length(lineas) > 0),
  creado_por      text not null,
  creado_en       timestamptz not null default now(),
  constraint ent_odoo_traslado_pedido_un unique (pedido_id),
  constraint ent_odoo_traslado_picking_un unique (picking_id)
);

alter table public.ent_odoo_traslado enable row level security;
revoke all on public.ent_odoo_traslado from anon, authenticated;
grant select, insert on public.ent_odoo_traslado to authenticated;

create policy ent_odoo_traslado_sel on public.ent_odoo_traslado
  for select to authenticated using (true);
create policy ent_odoo_traslado_ins on public.ent_odoo_traslado
  for insert to authenticated
  with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

-- CONTROL, adentro de la transacción y antes del commit.
select (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname = 'ent_odoo_traslado' and c.relrowsecurity) as tabla_con_rls,
       (select count(*) from pg_policy where polrelid = 'public.ent_odoo_traslado'::regclass) as politicas,
       (select count(*) from pg_constraint where conrelid = 'public.ent_odoo_traslado'::regclass and contype = 'c') as checks,
       (select count(*) from information_schema.role_table_grants
         where table_name = 'ent_odoo_traslado' and grantee = 'anon') as grants_anon,
       (select string_agg(privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
         where table_name = 'ent_odoo_traslado' and grantee = 'authenticated') as grants_authenticated;
-- ESPERADO: 1 · 2 · 5 · 0 · INSERT,SELECT

commit;
