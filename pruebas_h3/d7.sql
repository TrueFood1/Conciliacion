-- ════════════════════════════════════════════════════════════════════
-- PRUEBA D7 · CARRIL A
--
-- ⚠️ ESTE ARCHIVO NO SE PEGA EN EL EDITOR DE SQL. Es la ENTRADA de
--    pg_pruebas.py, que le pone el sobre (begin / rollback) y, si el
--    carril es B, tambien la identidad. Por eso NO lleva begin, ni
--    rollback, ni un solo `set`: el SQL de entrada tiene PROHIBIDO todo
--    control de transaccion (begin, commit, rollback, savepoint) y toda
--    palabra que cambie quien corre (set, set_config, reset, call, do).
--    El sobre y la identidad son de la herramienta, nunca de la prueba.
--
-- CARRIL A · llave maestra, saltea la RLS. Prueba reglas de CONTENIDO.
--
-- EXTRAIDO POR CONTENIDO de CAMBIO_DEVOLUCIONES.sql (lineas 660-676 del original, al
-- 17-sep-2026). El numero de linea NO es la llave: el bloque se localizo
-- por su par begin/rollback y su encabezado, y despues se VERIFICO
-- reensamblandolo y comparandolo con el original caracter por caracter.
-- Es la leccion del 16-sep, cuando un `sed -n '141,476p'` entrego el
-- pedazo equivocado y se pego P0-a creyendo que era otra cosa.
-- sha256[12] del cuerpo: e24d13fd1ceb
-- ════════════════════════════════════════════════════════════════════
-- D7 · §C · CONTROL · ESPERADO: PASA, y la ultima consulta devuelve 1 fila.
--      Un traslado interno completo, con su linea, aparece en la cola.
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por)
  values (current_date, 'manual', 'consumo_interno', 'prueba-d7');
  insert into ent_odoo_pendiente (tipo, pedido_id, fecha, destinatario, creado_por)
  select 'traslado_interno', id, current_date, 'Cocina', 'prueba-d7'
    from ent_pedido where creado_por = 'prueba-d7';
  insert into ent_odoo_pendiente_linea
    (pendiente_id, producto_id, lote, cant_uds, uom_id, uom_nombre, cant_uom, uom_factor)
  select id, 453, '100 / 1-27', 24, 37, 'Paquete de 4', 6, 0.25
    from ent_odoo_pendiente where creado_por = 'prueba-d7';
  -- ESPERADO: 1 fila. (Y ojo al factor: 6 paq x 4 = 24 uds. Escrito a mano
  -- entraria 4x corto, que es la trampa que §12 documenta.)
  select v.id, v.tipo, v.destinatario, l.producto_id, l.cant_uom, l.uom_factor, l.cant_uds
    from v_ent_odoo_pendiente v
    join ent_odoo_pendiente_linea l on l.pendiente_id = v.id
   where v.creado_por = 'prueba-d7';
