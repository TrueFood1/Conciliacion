-- ════════════════════════════════════════════════════════════════════
-- PRUEBA D1 · CARRIL A
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
-- EXTRAIDO POR CONTENIDO de CAMBIO_DEVOLUCIONES.sql (lineas 559-566 del original, al
-- 17-sep-2026). El numero de linea NO es la llave: el bloque se localizo
-- por su par begin/rollback y su encabezado, y despues se VERIFICO
-- reensamblandolo y comparandolo con el original caracter por caracter.
-- Es la leccion del 16-sep, cuando un `sed -n '141,476p'` entrego el
-- pedazo equivocado y se pego P0-a creyendo que era otra cosa.
-- sha256[12] del cuerpo: fd5b40673b7a
-- ════════════════════════════════════════════════════════════════════
-- D1 · ESPERADO: **ERROR** de `ent_devolucion_causa_ok` — causa fuera de lista.
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por)
  values (current_date, 'manual', 'regalia', 'prueba-d1');
  insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, causa, creado_por)
  select current_date, 999999, 'PRUEBA d1', id, 'se_mojo', 'prueba-d1'
    from ent_pedido where creado_por = 'prueba-d1';
  select 'D1 MAL: entro una causa inventada' as resultado;
