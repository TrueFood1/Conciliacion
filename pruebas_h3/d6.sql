-- ════════════════════════════════════════════════════════════════════
-- PRUEBA D6 · CARRIL A
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
-- EXTRAIDO POR CONTENIDO de CAMBIO_DEVOLUCIONES.sql (lineas 652-656 del original, al
-- 17-sep-2026). El numero de linea NO es la llave: el bloque se localizo
-- por su par begin/rollback y su encabezado, y despues se VERIFICO
-- reensamblandolo y comparandolo con el original caracter por caracter.
-- Es la leccion del 16-sep, cuando un `sed -n '141,476p'` entrego el
-- pedazo equivocado y se pego P0-a creyendo que era otra cosa.
-- sha256[12] del cuerpo: ffe28979c764
-- ════════════════════════════════════════════════════════════════════
-- D6 · §C · ESPERADO: **ERROR** de `ent_odoo_pendiente_forma_ok`.
--      Una nota de credito sin devolucion no es una nota de credito.
  insert into ent_odoo_pendiente (tipo, fecha, cliente_id, cliente_nombre, factura_id, creado_por)
  values ('nota_credito', current_date, 999999, 'PRUEBA d6', 4321, 'prueba-d6');
  select 'D6 MAL: entro una NC sin devolucion' as resultado;
