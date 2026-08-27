-- ════════════════════════════════════════════════════════════════════════
-- BACKFILL · escribir los 23 vínculos pedido → factura que faltan
-- 26-ago-2026.  Pegar COMO UN SOLO BLOQUE en el editor SQL de Supabase.
--
-- POR QUÉ FALTAN. `ent_pedido.factura_id` se escribió siempre, pero
-- ENTREGAS_SALIDAS.sql §2 la declara OBSOLETA: el vínculo vive SOLO en
-- `ent_pedido_factura`, y el único código que escribía ahí era el botón manual
-- "Vincular" de Pendientes. Ni `despConfirmar()` —que crea el pedido A PARTIR de
-- la factura— ni los dos cargues retroactivos la tocaban. Resultado: todo
-- despacho de venta cayó en "sin factura vinculada" aunque el sistema supiera
-- perfectamente cuál era su factura.
--
-- LA CAUSA YA ESTÁ ARREGLADA en b37: despConfirmar escribe el vínculo al crear el
-- pedido. Este bloque limpia lo que quedó de antes; sin b37 sería limpiar para
-- que se vuelva a ensuciar.
--
-- MEDIDO ANTES DE ESCRIBIR (consulta 2 de DIAGNOSTICO_VINCULOS.sql, 26-ago):
--     sin_vinculo_total = 23  ·  ya_saben_su_factura = 23  ·  sin_factura_conocida = 0
-- No hay nada que adivinar: cada uno trae su `factura_id` en la propia fila.
--
-- APPEND-ONLY. Se INSERTA el vínculo; no se toca `ent_pedido`, no se borra nada.
-- Si mañana alguno resulta mal vinculado, se inserta otra fila con `anulado`.
--
-- ⚠️ EL DESPACHO 11 (Mentha y limón, 19-ago) SE VINCULA IGUAL a la ...3484,
-- aunque esa factura esté anulada en Odoo. La entrega SÍ ocurrió —el Excel de
-- Daniel la tiene— y la 3484 es el documento que le corresponde a esa salida. Lo
-- contable se resuelve aparte. Decisión de Andrea, 26-ago.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── 1 · LOS QUE SE VAN A VINCULAR (mirar antes de confirmar) ────────────
-- `origen` y `motivo` están para poder cazar de un vistazo cualquier salida que
-- NO debería llevar factura. Una salida sin factura tiene motivo 'regalia',
-- 'reposicion', 'consumo_interno' o 'degustacion' y NO entra acá; y una venta
-- cargada a mano por "Entregas sin factura" nace con factura_id NULL, así que
-- tampoco. Si en esta lista aparece algo con origen 'manual', PARAR y mirarlo.
select p.id as despacho, p.fecha_despacho, p.cliente_nombre,
       p.motivo, p.origen, p.factura_id, p.factura_nombre, p.creado_por
  from ent_pedido p
  left join ent_pedido_factura_vigente v
         on v.pedido_id = p.id and v.anulado = false
 where p.motivo = 'venta'
   and p.factura_id is not null
   and v.pedido_id is null
 order by p.fecha_despacho, p.id;

-- ── 2 · CONTROL · ¿alguna factura quedaría vinculada a DOS pedidos? ─────
-- ENTREGAS_SALIDAS.sql avisa que no hay índice único que lo impida. Dos pedidos
-- con la misma factura serían un despacho contado dos veces, no un vínculo malo.
-- Esta consulta tiene que devolver CERO filas. Si devuelve alguna, NO seguir:
-- hacer rollback y revisar esos pedidos primero.
select p.factura_id, p.factura_nombre,
       count(*) as pedidos_que_la_reclaman,
       array_agg(p.id order by p.id) as despachos
  from ent_pedido p
  left join ent_pedido_factura_vigente v
         on v.pedido_id = p.id and v.anulado = false
 where p.motivo = 'venta' and p.factura_id is not null and v.pedido_id is null
 group by p.factura_id, p.factura_nombre
having count(*) > 1;

-- ── 3 · CONTROL · ¿la factura ya está vinculada a OTRO pedido? ──────────
-- También tiene que devolver CERO filas.
select p.id as despacho_nuevo, p.factura_nombre,
       v.pedido_id as ya_vinculada_al_despacho
  from ent_pedido p
  join ent_pedido_factura_vigente v
    on v.factura_id = p.factura_id and v.anulado = false and v.pedido_id <> p.id
  left join ent_pedido_factura_vigente vp
         on vp.pedido_id = p.id and vp.anulado = false
 where p.motivo = 'venta' and p.factura_id is not null and vp.pedido_id is null;

-- ── 4 · ESCRIBIR LOS VÍNCULOS ──────────────────────────────────────────
insert into ent_pedido_factura (pedido_id, factura_id, factura_nombre, anulado, nota, creado_por)
select p.id, p.factura_id, p.factura_nombre, false,
       case when p.id = 11 then
         'Backfill 26-ago-2026. El vínculo salía de ent_pedido.factura_id, que ya estaba '
         || 'escrito desde que se creó el despacho. OJO: la factura ...3484 está ANULADA en '
         || 'Odoo, pero la entrega del 19-ago SÍ ocurrió (el Excel de Daniel la tiene: '
         || '"19 ago 26 · Mentha y limón · Blanco 6 Uds 202-1/27 · Semillas 6 Uds 209-1/27"). '
         || 'Es el documento que le corresponde a esa salida; lo contable se resuelve aparte.'
       else
         'Backfill 26-ago-2026. El vínculo salía de ent_pedido.factura_id, que ya estaba '
         || 'escrito desde que se creó el despacho: ni despConfirmar() ni los cargues '
         || 'retroactivos escribían en ent_pedido_factura, que es donde vive la verdad. '
         || 'Causa arreglada en b37.'
       end,
       'backfill-sql:26ago-vinculos'
  from ent_pedido p
  left join ent_pedido_factura_vigente v
         on v.pedido_id = p.id and v.anulado = false
 where p.motivo = 'venta'
   and p.factura_id is not null
   and v.pedido_id is null;

-- ── 5 · COMPROBACIÓN · la consulta 2, otra vez ─────────────────────────
-- Tiene que dar sin_vinculo_total = 0.
select count(*)                       as sin_vinculo_total,
       count(p.factura_id)            as ya_saben_su_factura,
       count(*) - count(p.factura_id) as sin_factura_conocida
  from ent_pedido p
  left join ent_pedido_factura_vigente v
         on v.pedido_id = p.id and v.anulado = false
 where p.motivo = 'venta'
   and v.pedido_id is null;

-- ── 6 · COMPROBACIÓN · cuántos vínculos quedaron escritos ──────────────
select count(*) as vinculos_escritos_ahora
  from ent_pedido_factura
 where creado_por = 'backfill-sql:26ago-vinculos';

-- ── 7 · COMPROBACIÓN · ninguna factura vinculada dos veces ─────────────
-- Cero filas.
select factura_id, factura_nombre, count(*) as veces,
       array_agg(pedido_id order by pedido_id) as pedidos
  from ent_pedido_factura_vigente
 where anulado = false
 group by factura_id, factura_nombre
having count(*) > 1;

commit;
