-- ═══════════════════════════════════════════════════════════════════════════
-- CAMBIO_TIENDA_FACTURA.sql  ·  11-nov-2026  ·  SIN PEGAR
-- Factura electrónica a nombre del cliente y comprobante por correo, en la Tienda en línea.
--
-- POR QUÉ (Valery, contadora, 11-nov): si el cliente pide factura electrónica a su nombre es OBLIGATORIO
-- emitirla, y el cliente TIENE que recibir el comprobante (tiquete o factura). Hoy todo sale como tiquete a
-- «Venta en línea» (res.partner 1302, sin correo) y no le llega nada a nadie.
--
-- QUÉ CAMBIA (medido contra producción el 11-nov con pg_lector; 0 pedidos, correlativo en 2):
--   1. tienda_pedido: correo, fe_tipo, fe_numero, fe_nombre, fe_correo (todas NULL-ables) + dos CHECK
--      (correo válido; factura completa o vacía, con el formato del número por tipo).
--   2. tienda_tiquete: correo_estado (enviando · esperando · enviado · error · sin_correo), correo_detalle,
--      correo_intentos, correo_en, correo_reclamado_en. Las escribe SOLO el servicio, con su clave.
--   3. tienda_crear_pedido: la misma de hoy + `correo` y `factura` {tipo, numero, nombre, correo}. Sin esos
--      campos (la página vieja) entra igual que hoy. Errores nuevos: tienda:correo · tienda:factura.
--   4. tienda_tiquete_reclamar: la misma de hoy + `correo` y `factura` en el pedido que recibe el servicio.
--   5. Cuatro RPC del servicio: tienda_comprobante_leer · _reclamar (el turno: uno solo manda el correo;
--      vencido a los 10 min) · _marcar · _pendientes (clave del servicio; socias o equipo, que es el robot de /repaso). Ninguna tabla nueva: no dispara asistente_politicas.
--   _tienda_json_pedido, tienda_por_entregar/_por_preparar/_para_facturar NO cambian: Daniel no ve la cédula
--   ni el correo. Truefie los lee de tienda_pedido con la política de socias que ya existe.
--   Las dos funciones que se reemplazan se comparan antes con el md5 de su cuerpo medido el 11-nov: si alguien
--   las tocó, el pegado aborta sin hacer nada.
--
-- ORDEN DE PUBLICACIÓN: 1) ESTE SQL · 2) truefie-escritura (rama tienda-factura) · 3) ENCENDER en Render
--   TIQUETE_FACTURA, TIQUETE_CORREO y TIQUETE_CORREO_DE · 4) la tienda (web) · 5) Truefie. Con la web arriba y
--   TIQUETE_FACTURA apagado, un pedido con factura queda en error (no se emite tiquete en su lugar); y
--   tienda_comprobante_pendientes solo mira los últimos 7 días: un correo apagado más de una semana ya no se manda solo. Al revés: la página nueva contra la base vieja manda correo y factura y la base vieja los
--   IGNORA en silencio (el pedido entra sin factura). Por eso este va primero.
--
-- CONTROL (la última fila antes del commit). ESPERADO:
--   5 · 5 · 2 · 4 · 4 · 0 · true · false · true · true · 6 · 6
--   columnas en pedido · columnas en tiquete · checks · RPC nuevas · las ejecuta authenticated · las ejecuta
--   anon (0) · anon crea pedidos · authenticated no · crear_pedido nueva · reclamar nueva · políticas de
--   tienda_pedido · políticas de tienda_tiquete (no cambian).
-- Si el editor dice "Success. No rows returned", no llegó al final y NO VALE.
-- Antes de pegar esto: correr ENSAYO_TIENDA_FACTURA.sql (termina en rollback).
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- §0 · CANDADOS: no se pega dos veces, y solo sobre las dos funciones MEDIDAS el 11-nov (md5 de su cuerpo).
do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='tienda_pedido' and column_name='fe_tipo') then
    raise exception 'CAMBIO_TIENDA_FACTURA ya está aplicado: este archivo no se vuelve a pegar';
  end if;
  if to_regclass('public.tienda_tiquete') is null or to_regprocedure('public._ent_odoo_clave_ok(text)') is null then
    raise exception 'Falta TIENDA_TIQUETE.sql o ENTREGA_AUTO_RASTRO.sql';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.tienda_crear_pedido(jsonb)'::regprocedure)
       <> 'df5280702b3bf817bce6a7089f4c0a23' then
    raise exception 'tienda_crear_pedido cambió desde el 11-nov: no se reemplaza sin volver a medirla';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.tienda_tiquete_reclamar(text,bigint)'::regprocedure)
       <> '62649a771fd0e0729fcd0733dd46e1cb' then
    raise exception 'tienda_tiquete_reclamar cambió desde el 11-nov: no se reemplaza sin volver a medirla';
  end if;
end $$;

-- §1 · EL PEDIDO GUARDA EL CORREO Y, SI EL CLIENTE LA PIDIÓ, LA FACTURA. Todo NULL-able: un pedido de la
--      página vieja (sin estos campos) entra igual. La identificación se guarda SOLO en dígitos, como la `ref`
--      de los contactos de Odoo. Formato por tipo (Hacienda): física 9 sin cero adelante · jurídica 10 ·
--      DIMEX 11 o 12 sin cero adelante · NITE 10.
alter table public.tienda_pedido
  add column correo    text,
  add column fe_tipo   text,
  add column fe_numero text,
  add column fe_nombre text,
  add column fe_correo text;
alter table public.tienda_pedido add constraint tienda_pedido_correo_ok check (
  correo is null or (length(correo) <= 160 and correo ~ '^[^@\s<>"'',;]+@[^@\s<>"'',;]+\.[A-Za-z]{2,}$'));
alter table public.tienda_pedido add constraint tienda_pedido_factura_ok check (
     (fe_tipo is null and fe_numero is null and fe_nombre is null and fe_correo is null)
  or (fe_tipo in ('01','02','03','04')
      and fe_numero ~ (case fe_tipo when '01' then '^[1-9][0-9]{8}$' when '02' then '^[0-9]{10}$'
                                    when '03' then '^[1-9][0-9]{10,11}$' else '^[0-9]{10}$' end)
      and length(btrim(fe_nombre)) between 2 and 100
      and length(fe_correo) <= 160 and fe_correo ~ '^[^@\s<>"'',;]+@[^@\s<>"'',;]+\.[A-Za-z]{2,}$'));

-- §2 · EL ESTADO DEL CORREO DEL COMPROBANTE, al lado del tiquete. Lo escribe SOLO el servicio (con su clave).
--      «enviando» = alguien tiene el turno (correo_reclamado_en): el cron, el botón o un doble clic no mandan dos.
alter table public.tienda_tiquete
  add column correo_estado   text check (correo_estado in ('enviando','esperando','enviado','error','sin_correo')),
  add column correo_detalle  text,
  add column correo_intentos integer not null default 0,
  add column correo_en       timestamptz,
  add column correo_reclamado_en timestamptz;

-- §3 · tienda_crear_pedido: la de hoy + correo (opcional en la base, la página lo pide) + factura (opcional).
--      `create or replace` conserva los permisos: anon ejecuta, authenticated no (lo mide el control).
create or replace function public.tienda_crear_pedido(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id      uuid;
  v_nombre  text := btrim(coalesce(p->>'nombre',''));
  v_tel     text := btrim(coalesce(p->>'telefono',''));
  v_entrega text := p->>'entrega';
  v_dir     text := nullif(btrim(coalesce(p->>'direccion','')),'');
  v_metodo  text := p->>'metodo_pago';
  v_path    text := p->>'comprobante_path';
  v_total   text := p->>'total_crc';
  v_correo  text := lower(nullif(btrim(coalesce(p->>'correo','')),''));
  v_f       jsonb := p->'factura';
  v_ftipo   text;
  v_fnum    text;
  v_fnom    text;
  v_fcor    text;
  v_sub     integer := 0;
  v_envio   integer := 0;
  v_numero  bigint;
  v_lin     jsonb;
  v_cant    integer;
  v_prod    public.tienda_precio;
  v_vistos  text[] := '{}';
begin
  if coalesce(p->>'id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'tienda:datos';
  end if;
  v_id := (p->>'id')::uuid;

  if length(v_nombre) not between 2 and 120
     or length(regexp_replace(v_tel,'\D','','g')) not between 8 and 15
     or length(v_tel) > 25
     or v_entrega is null or v_entrega not in ('planta','propio','envio')
     or v_metodo is null or v_metodo not in ('sinpe','transferencia')
     or length(coalesce(v_dir,'')) > 400
     or coalesce(v_total,'') !~ '^\d{1,9}$' then
    raise exception 'tienda:datos';
  end if;

  if v_correo is not null
     and (length(v_correo) > 160 or v_correo !~ '^[^@\s<>"'',;]+@[^@\s<>"'',;]+\.[A-Za-z]{2,}$') then
    raise exception 'tienda:correo';
  end if;

  if v_f is not null and jsonb_typeof(v_f) <> 'null' then
    if jsonb_typeof(v_f) <> 'object' then raise exception 'tienda:factura'; end if;
    v_ftipo := v_f->>'tipo';
    v_fnum  := regexp_replace(coalesce(v_f->>'numero',''), '[\s.-]', '', 'g');
    v_fnom  := btrim(coalesce(v_f->>'nombre',''));
    v_fcor  := coalesce(lower(nullif(btrim(coalesce(v_f->>'correo','')),'')), v_correo);
    if v_ftipo is null or v_ftipo not in ('01','02','03','04')
       or v_fnum !~ (case v_ftipo when '01' then '^[1-9][0-9]{8}$' when '02' then '^[0-9]{10}$'
                                  when '03' then '^[1-9][0-9]{10,11}$' else '^[0-9]{10}$' end)
       or length(v_fnom) not between 2 and 100
       or v_fcor is null or length(v_fcor) > 160
       or v_fcor !~ '^[^@\s<>"'',;]+@[^@\s<>"'',;]+\.[A-Za-z]{2,}$' then
      raise exception 'tienda:factura';
    end if;
  end if;

  if v_entrega = 'envio' and v_dir is null then
    raise exception 'tienda:falta_direccion';
  end if;

  if jsonb_typeof(p->'lineas') is distinct from 'array' or jsonb_array_length(p->'lineas') = 0 then
    raise exception 'tienda:sin_productos';
  end if;

  if coalesce(v_path,'') not like v_id::text || '/comprobante.%'
     or not exists (select 1 from storage.objects o
                    where o.bucket_id = 'tienda-comprobantes' and o.name = v_path) then
    raise exception 'tienda:sin_comprobante';
  end if;

  if v_entrega = 'envio' then
    select precio_crc into v_envio from public.tienda_precio where es_envio and activo;
    if v_envio is null then raise exception 'tienda:datos'; end if;
  end if;

  -- El pedido se inserta con totales en cero y se cierra abajo, para poder colgarle las líneas.
  insert into public.tienda_pedido
    (id, nombre, telefono, entrega, direccion, metodo_pago, comprobante_path,
     subtotal_crc, envio_crc, total_crc, correo, fe_tipo, fe_numero, fe_nombre, fe_correo)
  values
    (v_id, v_nombre, v_tel, v_entrega, v_dir, v_metodo, v_path, 0, 0, 0,
     v_correo, v_ftipo, nullif(v_fnum, ''), nullif(v_fnom, ''), case when v_ftipo is null then null else v_fcor end)
  returning numero into v_numero;

  for v_lin in select * from jsonb_array_elements(p->'lineas') loop
    if coalesce(v_lin->>'cant','') !~ '^\d{1,2}$' or (v_lin->>'id') = any(v_vistos) then
      raise exception 'tienda:datos';
    end if;
    v_cant := (v_lin->>'cant')::integer;
    if v_cant not between 1 and 50 then raise exception 'tienda:datos'; end if;

    select * into v_prod from public.tienda_precio
     where id = v_lin->>'id' and activo and not es_envio;
    if not found then raise exception 'tienda:producto'; end if;

    v_vistos := v_vistos || (v_lin->>'id');
    v_sub := v_sub + v_cant * v_prod.precio_crc;
    insert into public.tienda_pedido_linea
      (pedido_id, producto_id, nombre, unidad_venta, cantidad, precio_crc)
    values (v_id, v_prod.id, v_prod.nombre, v_prod.unidad_venta, v_cant, v_prod.precio_crc);
  end loop;

  if v_total::bigint <> (v_sub + v_envio) then
    raise exception 'tienda:total_distinto';
  end if;

  update public.tienda_pedido
     set subtotal_crc = v_sub, envio_crc = v_envio, total_crc = v_sub + v_envio
   where id = v_id;

  return jsonb_build_object('numero', v_numero, 'total_crc', v_sub + v_envio);
exception
  when unique_violation then
    raise exception 'tienda:datos';
end;
$$;

-- §4 · tienda_tiquete_reclamar: la de hoy + 'correo' y 'factura' en el pedido que recibe el servicio
--      (factura = null si no la pidió: el servicio emite el tiquete de siempre).
create or replace function public.tienda_tiquete_reclamar(p_clave text, p_numero bigint) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_yo text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_perfil text := public.acceso_perfil();
  v public.tienda_pedido;
  t public.tienda_tiquete;
begin
  if not public._ent_odoo_clave_ok(p_clave) then
    raise exception 'tienda_tiquete_reclamar: clave del servicio inválida' using errcode = '42501';
  end if;
  if v_yo = '' or v_perfil is null or v_perfil not in ('socias','equipo') then raise exception 'tienda:perfil'; end if;
  select * into v from public.tienda_pedido where numero = p_numero for update;
  if not found then raise exception 'tienda:no_existe'; end if;
  if v.estado <> 'entregado' then raise exception 'tienda:estado'; end if;
  select * into t from public.tienda_tiquete where pedido_id = v.id;
  if not found then raise exception 'tienda:sin_tiquete'; end if;
  if v_perfil = 'equipo' and not exists (
       select 1 from public.tienda_pedido_evento e
        where e.pedido_id = v.id and e.a_estado = 'entregado' and lower(e.por) = v_yo and e.en > now() - interval '30 minutes') then
    raise exception 'tienda:perfil';
  end if;
  if t.estado = 'creado' then return jsonb_build_object('estado','creado','move_id',t.move_id); end if;
  if t.estado = 'en_curso' and t.reclamado_en > now() - interval '30 minutes' then
    return jsonb_build_object('estado','en_curso');
  end if;
  update public.tienda_tiquete
     set estado = 'en_curso', intentos = intentos + 1, reclamado_en = now(), por = v_yo, error = null, actualizado_en = now()
   where pedido_id = v.id;
  return jsonb_build_object('estado','reclamado','pedido', jsonb_build_object(
    'numero', v.numero, 'nombre', v.nombre, 'entrega', v.entrega, 'direccion', v.direccion, 'metodo_pago', v.metodo_pago,
    'subtotal_crc', v.subtotal_crc, 'envio_crc', v.envio_crc, 'total_crc', v.total_crc,
    'correo', v.correo,
    'factura', case when v.fe_tipo is null then null else jsonb_build_object(
                 'tipo', v.fe_tipo, 'numero', v.fe_numero, 'nombre', v.fe_nombre, 'correo', v.fe_correo) end,
    'pago_fecha', (select to_char(max(e.en) at time zone 'America/Costa_Rica', 'YYYY-MM-DD') from public.tienda_pedido_evento e
                    where e.pedido_id = v.id and e.a_estado = 'pago_recibido'),
    'lineas', (select coalesce(jsonb_agg(jsonb_build_object(
                  'nombre', l.nombre, 'cantidad', l.cantidad, 'precio_crc', l.precio_crc,
                  'producto_id', pr.producto_id, 'uom_id', pr.uom_id) order by l.nombre), '[]'::jsonb)
                 from public.tienda_pedido_linea l join public.tienda_precio pr on pr.id = l.producto_id
                where l.pedido_id = v.id)));
end;
$$;

-- §5 · EL COMPROBANTE POR CORREO: cuatro RPC del servicio, con su clave, para socias y equipo (el robot de
--      /repaso es equipo). Solo sobre tiquetes ya «creado» en Odoo. La dirección la da la base, nunca quien llama.
create function public.tienda_comprobante_leer(p_clave text, p_numero bigint) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_perfil text := public.acceso_perfil();
  v public.tienda_pedido;
  t public.tienda_tiquete;
begin
  if not public._ent_odoo_clave_ok(p_clave) then
    raise exception 'tienda_comprobante_leer: clave del servicio inválida' using errcode = '42501';
  end if;
  if v_perfil is null or v_perfil not in ('socias','equipo') then raise exception 'tienda:perfil'; end if;
  select * into v from public.tienda_pedido where numero = p_numero;
  if not found then raise exception 'tienda:no_existe'; end if;
  select * into t from public.tienda_tiquete where pedido_id = v.id;
  if not found then raise exception 'tienda:sin_tiquete'; end if;
  return jsonb_build_object('estado', t.estado, 'move_id', t.move_id, 'factura', v.fe_tipo is not null,
    'nombre', coalesce(v.fe_nombre, v.nombre), 'destino', coalesce(v.fe_correo, v.correo),
    'total_crc', v.total_crc, 'correo_estado', t.correo_estado);
end;
$$;

-- El turno: UNO solo pasa a «enviando» (la fila queda bloqueada por el update; el segundo ve el estado ya cambiado).
-- Un turno de más de 10 minutos (el servicio se cayó a la mitad) se puede retomar. «enviado» no se reclama nunca.
create function public.tienda_comprobante_reclamar(p_clave text, p_numero bigint) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare v_perfil text := public.acceso_perfil(); v_n int;
begin
  if not public._ent_odoo_clave_ok(p_clave) then
    raise exception 'tienda_comprobante_reclamar: clave del servicio inválida' using errcode = '42501';
  end if;
  if v_perfil is null or v_perfil not in ('socias','equipo') then raise exception 'tienda:perfil'; end if;
  update public.tienda_tiquete t
     set correo_estado = 'enviando', correo_reclamado_en = now(), actualizado_en = now()
    from public.tienda_pedido p
   where p.id = t.pedido_id and p.numero = p_numero and t.estado = 'creado'
     and t.correo_estado is distinct from 'enviado'
     and (t.correo_estado is distinct from 'enviando' or t.correo_reclamado_en < now() - interval '10 minutes');
  get diagnostics v_n = row_count;
  return v_n = 1;
end;
$$;

create function public.tienda_comprobante_marcar(p_clave text, p_numero bigint, p_estado text, p_detalle text) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare v_perfil text := public.acceso_perfil(); v_n int;
begin
  if not public._ent_odoo_clave_ok(p_clave) then
    raise exception 'tienda_comprobante_marcar: clave del servicio inválida' using errcode = '42501';
  end if;
  if v_perfil is null or v_perfil not in ('socias','equipo') then raise exception 'tienda:perfil'; end if;
  if p_estado is null or p_estado not in ('esperando','enviado','error','sin_correo') then raise exception 'tienda:datos'; end if;
  -- «enviado» no se pisa: un correo que salió no vuelve a esperar.
  update public.tienda_tiquete t
     set correo_estado = p_estado, correo_detalle = left(nullif(btrim(coalesce(p_detalle,'')),''), 300),
         correo_intentos = t.correo_intentos + (case when p_estado = 'error' then 1 else 0 end),
         correo_en = case when p_estado = 'enviado' then now() else t.correo_en end, actualizado_en = now()
    from public.tienda_pedido p
   where p.id = t.pedido_id and p.numero = p_numero and t.estado = 'creado' and t.correo_estado is distinct from 'enviado';
  get diagnostics v_n = row_count;
  return v_n = 1;
end;
$$;

-- Los que el /repaso tiene que mirar: creados en los últimos 7 días, sin correo enviado ni «sin_correo», y con
-- menos de 5 errores (de ahí en adelante se mira a mano). A lo sumo 20 por vuelta, los más viejos primero.
create function public.tienda_comprobante_pendientes(p_clave text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare v_perfil text := public.acceso_perfil(); v_r jsonb;
begin
  if not public._ent_odoo_clave_ok(p_clave) then
    raise exception 'tienda_comprobante_pendientes: clave del servicio inválida' using errcode = '42501';
  end if;
  if v_perfil is null or v_perfil not in ('socias','equipo') then raise exception 'tienda:perfil'; end if;
  select coalesce(jsonb_agg(x.numero order by x.numero), '[]'::jsonb) into v_r from (
    select p.numero from public.tienda_tiquete t join public.tienda_pedido p on p.id = t.pedido_id
     where t.estado = 'creado' and t.creado_en > now() - interval '7 days'
       and (t.correo_estado is null or t.correo_estado = 'esperando' or (t.correo_estado = 'error' and t.correo_intentos < 5)
            or (t.correo_estado = 'enviando' and t.correo_reclamado_en < now() - interval '10 minutes'))
     order by p.numero limit 20) x;
  return v_r;
end;
$$;

revoke all on function public.tienda_comprobante_leer(text,bigint), public.tienda_comprobante_marcar(text,bigint,text,text),
                       public.tienda_comprobante_pendientes(text), public.tienda_comprobante_reclamar(text,bigint)
  from public, anon, authenticated;
grant execute on function public.tienda_comprobante_leer(text,bigint), public.tienda_comprobante_marcar(text,bigint,text,text),
                          public.tienda_comprobante_pendientes(text), public.tienda_comprobante_reclamar(text,bigint) to authenticated;

-- CONTROL, justo antes del commit. ESPERADO: 5 · 5 · 2 · 4 · 4 · 0 · true · false · true · true · 6 · 6
with rpc(f) as (values ('public.tienda_comprobante_leer(text,bigint)'), ('public.tienda_comprobante_marcar(text,bigint,text,text)'),
                       ('public.tienda_comprobante_pendientes(text)'), ('public.tienda_comprobante_reclamar(text,bigint)'))
select (select count(*) from information_schema.columns where table_schema='public' and table_name='tienda_pedido'
         and column_name in ('correo','fe_tipo','fe_numero','fe_nombre','fe_correo')) as columnas_pedido,
       (select count(*) from information_schema.columns where table_schema='public' and table_name='tienda_tiquete'
         and column_name in ('correo_estado','correo_detalle','correo_intentos','correo_en','correo_reclamado_en')) as columnas_tiquete,
       (select count(*) from pg_constraint where conrelid='public.tienda_pedido'::regclass
         and conname in ('tienda_pedido_correo_ok','tienda_pedido_factura_ok')) as checks,
       (select count(*) from rpc where to_regprocedure(f) is not null) as rpc_nuevas,
       (select count(*) from rpc where has_function_privilege('authenticated', f, 'execute')) as authenticated_rpc,
       (select count(*) from rpc where has_function_privilege('anon', f, 'execute')) as anon_rpc,
       has_function_privilege('anon','public.tienda_crear_pedido(jsonb)','execute') as anon_crea,
       has_function_privilege('authenticated','public.tienda_crear_pedido(jsonb)','execute') as authenticated_crea,
       (select prosrc like '%tienda:factura%' from pg_proc where oid='public.tienda_crear_pedido(jsonb)'::regprocedure) as crear_nueva,
       (select prosrc like '%fe_numero%' from pg_proc where oid='public.tienda_tiquete_reclamar(text,bigint)'::regprocedure) as reclamar_nueva,
       (select count(*) from pg_policies where schemaname='public' and tablename='tienda_pedido') as politicas_pedido,
       (select count(*) from pg_policies where schemaname='public' and tablename='tienda_tiquete') as politicas_tiquete;

commit;
