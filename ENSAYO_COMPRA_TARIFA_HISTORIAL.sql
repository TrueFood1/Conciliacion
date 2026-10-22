-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_COMPRA_TARIFA_HISTORIAL.sql  ·  21-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Prueba la tabla y el rol de COMPRA_TARIFA_HISTORIAL.sql y lo deshace todo (rollback).
-- ✅ CORRIDO en Postgres local (espejo del respaldo del 21-oct, con los event triggers de producción):
--    todas ok = true. ⛔ NO corrido en producción.
--
-- CÓMO SE LEE
--   Una tabla con TODAS las filas en ok = true. Un RECHAZA da ok solo si el SQLSTATE esperado es
--   el que salió (no vale rechazar por el motivo de al lado). Si el editor dice "Success. No rows
--   returned", no llegó al final y no vale.
--   42501 = RLS o sin permiso · 23514 = check.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE DDL (copia de COMPRA_TARIFA_HISTORIAL.sql, sin begin/commit ni el control) ▼▼▼
do $$ begin
  if to_regclass('public.compra_tarifa_historial') is not null then
    raise exception 'compra_tarifa_historial ya existe: este archivo no se vuelve a pegar';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'truefie_tarifa_auto') then
    create role truefie_tarifa_auto nologin noinherit;
  end if;
end $$;

create table public.compra_tarifa_historial (
  id               bigint generated always as identity primary key,
  origen           text not null check (origen in ('automatico', 'clic')),
  proveedor_id     integer not null check (proveedor_id > 0),
  supplierinfo_id  integer not null check (supplierinfo_id > 0),
  producto_tmpl_id integer not null check (producto_tmpl_id > 0),
  producto         text not null check (length(btrim(producto)) > 0),
  unidad           text,
  precio_antes     numeric(14,4) not null check (precio_antes > 0),
  precio_nuevo     numeric(14,4) not null check (precio_nuevo > 0),
  factura_id       integer not null check (factura_id > 0),
  factura_nombre   text not null check (length(btrim(factura_nombre)) > 0),
  factura_fecha    date,
  linea_id         integer not null check (linea_id > 0),
  anterior_id      integer check (anterior_id > 0),
  anterior_nombre  text check (length(btrim(anterior_nombre)) > 0),
  precio_anterior  numeric(14,4) check (precio_anterior > 0),
  huella           text not null check (length(huella) between 1 and 64),
  creado_por       text not null check (length(btrim(creado_por)) > 0),
  creado_en        timestamptz not null default now(),
  constraint compra_tarifa_historial_cambia check (precio_nuevo <> precio_antes),
  constraint compra_tarifa_historial_anterior check (
    (anterior_id is null) = (precio_anterior is null) and (anterior_id is null) = (anterior_nombre is null)),
  constraint compra_tarifa_historial_automatico check (
    origen <> 'automatico'
    or (precio_anterior is not null and precio_nuevo between precio_anterior * 0.75 and precio_anterior * 1.25)),
  constraint compra_tarifa_historial_clic check (
    origen <> 'clic' or precio_anterior is null
    or precio_nuevo between precio_anterior * 0.5 and precio_anterior * 2)
);
create index compra_tarifa_historial_tarifa on public.compra_tarifa_historial (supplierinfo_id, creado_en desc);

alter table public.compra_tarifa_historial enable row level security;
revoke all on public.compra_tarifa_historial from anon, authenticated;
grant select, insert on public.compra_tarifa_historial to authenticated;
grant usage on schema public to truefie_tarifa_auto;
grant insert on public.compra_tarifa_historial to truefie_tarifa_auto;
-- La revisión diaria necesita saber qué insumos son de Compras: SOLO la fila compras_config (22-oct).
grant select on public.plan_config to truefie_tarifa_auto;
create policy plan_config_tarifa_auto on public.plan_config
  for select to truefie_tarifa_auto using (clave = 'compras_config');

create policy compra_tarifa_historial_sel on public.compra_tarifa_historial
  for select to authenticated using (acceso_es_socia());
create policy compra_tarifa_historial_clic on public.compra_tarifa_historial
  for insert to authenticated
  with check (acceso_es_socia() and origen = 'clic' and creado_por = (auth.jwt() ->> 'email'));
create policy compra_tarifa_historial_auto on public.compra_tarifa_historial
  for insert to truefie_tarifa_auto
  with check (origen = 'automatico' and creado_por = 'revision-automatica');
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

-- Solo para el ensayo (se deshace con el rollback): poder «ser» el rol automático desde el editor.
grant truefie_tarifa_auto to current_user;

do $$
declare
  v_socia text; v_equipo text; v_asis text; v_n int; v_m int; r record; v_ok boolean; v_obt text;
  v_res jsonb := '[]'::jsonb;
  -- una fila del historial; %1$L origen · %2$s antes · %3$s nuevo · %4$s anterior_id · %5$s anterior_nombre ·
  -- %6$s precio_anterior · %7$L creado_por
  ins constant text := 'insert into public.compra_tarifa_historial (origen, proveedor_id, supplierinfo_id, producto_tmpl_id, '
    'producto, unidad, precio_antes, precio_nuevo, factura_id, factura_nombre, factura_fecha, linea_id, anterior_id, '
    'anterior_nombre, precio_anterior, huella, creado_por) values (%1$L, 713, 13, 628, ''Azucar Cruda'', ''kg'', %2$s, %3$s, '
    '42432, ''2600'', date ''2026-10-12'', 134275, %4$s, %5$s, %6$s, ''a1b2c3d4e5f60718'', %7$L)';
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by id limit 1;
  select email into v_equipo from v_acceso_usuario where perfil not in ('socias', 'asistente') and activo order by id limit 1;
  select email into v_asis   from v_acceso_usuario where perfil = 'asistente' and activo order by id limit 1;
  if v_socia is null or v_equipo is null then
    raise exception 'el ensayo necesita una socia y alguien de equipo (socia %, equipo %)', v_socia, v_equipo;
  end if;

  for r in
    select * from (values
      -- socia (clic)
      (1,  'T1 socia: clic +30 % contra la anterior, con SU nombre',            'authenticated', v_socia,
           format(ins, 'clic', 100, 130, '41530', '''2538''', 100, v_socia), null),
      (2,  'T2 socia: clic SIN factura anterior (₡1.871 → ₡823,01, 0,44×)',     'authenticated', v_socia,
           format(ins, 'clic', 1871, 823.01, 'null', 'null', 'null', v_socia), null),
      (3,  'T3 socia firma con OTRO nombre',                                    'authenticated', v_socia,
           format(ins, 'clic', 100, 130, '41530', '''2538''', 100, 'otra@persona.com'), '42501'),
      (4,  'T4 socia anota un «automatico» (eso es del rol de la revisión)',    'authenticated', v_socia,
           format(ins, 'automatico', 100, 110, '41530', '''2538''', 100, v_socia), '42501'),
      -- T5 como dueño de la tabla (sin RLS): con cualquier otro rol la política frena antes (42501) y el
      -- CHECK del origen no se llega a probar; así se prueba la segunda capa sola.
      (5,  'T5 origen inventado, como dueño de la tabla (el CHECK solo)',       'postgres', null,
           format(ins, 'a_mano', 100, 110, '41530', '''2538''', 100, 'postgres'), '23514'),
      (6,  'T6 precio nuevo igual al de antes',                                 'authenticated', v_socia,
           format(ins, 'clic', 100, 100, '41530', '''2538''', 90, v_socia), '23514'),
      (7,  'T7 clic 2,5× la factura anterior (fuera de banda)',                 'authenticated', v_socia,
           format(ins, 'clic', 100, 250, '41530', '''2538''', 100, v_socia), '23514'),
      (8,  'T8 anterior a medias (id sin precio)',                              'authenticated', v_socia,
           format(ins, 'clic', 100, 130, '41530', 'null', 'null', v_socia), '23514'),
      (9,  'T9 socia EDITA el historial',                                       'authenticated', v_socia,
           'update public.compra_tarifa_historial set precio_nuevo = 1', '42501'),
      (10, 'T10 socia BORRA el historial',                                      'authenticated', v_socia,
           'delete from public.compra_tarifa_historial', '42501'),
      -- el rol de la revisión diaria
      (11, 'R1 revisión: AZÚCAR ₡1.871 → ₡823,01 automático (0 % contra la 2538)', 'truefie_tarifa_auto', null,
           format(ins, 'automatico', 1871, 823.01, '41530', '''2538''', 823.01, 'revision-automatica'), null),
      (12, 'R2 revisión: +25 % justo contra la anterior',                       'truefie_tarifa_auto', null,
           format(ins, 'automatico', 100, 125, '41530', '''2538''', 100, 'revision-automatica'), null),
      (13, 'R3 revisión: +30 % contra la anterior',                             'truefie_tarifa_auto', null,
           format(ins, 'automatico', 100, 130, '41530', '''2538''', 100, 'revision-automatica'), '23514'),
      (14, 'R4 revisión: automático SIN factura anterior',                      'truefie_tarifa_auto', null,
           format(ins, 'automatico', 100, 110, 'null', 'null', 'null', 'revision-automatica'), '23514'),
      (15, 'R5 revisión anota un «clic»',                                       'truefie_tarifa_auto', null,
           format(ins, 'clic', 100, 130, '41530', '''2538''', 100, 'revision-automatica'), '42501'),
      (16, 'R6 revisión firma con otro nombre',                                 'truefie_tarifa_auto', null,
           format(ins, 'automatico', 100, 110, '41530', '''2538''', 100, 'andrea@truefoodcr.com'), '42501'),
      (17, 'R7 revisión LEE el historial',                                      'truefie_tarifa_auto', null,
           'select count(*) from public.compra_tarifa_historial', '42501'),
      (18, 'R8 revisión EDITA el historial',                                    'truefie_tarifa_auto', null,
           'update public.compra_tarifa_historial set precio_nuevo = 1', '42501'),
      (19, 'R9 revisión escribe en OTRA tabla (compra_tarifa_odoo)',            'truefie_tarifa_auto', null,
           'insert into public.compra_tarifa_odoo (motivo) values (''factura_nueva'')', '42501'),
      (191,'R10 revisión EDITA compras_config',                                  'truefie_tarifa_auto', null,
           'update public.plan_config set valor = valor where clave = ''compras_config''', '42501'),
      (192,'R11 revisión agrega una fila a plan_config',                         'truefie_tarifa_auto', null,
           'insert into public.plan_config (clave, valor, usuario) values (''compras_config'', ''{}''::jsonb, ''x'')', '42501'),
      -- equipo y anon
      (20, 'E1 alguien de equipo anota un clic',                                'authenticated', v_equipo,
           format(ins, 'clic', 100, 130, '41530', '''2538''', 100, v_equipo), '42501'),
      (21, 'A1 anon lee el historial',                                          'anon', null,
           'select count(*) from public.compra_tarifa_historial', '42501'),
      (22, 'A2 anon anota',                                                     'anon', null,
           format(ins, 'clic', 100, 130, '41530', '''2538''', 100, 'anon'), '42501')
    ) v(n, p, rol, email, q, esp)
    order by n
  loop
    perform set_config('request.jwt.claims',
                       case when r.email is null then '' else json_build_object('email', r.email, 'role', 'authenticated')::text end, true);
    perform set_config('role', r.rol, true);
    begin
      execute r.q;
      v_obt := 'ENTRA'; v_ok := r.esp is null;
    exception when others then
      v_obt := 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm; v_ok := r.esp is not null and sqlstate = r.esp;
    end;
    perform set_config('role', 'postgres', true);
    v_res := v_res || jsonb_build_object('p', r.p, 'esperado', coalesce('RECHAZA · ' || r.esp, 'ENTRA'), 'obtenido', v_obt, 'ok', v_ok);
  end loop;

  -- lecturas
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_n from public.compra_tarifa_historial;
  perform set_config('role', 'postgres', true);
  v_res := v_res || jsonb_build_object('p', 'E2 alguien de equipo NO ve el historial (precios de compra)', 'esperado', '0', 'obtenido', v_n::text, 'ok', v_n = 0);
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_n from public.compra_tarifa_historial;
  perform set_config('role', 'postgres', true);
  v_res := v_res || jsonb_build_object('p', 'S1 la socia ve las 4 filas (T1, T2, R1, R2)', 'esperado', '4', 'obtenido', v_n::text, 'ok', v_n = 4);
  if v_asis is not null then
    perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    begin
      execute format(ins, 'clic', 100, 130, '41530', '''2538''', 100, v_asis);
      v_obt := 'ENTRA'; v_ok := false;
    exception when others then
      v_obt := 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm; v_ok := sqlstate = '42501';
    end;
    perform set_config('role', 'postgres', true);
    v_res := v_res || jsonb_build_object('p', 'I1 el asistente anota un clic', 'esperado', 'RECHAZA · 42501', 'obtenido', v_obt, 'ok', v_ok);
  end if;

  -- la revisión LEE compras_config y NADA más de plan_config
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'truefie_tarifa_auto', true);
  select count(*) into v_n from public.plan_config where clave = 'compras_config';
  select count(*) into v_m from public.plan_config where clave <> 'compras_config';
  perform set_config('role', 'postgres', true);
  v_res := v_res || jsonb_build_object('p', 'R12 revisión lee las filas de compras_config', 'esperado', '>0', 'obtenido', v_n::text, 'ok', v_n > 0);
  v_res := v_res || jsonb_build_object('p', 'R13 revisión NO ve otras claves de plan_config', 'esperado', '0', 'obtenido', v_m::text, 'ok', v_m = 0);

  -- catálogo: 8 políticas (5 automáticas + 3), sin grants a anon, el rol sin login
  select count(*) into v_n from pg_policy where polrelid = 'public.compra_tarifa_historial'::regclass;
  v_res := v_res || jsonb_build_object('p', 'C1 políticas: 5 automáticas del asistente + 3 propias', 'esperado', '8', 'obtenido', v_n::text, 'ok', v_n = 8);
  select count(*) into v_n from information_schema.role_table_grants where table_name = 'compra_tarifa_historial' and grantee = 'anon';
  v_res := v_res || jsonb_build_object('p', 'C2 grants a anon', 'esperado', '0', 'obtenido', v_n::text, 'ok', v_n = 0);
  select count(*) into v_n from pg_roles where rolname = 'truefie_tarifa_auto' and not rolcanlogin;
  v_res := v_res || jsonb_build_object('p', 'C3 el rol de la revisión existe y NO entra (sin login)', 'esperado', '1', 'obtenido', v_n::text, 'ok', v_n = 1);

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: 32 filas (31 si no hay perfil asistente activo), todas ok = true.

rollback;
