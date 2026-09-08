-- ════════════════════════════════════════════════════════════════════════
-- ARREGLO: el saldo por lote se descontaba por la fecha del ALISTO
-- Medido el 7-sep-2026. LISTO PARA PEGAR UNA SOLA VEZ en el SQL Editor.
--
-- Es UNA vista, `create or replace`. No toca datos, no migra nada, y se puede
-- correr más de una vez. Para volver atrás, pegar la definición vieja.
--
-- ── EL DEFECTO ──────────────────────────────────────────────────────────
-- `ent_salido_del_congelador_desde_ancla` filtraba por `av.preparado_en`, o sea
-- por CUÁNDO SE ALISTÓ, no por cuándo salió la mercadería. Si algo se alista
-- antes del conteo y sale después, entra en la foto del ancla Y NUNCA SE RESTA.
--
-- El caso que lo destapó: los pedidos 33 (Automercado, 96 u) y 34 (CSU, 168 u)
-- se alistaron el 28-ago a las 14:42 y 14:46 CR; Andrea contó a las 18:07; y los
-- dos salieron el 2-sep — lo dicen las dos fuentes, `ent_salida.salida_en` y el
-- albarán de Odoo. 264 unidades del lote 191 contadas y nunca descontadas.
--
-- ── EL ARREGLO NO ES CAMBIAR preparado_en POR salida_en A SECAS ──────────
-- Eso rompería otra cosa: un pedido ALISTADO Y TODAVÍA SIN SALIR dejaría de
-- descontarse, y la pantalla volvería a ofrecer un lote que ya está apartado en
-- la puerta. Por eso va `coalesce`, que es correcto en los cuatro casos:
--
--   alistado antes del corte, salió después  → manda salida_en  → SE DESCUENTA
--       (el defecto arreglado: no estaba cuando se contó... sí estaba, y se fue)
--   alistado antes, todavía sin salir        → cae en preparado_en → no se descuenta
--       (estaba en el congelador cuando se contó, y sigue estando)
--   alistado después, sin salir              → preparado_en      → se descuenta
--       (no estaba en la foto, y está comprometido)
--   salida retroactiva anterior al corte     → manda salida_en   → no se descuenta
--       (se fue antes de que se contara, así que la foto no lo vio)
--
-- Es además el mismo modismo que ya usa `fecha_ab_re_04` en
-- `v_ent_pedido_estado`. Una sola idea en el módulo, no dos.
--
-- ── QUÉ CAMBIA, MEDIDO ANTES DE PEGARLO ─────────────────────────────────
-- Se calculó el criterio nuevo como CTE contra la base real, sin aplicar nada.
-- NO es solo Buns: el defecto es de la vista, así que toca a los seis.
--
--   producto   ancla   saldo ANTES   saldo DESPUÉS
--   Blanco       983          863            713     (−150)
--   Semillas     357          205            121      (−84)
--   Francés     2320         2044           1636     (−408)
--   Pizza        532          508            424      (−84)
--   Buns        1908         1708           1444     (−264)
--   Galletas     149          149            101      (−48)
--
-- Diez lotes cambian. Tres de Francés (197, 203 y 204) pasan a CERO: estaban
-- agotados y la pantalla los seguía ofreciendo.
--
-- ⚠️ TODOS LOS SALDOS BAJAN. La vista rota venía SOBREESTIMANDO el inventario en
--    1.038 unidades, o sea que se estaba ofreciendo producto que no estaba.
--
-- ── LA COMPROBACIÓN QUE LE DA CONFIANZA ─────────────────────────────────
-- Buns contra el conteo físico de la mañana del 7-sep (Daniel: 30 cajas del 238,
-- 22 del 212, 1 caja + 5 paquetes del 191):
--
--   lote          saldo nuevo   congelador   dif
--   238 / 2-27            720          720    +0   ← exacto
--   212 / 1-27            672          528  +144
--   191 / 1-27             40           44    −4
--   175 / 12-26            12            0   +12
--   TOTAL                1444         1292  +152
--
-- Y las +152 que sobran son EXACTAMENTE las dos salidas que se sabe que no están
-- registradas en el módulo: las 144 u de Automercado del 7-sep (WH/OUT/02349) y
-- las 8 u del traslado del summit (WH/INT/00137). El arreglo deja el residuo
-- explicado entero; lo que falta ya no es la vista, son registros.
-- ════════════════════════════════════════════════════════════════════════

create or replace view ent_salido_del_congelador_desde_ancla
  with (security_invoker = true) as
  select al.lote,
         ali.producto_id,
         sum(al.cant_uds) as uds
    from ent_alisto_lote  al
    join ent_alisto_linea ali on ali.id        = al.linea_id
    join ent_alisto_vigente av on av.alisto_id = ali.alisto_id
    -- LEFT: un alisto sin salida todavía es legítimo (está preparado, no salió).
    -- Con INNER desaparecería del descuento y el lote se volvería a ofrecer.
    left join ent_salida_vigente sv on sv.alisto_id = av.alisto_id
   where coalesce(sv.salida_en, av.preparado_en) > (select corte from ent_ancla)
   group by al.lote, ali.producto_id;


-- ── VERIFICACIÓN, para pegar DESPUÉS ────────────────────────────────────
-- Tiene que devolver exactamente estas seis filas:
--
--   select producto_id,
--          sum(a.u) - coalesce(sum(s.uds),0) as saldo
--     from (select producto_id, lote, sum(uds) u from ent_conteo_linea
--            where conteo_id = (select id from ent_ancla) group by 1,2) a
--     left join ent_salido_del_congelador_desde_ancla s
--            on s.lote = a.lote and s.producto_id = a.producto_id
--    group by 1 order by 1;
--
--   451 → 713 · 452 → 121 · 453 → 1636 · 472 → 424 · 503 → 1444 · 519 → 101
--
-- Si Buns no da 1444, algo salió distinto de lo medido: NO seguir, avisar.


-- ── LO QUE ESTE ARREGLO NO TOCA ─────────────────────────────────────────
-- · `ent_devuelto_desde_ancla` filtra por `dv.recibido_en`, y está BIEN: una
--   devolución no tiene una "salida" aparte, el instante en que se recibe ES el
--   hecho. Se revisó y no se cambia.
-- · Los scripts sueltos DIAGNOSTICO_NEGATIVOS.sql, DIAGNOSTICO_LOTE208_
--   MOVIMIENTOS.sql y FOTO_ANTES_DEL_REANCLE.sql copian el criterio viejo por su
--   cuenta. No son objetos vivos —no afectan a la app— pero van a dar respuestas
--   equivocadas si alguien los corre. Quedan anotados, no corregidos acá: este
--   .sql es el arreglo de la vista y nada más.
-- · No corrige ningún dato. Las salidas que faltan (summit, Pan Blanco de
--   Automercado, Bmquepos) siguen faltando después de pegar esto.
