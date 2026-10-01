-- ═══════════════════════════════════════════════════════════════════════════
-- ENTREGAS_DESCARTE_ODOO.sql  ·  1-oct-2026  ·  APLICADO (1-oct-2026)
-- ✅ Pegado por Andrea en Supabase producción el 1-oct, después del ensayo
--    (ENSAYO_DESCARTE_ODOO.sql: 11 de 11 ok = true, con el texto esperado en
--    cada rechazo). Fila de control vista: 1 · 2 · 0 · INSERT,SELECT.
--    NO SE VUELVE A PEGAR (y si se pega, frena solo: la tabla ya existe).
-- «Descartar» en «No se pueden validar» (Pendientes › Validar entrega en Odoo).
--
-- ⚠️ Este encabezado se cambia a "APLICADO" SOLO después de ver la fila de
--    control del final con los números esperados. Un "Success" no vale.
--
-- QUÉ CREA
--   ent_pedido_odoo_descarte — append-only: se inserta y se lee; no se edita
--   ni se borra (sin grant de update/delete). Una fila = una socia sacó UN
--   pedido de la lista «No se pueden validar», tal como estaba en Odoo en ese
--   momento.
--   · `huella`: el estado de Odoo que se descartó (factura, si está revertida,
--     cada salida con su estado y, si el servidor lo rechazó, el motivo y las
--     cantidades). La pantalla esconde el pedido mientras la huella de HOY sea
--     igual a una descartada. Si en Odoo cambia la factura o la salida, la
--     huella cambia y el pedido VUELVE solo. Nada se borra para que vuelva.
--   · `motivo`: lo que la pantalla decía al descartar, para leerlo después.
--   · quién (`creado_por`) y cuándo (`creado_en`). La base exige socia y que
--     el nombre sea el del token: la firma no se elige.
--   anon no tiene ningún grant (memoria "anon: grants pendientes").
--
-- ANTES: correr ENSAYO_DESCARTE_ODOO.sql. Tiene que dar las 11 filas ok.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$ begin
  if to_regclass('public.ent_pedido_odoo_descarte') is not null then
    raise exception 'ent_pedido_odoo_descarte ya existe: este archivo no se vuelve a pegar';
  end if;
end $$;

-- ▼▼▼ BLOQUE DDL (el ensayo lo repite byte a byte) ▼▼▼
create table public.ent_pedido_odoo_descarte (
  id          bigint generated always as identity primary key,
  pedido_id   bigint not null references public.ent_pedido(id),
  huella      text not null check (length(btrim(huella)) > 0),
  motivo      text,
  creado_por  text not null,
  creado_en   timestamptz not null default now(),
  constraint ent_pedido_odoo_descarte_un unique (pedido_id, huella)
);

alter table public.ent_pedido_odoo_descarte enable row level security;
revoke all on public.ent_pedido_odoo_descarte from anon, authenticated;
grant select, insert on public.ent_pedido_odoo_descarte to authenticated;

create policy ent_pedido_odoo_descarte_sel on public.ent_pedido_odoo_descarte
  for select to authenticated using (true);
create policy ent_pedido_odoo_descarte_ins on public.ent_pedido_odoo_descarte
  for insert to authenticated
  with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

-- CONTROL, adentro de la transacción y antes del commit.
select (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname = 'ent_pedido_odoo_descarte' and c.relrowsecurity) as tabla_con_rls,
       (select count(*) from pg_policy where polrelid = 'public.ent_pedido_odoo_descarte'::regclass) as politicas,
       (select count(*) from information_schema.role_table_grants
         where table_name = 'ent_pedido_odoo_descarte' and grantee = 'anon') as grants_anon,
       (select string_agg(privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
         where table_name = 'ent_pedido_odoo_descarte' and grantee = 'authenticated') as grants_authenticated;
-- ESPERADO: 1 · 2 · 0 · INSERT,SELECT

commit;
