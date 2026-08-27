-- ════════════════════════════════════════════════════════════════════════
-- REVERTIR la anulación del despacho 11 · 26-ago-2026
-- Pegar COMO UN SOLO BLOQUE en el editor SQL de Supabase.
--
-- ⚠️ ESTE BLOQUE DESHACE LO QUE HIZO `CORRECCION_DESP11.sql`, QUE SE CORRIÓ
-- SOBRE UNA PREMISA FALSA.
--
-- QUÉ SE CONCLUYÓ MAL. Se dio por hecho que la salida del despacho 11 (Mentha y
-- limón, 19-ago) nunca había ocurrido, porque su factura ...3484 estaba anulada
-- en Odoo y su traslado WH/OUT/02319 en `cancel`. La factura dice QUÉ SE COBRÓ;
-- no dice qué salió del congelador.
--
-- QUÉ DICE LA EVIDENCIA BUENA. El Excel de Daniel —el único registro de lo que
-- físicamente sale— tiene el bloque:
--     19 ago 26 · Mentha y limón · Blanco 6 Uds 202-1/27 · Semillas 6 Uds 209-1/27
-- Calza exacto, producto por producto y lote por lote, con el despacho 11. El
-- despacho era correcto desde el principio.
--
-- SON DOS ENTREGAS DISTINTAS, no un duplicado:
--     19-ago  →  Blanco  202 / 1-27  ·  Semillas  209 / 1-27   (factura ...3484)
--     26-ago  →  Blanco  208 / 1-27  ·  Semillas  209 / 1-27   (factura ...3499)
-- El lote de Semillas 209 / 1-27 se usó las dos veces, y está bien: es el mismo
-- lote surtiendo dos entregas.
--
-- CONSECUENCIA A CORREGIR. Con la anulación puesta, el saldo tiene 12 unidades
-- de MÁS que no están en el congelador: 6 de Blanco 202 / 1-27 y 6 de Semillas
-- 209 / 1-27. Este bloque se las vuelve a descontar.
--
-- ⚠️ POR QUÉ SE RE-REGISTRA EN VEZ DE "DES-ANULAR". El esquema NO contempla
-- revertir una anulación: `ent_anulacion` no tiene columna para anularse a sí
-- misma, y `ent_alisto_vigente` / `ent_salida_vigente` usan `not exists (...)`,
-- así que cualquier fila de anulación es final — una fila posterior no la
-- deshace. Decisión de Andrea (26-ago): NO se tocan las vistas con urgencia y NO
-- se borra nada. Las filas `id 2` (alisto 9) e `id 3` (salida 8) SE QUEDAN
-- INTACTAS, con su motivo equivocado y su fecha, que es la evidencia de que esto
-- pasó. Lo que se hace es INSERTAR el alisto de nuevo, con la misma fecha, las
-- mismas líneas y los mismos lotes. Append-only de punta a punta.
--
-- La historia del pedido 11 queda leída así, que es la verdad:
--   preparado el 19-ago → anulado por error el 26-ago → vuelto a registrar el 26-ago
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── 0 · CANDADO ─────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from ent_anulacion where entidad='alisto' and entidad_id=9) then
    raise exception 'No existe la anulación del alisto 9. ¿Seguro que se corrió CORRECCION_DESP11.sql? No se insertó nada.';
  end if;
  if exists (select 1 from ent_alisto_vigente where pedido_id = 11) then
    raise exception 'YA REVERTIDO: el pedido 11 ya tiene un alisto vigente. No se insertó nada.';
  end if;
end $$;

-- ── 1 · EL ALISTO, DE NUEVO ─────────────────────────────────────────────
-- Misma fecha que el original (19-ago 00:00 CR): lo que importa para el saldo es
-- que caiga DESPUÉS del corte del ancla (14-ago 16:00), como el primero.
with a as (
  insert into ent_alisto (pedido_id, responsable, creado_en, nota, creado_por)
  values (11, 'Daniel', timestamptz '2026-08-19 00:00:00-06',
    'RE-REGISTRO. El alisto 9 de este mismo pedido se anuló por error el 26-ago '
    || '(ent_anulacion id 2) con el motivo "la preparación nunca ocurrió". Era falso: '
    || 'se concluyó desde la factura ...3484 anulada y su traslado WH/OUT/02319 en cancel, '
    || 'sin mirar el Excel de Daniel, que es el único registro de lo que sale físicamente '
    || 'del congelador. El Excel tiene el bloque "19 ago 26 · Mentha y limón · Blanco 6 Uds '
    || '202-1/27 · Semillas 6 Uds 209-1/27", que calza exacto con este despacho. La entrega '
    || 'del 19-ago y la del 26-ago (factura ...3499) son DOS entregas distintas. '
    || 'La anulación NO se borra: queda como evidencia de la corrección.',
    'correccion-sql:26ago-desp11-revertir')
  returning id
), al as (
  insert into ent_alisto_linea (alisto_id, producto_id, cant_uds, cant_uom)
  select a.id, v.* from a, (values
    (451, 6, 6),      -- Pan Blanco       6 unidades
    (452, 6, 6)       -- Pan de Semillas  6 unidades
  ) as v(producto_id, cant_uds, cant_uom)
  returning id, producto_id
), lot as (
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden)
  select al.id, v.lote, v.cant_uds, v.orden
    from al join (values
      (451, '202 / 1-27', 6, 0),
      (452, '209 / 1-27', 6, 0)
    ) as v(producto_id, lote, cant_uds, orden) on v.producto_id = al.producto_id
)
insert into ent_salida (alisto_id, salida_en, nota, creado_por)
select a.id, timestamptz '2026-08-19 00:00:00-06',
       'RE-REGISTRO junto con su alisto. La salida 8 se anuló por error el 26-ago '
       || '(ent_anulacion id 3). La hora NO está medida: el Excel de Daniel solo trae el día.',
       'correccion-sql:26ago-desp11-revertir'
  from a;

-- ── 2 · COMPROBACIÓN · el pedido 11 tiene alisto vigente otra vez ───────
-- Tiene que devolver UNA fila, con preparado_en = 2026-08-19.
select 'DEBE SALIR UNA FILA' as control, av.*
  from ent_alisto_vigente av
 where av.pedido_id = 11;

-- ── 3 · COMPROBACIÓN · los 12 vuelven a descontarse ────────────────────
-- Blanco 202 / 1-27 y Semillas 209 / 1-27 tienen que traer las 6 u de cada uno.
-- Semillas 209 / 1-27 va a sumar 12 en total: 6 del 19-ago y 6 del 26-ago.
select 'DESPUES' as momento, producto_id, lote, uds as uds_descontadas
  from ent_salido_del_congelador_desde_ancla
 where lote in ('202 / 1-27','209 / 1-27','208 / 1-27')
 order by producto_id, lote;

-- ── 4 · COMPROBACIÓN · la anulación vieja sigue ahí, sin borrar ────────
select 'LA EVIDENCIA SE QUEDA' as control, id, entidad, entidad_id,
       left(motivo, 60) as motivo, creado_en, creado_por
  from ent_anulacion
 order by id;

commit;
