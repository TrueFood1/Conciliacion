-- ════════════════════════════════════════════════════════════════════
-- PRUEBA D3-bis · CARRIL A
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
-- EXTRAIDO POR CONTENIDO de CAMBIO_DEVOLUCIONES.sql (lineas 596-603 del original, al
-- 17-sep-2026). El numero de linea NO es la llave: el bloque se localizo
-- por su par begin/rollback y su encabezado, y despues se VERIFICO
-- reensamblandolo y comparandolo con el original caracter por caracter.
-- Es la leccion del 16-sep, cuando un `sed -n '141,476p'` entrego el
-- pedazo equivocado y se pego P0-a creyendo que era otra cosa.
-- sha256[12] del cuerpo: d98481c174ac
-- ════════════════════════════════════════════════════════════════════
-- D3-bis · ESPERADO: **ERROR** — causa 'otro' con nota NULL.
--      Sin el `coalesce` del CHECK esta fila ENTRARIA: `length(btrim(null)) >= 6`
--      da NULL, la conjuncion queda NULL y Postgres deja pasar. Es el hueco
--      medido el 14-ago en ent_alisto_linea_no_entrega_ok. Si D3 da error y
--      D3-bis pasa, alguien saco los coalesce.
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por)
  values (current_date, 'manual', 'regalia', 'prueba-d3b');
  insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, causa, creado_por)
  select current_date, 999999, 'PRUEBA d3b', id, 'otro', 'prueba-d3b'
    from ent_pedido where creado_por = 'prueba-d3b';
  select 'D3-bis MAL: entro otro sin nota — se perdio el coalesce' as resultado;
