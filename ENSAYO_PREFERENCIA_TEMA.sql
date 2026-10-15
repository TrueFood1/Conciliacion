-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_PREFERENCIA_TEMA.sql  ·  4-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Prueba PREFERENCIA_TEMA.sql imitando a una socia y a alguien de equipo con
-- request.jwt.claims, y lo deshace todo (rollback).
-- ✅ CORRIDO el 4-oct-2026 por Andrea en producción: 19 de 19 ok = true, cada RECHAZA con su SQLSTATE.
--
-- CÓMO SE LEE
--   Una tabla de 19 filas, TODAS con ok = true. Un RECHAZA da ok solo si el SQLSTATE
--   esperado está en `obtenido` (no vale rechazar por el motivo de al lado). Si el
--   editor dice "Success. No rows returned", no llegó al final y no vale.
--   42501 = RLS o sin permiso · 23514 = check.
--   Necesita una socia y alguien de equipo ACTIVOS en acceso_usuario (toma los primeros).
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE DDL (copia de PREFERENCIA_TEMA.sql) ▼▼▼
create table public.preferencia_tema (
  id         bigint generated always as identity primary key,
  usuario    text not null check (usuario = lower(btrim(usuario)) and position('@' in usuario) > 1),
  tema       text not null check (tema in ('claro', 'oscuro')),
  creado_en  timestamptz not null default now()
);
create index preferencia_tema_usuario_idx on public.preferencia_tema (usuario, creado_en desc, id desc);

alter table public.preferencia_tema enable row level security;
revoke all on public.preferencia_tema from public, anon, authenticated;
grant select, insert on public.preferencia_tema to authenticated;

create policy preferencia_tema_sel on public.preferencia_tema
  for select to authenticated
  using (usuario = lower(coalesce(auth.jwt() ->> 'email', '')));
create policy preferencia_tema_ins on public.preferencia_tema
  for insert to authenticated
  with check (usuario = lower(coalesce(auth.jwt() ->> 'email', '')) and acceso_perfil() is not null);

-- security INVOKER: lee preferencia_tema con la RLS de quien pregunta (solo sus filas);
-- acceso_perfil() ya es definer y contesta solo sobre el que llama.
create or replace function public.tema_vigente() returns text
language sql stable security invoker set search_path = public as $$
  select coalesce(
    (select p.tema from preferencia_tema p
      where p.usuario = lower(coalesce(auth.jwt() ->> 'email', ''))
      order by p.creado_en desc, p.id desc
      limit 1),
    case when acceso_perfil() is null then null
         when acceso_perfil() = 'socias' then 'oscuro'
         else 'claro' end);
$$;
revoke all on function public.tema_vigente() from public, anon;
grant execute on function public.tema_vigente() to authenticated;
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

do $$
declare
  v_socia text; v_equipo text; v_n int; v_t text;
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
    v_t := (tema_vigente())::text;
    v_res := v_res || jsonb_build_object('p','S1 socia que nunca tocó el botón: entra en oscuro','esperado','oscuro','obtenido',coalesce(v_t,'null'),'ok',v_t is not distinct from 'oscuro');
  exception when others then
    v_res := v_res || jsonb_build_object('p','S1 socia que nunca tocó el botón: entra en oscuro','esperado','oscuro','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into preferencia_tema (usuario, tema) values (v_socia, 'claro');
    v_res := v_res || jsonb_build_object('p','S2 la socia elige claro, con SU correo','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S2 la socia elige claro, con SU correo','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := (tema_vigente())::text;
    v_res := v_res || jsonb_build_object('p','S3 ahora entra en claro','esperado','claro','obtenido',coalesce(v_t,'null'),'ok',v_t is not distinct from 'claro');
  exception when others then
    v_res := v_res || jsonb_build_object('p','S3 ahora entra en claro','esperado','claro','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into preferencia_tema (usuario, tema) values (v_socia, 'oscuro');
    v_res := v_res || jsonb_build_object('p','S4 vuelve a oscuro (otra fila, misma hora de transacción)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S4 vuelve a oscuro (otra fila, misma hora de transacción)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := (tema_vigente())::text;
    v_res := v_res || jsonb_build_object('p','S5 gana la fila más reciente (a igual hora, el id mayor)','esperado','oscuro','obtenido',coalesce(v_t,'null'),'ok',v_t is not distinct from 'oscuro');
  exception when others then
    v_res := v_res || jsonb_build_object('p','S5 gana la fila más reciente (a igual hora, el id mayor)','esperado','oscuro','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into preferencia_tema (usuario, tema) values ('otra@persona.com', 'claro');
    v_res := v_res || jsonb_build_object('p','S6 la socia guarda con OTRO correo','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S6 la socia guarda con OTRO correo','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into preferencia_tema (usuario, tema) values (v_socia, 'gris');
    v_res := v_res || jsonb_build_object('p','S7 tema inventado','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S7 tema inventado','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    v_t := ((select count(*) from preferencia_tema))::text;
    v_res := v_res || jsonb_build_object('p','S8 la socia ve solo sus filas','esperado','2','obtenido',coalesce(v_t,'null'),'ok',v_t is not distinct from '2');
  exception when others then
    v_res := v_res || jsonb_build_object('p','S8 la socia ve solo sus filas','esperado','2','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    update preferencia_tema set tema = 'claro' where usuario = v_socia;
    v_res := v_res || jsonb_build_object('p','S9 la socia EDITA una fila','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S9 la socia EDITA una fila','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    delete from preferencia_tema where usuario = v_socia;
    v_res := v_res || jsonb_build_object('p','S10 la socia BORRA sus filas','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S10 la socia BORRA sus filas','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── equipo ──
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  begin
    v_t := (tema_vigente())::text;
    v_res := v_res || jsonb_build_object('p','E1 alguien de equipo que nunca tocó el botón: entra en claro','esperado','claro','obtenido',coalesce(v_t,'null'),'ok',v_t is not distinct from 'claro');
  exception when others then
    v_res := v_res || jsonb_build_object('p','E1 alguien de equipo que nunca tocó el botón: entra en claro','esperado','claro','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := ((select count(*) from preferencia_tema))::text;
    v_res := v_res || jsonb_build_object('p','E2 equipo no ve las filas de la socia','esperado','0','obtenido',coalesce(v_t,'null'),'ok',v_t is not distinct from '0');
  exception when others then
    v_res := v_res || jsonb_build_object('p','E2 equipo no ve las filas de la socia','esperado','0','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into preferencia_tema (usuario, tema) values (v_socia, 'claro');
    v_res := v_res || jsonb_build_object('p','E3 equipo guarda con el correo de la socia','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E3 equipo guarda con el correo de la socia','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into preferencia_tema (usuario, tema) values (v_equipo, 'oscuro');
    v_res := v_res || jsonb_build_object('p','E4 equipo elige oscuro, con SU correo','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E4 equipo elige oscuro, con SU correo','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := (tema_vigente())::text;
    v_res := v_res || jsonb_build_object('p','E5 ahora entra en oscuro','esperado','oscuro','obtenido',coalesce(v_t,'null'),'ok',v_t is not distinct from 'oscuro');
  exception when others then
    v_res := v_res || jsonb_build_object('p','E5 ahora entra en oscuro','esperado','oscuro','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;

  -- ── anon ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
  begin
    select count(*) into v_n from preferencia_tema;
    v_res := v_res || jsonb_build_object('p','A1 anon lee las preferencias','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A1 anon lee las preferencias','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into preferencia_tema (usuario, tema) values ('anon@ejemplo.com', 'claro');
    v_res := v_res || jsonb_build_object('p','A2 anon guarda una preferencia','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A2 anon guarda una preferencia','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    v_t := tema_vigente();
    v_res := v_res || jsonb_build_object('p','A3 anon pregunta tema_vigente()','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A3 anon pregunta tema_vigente()','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── editor SQL ──
  perform set_config('role', 'postgres', true);
  select count(*) into v_n from preferencia_tema where (usuario = v_socia and tema in ('claro','oscuro')) or (usuario = v_equipo and tema = 'oscuro');
  v_res := v_res || jsonb_build_object('p','Z quedaron 3 filas: 2 de la socia y 1 de equipo, nada más','esperado','3 de 3','obtenido',v_n||' de '||(select count(*) from preferencia_tema),'ok',v_n=3 and (select count(*) from preferencia_tema)=3);

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: 19 filas, todas ok = true.

rollback;
