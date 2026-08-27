-- ════════════════════════════════════════════════════════════════════════
-- LA FOTO DE HOY, ANTES DEL RECONTEO — 27-ago-2026
-- Pegar COMO UN SOLO BLOQUE en el editor SQL de Supabase, ANTES de confirmar
-- el conteo nuevo. Después del reancle esto ya no se puede reconstruir.
--
-- ── POR QUÉ ─────────────────────────────────────────────────────────────
-- El conteo nuevo no resuelve el problema del lote 208: lo TAPA. Después del
-- reancle el 208 va a decir 126 y todo va a cuadrar, y se pierde para siempre
-- la única evidencia de dónde salieron esas 130 unidades.
--
-- Y hay algo más, que es lo que convierte esto de "evidencia" en "la mitad de
-- una medición": el conteo de mañana SOLO SE PUEDE INTERPRETAR contra los
-- números de hoy. Si el 208 nunca se movió, las 130 unidades salieron de otros
-- lotes, y esos lotes van a tener FÍSICAMENTE MENOS de lo que el sistema cree.
-- Sin esta foto, mañana se ven 34 números nuevos sin nada contra qué restarlos.
--
-- ── DOS HIPÓTESIS QUE ESTA FOTO SEPARA ──────────────────────────────────
-- Las dos explican que hoy haya 126 unidades físicas del 208:
--   A · El pan del 208 NUNCA SE MOVIÓ, y las 130 salieron de otros lotes.
--       → esos otros lotes tienen físicamente MENOS de lo que el sistema dice.
--   B · El 208 se consumió entero y una tanda POSTERIOR quedó físicamente
--       rotulada 208 aunque su chatter diga otra cosa. Ojo: WH/MO/01414 (230)
--       y WH/MO/01415 (231) produjeron EXACTAMENTE 126 u cada una.
--       → entonces el 230 o el 231 va a estar FÍSICAMENTE AUSENTE mañana.
-- Se distinguen mirando si 230 y 231 aparecen mañana con su cantidad. Por eso
-- la foto tiene que ser de TODOS los lotes, no solo del 208.
--
-- ⚠️ LA PRODUCCIÓN NO VIVE EN POSTGRES. Sale del chatter de Odoo y se calcula
-- en el navegador. Va abajo embebida a mano, leída de Odoo el 27-ago (ver la
-- CTE `prod_odoo`). Sin ella el saldo no son cuatro puntas, son tres.
--
-- ⚠️ ADEMÁS DE ESTO, SACALE UNA FOTO A LA PANTALLA DE INVENTARIO HOY. La app
-- calcula las cuatro puntas y además muestra las órdenes sin lote legible, que
-- son pan en el congelador que no suma a ningún lote y que este SQL no ve.
--
-- NO CORRIGE NADA. Solo lee. La parte 3 CREA una tabla nueva —no toca ni una
-- fila existente— y es la única forma de que la foto sobreviva al reancle.
-- ════════════════════════════════════════════════════════════════════════


-- ── 0 · CONTRA QUÉ ANCLA SE ESTÁ CALCULANDO ─────────────────────────────
-- Confirmá que el corte sea el del 14-ago 16:00 CR. Si ya no lo es, el reancle
-- YA PASÓ y esta foto llega tarde: avisá antes de seguir.
select 'ANCLA VIGENTE' as que, id as conteo_id, fecha,
       to_char(corte at time zone 'America/Costa_Rica','DD-Mon-YYYY HH24:MI') as corte_cr
  from ent_ancla;


-- ── DEFINICIÓN COMÚN ────────────────────────────────────────────────────
create or replace view _foto_lotes as
with a as (select id, corte from ent_ancla),
-- Producción con date_start POSTERIOR al corte, leída de Odoo el 27-ago-2026.
-- WH/MO/01411 (Galletas 226 / 2-27, 160 u) va en 0 A PROPÓSITO: está en
-- ENT_MO_EXCLUIDAS porque se registró 6 min después del corte pero el pan ya
-- estaba contado en el físico; sumarla lo contaría dos veces.
prod_odoo(producto_id, lote, uds) as (values
  (451,'230 / 2-27',126::numeric), (451,'231 / 2-27',126), (451,'236 / 2-27',168),
  (453,'232 / 2-27',180),          (453,'237 / 2-27',150),
  (503,'238 / 2-27',750),
  (519,'226 / 2-27',0)
),
ancla as (select cl.producto_id, cl.lote, sum(cl.uds) as uds
            from ent_conteo_linea cl where cl.conteo_id=(select id from a) group by 1,2),
salidas as (select ali.producto_id, al.lote, sum(al.cant_uds) as uds
              from ent_alisto_lote al
              join ent_alisto_linea ali on ali.id=al.linea_id
              join ent_alisto_vigente av on av.alisto_id=ali.alisto_id
             where av.preparado_en > (select corte from a) group by 1,2),
devol as (select dl.producto_id, dl.lote, sum(dl.cant_uds) as uds
            from ent_devolucion_linea dl
            join ent_devolucion_vigente dv on dv.devolucion_id=dl.devolucion_id
           where dv.recibido_en > (select corte from a) group by 1,2),
claves as (select producto_id, lote from ancla
     union select producto_id, lote from prod_odoo
     union select producto_id, lote from salidas
     union select producto_id, lote from devol)
select case k.producto_id when 451 then 'Pan Blanco' when 452 then 'Pan de Semillas'
            when 453 then 'Pan Francés' when 472 then 'Pizza Crust'
            when 503 then 'Buns' when 519 then 'Galletas'
            else '#'||k.producto_id end                     as producto,
       k.producto_id, k.lote,
       coalesce(an.uds,0) as ancla_14ago,
       coalesce(po.uds,0) as produccion_odoo,
       coalesce(sa.uds,0) as salidas,
       coalesce(de.uds,0) as devoluciones,
       coalesce(an.uds,0)+coalesce(po.uds,0)-coalesce(sa.uds,0)+coalesce(de.uds,0)
                          as saldo_esperado_hoy
  from claves k
  left join ancla     an on an.producto_id=k.producto_id and an.lote=k.lote
  left join prod_odoo po on po.producto_id=k.producto_id and po.lote=k.lote
  left join salidas   sa on sa.producto_id=k.producto_id and sa.lote=k.lote
  left join devol     de on de.producto_id=k.producto_id and de.lote=k.lote;


-- ── 1 · LA FOTO · saldo esperado de CADA lote de los seis productos ─────
-- ESTA es la columna contra la que hay que restar el conteo de mañana.
select producto, lote, ancla_14ago, produccion_odoo, salidas, devoluciones,
       saldo_esperado_hoy,
       case when saldo_esperado_hoy < 0 then '🔴 NEGATIVO' else '' end as alerta
  from _foto_lotes
 order by producto, lote;


-- ── 2 · TODOS LOS MOVIMIENTOS, de todos los lotes ───────────────────────
-- El detalle que explica cada número de arriba. Un renglón por movimiento.
with a as (select id, fecha, corte from ent_ancla)
select case ali.producto_id when 451 then 'Pan Blanco' when 452 then 'Pan de Semillas'
            when 453 then 'Pan Francés' when 472 then 'Pizza Crust'
            when 503 then 'Buns' when 519 then 'Galletas'
            else '#'||ali.producto_id end as producto,
       al.lote,
       to_char(av.preparado_en at time zone 'America/Costa_Rica','DD-Mon HH24:MI') as cuando_cr,
       av.pedido_id as despacho,
       p.cliente_nombre,
       coalesce(fv.factura_nombre,'sin factura') as factura,
       av.responsable,
       al2.creado_por,
       case when al2.creado_por like 'correccion-sql%' or al2.creado_por like '%backfill%'
            then '⚠ SQL' else 'pantalla' end as origen,
       -sum(al.cant_uds) as delta
  from ent_alisto_lote    al
  join ent_alisto_linea   ali on ali.id       = al.linea_id
  join ent_alisto_vigente av  on av.alisto_id = ali.alisto_id
  join ent_alisto         al2 on al2.id       = av.alisto_id
  join ent_pedido         p   on p.id         = av.pedido_id
  left join ent_pedido_factura_vigente fv on fv.pedido_id=p.id and fv.anulado=false
 where av.preparado_en > (select corte from a)
 group by ali.producto_id, al.lote, av.preparado_en, av.pedido_id,
          p.cliente_nombre, fv.factura_nombre, av.responsable, al2.creado_por
 order by 1, 2, av.preparado_en;


-- ── 3 · CONGELAR LA FOTO · lo único que sobrevive al reancle ────────────
-- El editor solo muestra un resultado y las dos consultas de arriba se pierden
-- al recargar la página. Esto las guarda en una tabla NUEVA. No toca ni una
-- fila existente: es puramente aditivo, del mismo espíritu append-only que
-- todo el módulo. Si preferís no crear tablas, copiá los dos resultados a un
-- Excel ANTES de confirmar el conteo — pero entonces la copia es el respaldo.
create table if not exists ent_foto_lote_27ago as
  select now() as tomada_en,
         'Foto anterior al reconteo del 28-ago. El lote Pan Blanco 208 / 1-27 daba '
         || '-4 en sistema y 126 u físicas (21 cajas). Descartado en Odoo que haya '
         || 'produccion posterior al ancla rotulada 208. Ver ENTREGAS_PENDIENTES.md.'
         as nota,
         *
    from _foto_lotes;

alter table ent_foto_lote_27ago enable row level security;
drop policy if exists ent_foto_lote_27ago_sel on ent_foto_lote_27ago;
create policy ent_foto_lote_27ago_sel on ent_foto_lote_27ago
  for select to authenticated using (true);
grant select on ent_foto_lote_27ago to authenticated;

-- La vista auxiliar ya no hace falta una vez congelada la tabla.
drop view if exists _foto_lotes;

-- Comprobación: tiene que devolver una fila por lote, con la hora de hoy.
select count(*) as lotes_congelados,
       to_char(min(tomada_en) at time zone 'America/Costa_Rica','DD-Mon HH24:MI') as tomada_cr
  from ent_foto_lote_27ago;
