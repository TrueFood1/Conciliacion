-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_ENTREGA_AUTO_RASTRO.sql  ·  26-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Prueba ENTREGA_AUTO_RASTRO.sql (clave del servicio, reclamo y rastro de /auto) con
-- datos inventados dentro de la transacción, y lo deshace TODO (rollback). NO SE CORRIÓ.
--
-- CÓMO SE LEE
--   Una tabla de 34 filas, TODAS con ok = true. Un RECHAZA da ok solo si el SQLSTATE
--   es 42501. Las de esperado true/false son lo que devuelve la función. Si el editor
--   dice "Success. No rows returned", no llegó al final y no vale.
--   Necesita una socia, alguien de «equipo» y el asistente activos en acceso_usuario.
--   La clave es una inventada ('clave-de-ensayo'), no la del servicio.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

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

do $$
declare
  v_socia text; v_equipo text; v_asist text; v_clave text := 'clave-de-ensayo';
  v_p1 bigint; v_p2 bigint; v_p3 bigint; v_p4 bigint; v_a bigint; v_s bigint;
  v_pn1 bigint; v_n int; v_b boolean; v_p5 bigint; v_a6 bigint;
  v_res jsonb := '[]'::jsonb;
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by id limit 1;
  select email into v_equipo from v_acceso_usuario where perfil = 'equipo' and activo order by id limit 1;
  select email into v_asist  from v_acceso_usuario where perfil = 'asistente' and activo order by id limit 1;
  if v_socia is null or v_equipo is null or v_asist is null then
    raise exception 'el ensayo necesita una socia, alguien de equipo y el asistente (socia %, equipo %, asistente %)',
      v_socia is not null, v_equipo is not null, v_asist is not null;
  end if;

  -- ── los datos inventados (como postgres, adentro de la transacción) ──
  insert into ent_odoo_servicio_clave (id, hash) values (1, encode(sha256(convert_to(v_clave, 'UTF8')), 'hex'));
  -- p1: Daniel entregó recién · p2: entregó la socia · p3: Daniel, hace 31 min · p4: Daniel, anulada
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por) values (current_date, 'manual', 'regalia', v_equipo) returning id into v_p1;
  insert into ent_alisto (pedido_id, responsable, creado_por) values (v_p1, v_equipo, v_equipo) returning id into v_a;
  insert into ent_salida (alisto_id, creado_por) values (v_a, v_equipo);
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por) values (current_date, 'manual', 'regalia', v_socia) returning id into v_p2;
  insert into ent_alisto (pedido_id, responsable, creado_por) values (v_p2, v_socia, v_socia) returning id into v_a;
  insert into ent_salida (alisto_id, creado_por) values (v_a, v_socia);
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por) values (current_date, 'manual', 'regalia', v_equipo) returning id into v_p3;
  insert into ent_alisto (pedido_id, responsable, creado_por) values (v_p3, v_equipo, v_equipo) returning id into v_a;
  insert into ent_salida (alisto_id, creado_por, creado_en) values (v_a, v_equipo, now() - interval '31 minutes');
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por) values (current_date, 'manual', 'regalia', v_equipo) returning id into v_p4;
  insert into ent_alisto (pedido_id, responsable, creado_por) values (v_p4, v_equipo, v_equipo) returning id into v_a;
  insert into ent_salida (alisto_id, creado_por) values (v_a, v_equipo) returning id into v_s;
  insert into ent_anulacion (entidad, entidad_id, motivo, creado_por) values ('salida', v_s, 'ensayo', v_socia);
  insert into ent_odoo_pendiente (tipo, pedido_id, fecha, creado_por) values ('traslado_interno', v_p1, current_date, v_equipo) returning id into v_pn1;
  -- p5: Daniel, DOS salidas (la primera hace 5 min) · a6: un alisto para probar el insert de ent_salida
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por) values (current_date, 'manual', 'regalia', v_equipo) returning id into v_p5;
  insert into ent_alisto (pedido_id, responsable, creado_por) values (v_p5, v_equipo, v_equipo) returning id into v_a;
  insert into ent_salida (alisto_id, creado_por, creado_en) values (v_a, v_equipo, now() - interval '5 minutes');
  insert into ent_salida (alisto_id, creado_por) values (v_a, v_equipo);
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por) values (current_date, 'manual', 'regalia', v_equipo) returning id into v_a6;
  insert into ent_alisto (pedido_id, responsable, creado_por) values (v_a6, v_equipo, v_equipo) returning id into v_a6;

  -- ── equipo (Daniel) ──
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into ent_odoo_validacion (pedido_id, factura_id, picking_id, picking_nombre, lineas, validado_por) values (v_p1, -1, -901, 'WH/OUT/FALSO', '[{"producto_id":481,"uds":5}]', v_equipo);
    v_res := v_res || jsonb_build_object('p','D1 equipo inserta DIRECTO en ent_odoo_validacion','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D1 equipo inserta DIRECTO en ent_odoo_validacion','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_odoo_traslado (pedido_id, picking_id, picking_nombre, motivo, destino_id, contacto_id, lineas, creado_por) values (v_p1, -902, 'WH/INT/FALSO', 'regalia', 19, 1260, '[{"producto_id":451,"uds":6}]', v_equipo);
    v_res := v_res || jsonb_build_object('p','D2 equipo inserta DIRECTO en ent_odoo_traslado','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D2 equipo inserta DIRECTO en ent_odoo_traslado','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_odoo_hecho (pendiente_id, referencia, creado_por) values (v_pn1, 'WH/INT/FALSO', v_equipo);
    v_res := v_res || jsonb_build_object('p','D3 equipo inserta DIRECTO en ent_odoo_hecho','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D3 equipo inserta DIRECTO en ent_odoo_hecho','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    select count(*) into v_n from ent_odoo_servicio_clave;
    v_res := v_res || jsonb_build_object('p','D4 equipo lee el hash de la clave','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D4 equipo lee el hash de la clave','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_odoo_reclamo (pedido_id, por, ruta) values (v_p1, v_equipo, 'auto');
    v_res := v_res || jsonb_build_object('p','D5 equipo escribe un reclamo directo','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D5 equipo escribe un reclamo directo','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    perform _ent_odoo_clave_ok('x');
    v_res := v_res || jsonb_build_object('p','D6 equipo prueba claves con _ent_odoo_clave_ok','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D6 equipo prueba claves con _ent_odoo_clave_ok','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    select ent_odoo_reclamar(v_clave, v_p1, 'auto') into v_b;
    v_res := v_res || jsonb_build_object('p','R1 equipo reclama SU salida de recién, con la clave','esperado','true','obtenido',coalesce(v_b::text,'null'),'ok',v_b is not distinct from true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R1 equipo reclama SU salida de recién, con la clave','esperado','true','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    select ent_odoo_reclamar(v_clave, v_p1, 'auto') into v_b;
    v_res := v_res || jsonb_build_object('p','R2 equipo reclama el mismo pedido otra vez','esperado','false','obtenido',coalesce(v_b::text,'null'),'ok',v_b is not distinct from false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R2 equipo reclama el mismo pedido otra vez','esperado','false','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    perform ent_odoo_reclamar('no-es-la-clave', v_p1, 'auto');
    v_res := v_res || jsonb_build_object('p','R3 equipo reclama con la clave equivocada','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R3 equipo reclama con la clave equivocada','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    perform ent_odoo_reclamar(v_clave, v_p1, 'validar');
    v_res := v_res || jsonb_build_object('p','R4 equipo reclama por la ruta de /validar','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R4 equipo reclama por la ruta de /validar','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    perform ent_odoo_reclamar(v_clave, v_p2, 'auto');
    v_res := v_res || jsonb_build_object('p','R5 equipo reclama la salida de la socia','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R5 equipo reclama la salida de la socia','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    perform ent_odoo_reclamar(v_clave, v_p3, 'auto');
    v_res := v_res || jsonb_build_object('p','R6 equipo reclama SU salida de hace 31 min','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R6 equipo reclama SU salida de hace 31 min','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    perform ent_odoo_reclamar(v_clave, v_p4, 'auto');
    v_res := v_res || jsonb_build_object('p','R7 equipo reclama SU salida anulada','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R7 equipo reclama SU salida anulada','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    perform ent_odoo_rastro_auto(v_clave, 'validacion', jsonb_build_object('pedido_id', v_p1, 'factura_id', -1, 'picking_id', -101, 'picking_nombre', 'WH/OUT/ENSAYO101', 'lineas', '[{"producto_id":481,"uds":5}]'::jsonb, 'validado_por', v_socia));
    v_res := v_res || jsonb_build_object('p','W1 rastro de validación por la RPC (firma la socia en el cuerpo)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','W1 rastro de validación por la RPC (firma la socia en el cuerpo)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    perform ent_odoo_rastro_auto(v_clave, 'traslado', jsonb_build_object('pedido_id', v_p1, 'picking_id', -201, 'picking_nombre', 'WH/INT/ENSAYO201', 'motivo', 'regalia', 'destino_id', 19, 'contacto_id', 1260, 'lineas', '[{"producto_id":451,"uds":6}]'::jsonb));
    v_res := v_res || jsonb_build_object('p','W2 rastro de traslado por la RPC, con su «hecho»','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','W2 rastro de traslado por la RPC, con su «hecho»','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    perform ent_odoo_rastro_auto(v_clave, 'validacion', jsonb_build_object('pedido_id', v_p2, 'factura_id', -1, 'picking_id', -102, 'picking_nombre', 'WH/OUT/ENSAYO102', 'lineas', '[{"producto_id":481,"uds":5}]'::jsonb, 'validado_por', v_socia));
    v_res := v_res || jsonb_build_object('p','W3 rastro de un pedido que no reclamó','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','W3 rastro de un pedido que no reclamó','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    perform ent_odoo_rastro_auto('no-es-la-clave', 'validacion', jsonb_build_object('pedido_id', v_p1, 'factura_id', -1, 'picking_id', -103, 'picking_nombre', 'WH/OUT/ENSAYO103', 'lineas', '[{"producto_id":481,"uds":5}]'::jsonb, 'validado_por', v_socia));
    v_res := v_res || jsonb_build_object('p','W4 rastro con la clave equivocada','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','W4 rastro con la clave equivocada','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    select ent_odoo_soltar(v_clave, v_p1) into v_b;
    v_res := v_res || jsonb_build_object('p','S1 equipo suelta su reclamo','esperado','true','obtenido',coalesce(v_b::text,'null'),'ok',v_b is not distinct from true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S1 equipo suelta su reclamo','esperado','true','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;

  -- ── la socia ──
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  begin
    select ent_odoo_reclamar(v_clave, v_p1, 'validar') into v_b;
    v_res := v_res || jsonb_build_object('p','S2 la socia reclama el pedido suelto','esperado','true','obtenido',coalesce(v_b::text,'null'),'ok',v_b is not distinct from true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S2 la socia reclama el pedido suelto','esperado','true','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ent_salida (alisto_id, creado_por) values (v_a6, v_socia);
    v_res := v_res || jsonb_build_object('p','E4 la socia registra una salida con SU correo','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E4 la socia registra una salida con SU correo','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  begin
    select ent_odoo_reclamar(v_clave, v_p1, 'auto') into v_b;
    v_res := v_res || jsonb_build_object('p','S3 equipo no lo puede reclamar mientras lo tiene la socia','esperado','false','obtenido',coalesce(v_b::text,'null'),'ok',v_b is not distinct from false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S3 equipo no lo puede reclamar mientras lo tiene la socia','esperado','false','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    select ent_odoo_soltar(v_clave, v_p1) into v_b;
    v_res := v_res || jsonb_build_object('p','S4 equipo no suelta el reclamo de la socia','esperado','false','obtenido',coalesce(v_b::text,'null'),'ok',v_b is not distinct from false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S4 equipo no suelta el reclamo de la socia','esperado','false','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    perform ent_odoo_reclamar(v_clave, v_p5, 'auto');
    v_res := v_res || jsonb_build_object('p','R8 equipo reclama un pedido con DOS salidas','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R8 equipo reclama un pedido con DOS salidas','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_salida (alisto_id, creado_por) values (v_a6, v_equipo);
    v_res := v_res || jsonb_build_object('p','E1 equipo registra una salida con SU correo','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E1 equipo registra una salida con SU correo','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ent_salida (alisto_id, creado_por) values (v_a6, v_socia);
    v_res := v_res || jsonb_build_object('p','E2 equipo registra una salida a nombre de la socia','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E2 equipo registra una salida a nombre de la socia','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_salida (alisto_id, creado_por) values (v_a6, upper(v_equipo));
    v_res := v_res || jsonb_build_object('p','E3 equipo, su correo en MAYÚSCULAS','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E3 equipo, su correo en MAYÚSCULAS','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('role', 'postgres', true);
  update ent_odoo_reclamo set en = now() - interval '11 minutes' where pedido_id = v_p1;
  perform set_config('role', 'authenticated', true);
  begin
    select ent_odoo_reclamar(v_clave, v_p1, 'auto') into v_b;
    v_res := v_res || jsonb_build_object('p','V1 el reclamo de la socia venció (11 min): equipo lo toma','esperado','true','obtenido',coalesce(v_b::text,'null'),'ok',v_b is not distinct from true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','V1 el reclamo de la socia venció (11 min): equipo lo toma','esperado','true','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;

  -- ── el asistente ──
  perform set_config('request.jwt.claims', json_build_object('email', v_asist, 'role', 'authenticated')::text, true);
  begin
    perform ent_odoo_reclamar(v_clave, v_p1, 'validar');
    v_res := v_res || jsonb_build_object('p','A1 el asistente reclama','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A1 el asistente reclama','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    perform ent_odoo_rastro_auto(v_clave, 'validacion', jsonb_build_object('pedido_id', v_p1, 'factura_id', -1, 'picking_id', -104, 'picking_nombre', 'WH/OUT/ENSAYO104', 'lineas', '[{"producto_id":481,"uds":5}]'::jsonb, 'validado_por', v_socia));
    v_res := v_res || jsonb_build_object('p','A2 el asistente escribe rastro','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A2 el asistente escribe rastro','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── anon ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
  begin
    perform ent_odoo_reclamar(v_clave, v_p1, 'validar');
    v_res := v_res || jsonb_build_object('p','N1 anon reclama','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','N1 anon reclama','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    perform ent_odoo_rastro_auto(v_clave, 'validacion', jsonb_build_object('pedido_id', v_p1, 'factura_id', -1, 'picking_id', -105, 'picking_nombre', 'WH/OUT/ENSAYO105', 'lineas', '[{"producto_id":481,"uds":5}]'::jsonb, 'validado_por', v_socia));
    v_res := v_res || jsonb_build_object('p','N2 anon escribe rastro','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','N2 anon escribe rastro','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── editor SQL: lo que quedó adentro ──
  perform set_config('role', 'postgres', true);
  select count(*) into v_n from ent_odoo_validacion where pedido_id = v_p1 and picking_id = -101 and validado_por = v_equipo;
  v_res := v_res || jsonb_build_object('p','Z1 UNA validación, firmada por el TOKEN (equipo), no por el cuerpo','esperado','1','obtenido',v_n::text,'ok',v_n=1);
  select (select count(*) from ent_odoo_traslado where pedido_id = v_p1 and creado_por = v_equipo)
       + (select count(*) from ent_odoo_hecho where pendiente_id = v_pn1 and referencia = 'WH/INT/ENSAYO201' and creado_por = v_equipo)
    into v_n;
  v_res := v_res || jsonb_build_object('p','Z2 UN traslado y SU «hecho»','esperado','2','obtenido',v_n::text,'ok',v_n=2);
  select count(*) into v_n from ent_odoo_validacion where picking_id in (-901, -102, -103, -104, -105);
  v_res := v_res || jsonb_build_object('p','Z3 ninguno de los rechazados dejó fila','esperado','0','obtenido',v_n::text,'ok',v_n=0);

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: 34 filas, todas ok = true.

rollback;
