-- CALC_BORRADOR.sql — Borradores de la Calculadora de precios (Andrea, 2-nov-2026)
-- ESTADO: APLICADO por Andrea el 4-nov-2026 ~15:45 CR. Control 7 · 2 · 1 · t · INSERT,SELECT · 0; verificado desde afuera (calc_borrador 7 columnas, sel+ins, vista, 0 filas).
--
-- QUÉ ES
--   Un «borrador» es el escenario de la pestaña Precio tal como se dejó: lo que se cotiza, la
--   cadena, frío/anaquel, las condiciones escritas, nuestro margen o precio, el PVP y la ventana de
--   negociación. Se guarda para volver después. No es una receta (eso es calc_receta) ni las
--   condiciones de la cadena (plan_config `calc_condiciones`).
--
-- QUÉ TRAE
--   · `calc_borrador` ........ solo de inserción. Volver a guardar un borrador = otra fila con el
--       mismo `borrador` (uuid); archivarlo = otra fila con archivado = true. Gana la más reciente.
--   · `calc_borrador_vigente`  el último estado de cada borrador no archivado (security_invoker).
--   · RLS igual que calc_receta: leen y guardan solo socias, y la firma es la de la sesión.
--   · Sin UPDATE ni DELETE para anon/authenticated: nada se pisa ni se borra.
--
-- NO TOCA calc_receta, plan_config ni Odoo.
--
-- FILA DE CONTROL ESPERADA (adentro de la transacción, justo antes del commit):
--   7 · 2 · 1 · t · INSERT,SELECT · 0

begin;

create table public.calc_borrador (
  id          bigint generated always as identity primary key,
  borrador    uuid not null,
  nombre      text not null check (length(btrim(nombre)) between 1 and 120),
  datos       jsonb not null check (jsonb_typeof(datos) = 'object'),
  archivado   boolean not null default false,
  creado_por  text not null,
  creado_en   timestamptz not null default now()
);
comment on table public.calc_borrador is
  'Borradores de la pestaña Precio de la Calculadora. Solo de inserción: misma `borrador` = nueva versión; archivado = true lo saca de la lista. Solo socias.';
create index calc_borrador_ultimo on public.calc_borrador (borrador, creado_en desc, id desc);

alter table public.calc_borrador enable row level security;
create policy calc_borrador_sel on public.calc_borrador
  for select to authenticated using (acceso_es_socia());
create policy calc_borrador_ins on public.calc_borrador
  for insert to authenticated
  with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));

revoke all on public.calc_borrador from anon, authenticated;
grant select, insert on public.calc_borrador to authenticated;

create view public.calc_borrador_vigente with (security_invoker = true) as
  select u.id, u.borrador, u.nombre, u.datos, u.creado_por, u.creado_en
  from (select distinct on (borrador) *
          from public.calc_borrador
         order by borrador, creado_en desc, id desc) u
  where not u.archivado;
revoke all on public.calc_borrador_vigente from anon, authenticated;
grant select on public.calc_borrador_vigente to authenticated;

-- CONTROL: si el editor no muestra esta fila, la transacción no llegó hasta acá.
select (select count(*) from information_schema.columns where table_schema='public' and table_name='calc_borrador') as columnas,
       (select count(*) from pg_policies where tablename='calc_borrador' and policyname in ('calc_borrador_sel','calc_borrador_ins')) as politicas,
       (select count(*) from pg_views where schemaname='public' and viewname='calc_borrador_vigente') as vista,
       (select coalesce('security_invoker=true' = any(reloptions), false) from pg_class where oid='public.calc_borrador_vigente'::regclass) as invoker,
       (select string_agg(privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
         where table_name='calc_borrador' and grantee='authenticated') as permisos,
       (select count(*) from public.calc_borrador) as filas;
-- ESPERADO: 7 · 2 · 1 · t · INSERT,SELECT · 0

commit;
