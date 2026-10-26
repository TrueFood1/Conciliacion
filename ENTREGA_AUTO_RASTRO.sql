-- ═══════════════════════════════════════════════════════════════════════════
-- ENTREGA_AUTO_RASTRO.sql  ·  26-oct-2026  ·  NO SE CORRIÓ
-- Validar en Odoo AL ENTREGAR (b132, decisión de Andrea del 26-oct). Reemplaza a
-- ENTREGA_AUTO_POLITICAS.sql (que nunca se pegó): aquella abría las tablas del rastro
-- al perfil «equipo», y con su token Daniel podía escribir un rastro falso por REST y
-- sacar un pedido de Pendientes sin validarlo en Odoo (revisión del 26-oct, ALTO 1).
--
-- ⚠️ Este encabezado se cambia a "APLICADO" SOLO después de ver la fila de
--    control del final con los números esperados. Un "Success" no vale.
--
-- QUÉ CREA (y qué NO abre)
--   · ent_odoo_servicio_clave — el HASH de la clave del servicio truefie-escritura.
--     Sin grants: ni anon ni authenticated la leen. La fila se carga APARTE con la
--     línea que arma `clave_rastro_auto.py nueva` (repo truefie-escritura).
--   · ent_odoo_reclamo — una fila por pedido mientras el servicio lo escribe en Odoo
--     (exclusión: /auto y el clic de Andrea no validan ni crean dos veces). Sin grants.
--   · ent_odoo_reclamar / ent_odoo_soltar / ent_odoo_rastro_auto — RPC security
--     definer, ejecutables por authenticated, que EXIGEN la clave del servicio. Quien
--     no la tiene (Daniel desde su teléfono, cualquiera con un token) recibe 42501.
--     El rastro de /auto lo escribe ent_odoo_rastro_auto, con el nombre DEL TOKEN, solo
--     si quien llama tiene el pedido reclamado; si es «equipo», además su salida
--     vigente tiene que ser suya y de hace menos de 30 min.
--   · ent_salida_ins: `creado_por` tiene que ser el correo DEL TOKEN (antes: with check true).
--     Ver el comentario junto al alter policy.
--   · NO toca las tablas del rastro: ni políticas ni grants. «equipo» sigue sin poder
--     insertar en ent_odoo_validacion, ent_odoo_traslado ni ent_odoo_hecho.
--   Las dos tablas nuevas reciben solas RLS y las 5 políticas del asistente (event
--   triggers ensure_rls y asistente_politicas); sin grants no sirven de nada, y se
--   cuentan abajo para que el control no sorprenda.
--
-- ANTES: correr ENSAYO_ENTREGA_AUTO_RASTRO.sql. Tiene que dar las 34 filas ok.
-- DESPUÉS: pegar la línea de `clave_rastro_auto.py nueva` (su `returning` muestra 1 fila)
--          y, desde afuera (pg_lector): select count(*) from ent_odoo_servicio_clave;  -- 1
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$ begin
  if to_regclass('public.ent_odoo_reclamo') is not null or to_regclass('public.ent_odoo_servicio_clave') is not null then
    raise exception 'ent_odoo_reclamo / ent_odoo_servicio_clave ya existen: este archivo no se vuelve a pegar';
  end if;
end $$;

-- ▼▼▼ BLOQUE DDL (el ensayo lo repite byte a byte) ▼▼▼
-- La clave del servicio, como HASH (sha256 de una clave de 36 bytes al azar). La clave misma vive
-- SOLO en Render (RASTRO_AUTO_CLAVE) y en el llavero de la Mac de Andrea. Nadie la lee por REST.
create table public.ent_odoo_servicio_clave (
  id         smallint primary key check (id = 1),
  hash       text not null check (hash ~ '^[0-9a-f]{64}$'),
  creado_en  timestamptz not null default now()
);
alter table public.ent_odoo_servicio_clave enable row level security;
revoke all on public.ent_odoo_servicio_clave from anon, authenticated;

-- EL RECLAMO: una fila por pedido mientras el servicio lo está escribiendo en Odoo. Vence a los
-- 10 min (si el servicio se cae a la mitad, el pedido no queda trabado para siempre).
create table public.ent_odoo_reclamo (
  pedido_id  bigint primary key references public.ent_pedido(id),
  por        text not null,
  ruta       text not null check (ruta in ('validar','trasladar','auto')),
  en         timestamptz not null default now()
);
alter table public.ent_odoo_reclamo enable row level security;
revoke all on public.ent_odoo_reclamo from anon, authenticated;

create function public._ent_odoo_clave_ok(p_clave text) returns boolean
  language sql stable security definer set search_path = public as $f$
  select exists (select 1 from ent_odoo_servicio_clave
                  where id = 1 and hash = encode(sha256(convert_to(coalesce(p_clave, ''), 'UTF8')), 'hex'));
$f$;

-- ¿La salida VIGENTE del pedido la registró quien llama, hace menos de 30 min, y es la ÚNICA salida
-- que tuvo el pedido (anuladas incluidas)? Una segunda salida —«Sale otro día», una corrección, o una
-- inventada por REST sobre un pedido viejo— no dispara nada: queda para Pendientes.
create function public._ent_odoo_salida_mia(p_pedido_id bigint) returns boolean
  language sql stable security definer set search_path = public as $f$
  select exists (select 1
                   from ent_salida_vigente s
                   join ent_alisto_vigente a on a.alisto_id = s.alisto_id
                  where a.pedido_id = p_pedido_id
                    and lower(s.creado_por) = lower(coalesce(auth.jwt() ->> 'email', ''))
                    and s.registrado_en > now() - interval '30 minutes')
     and (select count(*) from ent_salida s2 join ent_alisto a2 on a2.id = s2.alisto_id
           where a2.pedido_id = p_pedido_id) = 1;
$f$;

-- QUIÉN REGISTRÓ LA SALIDA SALE DEL TOKEN (revisión del 26-oct). Hasta hoy `ent_salida_ins` era
-- `with check (true)` y `creado_por` texto libre: alguien de «equipo» podía insertar por REST una
-- salida a nombre de otro. Los tres lugares de index.html que insertan (despConfirmar, despEntregar,
-- rpGuardar) ya mandan `user.email` de la sesión, y las 64 salidas de los últimos 30 días tienen un
-- correo de acceso_usuario (medido con pg_lector el 26-oct): nadie legítimo se rompe.
alter policy ent_salida_ins on public.ent_salida
  with check (lower(creado_por) = lower(coalesce(auth.jwt() ->> 'email', '')));

create function public.ent_odoo_reclamar(p_clave text, p_pedido_id bigint, p_ruta text) returns boolean
  language plpgsql security definer set search_path = public as $f$
declare v_yo text := coalesce(auth.jwt() ->> 'email', ''); v_perfil text := acceso_perfil(); v_n int;
begin
  if not _ent_odoo_clave_ok(p_clave) then
    raise exception 'ent_odoo_reclamar: clave del servicio inválida' using errcode = '42501';
  end if;
  if v_yo = '' or coalesce(v_perfil, '') not in ('socias', 'equipo') then
    raise exception 'ent_odoo_reclamar: solo socias o equipo' using errcode = '42501';
  end if;
  if v_perfil = 'equipo' and (p_ruta is distinct from 'auto' or not _ent_odoo_salida_mia(p_pedido_id)) then
    raise exception 'ent_odoo_reclamar: equipo solo reclama su salida de recién, al entregar' using errcode = '42501';
  end if;
  insert into ent_odoo_reclamo (pedido_id, por, ruta) values (p_pedido_id, v_yo, p_ruta)
  on conflict (pedido_id) do update set por = excluded.por, ruta = excluded.ruta, en = now()
   where ent_odoo_reclamo.en < now() - interval '10 minutes';
  get diagnostics v_n = row_count;
  return v_n = 1;
end $f$;

create function public.ent_odoo_soltar(p_clave text, p_pedido_id bigint) returns boolean
  language plpgsql security definer set search_path = public as $f$
begin
  if not _ent_odoo_clave_ok(p_clave) then
    raise exception 'ent_odoo_soltar: clave del servicio inválida' using errcode = '42501';
  end if;
  delete from ent_odoo_reclamo
   where pedido_id = p_pedido_id and lower(por) = lower(coalesce(auth.jwt() ->> 'email', ''));
  return found;
end $f$;

-- EL RASTRO DE /auto. Lo escribe esta función (como su dueña), NUNCA el token de Daniel: las tablas
-- del rastro siguen cerradas a «equipo». Exige la clave del servicio Y el reclamo vigente de quien
-- llama (o sea, el servicio está en medio de esa validación). El nombre sale del token, no del cuerpo.
create function public.ent_odoo_rastro_auto(p_clave text, p_tipo text, p_fila jsonb) returns bigint
  language plpgsql security definer set search_path = public as $f$
declare
  v_yo text := coalesce(auth.jwt() ->> 'email', ''); v_perfil text := acceso_perfil();
  v_ped bigint := (p_fila ->> 'pedido_id')::bigint; v_id bigint;
begin
  if not _ent_odoo_clave_ok(p_clave) then
    raise exception 'ent_odoo_rastro_auto: clave del servicio inválida' using errcode = '42501';
  end if;
  if v_yo = '' or coalesce(v_perfil, '') not in ('socias', 'equipo') then
    raise exception 'ent_odoo_rastro_auto: solo socias o equipo' using errcode = '42501';
  end if;
  if not exists (select 1 from ent_odoo_reclamo r where r.pedido_id = v_ped and lower(r.por) = lower(v_yo)
                    and r.en > now() - interval '10 minutes') then
    raise exception 'ent_odoo_rastro_auto: el pedido % no está reclamado por quien llama', v_ped using errcode = '42501';
  end if;
  if v_perfil = 'equipo' and not _ent_odoo_salida_mia(v_ped) then
    raise exception 'ent_odoo_rastro_auto: la salida no es de quien llama o no es de recién' using errcode = '42501';
  end if;
  if p_tipo = 'validacion' then
    insert into ent_odoo_validacion (pedido_id, factura_id, picking_id, picking_nombre, lineas, validado_por)
    values (v_ped, (p_fila ->> 'factura_id')::integer, (p_fila ->> 'picking_id')::integer,
            p_fila ->> 'picking_nombre', p_fila -> 'lineas', v_yo)
    returning id into v_id;
  elsif p_tipo = 'traslado' then
    insert into ent_odoo_traslado (pedido_id, picking_id, picking_nombre, motivo, destino_id, contacto_id, lineas, creado_por)
    values (v_ped, (p_fila ->> 'picking_id')::integer, p_fila ->> 'picking_nombre', p_fila ->> 'motivo',
            (p_fila ->> 'destino_id')::integer, (p_fila ->> 'contacto_id')::integer, p_fila -> 'lineas', v_yo)
    returning id into v_id;
    insert into ent_odoo_hecho (pendiente_id, referencia, creado_por)
    select p.id, p_fila ->> 'picking_nombre', v_yo
      from v_ent_odoo_pendiente p
     where p.pedido_id = v_ped and p.tipo = 'traslado_interno';
  else
    raise exception 'ent_odoo_rastro_auto: tipo % desconocido', p_tipo using errcode = '22023';
  end if;
  return v_id;
end $f$;

revoke all on function public._ent_odoo_clave_ok(text) from public, anon, authenticated;
revoke all on function public._ent_odoo_salida_mia(bigint) from public, anon, authenticated;
revoke all on function public.ent_odoo_reclamar(text, bigint, text) from public, anon;
revoke all on function public.ent_odoo_soltar(text, bigint) from public, anon;
revoke all on function public.ent_odoo_rastro_auto(text, text, jsonb) from public, anon;
grant execute on function public.ent_odoo_reclamar(text, bigint, text) to authenticated;
grant execute on function public.ent_odoo_soltar(text, bigint) to authenticated;
grant execute on function public.ent_odoo_rastro_auto(text, text, jsonb) to authenticated;
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

-- CONTROL, adentro de la transacción y antes del commit.
select (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname in ('ent_odoo_reclamo','ent_odoo_servicio_clave') and c.relrowsecurity) as tablas_con_rls,
       (select count(*) from information_schema.role_table_grants
         where table_name in ('ent_odoo_reclamo','ent_odoo_servicio_clave') and grantee in ('anon','authenticated')) as grants_tablas_nuevas,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.prosecdef and p.proname in
           ('_ent_odoo_clave_ok','_ent_odoo_salida_mia','ent_odoo_reclamar','ent_odoo_soltar','ent_odoo_rastro_auto')) as funciones_definer,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname in
           ('_ent_odoo_clave_ok','_ent_odoo_salida_mia','ent_odoo_reclamar','ent_odoo_soltar','ent_odoo_rastro_auto')
           and has_function_privilege('authenticated', p.oid, 'execute')) as rpc_para_authenticated,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname in
           ('_ent_odoo_clave_ok','_ent_odoo_salida_mia','ent_odoo_reclamar','ent_odoo_soltar','ent_odoo_rastro_auto')
           and has_function_privilege('anon', p.oid, 'execute')) as rpc_para_anon,
       (select count(*) from pg_policy where polrelid = 'public.ent_odoo_validacion'::regclass) as pol_validacion,
       (select count(*) from pg_policy where polrelid = 'public.ent_odoo_traslado'::regclass) as pol_traslado,
       (select count(*) from pg_policy where polrelid = 'public.ent_odoo_hecho'::regclass) as pol_hecho,
       (select count(*) from pg_policy where polrelid = 'public.ent_odoo_reclamo'::regclass) as pol_reclamo,
       (select count(*) from pg_policy where polrelid = 'public.ent_odoo_servicio_clave'::regclass) as pol_clave,
       (select count(*) from pg_policy where polrelid = 'public.ent_salida'::regclass) as pol_salida,
       (select count(*) from pg_policy where polrelid = 'public.ent_salida'::regclass and polname = 'ent_salida_ins'
           and pg_get_expr(polwithcheck, polrelid) like '%auth.jwt()%') as salida_atada_al_token;
-- ESPERADO: 2 · 0 · 5 · 3 · 0 · 7 · 7 · 7 · 5 · 5 · 7 · 1
--   (7·7·7 y 7 medido con pg_lector el 26-oct: las tablas del rastro y ent_salida no ganan ni pierden
--    políticas; ent_salida_ins cambia SOLO su with check)

commit;
