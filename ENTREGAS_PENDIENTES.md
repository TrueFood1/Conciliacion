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

**Estado**: el primer caso real (Mentha, 28-ago) se resuelve **a mano con SQL**
(`PEGADO_28AGO_DEVOLUCION_MENTHA.sql`, gitignored). Esto es la especificación
para que el segundo no requiera SQL.

### Qué la hace distinta de todo lo demás del módulo

Todo lo que existe hoy en Entregas **resta** del congelador. Esta es la única
pantalla que **suma**. Eso cambia dos cosas: no hay bloqueo por saldo (nunca vas
a "no tener suficiente" para recibir algo), y el error grave no es quedarse
corto sino **contar de más** — que es exactamente lo que casi pasa acá.

### Desde dónde se registra

**Desde el despacho, en el Historial.** El caso real llega como *"lo del 26-ago
vuelve"*, no como *"entraron 6 unidades de Blanco"*. Abrís el despacho y el pie
gana un control **"Registrar devolución"**.

Entrar por el despacho resuelve solo el problema difícil: **las líneas y los
lotes vienen ya cargados del alisto vigente**, con sus cantidades y sus unidades.
Nadie escribe un lote a mano, y por lo tanto nadie escribe el lote de otro
despacho. Es la red de diseño contra el error del 26-ago.

⚠️ **La red importa más que la comodidad.** Semillas `209 / 1-27` está en el
despacho 11 (6 u, se quedó el cliente) y en el 20 (6 u, vuelve). Una pantalla que
pidiera "producto + lote + cantidad" en campos libres deja pasar "12" sin
pestañear. Una que parte del despacho, no.

Hace falta **también** una entrada suelta —`ent_devolucion` es suelta a
propósito: *"una devolucion llega por telefono o en el camion de vuelta"*— pero
va **segunda**, y con el lote elegido de una lista, nunca escrito.

### El gesto

1. Se abre con **todas las líneas del despacho marcadas y en su cantidad total**:
   el caso normal es que vuelva todo (es lo que pasó acá). Devolver parcial es
   desmarcar o bajar el número, no llenar un formulario en blanco.
2. **Cantidad por lote, no por línea.** La unidad es la del alisto, y la línea
   avisa si se pide más de lo que salió en ese lote de ese despacho — *avisa*,
   no bloquea: puede volver producto de una entrega anterior en el mismo camión.
3. **Fecha del movimiento, editable, con el mismo control que la salida**
   (`de-fecha`, `min`/`max`, 16 px). El día por defecto es hoy. **Y el texto tiene
   que decir que se registra cuando el producto LLEGA, no cuando avisan que va a
   volver** — es la lección del 26-ago escrita en la pantalla.
4. **Motivo obligatorio**, texto libre. "El cliente no lo recibió, Lusof lo
   devolvió a la planta" no entra en ninguna lista cerrada.
5. **La pregunta que decide todo, explícita: ¿vuelve al congelador?** Sí → se
   registra. No → **no se registra nada** y la pantalla lo dice: lo que se bota no
   se registra (decisión de Andrea, `ENTREGAS_DEVOLUCIONES.sql` §alcance). No hay
   ruta de desecho y no se construye una.
6. Antes de confirmar, en letras: **"esto SUMA al congelador"**, con el saldo del
   lote antes y después. Es la simetría de "no registra una entrega nueva" del
   diálogo de Entregar, y es lo que hace el gesto seguro.

### Qué se muestra después

- **En el Historial, colgando del despacho**: *"devuelto el 28-ago · 6 u Blanco
  208 / 1-27 · 6 u Semillas 209 / 1-27"*. El despacho **no cambia de estado** —
  salió, y eso sigue siendo cierto. La devolución es un hecho que se le agrega.
- **En Inventario (M7)**: cuando un lote tiene devoluciones, poder ver de dónde
  salió ese saldo. Sin esto, un lote que sube sin producción se lee como un error.
- **En Pendientes**: nada. Una devolución registrada no es un problema.

### Lo que YA está y no hay que construir

- Esquema completo, con RLS select+insert y sin update/delete
  (`ENTREGAS_DEVOLUCIONES.sql`).
- Anulación: `ent_anulacion` ya acepta `entidad = 'devolucion'`, y
  `ent_devolucion_vigente` ya la respeta. Corregir es anular e insertar.
- El check del lote canónico en la propia columna (`^\d{1,3} / \d{1,2}-\d{2}$`),
  que es la red contra el `"183 - 12/26"` del 18-ago.
- La unidad independiente de cómo salió (se vendió 1 caja, devuelven 1 unidad):
  la línea guarda su `uom_id` y su `uom_factor` congelados.

### Lo que hay que construir, en orden

1. **§11 primero** — la cuarta punta en `rpCalcSaldos()`. Sin eso la pantalla
   registra algo que no se ve, que es peor que no tenerla.
2. El diálogo desde el Historial, reusando `_despDialogoHTML`.
3. El renglón de devoluciones en el detalle del Historial.
4. La entrada suelta (sin despacho), después y con lote de lista.

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
