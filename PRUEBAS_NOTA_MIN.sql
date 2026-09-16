-- ════════════════════════════════════════════════════════════════════════
-- PRUEBAS · el minimo de la nota, 10 -> 6 · UNA POR UNA
-- ════════════════════════════════════════════════════════════════════════
-- Preparado el 15-sep-2026. NO SE CORRIO.
--
-- CRITERIO (la leccion del 14-sep): las pruebas CREAN la fila, no la buscan.
-- La version vieja de 7a buscaba "una linea sin lotes" y hay 0 de esas, asi que
-- tocaba 0 filas y daba "Success" con el candado intacto. Un insert siempre
-- intenta escribir una fila, asi que el CHECK se evalua si o si.
--
-- Y LAS QUE TIENEN QUE PASAR HACEN UN SELECT ANTES DEL ROLLBACK. Un insert que
-- pasa es silencioso, y un "Success" mudo es indistinguible de uno que no hizo
-- nada — que es exactamente como se cayo 7a. El select obliga a VER la fila.
--
-- Las cuatro van en begin/rollback: no dejan nada escrito.
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- P0 · ANTES DE APLICAR · la prueba tiene que poder FALLAR
-- ════════════════════════════════════════════════════════════════════════
-- Correr ESTA SOLA, ANTES del cambio. Con el minimo en 10, una nota de 6
-- TIENE QUE DAR ERROR. Si pasa, el 10 no esta donde creemos: PARAR.
-- ESPERADO: ERROR violates check constraint "ent_alisto_linea_no_entrega_ok"
   begin;
     insert into ent_alisto_linea
            (alisto_id, producto_id, cant_uds, cant_uom,
             no_se_entrega, motivo_no_entrega, nota_no_entrega, no_entrega_por, no_entrega_en)
     values ((select id from ent_alisto where not anulado order by id desc limit 1),
             451, 0, 0, true, 'otro', 'abcdef', 'prueba-n6', now());
   rollback;


-- ════════════════════════════════════════════════════════════════════════
-- DE ACA EN ADELANTE: DESPUES DE APLICAR EL CAMBIO
-- ════════════════════════════════════════════════════════════════════════

-- ── P1 · nota de 6 caracteres EXACTOS · TIENE QUE PASAR ─────────────────
-- El select tiene que devolver 1 fila con largo = 6.
   begin;
     insert into ent_alisto_linea
            (alisto_id, producto_id, cant_uds, cant_uom,
             no_se_entrega, motivo_no_entrega, nota_no_entrega, no_entrega_por, no_entrega_en)
     values ((select id from ent_alisto where not anulado order by id desc limit 1),
             451, 0, 0, true, 'otro', 'abcdef', 'prueba-n6', now());
     select id, motivo_no_entrega, '['||nota_no_entrega||']' as nota,
            length(btrim(nota_no_entrega)) as largo
       from ent_alisto_linea where no_entrega_por = 'prueba-n6';
   rollback;


-- ── P2 · nota de 5 · TIENE QUE DAR ERROR ────────────────────────────────
-- El borde de abajo. 6 pasa, 5 no: si las dos pasan, el minimo no quedo en 6.
-- ESPERADO: ERROR violates check constraint "ent_alisto_linea_no_entrega_ok"
   begin;
     insert into ent_alisto_linea
            (alisto_id, producto_id, cant_uds, cant_uom,
             no_se_entrega, motivo_no_entrega, nota_no_entrega, no_entrega_por, no_entrega_en)
     values ((select id from ent_alisto where not anulado order by id desc limit 1),
             451, 0, 0, true, 'otro', 'abcde', 'prueba-n5', now());
   rollback;


-- ── P3 · "consigna" (8) · TIENE QUE PASAR ───────────────────────────────
-- El caso real que origino el cambio. El select tiene que dar largo = 8.
   begin;
     insert into ent_alisto_linea
            (alisto_id, producto_id, cant_uds, cant_uom,
             no_se_entrega, motivo_no_entrega, nota_no_entrega, no_entrega_por, no_entrega_en)
     values ((select id from ent_alisto where not anulado order by id desc limit 1),
             451, 0, 0, true, 'otro', 'consigna', 'prueba-consigna', now());
     select id, motivo_no_entrega, '['||nota_no_entrega||']' as nota,
            length(btrim(nota_no_entrega)) as largo
       from ent_alisto_linea where no_entrega_por = 'prueba-consigna';
   rollback;


-- ── P4 · EL HUECO DEL NULL · SOLO SI SE APLICO LA OPCION B ──────────────
-- Marcada, motivo NULL, pero firma y hora PUESTAS. La expresion del CHECK da
-- NULL y Postgres acepta un CHECK que da NULL.
--   · con la opcion A  -> PASA  (el hueco sigue abierto: NO es un fallo)
--   · con la opcion B  -> ERROR (el hueco quedo cerrado)
-- Correrla sabiendo cual se aplico, o el resultado no dice nada.
   begin;
     insert into ent_alisto_linea
            (alisto_id, producto_id, cant_uds, cant_uom,
             no_se_entrega, no_entrega_por, no_entrega_en)
     values ((select id from ent_alisto where not anulado order by id desc limit 1),
             451, 0, 0, true, 'prueba-hueco', now());
     select id, motivo_no_entrega, no_entrega_por
       from ent_alisto_linea where no_entrega_por = 'prueba-hueco';
   rollback;


-- ── CONTROL FINAL · el constraint quedo VALID y con su comentario ───────
select conname, convalidated,
       length(pg_get_constraintdef(oid)) as largo_def,
       length(obj_description(oid,'pg_constraint')) as largo_comentario
  from pg_constraint
 where conrelid='ent_alisto_linea'::regclass
   and conname='ent_alisto_linea_no_entrega_ok';
