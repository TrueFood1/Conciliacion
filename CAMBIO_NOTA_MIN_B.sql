-- ════════════════════════════════════════════════════════════════════════
-- CAMBIO B · minimo 10 -> 6 Y ADEMAS cierra el hueco del NULL
-- ════════════════════════════════════════════════════════════════════════
-- Preparado el 15-sep-2026. NO SE CORRIO.
--
-- QUE CAMBIA (DOS COSAS, no una): el minimo de `nota_no_entrega` pasa de 10 a 6 caracteres.
-- MOTIVO: "consigna" tiene 8 y no pasaba, asi que el caso real que origino el
-- bloque no se podia registrar.
--
-- EL CUERPO DEL CHECK NO SE REESCRIBIO DE MEMORIA: sale de
-- `pg_get_constraintdef` de la base y se le aplico el reemplazo CON POSTGRES
-- (replace sobre el texto devuelto). Medido el 15-sep 07:54 CR = 13:54 UTC:
--   texto original .... 579 caracteres
--   con 6+coalesce .... 593 caracteres
--
-- MEDICIONES QUE LO HABILITAN (15-sep, pg_lector, solo lectura):
--   filas con no_se_entrega = true ....... 0   (de 199 en ent_alisto_linea)
--   7e ... 8 filas, suma 423.500, md5 44dc89ae9bf7bd996291f518062ae990
--          (identico al patron del 14-sep, mismo archivo 7e_antes_14sep.sql)
--   Como NO hay ninguna fila marcada, bajar el minimo no puede invalidar nada
--   existente y el CHECK entra VALID.
--
-- ⚠️ EL `drop constraint` BORRA TAMBIEN EL COMENTARIO. Por eso el
-- `comment on constraint` del final NO es opcional: sin el, el comentario que
-- hoy tiene el constraint desaparece.
-- ════════════════════════════════════════════════════════════════════════

begin;

alter table ent_alisto_linea
  drop constraint if exists ent_alisto_linea_no_entrega_ok;

alter table ent_alisto_linea
  add constraint ent_alisto_linea_no_entrega_ok CHECK (
CASE
    WHEN no_se_entrega THEN (COALESCE(motivo_no_entrega = ANY (ARRAY['agotado'::text, 'otro'::text]), false) AND ((motivo_no_entrega <> 'otro'::text) OR ((nota_no_entrega IS NOT NULL) AND (length(btrim(nota_no_entrega)) >= 6))) AND (no_entrega_por IS NOT NULL) AND (length(btrim(no_entrega_por)) > 0) AND (no_entrega_en IS NOT NULL) AND (cant_uds = (0)::numeric) AND (COALESCE(cant_uom, (0)::numeric) = (0)::numeric))
    ELSE ((motivo_no_entrega IS NULL) AND (nota_no_entrega IS NULL) AND (no_entrega_por IS NULL) AND (no_entrega_en IS NULL) AND (cant_no_entregada IS NULL))
END);

comment on constraint ent_alisto_linea_no_entrega_ok on ent_alisto_linea is
  'La marca "no se entrega" viaja con su motivo, su firma y su hora, y con las cantidades en cero. Sin marca, los seis campos van nulos: no hay marca a medias en ninguna direccion. '
  'La nota del motivo "otro" exige 6 caracteres como minimo (era 10 hasta el '
  '15-sep-2026: "consigna", de 8, no pasaba).';

commit;

-- ── DESPUES DEL COMMIT ──────────────────────────────────────────────────
--   1. las tres pruebas de PRUEBAS_NOTA_MIN.sql, una por una
--   2. 7e con 7e_antes_14sep.sql -> md5 44dc89ae9bf7bd996291f518062ae990
--   3. el constraint sigue VALID: convalidated = t
--   4. LA PRUEBA DEL HUECO: marcada con motivo NULL pero firma y hora puestas
--      TIENE QUE DAR ERROR. Con el CHECK de hoy PASA (la expresion da NULL y
--      Postgres acepta un CHECK que da NULL).
