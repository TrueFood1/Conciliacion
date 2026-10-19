-- ════════════════════════════════════════════════════════════════════════
-- ENSAYO · INCAPACIDADES, con datos FICTICIOS y ROLLBACK
-- 3-oct-2026. Va DESPUES de PERSONAL_INCAPACIDAD.sql, ya pegado.
-- Se corre en el SQL Editor de Supabase (como postgres).
--
-- ⚠️ TERMINA EN `rollback;`. No deja NI UNA FILA: las cuatro personas, los
-- cuatro salarios y los cinco permisos que crea se deshacen. Se puede correr
-- las veces que haga falta y sobre la base de produccion.
--
-- ⚠️ TODOS LOS MONTOS SON FICTICIOS. El salario de ensayo es 600.000, elegido
-- SOLO porque deja tarifas redondas (dia 20.000) y se cuadra de cabeza. NO es
-- el de nadie — este archivo va al repo, que es PUBLICO.
--
-- ⚠️ Y LA SALIDA NO IMPRIME NINGUN MONTO. Cada resultado sale como un FACTOR:
-- cuantas veces la tarifa diaria se descuenta. «-3,5 × tarifa_dia» dice todo lo
-- que hay que saber y no lleva plata adentro, asi que la tabla se puede pegar en
-- un chat o en la bitacora.
--
-- ════════════════════════════════════════════════════════════════════════
-- POR QUE HAY QUE IMPERSONAR A UNA SOCIA, Y POR QUE ESO ES LO MAS IMPORTANTE
-- ════════════════════════════════════════════════════════════════════════
-- `v_rrhh_pago_detalle` y `v_rrhh_permiso_dia` llevan `where acceso_es_socia()`,
-- que lee el correo del JWT. En el SQL Editor se corre como `postgres`, que NO
-- TIENE JWT: `auth.jwt()` da null, `acceso_perfil()` da null, y las vistas
-- devuelven CERO FILAS.
--
-- Con cero filas, `bool_and` da NULL y cada aserción «pasaría» sin haber medido
-- nada. Seria el ensayo entero en verde probando exactamente nada. Por eso la
-- seccion 0 se pone los zapatos de una socia real (sin imprimir su correo) y la
-- seccion 3 ABORTA si no lo logro. Un ensayo que no puede fallar no es un
-- ensayo.
--
-- QUE SE PRUEBA
--   1 · 2 dias: los dos caen en el tramo 1-3, la empresa paga 50%  -> -1,0 ×
--   2 · 5 dias: cruza el dia 3 -> 4 (3 al 50%, 2 al 0%)            -> -3,5 ×
--   3 · 14 al 18: CRUZA DE QUINCENA. Q1 -1,0 × y Q2 -2,5 ×, y la suma tiene que
--       dar lo MISMO que el caso 2: partir por quincena no puede cambiar el
--       total, y el conteo «dia 1-3 vs 4+» NO reinicia en el 16.
--   4 · accidente de trabajo: la nota tiene que nombrar al INS, no a la CCSS.
--   5 · con `incapacidad_reglas_confirmadas` = 0, cada nota termina en
--       «REGLAS SIN CONFIRMAR».
--   6 · el CHECK rechaza una incapacidad SIN origen (el hueco del NULL).
--   7 · una incapacidad no deja renglon de 'descuento_permiso'.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── 0 · LOS ZAPATOS DE UNA SOCIA, sin imprimir su correo ─────────────────
select set_config('ensayo.socia',
  coalesce((select email from acceso_usuario
             where perfil = 'socias' and activo order by id limit 1), ''), true);
select set_config('ensayo.sal', '600000', true);   -- FICTICIO. Tarifa dia = 20.000.

do $$
begin
  if coalesce(current_setting('ensayo.socia', true), '') = '' then
    raise exception 'ENSAYO ABORTADO: no hay ninguna socia activa en acceso_usuario. '
      'Sin eso las vistas devuelven CERO FILAS y todas las aserciones pasarian en falso.';
  end if;
end $$;


-- ── 1 · DATOS FICTICIOS ─────────────────────────────────────────────────
-- Se insertan como `postgres`, que salta la RLS y la politica `rrhh_permiso_ins`
-- (esa exige estado='pendiente'; aca hacen falta ya aprobados).
-- `email` va en null a proposito: el indice unico es sobre lower(email) y un
-- correo inventado podria chocar con uno real.
-- UNA PERSONA POR CASO, para que los totales de cada quincena no se mezclen.
with p as (
  insert into rrhh_persona (nombre, email, puesto, ingreso, creado_por)
  values ('ZZ Ensayo 1 · 2 dias',        null, 'ensayo', '2026-01-05', 'ensayo-incap'),
         ('ZZ Ensayo 2 · 5 dias',        null, 'ensayo', '2026-01-05', 'ensayo-incap'),
         ('ZZ Ensayo 3 · cruza quincena',null, 'ensayo', '2026-01-05', 'ensayo-incap'),
         ('ZZ Ensayo 4 · accidente',     null, 'ensayo', '2026-01-05', 'ensayo-incap')
  returning id, nombre
)
select set_config('ensayo.p' || row_number() over (order by id), id::text, true)
  from p;

insert into rrhh_salario (persona_id, salario_mensual, vigente_desde, nota, creado_por)
select current_setting('ensayo.p' || n, true)::bigint,
       current_setting('ensayo.sal', true)::numeric,
       '2026-01-05', 'FICTICIO · ensayo de incapacidades', 'ensayo-incap'
  from generate_series(1, 4) n;

-- Los permisos, ya aprobados. El CHECK `rrhh_permiso_resuelto` exige
-- resuelto_por y resuelto_en cuando el estado no es 'pendiente'.
insert into rrhh_permiso (persona_id, fecha_inicio, fecha_fin, motivo, estado,
                          resuelto_por, resuelto_en, creado_por,
                          modalidad_descuento, incapacidad_origen, incapacidad_boleta)
values
  -- 1 · dos dias, los dos en el tramo 1-3
  (current_setting('ensayo.p1', true)::bigint, '2026-10-05','2026-10-06', null, 'aprobado',
   'ensayo', now(), 'ensayo-incap', 'incapacidad','enfermedad_comun', null),
  -- 2 · cinco dias seguidos: dia 1,2,3 al 50% y 4,5 al 0%
  (current_setting('ensayo.p2', true)::bigint, '2026-10-01','2026-10-05', null, 'aprobado',
   'ensayo', now(), 'ensayo-incap', 'incapacidad','enfermedad_comun', 'B-ENSAYO-2'),
  -- 3 · cinco dias que CRUZAN el 15: dias 1-2 en Q1, dias 3-4-5 en Q2
  (current_setting('ensayo.p3', true)::bigint, '2026-10-14','2026-10-18', null, 'aprobado',
   'ensayo', now(), 'ensayo-incap', 'incapacidad','enfermedad_comun', null),
  -- 4 · accidente de trabajo, dos dias
  (current_setting('ensayo.p4', true)::bigint, '2026-10-20','2026-10-21', null, 'aprobado',
   'ensayo', now(), 'ensayo-incap', 'incapacidad','accidente_trabajo', 'B-ENSAYO-4');


-- ── 2 · EL CHECK, PROBADO DE VERDAD ─────────────────────────────────────
-- Una incapacidad SIN origen tiene que ser imposible. Es el hueco del NULL que
-- CAMBIO_NOTA_MIN_B.sql encontro el 15-sep: sin el coalesce(..., false) del
-- CHECK, `origen in (...)` da NULL, el AND da NULL, y Postgres ACEPTA la fila.
-- Se prueba insertando y atrapando el error, no leyendo la definicion.
do $$
declare v_freno boolean := false;
begin
  begin
    insert into rrhh_permiso (persona_id, fecha_inicio, fecha_fin, estado, creado_por,
                              modalidad_descuento, incapacidad_origen)
    values (current_setting('ensayo.p1', true)::bigint, '2026-11-02','2026-11-03',
            'pendiente', 'ensayo-incap', 'incapacidad', null);
    v_freno := false;                      -- entro: el CHECK NO freno
  exception when check_violation then
    v_freno := true;                       -- rechazo: es lo que se espera
  end;
  perform set_config('ensayo.check_sin_origen', v_freno::text, true);

  -- Y el espejo: un permiso que NO es incapacidad no puede llevar origen puesto.
  begin
    insert into rrhh_permiso (persona_id, fecha_inicio, fecha_fin, estado, creado_por,
                              modalidad_descuento, incapacidad_origen)
    values (current_setting('ensayo.p1', true)::bigint, '2026-11-05','2026-11-06',
            'pendiente', 'ensayo-incap', 'descuento', 'enfermedad_comun');
    perform set_config('ensayo.check_origen_colgado', 'false', true);
  exception when check_violation then
    perform set_config('ensayo.check_origen_colgado', 'true', true);
  end;

  -- Y una incapacidad por HORAS tampoco: se paga por dias.
  begin
    insert into rrhh_permiso (persona_id, fecha_inicio, fecha_fin, estado, creado_por,
                              modalidad_descuento, incapacidad_origen, horas)
    values (current_setting('ensayo.p1', true)::bigint, '2026-11-09','2026-11-09',
            'pendiente', 'ensayo-incap', 'incapacidad', 'enfermedad_comun', 3);
    perform set_config('ensayo.check_incap_horas', 'false', true);
  exception when check_violation then
    perform set_config('ensayo.check_incap_horas', 'true', true);
  end;
end $$;


-- ── 3 · AHORA SI, COMO SOCIA · Y ABORTA SI NO LO LOGRA ──────────────────
select set_config('request.jwt.claims',
  json_build_object('email', current_setting('ensayo.socia', true),
                    'role',  'authenticated')::text, true);
select set_config('role', 'authenticated', true);

do $$
begin
  if not coalesce(acceso_es_socia(), false) then
    raise exception 'ENSAYO ABORTADO: acceso_es_socia() no dio true despues de impersonar. '
      'Las vistas iban a devolver cero filas y el ensayo habria salido en verde sin medir '
      'nada. Revisar que el correo de acceso_usuario calce con v_acceso_usuario.';
  end if;
end $$;


-- ── 4 · LA TABLA DE RESULTADOS ──────────────────────────────────────────
-- `obtenido` va como FACTOR de la tarifa diaria, nunca como monto.
with t as (
  select (current_setting('ensayo.sal', true)::numeric
          / rrhh_param('dias_mes_tarifa', date '2026-10-15')) as tdia
),
d as (
  select d.persona_id, d.quincena, d.concepto, d.cantidad, d.monto, d.nota
    from v_rrhh_pago_detalle d
   where d.persona_id in (current_setting('ensayo.p1', true)::bigint,
                          current_setting('ensayo.p2', true)::bigint,
                          current_setting('ensayo.p3', true)::bigint,
                          current_setting('ensayo.p4', true)::bigint)
     -- ⚠️ EL FILTRO DE QUINCENA FALTABA, Y ESO ROMPIO LA FILA 15 (3-oct-2026).
     -- `v_rrhh_pago_detalle` emite un renglon de `base` por persona y por CADA
     -- quincena del universo, no solo por las del ensayo. Y el universo lo fija
     -- el ensayo mismo: los salarios entran con vigente_desde 2026-01-05 y el
     -- permiso del caso 3 llega al 21-oct, asi que van de 2026-01-Q1 a
     -- 2026-10-Q2 = 20 quincenas. 4 personas × 20 = 80 renglones de base, y la
     -- fila 15 esperaba 8. El 80 era CORRECTO: la prueba estaba mal escrita.
     --
     -- Las quincenas se DERIVAN del dato y no se escriben a mano, para que el
     -- filtro siga valiendo si alguien mueve las fechas del ensayo. Escribir
     -- 'in (2026-10-Q1, 2026-10-Q2)' habria sido poner la respuesta al lado de
     -- la pregunta.
     and d.quincena in (
       select distinct rrhh_quincena(pm.fecha_inicio + g.i)
         from rrhh_permiso pm
         cross join generate_series(0, (pm.fecha_fin - pm.fecha_inicio)) g(i)
        where pm.creado_por = 'ensayo-incap')
),
f as (
  select d.*, round(d.monto / t.tdia, 4) as factor from d cross join t
),
filas as (
  -- CASO 1 · dos dias en el tramo 1-3: 2 × (1 - 0,50) = 1,0
  select 1 as ord, 'C1 · 2 dias (tramo 1-3) · factor'::text as prueba,
         '-1,0000'::text as esperado,
         coalesce((select factor::text from f
                    where persona_id = current_setting('ensayo.p1', true)::bigint
                      and concepto = 'incapacidad'), 'SIN RENGLON') as obtenido,
         coalesce((select abs(factor + 1.0) < 0.0001 from f
                    where persona_id = current_setting('ensayo.p1', true)::bigint
                      and concepto = 'incapacidad'), false) as ok
  union all
  -- CASO 1b · dias contados
  select 2, 'C1 · dias contados', '2',
         coalesce((select cantidad::text from f
                    where persona_id = current_setting('ensayo.p1', true)::bigint
                      and concepto = 'incapacidad'), 'SIN RENGLON'),
         coalesce((select cantidad = 2 from f
                    where persona_id = current_setting('ensayo.p1', true)::bigint
                      and concepto = 'incapacidad'), false)
  union all
  -- CASO 2 · cinco dias: 3 × 0,5 + 2 × 1,0 = 3,5
  select 3, 'C2 · 5 dias (cruza 3->4) · factor', '-3,5000',
         coalesce((select factor::text from f
                    where persona_id = current_setting('ensayo.p2', true)::bigint
                      and concepto = 'incapacidad'), 'SIN RENGLON'),
         coalesce((select abs(factor + 3.5) < 0.0001 from f
                    where persona_id = current_setting('ensayo.p2', true)::bigint
                      and concepto = 'incapacidad'), false)
  union all
  -- CASO 3 · cruza quincena · Q1 = dias 1 y 2 -> 2 × 0,5 = 1,0
  select 4, 'C3 · cruza quincena · Q1 (dias 1-2)', '-1,0000',
         coalesce((select factor::text from f
                    where persona_id = current_setting('ensayo.p3', true)::bigint
                      and concepto = 'incapacidad' and quincena = '2026-10-Q1'), 'SIN RENGLON'),
         coalesce((select abs(factor + 1.0) < 0.0001 from f
                    where persona_id = current_setting('ensayo.p3', true)::bigint
                      and concepto = 'incapacidad' and quincena = '2026-10-Q1'), false)
  union all
  -- CASO 3 · Q2 = dias 3, 4 y 5 -> 0,5 + 1,0 + 1,0 = 2,5
  -- ESTA ES LA PRUEBA CLAVE: si el conteo reiniciara en el 16, Q2 daria
  -- 3 × 0,5 = 1,5 en vez de 2,5.
  select 5, 'C3 · cruza quincena · Q2 (dias 3-4-5, NO reinicia)', '-2,5000',
         coalesce((select factor::text from f
                    where persona_id = current_setting('ensayo.p3', true)::bigint
                      and concepto = 'incapacidad' and quincena = '2026-10-Q2'), 'SIN RENGLON'),
         coalesce((select abs(factor + 2.5) < 0.0001 from f
                    where persona_id = current_setting('ensayo.p3', true)::bigint
                      and concepto = 'incapacidad' and quincena = '2026-10-Q2'), false)
  union all
  -- CASO 3 · el total partido tiene que dar lo mismo que el caso 2
  select 6, 'C3 · Q1 + Q2 = lo mismo que C2 (5 dias seguidos)', '-3,5000',
         coalesce((select round(sum(factor), 4)::text from f
                    where persona_id = current_setting('ensayo.p3', true)::bigint
                      and concepto = 'incapacidad'), 'SIN RENGLON'),
         coalesce((select abs(sum(factor) + 3.5) < 0.0001 from f
                    where persona_id = current_setting('ensayo.p3', true)::bigint
                      and concepto = 'incapacidad'), false)
  union all
  -- CASO 4 · accidente: la nota nombra al INS
  select 7, 'C4 · accidente de trabajo · la nota dice INS', 'si',
         coalesce((select case when nota like '%INS%' then 'si' else 'NO: ' || left(nota, 60) end
                     from f where persona_id = current_setting('ensayo.p4', true)::bigint
                      and concepto = 'incapacidad'), 'SIN RENGLON'),
         coalesce((select nota like '%INS%' and nota not like '%CCSS%' from f
                    where persona_id = current_setting('ensayo.p4', true)::bigint
                      and concepto = 'incapacidad'), false)
  union all
  select 8, 'C1 · enfermedad · la nota dice CCSS', 'si',
         coalesce((select case when nota like '%CCSS%' then 'si' else 'NO' end from f
                    where persona_id = current_setting('ensayo.p1', true)::bigint
                      and concepto = 'incapacidad'), 'SIN RENGLON'),
         coalesce((select nota like '%CCSS%' from f
                    where persona_id = current_setting('ensayo.p1', true)::bigint
                      and concepto = 'incapacidad'), false)
  union all
  -- CASO 5 · el semaforo de reglas sin confirmar
  select 9, 'C5 · todas las notas dicen REGLAS SIN CONFIRMAR',
         'si (mientras incapacidad_reglas_confirmadas = 0)',
         case when (select valor from rrhh_param where clave='incapacidad_reglas_confirmadas'
                     order by vigente_desde desc, creado_en desc limit 1) = 1
              then 'n/a · el semaforo ya esta en 1'
              else coalesce((select bool_and(nota like '%REGLAS SIN CONFIRMAR%')::text
                               from f where concepto='incapacidad'), 'SIN RENGLONES') end,
         case when (select valor from rrhh_param where clave='incapacidad_reglas_confirmadas'
                     order by vigente_desde desc, creado_en desc limit 1) = 1
              then true
              else coalesce((select bool_and(nota like '%REGLAS SIN CONFIRMAR%')
                               from f where concepto='incapacidad'), false) end
  union all
  select 10, 'C5 · y dicen que el subsidio NO va en la transferencia', 'si',
         coalesce((select bool_and(nota like '%NO incluido en esta transferencia%')::text
                     from f where concepto='incapacidad'), 'SIN RENGLONES'),
         coalesce((select bool_and(nota like '%NO incluido en esta transferencia%')
                     from f where concepto='incapacidad'), false)
  union all
  -- CASO 6 · los tres CHECK
  select 11, 'C6 · incapacidad SIN origen: rechazada', 'true',
         current_setting('ensayo.check_sin_origen', true),
         current_setting('ensayo.check_sin_origen', true) = 'true'
  union all
  select 12, 'C6 · permiso normal CON origen colgado: rechazado', 'true',
         current_setting('ensayo.check_origen_colgado', true),
         current_setting('ensayo.check_origen_colgado', true) = 'true'
  union all
  select 13, 'C6 · incapacidad por HORAS: rechazada', 'true',
         current_setting('ensayo.check_incap_horas', true),
         current_setting('ensayo.check_incap_horas', true) = 'true'
  union all
  -- CASO 7 · una incapacidad no es un descuento de permiso
  select 14, 'C7 · ninguna incapacidad dejo renglon descuento_permiso', '0',
         (select count(*)::text from f where concepto = 'descuento_permiso'),
         (select count(*) = 0 from f where concepto = 'descuento_permiso')
  union all
  -- Y que la base de la quincena siga ahi: si el pegado rompio la rama vieja,
  -- esto lo caza antes que cualquier revision a ojo.
  -- Ahora cuenta SOLO las quincenas del ensayo (ver el filtro del CTE `d`):
  -- 4 personas × 2 quincenas = 8.
  select 15, 'la base sigue saliendo · 4 personas × 2 quincenas del ensayo', '8',
         (select count(*)::text from f where concepto = 'base'),
         (select count(*) = 8 from f where concepto = 'base')
  union all
  -- INFO, no es una prueba. Deja a la vista cuantas quincenas tiene el universo
  -- y cuantos renglones de base salen SIN el filtro. Existe porque el 3-oct ese
  -- numero (80) aparecio sin explicacion y costo una vuelta entenderlo: con esta
  -- fila, la proxima vez se lee solo.
  select 16, 'INFO · base en TODAS las quincenas del universo (sin filtrar)',
         'informativo: 4 × (quincenas del universo)',
         (select count(*)::text from v_rrhh_pago_detalle x
           where x.concepto = 'base'
             and x.persona_id in (current_setting('ensayo.p1', true)::bigint,
                                  current_setting('ensayo.p2', true)::bigint,
                                  current_setting('ensayo.p3', true)::bigint,
                                  current_setting('ensayo.p4', true)::bigint)),
         true
)
select ord, prueba, esperado, obtenido,
       case when ok then 'OK' else 'FALLA' end as veredicto
  from filas order by ord;

rollback;

-- ── DESPUES DEL ROLLBACK ────────────────────────────────────────────────
-- No tiene que quedar nada. Para comprobarlo (otra consulta, ya fuera de la
-- transaccion):
--   select count(*) from rrhh_persona where creado_por = 'ensayo-incap';   -- 0
--   select count(*) from rrhh_permiso where creado_por = 'ensayo-incap';   -- 0
