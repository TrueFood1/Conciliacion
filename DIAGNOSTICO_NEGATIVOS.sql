-- ════════════════════════════════════════════════════════════════════════
-- DIAGNÓSTICO · el lote Pan Blanco 208 / 1-27 en −4, y los negativos de todos
-- 27-ago-2026.  **SOLO LECTURA**: ni un insert, ni un update, ni un delete.
-- Pegar como un solo bloque en el editor SQL de Supabase.
--
-- POR QUÉ HACE FALTA ESTO. El saldo por lote se arma con CUATRO puntas y una de
-- ellas —la PRODUCCIÓN— no vive en Postgres: sale del chatter de Odoo y se
-- calcula en el navegador. Así que un "select" solo nunca puede dar el saldo
-- real. Este bloque resuelve eso metiendo a mano, en `prod_odoo`, la producción
-- posterior al corte del ancla ya leída de Odoo el 27-ago (ver el comentario de
-- esa CTE). Con eso las cuatro puntas quedan del mismo lado y el número cierra.
--
-- LO QUE YA SE SABE, VERIFICADO CONTRA ODOO (no hace falta que esto lo confirme):
--   · El lote `208 / 1-27` es WH/MO/01390, `date_start` 27-jul-2026 16:50 CR,
--     126 u. Juliano 208 = 27 de julio. El "1-27" es el VENCIMIENTO (enero 2027),
--     no la fecha de producción.
--   · Esa producción es ANTERIOR al corte del ancla (14-ago 16:00 CR), así que
--     sus 126 u ya están dentro del conteo físico. NO falta producción que sumar:
--     el negativo no es un artefacto de la ventana de 3 meses.
-- ════════════════════════════════════════════════════════════════════════


-- ── 0 · EL ANCLA ────────────────────────────────────────────────────────
-- Confirma contra qué foto se está calculando todo lo de abajo.
select 'ANCLA' as que, id as conteo_id, fecha,
       to_char(corte at time zone 'America/Costa_Rica','DD-Mon-YYYY HH24:MI') as corte_cr
  from ent_ancla;


-- ── 1 · LA CUENTA COMPLETA DEL LOTE 208 / 1-27 (Pan Blanco, 451) ────────
-- Un renglón por movimiento, en orden, con el saldo corriendo al lado. La
-- columna `saldo` es la respuesta a "qué movimiento lo cruzó a negativo": es el
-- primer renglón donde se pone < 0.
with a as (select id, fecha, corte from ent_ancla),
mov as (
  select (select corte from a)                       as cuando,
         '1 · ANCLA'                                 as tipo,
         null::bigint                                as despacho,
         'conteo físico del ' || (select fecha::text from a) as detalle,
         null::text                                  as quien,
         sum(cl.uds)                                 as delta
    from ent_conteo_linea cl
   where cl.conteo_id = (select id from a)
     and cl.producto_id = 451 and cl.lote = '208 / 1-27'
   having sum(cl.uds) is not null

  union all

  -- Se descuenta al PREPARAR, no al entregar: `preparado_en` es la fecha buena.
  select av.preparado_en, '2 · SALIDA', av.pedido_id,
         coalesce(p.cliente_nombre,'—')
           || ' · ' || coalesce(fv.factura_nombre,'sin factura')
           || case when al2.creado_por like 'correccion-sql%'
                     or al2.creado_por like '%backfill%'
                   then '  ⚠ ESCRITO POR SQL (' || al2.creado_por || ')'
                   else '' end,
         av.responsable, -sum(al.cant_uds)
    from ent_alisto_lote    al
    join ent_alisto_linea   ali on ali.id       = al.linea_id
    join ent_alisto_vigente av  on av.alisto_id = ali.alisto_id
    join ent_alisto         al2 on al2.id       = av.alisto_id
    join ent_pedido         p   on p.id         = av.pedido_id
    left join ent_pedido_factura_vigente fv
           on fv.pedido_id = p.id and fv.anulado = false
   where ali.producto_id = 451 and al.lote = '208 / 1-27'
   group by av.preparado_en, av.pedido_id, p.cliente_nombre, fv.factura_nombre,
            av.responsable, al2.creado_por

  union all

  select dv.recibido_en, '3 · DEVOLUCIÓN', null,
         dv.cliente_nombre, dv.creado_por, sum(dl.cant_uds)
    from ent_devolucion_linea   dl
    join ent_devolucion_vigente dv on dv.devolucion_id = dl.devolucion_id
   where dl.producto_id = 451 and dl.lote = '208 / 1-27'
   group by dv.recibido_en, dv.cliente_nombre, dv.creado_por
)
select to_char(cuando at time zone 'America/Costa_Rica','DD-Mon HH24:MI') as cuando_cr,
       tipo, despacho, detalle, quien, delta,
       sum(delta) over (order by cuando, tipo
                        rows between unbounded preceding and current row) as saldo,
       case when sum(delta) over (order by cuando, tipo
                        rows between unbounded preceding and current row) < 0
            then '🔴 ACÁ CRUZA' else '' end as marca
  from mov
 order by cuando, tipo;


-- ── 1b · TODO LO QUE SE ESCRIBIÓ DE ESE LOTE, INCLUIDO LO ANULADO ───────
-- La consulta de arriba usa `ent_alisto_vigente` y por definición NO muestra lo
-- anulado. Acá está el rastro completo: si un alisto se anuló y se re-registró
-- (el despacho 11 del 26-ago), se ven los dos.
select al2.id as alisto_id, al2.pedido_id,
       to_char(al2.creado_en at time zone 'America/Costa_Rica','DD-Mon HH24:MI') as creado_cr,
       al2.responsable, al2.creado_por,
       al.cant_uds,
       case when exists (select 1 from ent_anulacion x
                          where x.entidad='alisto' and x.entidad_id=al2.id)
            then '⛔ ANULADO' else 'vigente' end as estado,
       left(coalesce(al2.nota,''),90) as nota
  from ent_alisto_lote   al
  join ent_alisto_linea  ali on ali.id = al.linea_id
  join ent_alisto        al2 on al2.id = ali.alisto_id
 where ali.producto_id = 451 and al.lote = '208 / 1-27'
 order by al2.creado_en;


-- ── 4 · TODOS LOS LOTES EN NEGATIVO, LOS SEIS PRODUCTOS ─────────────────
-- Con las CUATRO puntas. `prod_odoo` es la producción con `date_start` POSTERIOR
-- al corte del ancla, leída de Odoo el 27-ago-2026 (mrp.production `done` +
-- el lote del chatter). Es lo único que Postgres no puede saber solo.
--   WH/MO/01414 Blanco 230 / 2-27  126     WH/MO/01416+01417 Francés 232 / 2-27  180
--   WH/MO/01415 Blanco 231 / 2-27  126     WH/MO/01424       Francés 237 / 2-27  150
--   WH/MO/01420 Blanco 236 / 2-27  168     WH/MO/01428       Buns    238 / 2-27  750
--   WH/MO/01411 Galletas 226 / 2-27 → 0 A PROPÓSITO: está en ENT_MO_EXCLUIDAS.
--   Se registró 6 min después del corte pero el pan ya estaba contado en el
--   físico; sumarla lo contaría dos veces (el saldo daba 316 y el bueno es 156).
with a as (select id, corte from ent_ancla),
prod_odoo(producto_id, lote, uds) as (values
  (451,'230 / 2-27',126::numeric), (451,'231 / 2-27',126), (451,'236 / 2-27',168),
  (453,'232 / 2-27',180),          (453,'237 / 2-27',150),
  (503,'238 / 2-27',750),
  (519,'226 / 2-27',0)
),
ancla as (
  select cl.producto_id, cl.lote, sum(cl.uds) as uds
    from ent_conteo_linea cl
   where cl.conteo_id = (select id from a)
   group by 1,2
),
salidas as (
  select ali.producto_id, al.lote, sum(al.cant_uds) as uds
    from ent_alisto_lote    al
    join ent_alisto_linea   ali on ali.id       = al.linea_id
    join ent_alisto_vigente av  on av.alisto_id = ali.alisto_id
   where av.preparado_en > (select corte from a)
   group by 1,2
),
devol as (
  select dl.producto_id, dl.lote, sum(dl.cant_uds) as uds
    from ent_devolucion_linea   dl
    join ent_devolucion_vigente dv on dv.devolucion_id = dl.devolucion_id
   where dv.recibido_en > (select corte from a)
   group by 1,2
),
claves as (
  select producto_id, lote from ancla
  union select producto_id, lote from prod_odoo
  union select producto_id, lote from salidas
  union select producto_id, lote from devol
)
select case k.producto_id when 451 then 'Pan Blanco' when 452 then 'Pan de Semillas'
            when 453 then 'Pan Francés' when 472 then 'Pizza Crust'
            when 503 then 'Buns' when 519 then 'Galletas'
            else '#'||k.producto_id end                       as producto,
       k.lote,
       coalesce(an.uds,0) as ancla,
       coalesce(po.uds,0) as produccion,
       coalesce(sa.uds,0) as salidas,
       coalesce(de.uds,0) as devoluciones,
       coalesce(an.uds,0)+coalesce(po.uds,0)-coalesce(sa.uds,0)+coalesce(de.uds,0) as saldo
  from claves k
  left join ancla     an on an.producto_id=k.producto_id and an.lote=k.lote
  left join prod_odoo po on po.producto_id=k.producto_id and po.lote=k.lote
  left join salidas   sa on sa.producto_id=k.producto_id and sa.lote=k.lote
  left join devol     de on de.producto_id=k.producto_id and de.lote=k.lote
 where coalesce(an.uds,0)+coalesce(po.uds,0)-coalesce(sa.uds,0)+coalesce(de.uds,0) < 0
 order by 7, 1, 2;
-- CERO FILAS = ningún negativo. Si sale el 208 / 1-27 solo, el problema está
-- acotado a ese lote. Si salen otros, hay un patrón y hay que buscarlo.
