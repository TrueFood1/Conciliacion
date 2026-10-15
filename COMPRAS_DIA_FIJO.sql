-- ════════════════════════════════════════════════════════════════════════
-- COMPRAS_DIA_FIJO.sql — T-28 · BIO Ingredients entrega los LUNES (2-oct-2026)
-- ⚠ ESCRITO, NO PEGADO. Este archivo no prueba que la fila exista en la base:
--   para saberlo, correr la consulta de verificación de abajo.
-- ════════════════════════════════════════════════════════════════════════
-- Siembra la clave `compras_dia_fijo` de plan_config (documentada en PLAN_CONFIG_ESQUEMA.sql).
-- plan_config es append-only: gana la fila más reciente por clave. Para cambiar algo (el día de
-- pedido cuando Lorena lo confirme, el del huevo), se inserta OTRA fila con la lista COMPLETA.
--
-- Decisiones de Andrea (2-oct):
--   · Todo lo que se le compra a BIO sigue la regla del lunes —premezclas, levadura y semillas—:
--     llega el lunes DESPUÉS de medir y se usa para medir el lunes siguiente.
--   · El huevo líquido llega los JUEVES y se usa en producción (Cookie Dough). Su día de
--     pedido no está definido (null): la tarjeta lo calcula como si se pidiera hoy.
--   · Día de pedido 'jue': el 1-oct Lorena pidió un jueves; falta que confirme si es siempre.
--   · Bicarbonato [523] figura con BIO en Odoo pero no se le compró en 6 meses: NO va.
-- IDs de producción (product.product), verificados el 2-oct contra Odoo. Proveedor 948.

insert into plan_config (clave, valor, usuario) values ('compras_dia_fijo', '{
  "insumos": [
    {"producto_id": 461, "nombre": "Avena Molida",         "proveedor_id": 948, "proveedor": "BIO Ingredients", "pide": "jue", "llega": "lun", "momento": "despues", "uso": "medicion"},
    {"producto_id": 456, "nombre": "Almidon de Maiz",      "proveedor_id": 948, "proveedor": "BIO Ingredients", "pide": "jue", "llega": "lun", "momento": "despues", "uso": "medicion"},
    {"producto_id": 457, "nombre": "Almidon de Yuca",      "proveedor_id": 948, "proveedor": "BIO Ingredients", "pide": "jue", "llega": "lun", "momento": "despues", "uso": "medicion"},
    {"producto_id": 464, "nombre": "Harina de Arroz",      "proveedor_id": 948, "proveedor": "BIO Ingredients", "pide": "jue", "llega": "lun", "momento": "despues", "uso": "medicion"},
    {"producto_id": 460, "nombre": "Harina de Garbanzo",   "proveedor_id": 948, "proveedor": "BIO Ingredients", "pide": "jue", "llega": "lun", "momento": "despues", "uso": "medicion"},
    {"producto_id": 463, "nombre": "Goma Xantana",         "proveedor_id": 948, "proveedor": "BIO Ingredients", "pide": "jue", "llega": "lun", "momento": "despues", "uso": "medicion"},
    {"producto_id": 459, "nombre": "Sal",                  "proveedor_id": 948, "proveedor": "BIO Ingredients", "pide": "jue", "llega": "lun", "momento": "despues", "uso": "medicion"},
    {"producto_id": 458, "nombre": "Levadura",             "proveedor_id": 948, "proveedor": "BIO Ingredients", "pide": "jue", "llega": "lun", "momento": "despues", "uso": "medicion"},
    {"producto_id": 475, "nombre": "Semillas de Calabaza", "proveedor_id": 948, "proveedor": "BIO Ingredients", "pide": "jue", "llega": "lun", "momento": "despues", "uso": "medicion"},
    {"producto_id": 476, "nombre": "Semillas de linaza",   "proveedor_id": 948, "proveedor": "BIO Ingredients", "pide": "jue", "llega": "lun", "momento": "despues", "uso": "medicion"},
    {"producto_id": 477, "nombre": "Semillas de Girasol",  "proveedor_id": 948, "proveedor": "BIO Ingredients", "pide": "jue", "llega": "lun", "momento": "despues", "uso": "medicion"},
    {"producto_id": 521, "nombre": "Huevo liquido",        "proveedor_id": 948, "proveedor": "BIO Ingredients", "pide": null,  "llega": "jue", "momento": "despues", "uso": "produccion"}
  ]
}'::jsonb, 'andrea@truefoodcr.com');

-- VERIFICACIÓN (después de pegar): tiene que devolver 12.
-- select jsonb_array_length(valor->'insumos') from plan_config
--  where clave='compras_dia_fijo' order by creado_en desc limit 1;
