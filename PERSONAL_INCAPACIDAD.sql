-- ════════════════════════════════════════════════════════════════════════
-- MÓDULO PERSONAL · INCAPACIDADES   (PEGADO 6)
-- Preparado el 3-oct-2026. NO SE CORRIO.
-- Va DESPUES de PERSONAL_PAGO_QUINCENA.sql (pegado 5), que YA ESTA APLICADO y
-- NO SE TOCA. Todo lo de aca es alter/replace sobre lo que ese dejo.
--
-- QUE AGREGA
--   · rrhh_permiso.modalidad_descuento acepta un tercer valor: 'incapacidad'.
--   · rrhh_permiso.incapacidad_origen  — 'enfermedad_comun' / 'accidente_trabajo'.
--   · rrhh_permiso.incapacidad_boleta  — numero de boleta, opcional.
--   · 6 parametros nuevos en rrhh_param, incluido el indicador de que las
--     reglas TODAVIA NO ESTAN CONFIRMADAS.
--   · v_rrhh_permiso_dia  — se le agregan `dia_n` y `incapacidad_origen`.
--   · v_rrhh_pago_detalle — cuarta rama: concepto 'incapacidad'.
--   · v_rrhh_pago         — dos columnas al final: `incapacidades`, `incap_n`.
--
-- ════════════════════════════════════════════════════════════════════════
-- ⚠️⚠️ LAS REGLAS DE PAGO NO ESTAN CONFIRMADAS. ESO MANDA SOBRE TODO LO DEMAS.
-- ════════════════════════════════════════════════════════════════════════
-- Las preguntas estan en PREGUNTAS_contadora_incapacidades.md y todavia no las
-- contesto nadie. Consecuencia de diseño, y es el motivo de la mitad de este
-- archivo: NI UN PORCENTAJE NI UN PLAZO esta escrito dentro de una formula.
-- Los cuatro numeros de la regla salen de `rrhh_param`, con vigencia, asi que
-- corregir la regla es insertar una fila — no reescribir una vista, no publicar
-- de nuevo, y sin reescribir el pasado.
--
-- Y hay un parametro que no es una regla sino un SEMAFORO:
--     incapacidad_reglas_confirmadas = 0
-- Mientras valga 0, la nota de cada renglon termina en «REGLAS SIN CONFIRMAR» y
-- la pantalla pinta un aviso arriba. El numero se calcula y se VE —esconderlo
-- seria peor, porque entonces nadie revisa nada— pero no se puede transferir
-- contra el sin haberlo cuadrado a mano. Se apaga poniendolo en 1, y eso es una
-- decision de Andrea despues de hablar con la contadora, no un detalle tecnico.
--
-- ⚠️ CUIDADO CON LAS UNIDADES, que es como esto se rompe en seis meses.
-- Los parametros VIEJOS de incapacidad —`ccss_dias_empresa` = 3 y
-- `ccss_pct_empresa` = 0,5— siguen existiendo y alimentan
-- `v_rrhh_ajuste_detalle`, que NO TIENE PANTALLA (medido con grep el 3-oct:
-- nada escribe incap_ins/incap_ccss y nada consulta v_rrhh_ajuste). Los NUEVOS
-- guardan PORCENTAJE (50), no fraccion (0,5). Dos parametros que dicen lo mismo
-- en unidades distintas es como alguien divide por 100 dos veces, o ninguna.
-- Por eso el candado de la seccion 5 RECHAZA un pct nuevo que venga <= 1: si
-- alguien "corrige" 50 a 0,5, la transaccion se cae en vez de pagar de menos.
--
-- ⚠️ Y LA RAMA `permiso_sin_goce` SIGUE MUERTA A PROPOSITO. Lo dijo el pegado 5
-- y vale igual ahora que hay un tercer modo: el descuento de un permiso vive en
-- `rrhh_permiso`, no en `rrhh_evento`. Si alguien le construye pantalla a
-- v_rrhh_ajuste sin leer esto, el mismo permiso —o la misma incapacidad— se
-- descuenta dos veces, y nada en la base lo impide: son dos tablas.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── 1 · LOS DATOS ───────────────────────────────────────────────────────
alter table rrhh_permiso add column if not exists incapacidad_origen text;
alter table rrhh_permiso add column if not exists incapacidad_boleta text;

-- EL CHECK SE REESCRIBE ENTERO, no se "extiende". Un drop + add deja la
-- definicion que queda escrita aca y no depende de cual era la de antes — que
-- es la unica forma honesta de hacerlo sin poder leer `pg_constraint` desde
-- afuera (la anon key no ve el catalogo).
alter table rrhh_permiso drop constraint if exists rrhh_permiso_modalidad_ok;
alter table rrhh_permiso add  constraint rrhh_permiso_modalidad_ok check (
  modalidad_descuento is null
  or modalidad_descuento in ('descuento','reposicion','incapacidad'));

-- ORIGEN OBLIGATORIO SOLO EN LA INCAPACIDAD, y lo contrario tambien: un permiso
-- normal no puede quedar con un origen colgado, porque el dia que alguien filtre
-- por origen esa fila va a aparecer donde no corresponde.
--
-- ⚠️ EL `coalesce(..., false)` NO ES DECORACION. Postgres ACEPTA un CHECK que
-- evalua a NULL, y sin el coalesce este se cuela: con modalidad='incapacidad' y
-- origen NULL, `origen in (...)` da NULL, el AND da NULL, y la fila ENTRA — una
-- incapacidad sin origen, que es justo lo que este CHECK viene a impedir. Es el
-- mismo hueco que CAMBIO_NOTA_MIN_B.sql encontro el 15-sep-2026 en
-- `ent_alisto_linea`, y se cierra igual.
--
-- Y HORAS QUEDA PROHIBIDA en una incapacidad: se paga por dias (naturales o
-- habiles, segun el parametro), nunca por horas. Una incapacidad de 3 horas no
-- se puede leer y el descuento saldria mal por un factor de 8.
alter table rrhh_permiso drop constraint if exists rrhh_permiso_incap_ok;
alter table rrhh_permiso add  constraint rrhh_permiso_incap_ok check (coalesce(
  case when modalidad_descuento = 'incapacidad'
       then incapacidad_origen is not null
            and incapacidad_origen in ('enfermedad_comun','accidente_trabajo')
            and horas is null
       else incapacidad_origen is null and incapacidad_boleta is null
  end, false));

comment on column rrhh_permiso.incapacidad_origen is
  'enfermedad_comun (CCSS) / accidente_trabajo (INS). Obligatoria si '
  'modalidad_descuento = incapacidad, y prohibida si no. Decide que subsidio se '
  'nombra en el desglose y, si algun dia difieren, que porcentaje aplica.';
comment on column rrhh_permiso.incapacidad_boleta is
  'Numero de boleta de la CCSS o del INS. OPCIONAL. Solo se puede escribir al '
  'pedir o al resolver: despues la fila queda congelada (grant de update por '
  'columna). Una boleta que llegue mas tarde NO se puede adjuntar — queda '
  'anotado como limitacion, ver PREGUNTAS_contadora_incapacidades.md punto 7.';


-- ── 2 · LOS PARAMETROS ──────────────────────────────────────────────────
-- `rrhh_param.valor` es numeric, asi que los booleanos van como 1/0. No es
-- elegante y se dice en cada nota, porque un `0` leido como "cero colones" en
-- vez de "falso" es un malentendido caro.
--
-- El `where not exists` es el mismo patron de la semilla del pegado 2: pegar
-- esto dos veces no duplica ni pisa un valor ya corregido a mano.
insert into rrhh_param (clave, valor, nota, creado_por)
select * from (values
  ('incap_patrono_pct_dias_1_3', 50.0,
   'PORCENTAJE (no fraccion) del salario diario que paga la empresa los primeros '
   'dias de incapacidad. 50 es el minimo legal citado (art. 79 Codigo de Trabajo). '
   'SIN CONFIRMAR por la contadora.', 'semilla-incap'),
  ('incap_patrono_pct_dia_4_en_adelante', 0.0,
   'PORCENTAJE que pone la empresa POR ENCIMA del subsidio, del dia 4 en adelante. '
   '0 = la empresa no complementa. Si se decide que el trabajador cobre el 100%, '
   'esto pasa a 40 (sobre el 60% de la CCSS). SIN CONFIRMAR.', 'semilla-incap'),
  ('incap_dias_patrono', 3.0,
   'Hasta que dia de la incapacidad aplica el porcentaje de los primeros dias. '
   'Existe para que el 3 no quede escrito dentro de la vista. Es el gemelo nuevo '
   'de ccss_dias_empresa, que alimenta la vista vieja sin pantalla.', 'semilla-incap'),
  ('incap_dias_naturales', 1.0,
   'BOOLEANO como 1/0 (valor es numeric). 1 = se pagan dias naturales, incluidos '
   'sabados, domingos y feriados, con tarifa salario/30 igual que el resto del '
   'modulo. 0 = solo dias habiles. SIN CONFIRMAR.', 'semilla-incap'),
  ('incap_subsidio_lo_paga_la_empresa', 0.0,
   'BOOLEANO como 1/0. 0 = la CCSS o el INS depositan el subsidio DIRECTO al '
   'trabajador, asi que no pasa por esta transferencia y el desglose lo dice. '
   '1 = nos lo reembolsan y lo pagamos en planilla, y entonces el modelo de '
   'resta de este modulo NO sirve tal como esta. Es la pregunta 2 de la nota a '
   'la contadora, y la que puede invalidar el diseño.', 'semilla-incap'),
  ('incapacidad_reglas_confirmadas', 0.0,
   'BOOLEANO como 1/0. SEMAFORO, no regla. 0 = las reglas de arriba no las '
   'confirmo la contadora: el desglose marca REGLAS SIN CONFIRMAR y la pantalla '
   'pinta un aviso. Se pone en 1 por decision de Andrea, no por limpieza.',
   'semilla-incap')
) as v(clave, valor, nota, creado_por)
where not exists (select 1 from rrhh_param p where p.clave = v.clave);


-- ── 3 · LAS VISTAS ──────────────────────────────────────────────────────
-- Se REEMPLAZAN enteras (create or replace), asi que el texto de abajo salio
-- extraido del PERSONAL_PAGO_QUINCENA.sql ya aplicado y no reescrito de
-- memoria: lo unico nuevo son las partes comentadas como tales. Reescribir una
-- vista de memoria es como se pierde en silencio una condicion que si estaba.
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
                               @> (pm.fecha_inicio + g.i))) as habil,
       -- EL NUMERO DE DIA DENTRO DE LA INCAPACIDAD, no de la quincena. Es lo que
       -- permite que "dia 1-3 vs dia 4+" siga contando cuando la incapacidad
       -- cruza el 15: g.i corre sobre el rango del permiso, asi que el dia 4 es
       -- el dia 4 este donde este el corte de la quincena.
       -- ⚠️ CUENTA DIAS NATURALES SIEMPRE, incluso si `incap_dias_naturales`
       -- dice que solo se PAGAN los habiles. El plazo del art. 79 corre en dias
       -- de calendario: un fin de semana no se paga pero igual consume plazo.
       -- Si la contadora dice lo contrario, se cambia ACA y en un solo lugar.
       (g.i + 1)                                 as dia_n,
       pm.incapacidad_origen
  from rrhh_permiso pm
  join rrhh_persona p on p.id = pm.persona_id
  cross join lateral generate_series(0, (pm.fecha_fin - pm.fecha_inicio)) as g(i)
 where pm.estado = 'aprobado'
   and acceso_es_socia();


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
),
-- UNA INCAPACIDAD, RESUMIDA POR QUINCENA. Hermana de `perm`, con dos
-- diferencias que son todo el asunto:
--   · el porcentaje que paga la empresa depende de `pd.dia_n` —el numero de dia
--     DENTRO de la incapacidad— y no de donde cae en la quincena. Una
--     incapacidad del 14 al 18 deja renglon en Q1 y en Q2, y el dia 4 sigue
--     siendo el dia 4 en la segunda: el conteo NO reinicia.
--   · NI UN PORCENTAJE NI UN PLAZO estan escritos aca. Los cuatro salen de
--     `rrhh_param`, porque las reglas todavia no las confirmo la contadora
--     (ver PREGUNTAS_contadora_incapacidades.md). Cambiar la regla es insertar
--     una fila, no reescribir esta vista.
incap as (
  select s.quincena, s.ini, s.fin, s.persona_id, s.nombre, s.tarifa_dia,
         pd.permiso_id,
         max(pd.incapacidad_origen)             as origen,
         min(pd.dia)                            as dia_ini,
         max(pd.dia)                            as dia_fin,
         -- QUE DIAS SE CUENTAN. `incap_dias_naturales` va como 1/0 porque
         -- `rrhh_param.valor` es numeric y no admite booleanos.
         count(*) filter (
           where rrhh_param('incap_dias_naturales', s.fin) = 1 or pd.habil
         )                                      as dias,
         -- LO QUE SE DESCUENTA POR DIA = tarifa_dia - lo que paga la empresa.
         -- Con pct_dias_1_3 = 50 y pct_dia_4 = 0 esto da exactamente lo mismo
         -- que la rama `incap_ccss` que ya existia en v_rrhh_ajuste_detalle
         -- (0,5x los primeros tres dias, 1x del cuarto). No es casualidad: es
         -- la comprobacion de que el modelo nuevo no cambio la regla vieja,
         -- solo la trajo a una pantalla.
         sum(
           case when rrhh_param('incap_dias_naturales', s.fin) = 1 or pd.habil
                then s.tarifa_dia * (1 -
                       (case when pd.dia_n <= rrhh_param('incap_dias_patrono', s.fin)
                             then rrhh_param('incap_patrono_pct_dias_1_3',       s.fin)
                             else rrhh_param('incap_patrono_pct_dia_4_en_adelante', s.fin)
                        end) / 100.0)
                else 0 end
         )                                      as descuento
    from sal s
    join v_rrhh_permiso_dia pd
      on pd.persona_id = s.persona_id and pd.dia between s.ini and s.fin
   where pd.modalidad_descuento = 'incapacidad'
     and s.salario_mensual is not null
   group by s.quincena, s.ini, s.fin, s.persona_id, s.nombre, s.tarifa_dia, pd.permiso_id
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
 where acceso_es_socia()

union all

-- LAS INCAPACIDADES. Renglon APARTE y con etiqueta que dice que el subsidio no
-- va en esta transferencia: sin eso, el numero se lee como "esto es todo lo que
-- cobra" y no lo es — la Caja o el INS le depositan el resto por su cuenta.
select i.quincena, i.ini, i.fin, i.persona_id, i.nombre,
       'incapacidad'::text                   as concepto,
       i.permiso_id                          as ref_id,
       i.dia_ini                             as dia,
       i.dias::numeric                       as cantidad,
       'dias'::text                          as unidad,
       i.tarifa_dia                          as tarifa,
       - i.descuento                         as monto,
       ('Incapacidad'
        || case when i.origen = 'accidente_trabajo' then ' (accidente de trabajo)'
                when i.origen = 'enfermedad_comun'  then ' (enfermedad comun)'
                else '' end
        || ': ' || i.dias::text || case when i.dias = 1 then ' dia' else ' dias' end
        || ' · ' || to_char(i.dia_ini,'DD-MM')
        || case when i.dia_fin > i.dia_ini then ' al ' || to_char(i.dia_fin,'DD-MM') else '' end
        || case when rrhh_param('incap_subsidio_lo_paga_la_empresa', i.fin) = 1
                then ' · subsidio INCLUIDO en esta transferencia'
                else ' · subsidio '
                     || case when i.origen = 'accidente_trabajo' then 'INS' else 'CCSS' end
                     || ' NO incluido en esta transferencia' end
        || case when rrhh_param('incapacidad_reglas_confirmadas', i.fin) = 1 then ''
                else ' · REGLAS SIN CONFIRMAR' end
       )                                      as nota
  from incap i
 where acceso_es_socia();


create or replace view v_rrhh_pago with (security_invoker = true) as
select quincena, persona_id, nombre,
       min(ini) as ini, max(fin) as fin,
       coalesce(sum(monto) filter (where concepto = 'base'), 0)              as base,
       coalesce(sum(monto) filter (where concepto = 'descuento_permiso'), 0) as descuentos,
       coalesce(sum(monto) filter (where concepto = 'ajuste'), 0)            as ajustes,
       coalesce(sum(monto), 0)                                               as final,
       count(*) filter (where concepto = 'descuento_permiso')                as permisos,
       count(*) filter (where concepto = 'ajuste')                           as ajustes_n,
       -- LAS DOS NUEVAS VAN AL FINAL y no intercaladas: `create or replace
       -- view` solo permite AGREGAR columnas, nunca reordenar. `final` ya las
       -- suma porque es sum(monto) sobre todos los conceptos.
       coalesce(sum(monto) filter (where concepto = 'incapacidad'), 0)       as incapacidades,
       count(*) filter (where concepto = 'incapacidad')                      as incap_n
  from v_rrhh_pago_detalle
 where acceso_es_socia()
 group by quincena, persona_id, nombre;


-- ── 4 · GRANTS ──────────────────────────────────────────────────────────
-- Las dos columnas nuevas se suman al grant de update POR COLUMNA, para que la
-- socia pueda poner o corregir el origen y la boleta en el mismo movimiento en
-- que aprueba. Sigue siendo el unico momento posible: `rrhh_permiso_upd` solo
-- deja pasar pendiente -> final, asi que despues de resuelta la fila se congela.
-- `horas`, `fecha_inicio`, `fecha_fin` y `motivo` siguen FUERA de la lista.
grant update (estado, resolucion_nota, modalidad_descuento,
              incapacidad_origen, incapacidad_boleta) on rrhh_permiso
  to authenticated;

-- Las vistas se reemplazaron, no se crearon: los grants y el revoke de anon del
-- pegado 5 siguen vigentes. Se repiten igual porque `create or replace view` en
-- algunas versiones restablece privilegios por defecto, y depender de que no lo
-- haga es la clase de supuesto que deja una vista con SALARIO abierta a la anon
-- key. Es idempotente y cuesta nada.
revoke all on v_rrhh_permiso_dia, v_rrhh_pago_detalle, v_rrhh_pago from anon;
grant select on v_rrhh_permiso_dia, v_rrhh_pago_detalle, v_rrhh_pago to authenticated;


-- ── 5 · EL CANDADO ──────────────────────────────────────────────────────
do $candado$
declare
  anon_n    int;
  invoker_n int;
  par_n     int;
  pct_raros int;
  bool_raros int;
begin
  select count(*) into anon_n from (
    select unnest(array['v_rrhh_permiso_dia','v_rrhh_pago_detalle','v_rrhh_pago']) as t
  ) x
   where has_table_privilege('anon','public.'||x.t,'SELECT')
      or has_table_privilege('anon','public.'||x.t,'INSERT')
      or has_table_privilege('anon','public.'||x.t,'UPDATE')
      or has_table_privilege('anon','public.'||x.t,'DELETE');

  select count(*) into invoker_n
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname='public'
     and c.relname in ('v_rrhh_permiso_dia','v_rrhh_pago_detalle','v_rrhh_pago')
     and c.reloptions::text like '%security_invoker=true%';

  select count(distinct clave) into par_n from rrhh_param
   where clave in ('incap_patrono_pct_dias_1_3','incap_patrono_pct_dia_4_en_adelante',
                   'incap_dias_patrono','incap_dias_naturales',
                   'incap_subsidio_lo_paga_la_empresa','incapacidad_reglas_confirmadas');

  -- LA TRAMPA DE LAS UNIDADES, cazada. Un pct entre 0 y 1 (exclusivo) es casi
  -- seguro una fraccion que alguien escribio creyendo que esto usaba el mismo
  -- formato que `ccss_pct_empresa` (0,5). Con 0,5 en vez de 50, la empresa
  -- pagaria medio por ciento del dia en vez de la mitad: el trabajador cobra de
  -- menos y los numeros cierran solos. 0 SI es valido (no complementar nada).
  select count(*) into pct_raros from rrhh_param
   where clave in ('incap_patrono_pct_dias_1_3','incap_patrono_pct_dia_4_en_adelante')
     and (valor < 0 or valor > 100 or (valor > 0 and valor < 1));

  select count(*) into bool_raros from rrhh_param
   where clave in ('incap_dias_naturales','incap_subsidio_lo_paga_la_empresa',
                   'incapacidad_reglas_confirmadas')
     and valor not in (0, 1);

  if anon_n <> 0 then
    raise exception 'CANDADO: `anon` puede leer o escribir % de las 3 vistas. Aca hay '
      'SALARIO y la anon key es PUBLICA. NO SE APLICO NADA.', anon_n;
  end if;
  if invoker_n <> 3 then
    raise exception 'CANDADO: solo % de 3 vistas con security_invoker=true. Sin eso la '
      'vista corre con los permisos del dueño y esquiva la RLS. NO SE APLICO NADA.', invoker_n;
  end if;
  if par_n <> 6 then
    raise exception 'CANDADO: hay % de 6 parametros de incapacidad. NO SE APLICO NADA.', par_n;
  end if;
  if pct_raros <> 0 then
    raise exception 'CANDADO: % parametro(s) de porcentaje fuera de rango. Los nuevos van '
      'en PORCENTAJE (50), no en fraccion (0,5) como el viejo ccss_pct_empresa. '
      'Un 0,5 aca le paga al trabajador medio por ciento del dia. NO SE APLICO NADA.', pct_raros;
  end if;
  if bool_raros <> 0 then
    raise exception 'CANDADO: % parametro(s) booleano(s) con un valor que no es 0 ni 1. '
      '`rrhh_param.valor` es numeric: el booleano se guarda como 1/0. NO SE APLICO NADA.', bool_raros;
  end if;

  if (select valor from rrhh_param where clave='incapacidad_reglas_confirmadas'
       order by vigente_desde desc, creado_en desc limit 1) = 1 then
    raise warning 'OJO: incapacidad_reglas_confirmadas ya esta en 1. Si las reglas todavia '
      'no las confirmo la contadora, la pantalla NO va a avisar nada.';
  end if;

  raise notice 'CANDADO OK: anon en 0 · 3 vistas con security_invoker · 6 parametros · unidades sanas';
end
$candado$;


-- ── 6 · LA PRUEBA DE QUE LA TRANSACCION LLEGO HASTA ACA ─────────────────
-- Regla 🔴 de CLAUDE.md: un "Success" del editor no es evidencia de nada.
-- ESPERADO:  2 · 1 · 1 · 6 · 3 · 0 · 0
select
  (select count(*) from information_schema.columns
    where table_schema='public' and table_name='rrhh_permiso'
      and column_name in ('incapacidad_origen','incapacidad_boleta'))      as cols_nuevas,
  (select count(*) from pg_constraint where conname='rrhh_permiso_incap_ok') as check_incap,
  (select count(*) from pg_constraint c
    where c.conname='rrhh_permiso_modalidad_ok'
      and pg_get_constraintdef(c.oid) like '%incapacidad%')                as modalidad_extendido,
  (select count(distinct clave) from rrhh_param
    where clave like 'incap%')                                             as params_incap,
  (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public'
      and c.relname in ('v_rrhh_permiso_dia','v_rrhh_pago_detalle','v_rrhh_pago')
      and c.reloptions::text like '%security_invoker=true%')               as vistas_invoker,
  (select count(*) from (select unnest(array['v_rrhh_permiso_dia','v_rrhh_pago_detalle',
                                             'v_rrhh_pago']) as t) x
    where has_table_privilege('anon','public.'||x.t,'SELECT'))             as anon_debe_ser_0,
  (select valor::int from rrhh_param where clave='incapacidad_reglas_confirmadas'
    order by vigente_desde desc, creado_en desc limit 1)                   as reglas_confirmadas_0;

commit;


-- ════════════════════════════════════════════════════════════════════════
-- DESPUES DEL COMMIT
-- ════════════════════════════════════════════════════════════════════════
--   1. `python3 esquema_check.py` — los objetos no son nuevos (ya existian),
--      asi que el contador NO sube. Lo que tiene que seguir dando es
--      `✓ cerrado` en v_rrhh_pago y v_rrhh_pago_detalle. Si alguno pasa a
--      devolver una lista, el `create or replace view` restablecio el grant de
--      anon y eso es una FUGA con salario adentro.
--   2. `python3 herramientas/sonda_columnas.py --nuevas` mas las dos columnas
--      nuevas de rrhh_permiso (incapacidad_origen, incapacidad_boleta).
--   3. PRUEBAS_INCAPACIDAD.sql — las cinco pruebas con datos ficticios, en una
--      transaccion que termina en ROLLBACK. Son las unicas que miden la
--      ARITMETICA, y ninguna de las dos de arriba la mide.
--   4. Y lo que ningun script da: que la REGLA sea la correcta. Eso lo contesta
--      la contadora, y hasta entonces `incapacidad_reglas_confirmadas` se queda
--      en 0 y nadie transfiere sin cuadrar a mano.
