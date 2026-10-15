-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_CONT_BARRIDO_ODOO.sql · 14-oct-2026 · ENSAYO EN SECO · TERMINA EN ROLLBACK
-- El rastro del barrido de 1103030 · CONT_BARRIDO_ODOO.sql
--
-- ⚠️ ARCHIVO GENERADO. Se regenera con
--     python3 herramientas/ensayos/armar_ensayo_cont_barrido.py
--   El bloque DDL es el de CONT_BARRIDO_ODOO.sql BYTE A BYTE. md5: d47f16db52e5b3f545c7c5a07b60c82f
--
-- Sesiones simuladas (request.jwt.claims + rol authenticated, o sea CON RLS) de una
-- socia, alguien del equipo y el asistente, sacadas de v_acceso_usuario.
-- TIENE QUE DAR 15 filas, TODAS con ok = true. Si dice "Success. No rows returned",
-- no llegó al final y no vale.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ═══ DDL · DESDE ACA (ENSAYO_CONT_BARRIDO_ODOO.sql copia este bloque tal cual) ═══

do $$ begin
  if to_regclass('public.cont_barrido_odoo') is not null then
    raise exception 'cont_barrido_odoo ya existe: este archivo no se vuelve a pegar';
  end if;
end $$;

create table public.cont_barrido_odoo (
  id              bigint generated always as identity primary key,
  mes             text not null check (mes ~ '^\d{4}-(0[1-9]|1[0-2])$' and mes >= '2026-10'),
  asiento_id      integer not null check (asiento_id > 0),          -- account.move en Odoo
  asiento_nombre  text not null check (length(btrim(asiento_nombre)) > 0),
  fecha           date not null,                                     -- el último día del mes
  lineas          integer not null check (lineas > 0),              -- residuos barridos
  monto           numeric(14,2) not null,                            -- neto a 6106022 (puede ser negativo)
  excluidos       integer not null default 0 check (excluidos >= 0),  -- más que el umbral: a mano
  huella          text not null check (length(huella) between 1 and 64),
  creado_por      text not null,
  creado_en       timestamptz not null default now(),
  constraint cont_barrido_odoo_mes_un unique (mes)
);

alter table public.cont_barrido_odoo enable row level security;   -- ya lo hizo ensure_rls
revoke all on public.cont_barrido_odoo from anon, authenticated;
grant select, insert on public.cont_barrido_odoo to authenticated;

create policy cont_barrido_odoo_sel on public.cont_barrido_odoo
  for select to authenticated using (acceso_es_socia());
create policy cont_barrido_odoo_ins on public.cont_barrido_odoo
  for insert to authenticated
  with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));

-- ═══ DDL · HASTA ACA ═══

do $$
declare
  v_res jsonb := '[]'::jsonb;
  v_socia text; v_equipo text; v_asist text; v_n bigint;
begin

  -- ── las identidades salen de la base ──
  select email into v_socia  from v_acceso_usuario where perfil = 'socias'    and activo order by email limit 1;
  select email into v_equipo from v_acceso_usuario where perfil = 'equipo'    and activo order by email limit 1;
  select email into v_asist  from v_acceso_usuario where perfil = 'asistente' and activo order by email limit 1;
  if v_socia is null or v_equipo is null or v_asist is null then raise exception 'falta una identidad para ensayar'; end if;
  perform set_config('role', 'authenticated', true);

  -- ── R · el servicio registra un barrido, con el token de la socia ──
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  begin
    insert into cont_barrido_odoo (mes, asiento_id, asiento_nombre, fecha, lineas, monto, excluidos, huella, creado_por) values ('2026-10', 99999, 'MISC/ENSAYO', current_date, 26, 113.26, 0, 'fc659c00c4175e84', v_socia);
    v_res := v_res || jsonb_build_object('p', 'R1 socia · octubre 2026, firmado por ella', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R1 socia · octubre 2026, firmado por ella', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  begin
    insert into cont_barrido_odoo (mes, asiento_id, asiento_nombre, fecha, lineas, monto, excluidos, huella, creado_por) values ('2026-10', 99999, 'MISC/ENSAYO', current_date, 26, 113.26, 0, 'fc659c00c4175e84', v_socia);
    v_res := v_res || jsonb_build_object('p', 'R2 socia · octubre otra vez', 'esperado', 'RECHAZA · 23505 · cont_barrido_odoo_mes_un', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R2 socia · octubre otra vez', 'esperado', 'RECHAZA · 23505 · cont_barrido_odoo_mes_un', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '23505' and strpos(sqlerrm, 'cont_barrido_odoo_mes_un') > 0);
  end;
  begin
    insert into cont_barrido_odoo (mes, asiento_id, asiento_nombre, fecha, lineas, monto, excluidos, huella, creado_por) values ('2026-09', 99999, 'MISC/ENSAYO', current_date, 26, 113.26, 0, 'fc659c00c4175e84', v_socia);
    v_res := v_res || jsonb_build_object('p', 'R3 socia · septiembre (antes del inicio)', 'esperado', 'RECHAZA · 23514 · cont_barrido_odoo_mes_check', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R3 socia · septiembre (antes del inicio)', 'esperado', 'RECHAZA · 23514 · cont_barrido_odoo_mes_check', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '23514' and strpos(sqlerrm, 'cont_barrido_odoo_mes_check') > 0);
  end;
  begin
    insert into cont_barrido_odoo (mes, asiento_id, asiento_nombre, fecha, lineas, monto, excluidos, huella, creado_por) values ('2026-1', 99999, 'MISC/ENSAYO', current_date, 26, 113.26, 0, 'fc659c00c4175e84', v_socia);
    v_res := v_res || jsonb_build_object('p', 'R4 socia · un mes mal escrito («2026-1»)', 'esperado', 'RECHAZA · 23514 · cont_barrido_odoo_mes_check', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R4 socia · un mes mal escrito («2026-1»)', 'esperado', 'RECHAZA · 23514 · cont_barrido_odoo_mes_check', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '23514' and strpos(sqlerrm, 'cont_barrido_odoo_mes_check') > 0);
  end;
  begin
    insert into cont_barrido_odoo (mes, asiento_id, asiento_nombre, fecha, lineas, monto, excluidos, huella, creado_por) values ('2026-11', 99999, 'MISC/ENSAYO', current_date, 26, 113.26, 0, 'fc659c00c4175e84', v_equipo);
    v_res := v_res || jsonb_build_object('p', 'R5 socia · firmado con OTRO correo', 'esperado', 'RECHAZA · 42501 · row-level security', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R5 socia · firmado con OTRO correo', 'esperado', 'RECHAZA · 42501 · row-level security', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'row-level security') > 0);
  end;
  begin
    insert into cont_barrido_odoo (mes, asiento_id, asiento_nombre, fecha, lineas, monto, excluidos, huella, creado_por) values ('2026-11', 99999, 'MISC/ENSAYO', current_date, 26, -5, 0, 'fc659c00c4175e84', v_socia);
    v_res := v_res || jsonb_build_object('p', 'R6 socia · neto negativo (noviembre, −₡5)', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R6 socia · neto negativo (noviembre, −₡5)', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;

  -- ── N · nadie más escribe, y nadie edita ──
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  begin
    insert into cont_barrido_odoo (mes, asiento_id, asiento_nombre, fecha, lineas, monto, excluidos, huella, creado_por) values ('2026-12', 99999, 'MISC/ENSAYO', current_date, 26, 113.26, 0, 'fc659c00c4175e84', v_equipo);
    v_res := v_res || jsonb_build_object('p', 'N1 equipo · registrar diciembre', 'esperado', 'RECHAZA · 42501 · row-level security', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N1 equipo · registrar diciembre', 'esperado', 'RECHAZA · 42501 · row-level security', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'row-level security') > 0);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asist, 'role', 'authenticated')::text, true);
  begin
    insert into cont_barrido_odoo (mes, asiento_id, asiento_nombre, fecha, lineas, monto, excluidos, huella, creado_por) values ('2026-12', 99999, 'MISC/ENSAYO', current_date, 26, 113.26, 0, 'fc659c00c4175e84', v_asist);
    v_res := v_res || jsonb_build_object('p', 'N2 asistente · registrar diciembre', 'esperado', 'RECHAZA · 42501 · row-level security', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N2 asistente · registrar diciembre', 'esperado', 'RECHAZA · 42501 · row-level security', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'row-level security') > 0);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  begin
    update cont_barrido_odoo set monto = 0 where mes = '2026-10';
    v_res := v_res || jsonb_build_object('p', 'N3 socia · editar un barrido (update)', 'esperado', 'RECHAZA · 42501 · permission denied for table cont_barrido_odoo', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N3 socia · editar un barrido (update)', 'esperado', 'RECHAZA · 42501 · permission denied for table cont_barrido_odoo', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table cont_barrido_odoo') > 0);
  end;
  begin
    delete from cont_barrido_odoo where mes = '2026-10';
    v_res := v_res || jsonb_build_object('p', 'N4 socia · borrar un barrido (delete)', 'esperado', 'RECHAZA · 42501 · permission denied for table cont_barrido_odoo', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N4 socia · borrar un barrido (delete)', 'esperado', 'RECHAZA · 42501 · permission denied for table cont_barrido_odoo', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table cont_barrido_odoo') > 0);
  end;

  -- ── V · quién lo ve ──
  select count(*) into v_n from cont_barrido_odoo;
  v_res := v_res || jsonb_build_object('p', 'V1 socia ve los 2 barridos', 'esperado', '2', 'obtenido', v_n::text, 'ok', coalesce(v_n = 2, false));
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  select count(*) into v_n from cont_barrido_odoo;
  v_res := v_res || jsonb_build_object('p', 'V2 equipo no ve ninguno', 'esperado', '0', 'obtenido', v_n::text, 'ok', coalesce(v_n = 0, false));
  perform set_config('request.jwt.claims', json_build_object('email', v_asist, 'role', 'authenticated')::text, true);
  select count(*) into v_n from cont_barrido_odoo;
  v_res := v_res || jsonb_build_object('p', 'V3 asistente los ve (Instinct ve todo, con su interruptor encendido)', 'esperado', '2', 'obtenido', v_n::text, 'ok', coalesce(v_n = 2, false));

  -- ── P · anon no toca nada ──
  select count(*) into v_n from information_schema.role_table_grants where table_name = 'cont_barrido_odoo' and grantee = 'anon';
  v_res := v_res || jsonb_build_object('p', 'P1 anon: permisos sobre la tabla', 'esperado', '0', 'obtenido', v_n::text, 'ok', coalesce(v_n = 0, false));
  select count(*) into v_n from pg_policy where polrelid = 'public.cont_barrido_odoo'::regclass;
  v_res := v_res || jsonb_build_object('p', 'P2 políticas: 2 propias + 5 del asistente', 'esperado', '7', 'obtenido', v_n::text, 'ok', coalesce(v_n = 7, false));

  perform set_config('ensayo.res', v_res::text, true);
end $$;

-- ── EL RESULTADO. Esta tabla ES el ensayo. ESPERADO: 15 filas, todas ok = true.
select r.p as prueba, r.esperado, r.obtenido, r.ok
  from jsonb_to_recordset(current_setting('ensayo.res')::jsonb)
       as r(p text, esperado text, obtenido text, ok boolean);

rollback;
