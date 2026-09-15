-- ════════════════════════════════════════════════════════════════════════
-- QUITAR `decision` DE ent_alisto_linea_autorizacion · LA FILA ES LA VALIDACION
-- ════════════════════════════════════════════════════════════════════════
-- Preparado el 15-sep-2026. NO SE CORRIO.
--
-- POR QUE. El §3 modelo 'autorizada' / 'rechazada' como si la socia pudiera
-- negar algo. No puede: el pan ya salio o ya no salio, es un hecho fisico
-- cerrado. En la practica la socia SIEMPRE valida; lo unico que varia es si
-- deja una nota. Dos valores donde uno nunca se usa es un modelo que miente.
-- Queda UNA decision (la validacion), y la fila ES esa validacion.
-- La nota pasa a ser OPCIONAL.
--
-- MEDIDO ANTES (15-sep 08:46 CR = 14:46 UTC, pg_lector, solo lectura):
--   ent_alisto_linea_autorizacion .... 0 filas   -> no hay dato que migrar
--   v_ent_excepcion_pendiente ........ 6 de tipo lote_no_determinado,
--                                      ids {164,184,192,193,194,195}, 0 de no_se_entrega
--   7e ... 8 filas, suma 423.500, md5 44dc89ae9bf7bd996291f518062ae990
--
-- ⚠️ EL ORDEN NO ES LIBRE. La vista v_ent_excepcion_pendiente depende de la
-- columna `decision`, asi que el DROP COLUMN FALLA mientras la vista la use
-- ("cannot drop column ... because other objects depend on it"), y el CASCADE
-- que lo resolveria BORRARIA LA VISTA. Por eso la vista se redefine ANTES.
--
-- ⚠️ LOS DOS CHECK SE DROPEAN A LA VISTA, A PROPOSITO. Postgres los borraria
-- solo junto con la columna, en silencio y sin que quede escrito en ningun
-- lado. Dropearlos explicitamente deja el rastro de que se fueron y por que.
--
-- EL CUERPO DE LA VISTA NO SE REESCRIBIO DE MEMORIA: sale de pg_get_viewdef y
-- el reemplazo lo hizo Postgres (SELECT x.decision -> SELECT x.id, y
-- au.decision IS NULL -> au.id IS NULL). Medido: 1655 -> 1643 caracteres,
-- exactamente los 12 que suman los dos cambios. La sonda es la misma: el
-- LATERAL devuelve fila o no devuelve; `decision` solo se usaba para saber eso.
--
-- LOS GRANTS ABIERTOS (anon con los siete privilegios) NO SE TOCAN ACA:
-- quedan como deuda del §6, por decision de Andrea.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── a · los dos CHECK, dropeados a la vista ─────────────────────────────
-- `autorizacion_nota_ok` exigia nota >= 10 cuando decision = 'rechazada'.
-- Sin 'rechazada' no tiene sujeto: la nota queda opcional por ausencia de
-- regla, que es lo que se busca.
alter table ent_alisto_linea_autorizacion
  drop constraint if exists autorizacion_nota_ok;
alter table ent_alisto_linea_autorizacion
  drop constraint if exists ent_alisto_linea_autorizacion_decision_check;

-- ── b · la vista, sondando x.id en vez de x.decision ────────────────────
create or replace view v_ent_excepcion_pendiente
  with (security_invoker = true) as
 SELECT 'lote_no_determinado'::text AS tipo,
    p.id AS pedido_id,
    p.origen,
    p.cliente_nombre,
    COALESCE(fv.factura_nombre, p.factura_nombre) AS factura_nombre,
    ali.producto_id,
    ale.cant_uds,
    ale.motivo_indeterminado AS motivo,
    NULL::text AS nota,
    ale.excepcion_por AS registrada_por,
    av.preparado_en,
    ale.id AS alisto_lote_id,
    NULL::bigint AS alisto_linea_id
   FROM ent_alisto_lote_efectivo ale
     JOIN ent_alisto_linea ali ON ali.id = ale.linea_id
     JOIN ent_alisto_vigente av ON av.alisto_id = ali.alisto_id
     JOIN ent_pedido p ON p.id = av.pedido_id
     LEFT JOIN ent_pedido_factura_vigente fv ON fv.pedido_id = p.id AND fv.anulado = false
  WHERE ale.lote = 'NO DETERMINADO'::text
UNION ALL
 SELECT 'no_se_entrega'::text AS tipo,
    p.id AS pedido_id,
    p.origen,
    p.cliente_nombre,
    COALESCE(fv.factura_nombre, p.factura_nombre) AS factura_nombre,
    ali.producto_id,
    ali.cant_no_entregada AS cant_uds,
    ali.motivo_no_entrega AS motivo,
    ali.nota_no_entrega AS nota,
    ali.no_entrega_por AS registrada_por,
    av.preparado_en,
    NULL::bigint AS alisto_lote_id,
    ali.id AS alisto_linea_id
   FROM ent_alisto_linea ali
     JOIN ent_alisto_vigente av ON av.alisto_id = ali.alisto_id
     JOIN ent_pedido p ON p.id = av.pedido_id
     LEFT JOIN ent_pedido_factura_vigente fv ON fv.pedido_id = p.id AND fv.anulado = false
     LEFT JOIN LATERAL ( SELECT x.id
           FROM ent_alisto_linea_autorizacion x
          WHERE x.alisto_linea_id = ali.id
          ORDER BY x.creado_en DESC
         LIMIT 1) au ON true
  WHERE ali.no_se_entrega AND au.id IS NULL;

-- ── c · y recien ahora, la columna ──────────────────────────────────────
alter table ent_alisto_linea_autorizacion
  drop column decision;

-- ── d · el comentario, al dia ───────────────────────────────────────────
comment on table ent_alisto_linea_autorizacion is
  'El visto bueno de una socia sobre una linea marcada "no se entrega". LA FILA ES LA VALIDACION: '
  'que exista dice que una socia la valido, y no hay columna que interpretar. La nota es OPCIONAL. '
  'Append-only: manda la fila mas reciente por alisto_linea_id. NO mueve ningun saldo: el pan ya '
  'salio o ya no salio, y eso es un hecho fisico cerrado. Hasta el 15-sep-2026 hubo una columna '
  '`decision` con "autorizada"/"rechazada"; se quito porque la socia no puede negar un hecho '
  'consumado y "rechazada" no se uso nunca (0 filas en la tabla al quitarla). Para deshacer una '
  'marca equivocada se anula el alisto y se registra de nuevo, que es el unico camino que deja '
  'rastro de las dos versiones.';

commit;

-- ── DESPUES DEL COMMIT ──────────────────────────────────────────────────
--   1. las cuatro pruebas de PRUEBAS_AUTORIZACION.sql, una por una
--   2. la vista devuelve los MISMOS 6 ids {164,184,192,193,194,195}
--   3. 7e con 7e_antes_14sep.sql -> md5 44dc89ae9bf7bd996291f518062ae990
--   4. el trigger ent_alisto_linea_autorizacion_guard_trg sigue tgenabled='O'
--   5. la columna `decision` ya no existe
