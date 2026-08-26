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

---

## 6 · ABIERTO · `presentacion` guarda "caja" donde debería decir "paquete"

**Qué pasa.** `ent_pedido_linea.presentacion` se escribe así desde que existe el
lector de facturas:

```js
presentacion: (L.uom_factor === 1 ? 'uds' : 'cj')
```

O sea: *todo lo que no sea "Unidades" se guarda como CAJA*. Una línea facturada
en `Paquete de 4` [37] queda grabada como `'cj'`. **2 paquetes de 4 son 8
unidades, no 2 cajas**, y en Truefie "caja" es un objeto físico concreto —6 u en
Blanco/Semillas, 24 en Francés/Buns, 12 en Pizza—, así que la fila afirma algo
falso sobre lo que salió del congelador.

**Lo encontró Andrea el 26-ago-2026** probando en iPhone el diálogo de "Preparar
y entregar" con la **factura 3496**: la línea decía *"2 Paquete de
4"* y la conversión de al lado *"2 cj"*.

### Lo que YA se arregló (26-ago, b34) y lo que NO

- ✅ **La pantalla.** El rótulo corto ya no se deduce del factor: sale de
  `DESP_UOM_CORTA`, una tabla **por ID** de unidad (`37, 38, 50 → paq` ·
  `42, 44, 46, 49 → cj` · `1 → u` · `2 → doc`). Lo que no está en la tabla no se
  adivina: se muestra el nombre completo que vino de Odoo.
- ✅ **Nada lee ya `presentacion` para rotular.** Los dos diálogos pasaron a
  `uom_id`, que se guarda en la misma fila y es la unidad verdadera.
- ✅ **La aritmética nunca estuvo mal** y sigue igual: `cant_uds = cant ÷
  uom_factor`, con el factor real leído por ID y congelado en la línea.
  Verificado el 26-ago contra las **27 facturas** desde el arranque del módulo
  (15-ago): las 7 UoM en uso —`[1] Unidades`, `[37] Paquete de 4`, `[46] Caja`,
  `[44] Caja (Frances)`, `[42] Caja (Hamburguesa)`, `[49] Caja (Pizza)`,
  `[38] Paquete de 2`— están todas dentro del filtro del diálogo
  (`category_id.name = 'Unidad'`), así que **ninguna cayó al factor 1 por
  defecto**. Cero entregas registradas con el número equivocado.
- ❌ **La columna sigue guardando mal.** No se tocó a propósito.

### Por qué no se arregló la columna

La base tiene el candado puesto:

```sql
presentacion  text  not null  check (presentacion in ('cj','uds'))
```

No puede decir `'paq'` sin **migrar la columna** (ampliar el check, o retirar la
columna). Y `presentacion` es compartida: el camino manual de *Entregas sin
factura* la usa con esos dos valores elegidos por quien registra, no deducidos de
una UoM. Cambiarla a la ligera rompe ese camino — `rpEditarLinea` la lee de
vuelta para encender los botones "Cajas" / "Unidades".

Hoy no hay error a la vista y no entra en ninguna cuenta: es **deuda de dato**,
no un bug vivo. Por eso queda anotada en vez de parchada con apuro.

### Qué hay que decidir cuando se toque

1. **Qué pasa con las filas viejas.** Hay líneas ya guardadas con `'cj'` donde
   corresponde "paquete". ⚠️ **En este proyecto no se pisan datos: se corrige con
   registros nuevos.** Un `UPDATE` sobre las filas existentes está fuera de la
   regla. Las opciones a evaluar son (a) dejarlas como están y que la lectura
   siempre derive de `uom_id` —que es lo que ya hace la app—, o (b) escribir
   filas de corrección que digan qué se corrigió, cuándo y por qué, dejando la
   original visible. Decisión de Andrea.
2. **Si la columna sigue existiendo.** `uom_id`, `uom_nombre`, `uom_factor` y
   `cant_uom` ya viven en la misma fila y son la fuente verdadera.
   `ENTREGAS_DESPACHOS.sql` ya la declara "por compatibilidad con lo ya
   guardado". Puede que lo correcto sea **retirarla**, no ampliarla.
3. **El camino manual primero.** Cualquier cambio tiene que contemplar
   *Entregas sin factura*, que es el otro escritor de esta columna.

### Cómo ver cuáles son (solo lectura)

```sql
-- Líneas guardadas como "caja" que en realidad son paquete
select pl.pedido_id, p.factura_nombre, p.cliente_nombre, p.fecha_despacho,
       pl.producto_id, pl.uom_id, pl.uom_nombre, pl.presentacion,
       pl.cant_uom, pl.cant_uds
from ent_pedido_linea pl
join ent_pedido p on p.id = pl.pedido_id
where pl.presentacion = 'cj'
  and pl.uom_id in (37, 38, 50)      -- Paquete de 4 · de 2 · de 12
order by p.fecha_despacho, pl.pedido_id;
```

Referencia de Odoo (26-ago): desde el 15-ago hay **15 facturas** con líneas en
paquete — 3478, 3479, 3482, 3483, 3485, 3487, 3488, 3491, 3492, 3494, 3496,
3497, 3500, 3501, 3502. Cuántas de ellas llegaron a `ent_pedido_linea` depende de
cuáles se registraron por el módulo; el SELECT de arriba da la lista real.

---

## 7 · ABIERTO · Anular un despacho desde la pantalla, con motivo obligatorio

**El caso que lo abrió.** El 26-ago-2026 apareció el primero: el **despacho 11**
(Mentha y limón, 19-ago, factura ...3484) registraba una salida que **nunca
ocurrió**. Entró en el cargue retroactivo del 19-ago desde la hoja de Daniel —
la hoja tenía el bloque anotado y la factura existía en Odoo, así que el cargue lo
dio por salido. Pero el pan no salió ese día: la entrega no se hizo, por eso se
anuló la 3484 (NC id 40822) y su traslado `WH/OUT/02319` quedó `cancel`. El
producto salió el **26-ago con la ...3499**. El lote quedó descontado **dos
veces** y el saldo, 6 u por debajo del congelador físico en dos lotes.

**El problema de fondo: no hay forma de corregirlo desde la pantalla.** Hizo falta
SQL a mano (`CORRECCION_DESP11.sql`). Y va a volver a pasar: en 2026 hubo **37
reversiones administrativas** contra 6 devoluciones reales. Cada vez que una
entrega se cae después de registrada, hoy hace falta una sesión con SQL.

### Lo que el esquema YA resuelve (no hay que inventar nada)

`ent_anulacion` existe desde el 19-ago y está pensada exactamente para esto:
anular es **insertar** `(entidad, entidad_id, motivo, creado_por)`, con
`entidad in ('alisto','salida')`. `ent_alisto_vigente` y `ent_salida_vigente` ya
la respetan. Falta **solo la pantalla**.

⚠️ **Y hay que anular el ALISTO, no solo la salida.** El saldo se descuenta al
PREPARAR: `ent_salido_del_congelador_desde_ancla` suma desde `ent_alisto_lote`
pasando por `ent_alisto_vigente`. Anular solo la salida devuelve el pedido a
"Preparado" y deja el saldo igual de mal. Son dos gestos distintos y la pantalla
tiene que distinguirlos:

- **"No salió, pero sigue preparado"** → anular la salida. El pedido vuelve a la
  bandeja. El saldo NO cambia (el producto sigue fuera del congelador).
- **"Esto nunca pasó"** → anular el alisto (y su salida). El saldo VUELVE.

### Lo que hay que construir

1. Un control en el detalle del despacho, con **motivo obligatorio y de texto
   libre** — acá el motivo no se puede cerrar en una lista: "la hoja lo tenía
   anotado pero el pan no salió" no entra en ninguna categoría previsible.
2. Que diga **cuánto vuelve al saldo, por lote, ANTES de confirmar**. Es la única
   forma de que quien anula vea lo que está moviendo.
3. Que quede **visible que fue anulado y por qué** en el historial. Anular no es
   esconder: la fila se queda, con su motivo.

### Un cabo suelto que deja la anulación

Un pedido de venta cuyo alisto queda anulado **sigue apareciendo en "Salida de
venta, sin factura vinculada"**, porque esa lista solo mira `motivo = 'venta'` y
la ausencia de vínculo — no mira si el alisto sigue vigente. El despacho 11 va a
quedar ahí sin nada que hacer. Hay que decidir si esa lista excluye los pedidos
sin alisto vigente (ojo: un pedido que todavía NO se preparó también está sin
alisto, y ése sí tiene que aparecer — no es la misma cosa).

⚠️ **Y OJO CON UNA COSA ANTES DE CONSTRUIRLO**: hoy anular es un camino de una
sola dirección — ver §8. El primer caso real de anulación (este mismo despacho
11) resultó ser un error de diagnóstico que hubo que revertir al día siguiente
re-registrando el alisto a mano. Un botón de anular sin deshacer es una trampa;
§8 va antes que §7, o al menos junto.

### Ya arreglado de paso (26-ago, b38)

`pdLeer` leía `ent_alisto.anulado`, la columna que `ENTREGAS_ETAPAS.sql` §2
declara MUERTA: no tiene grant de UPDATE, así que nadie puede ponerla en true
nunca. Con la tabla cruda, un despacho anulado seguía saliendo en Pendientes para
siempre. Pasó a `ent_alisto_vigente`, que es la que refleja `ent_anulacion`.

---

## 8 · ABIERTO · `ent_anulacion` es de una sola dirección — no se puede revertir

Descubierto el 26-ago-2026 al tener que deshacer una anulación mal hecha (ver §7
y `CORRECCION_DESP11_REVERTIR.sql`).

**El problema.** `ent_anulacion` no tiene columna para anularse a sí misma, y las
dos vistas la leen con `not exists`:

```sql
where a.anulado = false
  and not exists (select 1 from ent_anulacion x
                   where x.entidad = 'alisto' and x.entidad_id = a.id)
```

Cualquier fila de anulación es **final**: una fila posterior no la deshace.
Anular es fácil y desanular es imposible sin tocar el esquema.

**Por qué importa ahora.** El pendiente §7 es construir la anulación desde la
pantalla. Si se construye sobre este esquema, se le está dando a alguien un botón
que **no tiene vuelta atrás** — y el primer caso real de anulación (el despacho
11) resultó ser un error de diagnóstico que hubo que revertir al día siguiente.
Un botón de anular sin deshacer es una trampa.

**Lo que habría que cambiar.** Agregar a `ent_anulacion` una columna que apunte a
la fila que la revierte (o un `anulado boolean`, el mismo patrón de
`ent_pedido_factura`), y pasar las dos vistas de `not exists` a **"gana la fila
más reciente"**, que es el criterio que el resto del módulo ya usa para el ancla,
el motivo y el vínculo a la factura. ⚠️ Toca `ent_alisto_vigente` y
`ent_salida_vigente`, de las que cuelgan los saldos, `v_ent_pedido_estado` y
Pendientes: no es un cambio para hacer con urgencia, y hay que probarlo antes.

**Mientras tanto**, revertir se hace **re-registrando** el alisto (append-only,
sin DDL): las filas de anulación se quedan como evidencia y se inserta el alisto
de nuevo con su misma fecha, líneas y lotes. Es lo que hace
`CORRECCION_DESP11_REVERTIR.sql` y funciona, pero deja el pedido con dos alistos.

---

## 9 · ABIERTO · "Despachar igual" no se persiste

El filtro de "Facturas sin despacho pendiente" (b39) aparta las facturas que ya
tienen su entrega hecha en Odoo, y deja el botón **"Despachar igual"** para
cuando el filtro se equivoque. Ese botón hoy es **de la sesión**: se guarda en
`_despForzar`, una variable en memoria. Si se recarga la pantalla antes de
despachar, la factura vuelve a la lista apartada.

Alcanza para el uso previsto —se confirma y se despacha en el momento— pero no
para el caso de "la aparto ahora y la despacho mañana". Persistirlo pide una
tabla (`ent_factura_forzada`, append-only con su motivo, como todo lo demás) y
decidir si la decisión es para siempre o solo para esa factura y esa fecha.

Aprobado como está por Andrea el 26-ago; anotado para cuando moleste.
