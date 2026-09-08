-- ════════════════════════════════════════════════════════════════════════
-- b56 · LA FECHA PEGADA DEL PEDIDO 44 (Walmart / CSU, factura 3515)
-- LISTO PARA PEGAR UNA SOLA VEZ en el SQL Editor de Supabase.
-- Append-only: NO hay UPDATE ni DELETE. Se puede correr dos veces sin daño
-- (tiene guarda), y no se puede correr desde pg_lector, que es de solo lectura.
--
-- ── EL DEFECTO ──────────────────────────────────────────────────────────
-- El pedido 44 nació SIN factura el 3-sep, y el 7-sep se le vinculó la factura
-- 3515. Vincular la factura no recalculó la fecha, y el arreglo de rpGuardar de
-- b55 solo aplica a registros nuevos: código nuevo no reescribe historia.
-- Resultado medido el 8-sep:
--     preparado_en  2026-09-07 07:58 CR   ← el alisto se cerró el 7-sep
--     salida_en     2026-09-03 12:00 CR   ← y la salida dice 3-sep, mediodía
-- La fila se contradice a sí misma: no se puede haber alistado cuatro días
-- después de haber salido.
--
-- ── EL PEDIDO 43 NO SE TOCA ─────────────────────────────────────────────
-- Se revisó igual porque venía en el mismo reporte. NO es de Walmart (es ABNER
-- GERARDO RUIZ GUERRERO, factura 3514) y su fecha está BIEN: su alisto se cerró
-- el 3-sep a las 12:02, dos minutos después del mediodía de su salida_en. Se
-- registró en el momento. Su albarán de Odoo (WH/OUT/02347) se validó el 7-sep
-- a las 11:15, igual que el del 44 — los dos en el mismo segundo, que es alguien
-- poniéndose al día en Odoo, no dos camiones. `date_done` mide la validación, no
-- la salida del pan (lo mismo que la entrega de BM del 7-sep, validada a las
-- 19:57). Para el 43 el testigo bueno es Truefie.
--
-- ── DE DÓNDE SALE LA HORA, Y POR QUÉ NO ES 11:15 ────────────────────────
-- La hora es el `preparado_en` del alisto vigente: 7-sep 07:58 CR. NO el
-- date_done de Odoo. Escribir 11:15:42 sería poner una hora ADMINISTRATIVA con
-- cara de medida, que es la falla exacta que esta corrección viene a arreglar.
-- Y es el modismo que el módulo ya usa: `ent_salido_del_congelador_desde_ancla`
-- resuelve `coalesce(sv.salida_en, av.preparado_en)` — el alisto es el testigo
-- cuando no hay salida medida. Acá se aplica la misma idea, no una nueva.
--
-- No se escribe un literal: la hora se LEE de ent_alisto_vigente. Una fecha
-- tecleada a mano es una fecha dicha de memoria, y de eso venimos.
--
-- ── QUÉ NO CAMBIA, Y ESTÁ VERIFICADO ABAJO ──────────────────────────────
-- · NINGÚN SALDO POR LOTE. El descuento usa
--   `coalesce(salida_en, preparado_en) > corte`, y el corte del ancla es el
--   29-ago 00:07 UTC. Antes (3-sep) y después (7-sep) los dos están DESPUÉS del
--   corte, así que el pedido se descontaba y se sigue descontando igual.
-- · El estado del pedido sigue siendo `entregado`.
-- · La fila vieja de ent_salida NO se borra ni se edita: queda como historia y
--   `ent_salida_vigente` (distinct on alisto_id, order by creado_en desc) toma
--   la nueva.
--
-- ── QUÉ SÍ CAMBIA, APROBADO POR ANDREA EL 8-SEP ─────────────────────────
-- El AB-RE-04. Las cinco líneas del pedido 44 pasan de la semana ISO 36 (3-sep,
-- jueves) a la 37 (7-sep, lunes), en unidad de VENTA:
--     Pan Blanco    217 / 2-27   ·  78 unidades   (13 cajas)
--     Semillas      225 / 2-27   · 126 unidades   (21 cajas)
--     Pan Francés   216 / 2-27   ·  48 paquetes   (8 cajas)
--     Pan Francés   221 / 2-27   ·   6 paquetes
--     Buns          191 / 1-27   ·  24 paquetes   (4 cajas)
-- Sin nota de documento emitido: la exportación del Historial no existe y el
-- Excel de Daniel se dejó de usar el 28-ago. La semana 36 solo existe adentro
-- de Truefie.
--
-- ── LO QUE ESTO NO ARREGLA, DICHO ───────────────────────────────────────
-- `ent_pedido.fecha_despacho` del pedido 44 se queda en 2026-09-03. La tabla no
-- tiene grant de UPDATE (append-only), así que no se puede corregir sin una fila
-- nueva de pedido, que sería peor. NO afecta ningún reporte: `fecha_ab_re_04` de
-- `v_ent_pedido_estado` es `coalesce(salida_en, fecha_despacho)` y salida_en
-- gana. Queda como residuo visible solo para quien lea la fila cruda.
-- ════════════════════════════════════════════════════════════════════════


-- ── 1 · ANTES DE ESCRIBIR: que la fila sea la que creemos ────────────────
-- Tiene que devolver UNA fila, cliente CORPORACION SUPERMERCADOS UNIDOS,
-- factura 00100001010000003515, preparado_en el 7-sep y salida_en el 3-sep.
-- Si devuelve otra cosa, NO SEGUIR.
--
-- ⚠️ LA FACTURA SE LEE DE `ent_pedido_factura_vigente`, NO DE
-- `ent_pedido.factura_nombre`. La primera versión de esta consulta leía la
-- columna de `ent_pedido` y devolvió NULL, que se lee como "el vínculo no
-- existe" — y es falso. ENTREGAS_SALIDAS.sql §2 declara esa columna OBSOLETA:
-- el vínculo vive SOLO en `ent_pedido_factura`. El pedido 44 nació `origen =
-- 'manual'` (sin factura), así que `despConfirmar` nunca escribió esa columna;
-- Andrea vinculó la 3515 desde Pendientes el 7-sep, y eso escribe únicamente en
-- la tabla del vínculo. Es exactamente la razón por la que la columna se
-- declaró obsoleta: leerla contesta mal.
select p.id as pedido, p.cliente_nombre,
       fv.factura_nombre                     as factura_del_vinculo,
       p.factura_nombre                      as factura_columna_obsoleta,
       av.alisto_id,
       av.preparado_en,
       (av.preparado_en at time zone 'America/Costa_Rica') as preparado_en_cr,
       sv.salida_en,
       (sv.salida_en at time zone 'America/Costa_Rica') as salida_en_cr
  from ent_pedido p
  join ent_alisto_vigente av on av.pedido_id = p.id
  left join ent_salida_vigente sv on sv.alisto_id = av.alisto_id
  left join ent_pedido_factura_vigente fv
         on fv.pedido_id = p.id and fv.anulado = false
 where p.id = 44;


-- ── 2 · LA CORRECCIÓN. Una fila nueva de ent_salida, y nada más ──────────
-- La guarda del `not exists` la hace segura de correr dos veces: si ya existe
-- una corrección de b56 para ese alisto, inserta CERO filas.
insert into ent_salida (alisto_id, salida_en, nota, creado_por)
select av.alisto_id,
       av.preparado_en,
       'Fecha de salida corregida a mano: la fecha es la real, la hora NO es medida'
         || ' · b56 8-sep-2026: el pedido nació sin factura el 3-sep y la 3515 se'
         || ' vinculó el 7-sep sin recalcular la fecha. La hora es el preparado_en'
         || ' del alisto (7-sep 07:58 CR), no el date_done de Odoo (11:15), que'
         || ' mide cuándo se validó el albarán y no cuándo salió el pan.'
         || ' Decidido por Andrea.',
       'correccion-sql · b56 · andrea@truefoodcr.com'
  from ent_alisto_vigente av
 where av.pedido_id = 44
   and not exists (select 1 from ent_salida s2
                    where s2.alisto_id = av.alisto_id
                      and s2.creado_por like 'correccion-sql · b56%');
-- Esperado: INSERT 0 1. Si dice INSERT 0 0, ya estaba corregido.


-- ── 3 · VERIFICACIÓN · pegar DESPUÉS, o pedírsela a Claude Code ──────────
-- (esto se puede correr con el lector de solo lectura, no hace falta pegarlo)
--
-- 3a · la salida vigente del 44 ya dice 7-sep, y el 43 sigue intacto en 3-sep:
--
--   select pedido_id, cliente_nombre, estado,
--          (preparado_en at time zone 'America/Costa_Rica') as preparado_cr,
--          (salida_en    at time zone 'America/Costa_Rica') as salida_cr,
--          extract(week from salida_en at time zone 'America/Costa_Rica') as semana_iso
--     from v_ent_pedido_estado where pedido_id in (43,44) order by pedido_id;
--
--   Esperado: 43 → salida 2026-09-03 12:00, semana 36 (SIN CAMBIO)
--             44 → salida 2026-09-07 07:58, semana 37
--
-- 3b · la historia quedó, no se borró nada (dos filas para el alisto del 44):
--
--   select s.id, s.alisto_id,
--          (s.salida_en at time zone 'America/Costa_Rica') as salida_cr,
--          s.creado_por, s.creado_en
--     from ent_salida s
--     join ent_alisto a on a.id = s.alisto_id
--    where a.pedido_id = 44 order by s.creado_en;
--
-- 3c · NINGÚN SALDO SE MOVIÓ. Tiene que dar exactamente lo mismo que el 7-sep:
--      451 → 713 · 452 → 121 · 453 → 1636 · 472 → 424 · 503 → 1444 · 519 → 101
--      (son unidades individuales, la escala interna del motor; en unidad de
--       venta eso es Blanco 713 u · Semillas 121 u · Francés 409 paq ·
--       Pizza 212 paq · Buns 361 paq · Galletas 101 u)
--
--   select a.producto_id,
--          sum(a.u) - coalesce(sum(s.uds),0) as saldo
--     from (select producto_id, lote, sum(uds) u from ent_conteo_linea
--            where conteo_id = (select id from ent_ancla) group by 1,2) a
--     left join ent_salido_del_congelador_desde_ancla s
--            on s.lote = a.lote and s.producto_id = a.producto_id
--    group by a.producto_id order by 1;
