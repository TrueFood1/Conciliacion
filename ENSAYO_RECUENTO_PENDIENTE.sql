-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_RECUENTO_PENDIENTE.sql · 30-oct-2026 · b151 · TERMINA EN ROLLBACK
-- Generado por armar.py: el bloque DDL es copia LITERAL de CAMBIO_RECUENTO_PENDIENTE.sql.
-- Reproduce la entrega de Intimo (factura 3613) con un pedido de ENSAYO: Blanco 250×2 +
-- 257×1 y Buns 266×3 paquetes, como el perfil equipo; abre el pendiente del 250 y prueba
-- las guardas (firma, forma, calce con la linea, RLS, solo insercion, cierre de socias).
-- Se corre ENTERO. La ultima fila dice «N de N ok». No deja nada: rollback.
-- ═══════════════════════════════════════════════════════════════════════════
begin;
-- ▼▼▼ BLOQUE DDL ▼▼▼
do $$ begin
  if to_regclass('public.ent_recuento_pendiente') is not null then
    raise exception 'ent_recuento_pendiente ya existe: este pegado ya corrio. No se vuelve a pegar.';
  end if;
end $$;

create table public.ent_recuento_pendiente (
  id                bigint generated always as identity primary key,
  cierra_id         bigint references public.ent_recuento_pendiente(id),
  producto_id       integer,
  lote              text,
  saldo_resultante  numeric,
  unidad_venta      text,
  alisto_lote_id    bigint references public.ent_alisto_lote(id),
  pedido_id         bigint references public.ent_pedido(id),
  motivo            text not null,
  nota              text,
  creado_por        text not null,
  creado_en         timestamptz not null default now(),
  constraint ent_recuento_pendiente_forma_ok check (
    (cierra_id is null
       and producto_id is not null and lote is not null and btrim(lote) <> ''
       and saldo_resultante is not null and saldo_resultante < 0
       and unidad_venta in ('unidad','paquete')
       and alisto_lote_id is not null and pedido_id is not null
       and motivo = 'despacho con lote en 0')
    or
    (cierra_id is not null
       and producto_id is null and lote is null and saldo_resultante is null
       and unidad_venta is null and alisto_lote_id is null and pedido_id is null
       and motivo = 'recuento'
       and nota is not null and length(btrim(nota)) >= 3)
  )
);
comment on table public.ent_recuento_pendiente is
  'Lotes que quedaron negativos al despachar con el lote en 0 en Truefie. Solo de insercion: '
  'cierra_id NULL abre, cierra_id = id cierra (solo socias). saldo_resultante en unidad de venta.';

create unique index ent_recuento_pendiente_un_cierre
  on public.ent_recuento_pendiente(cierra_id) where cierra_id is not null;
create unique index ent_recuento_pendiente_una_por_linea
  on public.ent_recuento_pendiente(alisto_lote_id) where cierra_id is null;
create index ent_recuento_pendiente_lote
  on public.ent_recuento_pendiente(producto_id, lote) where cierra_id is null;

create or replace function public.ent_recuento_pendiente_guard()
returns trigger language plpgsql security invoker set search_path = public as $$
declare
  v_quien text;
  v_abre  record;
begin
  -- La firma sale de la sesion, nunca de la fila.
  v_quien := lower(btrim(nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email'));
  if v_quien is null or v_quien = '' then
    raise exception 'un pendiente de recuento se registra desde la pantalla, con sesion iniciada: '
      'sin sesion no se sabe quien lo hizo';
  end if;
  if new.creado_por is not null and lower(btrim(new.creado_por)) <> v_quien then
    raise exception 'creado_por dice % y la sesion es de %. La firma no se elige.',
      new.creado_por, v_quien;
  end if;
  new.creado_por := v_quien;
  new.creado_en  := now();

  if new.cierra_id is null then
    -- ABRIR: la linea de lote tiene que existir y ser de ESTE lote y producto,
    -- y del pedido que dice.
    if not exists (
      select 1 from ent_alisto_lote al
        join ent_alisto_linea ln on ln.id = al.linea_id
        join ent_alisto a        on a.id  = ln.alisto_id
        join ent_alisto_vigente av on av.alisto_id = a.id
        join ent_pedido p        on p.id  = a.pedido_id
       where al.id = new.alisto_lote_id and al.lote = new.lote
         and ln.producto_id = new.producto_id and a.pedido_id = new.pedido_id
         and lower(btrim(p.creado_por)) = v_quien) then
      raise exception 'el pendiente no calza con la salida: la linea de lote % no es del lote % '
        'del producto % en una preparacion vigente del pedido %, hecha por %',
        new.alisto_lote_id, new.lote, new.producto_id, new.pedido_id, v_quien;
    end if;
  else
    -- CERRAR: solo socias, y solo un pendiente abierto (no un cierre).
    if not acceso_es_socia() then
      raise exception 'cerrar un pendiente de recuento es de un perfil socias, y % no lo es.', v_quien;
    end if;
    select * into v_abre from ent_recuento_pendiente where id = new.cierra_id;
    if v_abre.id is null or v_abre.cierra_id is not null then
      raise exception 'cierra_id % no es un pendiente abierto', new.cierra_id;
    end if;
  end if;
  return new;
end $$;

create trigger ent_recuento_pendiente_guard_trg
  before insert on public.ent_recuento_pendiente
  for each row execute function public.ent_recuento_pendiente_guard();

create or replace function public.ent_recuento_pendiente_inmutable()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'ent_recuento_pendiente es solo de insercion: un pendiente se cierra con otra '
    'fila (cierra_id), nunca con % ', tg_op using errcode = '42501';
end $$;

create trigger ent_recuento_pendiente_inmutable_trg
  before update or delete on public.ent_recuento_pendiente
  for each row execute function public.ent_recuento_pendiente_inmutable();
create trigger ent_recuento_pendiente_sin_truncate_trg
  before truncate on public.ent_recuento_pendiente
  for each statement execute function public.ent_recuento_pendiente_inmutable();

alter table public.ent_recuento_pendiente enable row level security;
create policy ent_recuento_pendiente_sel on public.ent_recuento_pendiente
  for select to authenticated using (true);
create policy ent_recuento_pendiente_ins on public.ent_recuento_pendiente
  for insert to authenticated with check (cierra_id is null or acceso_es_socia());

revoke all on public.ent_recuento_pendiente from anon, authenticated;
grant select, insert on public.ent_recuento_pendiente to authenticated;
revoke all on function public.ent_recuento_pendiente_guard() from public, anon;
revoke all on function public.ent_recuento_pendiente_inmutable() from public, anon;

create view public.ent_recuento_pendiente_abierto with (security_invoker = true) as
  select p.id, p.producto_id, p.lote, p.saldo_resultante, p.unidad_venta,
         p.alisto_lote_id, p.pedido_id, p.motivo, p.creado_por, p.creado_en
    from public.ent_recuento_pendiente p
   where p.cierra_id is null
     and not exists (select 1 from public.ent_recuento_pendiente c where c.cierra_id = p.id);
revoke all on public.ent_recuento_pendiente_abierto from anon, authenticated;
grant select on public.ent_recuento_pendiente_abierto to authenticated;
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲
do $ensayo$
declare
  v_res jsonb := '[]'::jsonb; v_txt text;
  v_eq text; v_eq2 text; v_so text; v_as text; v_l250 text; v_l257 text; v_l266 text;
  v_s250 numeric; v_s257 numeric; v_s266 numeric;
  v_ped bigint; v_ali bigint; v_lnb bigint; v_lnu bigint; v_al250 bigint; v_al257 bigint; v_al266 bigint;
  r jsonb; v_ok int := 0; v_n int := 0;
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);
  select lower(email) into v_eq from v_acceso_usuario where activo and perfil='equipo' order by email limit 1;
  select lower(email) into v_eq2 from v_acceso_usuario where activo and perfil='equipo' and lower(email)<>v_eq order by email limit 1;
  select lower(email) into v_so from v_acceso_usuario where activo and perfil='socias' order by email limit 1;
  select lower(email) into v_as from v_acceso_usuario where activo and perfil='asistente' order by email limit 1;
  select lote into v_l250 from ent_conteo_linea where conteo_id=(select id from ent_ancla) and producto_id=451 and lote like '250 /%' limit 1;
  select lote into v_l257 from ent_conteo_linea where conteo_id=(select id from ent_ancla) and producto_id=451 and lote like '257 /%' limit 1;
  v_l250 := coalesce(v_l250,'250 / 6-27'); v_l257 := coalesce(v_l257,'257 / 6-27'); v_l266 := '266 / 6-27';
  select coalesce(sum(uds) filter (where producto_id=451 and lote=v_l250),0),
         coalesce(sum(uds) filter (where producto_id=451 and lote=v_l257),0),
         coalesce(sum(uds) filter (where producto_id=503 and lote=v_l266),0)
    into v_s250, v_s257, v_s266 from ent_salido_del_congelador_desde_ancla;
  perform set_config('request.jwt.claims', json_build_object('email', v_eq, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  insert into ent_pedido(fecha_despacho,origen,factura_id,factura_nombre,cliente_id,cliente_nombre,motivo,creado_por)
    values (current_date,'factura',-3613,'ENSAYO 3613',657,'ENSAYO Intimo','venta',v_eq) returning id into v_ped;
  insert into ent_alisto(pedido_id,responsable,creado_por) values (v_ped,v_eq,v_eq) returning id into v_ali;
  insert into ent_alisto_linea(alisto_id,producto_id,cant_uds,cant_uom) values (v_ali,451,3,3) returning id into v_lnb;
  insert into ent_alisto_linea(alisto_id,producto_id,cant_uds,cant_uom) values (v_ali,503,12,3) returning id into v_lnu;
  insert into ent_alisto_lote(linea_id,lote,cant_uds,orden) values (v_lnb,v_l250,2,0) returning id into v_al250;
  insert into ent_alisto_lote(linea_id,lote,cant_uds,orden) values (v_lnb,v_l257,1,1) returning id into v_al257;
  insert into ent_alisto_lote(linea_id,lote,cant_uds,orden) values (v_lnu,v_l266,12,0) returning id into v_al266;
  begin
    insert into ent_recuento_pendiente(producto_id,lote,saldo_resultante,unidad_venta,alisto_lote_id,pedido_id,motivo,creado_por) values (451,v_l250,-2,'unidad',v_al250,v_ped,'despacho con lote en 0',null);
    v_res := v_res || jsonb_build_object('p','A · Intimo: Daniel abre el pendiente del 250 (saldo -2 unidades)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A · Intimo: Daniel abre el pendiente del 250 (saldo -2 unidades)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_txt := coalesce((select (creado_por = v_eq) from ent_recuento_pendiente where alisto_lote_id=v_al250)::text, 'null');
    v_res := v_res || jsonb_build_object('p','A · la firma sale de la sesion (creado_por = el de equipo)','esperado','true','obtenido',v_txt,'ok',v_txt='true');
  exception when others then
    v_res := v_res || jsonb_build_object('p','A · la firma sale de la sesion (creado_por = el de equipo)','esperado','true','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_txt := coalesce((select lote=v_l250 and saldo_resultante=-2 and unidad_venta='unidad' from ent_recuento_pendiente_abierto where alisto_lote_id=v_al250)::text, 'null');
    v_res := v_res || jsonb_build_object('p','A · la vista de abiertos lo muestra: 250 · -2 · unidad','esperado','true','obtenido',v_txt,'ok',v_txt='true');
  exception when others then
    v_res := v_res || jsonb_build_object('p','A · la vista de abiertos lo muestra: 250 · -2 · unidad','esperado','true','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_txt := coalesce((select count(*) from ent_recuento_pendiente where alisto_lote_id in (v_al257,v_al266))::text, 'null');
    v_res := v_res || jsonb_build_object('p','B · el 257 y el 266 (con saldo) no abren pendiente','esperado','0','obtenido',v_txt,'ok',v_txt='0');
  exception when others then
    v_res := v_res || jsonb_build_object('p','B · el 257 y el 266 (con saldo) no abren pendiente','esperado','0','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_txt := coalesce((select count(*) from ent_recuento_pendiente where pedido_id=v_ped)::text, 'null');
    v_res := v_res || jsonb_build_object('p','A/B · un solo pendiente en todo el pedido','esperado','1','obtenido',v_txt,'ok',v_txt='1');
  exception when others then
    v_res := v_res || jsonb_build_object('p','A/B · un solo pendiente en todo el pedido','esperado','1','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ent_recuento_pendiente(producto_id,lote,saldo_resultante,unidad_venta,alisto_lote_id,pedido_id,motivo,creado_por) values (451,v_l250,-2,'unidad',v_al250,v_ped,'despacho con lote en 0',v_so);
    v_res := v_res || jsonb_build_object('p','firma ajena: creado_por de otra persona','esperado','RECHAZA · P0001','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','firma ajena: creado_por de otra persona','esperado','RECHAZA · P0001','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='P0001');
  end;
  begin
    insert into ent_recuento_pendiente(producto_id,lote,saldo_resultante,unidad_venta,alisto_lote_id,pedido_id,motivo,creado_por) values (451,v_l257,0,'unidad',v_al257,v_ped,'despacho con lote en 0',null);
    v_res := v_res || jsonb_build_object('p','saldo_resultante 0 no es pendiente','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','saldo_resultante 0 no es pendiente','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into ent_recuento_pendiente(producto_id,lote,saldo_resultante,unidad_venta,alisto_lote_id,pedido_id,motivo,creado_por) values (503,v_l266,-1,'pan',v_al266,v_ped,'despacho con lote en 0',null);
    v_res := v_res || jsonb_build_object('p','unidad inventada (panes sueltos)','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','unidad inventada (panes sueltos)','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into ent_recuento_pendiente(producto_id,lote,saldo_resultante,unidad_venta,alisto_lote_id,pedido_id,motivo,creado_por) values (451,v_l257,-1,'unidad',v_al250,v_ped,'despacho con lote en 0',null);
    v_res := v_res || jsonb_build_object('p','el lote no calza con la linea','esperado','RECHAZA · P0001','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','el lote no calza con la linea','esperado','RECHAZA · P0001','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='P0001');
  end;
  begin
    insert into ent_recuento_pendiente(producto_id,lote,saldo_resultante,unidad_venta,alisto_lote_id,pedido_id,motivo,creado_por) values (503,v_l250,-1,'paquete',v_al250,v_ped,'despacho con lote en 0',null);
    v_res := v_res || jsonb_build_object('p','el producto no calza con la linea','esperado','RECHAZA · P0001','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','el producto no calza con la linea','esperado','RECHAZA · P0001','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='P0001');
  end;
  begin
    insert into ent_recuento_pendiente(producto_id,lote,saldo_resultante,unidad_venta,alisto_lote_id,pedido_id,motivo,creado_por) values (451,v_l250,-3,'unidad',v_al250,v_ped,'despacho con lote en 0',null);
    v_res := v_res || jsonb_build_object('p','segundo pendiente para la misma linea','esperado','RECHAZA · 23505','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','segundo pendiente para la misma linea','esperado','RECHAZA · 23505','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23505');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_eq2, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into ent_recuento_pendiente(producto_id,lote,saldo_resultante,unidad_venta,alisto_lote_id,pedido_id,motivo,creado_por) values (451,v_l257,-1,'unidad',v_al257,v_ped,'despacho con lote en 0',null);
    v_res := v_res || jsonb_build_object('p','otro del equipo no cuelga un pendiente de un pedido ajeno','esperado','RECHAZA · P0001','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','otro del equipo no cuelga un pendiente de un pedido ajeno','esperado','RECHAZA · P0001','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='P0001');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_eq, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into ent_recuento_pendiente(producto_id,lote,saldo_resultante,unidad_venta,alisto_lote_id,pedido_id,motivo) values (451,v_l257,-1,'unidad',v_al257,v_ped,'otro');
    v_res := v_res || jsonb_build_object('p','motivo distinto','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','motivo distinto','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    update ent_recuento_pendiente set saldo_resultante=-1 where alisto_lote_id=v_al250;
    v_res := v_res || jsonb_build_object('p','D · equipo: UPDATE','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D · equipo: UPDATE','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    delete from ent_recuento_pendiente where alisto_lote_id=v_al250;
    v_res := v_res || jsonb_build_object('p','D · equipo: DELETE','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D · equipo: DELETE','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_recuento_pendiente(cierra_id,motivo,nota) select id,'recuento','contado' from ent_recuento_pendiente where alisto_lote_id=v_al250;
    v_res := v_res || jsonb_build_object('p','equipo no puede cerrar','esperado','RECHAZA · P0001','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','equipo no puede cerrar','esperado','RECHAZA · P0001','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='P0001');
  end;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into ent_recuento_pendiente(producto_id,lote,saldo_resultante,unidad_venta,alisto_lote_id,pedido_id,motivo,creado_por) values (451,v_l257,-1,'unidad',v_al257,v_ped,'despacho con lote en 0',null);
    v_res := v_res || jsonb_build_object('p','sin sesion no entra','esperado','RECHAZA · P0001','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','sin sesion no entra','esperado','RECHAZA · P0001','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='P0001');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_as, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into ent_recuento_pendiente(producto_id,lote,saldo_resultante,unidad_venta,alisto_lote_id,pedido_id,motivo,creado_por) values (451,v_l257,-1,'unidad',v_al257,v_ped,'despacho con lote en 0',null);
    v_res := v_res || jsonb_build_object('p','la asistente no abre pendientes','esperado','RECHAZA · P0001','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','la asistente no abre pendientes','esperado','RECHAZA · P0001','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='P0001');
  end;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
  begin
    perform count(*) from ent_recuento_pendiente;
    v_res := v_res || jsonb_build_object('p','anon no lee','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','anon no lee','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);
  begin
    update ent_recuento_pendiente set saldo_resultante=-1 where alisto_lote_id=v_al250;
    v_res := v_res || jsonb_build_object('p','D · dueño (postgres): UPDATE','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D · dueño (postgres): UPDATE','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    delete from ent_recuento_pendiente where alisto_lote_id=v_al250;
    v_res := v_res || jsonb_build_object('p','D · dueño (postgres): DELETE','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D · dueño (postgres): DELETE','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    truncate ent_recuento_pendiente;
    v_res := v_res || jsonb_build_object('p','D · dueño (postgres): TRUNCATE','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D · dueño (postgres): TRUNCATE','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    v_txt := coalesce((select coalesce(sum(uds),0)-v_s250 from ent_salido_del_congelador_desde_ancla where producto_id=451 and lote=v_l250)::text, 'null');
    v_res := v_res || jsonb_build_object('p','Intimo · salidas del 250 suben 2 unidades','esperado','2','obtenido',v_txt,'ok',v_txt='2');
  exception when others then
    v_res := v_res || jsonb_build_object('p','Intimo · salidas del 250 suben 2 unidades','esperado','2','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_txt := coalesce((select coalesce(sum(uds),0)-v_s257 from ent_salido_del_congelador_desde_ancla where producto_id=451 and lote=v_l257)::text, 'null');
    v_res := v_res || jsonb_build_object('p','Intimo · salidas del 257 suben 1 unidad (74 -> 73)','esperado','1','obtenido',v_txt,'ok',v_txt='1');
  exception when others then
    v_res := v_res || jsonb_build_object('p','Intimo · salidas del 257 suben 1 unidad (74 -> 73)','esperado','1','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_txt := coalesce((select coalesce(sum(uds),0)-v_s266 from ent_salido_del_congelador_desde_ancla where producto_id=503 and lote=v_l266)::text, 'null');
    v_res := v_res || jsonb_build_object('p','Intimo · salidas del Buns 266 suben 3 paquetes (12 u base)','esperado','12','obtenido',v_txt,'ok',v_txt='12');
  exception when others then
    v_res := v_res || jsonb_build_object('p','Intimo · salidas del Buns 266 suben 3 paquetes (12 u base)','esperado','12','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_so, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into ent_recuento_pendiente(cierra_id,motivo,nota) select id,'recuento','ok' from ent_recuento_pendiente where alisto_lote_id=v_al250;
    v_res := v_res || jsonb_build_object('p','socia cierra con nota corta','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','socia cierra con nota corta','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into ent_recuento_pendiente(cierra_id,motivo,nota) select id,'recuento','contado el lunes: habia 2 de mas' from ent_recuento_pendiente where alisto_lote_id=v_al250;
    v_res := v_res || jsonb_build_object('p','socia cierra con recuento','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','socia cierra con recuento','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_txt := coalesce((select count(*) from ent_recuento_pendiente_abierto where alisto_lote_id=v_al250)::text, 'null');
    v_res := v_res || jsonb_build_object('p','cerrado: sale de la vista de abiertos','esperado','0','obtenido',v_txt,'ok',v_txt='0');
  exception when others then
    v_res := v_res || jsonb_build_object('p','cerrado: sale de la vista de abiertos','esperado','0','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ent_recuento_pendiente(cierra_id,motivo,nota) select id,'recuento','otra vez' from ent_recuento_pendiente where alisto_lote_id=v_al250;
    v_res := v_res || jsonb_build_object('p','segundo cierre del mismo pendiente','esperado','RECHAZA · 23505','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','segundo cierre del mismo pendiente','esperado','RECHAZA · 23505','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23505');
  end;
  begin
    insert into ent_recuento_pendiente(cierra_id,motivo,nota) select max(id),'recuento','cierre de cierre' from ent_recuento_pendiente where cierra_id is not null;
    v_res := v_res || jsonb_build_object('p','cerrar un cierre','esperado','RECHAZA · P0001','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','cerrar un cierre','esperado','RECHAZA · P0001','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='P0001');
  end;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);
  for r in select * from jsonb_array_elements(v_res) loop
    v_n := v_n + 1; if (r->>'ok')::boolean then v_ok := v_ok + 1; end if;
    raise notice '% · % · esperado % · obtenido %', case when (r->>'ok')::boolean then 'OK ' else 'MAL' end, r->>'p', r->>'esperado', r->>'obtenido';
  end loop;
  raise notice 'RESULTADO: % de % ok', v_ok, v_n;
  perform set_config('ensayo.resultado', v_ok||' de '||v_n, true);
end $ensayo$;
select current_setting('ensayo.resultado', true) as resultado;
rollback;
