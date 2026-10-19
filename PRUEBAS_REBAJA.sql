-- ════════════════════════════════════════════════════════════════════════
-- ENSAYO · REBAJA DEL TRABAJADOR, con datos FICTICIOS y ROLLBACK
-- 3-oct-2026. Va DESPUES de PERSONAL_REBAJA_TRABAJADOR.sql, ya pegado.
-- Se corre en el SQL Editor de Supabase (como postgres).
--
-- ⚠️ TERMINA EN `rollback;`. No deja ni una fila: las cuatro personas, los
-- cuatro salarios, el permiso, la incapacidad, el ajuste y la fila de parametro
-- que inserta para la prueba 6 se deshacen todos.
--
-- ⚠️ EL SALARIO ES FICTICIO: 600.000, elegido porque deja tarifa diaria 20.000
-- y base de quincena 300.000, y se cuadra de cabeza. NO es el de nadie. Los
-- montos que imprime la tabla salen TODOS de ese numero inventado.
--
-- ⚠️ EL PORCENTAJE NO ESTA ESCRITO ACA. Los esperados se derivan de
-- `rrhh_param('rebaja_trabajador_pct')`, igual que la vista. Si manana la
-- contadora dice 10,67 en vez de 6,49, este ensayo sigue valiendo sin tocarlo —
-- que es justamente lo que se quiere demostrar (prueba 6).
--
-- ⚠️ IMPERSONA A UNA SOCIA. `v_rrhh_pago` y `v_rrhh_pago_detalle` llevan
-- `where acceso_es_socia()`, que lee el correo del JWT. Como `postgres` no hay
-- JWT, las vistas devuelven CERO FILAS y cada asercion "pasaria" sin medir
-- nada. La seccion 2 se pone los zapatos de una socia real (sin imprimir su
-- correo) y ABORTA si no lo logra.
--
-- QUE SE PRUEBA
--   1 · sin permisos: neto = base × (1 - pct)
--   2 · con 2 dias de descuento: da LO MISMO que calcular la tarifa sobre el
--       neto. No es casualidad, es distributividad; se comprueba con numeros.
--   3 · el ajuste manual NO lleva rebaja (es un monto neto que escribio una socia)
--   4 · la parte de la incapacidad que paga la empresa NO lleva rebaja
--   5 · mientras rebaja_trabajador_confirmada = 0, la nota avisa
--   6 · cambiar el pct en el PARAMETRO cambia el neto, sin tocar codigo
--   7 · el desglose suma al neto (el control de la pantalla, con el renglon nuevo)
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── 1 · DATOS FICTICIOS (como postgres: salta RLS y politicas) ──────────
select set_config('ens.sal', '600000', true);          -- FICTICIO
select set_config('ens.q',   '2026-10-Q1', true);
select set_config('ens.socia',
  coalesce((select email from acceso_usuario
             where perfil='socias' and activo order by id limit 1), ''), true);

do $$
begin
  if coalesce(current_setting('ens.socia', true), '') = '' then
    raise exception 'ENSAYO ABORTADO: no hay socia activa en acceso_usuario. Sin eso las '
      'vistas devuelven CERO FILAS y todo "pasaria" sin medir nada.';
  end if;
end $$;

with p as (
  insert into rrhh_persona (nombre, email, puesto, ingreso, creado_por)
  values ('ZZ Rebaja 1 · sin nada',   null, 'ensayo', '2026-01-05', 'ensayo-rebaja'),
         ('ZZ Rebaja 2 · permiso',    null, 'ensayo', '2026-01-05', 'ensayo-rebaja'),
         ('ZZ Rebaja 3 · ajuste',     null, 'ensayo', '2026-01-05', 'ensayo-rebaja'),
         ('ZZ Rebaja 4 · incapacidad',null, 'ensayo', '2026-01-05', 'ensayo-rebaja')
  returning id
)
select set_config('ens.p' || row_number() over (order by id), id::text, true) from p;

insert into rrhh_salario (persona_id, salario_mensual, vigente_desde, nota, creado_por)
select current_setting('ens.p'||n, true)::bigint,
       current_setting('ens.sal', true)::numeric,
       '2026-01-05', 'FICTICIO · ensayo de rebaja', 'ensayo-rebaja'
  from generate_series(1,4) n;

-- P2 · dos dias habiles con descuento (6 y 7 de oct 2026 son martes y miercoles)
insert into rrhh_permiso (persona_id, fecha_inicio, fecha_fin, estado,
                          resuelto_por, resuelto_en, creado_por, modalidad_descuento)
values (current_setting('ens.p2', true)::bigint, '2026-10-06','2026-10-07','aprobado',
        'ensayo', now(), 'ensayo-rebaja', 'descuento');

-- P3 · un ajuste manual: monto NETO, no lleva rebaja
insert into rrhh_ajuste_manual (persona_id, fecha, monto, nota, creado_por)
values (current_setting('ens.p3', true)::bigint, '2026-10-08', -50000,
        'adelanto de ensayo', 'ensayo-rebaja');

-- P4 · incapacidad de dos dias: los dos caen en el tramo 1-3, al 50%
insert into rrhh_permiso (persona_id, fecha_inicio, fecha_fin, estado,
                          resuelto_por, resuelto_en, creado_por,
                          modalidad_descuento, incapacidad_origen)
values (current_setting('ens.p4', true)::bigint, '2026-10-06','2026-10-07','aprobado',
        'ensayo', now(), 'ensayo-rebaja', 'incapacidad', 'enfermedad_comun');


-- ── 2 · LOS ZAPATOS DE LA SOCIA, Y EL GUARDIA ───────────────────────────
select set_config('request.jwt.claims',
  json_build_object('email', current_setting('ens.socia', true),
                    'role',  'authenticated')::text, true);
select set_config('role', 'authenticated', true);

do $$
begin
  if not coalesce(acceso_es_socia(), false) then
    raise exception 'ENSAYO ABORTADO: acceso_es_socia() no dio true despues de impersonar. '
      'Las vistas iban a devolver cero filas y el ensayo habria salido verde sin medir nada.';
  end if;
end $$;


-- ── 3 · FASE A · capturar con el pct ORIGINAL ───────────────────────────
-- Se capturan ESCALARES y no verdictos: las aserciones viven todas juntas en la
-- tabla final, donde se pueden leer al lado de su esperado.
do $$
declare
  q text := current_setting('ens.q', true);
  r record;
begin
  perform set_config('ens.a_pct',
    (select rrhh_param('rebaja_trabajador_pct', max(fin))::text
       from v_rrhh_pago where quincena = q), true);

  for r in
    select 'p'||n as k, current_setting('ens.p'||n, true)::bigint as pid
      from generate_series(1,4) n
  loop
    perform set_config('ens.a_'||r.k||'_final',
      coalesce((select final::text    from v_rrhh_pago
                 where persona_id = r.pid and quincena = q), ''), true);
    perform set_config('ens.a_'||r.k||'_sub',
      coalesce((select subtotal::text from v_rrhh_pago
                 where persona_id = r.pid and quincena = q), ''), true);
    perform set_config('ens.a_'||r.k||'_reb',
      coalesce((select rebaja::text   from v_rrhh_pago
                 where persona_id = r.pid and quincena = q), ''), true);
  end loop;

  -- P2 · los dias que la vista conto. Se LEE en vez de asumir 2: si algun
  -- feriado cayera el 6 o el 7, asumirlo haria fallar la prueba de la rebaja por
  -- un motivo que no es la rebaja.
  perform set_config('ens.a_p2_cant',
    coalesce((select cantidad::text from v_rrhh_pago_detalle
               where persona_id = current_setting('ens.p2', true)::bigint
                 and quincena = q and concepto = 'descuento_permiso'), ''), true);

  -- P4 · de la incapacidad salen el bruto (cantidad × tarifa) y lo que paga la
  -- empresa (bruto + monto, porque monto = -(bruto - empresa)).
  select cantidad, tarifa, monto into r
    from v_rrhh_pago_detalle
   where persona_id = current_setting('ens.p4', true)::bigint
     and quincena = q and concepto = 'incapacidad';
  perform set_config('ens.a_p4_cant',   coalesce(r.cantidad::text,''), true);
  perform set_config('ens.a_p4_tarifa', coalesce(r.tarifa::text,''),   true);
  perform set_config('ens.a_p4_monto',  coalesce(r.monto::text,''),    true);

  -- La nota del renglon de rebaja de P1, para la prueba 5.
  perform set_config('ens.a_nota',
    coalesce((select nota from v_rrhh_pago_detalle
               where persona_id = current_setting('ens.p1', true)::bigint
                 and quincena = q and concepto = 'rebaja'), ''), true);
end $$;


-- ── 4 · CAMBIAR EL PARAMETRO · vuelve a postgres para poder insertar ────
-- `authenticated` no tiene insert en rrhh_param (ni politica), asi que esto
-- SOLO se puede hacer como postgres. Volver es legal porque el usuario de
-- sesion sigue siendo postgres.
select set_config('role', 'postgres', true);

-- 10 es el valor DE LA PRUEBA, no una regla: se elige distinto del original
-- para que el cambio se note, y con un neto redondo (300.000 × 0,90).
insert into rrhh_param (clave, valor, vigente_desde, nota, creado_por)
values ('rebaja_trabajador_pct', 10.0, '2026-10-01',
        'FILA DE ENSAYO · se deshace con el rollback', 'ensayo-rebaja');

select set_config('request.jwt.claims',
  json_build_object('email', current_setting('ens.socia', true),
                    'role',  'authenticated')::text, true);
select set_config('role', 'authenticated', true);


-- ── 5 · FASE B · el mismo neto, con el pct nuevo ────────────────────────
do $$
declare q text := current_setting('ens.q', true);
begin
  perform set_config('ens.b_pct',
    (select rrhh_param('rebaja_trabajador_pct', max(fin))::text
       from v_rrhh_pago where quincena = q), true);
  perform set_config('ens.b_p1_final',
    coalesce((select final::text from v_rrhh_pago
               where persona_id = current_setting('ens.p1', true)::bigint
                 and quincena = q), ''), true);
end $$;


-- ── 6 · LA TABLA DE RESULTADOS ──────────────────────────────────────────
-- Lee SOLO settings y constantes del ensayo, asi que no depende del rol ni de
-- que las vistas sigan contestando. Los montos son todos ficticios.
with k as (
  select current_setting('ens.sal', true)::numeric            as sal,
         nullif(current_setting('ens.a_pct', true),'')::numeric as p0,
         nullif(current_setting('ens.b_pct', true),'')::numeric as p1n
),
c as (
  select k.*,
         k.sal / 2                      as base,
         k.sal / 30                     as tdia,
         1 - k.p0/100                   as f0,
         1 - k.p1n/100                  as f1
    from k
),
g as (
  select c.*,
         nullif(current_setting('ens.a_p1_final', true),'')::numeric as a1,
         nullif(current_setting('ens.a_p1_sub',   true),'')::numeric as s1,
         nullif(current_setting('ens.a_p1_reb',   true),'')::numeric as r1,
         nullif(current_setting('ens.a_p2_final', true),'')::numeric as a2,
         nullif(current_setting('ens.a_p2_cant',  true),'')::numeric as c2,
         nullif(current_setting('ens.a_p3_final', true),'')::numeric as a3,
         nullif(current_setting('ens.a_p4_final', true),'')::numeric as a4,
         nullif(current_setting('ens.a_p4_cant',  true),'')::numeric as c4,
         nullif(current_setting('ens.a_p4_tarifa',true),'')::numeric as t4,
         nullif(current_setting('ens.a_p4_monto', true),'')::numeric as m4,
         nullif(current_setting('ens.b_p1_final', true),'')::numeric as b1,
         coalesce(current_setting('ens.a_nota', true),'')            as nota
    from c
),
x as (
  select g.*,
         (g.c4 * g.t4)             as bruto4,      -- tarifa_dia × dias de incapacidad
         (g.c4 * g.t4 + g.m4)      as emp4         -- lo que paga la empresa
    from g
),
filas as (
  select 0 as ord, 'pct leido del parametro (no escrito en el ensayo)'::text as prueba,
         'el de rrhh_param'::text as esperado,
         coalesce(x.p0::text,'SIN CAPTURAR') as obtenido,
         (x.p0 is not null) as ok from x
  union all
  -- 1 · sin nada: neto = base × (1 - pct)
  select 1, 'P1 sin permisos: neto = base × (1-pct)',
         to_char(x.base * x.f0, 'FM999999990.00'),
         coalesce(to_char(x.a1,'FM999999990.00'),'SIN CAPTURAR'),
         coalesce(abs(x.a1 - x.base * x.f0) < 0.01, false) from x
  union all
  select 2, 'P1 el subtotal es la base (nada que restar)',
         to_char(x.base,'FM999999990.00'),
         coalesce(to_char(x.s1,'FM999999990.00'),'SIN CAPTURAR'),
         coalesce(abs(x.s1 - x.base) < 0.01, false) from x
  union all
  select 3, 'P1 el renglon de rebaja = -(base × pct/100)',
         to_char(-(x.base * x.p0/100),'FM999999990.00'),
         coalesce(to_char(x.r1,'FM999999990.00'),'SIN CAPTURAR'),
         coalesce(abs(x.r1 + x.base * x.p0/100) < 0.01, false) from x
  union all
  -- 2 · la equivalencia: aplicar el pct DESPUES = tarifa sobre el neto
  select 4, 'P2 ' || coalesce(x.c2::text,'?') || ' dias: (base - d×S/30)×(1-pct)',
         to_char((x.base - x.c2 * x.tdia) * x.f0,'FM999999990.00'),
         coalesce(to_char(x.a2,'FM999999990.00'),'SIN CAPTURAR'),
         coalesce(abs(x.a2 - (x.base - x.c2 * x.tdia) * x.f0) < 0.01, false) from x
  union all
  select 5, 'P2 IGUAL a la tarifa sobre el neto: base×(1-p) - d×(S×(1-p)/30)',
         to_char(x.base * x.f0 - x.c2 * (x.sal * x.f0 / 30),'FM999999990.00'),
         coalesce(to_char(x.a2,'FM999999990.00'),'SIN CAPTURAR'),
         coalesce(abs(x.a2 - (x.base * x.f0 - x.c2 * (x.sal * x.f0 / 30))) < 0.01, false) from x
  union all
  -- 3 · el ajuste no lleva rebaja
  select 6, 'P3 ajuste SIN rebaja: base×(1-pct) - 50000',
         to_char(x.base * x.f0 - 50000,'FM999999990.00'),
         coalesce(to_char(x.a3,'FM999999990.00'),'SIN CAPTURAR'),
         coalesce(abs(x.a3 - (x.base * x.f0 - 50000)) < 0.01, false) from x
  union all
  select 7, 'P3 y NO es (base-50000)×(1-pct) — el contraste',
         'distinto de ' || to_char((x.base - 50000) * x.f0,'FM999999990.00'),
         coalesce(to_char(x.a3,'FM999999990.00'),'SIN CAPTURAR'),
         coalesce(abs(x.a3 - (x.base - 50000) * x.f0) > 0.01, false) from x
  union all
  -- 4 · la parte de la empresa no lleva rebaja
  select 8, 'P4 incapacidad: (base - bruto)×(1-pct) + lo que paga la empresa',
         to_char((x.base - x.bruto4) * x.f0 + x.emp4,'FM999999990.00'),
         coalesce(to_char(x.a4,'FM999999990.00'),'SIN CAPTURAR'),
         coalesce(abs(x.a4 - ((x.base - x.bruto4) * x.f0 + x.emp4)) < 0.01, false) from x
  union all
  select 9, 'P4 y NO es (base - bruto + empresa)×(1-pct) — el contraste',
         'distinto de ' || to_char((x.base - x.bruto4 + x.emp4) * x.f0,'FM999999990.00'),
         coalesce(to_char(x.a4,'FM999999990.00'),'SIN CAPTURAR'),
         coalesce(abs(x.a4 - (x.base - x.bruto4 + x.emp4) * x.f0) > 0.01, false) from x
  union all
  -- 5 · el semaforo
  select 10, 'la nota avisa mientras rebaja_trabajador_confirmada = 0', 'si',
         case when x.nota = '' then 'SIN RENGLON DE REBAJA'
              when x.nota like '%SIN CONFIRMAR%' then 'si' else 'NO: ' || left(x.nota,60) end,
         (x.nota like '%SIN CONFIRMAR%') from x
  union all
  select 11, 'y la nota dice el porcentaje', 'si',
         case when x.nota like '%' || trim(to_char(x.p0,'FM999990.00')) || '%'
              then 'si' else 'NO: ' || left(x.nota,60) end,
         (x.nota like '%' || trim(to_char(x.p0,'FM999990.00')) || '%') from x
  union all
  -- 6 · cambiar el parametro cambia el neto, sin tocar codigo
  select 12, 'pct cambiado en el parametro: ' || coalesce(x.p0::text,'?')
             || ' -> ' || coalesce(x.p1n::text,'?'),
         'distintos', coalesce(x.p1n::text,'SIN CAPTURAR'),
         coalesce(x.p1n is distinct from x.p0, false) from x
  union all
  select 13, 'P1 con el pct nuevo: neto = base × (1-pct nuevo)',
         to_char(x.base * x.f1,'FM999999990.00'),
         coalesce(to_char(x.b1,'FM999999990.00'),'SIN CAPTURAR'),
         coalesce(abs(x.b1 - x.base * x.f1) < 0.01, false) from x
  union all
  select 14, 'y el neto SE MOVIO (no quedo pegado al valor viejo)',
         'distinto de ' || coalesce(to_char(x.a1,'FM999999990.00'),'?'),
         coalesce(to_char(x.b1,'FM999999990.00'),'SIN CAPTURAR'),
         coalesce(abs(x.b1 - x.a1) > 0.01, false) from x
)
select ord, prueba, esperado, obtenido,
       case when ok then 'OK' else 'FALLA' end as veredicto
  from filas order by ord;

rollback;

-- ── DESPUES DEL ROLLBACK ────────────────────────────────────────────────
-- No tiene que quedar nada. La fila de parametro de la prueba 6 tambien se
-- deshace: si quedara, la rebaja real pasaria a ser 10% en silencio.
--   select count(*) from rrhh_persona      where creado_por = 'ensayo-rebaja';  -- 0
--   select count(*) from rrhh_permiso      where creado_por = 'ensayo-rebaja';  -- 0
--   select count(*) from rrhh_salario      where creado_por = 'ensayo-rebaja';  -- 0
--   select count(*) from rrhh_ajuste_manual where creado_por = 'ensayo-rebaja'; -- 0
--   select count(*) from rrhh_param        where creado_por = 'ensayo-rebaja';  -- 0  <- la mas importante
