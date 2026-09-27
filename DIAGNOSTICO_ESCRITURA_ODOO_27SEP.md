> **Versión PÚBLICA** (27-sep-2026): sin nombres de clientes ni proveedores y sin
> montos. La versión completa, con nombres y montos, vive en el repo PRIVADO
> `respaldo-truefie`, en `trabajo/odoo/diagnostico_odoo_27sep.md`.

# Diagnóstico · validar entregas en Odoo desde Truefie — relevamiento del 27-sep-2026

**Solo lectura. No se escribió nada en Odoo ni en Supabase, no se tocó el proxy ni
ningún permiso.** Odoo se leyó con `odoo_read.call(...)` (allowlist `LECTURA_OK`,
uid 28 `Lobby Solo Lectura`) contra `truefood.odoo.com`, versión **17.0+e**
(medida con `common.version()`). Supabase se leyó con `herramientas/pg_lector.py`
(transacción `READ ONLY`). Permisos con `python3 diagnostico_permisos.py` **sin
flags** (pasos 1 y 2, no modifican nada).

Cada afirmación lleva una marca:

- **[MEDIDO]** — sale de una lectura hecha hoy.
- **[INFERIDO]** — deducido de lo medido o del funcionamiento conocido de Odoo 17; no lo vi pasar.
- **[NO MEDIBLE]** — el lector no llega (permiso o allowlist). Se dice por qué.

Cantidades en la unidad de venta: Blanco, Semillas y Galletas en **unidades**;
Francés y Buns en **paquetes de 4**; Pizza en **paquetes de 2**. Horas: `CR = UTC−6`.

---

## 0 · Lo esencial en seis líneas

1. **La cola está casi vacía.** Hoy hay **1** salida sin validar (`WH/OUT/02378`), y es de un pedido que Truefie tampoco da por entregado. El 25-ago había 9. [MEDIDO]
2. **En 68 de 68 pedidos con salida validada, lo que Odoo descontó coincide exacto con lo que Truefie registra como salido.** [MEDIDO]
3. **La cadena pedido → factura → orden de venta → salida es 1 a 1 en 67 de 70 pedidos con factura.** Las 3 excepciones son una re-facturación que generó una segunda salida, una factura anulada con la salida cancelada y el pendiente de hoy. [MEDIDO]
4. **La que valida es Andrea: 71 de 71 desde el 15-ago**, en tandas. En 15 sesiones, 64 de las 71 salidas comparten el segundo exacto de validación con otra. [MEDIDO + INFERIDO: el "quién" sale del chatter, ver §3]
5. **Validar genera un asiento con la fecha del día en que se valida, no la del día en que salió el producto.** 180 de 180 asientos quedaron con la fecha CR de la validación, y solo 73 caen el mismo día de la entrega. 5 entregas de agosto quedaron asentadas en septiembre. [MEDIDO]
6. **Recomendación: opción C ahora** (seguir validando a mano y que Truefie muestre el cuadre contra Odoo, leyendo el estado real). **Opción B** (lote nocturno) queda para después, primero en modo simulación. **Opción A** (botón con carril de escritura) va al final. Detalle en §8.

---

# CASO 1 · Validar la entrega — qué sigue igual y qué cambió desde el 25-ago

## 1 · Qué queda pendiente en Odoo después de facturar

| Afirmación del 25-ago | Hoy | Marca |
|---|---|---|
| "Las facturas están `posted` desde que se factura" | **Se mantiene.** Las 78 `out_invoice` con fecha desde el 15-ago están `posted` y ninguna está en borrador. Las 6 notas de crédito (`out_refund`) también están `posted`. | MEDIDO |
| Cola: 9 `assigned`, 2 207 `done`, 104 `cancel` | **Cambió.** Hoy: **1 `assigned`, 2 266 `done`, 106 `cancel`**, y 0 en `draft`/`waiting`/`confirmed`. | MEDIDO |
| `WH/OUT/02319` (3484) sin validar | **Cambió: está `cancel`.** La 3484 se anuló con la NC `…0251` el 26-ago. | MEDIDO |
| `WH/OUT/02321` (3486) sin validar | **Cambió: `done`**, validada el 26-ago 20:17 UTC = 14:17 CR. | MEDIDO |
| 02324 / 02325 validadas el 24-ago 23:10 | **Se mantiene** (`date_done` 24-ago 23:10:00 UTC = 17:10 CR). | MEDIDO |
| El método es `button_validate()` | **No cambia** (`assigned → done`). No se pudo ejecutar para verlo. | INFERIDO |
| "`quantity == product_uom_qty`, con `picked = False`" antes de validar | **Se mantiene** en la única pendiente: `WH/OUT/02378` pide Francés 12 paq, tiene 12 reservados y `picked = False`. Después de validar: 182 de 182 movimientos quedaron con `picked = True` y cantidad = demanda. | MEDIDO |
| "No hay backorder posible" | **Matiz importante.** Desde el 15-ago hay **0 backorders** (`backorder_id` vacío en las 75 salidas). Pero **sí hubo validaciones parciales**: `WH/OUT/02357` (pedido 68, consigna) se validó con 2 de 6 productos y **los otros 4 movimientos quedaron `cancel`**. Es decir, alguien eligió "sin backorder" en el asistente. El tipo de operación 2 tiene `create_backorder = 'ask'`, así que ante una diferencia Odoo **pregunta**. | MEDIDO |
| Categoría "`Producto terminado - Venta`" en `real_time` / `average` | **El nombre no coincide:** hoy es **`Todos / Producto terminado - Vendible`** (categoría 7). Valoración `real_time` y costo `average`, igual que antes. No sé si la renombraron o si el documento la nombró mal. | MEDIDO |

### 1.1 · El vínculo pedido Truefie → factura → orden de venta → salida [MEDIDO]

**Universo:** 87 pedidos en `v_ent_pedido_estado` (del 17-ago al 24-sep). Hay **67 con `origen='factura'`**
(63 `entregado` y 4 `preparado`) y **20 `manual`** (todos `entregado`). **3 de los manuales se
vincularon después a una factura** (pedidos 43, 44 y 62), así que hay **70 pedidos con factura
vigente**. Ninguno tiene más de una factura vigente y ninguna factura está en dos pedidos.

Resultado de seguir la cadena en Odoo, sobre esos 70:

| Forma de la cadena | Pedidos |
|---|---|
| factura `posted`, sin revertir → 1 orden de venta → **1 salida `done`** | **67** (64 de origen factura + 3 manuales vinculados) |
| factura revertida con NC → 1 orden → 1 salida **`cancel`** | 1 (pedido 11, 3484 / NC 0251) |
| factura revertida con NC → 1 orden → **2 salidas `done`** | 1 (pedido 67, 3534 / NC 0253) |
| factura `posted` → 1 orden → 1 salida **`assigned`** (el pendiente) | 1 (pedido 135, 3545) |

**Casos raros, mirados en todo Odoo desde el 15-ago** (75 salidas `outgoing`, 84 facturas o NC):

| Caso | Cuántos | Detalle |
|---|---|---|
| Salida sin orden de venta | **0** | Las 75 tienen `sale_id`. |
| Orden de venta con 2 o más salidas | **1** | `S02394` (pedido 67). **No es un backorder** (`backorder_id` vacío en las dos): el 22-sep se subió la línea de 1 a 4 "Caja [46]" y **Odoo creó una salida nueva, `WH/OUT/02379`, por la diferencia de 4,5 paq de Buns.** Andrea la validó ese día a las 19:13 UTC (13:13 CR). En total salieron 1,5 + 4,5 = **6 paq = 1 caja**, que es lo que Truefie registra. |
| Backorders | **0** | Ninguna salida con `backorder_id` ni `backorder_ids`. |
| Factura hecha a mano sin orden de venta | **1** | **3504** (27-ago), creada por Keylor, sin `invoice_origin` y sin `sale_line_ids`. **No tiene salida en Odoo.** |
| NC (`out_refund`) | **6** | 0249 (3487), 0250 (3403), 0251 (3484), 0252 (3502), 0253 (3534), 0254 (3544). **Ninguna generó devolución de inventario:** desde el 15-ago hay 21 recepciones, las 21 son compras (`P006xx`), y ninguna salida tiene `return_id`. |
| Re-facturas | **3** | 3499 reemplaza a la 3484 (pedido 20). 3546 reemplaza a la 3534, **pero Truefie no la vinculó**: el pedido 67 sigue apuntando a la 3534 revertida y la 3546 quedó como "revisado" en `ent_factura_decision`. 3547 reemplaza a la 3544 y **sí** está vinculada al pedido 134. |
| Facturas del período que no están en Truefie | 7 | 3546 y 3504 (arriba), 3498 (marcada "revisado", entrega del 8-jul), 3502 y 3487 (revertidas, salida `cancel`), y **3495 y 3525 de Good Food SA**, que son "Pan para moler GF (merma)", 7 u cada una, un producto que no es de los seis terminados. |

### 1.2 · La cola hoy y los pedidos "entregados" [MEDIDO]

- **Salidas sin validar: 1.** `WH/OUT/02378`, programada el 21-sep a las 15:44 UTC (09:44 CR), orden `S02405`, Super Mercado B M: **Francés 12 paq (2 cajas)**. Es la más vieja porque es la única.
- **Cuántas son de pedidos que Truefie da por `entregado`: 0.** La 02378 es del pedido 135, que en Truefie está `preparado` desde el 21-sep a las 15:56 UTC (09:56 CR), con los mismos 12 paq de Francés.
- **Al revés, que es lo que sí aparece:** **17 de las 69 salidas validadas** de pedidos Truefie se validaron en Odoo **antes** de que Truefie registrara la salida, o sin que la registrara. De esas 17:
  - Tres pedidos (140, 141 y 142) **siguen `preparado` en Truefie** y Odoo los validó el 25-sep a las 02:15 UTC (24-sep 20:15 CR).
  - En el resto la diferencia es de minutos u horas. Son salidas registradas en Truefie con hora retroactiva, o validadas en Odoo apenas facturadas.
  - **O sea que la validación de hoy no depende de Truefie.** Andrea valida en Odoo lo facturado, en tanda.
- **Truefie marca a mano, no lee Odoo.** Los 63 pedidos `entregado` de origen factura están marcados "Hecho" en `ent_pedido_valida_vigente`, **incluido el pedido 11, cuya salida en Odoo está `cancel`**. La sección "Entregado en Truefie, sin marcar como validado" mide el clic, no a Odoo (el propio código lo aclara, `index.html` ~l. 15361).

### 1.3 · Las brechas de inventario conocidas — qué muestra Odoo [MEDIDO]

| Caso | Qué muestra Odoo hoy | Brecha en unidad de venta |
|---|---|---|
| **3385** (29-jun, Pizza) | Salida `WH/OUT/02214` **`done`** el 29-jun a las 17:37 UTC (11:37 CR). La línea de Pizza dice 1 "Caja [46]" (6 u), y **Odoo descontó 3 paq**. | Si salió 1 caja real (6 paq), **faltan 3 paq, media caja**. ⚠️ La consigna decía "6 Pizza (1 caja)": son **6 unidades = 3 paquetes**. La caja entera no falta, falta la mitad. |
| **3504** (27-ago) | **No hay orden de venta ni salida.** La factura trae Blanco 2 cajas, Semillas 2 cajas y Buns 1 "Caja [46]". **Odoo no descontó nada de las tres líneas.** | La bitácora (barrido del ~22-sep) le atribuye **4,5 paq de Buns**. ⚠️ **Contradicción en los registros:** el 27-ago, `ENTREGAS_PENDIENTES.md` §9 dice que la 3504 "la creó Keylor para resolver algo contable, y **no hay nada que entregar**". Si no salió nada, Odoo está bien. Si salió, faltan **todas** sus líneas, no solo los Buns. Desde Odoo no se puede saber: hay que preguntarle a Andrea o a Keylor. |
| **3534** (14-sep) y **3544** (21-sep), Buns | **Ya se corrigieron en Odoo el 22-sep.** La 3534 tuvo su segunda salida `WH/OUT/02379` por +4,5 paq. La 3544 se re-facturó (3547) y su salida `WH/OUT/02377` salió por 6 paq. En los dos pedidos Odoo descontó **6 paq = 1 caja**, igual que Truefie. | **0** en Odoo. El pendiente de la bitácora ("ajustar el inventario en −18 cada una") **ya no aplica a Odoo**. |
| **Pedido 11** (19-ago) — no estaba en la consigna | La salida `WH/OUT/02319` está **`cancel`**. La entrega del 26-ago se descontó con la 3499 (`WH/OUT/02333`). | Según CLAUDE.md salieron **dos** entregas. Si es así, **Odoo nunca descontó la del 19-ago: 6 u de Blanco y 6 u de Semillas**. Truefie la tiene como entregada y "Hecho". |

## 2 · Idempotencia

**Se mantiene la recomendación:** leer `state` antes de validar y saltar si está `done` o `cancel`.
Se agrega esto:

- **Leer el retorno.** En Odoo 17, `button_validate` puede devolver un **dict de acción**, el asistente `stock.backorder.confirmation`, si lo hecho no calza con lo pedido. En ese caso **no validó** y tampoco dio error. El código del carril (`proxy_lectura`, rama `dev`, `93f5b7a`) ya lo avisa en un comentario. [INFERIDO + código leído]
- **Evitar el asistente de "transferencia inmediata".** Hoy no aparece porque las cantidades vienen puestas por la reserva (`quantity = demanda`). [MEDIDO en la pendiente]

## 3 · Quién valida hoy y cómo

**Quién.** `mail.tracking.value` **no se puede medir con el lector**: el campo `tracking_value_ids` está
restringido a "Administration / Settings". Se usó un sustituto: el mensaje de chatter
**sin texto** que Odoo escribe en el mismo segundo del cambio de estado (±5 s de `date_done`). [INFERIDO sobre datos MEDIDOS]

| Período | Salidas validadas | Quién |
|---|---|---|
| 2026 completo | 532 | **Andrea 525 · Lorena 7** (coincide con `write_uid`: Andrea 524, Lorena 7, y 1 de uid 28, que es la prueba del 2-sep sobre `WH/OUT/02346`) |
| Desde el 15-ago | 71 | **Andrea 71** |

**Cómo: en tandas.** Desde el 15-ago hubo **15 sesiones** de validación (validaciones separadas por
10 min o menos). De las 71 salidas, **64 comparten el segundo exacto** con otra (9 grupos). Eso es
seleccionar varias en la lista y validarlas juntas. Las sesiones grandes: 15 salidas el 24-sep a
las 20:15 CR (25-sep 02:15 UTC), 11 el 26-ago a las 14:17 CR, 9 el 19-ago a las 15:57 CR y 9 el
2-sep a las 16:36 CR. [MEDIDO]

**Cuándo.** Desde el 15-ago, por día CR: miércoles 29, jueves 23, lunes 9, martes 9, viernes 1.
Horas CR: de 11 a 20. [MEDIDO]

**Atraso** (fecha CR de `date_done` menos fecha CR de `scheduled_date`, que es la fecha real de entrega):

| Atraso | 0 d | 1 d | 2 d | 3 d | 4 d | 5 d | 7 d | 8 d |
|---|---|---|---|---|---|---|---|---|
| Salidas (desde 15-ago, n = 71) | 27 | 20 | 9 | 2 | 2 | 2 | 2 | 7 |

Mediana: **1 día**. Percentil 90: 7 días. Máximo: 8 días. En todo 2026 (n = 532) la mediana
fue de 2 días y el máximo de 16. Contra la salida registrada en Truefie (n = 52 pares en orden):
mediana **26,3 h**, percentil 90 **200,5 h**; 19 de 52 validadas en menos de 24 h. [MEDIDO]

## 4 · Qué hace Odoo al validar — medido sobre lo ya validado

Universo: los **182 movimientos `done`** de las 71 salidas validadas desde el 15-ago.

| Pregunta | Resultado | Marca |
|---|---|---|
| ¿Crea capa de valoración (`stock.valuation.layer`)? | Sí, en **182 de 182**. Valor total **−₡[monto en la versión privada]**. | MEDIDO |
| ¿Crea asiento? | Sí, en **180 de 182**. Los 2 sin asiento son capas de **valor ₡0** ("Pan para moler GF (merma)"). Los 180 están en el diario **"Valoración inventario"**, todos `posted`. | MEDIDO |
| ¿Qué cuentas? | **Debe 1103030 Inventario en Tránsito / Haber 1103020 Producto final** en los 180. Ejemplo: `STJ/2026/08/0297` · `WH/OUT/02311` · Francés · ₡[monto en la versión privada]. | MEDIDO |
| ¿Y la factura? | Mueve el costo por su lado: **Debe 5101030 Costo de Ventas / Haber 1103030 Inventario en Tránsito** (en la 3545: ₡[monto en la versión privada]). La 1103030 es un **puente**: la factura la acredita y la validación la debita. Mientras la salida no se valida, el puente queda abierto. | MEDIDO |
| ¿Con qué fecha queda el asiento? | Con la **fecha CR del día en que se valida**, en 180 de 180. Coincide con la fecha de entrega solo en **73**. Las otras 107 quedan uno o más días después. Además, **5 entregas de agosto** (`WH/OUT/02338` a `02342`, programadas el 28 y el 31-ago) quedaron asentadas el **2-sep**. | MEDIDO |
| ¿La fecha usa la zona horaria de quien valida? | Probablemente sí. En 40 asientos la fecha UTC y la CR eran distintas, por ejemplo validaciones a las 20:15 CR, y los 40 tomaron la fecha CR, que es la zona de Andrea. **Un usuario nuevo sin zona horaria (UTC) asentaría con fecha de mañana cualquier validación hecha después de las 18:00 CR.** | INFERIDO de MEDIDO |
| Saldo de la 1103030 | Hoy **₡[monto en la versión privada]** (debe). Quedó en **cero exacto** al cierre de dic-2023 y de dic-2025. En 2026 osciló por mes entre −₡[monto en la versión privada] y +₡[monto en la versión privada] (agosto: −₡[monto en la versión privada]). | MEDIDO |
| Backorders | **0** desde el 15-ago. Hubo 1 validación parcial "sin backorder" (`WH/OUT/02357`, 4 movimientos `cancel` dentro de una salida `done`). | MEDIDO |
| `picked` (Odoo 17) | Antes de validar, `False` (la pendiente). Después, `True` en 182 de 182. | MEDIDO |
| Reservado contra pedido | `quantity == product_uom_qty` en 182 de 182 validados y en la pendiente. | MEDIDO |
| Lotes | **0 de 183** `stock.move.line` tienen `lot_id` o `lot_name`. Los seis terminados tienen `tracking = none` (re-leído hoy). El lote sigue viviendo solo en Truefie. | MEDIDO |
| ¿Todo en una transacción? | Sí, por diseño de Odoo: una llamada RPC es una transacción. **No se pudo ver** sin escribir. | INFERIDO |

## 5 · El candado y el permiso mínimo para validar

### 5.1 · Capa 3 — re-medida hoy [MEDIDO]

`python3 diagnostico_permisos.py` (sin flags):

| Modelo | read | write | create | unlink |
|---|:--:|:--:|:--:|:--:|
| `stock.picking` | ✅ | ❌ | ❌ | ❌ |
| `stock.move` | ✅ | ❌ | ❌ | ❌ |
| `stock.scrap` | ✅ | ❌ | ❌ | ❌ |
| **`stock.move.line`** | ✅ | **✅** | **✅** | **✅** |
| `account.move` | ✅ | ❌ | ❌ | ❌ |
| `product.product` | ✅ | ❌ | ❌ | ❌ |

- **Se mantiene lo del 3-sep:** ni `stock.picking` ni `stock.move` se pueden escribir, y **`stock.move.line` sigue abierto**.
- **Las `ir.rules` siguen sin frenar:** `check_access_rule('write')` pasó sobre `WH/OUT/02385` (`done`).
- `odoo_read.py --quien`: **16 grupos**, **sin `[42] Inventory / User`**. `[1] Internal User` implica 13 grupos técnicos, entre ellos `[56] Stock Accounting Automatic`.
- `ir.model.access`, `ir.rule` y `res.groups.model_access` dan acceso denegado: **no medible con el lector**. Por eso el origen exacto del permiso sobre `stock.move.line` sigue sin medir.

### 5.2 · Qué permiso hace falta para validar [INFERIDO — Odoo 17 estándar, no verificable sin leer ACL]

- **Lo mínimo práctico es el grupo `[42] Inventory / User`**, que da `stock.picking` / `stock.move` / `stock.move.line` / `stock.quant` con write/create. Validar crea y escribe `stock.move.line` y quants, y si hay backorder **crea** `stock.picking` y `stock.move`.
- **No hace falta permiso de contabilidad.** En `stock_account` el asiento y la capa de valoración se crean con `sudo()`. El grupo `[56] Stock Accounting Automatic` ya viene con todo usuario interno.
- **`[42]` implica `[1]` y `[70] Quality / User`** (medido en `res.groups.implied_ids`).
- **Hacerlo más angosto no es posible con ACL** (ya lo decía el 25-ago y se mantiene). Se puede acotar con una `ir.rule` a salidas `outgoing`, pero con `write` sobre `stock.picking` ese usuario también podría cambiar fechas, socios o cantidades.

### 5.3 · Licencia

- **Usuarios internos activos hoy: 7** — Administrator, Alfonso González, Andrea, Keylor, **Lobby Solo Lectura**, Lorena y María Fernanda. [MEDIDO]
- **Un usuario nuevo con acceso al backend es un usuario pago.** La página de precios de Odoo (consultada hoy, precios en USD tal como se muestran) cuenta como usuario pago a todo empleado "with backend access to create, view, or edit documents". Muestra **US$7,90/usuario/mes (Standard)** y **US$13,40 (Custom)**, y dice que la **"External API" es del plan Custom**. [MEDIDO en la web]
- Como uid 28 ya usa la API, **probablemente la empresa está en Custom**. [INFERIDO] **El contrato real y el precio en colones no están verificados.**
- La página también menciona un **"Light User" a US$2,90** para "warehouse operations". **No verificado** si un usuario así puede validar por API.
- **Alternativa sin licencia nueva: darle `[42]` a uid 28.** No se recomienda: deshace el arreglo del 3-sep y vuelve a dejar el candado en listas de JavaScript.

### 5.4 · El carril de escritura que ya existe en código [MEDIDO leyendo el repo]

`proxy_lectura`, rama **`dev`** (commit `93f5b7a`, 2-sep):

- Agrega `ESCRITURA_OK = {'stock.picking': ['button_validate']}`, apagado mientras no exista `ESCRITURA_ODOO=1`.
- Antes de validar, **re-lee** el picking y exige `outgoing` + `assigned`.
- **`origin/main`** (lo desplegado, historia distinta) **no tiene el carril**.

Tres problemas, con los permisos de hoy:

1. **Usa las mismas credenciales del lector** (`ODOO_LOGIN` / `ODOO_APIKEY` = uid 28). Desde el 3-sep uid 28 no puede escribir `stock.picking`, **así que encendido fallaría con error de acceso.** Para funcionar necesita otro usuario, y ese usuario **no debería** vivir en el mismo proceso que sirve las lecturas. [INFERIDO de lo MEDIDO]
2. **Reenvía el `context` que manda el navegador.** En `button_validate` hay claves de contexto que cambian el resultado: `cancel_backorder`, `skip_backorder`, `picking_ids_not_to_backorder` y `force_period_date` (esta última cambia la **fecha contable**). **El contexto lo tiene que fijar el servidor, no el cliente.** [INFERIDO]
3. **No compara cantidades con Truefie.** Solo mira el estado. La regla del 23-sep (descuadre) tendría que chequearse **del lado del servidor**, leyendo Supabase, no confiando en lo que diga el navegador.

## 6 · Pedidos DESCUADRADOS — definición y cuenta de hoy

**Definición exacta, sacada del código** (`_entColgarDetalle`, `index.html` l. 13727–13876).
Para cada pedido con alisto vigente, y por producto:

- **factura** = suma de `ent_pedido_linea.cant_uds` (lo que decía la factura **cuando se preparó**, en unidades sueltas);
- **salió** = suma de `ent_alisto_linea.cant_uds` del alisto vigente (las líneas `no_se_entrega` valen 0).

Es **descuadrado** si **algún producto** tiene `|factura − salió| > 0`.

SQL usado:

```sql
with fac as (select pedido_id, producto_id, sum(cant_uds) f from ent_pedido_linea group by 1,2),
sal as (select av.pedido_id, l.producto_id, sum(l.cant_uds) s
        from ent_alisto_vigente av join ent_alisto_linea l on l.alisto_id=av.alisto_id group by 1,2)
select ... from fac full join sal using (pedido_id, producto_id)
where pedido tiene alisto vigente and abs(f-s) > 0
```

**Hoy: 3 pedidos descuadrados** (los tres `entregado`, ninguno pendiente en Odoo). [MEDIDO]

| Pedido | Factura | Producto | Factura dice | Salió | Qué pasa en realidad |
|---|---|---|---|---|---|
| 67 | 3534 (revertida) | Buns | 1,5 paq | 6 paq (1 caja) | **Descuadre viejo.** Odoo ya se corrigió: re-facturada con la 3546 y descontados 6 paq. Truefie sigue apuntando a la 3534. |
| 134 | 3547 | Buns | 1,5 paq | 6 paq (1 caja) | **Descuadre viejo.** Se re-vinculó a la 3547, pero `ent_pedido_linea` **conserva las cantidades de la 3544**. La 3547 y Odoo dicen 6 paq. |
| 68 | 3524 | Semillas / Galletas / Francés / Buns | 1 u / 2 u / 1 paq / 1 paq | 0 (consigna, "no se entrega") | **Descuadre real, pero ya resuelto a mano en Odoo:** validación parcial sin backorder. La factura sigue cobrando lo que no salió. |

**Conclusión de diseño.** La regla del 23-sep es correcta, pero **el cálculo actual compara contra
una foto de la factura** que no se actualiza cuando se re-factura. **Para un carril automático, la
comparación que importa es Truefie "salió" contra la demanda viva del picking**
(`stock.move.product_qty`, en la unidad base del producto). Con esa comparación, hoy **0 pedidos**
quedarían apartados: la única salida pendiente (02378) calza exacto con Truefie, 12 paq de Francés
contra 12 paq. [MEDIDO]

## 7 · ¿Sirve la demo para probar?

- `demotruefood.odoo.com` **responde** (`common.version()` → **17.0+e**, el mismo que producción) y tiene una base asociada al dominio. [MEDIDO]
- **Pero no se puede usar hoy:**
  - **No existe `conexion_demo.env`** en el repo, así que no hay credenciales. [MEDIDO]
  - La lista de bases está cerrada (`db.list` → Access Denied), así que no se ve el nombre de la base. [MEDIDO]
  - La bitácora del 2-sep ya lo tenía como pendiente: "falta `conexion_demo.env`, y hay que resolver si la demo acepta API key o pide contraseña".
- **Advertencia para cuando se use:**
  - Los ids de producto de la demo **no coinciden** con producción (CLAUDE.md).
  - No sabemos de qué fecha es la copia.
  - **Para probar un `button_validate` sirve.** Para probar "calza con Truefie" no, porque los pedidos de Truefie apuntan a facturas de producción.

---

# CASO 2 · Salida sin factura → traslado interno (solo lo re-verificado)

- **La ubicación 19 "Mercadeo y Muestras" se mantiene** (`usage = inventory`, cuenta **6106008** de entrada y de salida), igual que la 14 (5101098), la 15 (1103015) y la 16 (6106016). [MEDIDO]
- **Ya se está usando, a mano:** desde el 15-ago hay **11 traslados internos `WH/INT/00134`–`00144`**, WH/Stock → Mercadeo y Muestras. Los 11 están `done`, los creó y validó Andrea, y tienen el `origin` vacío. [MEDIDO]
- Truefie lleva la cola en `ent_odoo_pendiente`: 5 `traslado_interno` + 1 `nota_credito`. 5 están marcados "Hecho" y queda **1 abierto**: el pedido 145, regalía del 23-sep. [MEDIDO]
- ⚠️ `ent_odoo_hecho.referencia` está **vacío en las 5 filas**, así que Truefie no guarda qué `WH/INT` corresponde a qué salida. Los pedidos de consumo interno también van a la ubicación 19, que es **cuenta de mercadeo**. Esto es una pregunta para la contadora (§9).

---

# 8 · Opciones de diseño

Contexto medido que pesa en la decisión:

- **Cola de 1.**
- **0 diferencias de cantidad en 68 pedidos.**
- **Una sola persona valida, en 15 sesiones en 6 semanas.**
- **El único costo visible del proceso manual es la fecha del asiento:** 107 de 180 asientos quedan después de la entrega, y 5 cruzaron de mes.
- Las brechas de inventario que existen (3385, 3504 y pedido 11) **no son de validación**. Vienen de una unidad mal facturada y de facturas anuladas o hechas sin orden de venta. Automatizar no las habría evitado.

## Opción A · Botón por pedido en Truefie → carril de escritura con usuario propio

Andrea (o Daniel, al entregar) toca "Validar en Odoo". Un **servicio aparte** del proxy de lectura (otro servicio en Render, o como mínimo otra variable de credenciales y otro proceso):

1. Valida el JWT y el **rol** de quien pide.
2. Lee Supabase por su cuenta: pedido `entregado`, salida vigente, sin anulación, sin descuadre **contra el picking vivo**, mismo partner, factura `posted` sin revertir.
3. Re-lee el picking (`outgoing`, `assigned`).
4. Llama `button_validate` con **contexto fijo del servidor**.
5. Trata un retorno dict como **fallo** y registra `pendiente` / `validada` / `fallo`.

- **Pros:** el asiento puede quedar con la fecha de la entrega real. Saca trabajo manual a Andrea. El código base (puerta angosta, relectura) ya existe en `dev`.
- **Contras:** **licencia nueva** (~US$13,40/mes si es Custom, no verificado). Superficie de escritura alcanzable desde un navegador. Hay que mantener un segundo servicio.
- **Riesgos:**
  - Con `[42]`, el usuario nuevo puede escribir **cualquier** salida, y además `stock.move.line`. Una `ir.rule` acota a salidas, pero no la operación.
  - Si se dispara al "Entregar" de Daniel, un error de registro en Truefie pasa a ser **inventario y contabilidad** en el momento, y desde el 27-ago no hay segundo testigo (el Excel).
  - Zona horaria del usuario nuevo mal puesta: asientos con fecha corrida.

## Opción B · Lote nocturno en el repo privado (como el vigía de unidades y el respaldo)

Un script de Python en GitHub Actions, con el usuario dedicado en *secrets*:

1. Lee Supabase y Odoo.
2. Arma la lista de salidas `assigned` cuyo pedido Truefie está `entregado` y calza exacto con el picking.
3. Valida **esas y solo esas**.
4. Abre un ticket por cada apartada (descuadre, NC, factura revertida, sin pedido).

**Primero corre 2 a 4 semanas en modo simulación**: escribe "validaría X" y se compara contra lo que Andrea valida a mano.

- **Pros:**
  - Ningún navegador toca la escritura.
  - Un solo script auditable, con modo simulación natural.
  - Reusa el patrón del vigía (tickets) y del respaldo (secrets).
  - Con lo medido hoy, casi no tendría excepciones.
- **Contras:**
  - Misma licencia que A.
  - **Atraso de cron medido: 4 h 43 min** (vigía) y ~5 h (respaldo). "Nocturno" puede correr de día.
  - La fecha del asiento sería la de la corrida, no la de la entrega. Mejora el promedio (hoy la mediana es 1 día), pero no lo deja exacto.
- **Riesgos:**
  - Un error de la lógica valida muchas salidas de golpe. Se mitiga con un tope por corrida y con simulación previa.
  - El usuario tiene que tener zona CR.

## Opción C · Seguir validando a mano y que Truefie muestre el cuadre contra Odoo (solo lectura)

Truefie deja de medir "alguien tocó Hecho" y **lee el estado real** del picking por el proxy de lectura. Muestra:

- Salidas `assigned` con el estado del pedido Truefie. Hoy: 02378 ↔ pedido 135 `preparado`.
- **Entregado en Truefie y `cancel` en Odoo.** Hoy: pedido 11.
- **Validado en Odoo y no entregado en Truefie.** Hoy: pedidos 140, 141 y 142.
- **Cantidad descontada ≠ salida** (hoy 0), comparando contra el picking vivo.
- **Descuadres viejos** por re-factura sin re-vincular. Hoy: pedidos 67 y 134.

- **Pros:** **cero escritura y cero licencia.** Usa permisos que ya existen y están medidos. Ataca lo que de verdad aparece en los datos (desincronizaciones), no la cola, que hoy es de 1.
- **Contras:** Andrea sigue validando. La fecha del asiento sigue corrida. La cola puede volver a crecer si Andrea se ausenta. En 2026 hubo atrasos de hasta 16 días.
- **Riesgos:** bajos. El mayor es que sea una pantalla más que nadie mira, y eso se evita con las 5 reglas de alerta: aparece solo si hay algo que hacer y con fecha.

## Recomendación

**C ahora, B después, y A solo si B se queda corto.**

- **C no escribe nada y cierra los agujeros que sí aparecen.** Los números de hoy no justifican abrir una puerta de escritura: cola de 1, 68 de 68 cantidades exactas.
- **Además, C es la precondición de B:** sin una comparación confiable Truefie ↔ picking vivo, un lote automático validaría a ciegas. **C es ese comparador.**
- **B tiene sentido si** la contadora dice que la fecha del asiento importa, o si la cola vuelve a crecer (por ejemplo, más de 5 salidas o más de 3 días).
- **A viene al final:** si hace falta, B se puede disparar a mano. Un botón en el teléfono de Daniel que escribe en contabilidad no tiene segundo testigo desde el 27-ago.

**Sea cual sea la opción:**

- **No encender el carril de `dev` tal como está.** Usa uid 28 y reenvía el contexto del cliente.
- **Usuario dedicado con zona horaria `America/Costa_Rica`.**
- **Sacar la comparación de descuadre de la foto `ent_pedido_linea`** y hacerla contra la demanda del picking.

---

# 9 · Preguntas para la contadora

1. **La fecha.** Cuando se confirma en Odoo que un pedido salió, el sistema hace un registro contable con la fecha del día en que alguien lo confirma, no del día en que salió el pan. Hoy, de 180 registros, 107 quedaron con una fecha posterior a la entrega, y cinco entregas de fines de agosto quedaron registradas el 2 de septiembre. ¿Le importa esa diferencia? ¿Qué fecha necesita usted: la de la entrega o la de la confirmación?
2. **La cuenta puente.** Al facturar, Odoo pasa el costo a "Costo de ventas" usando la cuenta "Inventario en Tránsito". Al confirmar la entrega, la vacía contra "Producto final". Esa cuenta tiene hoy ₡[monto en la versión privada], y quedó en cero exacto en diciembre de 2023 y en diciembre de 2025. ¿La ajusta usted a fin de año? ¿Revisa su saldo en los cierres de mes?
3. **Productos que salieron y Odoo no descontó.** ¿Qué hacemos con estos casos: un ajuste de inventario, contra qué cuenta, o se dejan?
   - La entrega del pedido 11, del 19 de agosto: 6 panes blancos y 6 de semillas. Su factura se anuló y el pedido quedó cancelado.
   - La factura 3385 de junio: cobró media caja de pizza menos de la que salió.
4. **La factura 3504** (27 de agosto) la hizo Keylor a mano, sin pedido. En Odoo no descontó nada del inventario: 2 cajas de pan blanco, 2 de semillas y 1 de buns. ¿Esa factura corresponde a producto que salió ese día, o era un ajuste de algo anterior?
5. **Notas de crédito.** Desde el 15 de agosto hubo 6 notas de crédito y ninguna devolvió producto al inventario de Odoo. ¿Está bien así cuando la nota es por un error de precio, de cédula o de unidad? Y cuando el cliente sí devuelve producto (hubo una devolución el 17 de septiembre), ¿cómo quiere que quede registrado?
6. **Re-facturar por un error de unidad.** En la factura 3534 se corrigió la cantidad en el pedido, y Odoo creó una segunda salida por la diferencia. ¿Le sirve así, o prefiere que se haga de otra forma?
7. **Consigna.** Al cliente en consigna del pedido 68 (9 de septiembre) se le facturaron 6 productos, pero solo salieron 2. En Odoo se confirmaron los 2 y se cerró el resto sin pendiente, así que la factura cobra 4 productos que no salieron. ¿Cómo quiere manejar la consigna: factura después de vender, o nota de crédito?
8. **Pedido incompleto.** Cuando sale menos de lo facturado, ¿se confirma lo que salió y se cierra el resto, o se deja un pendiente abierto en Odoo hasta que se aclare con el cliente?
9. **Regalías y consumo interno.** Hoy los dos se registran contra "Gastos de Mercadeo". ¿El consumo interno debería ir a otra cuenta?
10. **Un usuario automático.** Si un sistema confirmara las entregas en Odoo con su propio usuario, ¿tiene algún inconveniente contable o de control? ¿Quién debería figurar como responsable?

---

# Anexo · Cómo se midió (para volver a correrlo, no para citarlo)

Scripts en el scratchpad de esta sesión (solo lectura, todos por `odoo_read.call` o `pg_lector.Lector`):

- `dump_truefie.py` → `truefie.json`: `v_ent_pedido_estado`, `ent_pedido_factura(_vigente)`, `ent_pedido_linea`, las líneas del alisto vigente, `ent_anulacion`, `ent_odoo_pendiente/_linea/_hecho`, `ent_factura_decision_vigente` y `ent_salida_verif_vigente`.
- `pull1.py` → `odoo1.json`: `account.move.read` de las facturas de Truefie y sus reversiones, `account.move.line` (`sale_line_ids`), `sale.order.line`, `sale.order` y `stock.picking` de esas órdenes.
- `pull2.py` → `odoo2.json`: `stock.picking.search_read([picking_type_code='outgoing', scheduled_date o date_done ≥ '2026-08-15 06:00:00'])`, más sus `stock.move` y `stock.move.line`, las facturas y NC con `invoice_date ≥ 2026-08-15`, y `sale.order` desde el 10-ago.
- `pull3.py` → `odoo3.json`: salidas `done` con `date_done ≥ 2026-01-01 06:00 UTC`, más `mail.message` de esas salidas (sustituto del tracking).
- `an1.py` a `an6.py`: cadena 1 a 1, casos raros, quién/cuándo, Odoo contra Truefie, y valoración/asientos/cuentas.
- `det.py S0xxxx …`: detalle de orden → facturas → líneas → salidas → movimientos.
- En línea: `stock.picking.read_group([picking_type_code='outgoing'], ['state'])`, `account.move.line.read_group([account_id=598, parent_state='posted'], ['balance:sum'], ['date:month'])`, `product.category.read([7])`, `stock.location.read([14,15,16,19])`, `stock.picking.type.read([2,5])`, `res.groups.read([42,76,1,56])` y `res.users.search_read([share=False])`.
- Permisos: `python3 odoo_read.py --quien` y `python3 diagnostico_permisos.py` (sin `--escribir`).
- Demo: `xmlrpc/2/common.version()` y `xmlrpc/2/db.list()` sobre `demotruefood.odoo.com`, sin autenticar.
- Proxy: `git -C proxy_lectura show origin/main:server.js` y `origin/dev:server.js`.

**No medible con el lector:** `mail.tracking.value` / `tracking_value_ids` (Administration / Settings), `ir.model.access`, `ir.rule` y `res.groups.model_access`. Tampoco el comportamiento real de `button_validate` (habría que escribir) ni el contrato de licencias de la empresa.
