-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_DESCARTE_ODOO.sql  ·  1-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Prueba la tabla de «Descartar» (ENTREGAS_DESCARTE_ODOO.sql) y la deshace.
-- ✅ CORRIDO el 1-oct-2026 por Andrea en producción: 11 de 11 ok = true, con el
--    texto esperado en cada rechazo. Después se aplicó ENTREGAS_DESCARTE_ODOO.sql.
--
-- QUÉ HACE
--   1. Aplica el BLOQUE DDL de ENTREGAS_DESCARTE_ODOO.sql, igual.
--   2. Prueba como socia, como equipo y como anon (sesión simulada, CON RLS), y
--      como el editor SQL. Ningún correo va escrito: salen de v_acceso_usuario.
--   3. rollback. No queda nada.
--
-- CÓMO SE LEE
--   Una tabla de 11 filas, TODAS con ok = true. Un RECHAZA da ok solo si el
--   SQLSTATE esperado está en `obtenido`. Si el editor dice "Success. No rows
--   returned", no llegó al final y no vale.
--   Textos esperados: D2 y D7 «new row violates row-level security policy»;
--   D3 «duplicate key … ent_pedido_odoo_descarte_un»; D4 «…huella_check»;
--   D5, D6, D9 y D10 «permission denied for table ent_pedido_odoo_descarte».
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE DDL (copia de ENTREGAS_DESCARTE_ODOO.sql) ▼▼▼
create table public.ent_pedido_odoo_descarte (
  id          bigint generated always as identity primary key,
  pedido_id   bigint not null references public.ent_pedido(id),
  huella      text not null check (length(btrim(huella)) > 0),
  motivo      text,
  creado_por  text not null,
  creado_en   timestamptz not null default now(),
  constraint ent_pedido_odoo_descarte_un unique (pedido_id, huella)
);

alter table public.ent_pedido_odoo_descarte enable row level security;
revoke all on public.ent_pedido_odoo_descarte from anon, authenticated;
grant select, insert on public.ent_pedido_odoo_descarte to authenticated;

create policy ent_pedido_odoo_descarte_sel on public.ent_pedido_odoo_descarte
  for select to authenticated using (true);
create policy ent_pedido_odoo_descarte_ins on public.ent_pedido_odoo_descarte
  for insert to authenticated
  with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

do $$
declare
  v_socia text; v_equipo text; v_ped bigint; v_n int;
  v_res jsonb := '[]'::jsonb;
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
    insert into ent_pedido_odoo_descarte (pedido_id, huella, motivo, creado_por) values (v_ped, 'ENSAYO-H1', 'ensayo', v_socia);
    v_res := v_res || jsonb_build_object('p','D1 la socia descarta con SU nombre','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D1 la socia descarta con SU nombre','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ent_pedido_odoo_descarte (pedido_id, huella, motivo, creado_por) values (v_ped, 'ENSAYO-H2', 'ensayo', 'otra@persona.com');
    v_res := v_res || jsonb_build_object('p','D2 la socia firma con OTRO nombre','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D2 la socia firma con OTRO nombre','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_pedido_odoo_descarte (pedido_id, huella, motivo, creado_por) values (v_ped, 'ENSAYO-H1', 'ensayo', v_socia);
    v_res := v_res || jsonb_build_object('p','D3 la misma huella dos veces','esperado','RECHAZA · 23505','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D3 la misma huella dos veces','esperado','RECHAZA · 23505','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23505');
  end;
  begin
    insert into ent_pedido_odoo_descarte (pedido_id, huella, motivo, creado_por) values (v_ped, '   ', 'ensayo', v_socia);
    v_res := v_res || jsonb_build_object('p','D4 huella vacía','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D4 huella vacía','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    update ent_pedido_odoo_descarte set motivo = 'x' where huella = 'ENSAYO-H1';
    v_res := v_res || jsonb_build_object('p','D5 la socia EDITA una fila','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D5 la socia EDITA una fila','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    delete from ent_pedido_odoo_descarte where huella = 'ENSAYO-H1';
    v_res := v_res || jsonb_build_object('p','D6 la socia BORRA una fila','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D6 la socia BORRA una fila','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── equipo ──
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  begin
    insert into ent_pedido_odoo_descarte (pedido_id, huella, motivo, creado_por) values (v_ped, 'ENSAYO-H7', 'ensayo', v_equipo);
    v_res := v_res || jsonb_build_object('p','D7 alguien de equipo descarta','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D7 alguien de equipo descarta','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    select count(*) into v_n from ent_pedido_odoo_descarte where huella like 'ENSAYO-%';
    v_res := v_res || jsonb_build_object('p','D8 equipo LEE los descartes','esperado','1 fila','obtenido',v_n||' fila(s)','ok',v_n=1);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D8 equipo LEE los descartes','esperado','1 fila','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;

  -- ── anon ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
  begin
    select count(*) into v_n from ent_pedido_odoo_descarte;
    v_res := v_res || jsonb_build_object('p','D9 anon lee','esperado','RECHAZA · 42501','obtenido','ENTRA ('||v_n||')','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D9 anon lee','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_pedido_odoo_descarte (pedido_id, huella, motivo, creado_por) values (v_ped, 'ENSAYO-H10', 'ensayo', 'anon');
    v_res := v_res || jsonb_build_object('p','D10 anon descarta','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','D10 anon descarta','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── editor SQL ──
  perform set_config('role', 'postgres', true);
  select count(*) into v_n from ent_pedido_odoo_descarte where huella = 'ENSAYO-H1' and creado_por = v_socia and motivo = 'ensayo';
  v_res := v_res || jsonb_build_object('p','D11 quedó UNA fila, la de la socia, intacta','esperado','1','obtenido',v_n::text,'ok',v_n=1);

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: 11 filas, todas ok = true.

rollback;
