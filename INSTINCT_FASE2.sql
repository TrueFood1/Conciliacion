-- ═══════════════════════════════════════════════════════════════════════════
-- INSTINCT_FASE2.sql  ·  19-oct-2026  ·  Instinct crea insumos con «sí + código» (fase 2)
-- ⛔ NO SE CORRIÓ. Rama instinct-fase2, sin OK de Andrea. Antes: ENSAYO_INSTINCT_FASE2.sql en verde.
-- Para saber si está aplicado, mirar la base: `select to_regclass('public.asistente_vista_previa')`.
-- Plan: INSTINCT_FASE2_PLAN.md (aprobado el 19-oct).
--
-- QUÉ HACE
--   asistente_permiso       un permiso POR ACCIÓN para el asistente ('crear_insumo'; después 'facturar',
--                           'validar_entrega', 'confirmar_oc'). Append-only; manda la última fila de cada
--                           acción. Sin filas = apagado. Solo una socia lo enciende o lo apaga.
--   asistente_vista_previa  cada vista previa que el servicio le dio al asistente: propuesta, huella y
--                           el CÓDIGO de 4 dígitos. Vale solo la última de cada propuesta (columna `n`).
--                           Único (acción, propuesta, código): dentro de una propuesta dos vistas
--                           previas nunca comparten código.
--   asistente_intento       una fila por código equivocado. Con 3, esa vista previa queda agotada.
--   asistente_puede(acción) asistente + interruptor general encendido + permiso de esa acción encendido.
--
--   compra_insumo_propuesta el asistente puede proponer, con su correo y con el permiso encendido.
--   compra_insumo_odoo      columnas hecho_por_asistente · vista_previa_id · codigo. El asistente puede
--                           dejar el rastro de SU propuesta solo con la vista previa vigente, sin agotar,
--                           y su código. Una socia ya no puede firmar un rastro «hecho por Instinct».
--
--   Nadie actualiza ni borra en ninguna de las cinco: solo SELECT e INSERT.
--   El disparador `asistente_politicas` les pone a las tablas nuevas sus 5 políticas del asistente
--   (no se escriben acá: chocan con 42710). En las cuatro donde el asistente SÍ inserta se cambia SOLO
--   `asistente_no_inserta` por `asistente_inserta_con_permiso`. Las demás tablas de public, igual.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$ begin
  if to_regclass('public.asistente_permiso') is not null or to_regclass('public.asistente_vista_previa') is not null
     or to_regclass('public.asistente_intento') is not null then
    raise exception 'asistente_permiso / asistente_vista_previa / asistente_intento ya existen: este archivo no se vuelve a pegar';
  end if;
end $$;

-- ▼▼▼ BLOQUE DDL ▼▼▼
create table public.asistente_permiso (
  id          bigint generated always as identity primary key,
  accion      text not null check (accion in ('crear_insumo', 'facturar', 'validar_entrega', 'confirmar_oc')),
  encendido   boolean not null,
  motivo      text not null check (length(btrim(motivo)) > 0),
  creado_por  text not null,
  creado_en   timestamptz not null default now()
);

create table public.asistente_vista_previa (
  id           uuid primary key,                                   -- lo genera el servicio (entra en el código)
  n            bigint generated always as identity unique,         -- el orden: vale la de n más alto
  accion       text not null check (accion in ('crear_insumo', 'facturar', 'validar_entrega', 'confirmar_oc')),
  propuesta_id bigint not null check (propuesta_id > 0),
  huella       text not null check (length(huella) between 1 and 64),
  codigo       text not null check (codigo ~ '^[0-9]{4}$'),
  creado_por   text not null,
  creado_en    timestamptz not null default now(),
  unique (accion, propuesta_id, codigo)
);

create table public.asistente_intento (
  id              bigint generated always as identity primary key,
  vista_previa_id uuid not null references public.asistente_vista_previa (id),
  creado_por      text not null,
  creado_en       timestamptz not null default now()
);

alter table public.asistente_permiso enable row level security;
alter table public.asistente_vista_previa enable row level security;
alter table public.asistente_intento enable row level security;
revoke all on public.asistente_permiso, public.asistente_vista_previa, public.asistente_intento from anon, authenticated;
grant select, insert on public.asistente_permiso, public.asistente_vista_previa, public.asistente_intento to authenticated;

-- ── funciones (SECURITY DEFINER: leen por encima del RLS, solo devuelven sí o no) ──
create function public.asistente_puede(p_accion text) returns boolean
  language sql stable security definer set search_path = public as $f$
  select acceso_es_asistente() and not asistente_bloqueado()
         and coalesce((select p.encendido from asistente_permiso p where p.accion = p_accion
                        order by p.id desc limit 1), false);
$f$;

create function public.asistente_propuesta_propia(p_accion text, p_propuesta bigint) returns boolean
  language sql stable security definer set search_path = public as $f$
  select case p_accion
           when 'crear_insumo' then exists (select 1 from compra_insumo_propuesta p where p.id = p_propuesta
                                              and lower(p.creado_por) = lower(coalesce(auth.jwt() ->> 'email', '')))
           else false end;
$f$;

create function public.asistente_vista_previa_propia(p_vp uuid) returns boolean
  language sql stable security definer set search_path = public as $f$
  select exists (select 1 from asistente_vista_previa v where v.id = p_vp
                   and lower(v.creado_por) = lower(coalesce(auth.jwt() ->> 'email', ''))
                   and asistente_puede(v.accion));
$f$;

-- El rastro de una creación hecha por el asistente: su vista previa, la ÚLTIMA de esa propuesta,
-- con menos de 3 intentos fallidos, y el código de esa vista previa.
create function public.asistente_rastro_ok(p_propuesta bigint, p_vp uuid, p_codigo text) returns boolean
  language sql stable security definer set search_path = public as $f$
  select exists (select 1 from asistente_vista_previa v
                  where v.id = p_vp and v.accion = 'crear_insumo' and v.propuesta_id = p_propuesta
                    and v.codigo = p_codigo
                    and lower(v.creado_por) = lower(coalesce(auth.jwt() ->> 'email', ''))
                    and v.n = (select max(w.n) from asistente_vista_previa w
                                where w.accion = 'crear_insumo' and w.propuesta_id = p_propuesta)
                    and (select count(*) from asistente_intento i where i.vista_previa_id = v.id) < 3);
$f$;

revoke all on function public.asistente_puede(text), public.asistente_propuesta_propia(text, bigint),
                       public.asistente_vista_previa_propia(uuid), public.asistente_rastro_ok(bigint, uuid, text)
  from public, anon;
grant execute on function public.asistente_puede(text), public.asistente_propuesta_propia(text, bigint),
                          public.asistente_vista_previa_propia(uuid), public.asistente_rastro_ok(bigint, uuid, text)
  to authenticated;

-- ── asistente_permiso: solo socias ──
create policy asistente_permiso_sel on public.asistente_permiso
  for select to authenticated using (acceso_es_socia());
create policy asistente_permiso_ins on public.asistente_permiso
  for insert to authenticated with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));

-- ── asistente_vista_previa: la inserta el asistente (por el servicio, con su token) ──
create policy asistente_vista_previa_sel on public.asistente_vista_previa
  for select to authenticated using (acceso_es_socia());
drop policy asistente_no_inserta on public.asistente_vista_previa;
create policy asistente_inserta_con_permiso on public.asistente_vista_previa as restrictive
  for insert to authenticated
  with check (not (select public.acceso_es_asistente())
              or (asistente_puede(accion) and asistente_propuesta_propia(accion, propuesta_id)));
create policy asistente_vista_previa_ins on public.asistente_vista_previa
  for insert to authenticated
  with check ((select public.acceso_es_asistente()) and creado_por = (auth.jwt() ->> 'email')
              and asistente_puede(accion) and asistente_propuesta_propia(accion, propuesta_id));

-- ── asistente_intento: lo inserta el asistente sobre SUS vistas previas ──
create policy asistente_intento_sel on public.asistente_intento
  for select to authenticated using (acceso_es_socia());
drop policy asistente_no_inserta on public.asistente_intento;
create policy asistente_inserta_con_permiso on public.asistente_intento as restrictive
  for insert to authenticated
  with check (not (select public.acceso_es_asistente()) or asistente_vista_previa_propia(vista_previa_id));
create policy asistente_intento_ins on public.asistente_intento
  for insert to authenticated
  with check ((select public.acceso_es_asistente()) and creado_por = (auth.jwt() ->> 'email')
              and asistente_vista_previa_propia(vista_previa_id));

-- ── compra_insumo_propuesta: el asistente propone, con el permiso encendido ──
drop policy asistente_no_inserta on public.compra_insumo_propuesta;
create policy asistente_inserta_con_permiso on public.compra_insumo_propuesta as restrictive
  for insert to authenticated
  with check (not (select public.acceso_es_asistente()) or asistente_puede('crear_insumo'));
create policy compra_insumo_propuesta_ins_asistente on public.compra_insumo_propuesta
  for insert to authenticated
  with check ((select public.acceso_es_asistente()) and asistente_puede('crear_insumo')
              and creado_por = (auth.jwt() ->> 'email'));

-- ── compra_insumo_odoo: la marca de Instinct y su rastro ──
alter table public.compra_insumo_odoo
  add column hecho_por_asistente boolean not null default false,
  add column vista_previa_id uuid references public.asistente_vista_previa (id),
  add column codigo text check (codigo is null or codigo ~ '^[0-9]{4}$'),
  add constraint compra_insumo_odoo_marca_ok check (
    hecho_por_asistente = (vista_previa_id is not null) and (vista_previa_id is null) = (codigo is null));
drop policy compra_insumo_odoo_ins on public.compra_insumo_odoo;
create policy compra_insumo_odoo_ins on public.compra_insumo_odoo
  for insert to authenticated
  with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email') and not hecho_por_asistente);
drop policy asistente_no_inserta on public.compra_insumo_odoo;
create policy asistente_inserta_con_permiso on public.compra_insumo_odoo as restrictive
  for insert to authenticated
  with check (not (select public.acceso_es_asistente()) or asistente_puede('crear_insumo'));
create policy compra_insumo_odoo_ins_asistente on public.compra_insumo_odoo
  for insert to authenticated
  with check ((select public.acceso_es_asistente()) and creado_por = (auth.jwt() ->> 'email')
              and hecho_por_asistente and asistente_puede('crear_insumo')
              and asistente_propuesta_propia('crear_insumo', propuesta_id)
              and asistente_rastro_ok(propuesta_id, vista_previa_id, codigo));
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

-- CONTROL, adentro de la transacción y justo antes del commit. ESPERADO: una fila
--   3 · 7 · 7 · 7 · 9 · 9 · 1 · 0 · 4 · 0 · 3
--   (tablas nuevas con RLS · políticas de permiso, vista previa, intento, propuesta, rastro ·
--    `asistente_no_inserta` que quedan en permiso · y en las otras cuatro · funciones nuevas ·
--    grants a anon en las tablas nuevas · columnas nuevas del rastro)
--   Si las políticas de las tablas nuevas dan 2, el disparador del asistente no está: avisar ANTES de seguir.
select (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname in ('asistente_permiso', 'asistente_vista_previa', 'asistente_intento')
           and c.relrowsecurity) as tablas_con_rls,
       (select count(*) from pg_policy where polrelid = 'public.asistente_permiso'::regclass) as pol_permiso,
       (select count(*) from pg_policy where polrelid = 'public.asistente_vista_previa'::regclass) as pol_vista_previa,
       (select count(*) from pg_policy where polrelid = 'public.asistente_intento'::regclass) as pol_intento,
       (select count(*) from pg_policy where polrelid = 'public.compra_insumo_propuesta'::regclass) as pol_propuesta,
       (select count(*) from pg_policy where polrelid = 'public.compra_insumo_odoo'::regclass) as pol_rastro,
       (select count(*) from pg_policy where polname = 'asistente_no_inserta'
         and polrelid = 'public.asistente_permiso'::regclass) as no_inserta_permiso,
       (select count(*) from pg_policy where polname = 'asistente_no_inserta'
         and polrelid in ('public.asistente_vista_previa'::regclass, 'public.asistente_intento'::regclass,
                          'public.compra_insumo_propuesta'::regclass, 'public.compra_insumo_odoo'::regclass)) as no_inserta_abiertas,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
         and p.proname in ('asistente_puede', 'asistente_propuesta_propia', 'asistente_vista_previa_propia',
                           'asistente_rastro_ok')) as funciones,
       (select count(*) from information_schema.role_table_grants where grantee = 'anon'
         and table_name in ('asistente_permiso', 'asistente_vista_previa', 'asistente_intento')) as grants_anon,
       (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'compra_insumo_odoo'
         and column_name in ('hecho_por_asistente', 'vista_previa_id', 'codigo')) as columnas_rastro;
commit;
