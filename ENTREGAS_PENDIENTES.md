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

## 3 · ABIERTO · `WH/MO/01420` salió del horno sin número de lote

**Qué pasa.** Pan Blanco, 168 unidades, `date_start` 24-ago-2026 16:30 CR, `done`.
El chatter, escrito el 25-ago 08:34, dice literal:

```
WH/MO/01412 WH/MO/01419 ?/02 27
```

Keylor puso **`?`** donde va el día juliano. El extractor la manda a `sin_lote`
—correcto, no se inventa un lote— y el efecto es que **168 unidades que están en
el congelador no suman a ningún saldo**. No es un error de la herramienta: el
dato no existe en el origen.

**Por qué importa más de lo que parece.** Es la forma 1 de la fragilidad del
pendiente 5: si alguien mira el saldo de Blanco y lo ve corto, el faltante puede
estar acá, sin número, y nada lo dice. Un lote invisible no se distingue de un
sobregiro.

**Estado (25-ago-2026).** Keylor ya sabe y va a corregirlo a **236**, que es el
juliano que corresponde: 24-ago-2026 = día 236. Cuadra con `date_start`.

**Ojo al corregir:** hay que **editar** ese mensaje, no agregar otro. Dos lotes
válidos en el chatter marcan la orden `ambiguo` y el lote **desaparece** de la
lista — la trampa del `223` del 11-ago, ya documentada en `CLAUDE.md`.

---

## 4 · CERRADO (25-ago-2026) · Los saldos por lote después de la salida ...3489

**Qué se preguntó.** Si la salida del 24-ago (Automercado, registrada el 25 a las
10:49) había dejado algún lote en negativo. `main` está en b27, que no tiene
bloqueo duro, así que un sobregiro habría pasado en silencio.

**Resultado: cero negativos.** Saldos verificados con la lógica de
`rpCalcSaldos` — ancla del 14-ago + producción posterior por `date_start` −
salidas registradas:

| Producto · lote | Antes | Salió | Después |
|---|---|---|---|
| Buns `191 / 1-27` | 576 | 96 | 480 |
| Pizza `190 / 1-27` | 144 | 60 | 84 |
| Galletas `226 / 2-27` | 156 | 12 | 144 |
| Galletas `205 / 1-27` | 71 | 60 | 11 |
| Semillas `209 / 1-27` | 127 | 48 | 79 |
| Francés `203 / 1-27` | 360 | 288 | 72 |
| Blanco `208 / 1-27` | 126 | 84 | 42 |

**Tres cosas quedaron probadas, y vale tenerlas escritas:**

1. **`ENT_MO_EXCLUIDAS` funciona en producción.** Galletas `226 / 2-27` arrancó en
   **156, no en 316**: la exclusión de `WH/MO/01411` (las 160 u registradas 6 min
   después del corte del conteo) se aplicó. Huella verificada contra Odoo el
   25-ago — nombre, producto 519, 160 u, `date_start 2026-08-14 22:06:40`, `done`.
2. **La salida quedó registrada UNA vez** (`n_alistos: 1 · n_salidas: 1`) y con la
   verificación de factura en verde (`sin_verificar: null`). Sin nota de crédito
   en Odoo.
3. **Un negativo que NO es un sobregiro.** De los 34 lotes del ancla, el único en
   negativo es Blanco `230 / 2-27` en **−2**, y es artefacto del método: contar
   solo ancla − salidas **no suma la producción posterior al ancla**. Con
   `WH/MO/01414` (126 u, 18-ago) el saldo real es **124**. Cuadra exacto:
   −2 + 126 = 124. La herramienta no tiene este problema — `rpCalcSaldos` sí suma
   la producción; lo tiene una consulta que mire solo Supabase.

---

## 5 · Trazabilidad: lo frágil que el módulo convierte en estructura

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
