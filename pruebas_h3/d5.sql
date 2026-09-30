-- ════════════════════════════════════════════════════════════════════
-- PRUEBA D5 · CARRIL A
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
-- EXTRAIDO POR CONTENIDO de CAMBIO_DEVOLUCIONES.sql (lineas 623-648 del original, al
-- 17-sep-2026). El numero de linea NO es la llave: el bloque se localizo
-- por su par begin/rollback y su encabezado, y despues se VERIFICO
-- reensamblandolo y comparandolo con el original caracter por caracter.
-- Es la leccion del 16-sep, cuando un `sed -n '141,476p'` entrego el
-- pedazo equivocado y se pego P0-a creyendo que era otra cosa.
-- sha256[12] del cuerpo: c3c7067c6d0b
-- ════════════════════════════════════════════════════════════════════
-- D5 · §B · la vista del exceso MARCA y NO BLOQUEA.
--      ESPERADO: PASA, y la ultima consulta devuelve UNA fila con uds_exceso > 0.
--      Construye su propio pedido con alisto, saca 6 y devuelve 10.
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por)
  values (current_date, 'manual', 'regalia', 'prueba-d5');
  insert into ent_alisto (pedido_id, responsable, creado_por)
  select id, 'prueba-d5', 'prueba-d5' from ent_pedido where creado_por = 'prueba-d5';
  insert into ent_alisto_linea (alisto_id, producto_id, cant_uds, cant_uom)
  select id, 451, 6, 6 from ent_alisto where creado_por = 'prueba-d5';
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden)
  select l.id, '100 / 1-27', 6, 0
    from ent_alisto_linea l join ent_alisto a on a.id = l.alisto_id
   where a.creado_por = 'prueba-d5';

  -- vuelven DIEZ de un lote del que salieron SEIS: entra igual.
  insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, causa, creado_por)
  select current_date, 999999, 'PRUEBA d5', id, 'producto_equivocado', 'prueba-d5'
    from ent_pedido where creado_por = 'prueba-d5';
  insert into ent_devolucion_linea
    (devolucion_id, producto_id, lote, cant_uds, uom_id, uom_nombre, cant_uom, uom_factor)
  select id, 451, '100 / 1-27', 10, 1, 'Unidades', 10, 1
    from ent_devolucion where creado_por = 'prueba-d5';

  -- ESPERADO: 1 fila · uds_salio 6 · uds_volvio 10 · uds_exceso 4
  select e.* from v_ent_devolucion_exceso e
    join ent_pedido p on p.id = e.pedido_id
   where p.creado_por = 'prueba-d5';
