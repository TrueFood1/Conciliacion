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

## 9 · EN CURSO (26-ago) · "Despachar igual" no se persiste — y falta "Revisado"

> ✅ **EL FILTRO ATRAPÓ SU PRIMER CASO REAL EN VIVO (27-ago-2026).** Apareció la
> factura **...3504 (Bm De Uvita, 2 cajas de Pan Blanco)** marcada *"sin pedido de
> venta en Odoo"*. Andrea confirmó: la creó Keylor para resolver algo contable, y
> **no hay nada que entregar**. La segunda red hizo exactamente lo suyo — la
> factura **nunca llegó a "Por preparar"**, así que nadie sacó pan del congelador
> contra un papel administrativo. Se marca "Revisado" y sale de la lista.
> Es la primera evidencia medida de que el filtro aparta bien, y no solo de que
> aparta: hasta hoy solo sabíamos que filtraba 2 de 493 y que las dos eran
> administrativas, pero por reconstrucción, no viéndolo pasar.

El filtro de "Facturas sin despacho pendiente" (b39) aparta las facturas que ya
tienen su entrega hecha en Odoo, y deja el botón **"Despachar igual"** para
cuando el filtro se equivoque. Ese botón hoy es **de la sesión**: se guarda en
`_despForzar`, una variable en memoria. Si se recarga la pantalla antes de
despachar, la factura vuelve a la lista apartada.

Alcanza para el uso previsto —se confirma y se despacha en el momento— pero no
para el caso de "la aparto ahora y la despacho mañana". Persistirlo pide una
tabla (`ent_factura_forzada`, append-only con su motivo, como todo lo demás) y
decidir si la decisión es para siempre o solo para esa factura y esa fecha.

**Molestó el mismo día.** Andrea lo probó desde el iPhone: la lista **solo
crece**, porque el único botón es "Despachar igual" —que hace lo contrario de
marcarla como vista— y encima se pierde al recargar. Con ~41 reversiones
administrativas al año, en un año son 41 filas que nadie puede sacar.

**Lo aprobado el 26-ago**, pendiente de construir:
1. Botón **"Revisado"**: la marca como vista y sale de la lista. ⚠️ "Revisado" y
   NO "Validado": en este módulo validar ya significa *validar la entrega en
   Odoo* —el botón "Ya validé" de la misma pantalla— y dos palabras iguales para
   dos cosas distintas en la misma vista es exactamente lo que no puede pasar.
2. **"Despachar igual" se persiste** en la misma tabla: las dos decisiones son de
   la misma naturaleza —un humano miró una factura apartada y dijo qué hacer— y
   merecen el mismo registro, con quién y cuándo.
3. **Red por tiempo**: lo que nadie tocó en 30 días se pliega bajo un
   "ver N antiguas". No desaparece, pero la lista deja de crecer sin fin.

**El esquema ya está escrito**: `ENTREGAS_DECISION_FACTURA.sql` crea
`ent_factura_decision` (append-only, gana la fila más reciente, con el motivo del
filtro congelado en la fila) y su vista vigente. **Falta pegarlo**, y recién
después se construye la pantalla.

---

## 10 · APARCADO (27-ago) · No se puede CAMBIAR la factura de un despacho ya vinculado

> ⚠️ **APARCADO EL 27-AGO — sigue siendo pendiente válido, pero YA NO HAY CASO
> REAL ESPERANDO.** Mentha contestó, y el enredo se deshizo por otro camino: la
> entrega del 19-ago (despacho 11) **la recibieron y se la quedan**, y la factura
> ...3499 del 26-ago —emitida con otra intención— es la que van a pagar por ella.
> No hay nada que re-emitir ni que re-apuntar. Lo que vuelve es el despacho 20
> (ver §11). **Con 41 reversiones administrativas al año esto va a volver**, así
> que el diagnóstico de abajo se conserva entero, incluido el diseño de la
> pantalla y la decisión sobre el índice único. NO SE CONSTRUYÓ NADA.
>
> Del diagnóstico del 27-ago quedaron tres cosas anotadas que no estaban acá:
> 1. **Son DOS índices viejos, no uno**: `ent_pedido_factura_uidx`
>    (`ENTREGAS_ESQUEMA.sql:73`) y `ent_pedido_factura_unico`
>    (`ENTREGAS_DESPACHOS.sql:69`), los dos sobre `ent_pedido(factura_id)`.
> 2. **`ent_pedido_factura_vigente` no tiene desempate.** Ordena por `creado_en
>    desc` a secas, y `creado_en` usa `default now()`, que en Postgres es la hora
>    de la TRANSACCIÓN: dos filas insertadas juntas empatan y gana cualquiera.
>    Falta `, id desc`.
> 3. **El `coalesce` de `v_ent_pedido_estado` puede resucitar la factura vieja.**
>    El join pide `fv.anulado = false`; si la fila vigente de un pedido tuviera
>    `anulado = true`, el join no trae nada y el `coalesce` cae en
>    `ent_pedido.factura_id`, la columna obsoleta. Hoy nadie escribe `anulado =
>    true` desde la app; §10 es justo el pendiente que lo vuelve alcanzable.
>
> Y una consecuencia que la pantalla va a tener que decir en letras: **cambiar la
> factura A por la B devuelve la A a "Por preparar"** (pierde su vínculo vigente,
> y desde el 26-ago `v_ent_factura_despachada` lee el vínculo). Es correcto, pero
> se lee como un pendiente que apareció solo.

**El caso vivo (26-ago-2026) — RESUELTO POR OTRO CAMINO, ver el recuadro.** Mentha y limón se quedó con el producto de la
entrega del 19-ago (despacho 11), cuya factura ...3484 se anuló. Andrea va a
emitir una **factura nueva** por esas 12 unidades. Hay que apuntar el despacho 11
a la factura nueva — y **sin registrar una entrega nueva**, porque el movimiento
físico ya está registrado con sus lotes (`202 / 1-27` y `209 / 1-27`). Registrar
otro descontaría esos lotes dos veces.

Hoy no hay forma. El botón "Vincular factura" de Pendientes solo aparece para los
despachos que **no tienen ninguna**: es para llenar un hueco, no para reemplazar.

Con **37 reversiones administrativas al año**, esto vuelve.

### La buena noticia: el dato ya sabe hacerlo

`ent_pedido_factura_vigente` es **"gana la fila más reciente"**, no `not exists`:

```sql
select distinct on (pedido_id) pedido_id, factura_id, factura_nombre, anulado, ...
  from ent_pedido_factura
 order by pedido_id, creado_en desc;
```

O sea que **cambiar la factura ya es posible a nivel de datos**: se INSERTA una
fila con la factura nueva y esa pasa a ser la vigente. No hace falta anular la
anterior ni tocar el esquema. (Es justo lo contrario de `ent_anulacion` — ver §8.)

### La mitad peligrosa — RESUELTA el 26-ago con `VISTA_FACTURA_DESPACHADA.sql`

**`v_ent_factura_despachada` NO lee el vínculo vigente. Lee
`ent_pedido.factura_id`**, la columna que `ENTREGAS_SALIDAS.sql` §2 declara
OBSOLETA y que no tiene grant de UPDATE:

```sql
create or replace view v_ent_factura_despachada ... as
  select p.factura_id, p.id as pedido_id, ...
    from ent_pedido p
    join ent_alisto_vigente av on av.pedido_id = p.id
   where p.origen = 'factura' and p.factura_id is not null;
```

Esa vista es la que saca de "Por preparar" las facturas ya despachadas.
Consecuencia: **cambiar el vínculo NO va a sacar la factura nueva de "Por
preparar"**. Va a quedar ahí, con pinta de pendiente legítima, y el primero que
la prepare descuenta los lotes por segunda vez — exactamente lo que este pendiente
existe para evitar.

✅ **YA ARREGLADO** (`VISTA_FACTURA_DESPACHADA.sql`, 26-ago). La vista pasó a
leer `ent_pedido_factura_vigente`, así que cambiar el vínculo SÍ saca la factura
nueva de la bandeja. De paso se le quitó la condición `p.origen = 'factura'`: con
el vínculo en su propia tabla, lo que despacha una factura es TENER vínculo
vigente y alisto vigente, no cómo nació el pedido — un despacho cargado a mano y
vinculado después también tiene que sacarla.

⚠️ **El orden importaba**: la vista se cambió DESPUÉS de `VINCULOS_BACKFILL.sql`.
Al revés, las 23 facturas ya despachadas habrían vuelto a "Por preparar" con el
producto fuera del congelador. El bloque lleva un candado que lo impide.

⚠️ **Lo que queda abierto de esto**: el índice único `ent_pedido_factura_unico`
—la red que impide dos pedidos para la misma factura— vive sobre
`ent_pedido(factura_id)`, la columna vieja. `ent_pedido_factura` NO tiene índice
único (el esquema lo dice: "se valida en la app"). Cuando se construya el cambio
de factura, esa red hay que rehacerla del lado nuevo o el control queda en la app
sola.

### Cómo debería funcionar

1. **En el detalle del despacho**, no en Pendientes: un control "Cambiar la
   factura" disponible **también cuando ya tiene una**, mostrando cuál tiene hoy.
2. **Motivo obligatorio, texto libre.** "La 3484 se anuló y se re-emitió como
   ...35xx" no entra en ninguna lista cerrada.
3. **Que diga en letras que NO registra una entrega nueva** y que los lotes no se
   vuelven a descontar. Es la duda que va a tener quien lo use, y es lo que hace
   que el gesto sea seguro.
4. ~~`v_ent_factura_despachada` tiene que pasar a `ent_pedido_factura_vigente`.~~
   **Hecho el 26-ago.** Era el piso: sin esto el punto 1 era una trampa.
5. **El historial tiene que mostrar la cadena**: a qué factura apuntaba antes, a
   cuál apunta ahora, cuándo y por qué. El append-only ya guarda todo; falta
   mostrarlo.

### Relación con los otros pendientes

- **§8** (anular es de una sola dirección) es el problema espejo: ahí falta poder
  deshacer, acá falta poder reemplazar. Los dos salen del mismo caso real.
- **§6**: `presentacion` es otra columna que se sigue escribiendo mal. Junto con
  `ent_pedido.factura_id`, son dos columnas declaradas obsoletas de las que
  todavía cuelga algo. Vale una pasada que las cierre a las dos.

---

## 11 · CERRADO (27-ago, b48) · La CUARTA PUNTA está en el esquema y no en el código

> ✅ **ARREGLADO EN b48.** `rpCalcSaldos()` ya suma `ent_devuelto_desde_ancla`.
> Se publica ANTES del viernes 28-ago, para que el saldo lea las cuatro puntas el
> mismo día en que el pan vuelve al congelador. Se conserva el diagnóstico entero
> porque la LECCIÓN no es el bug, es cómo estuvo siete días invisible.
>
> **Medido al arreglarlo**: `esquema_check` pasó de 26 a **27 objetos** y marcó
> "dependencias nuevas respecto de main: 1" en cuanto el código escribió el
> `from('ent_devuelto_desde_ancla')`. Antes de eso daba ✓ con la función a medias.
> La regla que salió de acá está en `CLAUDE.md`: **al pegar un esquema, si el
> contador de `esquema_check` no sube, el esquema está muerto.**
>
> **Verificado que una sola aritmética alimenta las tres pantallas**: `rpCalcSaldos`
> es la única implementación, y la llaman el selector de lotes de Despachos
> (`_despSaldo`), Inventario M7 (`_lotSaldo`) y el Reporte (`_rpSaldo`). Las tres
> heredan el arreglo — comprobado, no asumido.

**Qué pasa.** `ENTREGAS_DEVOLUCIONES.sql` (20-ago) crea `ent_devolucion`,
`ent_devolucion_linea` y la vista `ent_devuelto_desde_ancla`, y la describe en su
propio comentario como *"la cuarta punta del saldo: disponible = ancla +
produccion - salidas + devoluciones"*. Las tablas existen en Supabase (sondeadas
el 27-ago: responden `200`, no `PGRST205`).

**Pero `index.html` no las nombra ni una vez.** `rpCalcSaldos()` hace exactamente
tres cosas:

```
  ancla   ← ent_conteo_linea del conteo anclado
+ producción ← chatter de Odoo (entLotesActivos), en el navegador
− salidas ← ent_salido_del_congelador_desde_ancla
```

y ahí termina. Falta la cuarta lectura. Son ~3 líneas, simétricas a las de
salidas:

```js
const {data:dev}=await c.from('ent_devuelto_desde_ancla').select('lote,producto_id,uds');
(dev||[]).forEach(function(r){ const k=r.producto_id+'|'+r.lote; s[k]=(s[k]||0)+(+r.uds||0); });
```

**Por qué no es cosmético.** ⚠️ **La razón que se escribió acá el 27-ago era
FALSA y se corrigió el mismo día.** Decía, citando a `ENTREGAS_DEVOLUCIONES.sql`:
*"con el bloqueo duro de Despachos un saldo subestimado ahora IMPIDE despachar
producto que sí está"*. **El bloqueo duro no existe** — nunca se construyó, ver
§13. Despachar con el saldo en cero o negativo se puede hoy, desde la pantalla.

La razón verdadera es otra y alcanza igual: **sin la cuarta punta, el producto
devuelto no aparece NUNCA**. El saldo queda por debajo de lo real de forma
permanente —solo lo limpiaría un conteo físico que reancle, que puede tardar
meses— y todas las decisiones que se tomen mirando ese número van a estar mal.
Lo que era falso era la urgencia, no la necesidad.

**Orden elegido** (decisión de Andrea, 27-ago): la lectura se agrega, se prueba
**y se publica ANTES** de que se pegue el bloque del viernes. La decisión se tomó
sobre la premisa falsa del bloqueo duro, pero **sigue siendo la correcta**: que el
saldo lea las cuatro puntas el mismo día en que el producto llega evita que alguien
mire un número equivocado durante el fin de semana.

**Una asimetría que quedó escrita en el código.** Las otras lecturas de
`rpCalcSaldos` se tragan el error en silencio. Ésta no: si falla, se escribe en la
consola. Es por la DIRECCIÓN del daño — si falla la de salidas el saldo queda
ALTO (se ofrece de más, y eso se ve al despachar); si falla la de devoluciones
queda BAJO y esconde producto que sí está. Un saldo que va por debajo sin decir
por qué es indepurable — y desde el 27-ago no hay Excel contra el cual notarlo.

---

## 12 · ABIERTO · La pantalla de DEVOLUCIONES (Entrega 2)

**Estado**: **nunca se registró una devolución en el sistema.** `ent_devolucion`
está vacía — 0 filas, 0 anuladas, medido el 16-sep-2026.

⚠️ **Y eso es lo correcto, no un olvido.** Esta línea decía hasta hoy que el
primer caso real (Mentha, 28-ago) *"se resolvió a mano con SQL"*. **Es falso**, y
el error venía del §12 original. Lo que la bitácora del 27-ago decidió, textual,
fue que Daniel recibiera la devolución (6 Blanco `208` + 6 Semillas `209`) y
**contara después**, para que el ancla nueva ya la incluyera y
`PEGADO_28AGO_DEVOLUCION_MENTHA.sql` **«NO se corre»** — el SQL era el plan B por
si Lusof llegaba tarde. El pan volvió, el conteo físico lo absorbió, y el archivo
nunca se pegó. **El saldo no está corto.**

Esto es la especificación para el primer caso que se registre de verdad.

> ⚠️ **REESCRITO EL 16-sep-2026.** La versión anterior de este §12 se escribió el
> 27-ago, y entraba por el **despacho en el Historial**, con **motivo de texto
> libre** y un tope que **avisaba** por lote. Andrea decidió el flujo nuevo el
> 16-sep. Lo que cambió, lo que se conservó, y por qué, está al pie en «Qué decía
> antes». **Se conserva el aviso en vez del bloqueo**, y eso no es un descuido:
> ver el punto 5.

### Qué la hace distinta de todo lo demás del módulo

Todo lo que existe hoy en Entregas **resta** del congelador. Ésta es la única
pantalla que **suma**. Eso cambia dos cosas: no hay bloqueo por saldo (nunca vas
a "no tener suficiente" para recibir algo), y el error grave no es quedarse
corto sino **contar de más** — que es exactamente lo que casi pasa el 26-ago.

### Desde dónde se registra

**Es una pestaña de Entregas, y la registra Daniel.** No es solo-socias: quien
recibe el producto en la planta es quien tiene que poder anotarlo.

El flujo:

1. **Elegir cliente.**
2. **Sus últimas 3 entregas registradas**, la más nueva primero. Un "+" abre la
   lista completa.
   ⚠️ **El rótulo dice "entregas registradas", no "facturas", y es literal.** La
   lista sale de `v_ent_pedido_estado`, o sea de lo que pasó por Truefie. Una
   factura de Odoo anterior al módulo, o despachada por fuera, **no tiene alisto
   y por lo tanto no tiene lotes**: no se puede ofrecer, porque no hay contra qué
   devolver. Prometer "tus últimas 3 facturas" y mostrar otra cosa es peor que
   nombrarlo bien.
3. **Elegir entrega → los productos de esa entrega.**
4. **Por producto: LOTE y CANTIDAD devuelta.**
5. **Causa, lista cerrada**: `producto_equivocado` / `otro` + nota.
6. Se registra y **SUMA al inventario, en el momento**.

**La red de diseño se conserva entera.** El argumento de la versión vieja era que
entrar por el despacho hace que *"las líneas y los lotes vengan ya cargados del
alisto vigente"*, y que nadie escriba un lote a mano. Eso sigue siendo cierto por
el camino nuevo: entrega → pedido → alisto → lotes. **Lo que cambió es la
navegación, no la fuente del dato.** Semillas `209 / 1-27` está en el despacho 11
y en el 20; una pantalla de campos libres deja pasar "12" sin pestañear, y ésta
no tiene campos libres de lote.

### Las reglas

- ⚠️ **El lote NO es "lo disponible hoy"**: son los lotes que SALIERON en esa
  entrega. Solo pueden devolver lo que se les entregó. **Si un lote de esa
  entrega ya se agotó, aparece igual** — se devuelve contra lo que salió, no
  contra lo que queda.
- ⚠️ **El centinela `'NO DETERMINADO'` NO se ofrece** (decisión de Andrea,
  16-sep). No se puede devolver a un lote que nadie sabe cuál es. La base ya lo
  rechaza —`ent_devolucion_linea.lote` tiene el check de forma canónica
  `^\d{1,3} / \d{1,2}-\d{2}$`— pero eso hace fallar el insert entero: **la
  pantalla no tiene que ofrecerlo**, que es distinto de que la base lo atrape.
- 🔴 **AVISA, NO FRENA, y el porqué es toda la regla.** Si se devuelve más de lo
  que salió en esa entrega, la línea **entra y queda marcada**.

  Andrea pidió "frena" el 16-sep y lo revirtió el mismo día. La razón: **puede
  volver producto de una entrega anterior en el mismo camión**. Con "frena", ese
  producto no se puede registrar por ninguna pantalla — y entonces vuelve al
  congelador **sin que el sistema lo sepa**. Un saldo que no cuadra y lo dice es
  mejor que producto real invisible. Es el mismo criterio que
  `ent_factura_decision`: *"filtrar no puede ser una puerta de una sola
  dirección"*.

  La marca **no es una columna que escriba la app**: sale de una vista que compara
  lo devuelto contra lo que salió por (pedido, producto, lote). Un flag que
  escribe el cliente es un flag que puede mentir; una vista derivada, no.
- **NO junta dos entregas.** Son dos devoluciones separadas. Lo hace cumplir
  `pedido_id`, que es de la cabecera: una devolución tiene UN pedido.
- **Producto DAÑADO no se registra acá.** La devolución siempre suma al
  inventario; si no suma, no es devolución. No hay ruta de desecho y no se
  construye una (`ENTREGAS_DEVOLUCIONES.sql` §alcance).
- **"Deshacer" mientras no se cierre**, igual que en el alisto.
- **NO necesita visto de socia.**
- **SÍ va al Historial**: es un movimiento de producto y BRC tiene que poder
  rastrearlo. Cuelga del despacho, que es lo que `pedido_id` permite.
- **Fecha del movimiento, editable**, con el mismo control que la salida
  (`de-fecha`, `min`/`max`, 16 px). El día por defecto es hoy. **Y el texto tiene
  que decir que se registra cuando el producto LLEGA, no cuando avisan que va a
  volver** — es la lección del 26-ago, escrita en la pantalla.
- Antes de confirmar, en letras: **"esto SUMA al congelador"**, con el saldo del
  lote antes y después.

### ⚠️ La trampa del factor

Escrita a mano entraría **4× corta en Francés y Buns, y 2× en Pizza**. No hay que
escribir ninguna conversión: **`_entColgarDetalle` ya devuelve el `uom_factor`
congelado** de `ent_pedido_linea`, junto con las líneas y sus lotes — la unidad
tal como la pidió el cliente, guardada en el momento. Es exactamente lo que
`ent_devolucion_linea` quiere guardar (`uom_id`, `uom_nombre`, `cant_uom`,
`uom_factor`), y no toca Odoo.

Hay **tres** conversiones en `index.html` (`NIV_INFO.presDiv` vía `rpUdsDe`,
`INV_TERM.presDiv` vía `_lotUds`, y el factor de Odoo vía `uomFactores`). Para
este flujo no se usa ninguna: se usa el factor congelado de la entrega.

### Qué se muestra después

- **En el Historial, colgando del despacho**: *"devuelto el 28-ago · 6 u Blanco
  208 / 1-27 · 6 u Semillas 209 / 1-27"*. El despacho **no cambia de estado** —
  salió, y eso sigue siendo cierto. La devolución es un hecho que se le agrega.
  ⚠️ El Historial corta en 300 y no lo dice (§16, abierto). Esto lo hereda.
- **En Inventario (M7)**: cuando un lote tiene devoluciones, poder ver de dónde
  salió ese saldo. Sin esto, un lote que sube sin producción se lee como un error.
- **En Pendientes**: la alerta de la NC (ver abajo). La devolución en sí no es un
  problema y no se lista.

### La alerta de la NC

Al registrar, queda pendiente para las socias: *"hay que hacer la NC y
re-facturar por la cantidad real"*. Guarda **exactamente lo que va a ir a Odoo**:
cliente, factura original, productos, cantidades, lotes. La NC ya armada, no un
recordatorio suelto.

Va en la misma pareja de tablas que la alerta del traslado interno, con un
`tipo`. Las cuatro automatizaciones pendientes de Odoo —traslado interno, NC,
validación de entregas, orden de fabricación— entran por la misma puerta: cuando
se abra el carril de escritura, automatizar tiene que ser **conectar un botón a
datos que ya están**, no salir a reconstruirlos.

### Lo que YA está y no hay que construir

- Esquema de devoluciones, con RLS select+insert y sin update/delete
  (`ENTREGAS_DEVOLUCIONES.sql`), **aplicado**.
- La **cuarta punta** en el saldo (`ent_devuelto_desde_ancla` leída por
  `_rpCalcularPuntas`), desde b48. §11, cerrado.
- Anulación: `ent_anulacion` ya acepta `entidad = 'devolucion'`, y
  `ent_devolucion_vigente` ya la respeta. Corregir es anular e insertar.
- El check del lote canónico en la propia columna, que es la red contra el
  `"183 - 12/26"` del 18-ago.
- La unidad independiente de cómo salió (se vendió 1 caja, devuelven 1 unidad):
  la línea guarda su `uom_id` y su `uom_factor` congelados.
- **El camino de datos completo, todo Supabase**: `cliente_id` →
  `v_ent_pedido_estado` (trae `factura_id`, `alisto_id`) → `_entColgarDetalle` →
  líneas con sus lotes y el factor congelado.
- **Que una devolución REABRA un lote en cero**: trazado en el código, pendiente
  de verificar en vivo. La cadena es `ent_devuelto_desde_ancla` →
  `_rpCalcularPuntas` suma a `s[k]` → la clave aparece en `entLotesUnion` (que une
  los lotes de Odoo con las claves del mapa de saldos) → pasa `entLotesSelector` y
  `entLotesDisponibles` por `saldo > 0`. Vale también para un lote fuera de la
  ventana de producción de Odoo.

### Lo que hay que construir, en orden

1. **El esquema** (`CAMBIO_DEVOLUCIONES.sql`): `pedido_id` y `causa` en
   `ent_devolucion`, la vista del exceso, y la pareja de tablas de pendientes de
   Odoo.
2. La pestaña y su flujo de cinco pasos.
3. El renglón de devoluciones en el detalle del Historial.
4. Las dos alertas en Pendientes, al lado de «Por resolver».

### Qué decía antes, y por qué cambió

| | Antes (27-ago) | Ahora (16-sep) |
|---|---|---|
| Entrada | desde el despacho, en el Historial | pestaña propia: cliente → entrega |
| Causa | texto libre obligatorio | lista cerrada + nota |
| Tope | avisa por lote | **avisa** (se conserva), y queda marcado |
| Fecha | editable, con el texto del 26-ago | **igual, se conserva** |
| Ligada a factura | **no**, suelta a propósito | **sí**, `pedido_id` NOT NULL |

- **La entrada** cambió porque el flujo nuevo arranca por el cliente, no por "lo
  del 26-ago vuelve". La red que justificaba el camino viejo —lotes precargados,
  ningún campo libre— se conserva entera.
- **La causa** pasó a lista cerrada porque un campo libre no se puede sumar. El
  caso que motivaba el texto libre —*"el cliente no lo recibió, Lusof lo devolvió
  a la planta"*— cae en `otro` + nota y funciona.
- **El tope NO cambió**: Andrea pidió "frena" y lo revirtió el mismo día, con el
  argumento de arriba. Queda escrito para que no se vuelva a discutir.
- **La ligadura a factura** revierte la decisión de
  `ENTREGAS_DEVOLUCIONES.sql` —*"Suelta: NO se liga a factura... esperar a saber
  contra qué factura fue es esperar a nunca"*—. Sigue siendo un buen argumento
  para una devolución que llega por teléfono; **deja de aplicar cuando el flujo
  ARRANCA por la entrega**: nunca se está en el caso de no saberla.

### 🔴 La entrada suelta queda CERRADA, por decisión

Decidido por Andrea el **16-sep-2026**. `ent_devolucion.pedido_id` es **NOT
NULL**: no existe la devolución sin entrega. Queda escrito acá con el argumento
completo para que **no se vuelva a discutir**.

**Por qué ahora y no en cualquier momento.** Se midió con §0: la tabla tiene
**cero filas**. Los costos no son simétricos:

| | hoy (0 filas) | después, con filas |
|---|---|---|
| nullable → NOT NULL | gratis | scan completo, **y falla con una sola fila suelta** |
| NOT NULL → nullable | — | `alter column drop not null`, instantáneo |

Y hay un cierre que endurece la asimetría: **si alguna vez se escribiera una
devolución suelta, el NOT NULL dejaría de estar disponible para siempre.** No se
puede rellenar un `pedido_id` que no existe, y el módulo **no tiene grant de
DELETE en ninguna tabla**. Quedaría convivir con la columna floja.

**Por qué no se pierde nada.** El flujo arranca por cliente y entregas, así que
**incluso una devolución avisada por teléfono va a tener su pedido** — solo que
elegido después, cuando el producto llega. Que es además el momento correcto
según el criterio del 26-ago: se registra cuando LLEGA, no cuando avisan.

**Lo que se cierra de paso, y no es menor.** La rama `pedido_id is null or (...)`
del CHECK era un **escape alcanzable desde la app**, no teórico: una fila sin
pedido no pasaba por ninguna validación de causa, y la RLS de `ent_devolucion` es
`with check (true)` para cualquier autenticado. Y en `v_ent_devolucion_exceso`, el
filtro `where dv.pedido_id is not null` hacía que una devolución suelta fuera
**invisible** para el control del exceso.

⚠️ **Si algún día se quiere reabrir**, es una sola sentencia
(`alter table ent_devolucion alter column pedido_id drop not null`) **más** volver
a poner las dos cosas de arriba: la rama del CHECK y el filtro de la vista. Las
tres van juntas o el escape vuelve sin que nadie lo decida.

---

## 13 · 🔴 ABIERTO · EL "BLOQUEO DURO" NO EXISTE — nunca se construyó

**Descubierto el 27-ago-2026** diagnosticando el lote Pan Blanco `208 / 1-27` en
−4. La pregunta era "¿cómo pasó el bloqueo duro?". La respuesta es que **no hay
bloqueo que pasar.**

### La evidencia, en el código

`_despSaldo` —el saldo por lote— se usa en **UN SOLO lugar** de todo `index.html`:

```js
out.push({lote:L.canon, saldo:(_despSaldo ? ... : null)});   // _despLotesDe()
```

y de ahí sale a **dos** usos, los dos cosméticos:
1. **Ordenar**: los agotados al fondo de la lista.
2. **Rotular**: la opción dice `208 / 1-27 — agotado según sistema`.

La opción **NO va `disabled`**. Se puede elegir y confirmar.

Y el control que apaga el botón de confirmar, `_despPendientes()`, mira
exactamente **dos** cosas — ninguna es el saldo:

```js
if(!_despLotesEfectivos(f,i).length) sinLote++;   // ¿se eligió lote?
else mal++;                                       // ¿la suma de lotes da la cantidad?
```

### De dónde salió la confusión

El bloqueo duro **se diseñó y se aprobó**, y quedó anotado en `BITACORA.md` como
parte de la **Entrega 2**: *"Devoluciones (UI) + bloqueo duro. Esquema pegado,
pantalla aprobada."* La Entrega 2 **nunca se construyó**.

Y este archivo lo decía bien el 25-ago, en §4:

> *"`main` está en b27, que **no tiene bloqueo duro**, así que un sobregiro habría
> pasado en silencio."*

Pero a partir del 20-ago los documentos empezaron a hablar de él **en presente**,
como si existiera, y esa frase se propagó sin que nadie volviera al código:

| Dónde | Qué dice | ¿Cierto? |
|---|---|---|
| `ENTREGAS_DEVOLUCIONES.sql:8` (20-ago) | "con el bloqueo duro de Despachos eso deja de ser cosmetico" | ❌ |
| `CLAUDE.md:182` | "con el bloqueo duro de Despachos eso es no poder despachar" | ❌ |
| `ENTREGAS_PENDIENTES.md` §11 (27-ago) | "el bloqueo duro no deja despachar" | ❌ |
| `PEGADO_28AGO_DEVOLUCION_MENTHA.sql:52` (27-ago) | idem | ❌ |
| `index.html` · comentario de la cuarta punta (b48) | idem | ❌ |
| Mensaje del commit de b48 | idem | ❌ |
| `ENTREGAS_PENDIENTES.md` §4 (25-ago) | "b27 **no tiene** bloqueo duro" | ✅ |

**La lección**: una afirmación sobre el comportamiento del código repetida en seis
documentos sigue siendo cero verificaciones. `_despSaldo` se lee en un solo lugar
y bastaba un `grep` para saberlo. **Antes de citar una salvaguarda, ir a verla.**

### Lo que esto cambia

- **Un sobregiro desde la UI es posible HOY y es silencioso.** No requiere SQL.
  Cualquier lote puede estar mal y nadie se entera — es exactamente lo que pasó.
- **La decisión de "nunca esconder un lote" NO se toca.** Está bien pensada y
  documentada: *"el congelador físico manda sobre el sistema"*, y esconder los
  agotados obligó a Andrea a escribir un lote a mano el 18-ago. El bloqueo duro
  nunca fue "esconder": es avisar y pedir confirmación al sobregirar.
- **b48 sigue siendo correcto, pero por otra razón que la que se escribió.** La
  cuarta punta hacía falta igual —sin ella el pan devuelto no aparece nunca—;
  lo falso era el argumento de urgencia ("Daniel no va a poder despacharlo").
  Sí va a poder: el número va a estar mal, nada más.

### Qué construir (sin decidir todavía)

**Avisar y dejar pasar con confirmación**, en línea con toda la doctrina del
módulo (proponer y nunca bloquear; la emergencia se resuelve dentro de Truefie
con rastro, no en el papel). Al elegir un lote cuyo saldo no alcanza: se dice
cuánto falta, y si se confirma igual **se registra el sobregiro con su marca**,
como ya se hace con la factura que no se pudo verificar contra Odoo.
Un bloqueo que impide registrar lo que YA salió del congelador empuja al Excel —
y desde el 27-ago el Excel ya no existe (ver `CLAUDE.md`).

---

## 14 · ABIERTO · Un saldo negativo tiene que avisar solo, en Pendientes

**El caso**: el `208 / 1-27` estuvo en −4 y **nadie se enteró** hasta que Andrea
abrió Inventario a mirar otra cosa. Un error que solo se ve si alguien pasa por
casualidad no está siendo vigilado.

**No es "lote por agotarse".** Eso se descartó a propósito y sigue descartado: un
lote bajando es información normal de la operación. **Un negativo no es
información, es un error** — dice que el sistema cree que salió más producto del
que hubo, y eso solo puede ser una de tres cosas: un sobregiro real (§13), un
lote mal tecleado, o producción que no se está sumando.

**Dónde va**: en Pendientes, que desde b47 es *"lo que está MAL, ordenado por
GRAVEDAD"*. Un negativo es de los dos primeros escalones —los que tienen producto
o cliente del otro lado—, no de los tres de papeles.

**Cumple las 5 reglas de alerta del lobby** (`CLAUDE.md`), que es el requisito
para existir: hay algo que hacer ✓ · tiene fecha (la del movimiento que lo cruzó) ✓
· se apaga sola cuando el saldo vuelve a cero o más, sin "marcar como visto" ✓ ·
máximo 3 y "y N más" ✓ · ámbar solo si urge ✓.

**Qué tiene que decir**, y es lo que lo hace accionable en vez de decorativo:
producto, lote, **cuánto falta**, y **cuál fue el movimiento que lo cruzó** — que
es la única pregunta que se va a hacer quien lo lea.

⚠️ **Ojo con el falso positivo**: el saldo necesita las cuatro puntas, y la
producción sale de Odoo en el navegador. Si la alerta se calculara solo con lo
que hay en Supabase, todo lote fabricado después del ancla saldría en negativo el
primer día. Tiene que colgar de `rpCalcSaldos()`, que ya las suma las cuatro
(desde b48), y no de una vista nueva.

---

## 15 · 🔴 ABIERTO · 130 unidades salieron de un lote que nunca se movió

**El caso (27-ago-2026).** El lote **Pan Blanco `208 / 1-27`** daba **−4** en
Inventario. Daniel contó el congelador: **21 cajas = 126 unidades físicas**,
cajas cerradas, abiertas para verificar y todas de ese lote.

**La cuenta, con las tres fuentes de acuerdo:**

| | |
|---|---|
| Ancla del 14-ago (`CONTEO_14AGO.sql`) | **126 u** (21 cajas) |
| Salidas registradas desde entonces | **130 u** en 8 movimientos |
| Saldo en sistema | **−4** |
| **Físico contado hoy** | **126 u** |

Odoo, el Excel de Daniel y Truefie **coinciden en las 130**. No hay salidas
ocultas ni un registro de más: el ledger tiene 8 movimientos, ancla incluida, y
todos calzan contra factura. La diferencia entre lo físico y lo esperado es
**exactamente 130** — o sea, **todo lo que se registró como salido del 208**.

**Traducción: el pan del 208 nunca se movió.** Las 130 unidades salieron
físicamente de OTROS lotes, y esos lotes tienen de más lo que al 208 le falta.

### Lo que ya se descartó, con evidencia

**¿Produjo Keylor Pan Blanco después del ancla y anotó `208` en el chatter en vez
del juliano del día?** Eso habría metido 126 unidades físicas nuevas sin tocar
ningún registro de salida. **NO.** Verificado en Odoo el 27-ago sobre TODAS las
órdenes de Pan Blanco con `date_start` entre el 14 y el 27 de agosto, en todos
los estados:

| Orden | Inicio | Cant. | Chatter crudo | Lote |
|---|---|---|---|---|
| `WH/MO/01414` | 18-ago | 126 | `WH/MO/01404 WH/MO/01412 230/02 27` | `230 / 2-27` |
| `WH/MO/01415` | 19-ago | 126 | `WH/MO/01412 231/02 27` | `231 / 2-27` |
| `WH/MO/01420` | 24-ago | 168 | `WH/MO/01412 WH/MO/01419 236/02 27` | `236 / 2-27` |

Las tres con **un solo lote legible**, ninguna ambigua, ninguna sin lote, y
**ninguna menciona 208**. Tampoco lo menciona ninguna orden de los otros cinco
productos en esa ventana.

> ⚠️ **Y un aviso sobre cómo se verifica esto.** La primera consulta que se
> corrió esa mañana tomaba **la última coincidencia** de lote del chatter en
> silencio, así que **una orden ambigua se habría visto como una orden normal** —
> justo el caso que había que descartar. Hubo que rehacerla mostrando TODAS las
> coincidencias. Al buscar un lote mal escrito, la consulta no puede quedarse con
> uno: tiene que decir cuántos encontró.

### Las dos hipótesis que quedan, y cómo se separan

Las dos explican que hoy haya 126 unidades físicas del 208. **No se distinguen
mirando el 208** — hay que mirar los otros lotes:

- **A · El 208 nunca se movió** y las 130 salieron de otros lotes (lote mal
  elegido en el selector, 8 veces).
  → esos lotes van a tener **físicamente MENOS** de lo que el sistema dice.
- **B · El 208 se consumió entero** y una tanda posterior quedó **físicamente
  rotulada 208** aunque su chatter diga otra cosa. Ojo con esto: `WH/MO/01414`
  (lote 230) y `WH/MO/01415` (lote 231) produjeron **exactamente 126 u cada
  una** — el mismo número. Y `CLAUDE.md` ya documenta que el papel y el chatter
  se pueden separar (la corrección de 222 a 223 del 11-ago).
  → entonces el **230 o el 231 va a estar físicamente ausente** mañana.

**El conteo del 28-ago los separa** — pero solo si existe la foto de hoy contra
la cual restarlo.

### Por qué la foto no es opcional

El reconteo **no resuelve esto, lo tapa**: después del reancle el 208 va a decir
126 y todo va a cuadrar. `FOTO_ANTES_DEL_REANCLE.sql` congela el saldo esperado
de cada lote de los seis productos más todos sus movimientos, en una tabla nueva
(`ent_foto_lote_27ago`, puramente aditiva). **El conteo de mañana solo se puede
interpretar contra esos números**: sin ellos son 34 cifras nuevas sin nada contra
qué restarlas.

Y hay que sacarle **una foto a la pantalla de Inventario** además del SQL: la app
calcula las cuatro puntas y muestra las órdenes sin lote legible —pan real que no
suma a ningún lote— que el SQL no ve.

### Relación con los otros pendientes

- **§13**: esto es el sobregiro silencioso funcionando como se predijo. Sin
  bloqueo, ocho salidas seguidas contra un lote que no tenía producto y nadie se
  enteró. Si el bloqueo hubiera existido, se habría frenado en la primera.
- **§14**: y nadie lo vio hasta que Andrea abrió Inventario a mirar otra cosa.
- **§1** (el lote sin código de producto) es la causa candidata número uno de la
  hipótesis A: si el selector no distingue bien un lote de otro, elegir el
  equivocado ocho veces es exactamente el error que ese pendiente describe.
- **`CLAUDE.md`, corte del 27-ago**: este caso se pudo cruzar contra el Excel
  porque es anterior al corte. El próximo no va a tener ese segundo testigo.

---

## 16 · 🟠 ABIERTO · El Historial corta en 300 y no lo dice

Detectado el 10-sep-2026 leyendo los filtros de la pantalla para especificar la
exportación. **No es el exportador** — el exportador consulta aparte y trae todo
lo que el filtro pida (decisión de Andrea, 10-sep). Esto es el arreglo de la
pantalla, y va por su cuenta.

**Qué pasa.** `bsLeer()` ([index.html:11985](index.html)) trae los pedidos con
`.order('fecha_ab_re_04', {ascending:false}).limit(300)`. Es un **techo duro y
anterior a cualquier filtro**: lo que no entró en esos 300 no está en memoria, y
entonces **ningún filtro lo puede encontrar**. Escribir el nombre de un cliente
viejo devuelve "Ninguna entrega con eso", que es indistinguible de "ese cliente
nunca compró".

**La pantalla ya sabe hacer esto bien, dos renglones más abajo.** `BS_TOPE = 60`
es el tope de DIBUJO y sí se anuncia:

```
y 12 más — afiná la búsqueda.
```

O sea que la regla —*"lo que no se dibuja se DICE; un corte callado se lee como
'esto es todo', que es la peor respuesta posible en una búsqueda"*— ya está
escrita en el propio archivo, en el comentario de `bsFiltrar()`. Lo que falta es
aplicarla al otro tope, el que de verdad esconde datos.

**Hoy no muerde y por eso es 🟠.** El día que el histórico pase de 300 pedidos,
muerde en silencio. La primera medición al retomarlo es cuántos hay:

```sql
select count(*) as pedidos_con_alisto from v_ent_pedido_estado;
```

### Qué hay que construir

Que `bsLeer()` pida **301** y, si vuelven 301, guarde la señal de que hay más y
la pantalla lo diga con la misma voz que el otro tope — algo como *"solo los 300
más recientes; hay más historial"*. Pedir uno de más es el truco barato para
saber si se cortó sin traer un `count` aparte.

⚠️ **No confundir los dos topes al arreglarlo.** `BS_TOPE` recorta lo que se
DIBUJA de un resultado ya filtrado; el `.limit(300)` recorta lo que se LEE antes
de filtrar. Los dos mensajes tienen que poder aparecer a la vez y decir cosas
distintas — si se los unifica en una sola frase, se pierde justo la diferencia
que importa.

---

## 17 · 🔴 ABIERTO · La columna "Unidades" del Conteo está en unidades individuales

Reportado por Andrea el 10-sep-2026, con el borrador del conteo abierto
(27 líneas, los 6 productos tecleados). Ese borrador es el que quedó como
**ancla vigente**: `ent_ancla` id 6, corte **10-sep-2026 17:07:50 CR =
10-sep-2026 23:07:50 UTC** (medido con `pg_lector` el 13-sep-2026, M10 de
`MEDICION_EXCEPCIONES.sql`).

⚠️ **LA HORA VA SIEMPRE CON SU ZONA, Y EN LOS DOS FORMATOS.** Este párrafo
decía `23:07` a secas. Ese número calza al minuto con el corte en **UTC**, no
con la hora de acá: a las 23:07 CR del 10-sep ya era el 11-sep en UTC. Se
arrastró durante tres días como si fuera hora local, y de ahí salió el
"11-sep 05:07 UTC" con el que se venían comparando las órdenes —seis horas
corrido—. `America/Costa_Rica` es UTC−6 sin horario de verano.

Es el mismo error del 19-ago-2026 que ya está en el `CLAUDE.md`: un timestamp
de Odoo o de Postgres anotado sin decir el huso. No cambió ninguna conclusión
—la orden más nueva de los seis terminados, `WH/MO/01453`, arranca el
9-sep 23:54 UTC, casi un día antes incluso del corte corregido— pero habría
cambiado la respuesta para cualquier tanda producida entre las 17:07 y las
23:07 CR de ese día.

**NO ES UN ERROR DE DATOS Y NO BLOQUEA CONFIRMAR EL ANCLA.** Se diagnosticó ese
mismo día antes de que Andrea confirmara: `ent_conteo_linea` guarda `cajas`,
`sueltas` **y** `uds`, y `uds` está en unidades individuales, que es exactamente
lo que el motor espera. Es el número correcto en la unidad equivocada.

**Qué pasa.** `_clUds(pid, cajas, sueltas)` devuelve
`cajas × cajaU + sueltas × presDiv`, o sea **unidades individuales**, y la
columna las muestra crudas bajo el rótulo "Unidades". Francés y Buns salen ×4 y
Pizza ×2 respecto de la unidad de venta. El pie (`_clFmtTot`) arrastra lo mismo:
"13 cj + 2 u" más un "320 u".

**Blanco, Semillas y Galletas se ven bien por casualidad**: tienen `presDiv: 1`,
así que unidad individual y unidad de venta coinciden y el error es invisible en
ellos. Es el mismo punto ciego de la auditoría del 28-ago — no sirven para
descartar.

### Lo que se verificó, y por qué el ancla es segura

Las cinco puntas del saldo y el cuadre contra Odoo están **todas** en unidades
individuales, medido en el código el 10-sep:

| punta | de dónde | unidad |
|---|---|---|
| ancla | `_clUds` | individuales |
| producción | `qty_produced / factor` (`index.html` 8391) | individuales |
| salidas | `cant_uom / uom_factor` (11163) | individuales |
| devoluciones | `ent_devuelto_desde_ancla.uds` | individuales |
| merma | `scrap_qty / factor` (8426) | individuales |
| cuadre Odoo | `qty_available / factor` (`_clLeerStock`) | individuales |

**Lo que lo cierra**: `_lotUds(uds, pid)` —con la que Inventario y los dos
selectores muestran un saldo— **divide entre `presDiv`**. El motor guarda
unidades individuales y convierte solo al mostrar. La pantalla de Conteo es la
única que no hace esa división.

Las 12 filas que reportó Andrea reconcilian exactas por los dos lados
(`13×24 + 2×4 = 320` y `320/4 = 80`): es el mismo dato en dos unidades, no dos
datos distintos.

### Al arreglarlo

Dividir entre `presDiv` y rotular la columna "Paquetes" / "Unidades" según el
producto, como ya hace `_lotUds`. **No tocar `_clUds` ni lo que se guarda** — eso
está bien y el motor entero depende de ello.

El factor vive dos veces y eso tiene su propio pendiente: **§20**. Al arreglar
esta pantalla, que lea de una sola.

---

## 18 · 🟠 ABIERTO · La columna de sueltas queda fuera de pantalla en iPhone vertical

Reportado por Andrea el 10-sep-2026.

**Qué pasa.** En vertical, en iPhone, la tabla de conteo se corta y la columna de
unidades sueltas no se ve. Solo aparece girando el teléfono.

**Por qué importa más de lo que parece.** No es incomodidad: es que **Daniel
podría contar todo como cajas sin enterarse de que existe la otra columna**. Un
lote con 3 sueltas se guardaría con 0 sueltas, y el ancla nacería corta sin que
nada avise. Es el mismo tipo de daño que el lote que no se ofrece para contar
(§ del selector, b56): lo que la pantalla no muestra, el conteo lo pierde.

Va junto con **§17**: las dos son de la misma tabla y conviene tocarla una sola
vez.

---

## 19 · 🟠 ABIERTO · El encabezado dice "solo lectura" durante el conteo

Reportado por Andrea el 10-sep-2026.

**Qué pasa.** El banner de producción dice "solo lectura" mientras se cuenta, con
sesión iniciada y guardando bien.

**Por qué el rótulo es engañoso, y por qué igual hay algo verdadero abajo.** La
regla madre "Producción es SOLO LECTURA" es sobre **Odoo**, no sobre Supabase: el
conteo escribe en Supabase, que nunca fue de solo lectura. Pero el banner se lee
como "esta pantalla no guarda", que es falso y en el peor momento — con el
congelador abierto y guantes puestos.

Al arreglarlo, **no basta con quitarlo**: lo que el banner dice de verdad
—"Truefie no le escribe a Odoo"— es información que cambia cómo se lee la
pantalla, y por la regla del estándar visual eso se queda. Lo que hay que
arreglar es que no se lea como si la pantalla no guardara.

---

## 20 · 🟠 ABIERTO · El factor caja→unidad vive DOS VECES

Detectado el 10-sep-2026 diagnosticando §17.

**Qué pasa.** La misma conversión está escrita en dos tablas distintas del
`index.html`:

| | dónde | cómo se llama |
|---|---|---|
| `NIV_INFO` | 6900-6905 | `cajaU` · `presDiv` |
| `INV_TERM` | 17327 | `factor` · `presDiv` |

Con los mismos números: Francés 24/4, Buns 24/4, Pizza 12/2, Blanco y Semillas
6/1, Galletas 12/1. **Hoy coinciden.**

**Por qué es un pendiente y no una curiosidad.** Es el modo de falla favorito de
este proyecto, y ya cobró cuatro veces: la regla del renglón en blanco que
Pendientes arregló y el Historial no recibió; la unión de lotes que vivía dentro
del render de Inventario y el selector de Daniel nunca vio; `_despYmd` que era
copia carácter por carácter de `_ymd`; las dos redacciones de "vigente" que
`ent_alisto_vigente` vino a unificar. **La segunda copia nunca recibe el arreglo
de la primera** — y acá lo que se desincronizaría es un factor de 4, o sea que el
síntoma sería un número plausible y equivocado, no una pantalla rota.

Y hay una diferencia peligrosa entre las dos que conviene ver antes de tocar
nada: **`NIV_INFO` la usan el planificador y el nivelador** (`cajaU` aparece en
7813, 7828, 7839, 7885, 7904, 7957), no solo Entregas. Unificar hacia el lado
equivocado movería números de producción. La consumidora natural es `INV_TERM`,
que es la tabla de los seis terminados y la que ya usa `_lotUds`.

**No urge**: mientras coincidan, nada falla. Se arregla cuando se toque §17.

---

## 21 · 🟠 ABIERTO · Producción registrada DESPUÉS del ancla con fecha ANTERIOR

Caso real del conteo del 10-sep-2026. Es el espejo de `ENT_MO_EXCLUIDAS`.

**El caso.** El lote **Semillas `252 / 6-27`** se agregó al conteo con "Agregar un
lote que no está" porque Keylor todavía no había registrado esa producción en
Odoo. Daniel lo contó físicamente: **28 cj + 1 u = 169 uds**, y así entró al
ancla. Keylor la va a registrar **mañana, con fecha de ayer** — o sea anterior al
corte.

### La respuesta, leída del código

**No se suma dos veces.** En `_rpCalcularPuntas()` la producción entra solo si es
**estrictamente posterior** al corte:

```js
if(rec.prodUtc && _odooMs(rec.prodUtc) > corteMs){ ... s[k] += rec.uds ... }
```

Una MO con fecha anterior al corte se ignora, que es exactamente lo correcto: su
pan ya está dentro de la foto del ancla. El comportamiento por defecto es el
bueno y **no hay que hacer nada**.

### ⚠️ Pero depende de un campo que nadie mira, y de cuál fecha ponga Keylor

`rec.prodUtc` es **`date_start`**, no `date_finished` (`index.html` 8391). Así que
la pregunta real no es "¿la registra con fecha de ayer?" sino **"¿qué queda en
`date_start`?"**:

- **`date_start` de ayer** → anterior al corte → se ignora. Correcto.
- **`date_start` de mañana** (si al registrarla la orden se abre y cierra en el
  momento) → **posterior al corte → se suma**, y el lote 252 queda inflado en 169
  uds, **en silencio**. Los números cierran solos y nada avisa.

Es el mismo mecanismo del 14-ago con Galletas `226 / 2-27` (§ de la bitácora y
`ENT_MO_EXCLUIDAS`), solo que al revés: allá la orden entró minutos DESPUÉS del
corte con el pan ya contado; acá puede entrar días después con la misma
consecuencia.

**Qué hacer cuando Keylor registre**: mirar `date_start` de esa MO en UTC contra
el corte del ancla del 10-sep — y recordar que `14-ago 16:00 CR = 14-ago 22:00
UTC`, así que comparar crudo invierte el resultado. Si cae después del corte, la
orden va a `ENT_MO_EXCLUIDAS` con su huella completa.

### Un segundo cabo, más chico — ✅ CERRADO el 13-sep-2026

**Lo que decía este apartado** (y se deja escrito, porque la trampa sigue viva
aunque esta instancia esté cerrada): el lote se tecleó a mano como `252 / 6-27`;
cuando apareciera la MO, `_entParseLote` iba a derivar su forma canónica del
chatter, y **si el chatter decía otra cosa iban a ser dos claves distintas**, con
el ancla colgando de una que la producción nunca alimenta.

**Pasó exactamente eso.** La MO apareció el 11-sep-2026 —`WH/MO/01453`, Pan de
Semillas, `date_start` 9-sep 17:54 CR— y su chatter decía `252/03 27`, **no**
`6-27`. Eran dos claves distintas: `452|252 / 3-27` contra `452|252 / 6-27`.

**Pero no era un error de transcripción.** Era el cambio de vida útil de 6 a 9
meses (decisión de True Food del 2-sep-2026), que ya estaba en el papel y en el
ancla y todavía no había bajado al chatter de Odoo. Medido el 13-sep sobre las
182 órdenes *done* de 2026 con lote legible: **174 a +6 meses y 8 a +9**, y las 8
de `WH/MO/01437` en adelante.

**Cómo se cerró.** Andrea corrigió los ocho chatters en Odoo —**editando** el
mensaje, no agregando otro, que habría dejado las órdenes en `ambiguo`— y se subió
`ENT_VIDA_MESES` de 6 a 9 (`6766f32`). Verificado el 13-sep corriendo
`_entParseLote` **real** bajo `jsc` sobre el chatter ya corregido: deriva
`452|252 / 6-27`, que **coincide exacto con lo tecleado en el ancla**. Los otros
dos lotes del mismo caso también calzan: `503|251 / 6-27` (Buns) y
`519|251 / 6-27` (Galletas).

**Lo que deja como lección**, que es por qué no se borra: el lote vive en texto
libre en el chatter, así que una regla de negocio nueva puede tardar días en
llegar ahí. Entre el 2 y el 11-sep el papel decía una cosa y Odoo otra, y el
único síntoma visible habría sido un lote que desaparece del selector.


---

## 22 · 🔴 ABIERTO · M12 **no** es el "antes" de 7e, y el plan dice que sí

Encontrado el 13-sep-2026, al preparar la aplicación de
`ENTREGAS_EXCEPCIONES_LINEA.sql`. **Nada aplicado todavía.**

El encabezado del plan (§0, línea 84 de ese archivo) dice: *"M12 · el balde del
alisto hoy, en unidad de venta. **Es el ANTES de 7e**."* Es falso: son dos
consultas distintas.

```sql
M12:  ... from ent_salido_del_congelador_desde_ancla s
       where s.lote = 'NO DETERMINADO'      group by ...  order by pres.nombre

7e :  ... from ent_salido_del_congelador_desde_ancla s
       (SIN where)                          group by ...  order by pres.nombre, s.lote
```

M12 mira **sólo el balde del centinela** — medido el 13-sep: **0 filas**. 7e mira
**todos los lotes**. Usar el 0 de M12 como patrón de comparación y después correr
7e haría aparecer la foto entera de saldos como si fuera un cambio, y se leería
como que la migración rompió algo.

**Qué hay que hacer:** correr **la consulta de 7e, tal cual**, inmediatamente
antes de pegar, y otra vez después. El propio 7e lo dice y explica por qué:

> *"⚠️ DIFERENCIAL, no contra numeros medidos otro dia. Comparar la misma consulta
> ANTES y DESPUES de pegar, en la misma sesion. Un 'esperado' copiado de una
> medicion de ayer ya fallo una vez (bitacora 8-sep): con doce pedidos de por
> medio parecio que la correccion habia roto los seis saldos."*

O sea: el error que 7e documenta **ya estaba cometido dentro del propio plan que
lo advierte**, una sección más arriba.

### Una trampa hermana, en el mismo archivo

**7e y 7f NO están comentadas.** Todo el §7 vive en comentarios salvo esas dos,
que son `select` ejecutables al final del archivo. Si se pega el archivo entero,
se aplican §1–§6 y acto seguido corren 7e y 7f — o sea que se obtiene el
**después** de 7e sin tener nunca el **antes**. Segunda razón para medir primero
y por separado.

### Y el archivo no trae transacción

`ENTREGAS_EXCEPCIONES_LINEA.sql` no tiene `begin/commit`: se aplica sentencia por
sentencia y un error a mitad deja la mitad puesta, sin aviso. Para la próxima
sesión quedó preparado `PARA_PEGAR_EXCEPCIONES_1a6.sql`, que es el cuerpo §1–§6
**copia literal** envuelto en `begin; … commit;` (Postgres soporta DDL
transaccional, así que pasa a ser todo o nada), y `PARA_PEGAR_EXCEPCIONES_7abc.sql`
con 7a/7b/7c descomentadas para pegar de a una. **Ninguno de los dos se corrió.**

### El control de 7f va por IDS, no por cantidad

Decisión de Andrea, 13-sep. `select tipo, count(*)` no alcanza: si la vista nueva
cambia de semántica y devuelve **seis filas distintas**, el número pasa igual. El
control es que `v_ent_excepcion_pendiente` con `tipo = 'lote_no_determinado'`
devuelva exactamente `alisto_lote_id` **{164, 184, 192, 193, 194, 195}**, pedidos
**48, 55 y 56**. Seis distintas = parar.

Medido el 13-sep con `pg_lector` sobre la vista vieja: las seis son del
**8-sep-2026**, entre las **09:16:57 y las 14:28:11 CR** (15:16:57 a 20:28:11
UTC), **todas anteriores al corte del ancla**. Ninguna mueve el saldo de hoy, y
corregirlas no movería ningún número: `ent_salido_del_congelador_desde_ancla`
filtra por `preparado_en > corte` y quedan del otro lado. Queda por decidir si se
cierran como absorbidas por el reancle o se dejan abiertas como historia.


---

## 23 · 🟠 ABIERTO · El prefijo `rp-` de CSS lo usan dos módulos

**Decisión de Andrea, 15-sep-2026: NO va en b59.** Hoy están scopeados y no hacen
daño; tocar una pantalla que anda bien, en la publicación que Daniel usa mañana,
no vale la pena. Queda anotado para después.

**Qué pasa.** `rp-` quiere decir dos cosas distintas en la misma hoja de estilos:

- **Finanzas** — "resultado producto": `rp-des`, `rp-desk`, `rp-dr`, `rp-mov`,
  en el costo por producto (`#vResultados`, nacidas el 10-ago en `fabe4d9`).
- **Entregas** — "reporte de despacho": 31 clases, de `rp-sec` a `rp-lotebtn`,
  nacidas el 13-ago en `85a0cba`. Tres días después.

**Lo que ya costó.** `rp-nota` era el único nombre que las dos listas compartían,
y la regla de Finanzas `.rp-mov,.rp-des,.rp-nota{display:none}` estaba **sin
scope**, así que escondía las notas de Entregas. Consecuencia medida el 15-sep:
**todos** los avisos de validación de "Entregas sin factura" llevaban **33 días
invisibles**, en todo ancho de pantalla — "Falta elegir el lote.", "Los lotes
suman 8 y la cantidad es 10 — tiene que dar igual.", "Sin motivo no se puede
guardar.", "Elegí una de las dos para seguir." y "no es hoy (…)". El botón se
quedaba quieto y no decía por qué.

Arreglado ese mismo día scopeando la regla a `#vResultados` (ver el comentario
largo en el CSS, línea ~398). **Hoy no queda ninguna regla `.rp-*` de Finanzas
sin scope**, verificado.

**Por qué sigue abierto.** El arreglo tapó el choque, no la causa: el espacio de
nombres sigue repartido. El día que alguien escriba `rp-mov` en Entregas —y
"movimiento" es una palabra probable ahí— vuelve a pasar, y la próxima vez puede
no encontrarla nadie: ésta apareció porque hubo que escribir un texto nuevo y no
se veía, no porque alguien revisara el CSS.

**Lo que hay que hacer.** Renombrar las cuatro de Finanzas a `cp-` (costo por
producto): `cp-des`, `cp-desk`, `cp-dr`, `cp-mov`. Son 4 clases, ~8 reglas y ~4
usos, todos dentro de `#vResultados` (verificado: son sus únicas apariciones).

**Lo que NO hay que renombrar.** Los otros diez prefijos que comparten dos o más
módulos —`btn`, `card`, `face`, `faces`, `s`, `mes`, `live`, `tbl`, `valid`,
`cl`— son el sistema de diseño: mismo nombre, misma cosa en todos lados.
Compartir no es chocar. El barrido del 15-sep midió los 11 y `rp` es el único
ambiguo.

**La regla, de acá en adelante.** Una regla escrita para un módulo va scopeada a
su `#vXxx`. Un selector de clase suelto en la hoja global aplica a toda la app,
no al módulo donde uno lo escribió.

---

## 24 · 🟠 ABIERTO · Las "sin lote" no se cierran nunca — les falta que un ancla las absorba

Anotado el 16-sep-2026 al construir la tarjeta «Por resolver», y **no
construido**. Decisión de Andrea ese mismo día.

**Qué pasa.** `v_ent_excepcion_pendiente`, rama (a), lista las salidas cuyo lote
quedó en `'NO DETERMINADO'`. Su criterio es *"el lote dice NO DETERMINADO"*, y eso
**es cierto para siempre**: nada lo cambia nunca, así que ninguna fila sale de esa
lista jamás. Hoy son 8.

**Por qué eso no es un pendiente.** Una salida sin lote **no es algo por
resolver, es historia**. Nadie va a saber nunca de qué lote salió: el producto ya
se entregó y el sticker se cayó hace días. Y el sistema **ya hace lo correcto** —
descuenta del producto sin imputar a ningún lote. La diferencia real aparece
cuando se vuelve a contar, y ahí se ajusta el ancla. No hay nada que hacer antes
de eso.

**Qué se hizo el 16-sep.** La tarjeta «Por resolver» filtra en la pantalla y
muestra **solo** la rama `no_se_entrega`. Quedan 4 líneas, todas accionables.
**La vista NO se tocó**: las dos ramas siguen existiendo, y
`v_ent_excepcion_pendiente_pedido` sigue exponiendo `n_sin_lote` para quien lo
necesite. Filtrar en la vista lo dejaría en 0 para siempre.

**Lo que falta, y es lo difícil.** Que una "sin lote" **se cierre sola** cuando un
ancla nueva la absorbe — el mismo argumento que cerró las seis del 8-sep. Requiere
definir qué significa exactamente *"absorbida por un ancla"*:

- ¿Basta con que el ancla sea posterior a `preparado_en`? Un ancla nueva ya
  reconcilia el saldo del producto, así que la salida sin lote quedó contabilizada
  en el conteo — pero eso hay que **medirlo**, no suponerlo.
- ¿Qué pasa con una salida sin lote registrada **después** del corte del ancla
  vigente? Ésa todavía no fue absorbida por nada.
- ¿Se refleja en la vista (un `where` contra `ent_ancla.corte`) o en una columna
  que alguien escriba? Lo primero se apaga solo; lo segundo necesita quién.

**Por qué no urge.** Nadie está esperando, no hay plata en juego y el saldo ya es
correcto. Lo único que costaba era ensuciar una lista de trabajo, y eso se
resolvió sacándolas de la pantalla.
