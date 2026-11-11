-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_TIENDA_FACTURA.sql  ·  11-nov-2026  ·  ENSAYO EN SECO · TERMINA EN ROLLBACK · SIN CORRER
-- Aplica CAMBIO_TIENDA_FACTURA.sql, lo prueba con pedidos de mentira y lo deshace todo.
--
-- CÓMO SE LEE
--   Dos cosas: el aviso «ENSAYO OK: 38 de 38» (pestaña de mensajes) y la fila de control con
--   5 · 4 · 2 · 3 · 3 · 0 · true · false · true · true · 6 · 6
--   Si una prueba falla, aborta con «FALLA …» y no muestra la fila. Si el editor dice
--   "Success. No rows returned", no llegó al final y no vale.
-- LO ÚNICO QUE QUEDA: F1 y F2 entran por tienda_crear_pedido y consumen DOS números del correlativo de
--   pedidos (una secuencia no vuelve atrás con rollback). El próximo pedido real sale dos números más arriba.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE DDL (copia EXACTA del cuerpo de CAMBIO_TIENDA_FACTURA.sql, sin begin/commit ni el control) ▼▼▼
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
alter table public.tienda_tiquete
  add column correo_estado   text check (correo_estado in ('esperando','enviado','error','sin_correo')),
  add column correo_detalle  text,
  add column correo_intentos integer not null default 0,
  add column correo_en       timestamptz;

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

-- §5 · EL COMPROBANTE POR CORREO: tres RPC del servicio, con su clave, para socias y equipo (el robot de
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
       and (t.correo_estado is null or t.correo_estado = 'esperando' or (t.correo_estado = 'error' and t.correo_intentos < 5))
     order by p.numero limit 20) x;
  return v_r;
end;
$$;

revoke all on function public.tienda_comprobante_leer(text,bigint), public.tienda_comprobante_marcar(text,bigint,text,text),
                       public.tienda_comprobante_pendientes(text) from public, anon, authenticated;
grant execute on function public.tienda_comprobante_leer(text,bigint), public.tienda_comprobante_marcar(text,bigint,text,text),
                          public.tienda_comprobante_pendientes(text) to authenticated;
-- ▲▲▲ FIN DEL BLOQUE DDL ▲▲▲

-- ▼▼▼ LAS PRUEBAS (solo en el ensayo) ▼▼▼
-- La clave del servicio se reemplaza SOLO adentro de esta transacción. Los pedidos de prueba del servicio llevan
-- número negativo (no consumen el correlativo); los DOS que entran por tienda_crear_pedido (F1 y F2) sí consumen
-- dos números del correlativo aunque todo termine en rollback (una secuencia no se deshace): el próximo pedido real
-- sale dos números más arriba. No rompe nada (TIENDA-n sigue siendo único).
insert into public.ent_odoo_servicio_clave (id, hash) values (1, encode(sha256(convert_to('clave-ensayo','UTF8')),'hex'))
on conflict (id) do update set hash = excluded.hash;
insert into public.acceso_usuario (email, nombre, perfil, activo, nota, creado_por) values
  ('zz-socia@prueba.truefie','ZZ','socias',true,'ensayo','ensayo'), ('zz-equipo@prueba.truefie','ZZ','equipo',true,'ensayo','ensayo'),
  ('zz-asistente@prueba.truefie','ZZ','asistente',true,'ensayo','ensayo');
create function pg_temp.yo(p text) returns void language plpgsql as $f$
begin
  reset role;
  perform set_config('request.jwt.claims', case when p is null then '' else json_build_object('email',p,'role','authenticated')::text end, true);
  if p is null then set local role anon; else set local role authenticated; end if;
end $f$;
-- esp = un SQLSTATE de 5 caracteres (42501 permiso, 23514 check) o el texto exacto del raise.
create function pg_temp.rechaza(q text, esp text, nom text) returns void language plpgsql as $f$
declare msg text; st text;
begin
  begin execute q; exception when others then
    get stacked diagnostics msg = message_text, st = returned_sqlstate;
    if esp ~ '^[0-9A-Z]{5}$' and st <> esp then raise exception 'FALLA %: dio % «%»', nom, st, msg; end if;
    if esp !~ '^[0-9A-Z]{5}$' and msg <> esp then raise exception 'FALLA %: dio «%»', nom, msg; end if;
    return;
  end;
  raise exception 'FALLA % pasó', nom;
end $f$;
create function pg_temp.ped(p_id uuid, p_num bigint, p_est text, p_fe boolean) returns void language sql as $f$
  insert into public.tienda_pedido (id,numero,estado,nombre,telefono,entrega,metodo_pago,comprobante_path,subtotal_crc,envio_crc,total_crc,
                                    correo,fe_tipo,fe_numero,fe_nombre,fe_correo)
  overriding system value values (p_id,p_num,p_est,'Prueba','88880000','planta','sinpe',p_id||'/c.jpg',5500,0,5500,'ana@correo.cr',
    case when p_fe then '02' end, case when p_fe then '3101123456' end, case when p_fe then 'Café Prueba S.A.' end,
    case when p_fe then 'facturas@cafe.cr' end);
  insert into public.tienda_pedido_linea (pedido_id,producto_id,nombre,unidad_venta,cantidad,precio_crc) values (p_id,'blanco','Pan Blanco','unidad',1,5500);
$f$;
do $t$
declare
  u1 uuid := '99999999-9999-4999-8999-999999999991'; u2 uuid := '99999999-9999-4999-8999-999999999992';
  a uuid := '99999999-9999-4999-8999-999999999993'; b uuid := '99999999-9999-4999-8999-999999999994';
  c uuid := '99999999-9999-4999-8999-999999999995';
  base jsonb; j jsonb; n int; r public.tienda_pedido; huella text; malo record;
begin
  select md5(coalesce(string_agg(pedido_id::text||estado||coalesce(correo_estado,''), ',' order by pedido_id),'')) into huella from public.tienda_tiquete;
  insert into storage.objects(bucket_id,name) values ('tienda-comprobantes', u1||'/comprobante.jpg'), ('tienda-comprobantes', u2||'/comprobante.pdf');
  -- ── LA TIENDA (anon) ──
  perform pg_temp.yo(null);
  j := public.tienda_crear_pedido(jsonb_build_object('id',u1,'nombre','Ana','telefono','8888-0000','entrega','planta','metodo_pago','sinpe',
         'comprobante_path',u1||'/comprobante.jpg','total_crc',5500,'lineas','[{"id":"blanco","cant":1}]'::jsonb,'factura',null));
  reset role;
  select * into r from public.tienda_pedido where id = u1;
  if r.numero is null or r.correo is not null or r.fe_tipo is not null or r.fe_correo is not null then raise exception 'FALLA F1 la página vieja: %', row_to_json(r); end if;
  base := jsonb_build_object('id',u2,'nombre','Ana','telefono','8888-0000','entrega','planta','metodo_pago','sinpe',
         'comprobante_path',u2||'/comprobante.pdf','total_crc',5500,'lineas','[{"id":"blanco","cant":1}]'::jsonb,'correo',' Ana@Correo.CR ');
  -- Rechazos: revientan ANTES del insert (no consumen correlativo)
  perform pg_temp.yo(null);
  for malo in select * from (values
      ('F3 correo malo', base || '{"correo":"ana@correo"}'::jsonb, 'tienda:correo'),
      ('F4 correo con coma', base || '{"correo":"a@b.cr,c@d.cr"}'::jsonb, 'tienda:correo'),
      ('F5 física de 8', base || '{"factura":{"tipo":"01","numero":"11234567","nombre":"Ana Mora"}}'::jsonb, 'tienda:factura'),
      ('F6 física con cero', base || '{"factura":{"tipo":"01","numero":"012345678","nombre":"Ana Mora"}}'::jsonb, 'tienda:factura'),
      ('F7 jurídica de 9', base || '{"factura":{"tipo":"02","numero":"310112345","nombre":"Café S.A."}}'::jsonb, 'tienda:factura'),
      ('F8 DIMEX de 10', base || '{"factura":{"tipo":"03","numero":"1234567890","nombre":"Ana Mora"}}'::jsonb, 'tienda:factura'),
      ('F9 tipo 05', base || '{"factura":{"tipo":"05","numero":"1234567890","nombre":"Ana Mora"}}'::jsonb, 'tienda:factura'),
      ('F10 nombre de 1', base || '{"factura":{"tipo":"02","numero":"3101123456","nombre":"A"}}'::jsonb, 'tienda:factura'),
      ('F11 factura sin ningún correo', (base - 'correo') || '{"factura":{"tipo":"02","numero":"3101123456","nombre":"Café S.A."}}'::jsonb, 'tienda:factura'),
      ('F12 factura que no es objeto', base || '{"factura":"sí"}'::jsonb, 'tienda:factura')) x(nom, pay, esp) loop
    begin
      perform public.tienda_crear_pedido(malo.pay);
      raise exception 'FALLA % pasó', malo.nom;
    exception when raise_exception then
      declare msg text; begin
        get stacked diagnostics msg = message_text;
        if msg <> malo.esp then raise exception 'FALLA %: dio «%»', malo.nom, msg; end if;
      end;
    end;
  end loop;
  -- Con factura, cédula con guiones, sin correo de factura (usa el del pedido)
  j := public.tienda_crear_pedido(base || '{"factura":{"tipo":"02","numero":"3-101-123456","nombre":"  Café Prueba S.A. "}}'::jsonb);
  reset role;
  select * into r from public.tienda_pedido where id = u2;
  if r.correo <> 'ana@correo.cr' or r.fe_tipo <> '02' or r.fe_numero <> '3101123456' or r.fe_nombre <> 'Café Prueba S.A.'
     or r.fe_correo <> 'ana@correo.cr' or r.total_crc <> 5500 then raise exception 'FALLA F2 factura guardada mal: %', row_to_json(r); end if;
  -- Las reglas viven también en la tabla
  perform pg_temp.rechaza($q$update public.tienda_pedido set fe_numero='310112345' where id='$q$||u2||$q$'$q$, '23514', 'F13 check: jurídica de 9');
  perform pg_temp.rechaza($q$update public.tienda_pedido set fe_nombre=null where id='$q$||u2||$q$'$q$, '23514', 'F14 check: factura a medias');
  perform pg_temp.rechaza($q$update public.tienda_pedido set correo='sin-arroba' where id='$q$||u2||$q$'$q$, '23514', 'F15 check: correo');
  -- ── EL SERVICIO ──
  perform pg_temp.ped(a, -31, 'entregado', true); perform pg_temp.ped(b, -32, 'entregado', false); perform pg_temp.ped(c, -33, 'entregado', true);
  insert into public.tienda_pedido_evento (pedido_id,de_estado,a_estado,por) values
    (a,'pago_recibido','entregado','zz-socia@prueba.truefie'), (b,'pago_recibido','entregado','zz-socia@prueba.truefie');
  insert into public.tienda_tiquete (pedido_id) values (a), (b);
  insert into public.tienda_tiquete (pedido_id, estado, move_id, creado_en) values (c, 'creado', 777, now() - interval '8 days');
  perform pg_temp.yo('zz-socia@prueba.truefie');
  j := public.tienda_tiquete_reclamar('clave-ensayo', -31);
  if j#>'{pedido,factura}' <> '{"tipo":"02","numero":"3101123456","nombre":"Café Prueba S.A.","correo":"facturas@cafe.cr"}'::jsonb
     or j#>>'{pedido,correo}' <> 'ana@correo.cr' then raise exception 'FALLA R1 reclamar no trae la factura: %', j; end if;
  j := public.tienda_tiquete_reclamar('clave-ensayo', -32);
  if j#>'{pedido,factura}' <> 'null'::jsonb or j#>>'{pedido,total_crc}' <> '5500' then raise exception 'FALLA R2 sin factura: %', j; end if;
  j := public.tienda_comprobante_leer('clave-ensayo', -31);
  if j->>'estado' <> 'en_curso' then raise exception 'FALLA C1 leer antes de creado: %', j; end if;
  perform public.tienda_tiquete_cerrar('clave-ensayo', -31, 43000);
  j := public.tienda_comprobante_leer('clave-ensayo', -31);
  if j <> '{"estado":"creado","move_id":43000,"factura":true,"nombre":"Café Prueba S.A.","destino":"facturas@cafe.cr","total_crc":5500,"correo_estado":null}'::jsonb
    then raise exception 'FALLA C2 leer: %', j; end if;
  perform public.tienda_tiquete_cerrar('clave-ensayo', -32, 43001);
  if public.tienda_comprobante_leer('clave-ensayo', -32)->>'destino' <> 'ana@correo.cr' or (public.tienda_comprobante_leer('clave-ensayo', -32)->>'factura')::boolean
    then raise exception 'FALLA C3 tiquete: el correo del pedido'; end if;
  -- Permisos
  perform pg_temp.rechaza($q$select public.tienda_comprobante_leer('mala', -31)$q$, '42501', 'C4 clave mala lee');
  perform pg_temp.rechaza($q$select public.tienda_comprobante_marcar('mala', -31, 'enviado', null)$q$, '42501', 'C5 clave mala marca');
  perform pg_temp.rechaza($q$select public.tienda_comprobante_pendientes('mala')$q$, '42501', 'C6 clave mala pendientes');
  perform pg_temp.rechaza($q$update public.tienda_tiquete set correo_estado='enviado'$q$, '42501', 'C7 socia escribe directo');
  perform pg_temp.yo(null);
  perform pg_temp.rechaza($q$select public.tienda_comprobante_leer('clave-ensayo', -31)$q$, '42501', 'C8 anon');
  perform pg_temp.yo('zz-asistente@prueba.truefie');
  perform pg_temp.rechaza($q$select public.tienda_comprobante_leer('clave-ensayo', -31)$q$, 'tienda:perfil', 'C9 asistente');
  perform pg_temp.yo('zz-nadie@prueba.truefie');
  perform pg_temp.rechaza($q$select public.tienda_comprobante_marcar('clave-ensayo', -31, 'enviado', null)$q$, 'tienda:perfil', 'C10 sin perfil');
  -- El ciclo del correo (como el robot: equipo)
  perform pg_temp.yo('zz-equipo@prueba.truefie');
  j := public.tienda_comprobante_pendientes('clave-ensayo');
  if not (j @> '[-31, -32]'::jsonb) or j @> '[-33]'::jsonb then raise exception 'FALLA C11 pendientes (y el de 8 días no): %', j; end if;
  if not public.tienda_comprobante_marcar('clave-ensayo', -31, 'esperando', 'Hacienda: procesando') then raise exception 'FALLA C12 marcar'; end if;
  if not (public.tienda_comprobante_pendientes('clave-ensayo') @> '[-31]'::jsonb) then raise exception 'FALLA C13 esperando sigue pendiente'; end if;
  for n in 1..5 loop perform public.tienda_comprobante_marcar('clave-ensayo', -32, 'error', 'correo_fallo: SMTP'); end loop;
  if public.tienda_comprobante_pendientes('clave-ensayo') @> '[-32]'::jsonb then raise exception 'FALLA C14 cinco errores: ya no es del repaso'; end if;
  if not public.tienda_comprobante_marcar('clave-ensayo', -31, 'enviado', null) then raise exception 'FALLA C15 enviado'; end if;
  if public.tienda_comprobante_marcar('clave-ensayo', -31, 'esperando', null) then raise exception 'FALLA C16 enviado se pisó'; end if;
  if public.tienda_comprobante_pendientes('clave-ensayo') @> '[-31]'::jsonb then raise exception 'FALLA C17 enviado sigue pendiente'; end if;
  perform pg_temp.rechaza($q$select public.tienda_comprobante_marcar('clave-ensayo', -31, 'mandado', null)$q$, 'tienda:datos', 'C18 estado inválido');
  reset role;
  if (select correo_estado||correo_intentos||(correo_en is not null)::text from public.tienda_tiquete where pedido_id=a) <> 'enviado0true'
     or (select correo_estado||correo_intentos||correo_detalle from public.tienda_tiquete where pedido_id=b) <> 'error5correo_fallo: SMTP'
    then raise exception 'FALLA C19 lo que quedó en la tabla'; end if;
  insert into public.tienda_tiquete (pedido_id) values (u1);
  perform pg_temp.yo('zz-socia@prueba.truefie');
  if public.tienda_comprobante_marcar('clave-ensayo', (select numero from public.tienda_pedido where id=u1), 'enviado', null)
    then raise exception 'FALLA C20 marcar un tiquete sin crear'; end if;
  reset role;
  if md5(coalesce((select string_agg(pedido_id::text||estado||coalesce(correo_estado,''), ',' order by pedido_id) from public.tienda_tiquete
                    where pedido_id not in (u1,u2,a,b,c)),'')) <> huella then raise exception 'FALLA C21 un tiquete real cambió'; end if;
  raise notice 'ENSAYO OK: 38 de 38';
end $t$;
-- ▲▲▲ FIN DE LAS PRUEBAS ▲▲▲

-- CONTROL. ESPERADO: 5 · 4 · 2 · 3 · 3 · 0 · true · false · true · true · 6 · 6
with rpc(f) as (values ('public.tienda_comprobante_leer(text,bigint)'), ('public.tienda_comprobante_marcar(text,bigint,text,text)'),
                       ('public.tienda_comprobante_pendientes(text)'))
select (select count(*) from information_schema.columns where table_schema='public' and table_name='tienda_pedido'
         and column_name in ('correo','fe_tipo','fe_numero','fe_nombre','fe_correo')) as columnas_pedido,
       (select count(*) from information_schema.columns where table_schema='public' and table_name='tienda_tiquete'
         and column_name in ('correo_estado','correo_detalle','correo_intentos','correo_en')) as columnas_tiquete,
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

rollback;
