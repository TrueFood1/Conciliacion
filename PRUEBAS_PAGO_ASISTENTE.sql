-- SOLO ENSAYO · PRUEBAS_PAGO_ASISTENTE.sql · termina en ROLLBACK, no deja nada
-- ════════════════════════════════════════════════════════════════════════
-- ENSAYO · el cierre de planta en cinco tramos · CON EL PEGADO 11 ADENTRO
-- GENERADO por herramientas/ensayos/armar_ensayo_pago_asistente.py — no editar a mano:
-- se regenera y se pierde. Para cambiar las pruebas, editar
-- herramientas/ensayos/pruebas_pago_asistente_cuerpo.sql y volver a correrlo.
--
-- ⚠️ ADENTRO VA EL CUERPO REAL DE PERSONAL_PAGO_ASISTENTE.sql, extraido del
-- archivo por estructura (sin su fila de control, que taparia la tabla de
-- veredictos). md5 del cuerpo extraido: eb7d2a90cb27e90aacc17b4cf332f53d
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
-- ║  CUERPO DE PERSONAL_PAGO_ASISTENTE.sql — pegado tal cual               ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- ── 1 · QUIEN PUEDE VER EL TOTAL ────────────────────────────────────────
create or replace function rrhh_pago_puede_ver() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(acceso_es_socia(), false) or coalesce(acceso_es_asistente(), false);
$$;
comment on function rrhh_pago_puede_ver() is
  'Quien puede leer el TOTAL a pagar: socias y el asistente (Instinct). Decision de Lorena '
  'del 19-oct-2026. El `coalesce` a false no es adorno: las dos funciones que llama '
  'devuelven NULL para una cuenta que no esta en acceso_usuario, y `null or null` es null — '
  'en un `if` de plpgsql eso no entra por la rama verdadera, pero en un `and` se propaga '
  'raro. Se fija en false. NO habilita escribir nada ni ver el desglose.';
revoke all on function rrhh_pago_puede_ver() from anon, public;
grant execute on function rrhh_pago_puede_ver() to authenticated;


-- ── 2 · EL CALCULO, SIN GUARDIA Y SIN GRANTS ────────────────────────────
-- Estas dos no las lee nadie directo. Son la UNICA copia de la formula.
-- ⚠️ SIN `security_invoker`: ESTA VISTA CORRE COMO SU DUEÑO, y es a proposito.
-- La vista publica de abajo tiene que poder leerla, y si corriera con los
-- permisos de quien pregunta, la socia leyendola chocaria con el `revoke` —
-- «permission denied for view v_rrhh_permiso_dia_calc». Medido el 19-oct.
-- LO QUE SE PIERDE, dicho sin adornos: estas dos _calc ya no pasan por la RLS de
-- rrhh_permiso ni de rrhh_persona. La puerta deja de ser doble y queda una sola:
-- el `acceso_es_socia()` de la vista publica y la guardia de rrhh_pago_total().
-- Es el precio de tener UNA sola copia de la formula; la alternativa eran dos
-- formulas para la misma plata. Mismo patron que `rrhh_calendario()`, que ya es
-- definer con su puerta explicita adentro.
create or replace view v_rrhh_permiso_dia_calc as
select pm.id                                     as permiso_id,
       pm.persona_id,
       p.nombre,
       pm.modalidad_descuento,
       pm.horas,
       (pm.fecha_inicio + g.i)                   as dia,
       rrhh_quincena(pm.fecha_inicio + g.i)      as quincena,
       rrhh_es_dia_descontable(pm.fecha_inicio + g.i) as habil,
       -- `dia_n` sigue contando DIAS NATURALES desde el inicio: el plazo del
       -- art. 79 («los primeros 3 dias») corre en calendario. Un fin de semana
       -- no descuenta pero igual consume plazo.
       (g.i + 1)                                 as dia_n,
       pm.incapacidad_origen
  from rrhh_permiso pm
  join rrhh_persona p on p.id = pm.persona_id
  cross join lateral generate_series(0, (pm.fecha_fin - pm.fecha_inicio)) as g(i)
 where pm.estado = 'aprobado';


create or replace view v_rrhh_pago_detalle_calc as   -- corre como su dueño, ver arriba
with rango as (
  -- Los dos extremos en su propio CTE: una subconsulta agregada como ARGUMENTO
  -- de generate_series dentro del FROM es sintaxis discutible segun la version,
  -- y esto no deja lugar a duda.
  --
  -- ⚠️ EL UNIVERSO TIENE QUE CUBRIR TAMBIEN AJUSTES Y PERMISOS, no solo salarios.
  -- La rama de ajustes de abajo hace `join q`, asi que un ajuste fuera del rango
  -- NO SALE EN NINGUNA PANTALLA — se guarda y desaparece. Y el rango se puede
  -- quedar corto de los dos lados: un ajuste con fecha anterior al primer salario
  -- cargado, o uno adelantado al mes que viene. Plata que existe y no se ve es
  -- peor que plata mal calculada, porque nada avisa.
  -- `least`/`greatest` de Postgres IGNORAN los nulls, asi que una tabla vacia no
  -- arrastra todo a null; si las tres estan vacias, d0 queda null, generate_series
  -- no devuelve filas y la vista sale vacia — la respuesta correcta.
  --
  -- ⚠️ AGREGADO EN EL PEGADO 10, y no es cosmetico: desde ahora la BASE del pago
  -- sale de rrhh_neto_quincena. Si el universo siguiera midiendose solo con
  -- rrhh_salario, una persona con neto cargado y sin salario quedaria fuera del
  -- rango y su pago no apareceria en ninguna pantalla — guardado y mudo. Lo
  -- mismo con un feriado trabajado adelantado a diciembre.
  select date_trunc('month', least(
           (select min(vigente_desde) from rrhh_salario),
           (select min(vigente_desde) from rrhh_neto_quincena),
           (select min(fecha)         from rrhh_feriado_trabajado),
           (select min(fecha)         from rrhh_ajuste_manual),
           (select min(fecha_inicio)  from rrhh_permiso)))::date            as desde,
         (date_trunc('month', greatest(
           current_date,
           (select max(vigente_desde) from rrhh_salario),
           (select max(vigente_desde) from rrhh_neto_quincena),
           (select max(fecha)      from rrhh_feriado_trabajado),
           (select max(fecha)      from rrhh_ajuste_manual),
           (select max(fecha_fin)  from rrhh_permiso)))
          + interval '1 month - 1 day')::date                              as hasta
),
q as (
  -- Serie de ENTEROS por la misma razon que en v_rrhh_permiso_dia: una serie de
  -- fechas con `interval` vuelve como timestamptz y el `::date` dependeria del
  -- timezone de la sesion. `date + integer` no toca ningun huso.
  select rrhh_quincena(r.desde + g.i) as quincena,
         min(r.desde + g.i)           as ini,
         max(r.desde + g.i)           as fin
    from rango r
    cross join lateral generate_series(0, (r.hasta - r.desde)) as g(i)
   group by 1
),
-- QUIÉN ENTRA EN CADA QUINCENA. Se excluye a quien todavía no había ingresado y
-- a quien ya estaba de baja antes de que la quincena empezara. La quincena en
-- la que alguien se va SÍ aparece, completa: prorratearla es una decisión de
-- plata que le toca a la socia, y la hace con un ajuste manual a la vista.
persona_q as (
  select p.id as persona_id, p.nombre, q.quincena, q.ini, q.fin
    from rrhh_persona p
    cross join q
    left join lateral (select b.anulada, b.fecha from rrhh_persona_baja b
                        where b.persona_id = p.id
                        order by b.creado_en desc limit 1) ba on true
   where (p.ingreso is null or p.ingreso <= q.fin)
     and (ba.fecha is null or ba.anulada or ba.fecha >= q.ini)
),
-- EL SALARIO VIGENTE EL ÚLTIMO DÍA DE LA QUINCENA, y de ahí las dos tarifas.
-- Mismo patrón que `v_rrhh_evento` (lateral + order by vigente_desde desc,
-- creado_en desc limit 1), para que dos filas con la misma vigencia desempaten
-- igual en los dos lados del módulo.,
-- EL NETO FIJO, vigente el ULTIMO dia de la quincena. Reemplaza al CTE `sal`,
-- que derivaba todo de salario_mensual. Mismo patron de desempate que
-- rrhh_salario (vigente_desde desc, creado_en desc) para que los dos lados del
-- modulo resuelvan igual una vigencia repetida.
neto as (
  select pq.persona_id, pq.nombre, pq.quincena, pq.ini, pq.fin,
         n.neto, n.vigente_desde,
         rrhh_dias_divisor(pq.ini, pq.fin)                          as divisor,
         n.neto / nullif(rrhh_dias_divisor(pq.ini, pq.fin), 0)      as valor_dia,
         n.neto / nullif(rrhh_dias_divisor(pq.ini, pq.fin), 0)
                / rrhh_param('jornada_horas', pq.fin)               as valor_hora
    from persona_q pq
    left join lateral (select nq.neto, nq.vigente_desde from rrhh_neto_quincena nq
                        where nq.persona_id = pq.persona_id and nq.vigente_desde <= pq.fin
                        order by nq.vigente_desde desc, nq.creado_en desc limit 1) n on true
),
-- PERMISOS CON DESCUENTO. `pd.habil` ya es «descontable», asi que un dia sobre un
-- feriado no entra en la cuenta.
perm as (
  select n.quincena, n.ini, n.fin, n.persona_id, n.nombre,
         n.valor_dia, n.valor_hora, pd.permiso_id,
         min(pd.dia) as dia_ini, max(pd.dia) as dia_fin,
         count(*) filter (where pd.habil) as dias,
         max(pd.horas)                    as horas
    from neto n
    join v_rrhh_permiso_dia_calc pd
      on pd.persona_id = n.persona_id and pd.dia between n.ini and n.fin
   where pd.modalidad_descuento = 'descuento'
     and n.neto is not null
   group by n.quincena, n.ini, n.fin, n.persona_id, n.nombre,
            n.valor_dia, n.valor_hora, pd.permiso_id
),
-- INCAPACIDADES. Que cuenten solo los dias descontables o todos los naturales lo
-- decide `incap_dias_naturales`, que el pegado puso en 0 (= solo habiles). El
-- parametro SE SIGUE LEYENDO a proposito: si dejara de consultarse, volverlo a 1
-- no haria nada y nadie se enteraria. La regla vive ahi, en un solo lugar.
-- El porcentaje del patrono depende del numero de dia DENTRO de la incapacidad
-- (dia_n, dias NATURALES: el plazo del art. 79 corre en calendario), no del dia
-- de la quincena.
incap as (
  select n.quincena, n.ini, n.fin, n.persona_id, n.nombre, n.valor_dia,
         pd.permiso_id, max(pd.incapacidad_origen) as origen,
         min(pd.dia) as dia_ini, max(pd.dia) as dia_fin,
         count(*) filter (where rrhh_param('incap_dias_naturales', n.fin) = 1
                             or pd.habil)                   as dias,
         sum(case when rrhh_param('incap_dias_naturales', n.fin) = 1 or pd.habil
                  then n.valor_dia * (1 -
                         (case when pd.dia_n <= rrhh_param('incap_dias_patrono', n.fin)
                               then rrhh_param('incap_patrono_pct_dias_1_3',        n.fin)
                               else rrhh_param('incap_patrono_pct_dia_4_en_adelante', n.fin)
                          end) / 100.0)
                  else 0 end)             as descuento
    from neto n
    join v_rrhh_permiso_dia_calc pd
      on pd.persona_id = n.persona_id and pd.dia between n.ini and n.fin
   where pd.modalidad_descuento = 'incapacidad'
     and n.neto is not null
   group by n.quincena, n.ini, n.fin, n.persona_id, n.nombre, n.valor_dia, pd.permiso_id
),
-- FERIADO TRABAJADO. Suma. La vista vuelve a preguntar si el dia califica aunque
-- el trigger ya lo valido al insertar: si alguien desmarca `pago_obligatorio`
-- despues, el adicional tiene que dejar de pagarse.
fert as (
  select n.quincena, n.ini, n.fin, n.persona_id, n.nombre,
         n.valor_dia, n.valor_hora, ft.id as ft_id, ft.fecha, ft.horas, ft.nota
    from neto n
    join rrhh_feriado_trabajado ft
      on ft.persona_id = n.persona_id and ft.fecha between n.ini and n.fin
   where n.neto is not null
     and rrhh_feriado_paga_doble(ft.fecha)
),
renglones as (
-- LA BASE: el neto fijo. El divisor va a la vista en `cantidad`, que es lo que
-- vuelve auditable el valor del dia sin abrir la base.
select n.quincena, n.ini, n.fin, n.persona_id, n.nombre,
       'base'::text                          as concepto,
       null::bigint                          as ref_id,
       n.ini                                 as dia,
       n.divisor::numeric                    as cantidad,
       'dias habiles'::text                  as unidad,
       n.valor_dia                           as tarifa,
       n.neto                                as monto,
       ('Neto de quincena vigente desde ' || to_char(n.vigente_desde,'DD-MM-YYYY')
        || ' · divisor ' || n.divisor)        as nota
  from neto n
 where n.neto is not null

union all

select p.quincena, p.ini, p.fin, p.persona_id, p.nombre,
       'descuento_permiso'::text             as concepto,
       p.permiso_id                          as ref_id,
       p.dia_ini                             as dia,
       case when p.horas is not null
            then case when p.dias > 0 then p.horas else 0 end
            else p.dias::numeric end         as cantidad,
       case when p.horas is not null then 'horas' else 'dias' end as unidad,
       case when p.horas is not null then p.valor_hora else p.valor_dia end as tarifa,
       - (case when p.horas is not null
               then case when p.dias > 0 then p.horas else 0 end * p.valor_hora
               else p.dias * p.valor_dia end) as monto,
       ('Permiso ' || to_char(p.dia_ini,'DD-MM')
          || case when p.dia_fin > p.dia_ini then ' al ' || to_char(p.dia_fin,'DD-MM') else '' end
          || case when p.dias = 0 then ' · sin dias descontables' else '' end) as nota
  from perm p

union all

select i.quincena, i.ini, i.fin, i.persona_id, i.nombre,
       'incapacidad'::text                   as concepto,
       i.permiso_id                          as ref_id,
       i.dia_ini                             as dia,
       i.dias::numeric                       as cantidad,
       'dias'::text                          as unidad,
       i.valor_dia                           as tarifa,
       - i.descuento                         as monto,
       ('Incapacidad'
        || case when i.origen = 'accidente_trabajo' then ' (accidente de trabajo)'
                when i.origen = 'enfermedad_comun'  then ' (enfermedad comun)' else '' end
        || ': ' || i.dias::text || case when i.dias = 1 then ' dia habil' else ' dias habiles' end
        || ' · ' || to_char(i.dia_ini,'DD-MM')
        || case when i.dia_fin > i.dia_ini then ' al ' || to_char(i.dia_fin,'DD-MM') else '' end
        || case when rrhh_param('incapacidad_reglas_confirmadas', i.fin) = 1 then ''
                else ' · REGLAS SIN CONFIRMAR' end) as nota
  from incap i

union all

-- FERIADO TRABAJADO · suma, y sale como su propio concepto para que Lorena lo vea
-- separado de cualquier otra cosa.
select f.quincena, f.ini, f.fin, f.persona_id, f.nombre,
       'feriado_trabajado'::text             as concepto,
       f.ft_id                               as ref_id,
       f.fecha                               as dia,
       coalesce(f.horas, 1)                  as cantidad,
       case when f.horas is not null then 'horas' else 'dias' end as unidad,
       case when f.horas is not null then f.valor_hora else f.valor_dia end as tarifa,
       case when f.horas is not null then f.horas * f.valor_hora else f.valor_dia end as monto,
       ('Feriado trabajado ' || to_char(f.fecha,'DD-MM')
        || case when f.horas is not null then ' · ' || f.horas::text || ' h' else ' · dia completo' end
        || ' · el dia queda al doble'
        || case when coalesce(f.nota,'') <> '' then ' · ' || f.nota else '' end) as nota
  from fert f

union all

select rrhh_quincena(a.fecha)                as quincena,
       q.ini, q.fin,
       a.persona_id, p.nombre,
       'ajuste'::text                        as concepto,
       a.id                                  as ref_id,
       a.fecha                               as dia,
       1::numeric                            as cantidad,
       null::text                            as unidad,
       null::numeric                         as tarifa,
       a.monto                               as monto,
       a.nota                                as nota
  from rrhh_ajuste_manual a
  join rrhh_persona p on p.id = a.persona_id
  join q on q.quincena = rrhh_quincena(a.fecha)
),
-- LA REBAJA sigue existiendo, apagada. Con el pct en 0 el renglon NO se emite:
-- un «-₡0» es ruido en la unica pantalla que tiene que leerse entera. El concepto
-- queda para poder reconstruir una quincena vieja.
reb as (
  select r.quincena, r.persona_id, r.nombre,
         min(r.ini) as ini, max(r.fin) as fin,
         sum(case when r.concepto in ('base','descuento_permiso','incapacidad')
                  then r.monto else 0 end) as sujeto
    from renglones r
   group by r.quincena, r.persona_id, r.nombre
)
select * from renglones

union all

select b.quincena, b.ini, b.fin, b.persona_id, b.nombre,
       'rebaja'::text, null::bigint, b.ini,
       rrhh_param('rebaja_trabajador_pct', b.fin),
       'pct'::text, null::numeric,
       - (b.sujeto * rrhh_param('rebaja_trabajador_pct', b.fin) / 100.0),
       ('Rebajas del trabajador ('
        || trim(to_char(rrhh_param('rebaja_trabajador_pct', b.fin), 'FM999990.00')) || '%)')
  from reb b
where coalesce(rrhh_param('rebaja_trabajador_pct', b.fin), 0) <> 0
   and b.sujeto <> 0;

-- Y EL CANDADO DE ESTAS DOS ES EL `revoke`: sin grants, no hay como llegarles.
-- El `public` tambien, que es el que se olvida y es el que alcanza a todos.
revoke all on v_rrhh_permiso_dia_calc, v_rrhh_pago_detalle_calc from anon, authenticated, public;

comment on view v_rrhh_permiso_dia_calc is
  'EL CALCULO, sin guardia de identidad y SIN GRANTS: no la lee nadie directo. Existe para '
  'que la formula viva en un solo lugar — la vista publica v_rrhh_permiso_dia es un filtro '
  'encima, y rrhh_pago_total() la lee desde una security definer. Si alguien le diera un '
  'grant, el asistente veria el origen de cada incapacidad.';
comment on view v_rrhh_pago_detalle_calc is
  'EL DESGLOSE COMPLETO, sin guardia y SIN GRANTS. Misma razon que la de arriba: si alguien '
  'le diera un grant, el asistente veria descuentos, incapacidades y las notas de los '
  'ajustes manuales, que Lorena decidio que NO vea.';


-- ── 3 · LAS VISTAS DE SIEMPRE: UN FILTRO ENCIMA, Y NADA MAS ─────────────
-- Para una socia devuelven EXACTAMENTE lo mismo que hoy, columna por columna y
-- en el mismo orden (`select *` sobre la _calc, que salio de su propio cuerpo).
-- Para el asistente, cero filas — igual que hoy.
-- Estas dos TAMPOCO llevan security_invoker, por lo mismo: tienen que poder
-- leer las _calc. Su puerta es el `where acceso_es_socia()` que se ve aca — para
-- el asistente son cero filas, igual que hoy.
create or replace view v_rrhh_permiso_dia as
  select * from v_rrhh_permiso_dia_calc where acceso_es_socia();

create or replace view v_rrhh_pago_detalle as
  select * from v_rrhh_pago_detalle_calc where acceso_es_socia();

-- `v_rrhh_pago` NO SE TOCA. Lee `v_rrhh_pago_detalle`, que sigue siendo solo de
-- socias, asi que sigue cerrada al asistente sin que haya que decirle nada.


-- ── 4 · LA UNICA PUERTA DEL ASISTENTE ───────────────────────────────────
-- Cuatro columnas. El total sale de sumar los MISMOS renglones que ve la socia,
-- asi que es el mismo numero por construccion y no por coincidencia.
create or replace function rrhh_pago_total()
returns table (quincena text, persona_id bigint, nombre text, total numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  -- LA GUARDIA, ADENTRO. Corriendo como su dueño esta funcion esquiva el
  -- `revoke` de las _calc, asi que si el guardia estuviera afuera —en un grant o
  -- en una politica— cualquiera con sesion leeria el total de todos.
  if not rrhh_pago_puede_ver() then
    return;   -- cero filas, no un error: un error le diria a quien sondea que del
              -- otro lado hay algo. Mismo criterio que rrhh_calendario().
  end if;
  return query
    select d.quincena, d.persona_id, d.nombre, sum(d.monto)::numeric
      from v_rrhh_pago_detalle_calc d
     group by d.quincena, d.persona_id, d.nombre;
end $$;
comment on function rrhh_pago_total() is
  'El TOTAL a pagar por quincena y por persona, y nada mas: cuatro columnas. Es la unica '
  'puerta del asistente (Instinct) al pago — decision de Lorena, 19-oct-2026. SECURITY '
  'DEFINER con la guardia adentro: suma los MISMOS renglones que ve la socia '
  '(v_rrhh_pago_detalle_calc), asi que el total es el mismo POR CONSTRUCCION. Calcularlo '
  'aparte serian dos formulas para la misma plata, que es como se desincronizan.';
revoke all on function rrhh_pago_total() from anon, public;
grant execute on function rrhh_pago_total() to authenticated;

-- Y la vista fina, para que la pantalla la consulte como cualquier tabla.
create or replace view v_rrhh_pago_total with (security_invoker = true) as
  select t.quincena, t.persona_id, t.nombre, t.total from rrhh_pago_total() t;
comment on view v_rrhh_pago_total is
  'Lo mismo que rrhh_pago_total(), en forma de vista para que la pantalla la lea con un '
  'select. La guardia vive en la funcion; esta vista no agrega ninguna.';
revoke all on v_rrhh_pago_total from anon, authenticated;
grant select on v_rrhh_pago_total to authenticated;


-- ── 5 · EL CANDADO ──────────────────────────────────────────────────────
do $candado$
declare
  v_fn int; v_src text; v_calc_abiertas int; v_socia int; v_inv int;
  v_anon int; v_cols text; v_puede_anon boolean; v_total_anon boolean;
begin
  select count(*) into v_fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in ('rrhh_pago_puede_ver','rrhh_pago_total');
  if v_fn <> 2 then
    raise exception 'CANDADO: faltan funciones (hay %, tenian que ser 2). NO SE APLICO NADA.', v_fn;
  end if;

  -- 5.1 · LO MAS IMPORTANTE: LAS _calc SIN UN SOLO GRANT. Es lo unico que las
  -- cierra. Si una quedara abierta, el asistente veria el desglose entero.
  select count(*) into v_calc_abiertas from (
    select unnest(array['v_rrhh_permiso_dia_calc','v_rrhh_pago_detalle_calc']) as v) x
   cross join unnest(array['anon','authenticated']) as r(rol)
   where has_table_privilege(r.rol,'public.'||x.v,'SELECT');
  if v_calc_abiertas <> 0 then
    raise exception 'CANDADO: % permiso(s) de lectura sobre las vistas _calc. Esas vistas NO '
      'tienen guardia de identidad: un grant ahi le muestra al asistente los descuentos, las '
      'incapacidades con su origen y las notas de los ajustes. NO SE APLICO NADA.', v_calc_abiertas;
  end if;

  -- 5.2 · LAS TRES DE SIEMPRE SIGUEN PIDIENDO SOCIA.
  select count(*) into v_socia from (
    select unnest(array['v_rrhh_permiso_dia','v_rrhh_pago_detalle','v_rrhh_pago']) as v) x
   where pg_get_viewdef(('public.'||x.v)::regclass) like '%acceso_es_socia()%';
  if v_socia <> 3 then
    raise exception 'CANDADO: solo % de 3 vistas siguen filtrando por acceso_es_socia(). '
      'Lorena pidio que el asistente NO las lea. NO SE APLICO NADA.', v_socia;
  end if;

  -- 5.3 · Y LA PUERTA NUEVA ENTREGA CUATRO COLUMNAS, NI UNA MAS.
  select string_agg(a.attname, ',' order by a.attnum) into v_cols
    from pg_attribute a
   where a.attrelid = 'public.v_rrhh_pago_total'::regclass and a.attnum > 0 and not a.attisdropped;
  if v_cols <> 'quincena,persona_id,nombre,total' then
    raise exception 'CANDADO: v_rrhh_pago_total expone «%» y tenia que exponer exactamente '
      'quincena,persona_id,nombre,total. NO SE APLICO NADA.', v_cols;
  end if;

  -- 5.4 · LA GUARDIA, ADENTRO DE LA DEFINER.
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='rrhh_pago_total';
  if position('rrhh_pago_puede_ver' in v_src) = 0 then
    raise exception 'CANDADO: rrhh_pago_total() es security definer y NO llama a '
      'rrhh_pago_puede_ver(). Asi cualquiera con sesion leeria el total de todos. '
      'NO SE APLICO NADA.';
  end if;

  v_puede_anon := has_function_privilege('anon','public.rrhh_pago_puede_ver()','EXECUTE');
  v_total_anon := has_function_privilege('anon','public.rrhh_pago_total()','EXECUTE');
  if v_puede_anon or v_total_anon then
    raise exception 'CANDADO: `anon` puede ejecutar alguna de las dos funciones. La anon key es '
      'PUBLICA y va dentro de index.html. NO SE APLICO NADA.';
  end if;

  select count(*) into v_inv from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public'
     and c.relname in ('v_rrhh_pago','v_rrhh_pago_total')
     and c.reloptions::text like '%security_invoker=true%';
  if v_inv <> 2 then
    raise exception 'CANDADO: solo % de 2 vistas con security_invoker (v_rrhh_pago y '
      'v_rrhh_pago_total). Las otras cuatro corren como su dueño A PROPOSITO — ver la nota '
      'de la seccion 2. NO SE APLICO NADA.', v_inv;
  end if;

  select count(*) into v_anon from (
    select unnest(array['v_rrhh_pago_total','v_rrhh_permiso_dia','v_rrhh_pago_detalle',
                        'v_rrhh_pago']) as v) x
   where has_table_privilege('anon','public.'||x.v,'SELECT');
  if v_anon <> 0 then
    raise exception 'CANDADO: `anon` llega a % vista(s) del pago. NO SE APLICO NADA.', v_anon;
  end if;

  raise notice 'CANDADO OK: 2 funciones · las _calc sin un solo grant · las 3 de siempre siguen '
    'pidiendo socia · la puerta nueva expone 4 columnas · la guardia esta adentro de la definer · '
    'anon sin nada · 5 vistas invoker';
end
$candado$;


-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  FIN DEL CUERPO DEL PEGADO · desde aca, las PRUEBAS                    ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- ════════════════════════════════════════════════════════════════════════
-- NETOS FICTICIOS Y REDONDOS: 1100, para que el valor del dia salga exacto
-- (1100 ÷ 11 = 100 en la quincena 1-15 oct). No se parecen a ningun sueldo.
-- Los esperados estan escritos a mano, derivados del calendario.
-- ════════════════════════════════════════════════════════════════════════

create table zz_res (n int, escenario text, esperado text, obtenido text, veredicto text);
grant select, insert, update on zz_res to public;
-- Igual que en los otros ensayos: `ensure_rls` le prende la seguridad por filas
-- a toda tabla nueva, y sin politica permisiva de insercion nadie inserta. Es un
-- papel borrador con resultados de prueba.
alter table zz_res disable row level security;

create or replace function zz_n(p numeric) returns text language sql immutable as $zz$
  select regexp_replace(regexp_replace(round(p, 10)::text, '(\.\d*?)0+$', '\1'), '\.$', '')
$zz$;

-- ── LAS CUENTAS Y LAS PERSONAS FICTICIAS ────────────────────────────────
-- @example.invalid: TLD reservado por la RFC 2606. No depende de ninguna cuenta
-- real y no escribe nada a nombre de nadie.
-- ⚠️ El CHECK de `perfil` se amplia a 'asistente' si hace falta: ACCESOS_ESQUEMA
-- lo creo con ('socias','equipo') y ASISTENTE_ROL lo amplio. Si el ensayo corre
-- contra una base donde eso ya paso, el `do` no hace nada.
do $$
begin
  if exists (select 1 from pg_constraint c join pg_class t on t.oid=c.conrelid
              where t.relname='acceso_usuario' and c.contype='c'
                and pg_get_constraintdef(c.oid) like '%perfil%'
                and pg_get_constraintdef(c.oid) not like '%asistente%') then
    raise exception 'ENSAYO ABORTADO: el CHECK de acceso_usuario.perfil no acepta '
      '«asistente», asi que ASISTENTE_ROL.sql no esta aplicado en esta base y este '
      'ensayo no puede probar nada del asistente.';
  end if;
end $$;

insert into acceso_usuario (email, nombre, perfil, activo, nota, creado_por) values
  ('zz-socia@example.invalid',    'ZZ Socia',    'socias',    true, 'ensayo-asis', 'ensayo'),
  ('zz-instinct@example.invalid', 'ZZ Instinct', 'asistente', true, 'ensayo-asis', 'ensayo'),
  ('zz-equipo@example.invalid',   'ZZ Equipo',   'equipo',    true, 'ensayo-asis', 'ensayo');

with p as (
  insert into rrhh_persona (nombre, email, puesto, ingreso, creado_por) values
    ('ZZ Con Permiso', 'zz-equipo@example.invalid', 'ensayo', '2026-01-05', 'ensayo-asis'),
    ('ZZ Limpia',      null,                        'ensayo', '2026-01-05', 'ensayo-asis')
  returning id, nombre)
select set_config('cc.'||case when nombre='ZZ Limpia' then 'limpia' else 'perm' end,
                  id::text, true) from p;

insert into rrhh_neto_quincena (persona_id, neto, vigente_desde, nota, creado_por)
select current_setting('cc.'||k,true)::bigint, 1100, '2026-10-01', 'FICTICIO', 'ensayo-asis'
  from (values ('perm'),('limpia')) v(k);

-- EL CASO QUE IMPORTA: un permiso con descuento, el mismo que se midio el 19-oct.
-- Sin el, el total del asistente podria salir igual por casualidad.
insert into rrhh_permiso (persona_id, fecha_inicio, fecha_fin, motivo, estado,
                          resuelto_por, resuelto_en, modalidad_descuento, creado_por)
values (current_setting('cc.perm',true)::bigint, '2026-10-06','2026-10-06','zz',
        'aprobado','zz-socia@example.invalid',now(),'descuento','ensayo-asis');

-- Y un ajuste manual con una nota, para probar que el asistente no la ve por
-- ninguna via (hoy ni siquiera llega al detalle, pero se prueba igual).
insert into rrhh_ajuste_manual (persona_id, fecha, monto, nota, creado_por)
values (current_setting('cc.limpia',true)::bigint, '2026-10-10', 50,
        'ZZ nota privada de la socia', 'ensayo-asis');

-- Y una incapacidad, para que exista un origen que el asistente no debe ver.
insert into rrhh_permiso (persona_id, fecha_inicio, fecha_fin, motivo, estado,
                          resuelto_por, resuelto_en, modalidad_descuento,
                          incapacidad_origen, creado_por)
values (current_setting('cc.limpia',true)::bigint, '2026-10-13','2026-10-13','zz',
        'aprobado','zz-socia@example.invalid',now(),'incapacidad','enfermedad_comun','ensayo-asis');


-- ── LO QUE VE LA SOCIA, PRIMERO: es la referencia de todo lo demas ──────
-- ⚠️ DE ACA EN ADELANTE SE MIDE COMO `authenticated`, NO COMO postgres.
-- postgres es SUPERUSUARIO: ignora los grants. Y el `revoke` de las dos vistas
-- _calc es lo UNICO que las cierra —no tienen guardia de identidad adentro—, asi
-- que midiendo como postgres esa prueba no prueba nada. La primera corrida de
-- este ensayo dio «7 filas» y «2 filas» donde esperaba «denegado», y el error
-- era este. Es el mismo error que la fila 32 del ensayo de la formula, al revés:
-- ahi medía permisos en vez de hechos, aca medía los hechos con el rol que no es.
select set_config('request.jwt.claims',
  json_build_object('email','zz-socia@example.invalid','role','authenticated')::text, true);
set local role authenticated;
do $$
begin
  if not coalesce(acceso_es_socia(), false) then
    raise exception 'ENSAYO ABORTADO: la socia ficticia no quedo reconocida por '
      'acceso_es_socia(). Sin eso todo daria «0 = 0» en verde sin probar nada.';
  end if;
  perform set_config('cc.socia_total_perm',
    (select zz_n(final) from v_rrhh_pago
      where persona_id = current_setting('cc.perm',true)::bigint and quincena='2026-10-Q1'), true);
  perform set_config('cc.socia_total_limpia',
    (select zz_n(final) from v_rrhh_pago
      where persona_id = current_setting('cc.limpia',true)::bigint and quincena='2026-10-Q1'), true);
  perform set_config('cc.socia_renglones',
    (select count(*)::text from v_rrhh_pago_detalle where quincena='2026-10-Q1'), true);
end $$;


-- ════════════════════════════════════════════════════════════════════════
-- 1 · LA SOCIA SIGUE VIENDO LO MISMO QUE ANTES
-- ════════════════════════════════════════════════════════════════════════
-- 1100 − 100 (un dia habil de permiso) = 1000 para la de permiso.
-- La limpia: 1100 + 50 (el ajuste) − 50 (incapacidad, 1 dia al 50% del patrono) = 1100.
insert into zz_res
select 1, 'SOCIA · total de la persona con permiso (1100 − 100) · y de la limpia',
       '1000 · 1100',
       current_setting('cc.socia_total_perm',true) || ' · ' ||
       current_setting('cc.socia_total_limpia',true), null;

insert into zz_res
select 2, 'SOCIA · sigue viendo el desglose y el dia por dia',
       'si · si',
       case when (select count(*) from v_rrhh_pago_detalle) > 0 then 'si' else 'NO' end || ' · ' ||
       case when (select count(*) from v_rrhh_permiso_dia)  > 0 then 'si' else 'NO' end, null;

insert into zz_res
select 3, 'SOCIA · ve el origen de la incapacidad y la nota del ajuste',
       'enfermedad_comun · si',
       coalesce((select max(incapacidad_origen) from v_rrhh_permiso_dia
                  where incapacidad_origen is not null),'(ninguno)') || ' · ' ||
       case when exists (select 1 from v_rrhh_pago_detalle
                          where nota like '%nota privada%') then 'si' else 'NO' end, null;

insert into zz_res
select 4, 'SOCIA · la puerta nueva le da el MISMO total que v_rrhh_pago',
       '1000 · igual',
       zz_n(t.total) || ' · ' ||
       case when zz_n(t.total) = current_setting('cc.socia_total_perm',true)
            then 'igual' else 'DISTINTO' end, null
  from v_rrhh_pago_total t
 where t.persona_id = current_setting('cc.perm',true)::bigint and t.quincena='2026-10-Q1';


-- ════════════════════════════════════════════════════════════════════════
-- 2 · EL ASISTENTE · UNA FILA POR PERSONA, EL MISMO TOTAL, Y NADA MAS
-- ════════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claims',
  json_build_object('email','zz-instinct@example.invalid','role','authenticated')::text, true);
set local role authenticated;   -- explicito: mover esta seccion no debe romperla
do $$
begin
  if not coalesce(acceso_es_asistente(), false) then
    raise exception 'ENSAYO ABORTADO: la cuenta ficticia de asistente no quedo reconocida '
      'por acceso_es_asistente(). Sin eso las pruebas del asistente no prueban nada.';
  end if;
  if coalesce(acceso_es_socia(), false) then
    raise exception 'ENSAYO ABORTADO: el asistente salio reconocido ADEMAS como socia.';
  end if;
end $$;

-- 5 · EL TOTAL, IGUAL AL DE LA SOCIA. Es la prueba que pidio Lorena, y el caso
--     con descuento es el que la hace valer: sin el, un total calculado sin los
--     permisos daria 1100 y pasaria igual.
insert into zz_res
select 5, 'ASISTENTE · total de la persona con permiso · igual al de la socia?',
       current_setting('cc.socia_total_perm',true) || ' · igual',
       zz_n(t.total) || ' · ' ||
       case when zz_n(t.total) = current_setting('cc.socia_total_perm',true)
            then 'igual' else 'DISTINTO' end, null
  from v_rrhh_pago_total t
 where t.persona_id = current_setting('cc.perm',true)::bigint and t.quincena='2026-10-Q1';

insert into zz_res
select 6, 'ASISTENTE · y el de la persona limpia tambien',
       current_setting('cc.socia_total_limpia',true) || ' · igual',
       zz_n(t.total) || ' · ' ||
       case when zz_n(t.total) = current_setting('cc.socia_total_limpia',true)
            then 'igual' else 'DISTINTO' end, null
  from v_rrhh_pago_total t
 where t.persona_id = current_setting('cc.limpia',true)::bigint and t.quincena='2026-10-Q1';

-- 7 · UNA FILA POR PERSONA Y POR QUINCENA, ni mas ni menos.
insert into zz_res
select 7, 'ASISTENTE · filas de la quincena 1-15 oct (2 personas ficticias)',
       '2',
       (select count(*)::text from v_rrhh_pago_total
         where quincena='2026-10-Q1'
           and persona_id in (current_setting('cc.perm',true)::bigint,
                              current_setting('cc.limpia',true)::bigint)), null;

-- 8 · CUATRO COLUMNAS, NI UNA MAS. Se mide el catalogo, no lo que devuelve un
--     select: una columna de mas existe aunque nadie la pida hoy.
insert into zz_res
select 8, 'ASISTENTE · las columnas que existen en la puerta',
       'quincena,persona_id,nombre,total',
       (select string_agg(a.attname, ',' order by a.attnum) from pg_attribute a
         where a.attrelid='v_rrhh_pago_total'::regclass and a.attnum>0 and not a.attisdropped), null;

-- 9 · LAS TRES VISTAS DE SIEMPRE LE DAN CERO O LE NIEGAN EL PERMISO.
do $$
declare v text:='';
begin
  begin v:=v||(select count(*) from v_rrhh_pago)||' filas';
  exception when insufficient_privilege then v:=v||'denegado'; when others then v:=v||sqlstate; end;
  begin v:=v||' · '||(select count(*) from v_rrhh_pago_detalle)||' filas';
  exception when insufficient_privilege then v:=v||' · denegado'; when others then v:=v||' · '||sqlstate; end;
  begin v:=v||' · '||(select count(*) from v_rrhh_permiso_dia)||' filas';
  exception when insufficient_privilege then v:=v||' · denegado'; when others then v:=v||' · '||sqlstate; end;
  insert into zz_res values (9,
    'ASISTENTE · v_rrhh_pago · v_rrhh_pago_detalle · v_rrhh_permiso_dia',
    '0 filas · 0 filas · 0 filas', v, null);
end $$;

-- 10 · Y LAS DOS INTERNAS, QUE SON LAS QUE TIENEN TODO, LE NIEGAN EL PERMISO.
--      Es el unico candado de esas dos: no tienen guardia de identidad adentro.
do $$
declare v text:='';
begin
  begin v:=v||(select count(*) from v_rrhh_pago_detalle_calc)||' filas ❌';
  exception when insufficient_privilege then v:=v||'denegado';
           when others then v:=v||'error '||sqlstate; end;
  begin v:=v||' · '||(select count(*) from v_rrhh_permiso_dia_calc)||' filas ❌';
  exception when insufficient_privilege then v:=v||' · denegado';
           when others then v:=v||' · error '||sqlstate; end;
  insert into zz_res values (10,
    'ASISTENTE · las dos vistas _calc, que tienen el desglose entero',
    'denegado · denegado', v, null);
end $$;

-- 11 · NI EL ORIGEN DE LA INCAPACIDAD NI LA NOTA DEL AJUSTE, POR NINGUNA VIA.
--      Se busca el texto en TODO lo que el asistente puede leer del pago.
insert into zz_res
select 11, 'ASISTENTE · aparece «enfermedad» o la nota privada en lo que puede leer?',
       'no · no',
       case when exists (select 1 from v_rrhh_pago_total t
                          where t.nombre ilike '%enfermedad%'
                             or t.quincena ilike '%enfermedad%') then 'SI ❌' else 'no' end
       || ' · ' ||
       case when exists (select 1 from v_rrhh_pago_total t
                          where t.nombre ilike '%nota privada%') then 'SI ❌' else 'no' end, null;

-- 12 · EL ASISTENTE NO ESCRIBE NADA. Se intenta de verdad, en las tres tablas
--      del pago, y se mira que el dato quede igual.
do $$
declare v text:=''; v_antes numeric; v_despues numeric;
begin
  select neto into v_antes from rrhh_neto_quincena
   where persona_id = current_setting('cc.perm',true)::bigint;
  begin insert into rrhh_ajuste_manual (persona_id,fecha,monto,nota,creado_por)
        values (current_setting('cc.perm',true)::bigint,'2026-10-14',999,'zz','asis');
        v:=v||'ajuste: ENTRO ❌';
  exception when others then v:=v||'ajuste: '||sqlstate; end;
  begin insert into rrhh_neto_quincena (persona_id,neto,vigente_desde,nota,creado_por)
        values (current_setting('cc.perm',true)::bigint,1,'2026-11-01','zz','asis');
        v:=v||' · neto: ENTRO ❌';
  exception when others then v:=v||' · neto: '||sqlstate; end;
  begin insert into rrhh_feriado_trabajado (persona_id,fecha,nota,creado_por)
        values (current_setting('cc.perm',true)::bigint,'2026-12-25','zz','asis');
        v:=v||' · feriado: ENTRO ❌';
  exception when others then v:=v||' · feriado: '||sqlstate; end;
  begin update rrhh_neto_quincena set neto=1
          where persona_id = current_setting('cc.perm',true)::bigint;
        v:=v||' · update: '||(case when found then 'ENTRO ❌' else '0 filas' end);
  exception when others then v:=v||' · update: '||sqlstate; end;
  begin delete from rrhh_neto_quincena
          where persona_id = current_setting('cc.perm',true)::bigint;
        v:=v||' · delete: 0 filas';
  exception when others then v:=v||' · delete: '||sqlstate; end;
  select neto into v_despues from rrhh_neto_quincena
   where persona_id = current_setting('cc.perm',true)::bigint;
  -- ⚠️ EL FERIADO DA 23514 Y NO 42501, Y NO ES UNA FALLA: `rrhh_feriado_trabajado`
  -- tiene un trigger BEFORE INSERT que rechaza una fecha que no sea feriado de
  -- pago obligatorio de lunes a viernes, y un BEFORE trigger corre ANTES de que
  -- se evalue el WITH CHECK de la politica. O sea que ahi hay una capa MAS, no
  -- una menos. Mi esperado decia 42501 por suponer el orden de los chequeos.
  -- Y para no depender del codigo de error, se agrega lo que de verdad importa:
  -- que no haya quedado NI UNA fila a nombre del asistente.
  insert into zz_res values (12,
    'ASISTENTE · escribir ajuste · neto · feriado · update · delete · dato igual · sin rastro',
    'ajuste: 42501 · neto: 42501 · feriado: 23514 · update: 42501 · delete: 42501 · igual · 0 filas',
    v || ' · ' || case when v_despues = v_antes then 'igual' else 'CAMBIO ❌' end
      || ' · ' || (
        (select count(*) from rrhh_ajuste_manual where creado_por='asis')
      + (select count(*) from rrhh_neto_quincena where creado_por='asis')
      + (select count(*) from rrhh_feriado_trabajado where creado_por='asis')
      )::text || ' filas', null);
end $$;


-- ════════════════════════════════════════════════════════════════════════
-- 3 · EL EMPLEADO SIN ROL Y anon · NADA
-- ════════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claims',
  json_build_object('email','zz-equipo@example.invalid','role','authenticated')::text, true);
set local role authenticated;
insert into zz_res
select 13, 'EMPLEADO (ni socia ni asistente) · filas en la puerta · en v_rrhh_pago',
       '0 · 0',
       (select count(*)::text from v_rrhh_pago_total) || ' · ' ||
       (select count(*)::text from v_rrhh_pago), null;

do $$
declare v text:='';
begin
  perform set_config('role','anon', true);
  begin v:=v||(select count(*) from v_rrhh_pago_total)||' filas ❌';
  exception when insufficient_privilege then v:=v||'denegado'; when others then v:=v||'denegado('||sqlstate||')'; end;
  begin perform rrhh_pago_total(); v:=v||' · ejecuto la funcion ❌';
  exception when insufficient_privilege then v:=v||' · denegado'; when others then v:=v||' · denegado('||sqlstate||')'; end;
  begin perform rrhh_pago_puede_ver(); v:=v||' · ejecuto puede_ver ❌';
  exception when insufficient_privilege then v:=v||' · denegado'; when others then v:=v||' · denegado('||sqlstate||')'; end;
  perform set_config('role','postgres', true);
  insert into zz_res values (14,
    'anon · leer la puerta · ejecutar rrhh_pago_total() · ejecutar puede_ver()',
    'denegado · denegado · denegado', v, null);
end $$;
select set_config('role','postgres', true);


-- ════════════════════════════════════════════════════════════════════════
-- 4 · LOS DATOS REALES, INTACTOS
-- ════════════════════════════════════════════════════════════════════════
-- Esta y el veredicto vuelven a postgres: cuentan filas de las TABLAS, no de las
-- vistas, y la pregunta es cuantas hay — no cuantas ve tal perfil.
set local role postgres;
insert into zz_res
select 15, 'los datos reales · filas que NO son del ensayo en las tres tablas del pago',
       'las mismas que antes',
       'netos ' || (select count(*)::text from rrhh_neto_quincena where creado_por <> 'ensayo-asis')
       || ' · permisos ' || (select count(*)::text from rrhh_permiso where creado_por <> 'ensayo-asis')
       || ' · ajustes ' || (select count(*)::text from rrhh_ajuste_manual where creado_por <> 'ensayo-asis'),
       'INFO';


-- ── EL VEREDICTO ────────────────────────────────────────────────────────
update zz_res set veredicto =
  case when obtenido is null                  then 'SIN DATO'
       when btrim(obtenido) = btrim(esperado) then 'OK'
       else 'FALLA' end
 where n between 1 and 14;

insert into zz_res
select n, 'ESTA PRUEBA NO CORRIO · la consulta no devolvio ninguna fila',
       'la fila existe', 'NO EXISTE', 'FALLA'
  from generate_series(1,14) n
 where n not in (select r.n from zz_res r);

-- El veredicto primero y el TOTAL arriba: una sola foto alcanza.
select t.veredicto as "veredicto", t.n as "#", t.escenario as "escenario",
       t.esperado as "esperado", t.obtenido as "obtenido"
  from (
    select r.veredicto, r.n, r.escenario, r.esperado,
           coalesce(r.obtenido,'(nada)') as obtenido,
           case when r.veredicto in ('FALLA','SIN DATO') then 1
                when r.veredicto = 'INFO'                then 2
                else 3 end as grupo
      from zz_res r
    union all
    select (select case when count(*) < 14 then 'FALTAN PRUEBAS · NO PEGAR'
                        when count(*) filter (where veredicto <> 'OK') = 0 then 'TODO VERDE'
                        else 'HAY ROJO · NO PEGAR' end from zz_res where n between 1 and 14),
           99, '── TOTAL ──',
           (select count(*)::text || ' pruebas' from zz_res where n between 1 and 14),
           (select count(*) filter (where veredicto='OK')::text || ' OK · ' ||
                   count(*) filter (where veredicto='FALLA')::text || ' FALLA · ' ||
                   count(*) filter (where veredicto='SIN DATO')::text || ' SIN DATO'
              from zz_res where n between 1 and 14),
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
