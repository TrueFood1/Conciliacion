# Entregas — pendientes anotados, no resueltos

## 1 · PRIORITARIO · El lote en pantalla no lleva el código de producto

**Qué pasa.** El número del lote es el **día juliano de producción**, y el día
juliano es del DÍA, no del producto. Si un día se producen dos cosas, las dos
salen con el mismo número y el mismo vencimiento. En pantalla quedan como la
**misma cadena** y no hay forma de distinguirlas.

El formato real del sticker es `DDD C / M AA`, donde `C` es el código de
producto: **Blanco 2 · Semillas 4 · Francés 1 · Buns 3 · Pizza 5 · Galletas 6**.
La forma canónica de la herramienta descarta ese código a propósito
(`_entParseLote`: *"la clave NO depende del código"*), así que `168 / 12-26` de
Buns y `168 / 12-26` de Pizza se leen idénticos.

**Casos reales, medidos el 19-ago-2026** — dos días distintos, dos colisiones:

| Día juliano | Fecha | Productos que comparten el número |
|---|---|---|
| 163 | 12-jun-2026 | Pizza Crust (`WH/MO/01332`) y Galletas (`WH/MO/01330`) |
| 168 | 17-jun-2026 | Buns y Semillas |

**Por qué no es cosmético.** En el cruce del 19-ago la Pizza del traslado interno
estaba anotada como `168 / 12-26` y el lote real era `163 / 12-26`. El error
sobrevivió a la hoja de Daniel, y **la única forma de resolverlo fue abrir el
chatter de la orden de producción en Odoo**. En la pantalla donde Daniel elige el
lote a las 6:30 de la mañana, con una mano libre, esa opción no existe.

**Lo que NO está roto.** La aritmética. El saldo va por `(producto, lote)` en las
dos puntas —`rpCalcSaldos` (`producto_id + '|' + lote`) y la vista
`ent_salido_del_congelador_desde_ancla` (`group by lote, producto_id`)— y la
clave de `_entAgrupar` lleva el producto desde b28. Dos productos con el mismo
juliano no comparten saldo. El problema es **de lectura humana**, y por eso no lo
caza ninguna comprobación numérica: los números cierran igual con el lote
equivocado, mientras el equivocado exista en el otro producto.

**Lo que hay que hacer.** Mostrar el código junto al lote donde Daniel elige
(selector de Despachos y del Reporte), y de paso donde se listan los lotes del
conteo. El dato ya está: `_entParseLote` lo parsea en `c.cod`, lo valida contra
`ENT_COD` y después lo tira. No hay que leer nada nuevo de Odoo.

**Ojo al hacerlo:** el código es OPCIONAL en el chatter. Un lote sin código no se
puede mostrar como si lo tuviera — va sin código y visible, nunca inventado.

---

## 2 · CERRADO (19-ago-2026) · Hueco de trazabilidad · orden WH/MO/01330

**Estaba así.** La orden `WH/MO/01330` (Galletas, 12-jun-2026, 160 unidades) no
tenía lote: el extractor la dejaba en el balde `sin_lote`, explícita, sin asumir
nada.

**Se resolvió.** Medido en el chatter el 19-ago: hay un mensaje de **Andrea
Fernandez del 13-ago-2026 20:36** que dice `163/12 26`. O sea que ya se llenó a
mano y las 160 unidades dejaron de ser un hueco.

**Lo que deja como enseñanza** es el pendiente 1: ese `163` es el mismo número
que el lote de Pizza del mismo día, y en pantalla no se distinguen.

---

## 3 · Trazabilidad: lo frágil que el módulo convierte en estructura

Vale dejarlo escrito porque es el argumento del módulo entero: hoy el lote es
texto libre en un comentario, y lo que sale del congelador no queda ligado a
ningún lote en ningún sistema. Odoo no lo respalda —los seis productos terminados
tienen `tracking = none` y los 1.604 movimientos de 2026 no llevan `lot_id`—, así
que la trazabilidad depende de que alguien escriba el lote a mano en el chatter.
El módulo no arregla Odoo (sigue siendo solo lectura) pero convierte las dos
puntas en dato estructurado: qué lote se fabricó (extractor) y qué lote salió
(`ent_alisto_lote`).

**Y la fragilidad tiene dos formas, no una:**

1. **Que no lo escriban** — el caso del pendiente 2, que se cerró llenándolo.
2. **Que lo escriban mal, o que se lea mal.** El chatter de `WH/MO/01332` dice
   `WH/MO/01326 163/12 26`: ese `WH/MO/01326` es la **premezcla** Pizza Crust
   [473] que se consumió, no la orden del terminado [472]. Leer la referencia
   como si fuera la orden lleva al producto equivocado — la misma trampa que
   `CLAUDE.md` ya anota para "Pizza Crust" vs "Premezcla Pizza Crust".
