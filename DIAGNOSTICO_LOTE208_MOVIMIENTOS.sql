-- ════════════════════════════════════════════════════════════════════════
-- LOTE Pan Blanco 208 / 1-27 · movimiento por movimiento.  SOLO LECTURA.
-- Suelta, para pegar sola: el editor de Supabase muestra un solo resultado.
--
-- CÓMO LEERLA
--   · Un renglón por movimiento, en orden cronológico, hora de Costa Rica.
--   · `delta` es lo que suma o resta ese movimiento.
--   · `saldo` es el acumulado DESPUÉS de ese movimiento.
--   · `marca` pone 🔴 en el primer renglón que cruza a negativo.
--   · `detalle` rotula con ⚠ ESCRITO POR SQL lo que no entró por la pantalla.
--
-- PARA CRUZAR CONTRA EL EXCEL DE DANIEL: el ancla del 14-ago son 126 u (21 cajas,
-- de `CONTEO_14AGO.sql`). El Excel suma 113 de salidas + 6 de Mentha = 119, que
-- daría saldo +7. Truefie viene dando −4, o sea 130 de salidas: 11 de diferencia.
-- Los renglones de abajo son los 130 desglosados — la diferencia tiene que estar
-- en uno de ellos, o en la fila del Excel que todavía no aparece.
-- ════════════════════════════════════════════════════════════════════════

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
