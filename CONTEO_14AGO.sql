-- ════════════════════════════════════════════════════════════════════════
-- CONTEO DEL VIERNES 14-AGO-2026 · TRANSCRIPCIÓN DEL PAPEL DE DANIEL
-- Se carga por SQL porque la pantalla perdía datos ese día (bugs 1 y 2 del
-- 14-ago, arreglados en b15). Pegar UNA sola vez en el SQL Editor de Supabase.
--
-- Entra como BORRADOR: NO se inserta en ent_conteo_ancla. Confirmarlo como ancla
-- es un segundo gesto, desde la pantalla, cuando Andrea lo dé por bueno.
--
-- ⚠️ REVISAR ANTES DE PEGAR:
--   1. `corte` está puesto a las 18:00 del 14-ago (hora CR). ES LA LÍNEA
--      DIVISORIA de todos los saldos por lote: todo lo fabricado y entregado
--      después de ese instante se cuenta contra esta foto. Si Daniel contó a
--      otra hora, cambialo.
--   2. La NOTA dice que Pizza SÍ cuadra. Ver la explicación abajo.
--
-- ⚠️⚠️ EL LOTE 223 DE PAN BLANCO — LEER ANTES DE PEGAR
-- El conteo trae `223 / 2-27` con 20 cajas + 1 unidad, que es lo que hay en el
-- congelador. Pero **Odoo no conoce el 223**: la orden WH/MO/01408 (arrancó el
-- 11-ago 22:47, 126 unidades, 3 mermas) tiene en su chatter el número **222**.
--
-- Qué pasó, confirmado el 15-ago: en el reporte manual del 11-8-26 el lote está
-- TACHADO y corregido de 222 a 223. Keylor transcribió al chatter el número sin
-- corregir. No falta ninguna orden de producción: es la misma tanda con dos
-- números. Lo corrobora todo: la fecha (01408 arrancó el 11-ago), las mermas
-- (la hoja dice 3 por cortada en el 223 y 0 en el 224; Odoo tiene SP/00355 con
-- 3 unidades en 01408 y ninguna en 01409) y que no existe ningún otro 222.
--
-- CONSECUENCIA SI SE PEGA ASÍ, SIN TOCAR ODOO: el saldo por lote va a mostrar un
-- 222 fantasma con 126 unidades que nadie contó, y un 223 con 121 unidades que
-- Odoo nunca fabricó. Los dos números están mal.
--
-- ⚠️ Y CUIDADO CÓMO SE CORRIGE EN ODOO: **NO agregar un comentario nuevo con el
-- 223.** El extractor junta TODOS los lotes que encuentra en el chatter, y si
-- encuentra dos válidos marca la orden como `ambiguo` y **el lote desaparece de
-- la lista del conteo**. Hay que EDITAR o BORRAR el mensaje que dice 222, no
-- sumarle otro.
--
-- ── SOBRE PIZZA, QUE SE CREÍA DESCUADRADA ───────────────────────────────
-- El resumen decía "39 CJ y 13 Uds" = 247 paquetes contra 251 esperados, y se
-- pidió cargarlo con una nota de discrepancia. **No hay discrepancia.** El
-- detalle por lote suma 17 sueltas, no 13: al sumar la columna se quedaron sin
-- contar las 4 del renglón `211-1/27 · 19 CJ 4 Uds`, que lleva cajas Y sueltas
-- en la misma línea. Con 17: 39 cajas × 6 paquetes + 17 = **251 paquetes**,
-- exactamente lo esperado y lo que dice Odoo.
-- Los otros cinco productos cuadran con su total declarado sin tocar nada.
--
-- ── CONVERSIONES USADAS (NIV_INFO de index.html) ────────────────────────
--   producto        caja       "Uds" de Daniel     uds = cajas×cajaU + sueltas×presDiv
--   Pan Blanco      6 u        unidad sueltas      cajas×6  + sueltas×1
--   Pan Semillas    6 u        unidad sueltas      cajas×6  + sueltas×1
--   Pan Francés     24 u       paquete de 4        cajas×24 + sueltas×4
--   Buns            24 u       paquete de 4        cajas×24 + sueltas×4
--   Pizza Crust     12 u       paquete de 2        cajas×12 + sueltas×2
--   Galletas        12 potes   pote suelto         cajas×12 + sueltas×1
-- `sueltas` se guarda TAL COMO lo contó Daniel (paquetes donde cuenta paquetes),
-- que es lo que hace la pantalla; `uds` es la conversión a unidades individuales.
--
-- ── FORMATO DEL LOTE ────────────────────────────────────────────────────
-- Canónico de la herramienta: `DDD / M-AA`, mes SIN cero a la izquierda y año
-- con dos dígitos (así lo arma `_entParseLote`). "082-9/26" entra como
-- "82 / 9-26" — el número pierde el cero, si no el saldo por lote no cruza.
-- ════════════════════════════════════════════════════════════════════════

with c as (
  insert into ent_conteo (fecha, corte, responsable, nota, creado_por)
  values ('2026-08-14', '2026-08-14 18:00:00-06', 'Daniel',
          'Transcrito del conteo manual de Daniel del 14-ago. Pizza VERIFICADA: el '
          'detalle suma 251 paquetes (39 cj × 6 + 17 sueltas), igual que Odoo. El '
          '"39 CJ y 13 Uds" del resumen dejaba fuera las 4 sueltas del renglón '
          '211-1/27, que lleva cajas y sueltas en la misma línea.',
          'carga-sql')
  returning id
)
insert into ent_conteo_linea (conteo_id, producto_id, lote, cajas, sueltas, uds)
select c.id, v.producto_id, v.lote, v.cajas, v.sueltas, v.uds from c, (values
  -- Pan Blanco: 147 cajas + 5 u = 887 u
  (451, '223 / 2-27', 20, 1, 121),
  (451, '195 / 1-27', 10, 4, 64),
  (451, '224 / 2-27', 21, 0, 126),
  (451, '215 / 2-27', 24, 0, 144),
  (451, '217 / 2-27', 21, 0, 126),
  (451, '208 / 1-27', 21, 0, 126),
  (451, '202 / 1-27', 21, 0, 126),
  (451, '201 / 1-27', 9, 0, 54),
  -- Pan Semillas: 97 cajas + 6 u = 588 u
  (452, '225 / 2-27', 28, 0, 168),
  (452, '209 / 1-27', 34, 1, 205),
  (452, '176 / 12-26', 6, 2, 38),
  (452, '218 / 2-27', 27, 3, 165),
  (452, '126 / 11-26', 2, 0, 12),
  -- Pan Francés: 75 cajas + 2 paq = 1808 u
  (453, '216 / 2-27', 15, 0, 360),
  (453, '197 / 1-27', 15, 0, 360),
  (453, '221 / 2-27', 15, 0, 360),
  (453, '203 / 1-27', 15, 0, 360),
  (453, '204 / 1-27', 15, 0, 360),
  (453, '182 / 12-26', 0, 2, 8),
  -- Buns: 76 cajas + 6 paq = 1848 u
  (503, '212 / 1-27', 28, 0, 672),
  (503, '175 / 12-26', 24, 0, 576),
  (503, '191 / 1-27', 24, 0, 576),
  (503, '168 / 12-26', 0, 6, 24),
  -- Pizza Crust: 39 cajas + 17 paq = 502 u
  (472, '211 / 1-27', 19, 4, 236),
  (472, '190 / 1-27', 16, 0, 192),
  (472, '183 / 12-26', 4, 0, 48),
  (472, '120 / 10-26', 0, 4, 8),
  (472, '146 / 11-26', 0, 3, 6),
  (472, '163 / 12-26', 0, 3, 6),
  (472, '82 / 9-26', 0, 2, 4),
  (472, '107 / 10-26', 0, 1, 2),
  -- Galletas: 19 cajas + 2 u = 230 u
  (519, '205 / 1-27', 6, 0, 72),
  (519, '226 / 2-27', 13, 2, 158)
) as v(producto_id, lote, cajas, sueltas, uds);


-- ── COMPROBACIÓN, correr después ────────────────────────────────────────
-- select p.producto_id, count(*) lotes, sum(p.cajas) cajas, sum(p.sueltas) sueltas, sum(p.uds) uds
--   from ent_conteo_linea p
--  where p.conteo_id = (select max(id) from ent_conteo)
--  group by p.producto_id order by p.producto_id;
--
--   451 Pan Blanco    8 lotes · 147 cj ·  5 ·  887 u
--   452 Pan Semillas  5 lotes ·  97 cj ·  6 ·  588 u
--   453 Pan Francés   6 lotes ·  75 cj ·  2 · 1808 u
--   472 Pizza Crust   8 lotes ·  39 cj · 17 ·  502 u   (= 251 paquetes)
--   503 Buns          4 lotes ·  76 cj ·  6 · 1848 u
--   519 Galletas      2 lotes ·  19 cj ·  2 ·  230 u
--
-- select id, fecha, corte, responsable from ent_conteo order by id desc limit 1;
-- select count(*) from ent_conteo_ancla where conteo_id=(select max(id) from ent_conteo);
--   → 0: entró como BORRADOR, como se pidió.
