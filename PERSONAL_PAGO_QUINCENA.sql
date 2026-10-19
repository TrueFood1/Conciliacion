-- ════════════════════════════════════════════════════════════════════════
-- MÓDULO PERSONAL · PAGO DE QUINCENA   (PEGADO 5)
-- Preparado el 3-oct-2026. NO SE CORRIO.
-- Va DESPUÉS de ACCESOS_ESQUEMA.sql (1), PERSONAL_ESQUEMA.sql (2) y
-- PERSONAL_CALENDARIO.sql (4): usa acceso_es_socia(), rrhh_param(),
-- rrhh_quincena(), rrhh_persona, rrhh_salario, rrhh_permiso y rrhh_feriado.
--
-- QUÉ AGREGA
--   · rrhh_permiso.modalidad_descuento — 'descuento' / 'reposicion', nullable.
--   · rrhh_permiso.horas              — nullable. Null = día(s) completo(s).
--   · rrhh_ajuste_manual              — append-only, solo socias.
--   · v_rrhh_permiso_dia              — el permiso abierto día por día.
--   · v_rrhh_pago_detalle             — un renglón por concepto. EL DESGLOSE.
--   · v_rrhh_pago                     — un renglón por persona y quincena.
--
-- ⚠️ SENSIBILIDAD. Las tres vistas nuevas CONTIENEN SALARIO, que hasta hoy no
-- salía de `rrhh_salario` más que por `v_rrhh_evento`. Las tres van
-- `security_invoker = true` + `where acceso_es_socia()` + `revoke all from
-- anon`, y las tres caen bajo el prefijo `v_rrhh_` que esquema_check.py trata
-- como sensible: ahí el resultado correcto es `permission denied`, y una lista
-- vacía es una FUGA. Ver la sección 6.
--
-- ⚠️ EL MOTIVO DEL PERMISO NO ENTRA AL DESGLOSE, a propósito. Las socias ya lo
-- ven en la bandeja (`v_rrhh_permiso`), así que no es un dato que se les esté
-- ocultando — es que para decidir una transferencia no hace falta, y el motivo
-- es texto libre donde alguien va a escribir algo médico (misma razón que el
-- encabezado del pegado 4). En el desglose un permiso se identifica por su
-- fecha y su duración.
--
-- ════════════════════════════════════════════════════════════════════════
-- LA DECISIÓN DE DISEÑO QUE HAY QUE LEER ANTES DE TOCAR ESTO
-- ════════════════════════════════════════════════════════════════════════
-- EL MÓDULO YA TENÍA UN APARATO DE DESCUENTO, Y NO ES EL QUE SE USA.
-- `rrhh_evento` tiene los tipos `permiso_sin_goce` (descuenta) y
-- `permiso_reponer` (va al banco de horas), y `v_rrhh_ajuste_detalle` ya los
-- calcula. Medido el 3-oct-2026 con `grep` sobre index.html: **ninguna pantalla
-- escribe `tipo_final`, `destino_final` ni `rrhh_evento_aprob`**, y nada
-- consulta `v_rrhh_ajuste`. O sea que ese aparato está escrito y no se usa, y
-- el único camino vivo de permisos es `rrhh_permiso`, que por diseño del pegado
-- 4 no movía plata.
--
-- DECISIÓN (Andrea, 3-oct-2026): la modalidad vive en `rrhh_permiso`, que es el
-- camino vivo. CONSECUENCIA QUE HAY QUE ASUMIR Y QUE QUEDA ESCRITA ACÁ PARA QUE
-- NADIE LA "ARREGLE": la rama `permiso_sin_goce` de `v_rrhh_ajuste_detalle`
-- queda MUERTA A PROPÓSITO. Si algún día alguien le construye pantalla sin leer
-- esto, el mismo permiso se va a descontar dos veces — una por `rrhh_permiso` y
-- otra por `rrhh_evento`. No hay nada en la base que lo impida: son dos tablas
-- y el descuento no es una fila que se pueda hacer única.
--
-- LA TARIFA ES UNA SOLA, Y NO ES LA QUE DECÍA EL PEDIDO.
-- El pedido original pedía `tarifa_día = (salario ÷ 2) ÷ días hábiles de la
-- quincena`. Eso convive mal con lo que ya existe: `rrhh_param` fija
-- `dias_mes_tarifa = 30` y `jornada_horas = 8`, y `v_rrhh_evento` ya calcula
-- `tarifa_hora = salario ÷ 30 ÷ 8` para incapacidades y extras. Las dos
-- fórmulas dan números distintos para la MISMA ausencia: con un salario de ₡X,
-- X/240 por hora contra X/176 en una quincena de 11 días hábiles — un 36% más
-- alto. Dos tarifas para el mismo hecho es la pantalla de transferir diciendo
-- un número y el ajuste de la contadora diciendo otro.
-- DECISIÓN (Andrea, 3-oct-2026): se unifica en la que ya existe.
--     tarifa_dia  = salario_mensual ÷ rrhh_param('dias_mes_tarifa')   → ÷ 30
--     tarifa_hora = tarifa_dia      ÷ rrhh_param('jornada_horas')     → ÷ 8
-- Cambiar la política es insertar una fila en `rrhh_param`, no reescribir esto.
--
-- ENTONCES PARA QUÉ SIGUEN SIRVIENDO LOS FERIADOS. No para la tarifa: para
-- decidir QUÉ DÍAS del permiso se descuentan. Un permiso que cruza un sábado,
-- un domingo o un feriado no descuenta esos días — nadie iba a trabajarlos. Los
-- días hábiles dejaron de ser un DIVISOR y pasaron a ser el CONTADOR, que es
-- donde el dato de `rrhh_feriado` dice algo verdadero.
--
-- POR QUÉ LA VISTA SE INDEXA POR QUINCENA Y NO POR UN RANGO LIBRE. Una vista no
-- recibe parámetros, y la alternativa —una función por rpc()— es invisible para
-- esquema_check.py, que solo mira los `from('...')` del index.html (está dicho
-- en CLAUDE.md y en el pegado 4). Además `rrhh_quincena()` ya existe y ya define
-- la quincena del módulo: Q1 = 1 al 15, Q2 = 16 al fin de mes. La pantalla
-- elige una quincena y muestra sus fechas; es el mismo "fecha inicio/fin" del
-- pedido, con el corte que el resto del módulo ya usa.
--
-- QUÉ SALARIO SE USA CUANDO SUBE A MITAD DE QUINCENA. El vigente el ÚLTIMO día
-- de la quincena, para la base y para la tarifa, y el desglose muestra de qué
-- `vigente_desde` salió. No se prorratea: un aumento con vigencia el día 20
-- paga toda la Q2 al valor nuevo. Es una simplificación CONSCIENTE y es visible
-- en pantalla, así que si algún caso real la necesita al revés, se corrige con
-- un `rrhh_ajuste_manual` — que es exactamente para lo que existe esa tabla.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── 1 · LA MODALIDAD Y LA DURACIÓN EN rrhh_permiso ──────────────────────
-- Las dos NULLABLE y sin default, y eso es lo que hace que este pegado no
-- reescriba el pasado: los permisos que ya existen —y los que no tienen
-- duración— quedan con las dos en null, que se lee como "esto no descuenta".
-- Un default 'descuento' habría convertido en descontable todo lo ya aprobado.
alter table rrhh_permiso add column if not exists modalidad_descuento text;
alter table rrhh_permiso add column if not exists horas               numeric;

alter table rrhh_permiso drop constraint if exists rrhh_permiso_modalidad_ok;
alter table rrhh_permiso add  constraint rrhh_permiso_modalidad_ok check (
  modalidad_descuento is null or modalidad_descuento in ('descuento','reposicion'));

-- `horas` SOLO EXISTE DENTRO DE UN DÍA. Un permiso de "3 horas" que además
-- abarca del lunes al jueves no se puede leer: no se sabe si son 3 horas en
-- total o 3 por día, y el descuento sale mal por un factor de 4. El CHECK lo
-- vuelve imposible en vez de dejarlo a la pantalla. El tope de 24 es cordura
-- contra un tecleo, no política — la jornada vive en `rrhh_param`, que no se
-- puede llamar desde un CHECK (es `stable`, no `immutable`).
alter table rrhh_permiso drop constraint if exists rrhh_permiso_horas_ok;
alter table rrhh_permiso add  constraint rrhh_permiso_horas_ok check (
  horas is null or (horas > 0 and horas <= 24 and fecha_fin = fecha_inicio));

comment on column rrhh_permiso.modalidad_descuento is
  'Cómo se compensa el permiso: descuento (resta del pago) o reposicion (se reponen las horas). '
  'Null = no descuenta (permiso sin duración, o aprobado antes del 3-oct-2026). '
  'Lo sugiere quien lo pide al insertar y lo confirma o lo cambia la socia AL RESOLVER: '
  'es la única actualización posible, porque rrhh_permiso_upd solo deja pasar pendiente -> final.';
comment on column rrhh_permiso.horas is
  'Duración parcial, dentro de UN día (el CHECK obliga fecha_fin = fecha_inicio). '
  'Null = día(s) completo(s), que se cuentan del rango fecha_inicio..fecha_fin. '
  'No es actualizable: no está en el grant de update por columna de la sección 6.';


-- ── 2 · AJUSTES MANUALES ────────────────────────────────────────────────
-- APPEND-ONLY, mismo criterio que el resto de rrhh y por la misma razón: de
-- acá cuelga una transferencia que ya se hizo. Para corregir se agrega otro
-- ajuste que compense, y los dos quedan a la vista en el desglose — que es el
-- registro honesto de lo que pasó, no un número editado hacia atrás.
create table if not exists rrhh_ajuste_manual (
  id          bigint generated always as identity primary key,
  persona_id  bigint  not null references rrhh_persona(id),
  fecha       date    not null,
  monto       numeric not null,
  nota        text    not null,
  creado_por  text    not null,
  creado_en   timestamptz not null default now(),

  -- UN AJUSTE DE CERO NO ES UN AJUSTE. Ocupa un renglón del desglose y no mueve
  -- el total: es ruido en la única pantalla que tiene que poder leerse entera.
  constraint rrhh_ajuste_manual_monto_ok check (monto <> 0),
  -- Y UNO SIN NOTA ES LA CAJA NEGRA QUE ESTA PANTALLA VIENE A EVITAR. Un monto
  -- suelto en la planilla sin una línea que diga por qué es justo lo que Andrea
  -- y Lorena no pueden auditar seis meses después. El mínimo de 3 es para que
  -- una "x" no pase por nota; el precedente es `nota_no_entrega` (mínimo 6).
  constraint rrhh_ajuste_manual_nota_ok check (length(btrim(nota)) >= 3)
);
create index if not exists rrhh_ajuste_manual_persona_idx
  on rrhh_ajuste_manual (persona_id, fecha);

-- RLS, Y NO ES OPCIONAL. El grant de la seccion 6 es para `authenticated`, o sea
-- para TODO el que esta logueado — Daniel y Daniela incluidos. Sin RLS, el grant
-- de select les deja leer los ajustes de todo el equipo (un adelanto es dato de
-- plata de otra persona) y el de insert les deja cargarse uno a si mismos. La
-- puerta que importa es esta, no el revoke de anon.
alter table rrhh_ajuste_manual enable row level security;

-- SOLO SOCIAS, DE LOS DOS LADOS. Misma regla que `rrhh_salario` y `rrhh_aguinaldo`
-- del pegado 2, y por la misma razon: es dato salarial, y el equipo no necesita
-- verlo para usar el modulo. Aca el empleado no ve ni lo suyo, a proposito.
drop policy if exists rrhh_ajuste_manual_sel on rrhh_ajuste_manual;
create policy rrhh_ajuste_manual_sel on rrhh_ajuste_manual for select to authenticated
  using (acceso_es_socia());
drop policy if exists rrhh_ajuste_manual_ins on rrhh_ajuste_manual;
create policy rrhh_ajuste_manual_ins on rrhh_ajuste_manual for insert to authenticated
  with check (acceso_es_socia());
-- Sin politica de update ni de delete: sin politica, la operacion no pasa aunque
-- alguien le diera el grant por error. Dos candados para el append-only.

comment on table rrhh_ajuste_manual is
  'Sumas y restas a mano sobre el pago de la quincena (adelanto, préstamo, corrección). '
  'Append-only y solo socias: no se edita ni se borra. Para corregir, otro ajuste que compense. '
  'El monto puede ser negativo. La nota es obligatoria y se muestra en el desglose.';


-- ── 3 · EL PERMISO, DÍA POR DÍA ─────────────────────────────────────────
-- Hermana de `v_rrhh_evento_dia` y por el mismo motivo: un permiso del 13 al 17
-- NO es de una quincena, son días que caen a caballo del 15. Y hace falta por
-- otra razón más: el día es la unidad donde se puede preguntar "¿era hábil?".
--
-- `habil` = lunes a viernes Y no cae en un feriado ni en un cierre de planta.
-- `isodow <= 5` es lunes-viernes (isodow: lunes = 1, domingo = 7). El rango de
-- `rrhh_feriado` es inclusivo en los dos extremos y `fecha_fin` null = un día
-- solo, igual que en `rrhh_calendario()`.
--
-- SOLO SOCIAS, aunque no tenga plata adentro. Es una pieza interna del cálculo
-- del pago y nadie más la necesita; abrirla al equipo sería superficie de más
-- sin un caso de uso que la pida.
create or replace view v_rrhh_permiso_dia with (security_invoker = true) as
--
-- ⚠️ LA SERIE ES DE ENTEROS, NO DE FECHAS, Y ESO NO ES ESTILO.
-- `generate_series(date, date, interval)` resuelve a la variante de TIMESTAMPTZ
-- (timestamptz es el tipo preferido de la categoria, asi que gana la resolucion
-- de funciones), y volver de timestamptz a `date` usa el TIMEZONE DE LA SESION:
-- con la sesion en hora CR, el 1-oct 00:00 UTC vuelve como 30-set. Todos los
-- dias corridos uno, en silencio, y el descuento cae en la quincena equivocada.
-- Es la trampa de "comparar siempre en el mismo huso" de CLAUDE.md.
-- `date - date` da integer y `date + integer` da date: cero timestamps, cero
-- husos. Es la misma forma que ya usa `v_rrhh_evento_dia` en el pegado 2.
select pm.id                                     as permiso_id,
       pm.persona_id,
       p.nombre,
       pm.modalidad_descuento,
       pm.horas,
       (pm.fecha_inicio + g.i)                   as dia,
       rrhh_quincena(pm.fecha_inicio + g.i)      as quincena,
       (extract(isodow from (pm.fecha_inicio + g.i)) <= 5
        and not exists (select 1 from rrhh_feriado f
                         where daterange(f.fecha, coalesce(f.fecha_fin, f.fecha), '[]')
                               @> (pm.fecha_inicio + g.i))) as habil
  from rrhh_permiso pm
  join rrhh_persona p on p.id = pm.persona_id
  cross join lateral generate_series(0, (pm.fecha_fin - pm.fecha_inicio)) as g(i)
 where pm.estado = 'aprobado'
   and acceso_es_socia();


-- ── 4 · EL DESGLOSE ─────────────────────────────────────────────────────
-- UN RENGLÓN POR CONCEPTO. La pantalla no recalcula nada: dibuja estos
-- renglones y los suma. Es lo que hace que "nada de caja negra" sea una
-- propiedad del dato y no una intención de la vista — si el total no cuadra con
-- lo que se ve, es que falta un renglón, y eso se nota.
--
-- EL UNIVERSO DE QUINCENAS SE GENERA, no se guarda. Va desde el mes del primer
-- salario cargado hasta el fin del mes en curso, y `rrhh_quincena()` hace el
-- corte — así Q1/Q2 no se redefinen acá. Si `rrhh_salario` está vacía,
-- generate_series no devuelve filas y la vista sale vacía, que es la respuesta
-- correcta: sin salario no hay pago que calcular.
create or replace view v_rrhh_pago_detalle with (security_invoker = true) as
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
  select date_trunc('month', least(
           (select min(vigente_desde) from rrhh_salario),
           (select min(fecha)         from rrhh_ajuste_manual),
           (select min(fecha_inicio)  from rrhh_permiso)))::date            as desde,
         (date_trunc('month', greatest(
           current_date,
           (select max(vigente_desde) from rrhh_salario),
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
-- igual en los dos lados del módulo.
sal as (
  select pq.persona_id, pq.nombre, pq.quincena, pq.ini, pq.fin,
         s.salario_mensual, s.vigente_desde,
         s.salario_mensual / rrhh_param('dias_mes_tarifa', pq.fin) as tarifa_dia,
         s.salario_mensual / rrhh_param('dias_mes_tarifa', pq.fin)
                           / rrhh_param('jornada_horas',   pq.fin) as tarifa_hora
    from persona_q pq
    left join lateral (select sa.salario_mensual, sa.vigente_desde from rrhh_salario sa
                        where sa.persona_id = pq.persona_id and sa.vigente_desde <= pq.fin
                        order by sa.vigente_desde desc, sa.creado_en desc limit 1) s on true
),
-- UN PERMISO CON DESCUENTO, RESUMIDO POR QUINCENA. El group by corta por
-- quincena, así que el permiso del 13 al 17 deja un renglón en cada una con los
-- días que le tocan a cada una.
perm as (
  select s.quincena, s.ini, s.fin, s.persona_id, s.nombre,
         s.tarifa_dia, s.tarifa_hora,
         pd.permiso_id,
         min(pd.dia)                            as dia_ini,
         max(pd.dia)                            as dia_fin,
         count(*) filter (where pd.habil)       as dias_habiles,
         max(pd.horas)                          as horas
    from sal s
    join v_rrhh_permiso_dia pd
      on pd.persona_id = s.persona_id and pd.dia between s.ini and s.fin
   -- SIN SALARIO NO HAY TARIFA, y sin tarifa el monto sale null: el renglon
   -- aparecia en el desglose valiendo cero y sin decir por que. Mejor que el
   -- permiso no deje renglon y que la persona no figure — la pantalla ya dice
   -- que hay que revisar que tenga salario en rrhh_salario.
   where pd.modalidad_descuento = 'descuento'
     and s.salario_mensual is not null
   group by s.quincena, s.ini, s.fin, s.persona_id, s.nombre,
            s.tarifa_dia, s.tarifa_hora, pd.permiso_id
)
-- LA BASE
select s.quincena, s.ini, s.fin, s.persona_id, s.nombre,
       'base'::text                          as concepto,
       null::bigint                          as ref_id,
       s.ini                                 as dia,
       1::numeric                            as cantidad,
       'quincena'::text                      as unidad,
       s.salario_mensual                     as tarifa,
       (s.salario_mensual / 2)               as monto,
       -- De qué fila de salario salió. Va a pantalla: es lo que deja ver un
       -- aumento mal fechado sin tener que abrir la base.
       ('Salario vigente desde ' || to_char(s.vigente_desde,'DD-MM-YYYY')) as nota
  from sal s
 where s.salario_mensual is not null
   and acceso_es_socia()

union all

-- LOS DESCUENTOS POR PERMISO
-- `horas` manda cuando está: el permiso es de un día y se descuenta por hora.
-- Y SE MULTIPLICA POR dias_habiles > 0, que no es un detalle: tres horas
-- pedidas un domingo no descuentan nada, porque no había nada que trabajar.
-- Sin ese factor, un permiso parcial en día cerrado restaría plata.
select p.quincena, p.ini, p.fin, p.persona_id, p.nombre,
       'descuento_permiso'::text             as concepto,
       p.permiso_id                          as ref_id,
       p.dia_ini                             as dia,
       case when p.horas is not null
            then case when p.dias_habiles > 0 then p.horas else 0 end
            else p.dias_habiles::numeric end as cantidad,
       case when p.horas is not null then 'horas' else 'dias' end as unidad,
       case when p.horas is not null then p.tarifa_hora else p.tarifa_dia end as tarifa,
       - (case when p.horas is not null
               then case when p.dias_habiles > 0 then p.horas else 0 end * p.tarifa_hora
               else p.dias_habiles * p.tarifa_dia end) as monto,
       ('Permiso ' || to_char(p.dia_ini,'DD-MM')
          || case when p.dia_fin > p.dia_ini then ' al ' || to_char(p.dia_fin,'DD-MM') else '' end)
                                             as nota
  from perm p
 where acceso_es_socia()

union all

-- LOS AJUSTES MANUALES. El monto va tal cual, con su signo, y la nota es la
-- nota de quien lo cargó — no se reescribe acá.
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
 where acceso_es_socia();


-- ── 5 · EL NÚMERO A TRANSFERIR ──────────────────────────────────────────
-- Una fila por persona y quincena, con los tres grupos separados. `final` es lo
-- que se transfiere; los otros tres están para que ese número se pueda explicar
-- sin abrir el detalle. `acceso_es_socia()` va también acá y no solo heredado:
-- es la misma lógica de cinturón y tirantes del pegado 2.
create or replace view v_rrhh_pago with (security_invoker = true) as
select quincena, persona_id, nombre,
       min(ini) as ini, max(fin) as fin,
       coalesce(sum(monto) filter (where concepto = 'base'), 0)              as base,
       coalesce(sum(monto) filter (where concepto = 'descuento_permiso'), 0) as descuentos,
       coalesce(sum(monto) filter (where concepto = 'ajuste'), 0)            as ajustes,
       coalesce(sum(monto), 0)                                               as final,
       count(*) filter (where concepto = 'descuento_permiso')                as permisos,
       count(*) filter (where concepto = 'ajuste')                           as ajustes_n
  from v_rrhh_pago_detalle
 where acceso_es_socia()
 group by quincena, persona_id, nombre;


-- ── 6 · GRANTS Y REVOKES ────────────────────────────────────────────────
-- `v_rrhh_permiso` SE REEMPLAZA para que la bandeja de aprobación pueda mostrar
-- la sugerencia del empleado. Las dos columnas van AL FINAL porque
-- `create or replace view` solo permite agregar, nunca intercalar; y el
-- index.html pide columnas por nombre, así que agregar no rompe nada.
create or replace view v_rrhh_permiso with (security_invoker = true) as
select pm.id, pm.persona_id, p.nombre, pm.fecha_inicio, pm.fecha_fin,
       (pm.fecha_fin - pm.fecha_inicio + 1) as dias,
       pm.motivo, pm.estado, pm.resolucion_nota, pm.resuelto_por, pm.resuelto_en,
       pm.creado_en, pm.creado_por,
       pm.modalidad_descuento, pm.horas
  from rrhh_permiso pm
  join rrhh_persona p on p.id = pm.persona_id;

-- LO MISMO QUE EN LOS PEGADOS 2 Y 4, Y POR LA MISMA LECCIÓN DEL 24-ago: Supabase
-- le regala `select` a `anon` sobre todo lo que nace en `public`. La anon key va
-- publicada adentro de index.html y GitHub Pages la sirve. Acá hay SALARIO.
revoke all on rrhh_ajuste_manual, v_rrhh_permiso_dia, v_rrhh_pago_detalle, v_rrhh_pago
  from anon;

grant select on rrhh_ajuste_manual, v_rrhh_permiso_dia, v_rrhh_pago_detalle, v_rrhh_pago
  to authenticated;
-- Insert y nada más: ni update ni delete. Es lo que hace que el append-only sea
-- una propiedad del sistema y no una buena intención de la pantalla.
grant insert on rrhh_ajuste_manual to authenticated;

-- UPDATE POR COLUMNA, igual que en el pegado 4. `modalidad_descuento` se suma a
-- las dos que ya estaban; `horas`, `fecha_inicio`, `fecha_fin` y `motivo` siguen
-- fuera de la lista, así que una resolución no puede mover la duración ni las
-- fechas del permiso que está resolviendo. Los grants se acumulan: repetir
-- estado y resolucion_nota es idempotente y deja la lista completa a la vista.
grant update (estado, resolucion_nota, modalidad_descuento) on rrhh_permiso
  to authenticated;


-- ── 7 · EL CANDADO ──────────────────────────────────────────────────────
-- Lo que no se puede dejar pasar es una FUGA: una vista con salario adentro que
-- `anon` pueda leer, o sin `security_invoker` (que la haría correr con los
-- permisos del dueño y esquivar la RLS — exactamente la fuga del 24-ago-2026).
-- Si algo de eso falla, la transacción entera se cae y no se aplica NADA.
do $candado$
declare
  anon_n    int;
  invoker_n int;
  rls_on    boolean;
  pol_n     int;
begin
  -- SE PREGUNTA CON has_table_privilege(), NO con information_schema.
  -- `role_table_grants` solo muestra los grants donde el otorgante o el
  -- beneficiario es un rol HABILITADO en la sesion, asi que corrido como
  -- `postgres` puede devolver cero filas para `anon` SIEMPRE — y entonces este
  -- candado pasaria sin medir nada. Un candado que no puede fallar no es un
  -- candado; es la lección de "una salvaguarda citada no es una salvaguarda
  -- verificada" aplicada al propio chequeo.
  -- has_table_privilege() contesta por el rol que se le nombra, exista o no en
  -- la sesion, y ademas ve los privilegios heredados via PUBLIC.
  select count(*) into anon_n from (
    select unnest(array['rrhh_ajuste_manual','v_rrhh_permiso_dia',
                        'v_rrhh_pago_detalle','v_rrhh_pago']) as t
  ) x
   where has_table_privilege('anon', 'public.' || x.t, 'SELECT')
      or has_table_privilege('anon', 'public.' || x.t, 'INSERT')
      or has_table_privilege('anon', 'public.' || x.t, 'UPDATE')
      or has_table_privilege('anon', 'public.' || x.t, 'DELETE');

  select count(*) into invoker_n
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname in ('v_rrhh_permiso_dia','v_rrhh_pago_detalle','v_rrhh_pago','v_rrhh_permiso')
     and c.reloptions::text like '%security_invoker=true%';

  select c.relrowsecurity into rls_on
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'rrhh_ajuste_manual';

  select count(*) into pol_n
    from pg_policies
   where schemaname = 'public' and tablename = 'rrhh_ajuste_manual';

  if not coalesce(rls_on, false) then
    raise exception 'CANDADO: rrhh_ajuste_manual quedo SIN RLS. El grant de select es para '
      '`authenticated`, o sea para todo el equipo: sin RLS, los ajustes de plata de cada '
      'persona los lee cualquiera que se loguee. NO SE APLICO NADA.';
  end if;

  if pol_n <> 2 then
    raise exception 'CANDADO: rrhh_ajuste_manual tiene % politica(s), tenian que ser 2 '
      '(select y insert, las dos solo socias). NO SE APLICO NADA.', pol_n;
  end if;

  if anon_n <> 0 then
    raise exception 'CANDADO: `anon` todavia puede leer o escribir % de las 4 tablas/vistas '
      'nuevas. Aca hay SALARIO y la anon key es PUBLICA (va dentro de index.html y '
      'GitHub Pages la sirve). NO SE APLICO NADA.', anon_n;
  end if;

  -- Y QUE `authenticated` SI PUEDA LEER, que es el error espejo: un revoke de
  -- mas deja la pantalla vacia para Andrea con un "permission denied" que se
  -- lee como que el calculo esta roto.
  if not (has_table_privilege('authenticated','public.v_rrhh_pago','SELECT')
      and has_table_privilege('authenticated','public.v_rrhh_pago_detalle','SELECT')
      and has_table_privilege('authenticated','public.rrhh_ajuste_manual','INSERT')) then
    raise exception 'CANDADO: a `authenticated` le falta algun grant — la pantalla de pago '
      'quedaria vacia para las socias. NO SE APLICO NADA.';
  end if;

  if invoker_n <> 4 then
    raise exception 'CANDADO: solo % de 4 vistas tienen security_invoker=true. '
      'Sin eso la vista corre con los permisos del dueño y esquiva la RLS. NO SE APLICO NADA.',
      invoker_n;
  end if;

  raise notice 'CANDADO OK: anon en 0 grants · 4 vistas con security_invoker · RLS activa con 2 politicas';
end
$candado$;


-- ── 8 · LA PRUEBA DE QUE LA TRANSACCIÓN LLEGÓ HASTA ACÁ ─────────────────
-- Regla 🔴 de CLAUDE.md: un "Success" del editor no es evidencia de nada. Este
-- select va ADENTRO de la transacción y justo antes del commit. Si el editor
-- muestra la fila, corrió. Si vuelve a decir "Success. No rows returned", ni
-- siquiera llegó hasta acá — y se sabe en el momento.
--
-- ESPERADO:  2 · 1 · 4 · 4 · 0 · t · 2
select
  (select count(*) from information_schema.columns
    where table_schema='public' and table_name='rrhh_permiso'
      and column_name in ('modalidad_descuento','horas'))        as cols_permiso,
  (select count(*) from information_schema.tables
    where table_schema='public' and table_name='rrhh_ajuste_manual') as tabla_ajuste,
  (select count(*) from pg_constraint
    where conname in ('rrhh_permiso_modalidad_ok','rrhh_permiso_horas_ok',
                      'rrhh_ajuste_manual_monto_ok','rrhh_ajuste_manual_nota_ok')) as checks_nuevos,
  (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public'
      and c.relname in ('v_rrhh_permiso_dia','v_rrhh_pago_detalle','v_rrhh_pago','v_rrhh_permiso')
      and c.reloptions::text like '%security_invoker=true%')     as vistas_invoker,
  (select count(*) from (select unnest(array['rrhh_ajuste_manual','v_rrhh_permiso_dia',
                                            'v_rrhh_pago_detalle','v_rrhh_pago']) as t) x
    where has_table_privilege('anon','public.'||x.t,'SELECT')
       or has_table_privilege('anon','public.'||x.t,'INSERT'))   as anon_debe_ser_0,
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='rrhh_ajuste_manual') as ajuste_con_rls,
  (select count(*) from pg_policies
    where schemaname='public' and tablename='rrhh_ajuste_manual') as ajuste_politicas;

commit;


-- ════════════════════════════════════════════════════════════════════════
-- DESPUÉS DEL COMMIT — qué verificar, y con qué
-- ════════════════════════════════════════════════════════════════════════
-- El select de la sección 8 prueba que la transacción llegó al final. Lo de
-- abajo prueba que dejó lo que tenía que dejar. Son dos preguntas distintas.
--
--   1. `python3 esquema_check.py` tiene que decir, para los tres objetos
--      nuevos que el index.html consulta:
--          ✓ cerrado rrhh_ajuste_manual
--          ✓ cerrado v_rrhh_pago_detalle
--          ✓ cerrado v_rrhh_pago
--      Y el contador de objetos tiene que SUBIR de 58 a 61. Si no sube, el
--      esquema está muerto (CLAUDE.md, punto ciego 1 de esquema_check).
--      ⚠️ `v_rrhh_permiso_dia` NO va a aparecer: ninguna pantalla lo consulta
--      directo, así que esquema_check no lo ve. Se verifica con la sonda de
--      columnas (`herramientas/sonda_columnas.py`), que pregunta por REST y
--      distingue 42501 (existe y está cerrado) de 42703 / PGRST205.
--
--   2. LA PRUEBA QUE NO SE PUEDE SALTEAR, y que ningún contador da: que el
--      descuento calculado sea el correcto. Con un salario de ejemplo ₡X:
--          tarifa_dia  = X / 30        tarifa_hora = X / 240
--      Un permiso 'descuento' de 2 días hábiles tiene que dar -2X/30, y uno de
--      3 horas -3X/240. Correrlo contra una persona real y cuadrarlo a mano
--      ANTES de transferir nada. No escribir montos reales en ningún archivo.
--
--   3. Que un permiso 'reposicion' NO reste: tiene que no dejar renglón
--      'descuento_permiso' en v_rrhh_pago_detalle.
--
--   4. Que un permiso en sábado, domingo o feriado NO reste (cantidad = 0).
--
--   5. Que `anon` no lea: la sonda de columnas sobre las cuatro nuevas tiene
--      que dar 42501 en todas.
