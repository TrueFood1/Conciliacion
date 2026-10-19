-- SOLO SE PEGA DESPUES DEL ENSAYO · PERSONAL_PAGO_ASISTENTE.sql
-- ════════════════════════════════════════════════════════════════════════
-- MODULO PERSONAL · INSTINCT VE SOLO EL TOTAL A PAGAR  (PEGADO 12)
-- Preparado el 19-oct-2026. NO SE CORRIO.
-- Va DESPUES del pegado 10 (aplicado el 16-oct). Es independiente del 11.
--
-- ════════════════════════════════════════════════════════════════════════
-- QUE PIDIO LORENA, Y QUE NO
-- ════════════════════════════════════════════════════════════════════════
-- 19-oct-2026: el perfil `asistente` (Instinct) ve, por quincena y por persona,
-- SOLO EL TOTAL A PAGAR. Nada de la explicacion: ni descuentos, ni permisos, ni
-- incapacidades, ni ajustes, ni notas, ni tarifa, ni divisor, ni desglose.
--
-- Cuatro columnas y se termina: quincena · persona_id · nombre · total.
--
-- ⚠️ LAS TRES VISTAS DE SIEMPRE SIGUEN CERRADAS AL ASISTENTE, igual que hoy.
-- `v_rrhh_pago`, `v_rrhh_pago_detalle` y `v_rrhh_permiso_dia` conservan su
-- `acceso_es_socia()` y le devuelven cero filas. Este pegado NO las abre.
--
-- ════════════════════════════════════════════════════════════════════════
-- EL PROBLEMA, Y POR QUE LA SOLUCION TIENE ESTA FORMA
-- ════════════════════════════════════════════════════════════════════════
-- El total tiene que ser EXACTAMENTE el de la socia, descuentos incluidos. Y la
-- primera idea —una funcion `security definer` que lea `v_rrhh_pago`— NO SIRVE,
-- por una razon que conviene entender antes de tocar esto:
--
--     `acceso_es_socia()` mira el CORREO DEL JWT, no el rol de Postgres.
--
-- Una definer cambia el rol efectivo, no el JWT. Asi que adentro de la funcion
-- la guardia de la vista sigue evaluando al asistente y sigue dando false: cero
-- filas. Medido el 19-oct.
--
-- Y calcular el total aparte seria PEOR: dos formulas para la misma plata, que es
-- exactamente como se desincronizan. Ya paso en este modulo con el 6,49%.
--
-- LA FORMA QUE SI SIRVE: se saca la guardia de identidad del CALCULO y se la
-- deja en la PUERTA.
--
--   v_rrhh_permiso_dia_calc   · el calculo, SIN guardia y SIN grants
--   v_rrhh_pago_detalle_calc  · idem, y lee el de arriba
--        ↑ nadie las puede leer: `revoke all` de anon, authenticated y public.
--          Lo verifica el ensayo llamandolas de verdad como asistente.
--
--   v_rrhh_permiso_dia        · `select * from el_calc where acceso_es_socia()`
--   v_rrhh_pago_detalle       · idem  → para socias, IDENTICAS a hoy
--   v_rrhh_pago               · no se toca: lee el detalle filtrado
--
--   rrhh_pago_total()         · `security definer` con la guardia ADENTRO
--                               (socia o asistente), lee el _calc y proyecta
--                               CUATRO columnas. Es la unica puerta del asistente.
--   v_rrhh_pago_total         · la vista fina para que la pantalla la consulte.
--
-- Una definer puede leer una vista sin grants porque adentro el usuario efectivo
-- es el dueño; quien la llama, no. Eso se midio antes de escribir esto: el
-- asistente leyendo la interna directo da `insufficient_privilege`, y por la
-- funcion recibe su fila. UNA formula, UNA puerta, CUATRO columnas.
--
-- ⚠️ EL CUERPO DE LAS DOS VISTAS _calc SALE DEL PEGADO 10 POR EXTRACCION, no
-- retecleado. Lo unico que se le quito son las 7 guardias de identidad (1 en
-- permiso_dia y 6 en el detalle), contadas antes y despues: si el pegado 10
-- cambiara y apareciera una octava, la generacion aborta en vez de dejarla.
-- ════════════════════════════════════════════════════════════════════════

begin;

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


-- ── 6 · LA FILA DE CONTROL ──────────────────────────────────────────────
-- Regla 🔴 de CLAUDE.md: un "Success" del editor no es evidencia de nada.
-- ESPERADO:  2 · 0 · 3 · quincena,persona_id,nombre,total · t · f · f · 2 · 0
select
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('rrhh_pago_puede_ver','rrhh_pago_total'))
                                                                             as funciones_2,
  (select count(*) from (select unnest(array['v_rrhh_permiso_dia_calc',
      'v_rrhh_pago_detalle_calc']) as v) x
    cross join unnest(array['anon','authenticated']) as r(rol)
    where has_table_privilege(r.rol,'public.'||x.v,'SELECT'))                as calc_abiertas_0,
  (select count(*) from (select unnest(array['v_rrhh_permiso_dia','v_rrhh_pago_detalle',
      'v_rrhh_pago']) as v) x
    where pg_get_viewdef(('public.'||x.v)::regclass) like '%acceso_es_socia()%')
                                                                             as siguen_solo_socia_3,
  (select string_agg(a.attname, ',' order by a.attnum) from pg_attribute a
    where a.attrelid='public.v_rrhh_pago_total'::regclass and a.attnum>0 and not a.attisdropped)
                                                                             as columnas_de_la_puerta,
  (select position('rrhh_pago_puede_ver' in p.prosrc) > 0 from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='rrhh_pago_total')                 as guardia_adentro_t,
  has_function_privilege('anon','public.rrhh_pago_total()','EXECUTE')         as anon_total_f,
  has_function_privilege('anon','public.rrhh_pago_puede_ver()','EXECUTE')     as anon_puede_f,
  (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname in ('v_rrhh_pago','v_rrhh_pago_total')
      and c.reloptions::text like '%security_invoker=true%')                 as invoker_2,
  (select count(*) from (select unnest(array['v_rrhh_pago_total','v_rrhh_permiso_dia',
      'v_rrhh_pago_detalle','v_rrhh_pago']) as v) x
    where has_table_privilege('anon','public.'||x.v,'SELECT'))               as anon_0;

commit;


-- ════════════════════════════════════════════════════════════════════════
-- DESPUES DEL COMMIT
-- ════════════════════════════════════════════════════════════════════════
--   1. PRUEBAS_PAGO_ASISTENTE.sql — el ensayo, con ESTE cuerpo adentro y rollback.
--   2. esquema_check.py y sonda_columnas.py --nuevas.
--   3. Y lo que ningun script da: que Instinct abra la pestaña de Pago y vea UNA
--      LISTA de persona y total, con los mismos numeros que Lorena, y nada mas.
