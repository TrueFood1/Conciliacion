-- ════════════════════════════════════════════════════════════════════════
-- LOS ESPERADOS ESTAN ESCRITOS A MANO, derivados del calendario:
--   18 al 24 dic 2026 ·  7 dias · viernes a jueves · cierre
--   25 dic 2026       ·  1 dia  · VIERNES          · feriado obligatorio
--   26 al 31 dic 2026 ·  6 dias · sabado a jueves  · cierre
--   1 ene 2027        ·  1 dia  · VIERNES          · feriado obligatorio
--   2 al 11 ene 2027  · 10 dias · sabado a lunes   · cierre
--                      ─────────
--                        25 dias, los mismos que el cierre entero
-- Los lunes que se usan para probar los tramos de cierro son el 21-dic, el 28-dic
-- y el 4-ene: lunes a proposito, para que un «no paga doble» no venga de que el
-- dia caiga fin de semana.
-- Netos ficticios: 1200 para la persona de diciembre (divisor 12 → dia 100) y
-- 1100 para la de enero (divisor 11 → dia 100). No se parecen a ningun sueldo.
-- ════════════════════════════════════════════════════════════════════════

create table zz_res (
  n int, escenario text, esperado text, obtenido text, veredicto text
);
grant select, insert, update on zz_res to public;
-- Igual que en el ensayo de la formula: en esta base hay un disparador
-- (`ensure_rls`) que le prende la seguridad por filas a toda tabla nueva, y sin
-- politica permisiva de insercion nadie inserta. Es un papel borrador.
alter table zz_res disable row level security;

create or replace function zz_n(p numeric) returns text
language sql immutable as $zz$
  select regexp_replace(regexp_replace(round(p, 10)::text, '(\.\d*?)0+$', '\1'), '\.$', '')
$zz$;


-- ── LAS PERSONAS FICTICIAS ──────────────────────────────────────────────
insert into acceso_usuario (email, nombre, perfil, activo, nota, creado_por) values
  ('zz-socia@example.invalid', 'ZZ Socia', 'socias', true, 'ensayo-cierre', 'ensayo')
on conflict do nothing;

with p as (
  insert into rrhh_persona (nombre, email, puesto, ingreso, creado_por) values
    ('ZZ Dic', 'zz-dic@example.invalid', 'ensayo', '2026-01-05', 'ensayo-cierre'),
    ('ZZ Ene', 'zz-ene@example.invalid', 'ensayo', '2026-01-05', 'ensayo-cierre')
  returning id, nombre)
select set_config('cc.' || case when nombre = 'ZZ Dic' then 'dic' else 'ene' end,
                  id::text, true) from p;

insert into rrhh_neto_quincena (persona_id, neto, vigente_desde, nota, creado_por) values
  (current_setting('cc.dic',true)::bigint, 1200, '2026-10-01', 'FICTICIO', 'ensayo-cierre'),
  (current_setting('cc.ene',true)::bigint, 1100, '2026-10-01', 'FICTICIO', 'ensayo-cierre');

-- Una ausencia en cada uno de los dos feriados obligatorios.
insert into rrhh_permiso (persona_id, fecha_inicio, fecha_fin, motivo, estado,
                          resuelto_por, resuelto_en, modalidad_descuento, creado_por) values
  (current_setting('cc.dic',true)::bigint, '2026-12-25','2026-12-25','zz',
   'aprobado','zz-socia@example.invalid',now(),'descuento','ensayo-cierre'),
  (current_setting('cc.ene',true)::bigint, '2027-01-01','2027-01-01','zz',
   'aprobado','zz-socia@example.invalid',now(),'descuento','ensayo-cierre');


-- ⚠️ LA SESION, ANTES DE MEDIR NADA. `v_rrhh_pago` lleva `where
-- acceso_es_socia()` adentro, y esa funcion mira el CORREO DEL JWT, no el rol de
-- Postgres. Sin estas dos lineas las filas 7, 8 y 10 saldrian «SIN DATO» — o
-- peor, si alguien las escribiera con un count() darian 0 y pasarian en verde sin
-- haber probado nada.
--
-- No se cambia de rol a `authenticated` a proposito: este ensayo prueba el
-- CALENDARIO, no los permisos. De los permisos se ocupa el ensayo de la formula,
-- que si impersona al equipo y a anon.
select set_config('request.jwt.claims',
  json_build_object('email','zz-socia@example.invalid','role','authenticated')::text, true);
do $$
begin
  if not coalesce(acceso_es_socia(), false) then
    raise exception 'ENSAYO ABORTADO: la socia ficticia no quedo reconocida por '
      'acceso_es_socia(). Sin eso v_rrhh_pago devuelve CERO filas y las pruebas del '
      'descuento no probarian nada.';
  end if;
end $$;


-- ── LAS PRUEBAS ─────────────────────────────────────────────────────────

-- 1 · EL CALENDARIO NO CAMBIO NI UN DIA. La prueba que importa de verdad: se
--     comparan los CONJUNTOS DE DIAS, no los rangos. Dos rangos distintos pueden
--     cubrir los mismos dias, asi que contar filas no probaria nada.
insert into zz_res
select 1, 'el calendario no cambio · dias que faltan · dias que sobran · total cerrados',
       '0 · 0 · 25',
       (select count(*) from (select dia from zz_cerrados_antes
          except select (f.fecha + g.i)::date from rrhh_feriado f
           cross join lateral generate_series(0,(coalesce(f.fecha_fin,f.fecha)-f.fecha)) g(i)) a)
       || ' · ' ||
       (select count(*) from (select (f.fecha + g.i)::date from rrhh_feriado f
           cross join lateral generate_series(0,(coalesce(f.fecha_fin,f.fecha)-f.fecha)) g(i)
          except select dia from zz_cerrados_antes) b)
       || ' · ' ||
       (select count(*) from (select (f.fecha + g.i)::date as dia from rrhh_feriado f
           cross join lateral generate_series(0,(coalesce(f.fecha_fin,f.fecha)-f.fecha)) g(i)) c
         where dia between date '2026-12-18' and date '2027-01-11'), null;

-- 2 · LOS CINCO TRAMOS, con sus bordes y sus dias. Si un borde se corre, el total
--     de la fila 1 puede seguir dando 25 y el calendario estar mal partido.
insert into zz_res
select 2, 'los cinco tramos · desde-hasta · dias',
       '18-12/24-12:7 · 25-12/25-12:1 · 26-12/31-12:6 · 01-01/01-01:1 · 02-01/11-01:10',
       string_agg(to_char(f.fecha,'DD-MM') || '/' || to_char(coalesce(f.fecha_fin,f.fecha),'DD-MM')
                  || ':' || ((coalesce(f.fecha_fin,f.fecha) - f.fecha) + 1),
                  ' · ' order by f.fecha), null
  from rrhh_feriado f
 where f.fecha between date '2026-12-18' and date '2027-01-11';

-- 3 · Y EL TIPO Y LA BANDERA DE CADA TRAMO, en orden.
insert into zz_res
select 3, 'tipo y pago_obligatorio de los cinco tramos, en orden',
       'cierre/f · feriado/t · cierre/f · feriado/t · cierre/f',
       string_agg(f.tipo || '/' || left(f.pago_obligatorio::text,1), ' · ' order by f.fecha), null
  from rrhh_feriado f
 where f.fecha between date '2026-12-18' and date '2027-01-11';

-- 4 · EL PAGO DOBLE: si en los dos feriados, no en los tres tramos de cierre.
--     Los tres de cierre se preguntan en un LUNES (21-dic, 28-dic, 4-ene) para
--     que el «no» no venga de que el dia caiga sabado o domingo.
insert into zz_res
select 4, 'paga doble? · 25-dic · 1-ene · lun 21-dic · lun 28-dic · lun 4-ene',
       't · t · f · f · f',
       concat_ws(' · ', left(rrhh_feriado_paga_doble('2026-12-25')::text,1),
                        left(rrhh_feriado_paga_doble('2027-01-01')::text,1),
                        left(rrhh_feriado_paga_doble('2026-12-21')::text,1),
                        left(rrhh_feriado_paga_doble('2026-12-28')::text,1),
                        left(rrhh_feriado_paga_doble('2027-01-04')::text,1)), null;

-- 5 · EL DESCUENTO: ninguno de los cinco tramos descuenta. Los dos feriados
--     porque son de pago obligatorio; los cierres porque siguen como estaban.
insert into zz_res
select 5, 'descuenta? · 25-dic · 1-ene · lun 21-dic · lun 28-dic · lun 4-ene',
       'f · f · f · f · f',
       concat_ws(' · ', left(rrhh_es_dia_descontable('2026-12-25')::text,1),
                        left(rrhh_es_dia_descontable('2027-01-01')::text,1),
                        left(rrhh_es_dia_descontable('2026-12-21')::text,1),
                        left(rrhh_es_dia_descontable('2026-12-28')::text,1),
                        left(rrhh_es_dia_descontable('2027-01-04')::text,1)), null;

-- 6 · EL DIVISOR NO SE MOVIO. Partir el cierre no puede cambiar lo que se paga en
--     una quincena limpia: el divisor son todos los lunes a viernes, y los
--     feriados —de cualquier tipo— ya estaban adentro.
insert into zz_res
select 6, 'divisor · 16-31 dic · 1-15 ene 2027',
       '12 · 11',
       rrhh_dias_divisor('2026-12-16','2026-12-31') || ' · ' ||
       rrhh_dias_divisor('2027-01-01','2027-01-15'), null;

-- 7 · UNA AUSENCIA EL 25-DIC DESCUENTA CERO. Neto 1200, divisor 12, dia 100: si
--     descontara, el final seria 1100.
insert into zz_res
select 7, 'ausencia el 25-dic · neto 1200 · final · descuento',
       '1200 · 0',
       zz_n(v.final) || ' · ' || zz_n(v.descuentos), null
  from v_rrhh_pago v
 where v.persona_id = current_setting('cc.dic',true)::bigint and v.quincena = '2026-12-Q2';

-- 8 · Y UNA AUSENCIA EL 1-ENE TAMPOCO. Neto 1100, divisor 11, dia 100.
insert into zz_res
select 8, 'ausencia el 1-ene-2027 · neto 1100 · final · descuento',
       '1100 · 0',
       zz_n(v.final) || ' · ' || zz_n(v.descuentos), null
  from v_rrhh_pago v
 where v.persona_id = current_setting('cc.ene',true)::bigint and v.quincena = '2027-01-Q1';

-- 9 · Y AHORA SI SE PUEDE CARGAR UN FERIADO TRABAJADO EN ESOS DOS DIAS. Antes de
--     este pegado el trigger los rechazaba: el 25-dic no existia como feriado y el
--     1-ene tampoco, asi que `rrhh_feriado_paga_doble` daba false en los dos.
do $$
declare v_res text := '';
begin
  begin
    insert into rrhh_feriado_trabajado (persona_id, fecha, nota, creado_por)
    values (current_setting('cc.dic',true)::bigint, '2026-12-25', 'zz', 'ensayo-cierre');
    v_res := v_res || 'aceptado';
  exception when others then v_res := v_res || 'RECHAZADO ' || sqlstate; end;
  begin
    insert into rrhh_feriado_trabajado (persona_id, fecha, nota, creado_por)
    values (current_setting('cc.ene',true)::bigint, '2027-01-01', 'zz', 'ensayo-cierre');
    v_res := v_res || ' · aceptado';
  exception when others then v_res := v_res || ' · RECHAZADO ' || sqlstate; end;
  -- Y un lunes de cierre tiene que seguir rechazandose: no es feriado.
  begin
    insert into rrhh_feriado_trabajado (persona_id, fecha, nota, creado_por)
    values (current_setting('cc.dic',true)::bigint, '2026-12-28', 'zz', 'ensayo-cierre');
    v_res := v_res || ' · ACEPTADO';
  exception when check_violation then v_res := v_res || ' · rechazado 23514';
           when others then v_res := v_res || ' · error ' || sqlstate; end;
  insert into zz_res values (9,
    'cargar feriado trabajado · 25-dic · 1-ene · un lunes de cierre',
    'aceptado · aceptado · rechazado 23514',
    -- Sin `replace` encima: el texto se arma ya limpio. La version anterior
    -- recortaba dos prefijos de tres y la fila fallaba por el que sobraba —
    -- limpiar a posteriori lo que se puede no escribir es como se cuelan esos.
    v_res, null);
end $$;

-- 10 · Y EL ADICIONAL SE PAGA. Neto 1200, divisor 12, dia completo = +100.
--      El permiso del 25-dic descuenta 0 y el feriado trabajado suma 100.
insert into zz_res
select 10, 'el 25-dic trabajado suma un dia · final · suma · cuantos',
       '1300 · 100 · 1',
       zz_n(v.final) || ' · ' || zz_n(v.feriados_trab) || ' · ' || v.feriados_trab_n, null
  from v_rrhh_pago v
 where v.persona_id = current_setting('cc.dic',true)::bigint and v.quincena = '2026-12-Q2';

-- 11 · NADA FUERA DEL CIERRE CAMBIO. Las tres filas de feriado que estaban antes
--      siguen igual, con su pago_obligatorio en false, y ningun dia de octubre o
--      noviembre se volvio cerrado.
insert into zz_res
select 11, 'fuera del cierre · filas de 2026 antes de dic · obligatorias · dias cerrados en oct y nov',
       '3 · 0 · 0',
       (select count(*) from rrhh_feriado where fecha < date '2026-12-18')
       || ' · ' ||
       (select count(*) from rrhh_feriado where fecha < date '2026-12-18' and pago_obligatorio)
       || ' · ' ||
       (select count(*) from (select (f.fecha + g.i)::date as dia from rrhh_feriado f
           cross join lateral generate_series(0,(coalesce(f.fecha_fin,f.fecha)-f.fecha)) g(i)) c
         where dia between date '2026-10-01' and date '2026-11-30'), null;

-- 12 · Y EL TRAMO 1 SIGUE SIENDO LA MISMA FILA. El mecanismo encoge la fila
--      original en vez de borrarla y reinsertarla, asi que en el calendario se
--      conserva quien cargo el cierre: `creado_por = 'semilla'`.
insert into zz_res
select 12, 'el primer tramo conserva la fila original · cargado_por · y los otros cuatro',
       'semilla · 4 de pegado-11',
       (select f.creado_por from rrhh_feriado f where f.fecha = date '2026-12-18')
       || ' · ' ||
       (select count(*) from rrhh_feriado f
         where f.fecha between date '2026-12-18' and date '2027-01-11'
           and f.creado_por = 'pegado-11') || ' de pegado-11', null;


-- ── EL VEREDICTO ────────────────────────────────────────────────────────
update zz_res set veredicto =
  case when obtenido is null                  then 'SIN DATO'
       when btrim(obtenido) = btrim(esperado) then 'OK'
       else 'FALLA' end;

insert into zz_res
select n, 'ESTA PRUEBA NO CORRIO · la consulta no devolvio ninguna fila',
       'la fila existe', 'NO EXISTE', 'FALLA'
  from generate_series(1,12) n
 where n not in (select r.n from zz_res r);

-- El veredicto primero y el total arriba, igual que en el ensayo de la formula:
-- asi se confirma con una sola foto y sin arrastrar la tabla a la derecha.
select t.veredicto as "veredicto", t.n as "#", t.escenario as "escenario",
       t.esperado as "esperado", t.obtenido as "obtenido"
  from (
    select r.veredicto, r.n, r.escenario, r.esperado,
           coalesce(r.obtenido,'(nada)') as obtenido,
           case when r.veredicto in ('FALLA','SIN DATO') then 1 else 3 end as grupo
      from zz_res r
    union all
    select (select case when count(*) < 12 then 'FALTAN PRUEBAS · NO PEGAR'
                        when count(*) filter (where veredicto <> 'OK') = 0 then 'TODO VERDE'
                        else 'HAY ROJO · NO PEGAR' end from zz_res where n between 1 and 12),
           99, '── TOTAL ──',
           (select count(*)::text || ' pruebas' from zz_res where n between 1 and 12),
           (select count(*) filter (where veredicto='OK')::text || ' OK · ' ||
                   count(*) filter (where veredicto='FALLA')::text || ' FALLA · ' ||
                   count(*) filter (where veredicto='SIN DATO')::text || ' SIN DATO'
              from zz_res where n between 1 and 12),
           0
  ) t
 order by t.grupo, t.n;
