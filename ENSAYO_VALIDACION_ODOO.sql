-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_VALIDACION_ODOO.sql  ·  30-sep-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Prueba la tabla del rastro del carril (ENTREGAS_VALIDACION_ODOO.sql) y la deshace.
-- ✅ CORRIDO el 30-sep-2026 por Andrea en producción: 11 de 11 ok = true, con el
--    texto esperado en cada rechazo. Después se aplicó ENTREGAS_VALIDACION_ODOO.sql.
--
-- QUÉ HACE
--   1. Aplica el BLOQUE DDL de ENTREGAS_VALIDACION_ODOO.sql, igual.
--   2. Prueba como socia, como equipo y como anon (sesión simulada, CON RLS), y
--      como el editor SQL. Ningún correo va escrito: salen de v_acceso_usuario.
--   3. rollback. No queda nada.
--
-- CÓMO SE LEE
--   Una tabla de 11 filas, TODAS con ok = true. Un RECHAZA da ok solo si el
--   SQLSTATE esperado está en `obtenido`. Si el editor dice "Success. No rows
--   returned", no llegó al final y no vale.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE DDL (copia de ENTREGAS_VALIDACION_ODOO.sql) ▼▼▼
create table public.ent_odoo_validacion (
  id              bigint generated always as identity primary key,
  pedido_id       bigint not null references public.ent_pedido(id),
  factura_id      integer not null,
  picking_id      integer not null,
  picking_nombre  text not null check (length(btrim(picking_nombre)) > 0),
  lineas          jsonb not null check (jsonb_typeof(lineas) = 'array' and jsonb_array_length(lineas) > 0),
  validado_por    text not null,
  validado_en     timestamptz not null default now(),
  constraint ent_odoo_validacion_picking_un unique (picking_id)
);
create index ent_odoo_validacion_pedido_idx on public.ent_odoo_validacion (pedido_id);

alter table public.ent_odoo_validacion enable row level security;
revoke all on public.ent_odoo_validacion from anon, authenticated;
grant select, insert on public.ent_odoo_validacion to authenticated;

create policy ent_odoo_validacion_sel on public.ent_odoo_validacion
  for select to authenticated using (true);
create policy ent_odoo_validacion_ins on public.ent_odoo_validacion
  for insert to authenticated
  with check (acceso_es_socia() and validado_por = (auth.jwt() ->> 'email'));
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

do $$
declare
  v_socia text; v_equipo text; v_ped bigint; v_n int;
  v_res jsonb := '[]'::jsonb;
  L constant jsonb := '[{"producto_id":451,"salio_truefie":6}]';
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by id limit 1;
  select email into v_equipo from v_acceso_usuario where perfil <> 'socias' and activo order by id limit 1;
  select max(id) into v_ped from ent_pedido;
  if v_socia is null or v_equipo is null or v_ped is null then
    raise exception 'el ensayo necesita una socia, alguien de equipo y un pedido (socia %, equipo %, pedido %)', v_socia, v_equipo, v_ped;
  end if;

  -- ── socia ──
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into ent_odoo_validacion (pedido_id, factura_id, picking_id, picking_nombre, lineas, validado_por)
      values (v_ped, 1, -1, 'WH/OUT/ENSAYO-1', L, v_socia);
    v_res := v_res || jsonb_build_object('p','E1 la socia registra con SU nombre','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E1 la socia registra con SU nombre','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ent_odoo_validacion (pedido_id, factura_id, picking_id, picking_nombre, lineas, validado_por)
      values (v_ped, 1, -2, 'WH/OUT/ENSAYO-2', L, 'otra@persona.com');
    v_res := v_res || jsonb_build_object('p','E2 la socia firma con OTRO nombre','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E2 la socia firma con OTRO nombre','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_odoo_validacion (pedido_id, factura_id, picking_id, picking_nombre, lineas, validado_por)
      values (v_ped, 1, -1, 'WH/OUT/ENSAYO-1', L, v_socia);
    v_res := v_res || jsonb_build_object('p','E3 el mismo albarán dos veces','esperado','RECHAZA · 23505','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E3 el mismo albarán dos veces','esperado','RECHAZA · 23505','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23505');
  end;
  begin
    insert into ent_odoo_validacion (pedido_id, factura_id, picking_id, picking_nombre, lineas, validado_por)
      values (v_ped, 1, -3, 'WH/OUT/ENSAYO-3', '[]', v_socia);
    v_res := v_res || jsonb_build_object('p','E4 sin líneas','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E4 sin líneas','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    update ent_odoo_validacion set validado_por = v_socia where picking_id = -1;
    v_res := v_res || jsonb_build_object('p','E5 la socia EDITA una fila','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E5 la socia EDITA una fila','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    delete from ent_odoo_validacion where picking_id = -1;
    v_res := v_res || jsonb_build_object('p','E6 la socia BORRA una fila','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E6 la socia BORRA una fila','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── equipo ──
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  begin
    insert into ent_odoo_validacion (pedido_id, factura_id, picking_id, picking_nombre, lineas, validado_por)
      values (v_ped, 1, -4, 'WH/OUT/ENSAYO-4', L, v_equipo);
    v_res := v_res || jsonb_build_object('p','E7 alguien de equipo registra','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E7 alguien de equipo registra','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    select count(*) into v_n from ent_odoo_validacion;
    v_res := v_res || jsonb_build_object('p','E8 equipo LEE el rastro','esperado','1 fila','obtenido',v_n||' fila(s)','ok',v_n=1);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E8 equipo LEE el rastro','esperado','1 fila','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;

  -- ── anon ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
  begin
    select count(*) into v_n from ent_odoo_validacion;
    v_res := v_res || jsonb_build_object('p','E9 anon lee','esperado','RECHAZA · 42501','obtenido','ENTRA ('||v_n||')','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E9 anon lee','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_odoo_validacion (pedido_id, factura_id, picking_id, picking_nombre, lineas, validado_por)
      values (v_ped, 1, -5, 'WH/OUT/ENSAYO-5', L, 'anon');
    v_res := v_res || jsonb_build_object('p','E10 anon registra','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E10 anon registra','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── editor SQL ──
  perform set_config('role', 'postgres', true);
  select count(*) into v_n from ent_odoo_validacion where picking_id = -1 and validado_por = v_socia;
  v_res := v_res || jsonb_build_object('p','E11 quedó UNA fila, la de la socia, intacta','esperado','1','obtenido',v_n::text,'ok',v_n=1);

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: 11 filas, todas ok = true.

rollback;
