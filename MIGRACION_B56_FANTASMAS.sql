-- ════════════════════════════════════════════════════════════════════════
-- b56 · MIGRACION 3.7 · las seis filas fantasma pasan a NO DETERMINADO
-- NO PEGAR antes que ENTREGAS_INDETERMINADO.sql: esto escribe en una tabla que
-- ese archivo crea, y depende de su trigger y de sus checks.
-- Append-only, con guarda: se puede correr dos veces sin danio.
--
-- ── QUE SE MIGRA, MEDIDO EL 8-SEP ───────────────────────────────────────
-- SEIS filas de ent_alisto_lote, en DOS ortografias que la base trata como dos
-- lotes distintos. La lista es EXPLICITA ('sin lote' y 'Sin lote'), no un
-- `!~ regex`: un regex arrastraria tambien el '183 - 12/26', que NO se migra.
--
--   pedido 55 · Automercado, factura 3516, 7-sep     → chofer_no_reporto
--       Pan Blanco  102 unidades (17 cajas)          'sin lote'
--   pedido 56 · summit, 2-sep                        → no_se_anoto
--       Buns          2 paquetes                     'sin lote'
--       Pan Blanco    2 unidades                     'sin lote'
--       Semillas      2 unidades                     'sin lote'
--       Pan Frances   2 paquetes                     'sin lote'
--   pedido 48 · Carne M D L, factura 3520, 8-sep     → sticker_caido
--       Pan Blanco    1 unidad                       'Sin lote'
--
-- ── LO QUE NO SE MIGRA, Y POR QUE ───────────────────────────────────────
-- '183 - 12/26' (pedido 2, 18-ago, Pizza Crust, 42 paquetes) es un lote REAL mal
-- transcrito, no una excepcion. Su alisto (id 1) fue reemplazado por el 12
-- (`correccion-sql`, 20-ago) y se verifico que la cadena NO aparece en
-- `ent_salido_del_congelador_desde_ancla`: no mueve ningun numero. Queda quieta.
-- Decision de Andrea, 8-sep.
--
-- ── EL PEDIDO 48 NO SE MUEVE ────────────────────────────────────────────
-- Esta PREPARADO y sin salida. Esto le cambia el lote efectivo y NADA MAS: no le
-- inventa salida, no le toca el estado, no lo saca de "Por entregar". Se verifica.
-- ════════════════════════════════════════════════════════════════════════


-- ── 0 · LA FOTO DE ANTES. Correr con el lector de solo lectura ANTES de migrar,
--      para poder probar despues que ningun lote REAL se movio.
--      (esto no escribe nada; se deja aca para que quede junto)
select ali.producto_id, al.lote, sum(al.cant_uds) as suma
  from ent_alisto_lote al
  join ent_alisto_linea ali on ali.id = al.linea_id
 where al.lote ~ '^\d{1,3} / \d{1,2}-\d{2}$'
 group by ali.producto_id, al.lote
 order by ali.producto_id, al.lote;


-- ── 1 · ANTES DE ESCRIBIR: las seis filas, y solo las seis ───────────────
-- ESPERADO: 6 filas — cinco 'sin lote' (una del pedido 55, cuatro del 56) y una
-- 'Sin lote' (pedido 48). Si aparece otra cosa, NO SEGUIR.
select alt.id as alisto_lote_id, a.pedido_id, ali.producto_id,
       '[' || alt.lote || ']' as cadena_exacta, alt.cant_uds
  from ent_alisto_lote alt
  join ent_alisto_linea ali on ali.id = alt.linea_id
  join ent_alisto a on a.id = ali.alisto_id
 where alt.lote in ('sin lote','Sin lote')
 order by a.pedido_id, ali.producto_id;


-- ── 2 · LA MIGRACION ─────────────────────────────────────────────────────
-- El motivo va por PEDIDO, uno cada uno, como los confirmo Andrea. No se
-- generaliza ni se adivina: los tres pedidos estan nombrados a mano.
insert into ent_alisto_lote_correccion
       (alisto_lote_id, lote, motivo, nota, creado_por)
select alt.id,
       'NO DETERMINADO',
       m.motivo,
       m.nota,
       'correccion-sql · b56 · andrea@truefoodcr.com'
  from ent_alisto_lote alt
  join ent_alisto_linea ali on ali.id = alt.linea_id
  join ent_alisto a on a.id = ali.alisto_id
  join (values
    (55, 'chofer_no_reporto',
         'Migracion b56: la entrega de Automercado del 7-sep se cerro escribiendo '
         || '"sin lote" a mano, antes de que existiera esta opcion. El chofer no '
         || 'reporto los lotes. Confirmado por Andrea el 8-sep.'),
    (56, 'no_se_anoto',
         'Migracion b56: el traslado del summit del 2-sep se cerro escribiendo '
         || '"sin lote" a mano, antes de que existiera esta opcion. Los lotes no se '
         || 'anotaron al momento. Confirmado por Andrea el 8-sep.'),
    (48, 'sticker_caido',
         'Migracion b56: la factura 3520 del 8-sep se cerro escribiendo "Sin lote" a '
         || 'mano, antes de que existiera esta opcion. Se cayo el sticker de la caja. '
         || 'Confirmado por Andrea el 8-sep.')
  ) as m(pedido_id, motivo, nota) on m.pedido_id = a.pedido_id
 where alt.lote in ('sin lote','Sin lote')
   and not exists (select 1 from ent_alisto_lote_correccion c
                    where c.alisto_lote_id = alt.id);
-- ESPERADO: INSERT 0 6. Si dice 0, ya estaba migrado. Si dice otro numero, PARAR.


-- ── 3 · VERIFICACION, en el mismo pegado ─────────────────────────────────
-- 3a · el balde por producto, EN UNIDAD DE VENTA. La conversion va adentro del SQL
--      para que nadie deshaga un factor de memoria.
with pres(producto_id, nombre, div, rotulo) as (values
  (451,'Pan Blanco',1,'unidades'), (452,'Pan de Semillas',1,'unidades'),
  (453,'Pan Frances',4,'paquetes'), (472,'Pizza Crust',2,'paquetes'),
  (503,'Buns',4,'paquetes'), (519,'Galletas',1,'unidades'))
select pres.nombre as producto, al.lote,
       round(sum(al.cant_uds) / pres.div, 3) as cantidad,
       pres.rotulo as unidad
  from ent_alisto_lote_efectivo al
  join ent_alisto_linea ali on ali.id = al.linea_id
  join pres on pres.producto_id = ali.producto_id
 where al.lote !~ '^\d{1,3} / \d{1,2}-\d{2}$'
 group by pres.nombre, pres.rotulo, pres.div, al.lote
 order by pres.nombre, al.lote;
-- ESPERADO, y nada mas que esto:
--     Pan Blanco       NO DETERMINADO   105 unidades
--     Pan de Semillas  NO DETERMINADO     2 unidades
--     Pan Frances      NO DETERMINADO     2 paquetes
--     Buns             NO DETERMINADO     2 paquetes
--     Pizza Crust      183 - 12/26       42 paquetes   ← la que se deja quieta
-- Si sigue apareciendo 'sin lote' o 'Sin lote', la migracion no llego a la vista.

-- 3b · el pedido 48 sigue PREPARADO y sin salida.
select pedido_id, cliente_nombre, factura_nombre, estado, n_lineas, salida_en
  from v_ent_pedido_estado
 where pedido_id = 48;

-- 3c · NINGUN LOTE REAL SE MOVIO: esta consulta tiene que dar EXACTAMENTE lo mismo
--      que la foto del paso 0. Es la misma consulta, pero sobre el lote EFECTIVO.
select ali.producto_id, al.lote, sum(al.cant_uds) as suma
  from ent_alisto_lote_efectivo al
  join ent_alisto_linea ali on ali.id = al.linea_id
 where al.lote ~ '^\d{1,3} / \d{1,2}-\d{2}$'
 group by ali.producto_id, al.lote
 order by ali.producto_id, al.lote;

-- 3d · la lista de revision de Andrea ya tiene las tres excepciones.
select pedido_id, cliente_nombre, factura_nombre, producto_id,
       motivo_indeterminado, excepcion_por
  from v_ent_indeterminado_pendiente
 order by pedido_id, producto_id;
