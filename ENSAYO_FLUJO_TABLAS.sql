-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_FLUJO_TABLAS.sql  ·  24-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Prueba las tablas de FLUJO_TABLAS.sql y lo deshace todo (rollback).
-- ⛔ SIN CORRER. No hay Postgres en la Mac: pasó solo por compila_sql.py y lint_sql_ensayo.py.
--
-- CÓMO SE LEE
--   Una tabla con TODAS las filas en ok = true. Un RECHAZA da ok solo si el SQLSTATE esperado es
--   el que salió (no vale rechazar por el motivo de al lado). Si el editor dice "Success. No rows
--   returned", no llegó al final y no vale.
--   42501 = RLS o sin permiso · 23514 = check.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE DDL (copia de FLUJO_TABLAS.sql, sin begin/commit ni el control) ▼▼▼
do $$ begin
  if to_regclass('public.flujo_compromiso') is not null or to_regclass('public.flujo_ancla') is not null
     or to_regclass('public.flujo_corrida') is not null or to_regclass('public.flujo_supuesto') is not null then
    raise exception 'alguna tabla flujo_* ya existe: este archivo no se vuelve a pegar';
  end if;
end $$;

-- ── flujo_compromiso: lo que entra o sale con fecha conocida (diseño §4d) ──
create table public.flujo_compromiso (
  id             bigint generated always as identity primary key,
  clave          text not null check (clave ~ '^[a-z0-9_]{2,40}$'),       -- une las versiones de un mismo compromiso
  concepto       text not null check (length(btrim(concepto)) between 1 and 120),
  categoria      text not null check (categoria in ('fijo', 'variable', 'MP', 'financiero', 'unico', 'venta', 'ventana')),
  sentido        text check (sentido in ('entrada', 'salida')),
  monto          numeric(14,2) check (monto >= 0),                         -- por ocurrencia, en su moneda
  moneda         text check (moneda in ('CRC', 'USD')),
  periodicidad   text not null check (periodicidad in ('diaria', 'semanal', 'quincenal', 'mensual', 'bimestral', 'unica')),
  dias           smallint[],                                               -- semanal: 1 lunes … 7 domingo · mes: 1–31 (31 = último)
  fecha          date,                                                     -- única: el día · ventana: desde
  fecha_hasta    date,                                                     -- ventana: hasta (incluido)
  apaga          text[],                                                   -- ventana: categorías que apaga, por fecha de devengo
  plazo_dias     smallint not null default 0 check (plazo_dias between 0 and 120),  -- la plata se mueve N días después del devengo
  vigente_desde  date not null,
  vigente_hasta  date,
  activo         boolean not null default true,                            -- false = baja desde vigente_desde
  tentativo      boolean not null default false,                           -- se suma, pero se dibuja aparte (y hay un saldo sin tentativos)
  proveedor      boolean not null default true,                            -- día no hábil: proveedor → hábil SIGUIENTE; si no (planilla, impuestos…) → ANTERIOR (Andrea 29-oct)
  regla          text check (length(regla) <= 300),                        -- p. ej. «desde tal mes — regla de Andrea»
  fuente         text not null check (length(btrim(fuente)) between 1 and 200),
  creado_por     text not null check (length(btrim(creado_por)) > 0),
  creado_en      timestamptz not null default now(),
  constraint flujo_compromiso_vigencia check (vigente_hasta is null or vigente_hasta >= vigente_desde),
  constraint flujo_compromiso_ventana check (
    (categoria = 'ventana') = (apaga is not null)
    and (categoria <> 'ventana' or (periodicidad = 'unica' and fecha is not null and fecha_hasta is not null and fecha_hasta >= fecha
         and cardinality(apaga) > 0 and apaga <@ array['fijo', 'variable', 'MP', 'financiero', 'unico', 'venta']
         and sentido is null and monto is null and moneda is null))),
  -- todo lo que no es ventana mueve plata: sentido, moneda y monto (0 solo en una baja)
  constraint flujo_compromiso_plata check (
    categoria = 'ventana' or (sentido is not null and moneda is not null and monto is not null
                              and (monto > 0 or not activo))),
  constraint flujo_compromiso_unica check (periodicidad <> 'unica' or fecha is not null),
  constraint flujo_compromiso_proveedor check (proveedor or sentido = 'salida'),  -- «no proveedor» es solo de una salida
  constraint flujo_compromiso_fecha_hasta check (categoria = 'ventana' or fecha_hasta is null),
  constraint flujo_compromiso_dias check (
    case periodicidad
      when 'semanal' then dias is not null and cardinality(dias) > 0 and dias <@ array[1,2,3,4,5,6,7]::smallint[]
      when 'diaria'  then dias is null
      when 'unica'   then dias is null
      else dias is not null and cardinality(dias) > 0
           and 1 <= all (dias) and 31 >= all (dias)
    end)
);
create index flujo_compromiso_clave on public.flujo_compromiso (clave, creado_en desc);

-- ── flujo_ancla: el saldo del BAC, con fecha y autora (diseño §4a: B con A de respaldo) ──
create table public.flujo_ancla (
  id             bigint generated always as identity primary key,
  fecha          date not null,                                            -- el saldo es al cierre de este día
  saldo          numeric(16,2) not null,                                   -- puede ser negativo
  tipo           text not null check (tipo in ('libros', 'disponible')),
  origen         text not null check (origen in ('extracto', 'a_mano')),
  huella         text check (huella ~ '^[0-9a-f]{16,64}$'),                -- del XLS; nunca el archivo ni sus movimientos
  nota           text check (length(nota) <= 300),
  creado_por     text not null check (length(btrim(creado_por)) > 0),
  creado_en      timestamptz not null default now(),
  constraint flujo_ancla_extracto check ((origen = 'extracto') = (huella is not null))
);
create index flujo_ancla_fecha on public.flujo_ancla (fecha desc, creado_en desc);

-- ── flujo_corrida: la foto de cada viernes (lo que se mandó), para el desvío de la semana ──
create table public.flujo_corrida (
  id             bigint generated always as identity primary key,
  semana_lunes   date not null check (extract(isodow from semana_lunes) = 1),
  ancla_id       bigint not null references public.flujo_ancla (id),
  saldo_inicial  numeric(16,2) not null,
  minimo         numeric(16,2) not null,
  minimo_fecha   date not null,
  saldo_final    numeric(16,2) not null,
  resumen        jsonb not null check (jsonb_typeof(resumen) = 'object' and resumen ? 'semanas' and resumen ? 'dias'),
  motor_version  text not null check (length(btrim(motor_version)) between 1 and 40),
  origen         text not null check (origen in ('pantalla', 'action')),
  creado_por     text not null check (length(btrim(creado_por)) > 0),
  creado_en      timestamptz not null default now()
);
create index flujo_corrida_semana on public.flujo_corrida (semana_lunes desc, creado_en desc);

-- ── flujo_supuesto: los supuestos del motor que llevan nombres de clientes o montos de venta ──
-- (ventas por canal, facturas que el motor no cuenta, atrasos de pago, caja mínima). NO van en plan_config:
-- su política plan_config_sel es `true` y lo lee TODO usuario autenticado (medido el 29-oct con pg_lector).
-- Append-only como plan_config: gana la fila más nueva de cada clave. El tipo de cambio sí queda en
-- plan_config (flujo_tc): es la venta del BCCR, pública.
create table public.flujo_supuesto (
  id             bigint generated always as identity primary key,
  clave          text not null check (clave in ('flujo_ventas', 'flujo_excluir', 'flujo_opciones', 'flujo_caja_minima')),
  valor          jsonb not null,
  nota           text check (length(nota) <= 300),
  creado_por     text not null check (length(btrim(creado_por)) > 0),
  creado_en      timestamptz not null default now(),
  constraint flujo_supuesto_forma check (
    case clave
      when 'flujo_ventas'   then jsonb_typeof(valor) = 'array'
      when 'flujo_excluir'  then jsonb_typeof(valor) = 'array'
      when 'flujo_opciones' then jsonb_typeof(valor) = 'object'
      else jsonb_typeof(valor) = 'number'
    end)
);
create index flujo_supuesto_clave on public.flujo_supuesto (clave, creado_en desc);

-- ── permisos: append-only, solo socias, cada una firma con su correo ──
alter table public.flujo_compromiso enable row level security;   -- ya lo prende ensure_rls; no estorba
alter table public.flujo_ancla      enable row level security;
alter table public.flujo_corrida    enable row level security;
alter table public.flujo_supuesto   enable row level security;
revoke all on public.flujo_compromiso, public.flujo_ancla, public.flujo_corrida, public.flujo_supuesto from anon, authenticated;
grant select, insert on public.flujo_compromiso, public.flujo_ancla, public.flujo_corrida, public.flujo_supuesto to authenticated;

create policy flujo_compromiso_sel on public.flujo_compromiso
  for select to authenticated using (acceso_es_socia());
create policy flujo_compromiso_ins on public.flujo_compromiso
  for insert to authenticated with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));
create policy flujo_ancla_sel on public.flujo_ancla
  for select to authenticated using (acceso_es_socia());
create policy flujo_ancla_ins on public.flujo_ancla
  for insert to authenticated with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));
create policy flujo_corrida_sel on public.flujo_corrida
  for select to authenticated using (acceso_es_socia());
create policy flujo_corrida_ins on public.flujo_corrida
  for insert to authenticated with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email') and origen = 'pantalla');
create policy flujo_supuesto_sel on public.flujo_supuesto
  for select to authenticated using (acceso_es_socia());
create policy flujo_supuesto_ins on public.flujo_supuesto
  for insert to authenticated with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

do $$
declare
  v_socia text; v_equipo text; v_asis text; v_n int; r record; v_ok boolean; v_obt text;
  v_res jsonb := '[]'::jsonb;
  -- un compromiso: %1$L clave · %2$L categoria · %3$s sentido · %4$s monto · %5$s moneda · %6$L periodicidad ·
  -- %7$s dias · %8$s fecha · %9$s fecha_hasta · %10$s apaga · %11$L creado_por
  comp constant text := 'insert into public.flujo_compromiso (clave, concepto, categoria, sentido, monto, moneda, '
    'periodicidad, dias, fecha, fecha_hasta, apaga, vigente_desde, fuente, creado_por) values (%1$L, ''Prueba'', %2$L, '
    '%3$s, %4$s, %5$s, %6$L, %7$s, %8$s, %9$s, %10$s, date ''2026-11-01'', ''ensayo'', %11$L)';
  -- un ancla: %1$L origen · %2$s huella · %3$L creado_por
  anc constant text := 'insert into public.flujo_ancla (fecha, saldo, tipo, origen, huella, creado_por) values '
    '(date ''2026-10-24'', -1234.56, ''disponible'', %1$L, %2$s, %3$L)';
  -- una corrida: %1$L semana_lunes · %2$s resumen · %3$L origen · %4$L creado_por
  cor constant text := 'insert into public.flujo_corrida (semana_lunes, ancla_id, saldo_inicial, minimo, minimo_fecha, '
    'saldo_final, resumen, motor_version, origen, creado_por) values (date %1$L, (select max(id) from public.flujo_ancla), '
    '1, -5, date ''2026-11-05'', 2, %2$s, ''f1-24oct2026'', %3$L, %4$L)';
  res_ok constant text := '''{"semanas": [], "dias": []}''::jsonb';
  -- un supuesto: %1$L clave · %2$s valor · %3$L creado_por
  sup constant text := 'insert into public.flujo_supuesto (clave, valor, creado_por) values (%1$L, %2$s, %3$L)';
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by id limit 1;
  select email into v_equipo from v_acceso_usuario where perfil not in ('socias', 'asistente') and activo order by id limit 1;
  select email into v_asis   from v_acceso_usuario where perfil = 'asistente' and activo order by id limit 1;
  if v_socia is null or v_equipo is null then
    raise exception 'el ensayo necesita una socia y alguien de equipo (socia %, equipo %)', v_socia, v_equipo;
  end if;

  for r in
    select * from (values
      -- socia: lo que tiene que entrar
      (1,  'S1 socia: compromiso mensual con SU nombre',                       'authenticated', v_socia,
           format(comp, 'alquiler', 'fijo', '''salida''', '1111000', '''CRC''', 'mensual', 'array[1]::smallint[]', 'null', 'null', 'null', v_socia), null),
      (2,  'S2 socia: ventana de cierre que apaga MP',                          'authenticated', v_socia,
           format(comp, 'cierre_fin_de_anio', 'ventana', 'null', 'null', 'null', 'unica', 'null', 'date ''2026-12-18''', 'date ''2027-01-11''', 'array[''MP'']', v_socia), null),
      (3,  'S3 socia: ancla escrita a mano, saldo negativo',                    'authenticated', v_socia,
           format(anc, 'a_mano', 'null', v_socia), null),
      (4,  'S4 socia: ancla del extracto con huella',                           'authenticated', v_socia,
           format(anc, 'extracto', '''a1b2c3d4e5f60718''', v_socia), null),
      (5,  'S5 socia: corrida desde la pantalla',                               'authenticated', v_socia,
           format(cor, '2026-10-19', res_ok, 'pantalla', v_socia), null),
      -- socia: lo que no
      (6,  'T1 socia firma con OTRO nombre',                                    'authenticated', v_socia,
           format(comp, 'alquiler', 'fijo', '''salida''', '1', '''CRC''', 'mensual', 'array[1]::smallint[]', 'null', 'null', 'null', 'otra@persona.com'), '42501'),
      (7,  'T2 socia EDITA un compromiso',                                      'authenticated', v_socia,
           'update public.flujo_compromiso set monto = 1', '42501'),
      (8,  'T3 socia BORRA un ancla',                                           'authenticated', v_socia,
           'delete from public.flujo_ancla', '42501'),
      (9,  'T4 socia anota una corrida «action» (es del rol de F3)',            'authenticated', v_socia,
           format(cor, '2026-10-19', res_ok, 'action', v_socia), '42501'),
      -- checks (como socia: la política deja pasar, frena la tabla)
      (10, 'C1 categoría inventada',                                            'authenticated', v_socia,
           format(comp, 'x_1', 'otra', '''salida''', '1', '''CRC''', 'mensual', 'array[1]::smallint[]', 'null', 'null', 'null', v_socia), '23514'),
      (11, 'C2 ventana sin fecha_hasta',                                        'authenticated', v_socia,
           format(comp, 'x_2', 'ventana', 'null', 'null', 'null', 'unica', 'null', 'date ''2026-12-18''', 'null', 'array[''MP'']', v_socia), '23514'),
      (12, 'C3 monto negativo',                                                 'authenticated', v_socia,
           format(comp, 'x_3', 'fijo', '''salida''', '-5', '''CRC''', 'mensual', 'array[1]::smallint[]', 'null', 'null', 'null', v_socia), '23514'),
      (13, 'C4 única sin fecha',                                                'authenticated', v_socia,
           format(comp, 'x_4', 'unico', '''salida''', '5', '''CRC''', 'unica', 'null', 'null', 'null', 'null', v_socia), '23514'),
      (14, 'C5 semanal el día 8',                                               'authenticated', v_socia,
           format(comp, 'x_5', 'variable', '''salida''', '5', '''CRC''', 'semanal', 'array[8]::smallint[]', 'null', 'null', 'null', v_socia), '23514'),
      (15, 'C6 ventana que apaga una categoría inventada',                      'authenticated', v_socia,
           format(comp, 'x_6', 'ventana', 'null', 'null', 'null', 'unica', 'null', 'date ''2026-12-18''', 'date ''2027-01-11''', 'array[''planilla'']', v_socia), '23514'),
      (16, 'C7 mensual el día 0',                                               'authenticated', v_socia,
           format(comp, 'x_7', 'fijo', '''salida''', '5', '''CRC''', 'mensual', 'array[0]::smallint[]', 'null', 'null', 'null', v_socia), '23514'),
      (17, 'C8 compromiso sin moneda',                                          'authenticated', v_socia,
           format(comp, 'x_8', 'fijo', '''salida''', '5', 'null', 'mensual', 'array[1]::smallint[]', 'null', 'null', 'null', v_socia), '23514'),
      (18, 'C9 clave con mayúsculas y espacios',                                'authenticated', v_socia,
           format(comp, 'Alquiler Local', 'fijo', '''salida''', '5', '''CRC''', 'mensual', 'array[1]::smallint[]', 'null', 'null', 'null', v_socia), '23514'),
      (19, 'C10 ancla del extracto SIN huella',                                 'authenticated', v_socia,
           format(anc, 'extracto', 'null', v_socia), '23514'),
      (20, 'C11 corrida con semana que no arranca lunes',                       'authenticated', v_socia,
           format(cor, '2026-10-24', res_ok, 'pantalla', v_socia), '23514'),
      (21, 'C12 corrida sin los días en el resumen',                            'authenticated', v_socia,
           format(cor, '2026-10-19', '''{"semanas": []}''::jsonb', 'pantalla', v_socia), '23514'),
      -- equipo y anon
      (22, 'E1 alguien de equipo anota un compromiso',                          'authenticated', v_equipo,
           format(comp, 'x_9', 'fijo', '''salida''', '5', '''CRC''', 'mensual', 'array[1]::smallint[]', 'null', 'null', 'null', v_equipo), '42501'),
      (23, 'E2 alguien de equipo anota un ancla',                               'authenticated', v_equipo,
           format(anc, 'a_mano', 'null', v_equipo), '42501'),
      (24, 'A1 anon lee los compromisos',                                       'anon', null,
           'select count(*) from public.flujo_compromiso', '42501'),
      (25, 'A2 anon anota un ancla',                                            'anon', null,
           format(anc, 'a_mano', 'null', 'anon'), '42501'),
      -- flujo_supuesto
      (26, 'S7 socia: supuesto de ventas por canal',                            'authenticated', v_socia,
           format(sup, 'flujo_ventas', '''[{"canal": "A", "monto_semanal": 1000}]''::jsonb', v_socia), null),
      (27, 'T5 socia firma un supuesto con OTRO nombre',                        'authenticated', v_socia,
           format(sup, 'flujo_ventas', '''[]''::jsonb', 'otra@persona.com'), '42501'),
      (28, 'C13 supuesto con clave inventada',                                  'authenticated', v_socia,
           format(sup, 'flujo_otra', '''[]''::jsonb', v_socia), '23514'),
      (29, 'C14 ventas que no son una lista',                                   'authenticated', v_socia,
           format(sup, 'flujo_ventas', '''{"canal": "A"}''::jsonb', v_socia), '23514'),
      (30, 'E4 alguien de equipo anota un supuesto',                            'authenticated', v_equipo,
           format(sup, 'flujo_excluir', '''[]''::jsonb', v_equipo), '42501'),
      -- proveedor: decide a qué hábil va un pago que cae en sábado, domingo o feriado
      (31, 'S8 socia: planilla como NO proveedor (hábil anterior)',             'authenticated', v_socia,
           'insert into public.flujo_compromiso (clave, concepto, categoria, sentido, monto, moneda, periodicidad, dias, '
           'vigente_desde, proveedor, fuente, creado_por) values (''planilla'', ''Prueba'', ''fijo'', ''salida'', 5, ''CRC'', '
           '''quincenal'', array[15,31]::smallint[], date ''2026-11-01'', false, ''ensayo'', ' || quote_literal(v_socia) || ')', null),
      (32, 'C15 una ENTRADA marcada como no proveedor',                         'authenticated', v_socia,
           'insert into public.flujo_compromiso (clave, concepto, categoria, sentido, monto, moneda, periodicidad, dias, '
           'vigente_desde, proveedor, fuente, creado_por) values (''x_10'', ''Prueba'', ''unico'', ''entrada'', 5, ''CRC'', '
           '''mensual'', array[1]::smallint[], date ''2026-11-01'', false, ''ensayo'', ' || quote_literal(v_socia) || ')', '23514')
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

  -- lecturas: equipo no ve nada; la socia ve lo que entró (3 compromisos, 2 anclas, 1 corrida, 1 supuesto = 7)
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select (select count(*) from public.flujo_compromiso) + (select count(*) from public.flujo_ancla)
       + (select count(*) from public.flujo_corrida) + (select count(*) from public.flujo_supuesto) into v_n;
  perform set_config('role', 'postgres', true);
  v_res := v_res || jsonb_build_object('p', 'E3 alguien de equipo NO ve el flujo', 'esperado', '0', 'obtenido', v_n::text, 'ok', v_n = 0);
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select (select count(*) from public.flujo_compromiso) + (select count(*) from public.flujo_ancla)
       + (select count(*) from public.flujo_corrida) + (select count(*) from public.flujo_supuesto) into v_n;
  perform set_config('role', 'postgres', true);
  v_res := v_res || jsonb_build_object('p', 'S6 la socia ve las 7 filas (S1–S5, S7 y S8)', 'esperado', '7', 'obtenido', v_n::text, 'ok', v_n = 7);
  if v_asis is not null then
    perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    begin
      execute format(anc, 'a_mano', 'null', v_asis);
      v_obt := 'ENTRA'; v_ok := false;
    exception when others then
      v_obt := 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm; v_ok := sqlstate = '42501';
    end;
    perform set_config('role', 'postgres', true);
    v_res := v_res || jsonb_build_object('p', 'I1 el asistente anota un ancla', 'esperado', 'RECHAZA · 42501', 'obtenido', v_obt, 'ok', v_ok);
  end if;

  -- catálogo
  select count(*) into v_n from pg_policy where polrelid in ('public.flujo_compromiso'::regclass,
    'public.flujo_ancla'::regclass, 'public.flujo_corrida'::regclass, 'public.flujo_supuesto'::regclass);
  v_res := v_res || jsonb_build_object('p', 'K1 políticas: 4 × (5 automáticas + 2 propias)', 'esperado', '28', 'obtenido', v_n::text, 'ok', v_n = 28);
  select count(*) into v_n from information_schema.role_table_grants
   where table_name in ('flujo_compromiso', 'flujo_ancla', 'flujo_corrida', 'flujo_supuesto') and grantee = 'anon';
  v_res := v_res || jsonb_build_object('p', 'K2 grants a anon', 'esperado', '0', 'obtenido', v_n::text, 'ok', v_n = 0);
  select count(*) into v_n from pg_class c join pg_namespace s on s.oid = c.relnamespace
   where s.nspname = 'public' and c.relname in ('flujo_compromiso', 'flujo_ancla', 'flujo_corrida', 'flujo_supuesto') and c.relrowsecurity;
  v_res := v_res || jsonb_build_object('p', 'K3 las cuatro tablas con RLS', 'esperado', '4', 'obtenido', v_n::text, 'ok', v_n = 4);

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: 38 filas (37 si no hay perfil asistente activo), todas ok = true.

rollback;
