-- ════════════════════════════════════════════════════════════════════
-- PRUEBA D8 · CARRIL B
--
-- ⚠️ ESTE ARCHIVO NO SE PEGA EN EL EDITOR DE SQL. Es la ENTRADA de
--    pg_pruebas.py, que le pone el sobre (begin / rollback) y, si el
--    carril es B, tambien la identidad. Por eso NO lleva begin, ni
--    rollback, ni un solo `set`: el SQL de entrada tiene PROHIBIDO todo
--    control de transaccion (begin, commit, rollback, savepoint) y toda
--    palabra que cambie quien corre (set, set_config, reset, call, do).
--    El sobre y la identidad son de la herramienta, nunca de la prueba.
--
-- CARRIL B · como usuario real, NO saltea nada. Prueba reglas de PERMISO.
--
-- 🔴 D8 NECESITA CORRERSE DOS VECES, CON DOS IDENTIDADES. Tal como esta
--    escrita mide DOS cosas a la vez y hay que separarlas, o vuelve el
--    problema de fallar por el motivo de al lado:
--      · con el usuario de prueba (perfil 'equipo'):
--          ESPERADO **ERROR 42501** en el insert a `ent_odoo_hecho`
--          ("new row violates row-level security policy"). Es la prueba
--          de PERMISO: `ent_odoo_hecho_ins` exige `acceso_es_socia()`.
--          La cola NO se vacia, y no tiene que vaciarse.
--      · con una socia (forjando el correo de Andrea, que ya esta en
--        `acceso_usuario`):
--          ESPERADO lo que dice el encabezado original: antes 1, despues 0.
--          Es la prueba de CONTENIDO: la cola se vacia al marcar hecho.
--    El 16-sep esta prueba paso en verde desde el SQL Editor SIN ejercitar
--    `acceso_es_socia()`, porque `postgres` saltea la RLS. Ese es el
--    agujero que H3 vino a tapar; correrla con una sola identidad lo deja
--    abierto en el lugar nuevo.
--    ⚠️ Si B0 no dio `filas_visibles = 1`, esta prueba no significa nada.
--
-- EXTRAIDO POR CONTENIDO de CAMBIO_DEVOLUCIONES.sql (lineas 684-694 del original, al
-- 17-sep-2026). El numero de linea NO es la llave: el bloque se localizo
-- por su par begin/rollback y su encabezado, y despues se VERIFICO
-- reensamblandolo y comparandolo con el original caracter por caracter.
-- Es la leccion del 16-sep, cuando un `sed -n '141,476p'` entrego el
-- pedazo equivocado y se pego P0-a creyendo que era otra cosa.
-- sha256[12] del cuerpo: 460603bae855
-- ════════════════════════════════════════════════════════════════════
-- D8 · §C · la cola se VACIA al marcar hecho.
--      ESPERADO: la primera consulta 1 fila, la segunda 0 filas.
--      ⚠️ Si el insert en ent_odoo_hecho da "new row violates row-level security",
--      la sesion no es de una socia: es lo correcto, pero entonces esta prueba hay
--      que correrla con una sesion que lo sea, o desde el SQL Editor (postgres
--      saltea la RLS).
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por)
  values (current_date, 'manual', 'consumo_interno', 'prueba-d8');
  insert into ent_odoo_pendiente (tipo, pedido_id, fecha, destinatario, creado_por)
  select 'traslado_interno', id, current_date, 'Cocina', 'prueba-d8'
    from ent_pedido where creado_por = 'prueba-d8';
  select count(*) as antes_debe_ser_1 from v_ent_odoo_pendiente where creado_por = 'prueba-d8';
  insert into ent_odoo_hecho (pendiente_id, referencia, creado_por)
  select id, 'WH/INT/00001', 'prueba-d8' from ent_odoo_pendiente where creado_por = 'prueba-d8';
  select count(*) as despues_debe_ser_0 from v_ent_odoo_pendiente where creado_por = 'prueba-d8';
