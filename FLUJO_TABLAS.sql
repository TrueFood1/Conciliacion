-- ═══════════════════════════════════════════════════════════════════════════
-- FLUJO_TABLAS.sql  ·  24-oct-2026  ·  T-275 F1 · Flujo de caja vivo en Finanzas
-- ⛔ SIN APLICAR. Escrito en seco. No se corrió contra Supabase ni contra ningún Postgres
--    (en la Mac no hay Postgres): pasó solo por compila_sql.py (parser real) y lint_sql_ensayo.py.
--    Primero va ENSAYO_FLUJO_TABLAS.sql (termina en rollback). Este header se toca DESPUÉS de
--    verificar, nunca sobre lo que alguien anunció que iba a hacer.
-- Para saber si está aplicado, mirar la base: `select to_regclass('public.flujo_compromiso')`.
--
-- QUÉ HACE (informes/DISENO_FLUJO_CAJA_22oct2026.md §4d y §4e)
--   flujo_compromiso  lo que entra o sale con fecha conocida: fijos, variables, MP, financieros,
--                     únicos (Reembolso III, tentativo), y VENTANAS (el cierre de fin de año, que
--                     apaga categorías por fecha de devengo). Append-only como rrhh_neto_quincena:
--                     cambiar un monto = fila nueva de la misma `clave` con su vigente_desde; terminar
--                     uno = fila nueva con vigente_hasta, o con activo = false. Gana la más nueva
--                     vigente ese día (flujoVersion en index.html).
--   flujo_ancla       el saldo del BAC con fecha, tipo (libros / disponible) y autora. Del XLS se
--                     guarda SOLO saldo, fecha y huella del archivo; nunca movimientos ni cuenta.
--   flujo_supuesto    los supuestos con nombres de clientes o montos de venta (ventas por canal,
--                     facturas excluidas, atrasos, caja mínima). Solo socias: plan_config lo lee todo
--                     usuario autenticado (plan_config_sel = true, medido el 29-oct).
--   flujo_corrida     la foto de cada viernes: las 26 semanas y el saldo por día (en céntimos, de
--                     flujoResumenCorrida), sin partidas con nombres. Sirve para el desvío de la semana.
--
--   QUIÉN: solo las socias leen y escriben, y cada una firma con SU correo. Nadie edita ni borra
--   (sin grant de update/delete). La corrida de la Action (F3) entra con un rol propio que este
--   archivo NO crea: hoy solo se acepta origen = 'pantalla'.
--   Las 5 políticas del asistente y el RLS los pone sola la base al crear cada tabla (event
--   triggers asistente_politicas y ensure_rls, verificados el 24-oct con pg_lector): este archivo NO
--   las escribe y las CUENTA en el control.
--   Los montos que se carguen son de EMPRESA y agregados. La planilla entra como total por quincena
--   (y después, con el OK de Lorena, por flujo_planilla()); nunca por persona.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

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
    and (categoria <> 'ventana' or (periodicidad = 'unica' and fecha is not null and fecha_hasta >= fecha
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

-- Control (ESPERADO: 4 · 28 · 0 · INSERT,SELECT · 4 · 0)
--   tablas con RLS · políticas (4 × (5 automáticas del asistente + 2 propias)) · grants a anon ·
--   grants a authenticated (los mismos en las tres) · índices propios · filas (nacen vacías)
select (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname in ('flujo_compromiso', 'flujo_ancla', 'flujo_corrida', 'flujo_supuesto')
           and c.relrowsecurity) as tablas_con_rls,
       (select count(*) from pg_policy where polrelid in ('public.flujo_compromiso'::regclass,
         'public.flujo_ancla'::regclass, 'public.flujo_corrida'::regclass, 'public.flujo_supuesto'::regclass)) as politicas,
       (select count(*) from information_schema.role_table_grants
         where table_name in ('flujo_compromiso', 'flujo_ancla', 'flujo_corrida', 'flujo_supuesto') and grantee = 'anon') as grants_anon,
       (select string_agg(distinct privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
         where table_name in ('flujo_compromiso', 'flujo_ancla', 'flujo_corrida', 'flujo_supuesto') and grantee = 'authenticated') as grants_authenticated,
       (select count(*) from pg_indexes where indexname in ('flujo_compromiso_clave', 'flujo_ancla_fecha',
         'flujo_corrida_semana', 'flujo_supuesto_clave')) as indices,
       (select count(*) from public.flujo_compromiso) + (select count(*) from public.flujo_ancla)
         + (select count(*) from public.flujo_corrida) + (select count(*) from public.flujo_supuesto) as filas;
commit;
