-- ═══════════════════════════════════════════════════════════════════════════
-- CONTENIDO.sql  ·  27-oct-2026  ·  Módulo «Contenido» (b138): calendario, métricas, banco, revisión
-- ✅ APLICADO en producción por Andrea (27-oct), control 4·30·0·0·INSERT,SELECT,UPDATE·0·0·2·2·4; ensayo 59/59; verificado desde afuera (REST anon 42501 en las 6). Antes: ENSAYO_CONTENIDO.sql (ensayo en seco, no deja nada). Después: la fila de
--    control de abajo tiene que salir EXACTA. Este header se toca DESPUÉS de verificar, nunca antes.
-- Para saber si está aplicado, mirar la base: `select to_regclass('public.contenido_post')`.
--
-- QUÉ HACE
--   contenido_post          un post o una historia: título, fecha planeada, formato, pilar, producto,
--                           texto, enlace a la vista previa y al post publicado. Se EDITA (socias);
--                           no se borra: se descarta con un estado.
--   contenido_post_estado   cada cambio de estado (idea → borrador → aprobado → publicado, o
--                           descartado). Append-only: gana la última fila. La de «aprobado» guarda
--                           las fallas automáticas que se vieron, la lista tildada y la huella del texto.
--                           La base EXIGE que un aprobado con fallas diga que se vieron (CHECK).
--   contenido_metrica       una lectura de Meta Business Suite: alcance, vistas, me gusta, respuestas,
--                           guardados, compartidos, clics de enlace, seguidores. Por momento (parcial,
--                           24 h, 7 días, final). Append-only: gana la última lectura de cada momento.
--   contenido_banco         fotos y videos de Google Drive para tener a mano (empaques, tablas
--                           nutricionales, producto…): el id del archivo, nunca el archivo.
--   v_contenido_post / v_contenido_metrica_vigente   vistas security_invoker (la RLS de abajo manda).
--
--   QUIÉN: solo socias leen y escriben (acceso_es_socia()). anon: nada (ni leer). equipo: nada.
--   El asistente LEE por las 5 políticas automáticas (event trigger asistente_politicas) y no escribe.
--   Los permisos por defecto de producción dan SELECT/INSERT/UPDATE/DELETE a anon en toda tabla nueva,
--   USAGE/SELECT/UPDATE en toda secuencia y EXECUTE en toda función (T-148): por eso cada tabla, vista,
--   secuencia de id y la función de trigger empiezan con un `revoke` a anon y authenticated (y la
--   función, también a PUBLIC). Insertar no necesita la secuencia: las columnas son GENERATED ALWAYS AS
--   IDENTITY y Postgres no pide permiso sobre su secuencia (medido en el ENSAYO, Q1–Q4).
--   service_role CONSERVA todo (es el rol de servicio de Supabase, salta la RLS): a propósito, no se toca.
--
--   La carga de datos semilla (las 3 historias del 26-oct y los archivos del banco) NO va acá: está
--   en PEGADO_CONTENIDO_SEMILLA.sql, fuera de git (lleva ids de Drive y métricas de la cuenta).
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$ begin
  if to_regclass('public.contenido_post') is not null then
    raise exception 'contenido_post ya existe: este archivo no se vuelve a pegar';
  end if;
end $$;

-- ── 1 · el post ──────────────────────────────────────────────────────────
create table public.contenido_post (
  id              bigint generated always as identity primary key,
  titulo          text not null check (length(btrim(titulo)) between 1 and 140),
  fecha_planeada  date,
  formato         text not null check (formato in ('carrusel', 'reel', 'historia', 'post')),
  pilar           text check (pilar in ('recetas', 'porque', 'nosotras', 'novedades')),
  producto_id     integer check (producto_id in (451, 452, 453, 503, 472, 519)),   -- por ID, nunca por nombre
  texto           text not null default '' check (length(texto) <= 6000),
  -- Solo https y sin comillas ni espacios: se pintan como enlace, y un `javascript:` sería un script.
  enlace_vista    text check (enlace_vista ~ '^https://[^[:space:]<>"''`]+$' and length(enlace_vista) <= 500),
  enlace_ig       text check (enlace_ig ~ '^https://[^[:space:]<>"''`]+$' and length(enlace_ig) <= 500),
  publicado_en    timestamptz,
  creado_por      text not null check (length(btrim(creado_por)) > 0),
  creado_en       timestamptz not null default now(),
  editado_por     text,
  editado_en      timestamptz
);
create index contenido_post_fecha on public.contenido_post (fecha_planeada);

create function public.contenido_post_editado() returns trigger
  language plpgsql set search_path = public as $f$
begin
  new.editado_en := now();
  return new;
end $f$;
create trigger contenido_post_editado before update on public.contenido_post
  for each row execute function public.contenido_post_editado();

-- ── 2 · los estados (append-only) ────────────────────────────────────────
create table public.contenido_post_estado (
  id             bigint generated always as identity primary key,
  post_id        bigint not null references public.contenido_post (id),
  estado         text not null check (estado in ('idea', 'borrador', 'aprobado', 'publicado', 'descartado')),
  fallas         jsonb not null default '[]'::jsonb check (jsonb_typeof(fallas) = 'array'),
  fallas_vistas  boolean not null default false,
  checklist      jsonb not null default '[]'::jsonb check (jsonb_typeof(checklist) = 'array'),
  huella         text check (length(huella) between 1 and 64),
  creado_por     text not null check (length(btrim(creado_por)) > 0),
  creado_en      timestamptz not null default now(),
  -- «Un post no pasa a aprobado con fallas automáticas sin que se vea»
  constraint contenido_post_estado_fallas_vistas check (
    estado <> 'aprobado' or jsonb_array_length(fallas) = 0 or fallas_vistas)
);
create index contenido_post_estado_post on public.contenido_post_estado (post_id, creado_en desc, id desc);

-- ── 3 · las métricas (append-only) ───────────────────────────────────────
create table public.contenido_metrica (
  id            bigint generated always as identity primary key,
  post_id       bigint not null references public.contenido_post (id),
  momento       text not null check (momento in ('parcial', '24h', '7d', 'final')),
  leido_en      timestamptz not null,
  alcance       integer check (alcance >= 0),
  vistas        integer check (vistas >= 0),
  me_gusta      integer check (me_gusta >= 0),
  respuestas    integer check (respuestas >= 0),
  guardados     integer check (guardados >= 0),
  compartidos   integer check (compartidos >= 0),
  clics_enlace  integer check (clics_enlace >= 0),
  seguidores    integer check (seguidores >= 0),
  nota          text check (length(nota) <= 500),
  creado_por    text not null check (length(btrim(creado_por)) > 0),
  creado_en     timestamptz not null default now(),
  constraint contenido_metrica_algo check (num_nonnulls(alcance, vistas, me_gusta, respuestas, guardados,
                                                       compartidos, clics_enlace, seguidores) > 0)
);
create index contenido_metrica_post on public.contenido_metrica (post_id, momento, creado_en desc, id desc);

-- ── 4 · el banco de fotos y videos ───────────────────────────────────────
create table public.contenido_banco (
  id           bigint generated always as identity primary key,
  drive_id     text not null unique check (drive_id ~ '^[A-Za-z0-9_-]{20,80}$'),
  nombre       text not null check (length(btrim(nombre)) between 1 and 200),
  tipo         text not null check (tipo in ('foto', 'video')),
  categoria    text not null check (categoria in ('producto', 'empaque', 'tabla_nutricional', 'marca',
                                                  'punto_de_venta', 'fabrica', 'otro')),
  producto_id  integer check (producto_id in (451, 452, 453, 503, 472, 519)),
  nota         text check (length(nota) <= 500),
  activo       boolean not null default true,
  creado_por   text not null check (length(btrim(creado_por)) > 0),
  creado_en    timestamptz not null default now(),
  editado_por  text,
  editado_en   timestamptz
);
create trigger contenido_banco_editado before update on public.contenido_banco
  for each row execute function public.contenido_post_editado();

-- ── 5 · permisos: nadie por defecto, socias por política ─────────────────
alter table public.contenido_post        enable row level security;   -- ya lo prende ensure_rls; no estorba
alter table public.contenido_post_estado enable row level security;
alter table public.contenido_metrica     enable row level security;
alter table public.contenido_banco       enable row level security;
revoke all on public.contenido_post, public.contenido_post_estado, public.contenido_metrica,
              public.contenido_banco from anon, authenticated;
grant select, insert on public.contenido_post, public.contenido_post_estado, public.contenido_metrica,
                        public.contenido_banco to authenticated;
-- UPDATE solo de las columnas editables: creado_por/creado_en/id no se tocan nunca.
grant update (titulo, fecha_planeada, formato, pilar, producto_id, texto, enlace_vista, enlace_ig,
              publicado_en, editado_por) on public.contenido_post to authenticated;
grant update (nombre, tipo, categoria, producto_id, nota, activo, editado_por)
  on public.contenido_banco to authenticated;
-- Las secuencias de los id y la función de trigger: nadie de afuera (ver el header).
revoke all on sequence public.contenido_post_id_seq, public.contenido_post_estado_id_seq,
                       public.contenido_metrica_id_seq, public.contenido_banco_id_seq from anon, authenticated;
revoke execute on function public.contenido_post_editado() from public, anon, authenticated;

create policy contenido_post_sel on public.contenido_post
  for select to authenticated using (acceso_es_socia());
create policy contenido_post_ins on public.contenido_post
  for insert to authenticated with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));
create policy contenido_post_upd on public.contenido_post
  for update to authenticated using (acceso_es_socia())
  with check (acceso_es_socia() and editado_por = (auth.jwt() ->> 'email'));

create policy contenido_post_estado_sel on public.contenido_post_estado
  for select to authenticated using (acceso_es_socia());
create policy contenido_post_estado_ins on public.contenido_post_estado
  for insert to authenticated with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));

create policy contenido_metrica_sel on public.contenido_metrica
  for select to authenticated using (acceso_es_socia());
create policy contenido_metrica_ins on public.contenido_metrica
  for insert to authenticated with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));

create policy contenido_banco_sel on public.contenido_banco
  for select to authenticated using (acceso_es_socia());
create policy contenido_banco_ins on public.contenido_banco
  for insert to authenticated with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));
create policy contenido_banco_upd on public.contenido_banco
  for update to authenticated using (acceso_es_socia())
  with check (acceso_es_socia() and editado_por = (auth.jwt() ->> 'email'));

-- ── 6 · vistas (security_invoker: corren con los permisos de quien pregunta) ──
create view public.v_contenido_post with (security_invoker = true) as
  select p.*, coalesce(e.estado, 'idea') as estado, e.creado_en as estado_en, e.creado_por as estado_por,
         e.fallas, e.fallas_vistas, e.checklist, e.huella
    from public.contenido_post p
    left join lateral (select x.* from public.contenido_post_estado x where x.post_id = p.id
                        order by x.creado_en desc, x.id desc limit 1) e on true;

create view public.v_contenido_metrica_vigente with (security_invoker = true) as
  select distinct on (m.post_id, m.momento) m.*
    from public.contenido_metrica m
   order by m.post_id, m.momento, m.creado_en desc, m.id desc;

revoke all on public.v_contenido_post, public.v_contenido_metrica_vigente from anon, authenticated;
grant select on public.v_contenido_post, public.v_contenido_metrica_vigente to authenticated;

-- Control: 4 · 30 · 0 · 0 · INSERT,SELECT,UPDATE · 0 · 0 · 2 · 2 · 4
--   tablas con RLS · políticas (10 propias + 5 automáticas del asistente × 4 tablas) ·
--   privilegios de anon sobre las 4 tablas, 2 vistas y 4 secuencias (has_*_privilege: no depende de
--   quién consulta) · DELETE de authenticated en las tablas · privilegios de authenticated sobre
--   contenido_post (tabla + columnas) · privilegios de authenticated sobre las 4 secuencias ·
--   roles que pueden ejecutar la función de trigger (anon, authenticated) · vistas con security_invoker ·
--   triggers de editado · índices propios
with t(o) as (values ('public.contenido_post'), ('public.contenido_post_estado'), ('public.contenido_metrica'),
                     ('public.contenido_banco'), ('public.v_contenido_post'), ('public.v_contenido_metrica_vigente')),
     q(o) as (values ('public.contenido_post_id_seq'), ('public.contenido_post_estado_id_seq'),
                     ('public.contenido_metrica_id_seq'), ('public.contenido_banco_id_seq')),
     tp(p) as (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'), ('REFERENCES'), ('TRIGGER')),
     qp(p) as (values ('USAGE'), ('SELECT'), ('UPDATE'))
select (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
           and c.relname in ('contenido_post', 'contenido_post_estado', 'contenido_metrica', 'contenido_banco')) as tablas_con_rls,
       (select count(*) from pg_policy where polrelid in ('public.contenido_post'::regclass, 'public.contenido_post_estado'::regclass,
                                                          'public.contenido_metrica'::regclass, 'public.contenido_banco'::regclass)) as politicas,
       (select count(*) from t, tp where has_table_privilege('anon', t.o, tp.p))
     + (select count(*) from q, qp where has_sequence_privilege('anon', q.o, qp.p)) as privs_anon,
       (select count(*) from t, (values ('DELETE'), ('TRUNCATE')) d(p)
         where t.o not like 'public.v\_%' and has_table_privilege('authenticated', t.o, d.p)) as borra_authenticated,
       (select string_agg(distinct privilege_type, ',' order by privilege_type) from (
          select privilege_type from information_schema.role_table_grants
           where grantee = 'authenticated' and table_name = 'contenido_post'
          union all
          select privilege_type from information_schema.role_column_grants
           where grantee = 'authenticated' and table_name = 'contenido_post') g) as privs_post,
       (select count(*) from q, qp where has_sequence_privilege('authenticated', q.o, qp.p)) as privs_seq_authenticated,
       (select count(*) from (values ('anon'), ('authenticated')) r(rol)
         where has_function_privilege(r.rol, 'public.contenido_post_editado()', 'EXECUTE')) as funcion_ejecutable,
       (select count(*) from pg_class where relname in ('v_contenido_post', 'v_contenido_metrica_vigente')
           and 'security_invoker=true' = any (reloptions)) as vistas_invoker,
       (select count(*) from pg_trigger where not tgisinternal
           and tgname in ('contenido_post_editado', 'contenido_banco_editado')) as triggers,
       (select count(*) from pg_indexes where schemaname = 'public'
           and indexname in ('contenido_post_fecha', 'contenido_post_estado_post', 'contenido_metrica_post',
                             'contenido_banco_drive_id_key')) as indices;
commit;
