-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_TRASLADO_ODOO.sql  ·  1-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Prueba la tabla del rastro del traslado (ENTREGAS_TRASLADO_ODOO.sql) y la deshace.
--
-- CÓMO SE LEE
--   Una tabla de 14 filas, TODAS con ok = true. Un RECHAZA da ok solo si el
--   SQLSTATE esperado está en `obtenido`. Si el editor dice "Success. No rows
--   returned", no llegó al final y no vale.
--   Textos esperados: T2 y T11 «new row violates row-level security policy»;
--   T3 «…_pedido_un»; T4 «…_picking_un»; T5 «…lineas_check»; T6 «…motivo_check»;
--   T7 «…destino_id_check»; T8 «…contacto_id_check»; T9, T10, T12 y T13
--   «permission denied for table ent_odoo_traslado».
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE DDL (copia de ENTREGAS_TRASLADO_ODOO.sql) ▼▼▼
create table public.ent_odoo_traslado (
  id              bigint generated always as identity primary key,
  pedido_id       bigint not null references public.ent_pedido(id),
  picking_id      integer not null,
  picking_nombre  text not null check (length(btrim(picking_nombre)) > 0),
  motivo          text not null check (motivo in ('regalia','degustacion','consumo_interno','reposicion')),
  destino_id      integer not null check (destino_id in (16, 19)),
  contacto_id     integer not null check (contacto_id in (1260, 1261, 1262, 1263)),
  lineas          jsonb not null check (jsonb_typeof(lineas) = 'array' and jsonb_array_length(lineas) > 0),
  creado_por      text not null,
  creado_en       timestamptz not null default now(),
  constraint ent_odoo_traslado_pedido_un unique (pedido_id),
  constraint ent_odoo_traslado_picking_un unique (picking_id)
);

alter table public.ent_odoo_traslado enable row level security;
revoke all on public.ent_odoo_traslado from anon, authenticated;
grant select, insert on public.ent_odoo_traslado to authenticated;

create policy ent_odoo_traslado_sel on public.ent_odoo_traslado
  for select to authenticated using (true);
create policy ent_odoo_traslado_ins on public.ent_odoo_traslado
  for insert to authenticated
  with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

do $$
declare
  v_socia text; v_equipo text; v_ped bigint; v_ped2 bigint; v_n int;
  v_res jsonb := '[]'::jsonb;
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by id limit 1;
  select email into v_equipo from v_acceso_usuario where perfil <> 'socias' and activo order by id limit 1;
  select max(id) into v_ped from ent_pedido;
  select max(id) into v_ped2 from ent_pedido where id < v_ped;
  if v_socia is null or v_equipo is null or v_ped is null or v_ped2 is null then
    raise exception 'el ensayo necesita una socia, alguien de equipo y dos pedidos (socia %, equipo %, pedidos % %)', v_socia, v_equipo, v_ped, v_ped2;
  end if;

  -- ── socia ──
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into ent_odoo_traslado (pedido_id, picking_id, picking_nombre, motivo, destino_id, contacto_id, lineas, creado_por) values (v_ped, -1, 'WH/INT/ENSAYO-1', 'consumo_interno', 19, 1262, '[{"producto_id":519,"uds":1}]', v_socia);
    v_res := v_res || jsonb_build_object('p','T1 la socia registra con SU nombre','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T1 la socia registra con SU nombre','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ent_odoo_traslado (pedido_id, picking_id, picking_nombre, motivo, destino_id, contacto_id, lineas, creado_por) values (v_ped2, -2, 'WH/INT/ENSAYO-2', 'regalia', 19, 1260, '[{"producto_id":519,"uds":1}]', 'otra@persona.com');
    v_res := v_res || jsonb_build_object('p','T2 la socia firma con OTRO nombre','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T2 la socia firma con OTRO nombre','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_odoo_traslado (pedido_id, picking_id, picking_nombre, motivo, destino_id, contacto_id, lineas, creado_por) values (v_ped, -3, 'WH/INT/ENSAYO-3', 'regalia', 19, 1260, '[{"producto_id":519,"uds":1}]', v_socia);
    v_res := v_res || jsonb_build_object('p','T3 la misma salida dos veces','esperado','RECHAZA · 23505','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T3 la misma salida dos veces','esperado','RECHAZA · 23505','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23505');
  end;
  begin
    insert into ent_odoo_traslado (pedido_id, picking_id, picking_nombre, motivo, destino_id, contacto_id, lineas, creado_por) values (v_ped2, -1, 'WH/INT/ENSAYO-1', 'regalia', 19, 1260, '[{"producto_id":519,"uds":1}]', v_socia);
    v_res := v_res || jsonb_build_object('p','T4 el mismo traslado de Odoo dos veces','esperado','RECHAZA · 23505','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T4 el mismo traslado de Odoo dos veces','esperado','RECHAZA · 23505','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23505');
  end;
  begin
    insert into ent_odoo_traslado (pedido_id, picking_id, picking_nombre, motivo, destino_id, contacto_id, lineas, creado_por) values (v_ped2, -5, 'WH/INT/ENSAYO-5', 'regalia', 19, 1260, '[]', v_socia);
    v_res := v_res || jsonb_build_object('p','T5 sin líneas','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T5 sin líneas','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into ent_odoo_traslado (pedido_id, picking_id, picking_nombre, motivo, destino_id, contacto_id, lineas, creado_por) values (v_ped2, -6, 'WH/INT/ENSAYO-6', 'venta', 19, 1260, '[{"producto_id":519,"uds":1}]', v_socia);
    v_res := v_res || jsonb_build_object('p','T6 motivo venta','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T6 motivo venta','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into ent_odoo_traslado (pedido_id, picking_id, picking_nombre, motivo, destino_id, contacto_id, lineas, creado_por) values (v_ped2, -7, 'WH/INT/ENSAYO-7', 'regalia', 8, 1260, '[{"producto_id":519,"uds":1}]', v_socia);
    v_res := v_res || jsonb_build_object('p','T7 destino WH/Stock [8]','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T7 destino WH/Stock [8]','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into ent_odoo_traslado (pedido_id, picking_id, picking_nombre, motivo, destino_id, contacto_id, lineas, creado_por) values (v_ped2, -8, 'WH/INT/ENSAYO-8', 'regalia', 19, 994, '[{"producto_id":519,"uds":1}]', v_socia);
    v_res := v_res || jsonb_build_object('p','T8 contacto Influencers [994]','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T8 contacto Influencers [994]','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    update ent_odoo_traslado set destino_id = 16 where picking_id = -1;
    v_res := v_res || jsonb_build_object('p','T9 la socia EDITA una fila','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T9 la socia EDITA una fila','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    delete from ent_odoo_traslado where picking_id = -1;
    v_res := v_res || jsonb_build_object('p','T10 la socia BORRA una fila','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T10 la socia BORRA una fila','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── equipo ──
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  begin
    insert into ent_odoo_traslado (pedido_id, picking_id, picking_nombre, motivo, destino_id, contacto_id, lineas, creado_por) values (v_ped2, -11, 'WH/INT/ENSAYO-11', 'regalia', 19, 1260, '[{"producto_id":519,"uds":1}]', v_equipo);
    v_res := v_res || jsonb_build_object('p','T11 alguien de equipo registra','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T11 alguien de equipo registra','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── anon ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
  begin
    select count(*) into v_n from ent_odoo_traslado;
    v_res := v_res || jsonb_build_object('p','T12 anon lee','esperado','RECHAZA · 42501','obtenido','ENTRA ('||v_n||')','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T12 anon lee','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_odoo_traslado (pedido_id, picking_id, picking_nombre, motivo, destino_id, contacto_id, lineas, creado_por) values (v_ped2, -13, 'WH/INT/ENSAYO-13', 'regalia', 19, 1260, '[{"producto_id":519,"uds":1}]', 'anon');
    v_res := v_res || jsonb_build_object('p','T13 anon registra','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T13 anon registra','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── editor SQL ──
  perform set_config('role', 'postgres', true);
  select count(*) into v_n from ent_odoo_traslado where picking_id = -1 and creado_por = v_socia and destino_id = 19;
  v_res := v_res || jsonb_build_object('p','T14 quedó UNA fila, la de la socia, intacta','esperado','1','obtenido',v_n::text,'ok',v_n=1);

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: 14 filas, todas ok = true.

rollback;
