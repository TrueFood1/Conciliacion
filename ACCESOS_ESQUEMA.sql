-- ════════════════════════════════════════════════════════════════════════
-- ACCESOS POR PERFIL · ESQUEMA SUPABASE   (PEGADO 1 de 3)
-- PROPUESTA 13-ago-2026.
-- ✅ APROBADO POR ANDREA 24-ago-2026 — se levanta el STOP de diseño.
-- Es el PRIMERO de los tres: acá se crean acceso_es_socia() y acceso_perfil(),
-- de las que dependen todas las políticas del pegado 2.
--
-- ⚠️ LA SEMILLA DEL FINAL NO ESTÁ COMENTADA — se ejecuta apenas le des Run, y
-- tiene `on conflict do nothing`, así que NO falla si quedan los CAMBIAR-.
-- Reemplazá los tres correos ANTES de ejecutar o vas a insertar tres correos
-- falsos sin que nada te avise.
--
-- QUÉ RESUELVE
-- Hoy la lista de accesos vive en index.html (`ACCESO_USUARIOS`) y los nombres
-- del saludo también (`SALUDO_NOMBRES`). Con dos correos de empresa eso se
-- aguantaba. Con Daniel, Daniela y Ney —tres gmail PERSONALES— ya no: el repo es
-- público y el index.html se publica tal cual en GitHub Pages. El 13-ago se
-- llegó a poner el correo de Daniel y se revirtió el mismo día por eso mismo, y
-- el saludo terminó resolviéndose por una HUELLA del correo para no publicarlo.
--
-- Esta tabla borra ese problema entero:
--   · los correos viven en Supabase, no en el HTML público;
--   · sumar a Daniela y a Ney es INSERTAR DOS FILAS, no tocar código ni publicar;
--   · el saludo sale de acá (`nombre`), así que la huella del correo se elimina
--     de index.html cuando esto entre — deja de hacer falta;
--   · y es el primer escalón real hacia "Roles y accesos": la misma tabla que
--     hoy dibuja el lobby es la que mañana alimenta la RLS de cada módulo.
--     De hecho el módulo Personal (pegado 2) YA la usa para eso.
--
-- QUÉ SIGUE EN EL CÓDIGO, Y POR QUÉ
-- El mapa PERFIL → MÓDULOS se queda en index.html. No es dato sensible, es
-- lógica de interfaz, y quererla en base de datos obliga a un pegado de SQL cada
-- vez que nace un módulo. Lo que se va a Supabase es la IDENTIDAD (quién es
-- quién y de qué perfil), que es lo único delicado.
--
--   perfil    quiénes                  ven
--   socias    Andrea, Lorena           todo
--   equipo    Daniel, Daniela, Ney     Entregas · Personal · Producción (cuando exista)
--
-- APPEND-ONLY, como todo: cambiar a alguien de perfil o darlo de baja es
-- insertar una fila nueva. Gana la más reciente por correo.
-- ════════════════════════════════════════════════════════════════════════

create table if not exists acceso_usuario (
  id          bigint generated always as identity primary key,
  email       text    not null,
  nombre      text    not null,                   -- nombre de pila, para el saludo del lobby
  perfil      text    not null check (perfil in ('socias','equipo')),
  activo      boolean not null default true,      -- dar de baja = insertar con false
  nota        text,
  creado_en   timestamptz not null default now(),
  creado_por  text    not null
);
create index if not exists acceso_usuario_email_idx
  on acceso_usuario (lower(email), creado_en desc);

-- La fila VIGENTE de un correo: la más reciente. Una sola definición de
-- "vigente" para todo el sistema, así ninguna vista la reinventa distinto.
--
-- ⚠️ `security_invoker` NO ES OPCIONAL ACÁ, y falta costó una fuga real. Esta
-- vista nació sin la opción y el 24-ago-2026, con el esquema recién pegado, la
-- anon key —que va publicada dentro de index.html en GitHub Pages— devolvía las
-- 5 filas completas: nombre, perfil y correo, tres de ellos personales. La
-- tabla estaba bien cerrada por RLS; la vista la esquivaba, porque sin esta
-- opción corre con los permisos de su dueño y la RLS del que llama no se
-- aplica. Puerta con llave, ventana abierta al lado.
-- Regla que sale de esto: TODA vista de este módulo lleva security_invoker.
create or replace view v_acceso_usuario with (security_invoker = true) as
select distinct on (lower(email))
       id, lower(email) as email, nombre, perfil, activo, creado_en
  from acceso_usuario
 order by lower(email), creado_en desc;

-- El perfil de QUIEN PREGUNTA. `security definer` a propósito: la función tiene
-- que poder mirar la tabla entera aunque la RLS del que llama no lo deje, o no
-- podría contestar sobre sí mismo.
create or replace function acceso_perfil() returns text
language sql stable security definer set search_path = public as $$
  select case when v.activo then v.perfil else null end
    from v_acceso_usuario v
   where v.email = lower(coalesce(auth.jwt() ->> 'email',''))
   limit 1;
$$;

create or replace function acceso_es_socia() returns boolean
language sql stable security definer set search_path = public as $$
  select acceso_perfil() = 'socias';
$$;

-- ── RLS ─────────────────────────────────────────────────────────────────
-- Cada quien lee SU fila (la app necesita su perfil y su nombre para dibujar el
-- lobby). Las socias leen todas. NADIE inserta desde la herramienta: esta tabla
-- se administra desde el SQL Editor. Quien pueda cambiarse el perfil a sí mismo
-- desde la interfaz vuelve la puerta un adorno.
alter table acceso_usuario enable row level security;

drop policy if exists acceso_usuario_sel on acceso_usuario;
create policy acceso_usuario_sel on acceso_usuario
  for select to authenticated
  using (lower(email) = lower(coalesce(auth.jwt() ->> 'email','')) or acceso_es_socia());

-- OJO CON LOS GRANTS: Supabase le da `select` a `anon` y a `authenticated`
-- sobre todo lo que nace en `public`, por privilegios por defecto. O sea que
-- los `grant` de abajo no restringen nada — repiten algo ya dado. Lo que sí
-- hace falta es QUITARLE a `anon` lo que no debería tener: antes del login no
-- hay nada acá que leer. Sin este revoke, cualquiera con la anon key (pública,
-- va dentro de index.html) consulta la tabla por REST.
revoke all on acceso_usuario, v_acceso_usuario from anon;

grant select on acceso_usuario to authenticated;
grant select on v_acceso_usuario to authenticated;
-- Sin grant de insert/update/delete, a propósito.


-- ── SEMILLA ─────────────────────────────────────────────────────────────
-- ⚠️ ANDREA: cambiá los tres correos de abajo por los reales antes de pegar.
-- El de Daniel ya está confirmado (lo tiene Andrea); los de Daniela y Ney faltan.
-- Los correos NO se escriben en este archivo — el repo es público y este archivo
-- vive en él. Van directo en el SQL Editor de Supabase, que es privado, y nunca
-- por chat ni por correo.
insert into acceso_usuario (email, nombre, perfil, nota, creado_por) values
  ('andrea@truefoodcr.com',        'Andrea',  'socias', 'socia',            'semilla'),
  ('lorena@truefoodcr.com',        'Lorena',  'socias', 'socia',            'semilla'),
  ('CAMBIAR-daniel@ejemplo.com',   'Daniel',  'equipo', 'producción',       'semilla'),
  ('CAMBIAR-daniela@ejemplo.com',  'Daniela', 'equipo', 'producción',       'semilla'),
  ('CAMBIAR-ney@ejemplo.com',      'Ney',     'equipo', 'producción',       'semilla')
on conflict do nothing;

-- Chequeo: que no quede ningún CAMBIAR- suelto.
-- select email, nombre, perfil from v_acceso_usuario order by perfil, nombre;
