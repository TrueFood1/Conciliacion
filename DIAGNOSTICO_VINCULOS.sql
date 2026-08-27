-- ════════════════════════════════════════════════════════════════════════
-- DIAGNÓSTICO · ¿por qué "Salida de venta, sin factura vinculada" no se vacía?
-- 26-ago-2026.  SOLO LECTURA — no inserta, no actualiza, no borra.
--
-- POR QUÉ HACE FALTA CORRERLO A MANO: las 13 tablas y vistas de Entregas están
-- bajo RLS y con la anon key devuelven 0 filas. Desde afuera de una sesión no se
-- puede ver ni un despacho. Pegar en el SQL editor de Supabase, que corre como
-- dueño, y pasarme la salida.
--
-- LA HIPÓTESIS QUE VIENE A CONFIRMAR (leída del código, no de los datos):
-- el vínculo vive en `ent_pedido_factura` (ENTREGAS_SALIDAS.sql §2 declara
-- `ent_pedido.factura_id` OBSOLETA). Pero el ÚNICO lugar del código que escribe
-- en esa tabla es el botón manual "Vincular" de Pendientes: `despConfirmar()`
-- —el flujo normal, que crea el pedido A PARTIR de una factura— nunca la
-- escribe, y los dos cargues retroactivos tampoco. Si es así, TODO pedido de
-- venta cae en la lista aunque el sistema sepa perfectamente cuál es su factura.
-- ════════════════════════════════════════════════════════════════════════

-- ── 1 · LA LISTA, con lo que el pedido YA SABE de su factura ─────────────
-- La columna clave es `factura_id_en_la_fila`. Si viene llena, no hay nada que
-- adivinar: el sistema ya sabe la factura y solo le falta el vínculo.
select p.id                    as despacho,
       p.fecha_despacho,
       p.cliente_id,
       p.cliente_nombre,
       p.motivo,
       p.factura_id            as factura_id_en_la_fila,
       p.factura_nombre        as factura_en_la_fila,
       p.origen,
       p.creado_por,
       p.creado_en
  from ent_pedido p
  left join ent_pedido_factura_vigente v
         on v.pedido_id = p.id and v.anulado = false
 where p.motivo = 'venta'
   and v.pedido_id is null
 order by p.fecha_despacho, p.id;

-- ── 2 · EL RESUMEN de una línea: ¿cuántas saben su factura y cuántas no? ──
select count(*)                                          as sin_vinculo_total,
       count(p.factura_id)                               as ya_saben_su_factura,
       count(*) - count(p.factura_id)                    as sin_factura_conocida
  from ent_pedido p
  left join ent_pedido_factura_vigente v
         on v.pedido_id = p.id and v.anulado = false
 where p.motivo = 'venta'
   and v.pedido_id is null;

-- ── 3 · LAS CANTIDADES de cada despacho sin vínculo ──────────────────────
-- Para cruzar contra Odoo producto por producto. Solo hace falta si el punto 2
-- devuelve `sin_factura_conocida` > 0.
select p.id as despacho, p.fecha_despacho, p.cliente_nombre,
       l.producto_id, l.cant_uds, l.cant_uom, l.uom_id, l.uom_nombre
  from ent_pedido p
  join ent_pedido_linea l on l.pedido_id = p.id
  left join ent_pedido_factura_vigente v
         on v.pedido_id = p.id and v.anulado = false
 where p.motivo = 'venta'
   and v.pedido_id is null
 order by p.fecha_despacho, p.id, l.producto_id;

-- ── 4 · LA OTRA SECCIÓN · "Entregado en Truefie, sin validar en Odoo" ────
-- Trae cliente y fecha para cruzar contra el estado real del `stock.picking`,
-- que ya está medido en Odoo (ver el informe del 26-ago).
select p.id as despacho, p.fecha_despacho, p.cliente_id, p.cliente_nombre,
       a.creado_en as preparado_en,
       s.salida_en
  from ent_pedido p
  join ent_alisto a on a.pedido_id = p.id and a.anulado = false
  left join ent_pedido_valida_vigente vv
         on vv.pedido_id = p.id and vv.anulado = false
  left join ent_salida s on s.alisto_id = a.id
 where vv.pedido_id is null
 order by p.fecha_despacho, p.id;

-- ── 5 · ¿HAY FACTURAS VINCULADAS DOS VECES? ─────────────────────────────
-- ENTREGAS_SALIDAS.sql avisa que no hay índice único que lo impida y que se
-- valida en la app. Antes de vincular en bloque conviene saber si ya pasó.
select factura_id, factura_nombre, count(*) as veces,
       array_agg(pedido_id order by pedido_id) as pedidos
  from ent_pedido_factura_vigente
 where anulado = false
 group by factura_id, factura_nombre
having count(*) > 1
 order by factura_id;
