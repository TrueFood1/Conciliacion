-- SOLO ENSAYO · PRUEBAS_CIERRE_TRAMOS.sql · termina en ROLLBACK, no deja nada
-- ════════════════════════════════════════════════════════════════════════
-- ENSAYO · el cierre de planta en cinco tramos · CON EL PEGADO 11 ADENTRO
-- GENERADO por herramientas/ensayos/armar_ensayo_cierre.py — no editar a mano:
-- se regenera y se pierde. Para cambiar las pruebas, editar
-- herramientas/ensayos/pruebas_cierre_cuerpo.sql y volver a correrlo.
--
-- ⚠️ ADENTRO VA EL CUERPO REAL DE PERSONAL_CIERRE_TRAMOS.sql, extraido del
-- archivo por estructura (sin su fila de control, que taparia la tabla de
-- veredictos). md5 del cuerpo extraido: 59ab31801b0f279d9012e34dbc556a6f
--
-- ⚠️ NECESITA EL PEGADO 10 YA APLICADO. Usa `pago_obligatorio`,
-- `rrhh_feriado_paga_doble()`, `rrhh_es_dia_descontable()` y
-- `rrhh_neto_quincena`, que los crea PERSONAL_NETO_QUINCENA.sql. Contra una base
-- sin el 10 falla en la primera linea, y esta bien que falle.
--
-- ⚠️ TERMINA EN `rollback;`. El cierre de planta vuelve a ser UNA fila del
-- 18-dic al 11-ene, como estaba. No deja ni una fila ni un objeto.
--
-- ⚠️ TOCA UNA FILA QUE YA EXISTE, y es el unico ensayo del modulo que lo hace:
-- encoge el cierre de planta sembrado por PERSONAL_CALENDARIO.sql. El rollback
-- lo devuelve, pero si la corrida se cortara a la mitad hay que verificar que el
-- cierre siga entero — la consulta esta al final del archivo.
--
-- ⚠️ LOS MONTOS SON INVENTADOS: 1200 y 1100, elegidos redondos para que el valor
-- del dia salga exacto (1200÷12 y 1100÷11 = 100). No se parecen a ningun sueldo.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── 0 · LA FOTO DE LO QUE HAY FUERA DEL CIERRE, ANTES DE TOCAR NADA ─────
-- Va ANTES del cuerpo del pegado, y por eso esta aca y no en las pruebas: una
-- vez que el pegado corrio, el «antes» ya no se puede medir.
--
-- POR QUE EXISTE. La prueba 11 comparaba contra un 3 escrito a mano, sacado de
-- la semilla del repo (31-ago, 15-sep, 1-dic). En produccion hay 10 filas: el
-- calendario llevaba un año de uso y `rrhh_feriado` es la unica tabla EDITABLE
-- del modulo — la pantalla «Dias cerrados» la cambia de verdad. Asi que la
-- prueba medía CUANTO CALENDARIO HAY, no si el pegado cambio algo: dos cosas
-- distintas, y estaba midiendo la equivocada.
-- Ahora el esperado es la foto de antes, y el obtenido la medicion de despues.
-- Sin numeros fijos: funciona con el calendario que sea.
create temporary table zz_antes_fuera on commit drop as
select (select count(*) from rrhh_feriado where fecha < date '2026-12-18')     as filas,
       (select count(*) from rrhh_feriado where fecha < date '2026-12-18'
         and pago_obligatorio)                                                 as obligatorias,
       (select count(*) from (select (f.fecha + g.i)::date as dia
          from rrhh_feriado f cross join lateral
               generate_series(0,(coalesce(f.fecha_fin,f.fecha)-f.fecha)) g(i)) c
         where dia between date '2026-10-01' and date '2026-11-30')            as dias_oct_nov,
       (select string_agg(to_char(fecha,'DD-MM-YYYY'), ' · ' order by fecha)
          from rrhh_feriado where fecha < date '2026-12-18')                   as cuales;

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  CUERPO DE PERSONAL_CIERRE_TRAMOS.sql — pegado tal cual               ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- ── 1 · LA FOTO DE ANTES ────────────────────────────────────────────────
-- Dia por dia, no por rangos: dos rangos distintos pueden cubrir los mismos dias
-- y dos iguales pueden estar en filas distintas. Lo que no puede cambiar es el
-- CONJUNTO DE DIAS, y eso es lo que se guarda.
create temporary table zz_cerrados_antes on commit drop as
select d::date as dia
  from rrhh_feriado f
  cross join lateral generate_series(0, (coalesce(f.fecha_fin, f.fecha) - f.fecha)) g(i)
  cross join lateral (select f.fecha + g.i) x(d);


-- ── 2 · EL TRAMO QUE YA EXISTE SE ENCOGE ────────────────────────────────
-- ⚠️ ESTO PRIMERO, SIEMPRE. Mientras la fila cubra del 18-dic al 11-ene, ninguno
-- de los cuatro insert de abajo entra: la exclusion por rangos los rechaza.
-- Se busca por su RANGO EXACTO y no por su descripcion ni por su id: una
-- descripcion se edita desde la pantalla y un id no se puede escribir a mano en
-- un pegado que todavia no se corrio.
do $tramo1$
declare v_n int;
begin
  update rrhh_feriado
     set fecha_fin   = date '2026-12-24',
         descripcion = 'Cierre de planta de fin de año (18 al 24 de dic)'
   where fecha = date '2026-12-18' and fecha_fin = date '2027-01-11' and tipo = 'cierre';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'ABORTADO: esperaba UNA fila de cierre del 18-dic-2026 al 11-ene-2027 y '
      'encontre %. O ya se partio, o alguien le movio las fechas desde la pantalla «Dias '
      'cerrados». Mirar que hay con: select id, fecha, fecha_fin, descripcion, tipo from '
      'rrhh_feriado order by fecha. NO SE APLICO NADA.', v_n;
  end if;
end
$tramo1$;


-- ── 3 · LOS OTROS CUATRO TRAMOS ─────────────────────────────────────────
-- Los dos feriados van con pago_obligatorio = true; los dos cierres, con el
-- default false, que es el tratamiento que ya tenian.
insert into rrhh_feriado (fecha, fecha_fin, descripcion, tipo, pago_obligatorio, creado_por) values
  (date '2026-12-25', null,               'Navidad',
   'feriado', true,  'pegado-11'),
  (date '2026-12-26', date '2026-12-31',  'Cierre de planta de fin de año (26 al 31 de dic)',
   'cierre',  false, 'pegado-11'),
  (date '2027-01-01', null,               'Año Nuevo',
   'feriado', true,  'pegado-11'),
  (date '2027-01-02', date '2027-01-11',  'Cierre de planta de fin de año (2 al 11 de ene)',
   'cierre',  false, 'pegado-11');


-- ── 4 · EL CANDADO ──────────────────────────────────────────────────────
do $candado$
declare
  v_falta int; v_sobra int; v_tramos int; v_dias int;
  v_doble_25 boolean; v_doble_1 boolean;
  v_doble_cierre int; v_desc_25 boolean; v_desc_1 boolean; v_desc_cierre int;
begin
  -- 4.1 · EL CALENDARIO NO CAMBIO NI UN DIA. Es lo unico que no se negocia.
  select count(*) into v_falta from (
    select dia from zz_cerrados_antes
    except
    select (f.fecha + g.i)::date from rrhh_feriado f
     cross join lateral generate_series(0, (coalesce(f.fecha_fin, f.fecha) - f.fecha)) g(i)) a;
  select count(*) into v_sobra from (
    select (f.fecha + g.i)::date from rrhh_feriado f
     cross join lateral generate_series(0, (coalesce(f.fecha_fin, f.fecha) - f.fecha)) g(i)
    except
    select dia from zz_cerrados_antes) b;
  if v_falta <> 0 or v_sobra <> 0 then
    raise exception 'CANDADO: el calendario cambio. Quedaron % dia(s) sin cubrir y aparecieron '
      '% dia(s) nuevos. Partir el cierre no puede agregar ni quitar un solo dia cerrado. '
      'NO SE APLICO NADA.', v_falta, v_sobra;
  end if;

  -- 4.2 · LOS CINCO TRAMOS, Y LOS 25 DIAS.
  select count(*) into v_tramos from rrhh_feriado
   where fecha between date '2026-12-18' and date '2027-01-11';
  select count(*) into v_dias from (
    select (f.fecha + g.i)::date as dia from rrhh_feriado f
     cross join lateral generate_series(0, (coalesce(f.fecha_fin, f.fecha) - f.fecha)) g(i)
     where f.fecha >= date '2026-12-18') c
   where dia between date '2026-12-18' and date '2027-01-11';
  if v_tramos <> 5 or v_dias <> 25 then
    raise exception 'CANDADO: quedaron % tramos y % dias cerrados entre el 18-dic y el 11-ene; '
      'tenian que ser 5 tramos y 25 dias. NO SE APLICO NADA.', v_tramos, v_dias;
  end if;

  -- 4.3 · LA REGLA DEL PAGO DOBLE, EN LOS DOS SENTIDOS. Los dos feriados si; los
  -- tres tramos de cierre no, y se preguntan en un LUNES de cada uno para que el
  -- «no» no venga de que el dia caiga fin de semana.
  v_doble_25 := rrhh_feriado_paga_doble(date '2026-12-25');  -- viernes, obligatorio
  v_doble_1  := rrhh_feriado_paga_doble(date '2027-01-01');  -- viernes, obligatorio
  select count(*) into v_doble_cierre
    from (values (date '2026-12-21'), (date '2026-12-28'), (date '2027-01-04')) t(d)
   where rrhh_feriado_paga_doble(t.d);                       -- los tres son lunes
  if not v_doble_25 or not v_doble_1 then
    raise exception 'CANDADO: el 25-dic-2026 o el 1-ene-2027 no califican para pago doble, y los '
      'dos son viernes y de pago obligatorio. NO SE APLICO NADA.';
  end if;
  if v_doble_cierre <> 0 then
    raise exception 'CANDADO: % de los tramos de CIERRE califican para pago doble, y ninguno '
      'tiene que calificar: son dias cerrados, no feriados. NO SE APLICO NADA.', v_doble_cierre;
  end if;

  -- 4.4 · Y EL DESCUENTO. Ni los dos feriados ni los cierres descuentan.
  v_desc_25 := rrhh_es_dia_descontable(date '2026-12-25');
  v_desc_1  := rrhh_es_dia_descontable(date '2027-01-01');
  select count(*) into v_desc_cierre
    from (values (date '2026-12-21'), (date '2026-12-28'), (date '2027-01-04')) t(d)
   where rrhh_es_dia_descontable(t.d);
  if v_desc_25 or v_desc_1 then
    raise exception 'CANDADO: el 25-dic o el 1-ene DESCUENTAN si alguien falta, y son feriados '
      'de pago obligatorio: ese dia se paga igual. NO SE APLICO NADA.';
  end if;
  if v_desc_cierre <> 0 then
    raise exception 'CANDADO: % dia(s) de los tramos de cierre pasaron a DESCONTAR. El cierre '
      'tenia que quedar como estaba. NO SE APLICO NADA.', v_desc_cierre;
  end if;

  raise notice 'CANDADO OK: el calendario no cambio ni un dia · 5 tramos · 25 dias · el 25-dic y '
    'el 1-ene pagan doble y no descuentan · los tres tramos de cierre siguen igual';
end
$candado$;


-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  FIN DEL CUERPO DEL PEGADO · desde aca, las PRUEBAS                    ║
-- ╚══════════════════════════════════════════════════════════════════════╝

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

-- 11 · NADA FUERA DEL CIERRE CAMBIO · ANTES CONTRA DESPUES, SIN NUMEROS FIJOS.
--      El esperado SALE DE LA FOTO que el prologo tomo antes de tocar la tabla, y
--      el obtenido se mide ahora. Si el pegado hubiera tocado una fila de fuera,
--      los dos textos dejarian de coincidir — con el calendario que sea.
--
--      ⚠️ La version anterior comparaba contra un '3 · 0 · 0' escrito a mano,
--      sacado de la semilla del repo. En produccion el primer numero da 10,
--      porque el calendario lleva un año de uso y esa tabla se edita desde la
--      pantalla. La prueba fallaba sin que nada estuviera mal: medía cuanto
--      calendario hay, no si el pegado cambio algo.
insert into zz_res
select 11, 'fuera del cierre, antes contra despues · filas · obligatorias · dias en oct y nov',
       (select filas || ' · ' || obligatorias || ' · ' || dias_oct_nov from zz_antes_fuera),
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


-- 13 · INFO · QUE HAY CARGADO FUERA DEL CIERRE. No es una prueba y no puede
--      fallar: esta para VER el calendario real, que es lo que la version
--      anterior de la 11 daba por sabido. Las fechas no son dato sensible —
--      «los dias cerrados no son de nadie», dice el pegado 4.
insert into zz_res values (13,
  'INFO · dias cerrados cargados ANTES del 18-dic · cuantos · obligatorios · en oct-nov · cuales',
  '(lo que diga, no es una falla)',
  (select filas || ' filas · ' || obligatorias || ' obligatoria(s) · ' || dias_oct_nov
          || ' dia(s) en oct-nov · ' || coalesce(cuales,'(ninguna)')
     from zz_antes_fuera),
  'INFO');


-- ── EL VEREDICTO ────────────────────────────────────────────────────────
-- La fila 13 queda fuera: ya trae su veredicto y no se compara contra nada.
update zz_res set veredicto =
  case when obtenido is null                  then 'SIN DATO'
       when btrim(obtenido) = btrim(esperado) then 'OK'
       else 'FALLA' end
 where n between 1 and 12;

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
           case when r.veredicto in ('FALLA','SIN DATO') then 1
                when r.veredicto = 'INFO'                then 2
                else 3 end                                              as grupo
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

rollback;

-- ── DESPUES DEL ROLLBACK ────────────────────────────────────────────────
-- El cierre tiene que haber vuelto a ser UNA sola fila, y no tiene que quedar
-- nada del ensayo:
--   select (select count(*) from rrhh_feriado
--            where fecha between date '2026-12-18' and date '2027-01-11') as tramos,
--          (select count(*) from rrhh_feriado where creado_por = 'pegado-11')  as del_pegado,
--          (select count(*) from rrhh_persona where creado_por = 'ensayo-cierre') as personas,
--          (select count(*) from rrhh_permiso where creado_por = 'ensayo-cierre') as permisos,
--          (select count(*) from information_schema.tables where table_schema='public'
--            and table_name = 'zz_res')                                      as sobras;
--   -- ESPERADO: 1 · 0 · 0 · 0 · 0
--
-- ⚠️ Si `tramos` no da 1, el rollback NO corrio y el cierre quedo partido en la
-- base de verdad. En ese caso NO pegar nada mas y avisar.
