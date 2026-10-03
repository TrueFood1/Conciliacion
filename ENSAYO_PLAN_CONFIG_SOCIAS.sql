-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_PLAN_CONFIG_SOCIAS.sql  ·  2-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Prueba PLAN_CONFIG_SOCIAS.sql y lo deshace todo (rollback). ✅ CORRIDO el 3-oct-2026: 7/7 ok.
--
-- CÓMO SE LEE: 7 filas, TODAS ok = true. Un RECHAZA vale solo con el SQLSTATE esperado
-- (42501 = RLS o sin permiso). "Success. No rows returned" = no llegó al final, no vale.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE DDL (copia de PLAN_CONFIG_SOCIAS.sql) ▼▼▼
drop policy plan_config_ins on public.plan_config;
create policy plan_config_ins on public.plan_config
  for insert to authenticated
  with check (clave <> 'compras_dia_fijo'
              or (acceso_es_socia() and usuario = (auth.jwt() ->> 'email')));
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

do $$
declare
  v_socia text; v_equipo text; v_n int;
  v_res jsonb := '[]'::jsonb;
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by id limit 1;
  select email into v_equipo from v_acceso_usuario where perfil <> 'socias' and activo order by id limit 1;
  if v_socia is null or v_equipo is null then
    raise exception 'el ensayo necesita una socia y alguien de equipo (socia %, equipo %)', v_socia, v_equipo;
  end if;

  -- ── socia ──
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into plan_config (clave, valor, usuario) values ('compras_dia_fijo', '{"insumos":[]}'::jsonb, v_socia);
    v_res := v_res || jsonb_build_object('p','S1 la socia cambia compras_dia_fijo con SU nombre','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S1 la socia cambia compras_dia_fijo con SU nombre','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into plan_config (clave, valor, usuario) values ('compras_dia_fijo', '{"insumos":[]}'::jsonb, 'otra@persona.com');
    v_res := v_res || jsonb_build_object('p','S2 la socia la firma con OTRO nombre','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S2 la socia la firma con OTRO nombre','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into plan_config (clave, valor, usuario) values ('compras_dia_fijo', '{"insumos":[]}'::jsonb, null);
    v_res := v_res || jsonb_build_object('p','S3 la socia la guarda sin nombre','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S3 la socia la guarda sin nombre','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── equipo ──
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  begin
    insert into plan_config (clave, valor, usuario) values ('compras_dia_fijo', '{"insumos":[]}'::jsonb, v_equipo);
    v_res := v_res || jsonb_build_object('p','E1 alguien de equipo cambia compras_dia_fijo','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E1 alguien de equipo cambia compras_dia_fijo','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into plan_config (clave, valor, usuario) values ('medir_lunes_frac', '0.5'::jsonb, v_equipo);
    v_res := v_res || jsonb_build_object('p','E2 alguien de equipo guarda OTRA clave (no cambia)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E2 alguien de equipo guarda OTRA clave (no cambia)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;

  -- ── anon ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
  begin
    insert into plan_config (clave, valor, usuario) values ('compras_dia_fijo', '{"insumos":[]}'::jsonb, 'anon');
    v_res := v_res || jsonb_build_object('p','A1 anon cambia compras_dia_fijo','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A1 anon cambia compras_dia_fijo','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── editor SQL ──
  perform set_config('role', 'postgres', true);
  select count(*) into v_n from plan_config where clave = 'compras_dia_fijo' and usuario = v_socia and valor = '{"insumos":[]}'::jsonb;
  v_res := v_res || jsonb_build_object('p','Z quedó UNA fila nueva de compras_dia_fijo, la de la socia','esperado','1','obtenido',v_n::text,'ok',v_n=1);

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: 7 filas, todas ok = true.

rollback;
