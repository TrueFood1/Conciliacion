-- ════════════════════════════════════════════════════════════════════
-- PRUEBA D3 · CARRIL A
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
-- EXTRAIDO POR CONTENIDO de CAMBIO_DEVOLUCIONES.sql (lineas 582-589 del original, al
-- 17-sep-2026). El numero de linea NO es la llave: el bloque se localizo
-- por su par begin/rollback y su encabezado, y despues se VERIFICO
-- reensamblandolo y comparandolo con el original caracter por caracter.
-- Es la leccion del 16-sep, cuando un `sed -n '141,476p'` entrego el
-- pedazo equivocado y se pego P0-a creyendo que era otra cosa.
-- sha256[12] del cuerpo: c815420e50b2
-- ════════════════════════════════════════════════════════════════════
-- D3 · ESPERADO: **ERROR** — causa 'otro' con nota de 3 caracteres (minimo 6).
--      ⚠️ Y ESTA ES LA QUE CAZA EL HUECO DEL NULL: si se "arregla" el CHECK
--      sacando los coalesce, esta prueba sigue dando error pero D3-bis no.
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por)
  values (current_date, 'manual', 'regalia', 'prueba-d3');
  insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, causa, nota, creado_por)
  select current_date, 999999, 'PRUEBA d3', id, 'otro', 'abc', 'prueba-d3'
    from ent_pedido where creado_por = 'prueba-d3';
  select 'D3 MAL: entro otro con nota corta' as resultado;
