-- ════════════════════════════════════════════════════════════════════════
-- MODULO PERSONAL · REBAJA DEL TRABAJADOR (del bruto guardado al NETO)
-- (PEGADO 7) · Preparado el 3-oct-2026. NO SE CORRIO.
-- Va DESPUES de PERSONAL_PAGO_QUINCENA.sql (5) y PERSONAL_INCAPACIDAD.sql (6),
-- los dos YA APLICADOS y que NO SE TOCAN. Todo lo de aca es insert de
-- parametros y `create or replace` sobre las vistas que esos dejaron.
--
-- QUE AGREGA
--   · 3 parametros: rebaja_trabajador_pct (6,49), rebaja_trabajador_confirmada
--     (0) e incap_sujeta_a_rebaja (0).
--   · v_rrhh_pago_detalle — quinta rama: concepto 'rebaja'.
--   · v_rrhh_pago         — dos columnas al final: `rebaja` y `subtotal`.
--     `final` pasa a ser el NETO sin cambiar de nombre: ya era sum(monto) sobre
--     todos los conceptos, y la rebaja es un concepto mas.
--
-- ════════════════════════════════════════════════════════════════════════
-- DE DONDE SALE EL 6,49, Y POR QUE NO ESTA ESCRITO EN NINGUNA FORMULA
-- ════════════════════════════════════════════════════════════════════════
-- MEDIDO el 3-oct-2026: la pantalla mostraba un 6,94% MAS que lo que Lorena
-- transfiere, y la proporcion era la misma en las tres personas. Que sea
-- proporcional es lo que descarta un error de calculo puntual y apunta a una
-- rebaja porcentual: `rrhh_salario.salario_mensual` esta ANTES de las rebajas
-- del trabajador. 1 - 1/1,0694 = 0,064896 -> 6,49%, y la vuelta cierra exacto
-- (con 6,49% de rebaja el bruto queda 6,9404% mas alto).
--
-- ⚠️ ES UN DATO DERIVADO DE UNA OBSERVACION, NO UNA TASA LEGAL. Por eso vive en
-- `rrhh_param` con su propio semaforo `rebaja_trabajador_confirmada = 0`:
-- mientras valga 0 la pantalla avisa y nadie transfiere contra ese neto sin
-- cuadrarlo. Cambiar el porcentaje es INSERTAR UNA FILA — no tocar esta vista,
-- no publicar la herramienta de nuevo.
--
-- ⚠️ Y HAY ALGO QUE CONVIENE PREGUNTARLE A LA CONTADORA, porque el numero no
-- cuadra con lo esperable: la rebaja del trabajador en Costa Rica se suele
-- citar en torno al 10,67% (CCSS 9,67% + Banco Popular 1%). 6,49% es
-- BASTANTE MENOS. Las dos lecturas posibles son distintas y llevan a codigo
-- distinto:
--   (a) lo guardado en `rrhh_salario` NO es el bruto de planilla sino algo
--       intermedio, y entonces un unico porcentaje va a ir desviandose;
--   (b) la rebaja efectiva de estas tres personas es menor por alguna razon
--       que solo la contadora conoce.
-- No se resuelve adivinando. Si la respuesta es (a), lo correcto deja de ser un
-- porcentaje y pasa a ser guardar el monto transferido por persona como dato
-- propio — que es justamente el plan B que ya esta sobre la mesa.
--
-- ════════════════════════════════════════════════════════════════════════
-- LA FORMULA, Y LAS TRES COSAS QUE NO LLEVAN REBAJA
-- ════════════════════════════════════════════════════════════════════════
--   neto = (base - descuentos de permiso - bruto de dias de incapacidad)
--            × (1 - pct/100)
--        + lo que la empresa paga por la incapacidad     <- SIN rebaja
--        + ajustes manuales                              <- SIN rebaja
--
--   1 · LOS AJUSTES MANUALES NO LLEVAN REBAJA. Un adelanto es un monto NETO que
--       escribio una socia; aplicarle el 6,49% le descontaria de nuevo a un
--       numero que ya es final.
--   2 · LA PARTE DE LA INCAPACIDAD QUE PAGA LA EMPRESA TAMPOCO, por defecto: un
--       subsidio no esta sujeto a cargas sociales (criterio del MTSS, TAMBIEN
--       SIN CONFIRMAR). Lo gobierna `incap_sujeta_a_rebaja = 0`; si la contadora
--       dice lo contrario, se pone en 1 y la formula lo incluye sola.
--   3 · EL BRUTO DE LOS DIAS DE INCAPACIDAD SE RESTA ANTES de la rebaja: esos
--       dias no se pagan como salario, asi que no pueden generar rebaja.
--
-- EL DESCUENTO DE PERMISO SIGUE CALCULANDOSE SOBRE LA TARIFA DEL BRUTO
-- (salario ÷ 30 y ÷ 8) y la rebaja se aplica DESPUES. Da exactamente lo mismo
-- que calcular la tarifa sobre el neto, y no es una casualidad afortunada sino
-- distributividad:
--     (B - d·S/30)·(1-p)  =  B·(1-p) - d·(S·(1-p))/30
-- El ensayo PRUEBAS_REBAJA.sql lo comprueba con numeros, no de palabra.
--
-- ⚠️ Y LA REBAJA SE CALCULA SOBRE LOS RENGLONES YA EMITIDOS, no recalculando
-- las formulas. De ahi el CTE `renglones` nuevo: si la rebaja volviera a derivar
-- el descuento de un permiso por su cuenta, habria DOS copias de la misma
-- formula de plata y la segunda nunca recibiria el arreglo de la primera.
--
-- ⚠️ La rama `permiso_sin_goce` de `v_rrhh_ajuste_detalle` SIGUE MUERTA A
-- PROPOSITO (pegados 5 y 6). Vale igual ahora: esa vista no sabe nada de esta
-- rebaja, asi que si alguien le construye pantalla, va a mostrar brutos.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── 1 · LOS PARAMETROS ──────────────────────────────────────────────────
-- EN PORCENTAJE (6.49), NO EN FRACCION (0.0649). Es la misma convencion que los
-- pct de incapacidad del pegado 6, y el candado de la seccion 4 rechaza un valor
-- entre 0 y 1 justamente para que nadie lo "corrija" a fraccion: 0,0649 aca
-- rebajaria un 0,06% en vez de un 6,49% y los numeros cerrarian solos.
-- Los booleanos van como 1/0 porque `rrhh_param.valor` es numeric.
insert into rrhh_param (clave, valor, nota, creado_por)
select * from (values
  ('rebaja_trabajador_pct', 6.49,
   'PORCENTAJE (no fraccion) que se le rebaja al trabajador sobre el salario '
   'guardado en rrhh_salario, para llegar al NETO que se transfiere. DERIVADO DE '
   'UNA OBSERVACION del 3-oct-2026 (la pantalla daba 6,94% mas que la '
   'transferencia real, igual en las tres personas): 1 - 1/1,0694 = 6,49%. '
   'SIN CONFIRMAR por la contadora. Ojo: la rebaja habitual en CR se cita cerca '
   'del 10,67%, asi que este numero mas bajo es, en si mismo, una pregunta.',
   'semilla-rebaja'),
  ('rebaja_trabajador_confirmada', 0.0,
   'BOOLEANO como 1/0. SEMAFORO, no regla. 0 = el porcentaje de arriba no lo '
   'confirmo la contadora: el desglose marca PORCENTAJE SIN CONFIRMAR y la '
   'pantalla pinta un aviso. Se pone en 1 por decision de Andrea.',
   'semilla-rebaja'),
  ('incap_sujeta_a_rebaja', 0.0,
   'BOOLEANO como 1/0. 0 = la parte de la incapacidad que paga la empresa NO '
   'lleva rebaja del trabajador (un subsidio no esta sujeto a cargas sociales, '
   'criterio del MTSS). SIN CONFIRMAR: va junto con las demas preguntas de '
   'incapacidad en PREGUNTAS_contadora_incapacidades.md.',
   'semilla-rebaja')
) as v(clave, valor, nota, creado_por)
where not exists (select 1 from rrhh_param p where p.clave = v.clave);


-- ── 2 · LAS VISTAS ──────────────────────────────────────────────────────
-- Se reemplazan enteras, asi que el texto de abajo salio EXTRAIDO del
-- PERSONAL_INCAPACIDAD.sql ya aplicado, no reescrito de memoria. Lo unico nuevo
-- son las partes comentadas como tales.
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
),
-- ⚠️ LAS CUATRO RAMAS DE SIEMPRE, AHORA ADENTRO DE UN CTE, y esa es toda la
-- estructura nueva. La rebaja del trabajador se calcula SOBRE LOS RENGLONES YA
-- EMITIDOS, no recalculando las formulas: si la rebaja volviera a derivar el
-- descuento de un permiso por su cuenta, habria DOS copias de la misma formula
-- de plata y la segunda nunca recibiria el arreglo de la primera. Es la regla
-- de "una regla de presentacion escrita por pantalla se desincroniza", aplicada
-- adentro de una vista.
renglones as (
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
 where acceso_es_socia()
),

-- ── LA REBAJA DEL TRABAJADOR ────────────────────────────────────────────
-- POR QUE EXISTE. `rrhh_salario.salario_mensual` esta ANTES de las rebajas que
-- se le descuentan al trabajador, y la pantalla tiene que llegar al NETO que
-- Lorena transfiere. Medido el 3-oct-2026: la pantalla mostraba un 6,94% mas
-- que la transferencia real, igual de proporcional en las tres personas, y eso
-- equivale a una rebaja del 6,49% sobre lo guardado (1 - 1/1,0694).
--
-- ⚠️ EL 6,49 NO ESTA ESCRITO ACA. Sale de `rrhh_param('rebaja_trabajador_pct')`,
-- porque es un dato DERIVADO DE UNA OBSERVACION y no una tasa legal confirmada.
-- La contadora lo confirma esta semana. Cambiarlo es insertar una fila.
--
-- COMO SE PARTE LA PLATA, que es la unica parte delicada:
--   · `sujeto`  = lo que se paga COMO SALARIO y por lo tanto lleva rebaja:
--                 la base de la quincena, menos los descuentos de permiso,
--                 menos el BRUTO de los dias de incapacidad (cantidad ×
--                 tarifa_dia) — esos dias no se pagan como salario.
--   · `empresa` = lo que la empresa pone por la incapacidad (los dias 1-3 al
--                 porcentaje del patrono). Se saca del propio renglon:
--                 monto = -(bruto - empresa), asi que empresa = bruto + monto.
--                 NO lleva rebaja por defecto: un subsidio no esta sujeto a
--                 cargas sociales (criterio del MTSS, TAMBIEN SIN CONFIRMAR),
--                 y eso lo gobierna `incap_sujeta_a_rebaja`.
--   · LOS AJUSTES MANUALES NO ENTRAN NI A UNO NI A OTRO. Un adelanto es un
--     monto NETO que escribio una socia: aplicarle la rebaja le estaria
--     descontando un 6,49% a un numero que ya es final.
reb as (
  select r.quincena, r.persona_id, r.nombre,
         min(r.ini) as ini, max(r.fin) as fin,
         sum(case r.concepto
               when 'base'              then r.monto
               when 'descuento_permiso' then r.monto
               when 'incapacidad'       then - (r.cantidad * r.tarifa)
               else 0 end)                                    as sujeto,
         sum(case when r.concepto = 'incapacidad'
                  then (r.cantidad * r.tarifa) + r.monto
                  else 0 end)                                 as empresa
    from renglones r
   group by r.quincena, r.persona_id, r.nombre
)
select * from renglones

union all

select b.quincena, b.ini, b.fin, b.persona_id, b.nombre,
       'rebaja'::text                        as concepto,
       null::bigint                          as ref_id,
       b.ini                                 as dia,
       rrhh_param('rebaja_trabajador_pct', b.fin) as cantidad,
       'pct'::text                           as unidad,
       null::numeric                         as tarifa,
       - ((b.sujeto
           + case when rrhh_param('incap_sujeta_a_rebaja', b.fin) = 1
                  then b.empresa else 0 end)
          * rrhh_param('rebaja_trabajador_pct', b.fin) / 100.0) as monto,
       ('Rebajas del trabajador ('
        || trim(to_char(rrhh_param('rebaja_trabajador_pct', b.fin), 'FM999990.00'))
        || '%)'
        || case when b.empresa <> 0 and rrhh_param('incap_sujeta_a_rebaja', b.fin) <> 1
                then ' · no se aplican a la parte de incapacidad que paga la empresa'
                else '' end
        || case when rrhh_param('rebaja_trabajador_confirmada', b.fin) = 1 then ''
                else ' · PORCENTAJE SIN CONFIRMAR' end)        as nota
  from reb b
 where acceso_es_socia()
   -- Un renglon de rebaja en cero es ruido en la unica pantalla que tiene que
   -- poder leerse entera (misma razon que el CHECK monto <> 0 de los ajustes).
   and (b.sujeto + b.empresa) <> 0;


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
       count(*) filter (where concepto = 'incapacidad')                      as incap_n,
       -- AL FINAL otra vez: `create or replace view` solo permite agregar.
       -- `final` ya es el NETO, porque es sum(monto) sobre TODOS los conceptos y
       -- la rebaja es uno mas. `subtotal` es lo mismo sin la rebaja, para que la
       -- pantalla pueda mostrar el paso intermedio sin recalcularlo.
       coalesce(sum(monto) filter (where concepto = 'rebaja'), 0)            as rebaja,
       coalesce(sum(monto) filter (where concepto <> 'rebaja'), 0)           as subtotal
  from v_rrhh_pago_detalle
 where acceso_es_socia()
 group by quincena, persona_id, nombre;


-- ── 3 · GRANTS ──────────────────────────────────────────────────────────
-- Las vistas se reemplazaron, no se crearon, asi que los grants del pegado 5
-- siguen vigentes. Se repiten igual porque `create or replace view` puede
-- restablecer privilegios por defecto segun la version, y depender de que no lo
-- haga es como se deja una vista con SALARIO abierta a la anon key. Idempotente.
revoke all on v_rrhh_pago_detalle, v_rrhh_pago from anon;
grant select on v_rrhh_pago_detalle, v_rrhh_pago to authenticated;


-- ── 4 · EL CANDADO ──────────────────────────────────────────────────────
do $candado$
declare
  anon_n     int;
  invoker_n  int;
  par_n      int;
  pct_raros  int;
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
   where clave in ('rebaja_trabajador_pct','rebaja_trabajador_confirmada',
                   'incap_sujeta_a_rebaja');

  -- LA TRAMPA DE LAS UNIDADES, ahora tambien para la rebaja. Un pct entre 0 y 1
  -- (exclusivo) es casi seguro una fraccion escrita por alguien que creyo que
  -- esto usaba el formato de `ccss_pct_empresa` (0,5). Con 0,0649 en vez de 6,49
  -- la rebaja seria del 0,06% y el neto quedaria practicamente igual al bruto:
  -- los numeros cerrarian solos y nadie lo notaria. 0 SI es valido.
  select count(*) into pct_raros from rrhh_param
   where clave in ('incap_patrono_pct_dias_1_3','incap_patrono_pct_dia_4_en_adelante',
                   'rebaja_trabajador_pct')
     and (valor < 0 or valor > 100 or (valor > 0 and valor < 1));

  select count(*) into bool_raros from rrhh_param
   where clave in ('incap_dias_naturales','incap_subsidio_lo_paga_la_empresa',
                   'incapacidad_reglas_confirmadas','rebaja_trabajador_confirmada',
                   'incap_sujeta_a_rebaja')
     and valor not in (0, 1);

  if anon_n <> 0 then
    raise exception 'CANDADO: `anon` puede leer o escribir % de las 3 vistas. Aca hay '
      'SALARIO y la anon key es PUBLICA. NO SE APLICO NADA.', anon_n;
  end if;
  if invoker_n <> 3 then
    raise exception 'CANDADO: solo % de 3 vistas con security_invoker=true. NO SE APLICO NADA.',
      invoker_n;
  end if;
  if par_n <> 3 then
    raise exception 'CANDADO: hay % de 3 parametros de rebaja. NO SE APLICO NADA.', par_n;
  end if;
  if pct_raros <> 0 then
    raise exception 'CANDADO: % parametro(s) de porcentaje fuera de rango. Van en PORCENTAJE '
      '(6.49), no en fraccion (0.0649). Una fraccion aca deja el neto igual al bruto y '
      'nadie lo nota. NO SE APLICO NADA.', pct_raros;
  end if;
  if bool_raros <> 0 then
    raise exception 'CANDADO: % parametro(s) booleano(s) que no son 0 ni 1. NO SE APLICO NADA.',
      bool_raros;
  end if;

  if (select valor from rrhh_param where clave='rebaja_trabajador_confirmada'
       order by vigente_desde desc, creado_en desc limit 1) = 1 then
    raise warning 'OJO: rebaja_trabajador_confirmada ya esta en 1. Si la contadora todavia '
      'no confirmo el 6,49%%, la pantalla NO va a avisar nada.';
  end if;

  raise notice 'CANDADO OK: anon en 0 · 3 vistas con security_invoker · 3 parametros · unidades sanas';
end
$candado$;


-- ── 5 · LA PRUEBA DE QUE LA TRANSACCION LLEGO HASTA ACA ─────────────────
-- Regla 🔴 de CLAUDE.md: un "Success" del editor no es evidencia de nada.
-- ESPERADO:  3 · 6.49 · 0 · 0 · 3 · 0 · 1 · 1
select
  (select count(distinct clave) from rrhh_param
    where clave in ('rebaja_trabajador_pct','rebaja_trabajador_confirmada',
                    'incap_sujeta_a_rebaja'))                              as params_nuevos,
  (select valor from rrhh_param where clave='rebaja_trabajador_pct'
    order by vigente_desde desc, creado_en desc limit 1)                   as pct,
  (select valor::int from rrhh_param where clave='rebaja_trabajador_confirmada'
    order by vigente_desde desc, creado_en desc limit 1)                   as confirmada_0,
  (select valor::int from rrhh_param where clave='incap_sujeta_a_rebaja'
    order by vigente_desde desc, creado_en desc limit 1)                   as incap_rebaja_0,
  (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public'
      and c.relname in ('v_rrhh_permiso_dia','v_rrhh_pago_detalle','v_rrhh_pago')
      and c.reloptions::text like '%security_invoker=true%')               as vistas_invoker,
  (select count(*) from (select unnest(array['v_rrhh_pago_detalle','v_rrhh_pago']) as t) x
    where has_table_privilege('anon','public.'||x.t,'SELECT'))             as anon_debe_ser_0,
  -- Que la quinta rama exista de verdad: la columna `rebaja` en v_rrhh_pago y el
  -- concepto 'rebaja' en la definicion del detalle.
  (select count(*) from information_schema.columns
    where table_schema='public' and table_name='v_rrhh_pago'
      and column_name = 'rebaja')                                          as col_rebaja,
  (select count(*) from pg_views
    where schemaname='public' and viewname='v_rrhh_pago_detalle'
      and definition like '%''rebaja''%')                                  as rama_rebaja;

commit;


-- ════════════════════════════════════════════════════════════════════════
-- DESPUES DEL COMMIT
-- ════════════════════════════════════════════════════════════════════════
--   1. `python3 esquema_check.py` — los objetos no son nuevos, el contador NO
--      sube. Lo que tiene que seguir dando es `✓ cerrado` en v_rrhh_pago y
--      v_rrhh_pago_detalle: si alguna devuelve una lista, el `create or replace
--      view` restablecio el grant de anon y eso es una FUGA con salario adentro.
--   2. `python3 herramientas/sonda_columnas.py --nuevas` (incluye `rebaja` y
--      `subtotal`).
--   3. PRUEBAS_REBAJA.sql — las seis pruebas con datos ficticios y ROLLBACK.
--      Son las unicas que miden la ARITMETICA.
--   4. ⚠️ EL CUADRE QUE NO LO HACE NINGUN SCRIPT, y es el que decide si esto
--      sirve: Lorena abre una quincena SIN permisos ni incapacidades ni ajustes
--      y compara el neto de cada una de las tres personas contra lo que
--      transfiere, AL COLON. Si las tres calzan, el 6,49% es bueno y se pone
--      `rebaja_trabajador_confirmada` en 1. Si alguna NO calza, el porcentaje
--      unico no alcanza y hay que pasar al plan B: guardar el monto transferido
--      por persona como dato propio.
