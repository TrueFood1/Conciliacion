-- ═══════════════════════════════════════════════════════════════════════════
-- PREFERENCIA_TEMA.sql  ·  4-oct-2026  ·  modo claro / oscuro de Truefie, guardado en la CUENTA
-- ⛔ SIN APLICAR. Primero ENSAYO_PREFERENCIA_TEMA.sql (19 de 19 ok = true).
-- Para saber si está aplicado, mirar la base: `select to_regclass('public.preferencia_tema')`.
--
-- QUÉ HACE
--   preferencia_tema   una fila cada vez que alguien toca la luna / el sol. Append-only:
--                      nadie edita ni borra (RLS sin update/delete, sin grant de update/delete).
--                      Gana la fila MÁS RECIENTE (creado_en, y a igual hora el id mayor).
--   tema_vigente()     el modo con el que entra QUIEN PREGUNTA: su última fila o, si nunca
--                      tocó el botón, el de su perfil según acceso_perfil(): socias → oscuro,
--                      el resto (equipo) → claro. Sin perfil activo → null (la app no cambia nada).
--
--   La preferencia es de la CUENTA, no del aparato: la app guarda una copia local solo para
--   arrancar sin parpadeo y la corrige con tema_vigente() apenas hay sesión.
--
-- RLS: cada persona lee e inserta SOLO sus filas (usuario = correo del token, en minúscula) y
-- tiene que tener perfil activo en acceso_usuario. anon: nada (ni tabla ni función). Los
-- grants por defecto de supabase_admin siguen abiertos (ver anon-grants-pendientes), así que
-- acá se revoca a mano.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$ begin
  if to_regclass('public.preferencia_tema') is not null then
    raise exception 'preferencia_tema ya existe: este archivo no se vuelve a pegar';
  end if;
end $$;

create table public.preferencia_tema (
  id         bigint generated always as identity primary key,
  usuario    text not null check (usuario = lower(btrim(usuario)) and position('@' in usuario) > 1),
  tema       text not null check (tema in ('claro', 'oscuro')),
  creado_en  timestamptz not null default now()
);
create index preferencia_tema_usuario_idx on public.preferencia_tema (usuario, creado_en desc, id desc);

alter table public.preferencia_tema enable row level security;
revoke all on public.preferencia_tema from public, anon, authenticated;
grant select, insert on public.preferencia_tema to authenticated;

create policy preferencia_tema_sel on public.preferencia_tema
  for select to authenticated
  using (usuario = lower(coalesce(auth.jwt() ->> 'email', '')));
create policy preferencia_tema_ins on public.preferencia_tema
  for insert to authenticated
  with check (usuario = lower(coalesce(auth.jwt() ->> 'email', '')) and acceso_perfil() is not null);

-- security INVOKER: lee preferencia_tema con la RLS de quien pregunta (solo sus filas);
-- acceso_perfil() ya es definer y contesta solo sobre el que llama.
create or replace function public.tema_vigente() returns text
language sql stable security invoker set search_path = public as $$
  select coalesce(
    (select p.tema from preferencia_tema p
      where p.usuario = lower(coalesce(auth.jwt() ->> 'email', ''))
      order by p.creado_en desc, p.id desc
      limit 1),
    case when acceso_perfil() is null then null
         when acceso_perfil() = 'socias' then 'oscuro'
         else 'claro' end);
$$;
revoke all on function public.tema_vigente() from public, anon;
grant execute on function public.tema_vigente() to authenticated;

-- FILA DE CONTROL — esperado: 1 · 2 · 0 · INSERT,SELECT · f · t
select (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname = 'preferencia_tema' and c.relrowsecurity) as tabla_con_rls,
       (select count(*) from pg_policy where polrelid = 'public.preferencia_tema'::regclass) as politicas,
       (select count(*) from information_schema.role_table_grants
         where table_name = 'preferencia_tema' and grantee = 'anon') as grants_anon,
       (select string_agg(distinct privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
         where table_name = 'preferencia_tema' and grantee = 'authenticated') as grants_authenticated,
       has_function_privilege('anon', 'public.tema_vigente()', 'execute') as anon_ejecuta,
       has_function_privilege('authenticated', 'public.tema_vigente()', 'execute') as authenticated_ejecuta;
commit;
