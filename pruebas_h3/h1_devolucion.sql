-- PRUEBA H1 · CARRIL A · ¿anular la salida deja algo inconsistente si el
-- pedido YA tiene una devolucion vigente?
-- Se fabrica el escenario: hoy no hay ninguna viva (la unica, la 12, esta anulada).
-- Pedido 132 · alisto 88 · salida 77 · Supermercados Unidos.
select 'ANTES' as t, lote, producto_id, uds from ent_salido_del_congelador_desde_ancla
 where producto_id=453 and lote='237 / 2-27';

-- 1 · una devolucion vigente colgada del pedido 132
insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, causa, creado_por)
select current_date, p.cliente_id, p.cliente_nombre, 132, 'producto_equivocado', 'prueba-h1'
  from ent_pedido p where p.id=132;
insert into ent_devolucion_linea (devolucion_id, producto_id, lote, cant_uds, uom_id, uom_nombre, cant_uom, uom_factor)
select d.id, 453, '237 / 2-27', 24, 37, 'Paquete de 4', 6, 4
  from ent_devolucion d where d.creado_por='prueba-h1';

select 'con devolucion, salida VIGENTE' as t,
       (select count(*) from ent_devolucion_vigente where pedido_id=132) as dev_vigente,
       (select uds from ent_salido_del_congelador_desde_ancla where producto_id=453 and lote='237 / 2-27') as salio,
       (select uds from ent_devuelto_desde_ancla where producto_id=453 and lote='237 / 2-27') as devuelto,
       (select estado from v_ent_pedido_estado where pedido_id=132) as estado;

-- 2 · ahora se anula la salida
insert into ent_anulacion (entidad, entidad_id, motivo, creado_por)
values ('salida', 77, 'prueba-h1 (rollback)', 'prueba-h1');

select 'con devolucion, salida ANULADA' as t,
       (select count(*) from ent_devolucion_vigente where pedido_id=132) as dev_vigente,
       (select uds from ent_salido_del_congelador_desde_ancla where producto_id=453 and lote='237 / 2-27') as salio,
       (select uds from ent_devuelto_desde_ancla where producto_id=453 and lote='237 / 2-27') as devuelto,
       (select estado from v_ent_pedido_estado where pedido_id=132) as estado;

-- 3 · lo que veria la pantalla: un pedido "preparado, sin salir" con una
--     devolucion colgando, y su NC ya en la cola de Odoo.
select 'lo que queda visible' as t,
       (select count(*) from ent_devolucion_vigente where pedido_id=132) as dev_sigue_visible,
       (select count(*) from ent_odoo_pendiente where pedido_id=132) as nc_en_cola;
