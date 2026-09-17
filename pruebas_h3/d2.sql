-- ════════════════════════════════════════════════════════════════════
-- PRUEBA D2 · CARRIL A
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
-- EXTRAIDO POR CONTENIDO de CAMBIO_DEVOLUCIONES.sql (lineas 570-577 del original, al
-- 17-sep-2026). El numero de linea NO es la llave: el bloque se localizo
-- por su par begin/rollback y su encabezado, y despues se VERIFICO
-- reensamblandolo y comparandolo con el original caracter por caracter.
-- Es la leccion del 16-sep, cuando un `sed -n '141,476p'` entrego el
-- pedazo equivocado y se pego P0-a creyendo que era otra cosa.
-- sha256[12] del cuerpo: 85995b172d9a
-- ════════════════════════════════════════════════════════════════════
-- D2 · ESPERADO: **ERROR** — con pedido y SIN causa. Es el espejo de P0-b: lo
--      que hoy pasa, despues de §A no tiene que pasar.
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por)
  values (current_date, 'manual', 'regalia', 'prueba-d2');
  insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, creado_por)
  select current_date, 999999, 'PRUEBA d2', id, 'prueba-d2'
    from ent_pedido where creado_por = 'prueba-d2';
  select 'D2 MAL: entro sin causa' as resultado;
