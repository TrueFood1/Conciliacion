-- SOLO LECTURA · MEDICION_REPETIDAS.sql · no escribe nada
-- ════════════════════════════════════════════════════════════════════════
-- MEDICION · ¿cuantas solicitudes repetidas hay HOY? · SOLO LECTURA
-- 15-oct-2026. Una sola sentencia, una sola tabla.
--
-- PARA QUE. Antes de construir la proteccion contra repetidas hay que saber
-- contra que datos va a chocar. Si ya existen grupos que la proteccion
-- rechazaria, un constraint los rechaza HACIA ATRAS y el pegado no entra; y si
-- existen casos legitimos (rechazada y vuelta a pedir), una regla mal escrita
-- los rompe. Medir primero es lo que decide si la proteccion puede ser un
-- constraint o tiene que ser un chequeo en la funcion de inserto.
--
-- ⚠️ SOLO LECTURA: un `select`. Sin escrituras, sin DDL, sin transaccion.
-- ⚠️ SIN SALARIOS. Lleva nombre y fechas, que es lo autorizado. No pegar la
--    tabla en un chat publico si aparecen nombres que no corresponda mostrar.
-- ⚠️ Se corre como `postgres` desde el SQL Editor, asi que la RLS no recorta:
--    ve al equipo entero. No hace falta impersonar a nadie.
--
-- COMO SE DEFINE "REPETIDA"
--   vacaciones (rrhh_evento) : misma persona + mismo tipo + misma fecha + mismos dias
--   permisos   (rrhh_permiso): misma persona + mismas dos fechas + mismas horas
--   y en los dos casos, contando SOLO las filas no anuladas / no canceladas.
--
-- COMO SE LEE EL VEREDICTO DE CADA GRUPO
--   RECHAZARIA  = 2 o mas filas vivas (pendiente/solicitado o aprobado). Es un
--                 choque real: la proteccion lo frenaria, y si ya existe hay que
--                 limpiarlo antes o la proteccion no puede ser un constraint.
--   LEGITIMO    = a lo sumo 1 viva. El caso tipico es "rechazada y vuelta a
--                 pedir", que TIENE que seguir permitido.
-- ════════════════════════════════════════════════════════════════════════
with
-- ── vacaciones y todo lo de rrhh_evento, con su estado ──────────────────
ev as (
  select e.id, e.persona_id, p.nombre, e.tipo, e.fecha, e.dias, e.horas,
         v.estado
    from rrhh_evento e
    join rrhh_persona p on p.id = e.persona_id
    join v_rrhh_evento_estado v on v.id = e.id
   where v.estado <> 'anulado'        -- una anulada ya no choca con nada
),
ev_grupo as (
  select persona_id, max(nombre) as nombre, tipo, fecha, dias,
         count(*)                                                as filas,
         count(*) filter (where estado in ('solicitado','aprobado')) as vivas,
         string_agg(estado, ' + ' order by id)                    as estados,
         min(fecha)::text                                         as desde
    from ev
   group by persona_id, tipo, fecha, dias
  having count(*) > 1
),
-- ── permisos ────────────────────────────────────────────────────────────
-- `coalesce(horas,-1)` para agrupar: un permiso de 3 h y uno de dia completo el
-- mismo dia NO son la misma solicitud, y con null el group by los separaria mal.
pm as (
  select pm.id, pm.persona_id, p.nombre, pm.fecha_inicio, pm.fecha_fin,
         coalesce(pm.horas, -1) as horas_k, pm.horas, pm.estado
    from rrhh_permiso pm
    join rrhh_persona p on p.id = pm.persona_id
   where pm.estado <> 'cancelado'     -- hoy ese estado no existe; queda listo
),
pm_grupo as (
  select persona_id, max(nombre) as nombre, fecha_inicio, fecha_fin, horas_k,
         count(*)                                              as filas,
         count(*) filter (where estado in ('pendiente','aprobado')) as vivas,
         string_agg(estado, ' + ' order by id)                  as estados
    from pm
   group by persona_id, fecha_inicio, fecha_fin, horas_k
  having count(*) > 1
)
select * from (

  -- ── A · TOTALES POR TABLA ─────────────────────────────────────────────
  select 1 as orden, 'TOTAL'::text as tabla,
         'filas vivas en rrhh_evento (sin anuladas)'::text as detalle,
         ''::text as fechas,
         (select count(*) from ev)::int as filas,
         ''::text as estados,
         'informativo'::text as veredicto
  union all
  select 2, 'TOTAL', 'filas vivas en rrhh_permiso (sin canceladas)', '',
         (select count(*) from pm)::int, '', 'informativo'
  union all

  -- ── B · EL RESUMEN QUE DECIDE ─────────────────────────────────────────
  select 3, 'RESUMEN', 'grupos repetidos en rrhh_evento que la proteccion RECHAZARIA', '',
         (select count(*) from ev_grupo where vivas >= 2)::int, '',
         case when (select count(*) from ev_grupo where vivas >= 2) = 0
              then 'cero: la proteccion puede entrar sin limpiar nada'
              else 'HAY QUE LIMPIARLOS ANTES (o la proteccion no puede ser constraint)' end
  union all
  select 4, 'RESUMEN', 'grupos repetidos en rrhh_evento LEGITIMOS (a lo sumo 1 viva)', '',
         (select count(*) from ev_grupo where vivas < 2)::int, '',
         'tienen que seguir permitidos (rechazada y vuelta a pedir)'
  union all
  select 5, 'RESUMEN', 'grupos repetidos en rrhh_permiso que la proteccion RECHAZARIA', '',
         (select count(*) from pm_grupo where vivas >= 2)::int, '',
         case when (select count(*) from pm_grupo where vivas >= 2) = 0
              then 'cero: la proteccion puede entrar sin limpiar nada'
              else 'HAY QUE LIMPIARLOS ANTES' end
  union all
  select 6, 'RESUMEN', 'grupos repetidos en rrhh_permiso LEGITIMOS (a lo sumo 1 viva)', '',
         (select count(*) from pm_grupo where vivas < 2)::int, '',
         'tienen que seguir permitidos'
  union all

  -- ── C · EL DETALLE, un renglon por grupo repetido ──────────────────────
  select 10, 'rrhh_evento', g.nombre || ' · ' || g.tipo, g.fecha::text,
         g.filas::int, g.estados,
         case when g.vivas >= 2 then 'RECHAZARIA · ' || g.vivas || ' vivas'
              else 'legitimo · ' || g.vivas || ' viva' end
    from ev_grupo g
  union all
  select 11, 'rrhh_permiso', g.nombre || ' · permiso'
           || case when g.horas_k >= 0 then ' (' || g.horas_k || ' h)' else ' (dia completo)' end,
         g.fecha_inicio::text
           || case when g.fecha_fin > g.fecha_inicio then ' al ' || g.fecha_fin::text else '' end,
         g.filas::int, g.estados,
         case when g.vivas >= 2 then 'RECHAZARIA · ' || g.vivas || ' vivas'
              else 'legitimo · ' || g.vivas || ' viva' end
    from pm_grupo g

) t order by t.orden, t.detalle;
