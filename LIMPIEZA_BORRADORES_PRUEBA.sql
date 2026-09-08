-- ════════════════════════════════════════════════════════════════════════
-- LIMPIAR LOS BORRADORES DE PRUEBA ANTES DE PUBLICAR b55
-- 7-sep-2026. Pegar UNA VEZ en el SQL Editor, antes de publicar a main.
--
-- POR QUÉ: Andrea probó el borrador desde el celular en prueba.html y dejó
-- 20 filas abiertas — 19 de `factura|41211` (una por toque) y 1 de un manual.
-- Si no se descartan, Daniel abre mañana a las 6:30 y ve en la tira "Sin cerrar"
-- borradores que no son suyos y que no corresponden a ninguna entrega real.
--
-- ⚠️ NO SE BORRA NADA, y no se podría: `ent_alisto_borrador` es append-only y su
-- RLS solo tiene select e insert. Descartar es INSERTAR una fila con
-- estado='descartado', que es como el módulo cierra un borrador. La vista
-- `_vigente` toma la más reciente de cada (origen, ref), así que a partir de
-- este insert las de prueba dejan de estar 'abierto' y salen de la tira —
-- `boCargarAbiertos` filtra por estado='abierto'.
--
-- Las filas de prueba quedan en la tabla, con su razón escrita. Es lo correcto:
-- son la evidencia de que la capa de Supabase funcionó.
-- ════════════════════════════════════════════════════════════════════════

-- ── 1 · MIRAR PRIMERO qué se va a descartar ─────────────────────────────
-- Correr esto SOLO, y confirmar que son las de prueba y nada más.
-- Esperado el 7-sep: dos filas, `factura|41211` y un `manual|m...`.
select origen, ref, estado, creado_por,
       (creado_en at time zone 'America/Costa_Rica')::timestamp(0) as creado_cr,
       (select count(*) from ent_alisto_borrador b
         where b.origen = v.origen and b.ref = v.ref) as filas_en_total
  from ent_alisto_borrador_vigente v
 where v.estado = 'abierto'
 order by 1, 2;


-- ── 2 · DESCARTARLAS ────────────────────────────────────────────────────
-- Descarta TODO lo que esté abierto en este momento. Es correcto HOY porque lo
-- único abierto son las pruebas; si mañana quedara un borrador de verdad sin
-- cerrar, esto se lo llevaría también. Por eso el paso 1 no es opcional.
insert into ent_alisto_borrador (origen, ref, estado, datos, nota, creado_por)
select v.origen, v.ref, 'descartado', v.datos,
       'Borrador de PRUEBA del 7-sep-2026 (Andrea, desde el celular, en '
       || 'prueba.html). Se descarta antes de publicar b55 para que no aparezca '
       || 'en la tira de Daniel. Las filas originales quedan: son la evidencia '
       || 'de que la capa de Supabase funcionó.',
       'limpieza-pruebas-7sep'
  from ent_alisto_borrador_vigente v
 where v.estado = 'abierto';


-- ── 3 · VERIFICAR ───────────────────────────────────────────────────────
-- Tiene que devolver 0 en `abiertos`. Si devuelve más, algo quedó sin descartar.
select count(*) filter (where estado = 'abierto')     as abiertos,
       count(*) filter (where estado = 'descartado')  as descartados,
       count(*)                                       as parejas_en_total
  from ent_alisto_borrador_vigente;


-- ── LO QUE ESTO NO ALCANZA ──────────────────────────────────────────────
-- El celular con el que Andrea probó todavía tiene la copia LOCAL del borrador
-- en su localStorage. Queda inerte: `_boBajar` no la restaura porque en la nube
-- ya no está 'abierto', y la tira sale de la nube. Solo volvería a aparecer si
-- alguien abre esa misma factura EN ESE MISMO celular y toca un lote — y ahí
-- sería un borrador nuevo y legítimo, no la prueba.
-- Si aun así aparece algo raro en la tira mañana, avisar: significaría que quedó
-- una escritura local marcada sin subir y el reintento la resucitó.
