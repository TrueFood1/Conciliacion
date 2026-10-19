-- SOLO LECTURA · DIAGNOSTICO_OCT_Q1.sql · termina en rollback · no escribe nada
-- ════════════════════════════════════════════════════════════════════════
-- QUINCENA 1-15 DE OCTUBRE 2026 · salario, neto calculado y la diferencia
-- 15-oct-2026. Una sola tabla, una fila por persona.
--
-- ⚠️ ESTE ARCHIVO NO LLEVA NINGUN MONTO, Y NO HAY QUE PONERLE NINGUNO QUE SE
-- COMMITEE. El repo es PUBLICO. Los tres netos transferidos van en `null` abajo:
-- Lorena los escribe EN EL EDITOR antes de correr, y los numeros salen en SU
-- pantalla. Si se guarda el archivo con los numeros puestos, no commitearlo.
--
-- ⚠️ TERMINA EN `rollback;`. Hace falta la transaccion porque `set_config(...,
-- true)` dura solo lo que dura la transaccion, y sin impersonar a una socia las
-- vistas del pago (que llevan `where acceso_es_socia()`) devuelven CERO FILAS
-- corridas como postgres. No escribe nada: son tres `select`.
--
-- QUE CONTESTA
--   · el salario mensual registrado y desde cuando rige;
--   · el neto que calcula la pantalla (de v_rrhh_pago, no recalculado aca);
--   · la diferencia contra lo que se transfiere, en colones y en PORCENTAJE;
--   · si el 6,49 % explica esa diferencia, persona por persona;
--   · y si la quincena esta LIMPIA: sin extras, sin permisos con descuento, sin
--     incapacidades y sin ajustes manuales. Porque la comparacion solo vale si
--     no hay nada mas restando.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- Impersonar una socia: sin esto, v_rrhh_pago devuelve cero filas.
select set_config('request.jwt.claims',
  json_build_object('email', (select a.email from acceso_usuario a
                               where a.perfil='socias' and a.activo order by a.id limit 1),
                    'role','authenticated')::text, true);
select set_config('role','authenticated', true);

with
-- ┌──────────────────────────────────────────────────────────────────────┐
-- │ PONER ACA LOS TRES NETOS TRANSFERIDOS, reemplazando los null.        │
-- │ Van en null a proposito: este archivo vive en un repo publico.       │
-- └──────────────────────────────────────────────────────────────────────┘
esp(quien, neto_transferido) as (values
  ('daniel',  null::numeric),
  ('daniela', null::numeric),
  ('ney',     null::numeric)
),
qn as (select '2026-10-Q1'::text as quincena,
              date '2026-10-01'  as ini,
              date '2026-10-15'  as fin),
-- El porcentaje de rebaja vigente, leido del parametro (no escrito aca).
pct as (select rrhh_param('rebaja_trabajador_pct', (select fin from qn)) as p),
gente as (
  select p.id, p.nombre, lower(split_part(btrim(p.nombre),' ',1)) as primera
    from rrhh_persona p
),
-- Salario vigente el ULTIMO dia de la quincena, igual que lo elige el pegado 5.
sal as (
  select g.id, s.salario_mensual, s.vigente_desde
    from gente g
    left join lateral (
      select sa.salario_mensual, sa.vigente_desde from rrhh_salario sa
       where sa.persona_id = g.id and sa.vigente_desde <= (select fin from qn)
       order by sa.vigente_desde desc, sa.creado_en desc limit 1) s on true
),
-- ¿Cambio el salario ADENTRO de la quincena? El pegado 5 NO prorratea: un
-- aumento con vigencia el dia 10 paga toda la Q1 al valor nuevo. Si esto marca,
-- es la explicacion mas probable de un neto que no calza.
cambio as (
  select g.id, count(*) as n,
         coalesce(string_agg(to_char(sa.vigente_desde,'DD-MM'), ', '), '') as cuando
    from gente g
    left join rrhh_salario sa on sa.persona_id = g.id
          and sa.vigente_desde > (select ini from qn)
          and sa.vigente_desde <= (select fin from qn)
   group by g.id
),
-- El neto que calcula la PANTALLA. Se lee de la vista, no se recalcula: si se
-- recalculara aca habria dos formulas y esta diria lo que yo creo, no lo que la
-- pantalla muestra.
pago as (
  select g.id, v.base, v.descuentos, v.incapacidades, v.ajustes, v.rebaja,
         v.subtotal, v.final
    from gente g
    left join v_rrhh_pago v
           on v.persona_id = g.id and v.quincena = (select quincena from qn)
),
-- LO QUE PODRIA ESTAR RESTANDO. La comparacion solo vale si no hay nada de esto.
mov as (
  select g.id,
         (select count(*) from rrhh_evento e
           join v_rrhh_evento_estado ve on ve.id = e.id
          where e.persona_id = g.id and ve.estado='aprobado'
            and e.tipo in ('extra','dia_extra')
            and e.fecha between (select ini from qn) and (select fin from qn)) as extras,
         (select count(*) from rrhh_permiso p
          where p.persona_id = g.id and p.estado='aprobado'
            and p.modalidad_descuento = 'descuento'
            and daterange(p.fecha_inicio,p.fecha_fin,'[]')
                && daterange((select ini from qn),(select fin from qn),'[]')) as perm_desc,
         (select count(*) from rrhh_permiso p
          where p.persona_id = g.id and p.estado='aprobado'
            and p.modalidad_descuento = 'incapacidad'
            and daterange(p.fecha_inicio,p.fecha_fin,'[]')
                && daterange((select ini from qn),(select fin from qn),'[]')) as incaps,
         (select count(*) from rrhh_ajuste_manual a
          where a.persona_id = g.id
            and a.fecha between (select ini from qn) and (select fin from qn)) as ajustes
    from gente g
)
select g.nombre                                                   as persona,
       sal.salario_mensual                                        as salario_mensual,
       to_char(sal.vigente_desde,'DD-MM-YYYY')                    as rige_desde,
       case when cambio.n > 0 then '⚠ ' || cambio.cuando else 'no' end
                                                                  as cambio_en_la_quincena,
       pago.base                                                  as base_quincena,
       (select p from pct)                                         as rebaja_pct,
       pago.rebaja                                                as rebaja_monto,
       pago.final                                                 as neto_calculado,
       esp.neto_transferido                                       as neto_transferido,
       (pago.final - esp.neto_transferido)                        as diferencia,
       case when esp.neto_transferido is null or esp.neto_transferido = 0 then null
            else round((pago.final - esp.neto_transferido)
                       / esp.neto_transferido * 100, 2) end       as dif_pct,
       -- ¿EL 6,49 % EXPLICA ESTA PERSONA? Si el neto calculado calza al colon con
       -- lo transferido, si. Si no, el porcentaje unico no alcanza para ella.
       case when esp.neto_transferido is null then 'falta el dato'
            when abs(pago.final - esp.neto_transferido) <= 1 then 'SI, calza'
            else 'NO · se separa ' || round(abs(pago.final - esp.neto_transferido), 0) end
                                                                  as el_pct_explica,
       -- EL PORCENTAJE QUE HARIA CALZAR A ESTA PERSONA. Si los tres dan el mismo,
       -- el parametro unico sirve. Si uno se aparta, no.
       case when sal.salario_mensual is null or sal.salario_mensual = 0
                 or esp.neto_transferido is null then null
            else round((1 - esp.neto_transferido / (sal.salario_mensual / 2)) * 100, 4) end
                                                                  as pct_que_calzaria,
       mov.extras, mov.perm_desc, mov.incaps, mov.ajustes,
       case when mov.extras + mov.perm_desc + mov.incaps + mov.ajustes = 0
            then 'limpia' else '⚠ hay movimientos' end            as quincena
  from gente g
  join sal    on sal.id    = g.id
  join cambio on cambio.id = g.id
  join pago   on pago.id   = g.id
  join mov    on mov.id    = g.id
  left join esp on esp.quien = g.primera
 order by g.nombre;

rollback;
