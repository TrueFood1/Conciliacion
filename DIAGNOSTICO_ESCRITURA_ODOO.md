# Diagnóstico · las dos primeras escrituras en Odoo

**25-ago-2026. Solo diagnóstico: no se escribió nada en Odoo, no se tocó el
proxy, no se cambió ningún permiso.** Todas las lecturas salieron por
`odoo_read.py` (allowlist de solo lectura) contra `truefood.odoo.com`.
Versión medida: **Odoo 17.0+e** (Enterprise).

---

# CASO 1 · Validar la entrega

## 1 · Qué queda pendiente en Odoo después de facturar

**La factura no.** Las 22 facturas del 17-ago en adelante están `posted` desde el
momento de facturar. No hay nada que confirmar ahí.

**Lo que queda pendiente es el `stock.picking` de salida, en estado `assigned`.**
Estado real de la cola de salidas, medido:

| Estado | Cantidad |
|---|---|
| `assigned` (reservado, **sin validar**) | **9** |
| `done` | 2 207 |
| `cancel` | 104 |
| `draft` / `waiting` / `confirmed` | 0 |

Los 9 sin validar: 7 son de hoy (25-ago) y **dos vienen arrastrados**:

| Picking | Fecha | Cliente | Origen | Factura |
|---|---|---|---|---|
| `WH/OUT/02319` | 19-ago | Mentha y limón | `S02346` | 3484 |
| `WH/OUT/02321` | 20-ago | Pastelería Christophe | `S02348` | **3486** |

⚠️ **`WH/OUT/02321` es el pendiente abierto de la bitácora.** La 3486 figuraba
como "sin bloque en la hoja Y sin salida de inventario validada en Odoo". Acá
está la respuesta: el picking **existe**, tiene Pan Blanco **20 u** reservadas y
nunca se validó. No es que no haya salido: es que nadie confirmó el documento.

Las de la 3489 y 3490 (`WH/OUT/02324` y `02325`) ya están `done`, validadas a
mano el 24-ago 23:10.

**El método es `stock.picking.button_validate()`**, que lleva `assigned → done`.
Los movimientos ya vienen con la cantidad puesta por la reserva
(`quantity == product_uom_qty`), con `picked = False`. No hay backorder posible
porque no hay diferencia entre pedido y reservado.

⚠️ **Validar NO es solo mover inventario: genera asiento contable.** La categoría
`Producto terminado - Venta` está en **`real_time` / `average`**, así que el
`_action_done` posta al diario de existencias. La escritura llega a contabilidad,
no solo a stock. Es un argumento a favor del caso —el asiento hoy tampoco se está
generando en esos 9— pero hay que decirlo antes de abrir.

## 2 · Idempotencia

**Recomendación: no depender del error de Odoo. Leer `state` primero y saltar si
ya está `done` o `cancel`.** La lectura ya está permitida por el candado, cuesta
una llamada y convierte el caso en inofensivo por construcción.

Por qué no confiar en el error: no pude medirlo sin escribir, y un `UserError` de
Odoo llega por RPC como un `Fault` genérico, del mismo tipo que un error real de
permisos o de datos. Distinguir "ya estaba validado" de "no pude validar" por el
texto del mensaje es frágil — y esa distinción es justo la que decide si se
reintenta o se alerta.

## 3 · Modo de fallo

**Del lado de Odoo el riesgo es bajo:** `button_validate` corre en UNA transacción
por llamada RPC. O el picking queda `done` con sus movimientos, sus quants y su
asiento, o no cambia nada. No hay estado intermedio persistido.

**El riesgo está en la costura, y ya lo conocemos.** Cuando Truefie dispare la
validación, la salida **ya está registrada en Supabase** — y el saldo por lote ya
bajó, porque baja al **PREPARAR**, no al entregar. O sea: si la validación falla,
Truefie tiene la verdad y Odoo queda atrás. Es exactamente el mismo desbalance del
20-ago con la verificación de factura.

**Manejo propuesto, con el patrón del domingo:**

1. **Registrar y marcar**, nunca fallar cerrado. La salida se registra igual; una
   fila nueva (misma forma que `ent_salida_verificacion`) guarda
   `pendiente` / `validada` / `fallo` con el `picking_id` y el detalle.
2. **Reintento hacia atrás**, como `ent_salida_a_reverificar`: las `pendiente` se
   vuelven a intentar, no se quedan esperando a que alguien las mire.
3. **Alerta en Pendientes** para lo que no se resolvió solo.
4. La sección actual "Entregado en Truefie, sin validar en Odoo" **no se borra**:
   pasa a ser la red que atrapa lo que el disparo no logró.

## 4 · El candado — cuál capa hay que abrir

Las tres capas, medidas:

| Capa | Qué es | Estado |
|---|---|---|
| 1 · `odooRpc` en `index.html` | allowlist `LECTURA_OK`, deny-by-default | cliente |
| 2 · Proxy de lectura (`server.js`) | allowlist `LECTURA_OK`, deny-by-default | servidor |
| 3 · **El usuario de Odoo** | el proxy se autentica como **`Lobby Solo Lectura`** (uid 28), grupo **`Solo Lectura Lobby` [76]** | **Odoo** |

**La capa 3 es real, no cosmética**: el grupo 76 tiene **18 reglas de acceso y
CERO con permiso de escritura**. Aunque alguien se saltara las capas 1 y 2, Odoo
rechazaría la escritura. Eso es bueno y conviene no perderlo.

**⚠️ Y acá está la respuesta que cambia la decisión: Odoo NO puede expresar un
permiso tan estrecho.** Las ACL de Odoo (`ir.model.access`) son por **modelo y
operación CRUD**, no por método. No existe "puede llamar `button_validate` y nada
más". Lo más angosto que se puede escribir es:

- **`write` sobre `stock.picking` y `stock.move`** para el grupo 76.
- Se puede acotar **qué registros** con una `ir.rule` (por ejemplo, solo pickings
  con `picking_type_id.code = 'outgoing'` del almacén WH) — eso limita el alcance
  a las salidas, que es la mitad del problema.
- Lo que **no** se puede limitar es la operación: con `write` sobre
  `stock.picking`, ese usuario también puede cambiar fechas, socios o cantidades
  de cualquier picking que la regla le deje ver.

**De yapa, algo que ya está abierto y conviene saber:** `stock.move.line`
("Product Moves") tiene permiso de escritura para **`Tipos de usuario / Usuario
interno`** — o sea, para cualquier usuario interno, incluido el de solo lectura.
Esa puerta ya existe y no la puso este proyecto.

## 5 · Precondiciones para que el disparo sea seguro

1. La **factura** está `posted` y **no reversada** (`reversed_entry_id` vacío) —
   ya lo lee Despachos hoy.
2. La **orden de venta** no está `cancel`. Medido: `S02349` (3487) lo está, y su
   picking quedó `cancel` — disparar ahí no debe intentar nada.
3. **Existe el picking** y su `state` es `assigned`. Si está `draft`, `waiting` o
   `confirmed`, falta reserva y validar no corresponde: eso es un problema de
   inventario, no de despacho.
4. **Las cantidades calzan**: la suma por producto del alisto vigente de Truefie
   == `product_uom_qty` del picking. Si no calzan, **no se dispara y se alerta** —
   validar con diferencia crea un backorder silencioso.
5. El pedido tiene **alisto vigente** y **salida vigente** en Truefie, sin fila en
   `ent_anulacion`.
6. El picking pertenece al **mismo partner** que el pedido de Truefie.

⚠️ Recordatorio que se cumple solo: los seis terminados tienen `tracking = none`,
así que **la validación confirma cantidades y movimiento, nunca lotes**. El lote
sigue viviendo solo en Truefie. No hay nada que escribirle a Odoo al respecto.

---

# CASO 2 · Salida sin factura → traslado interno

## 1 · La ubicación "Mercadeo y Muestras" YA EXISTE

**No hay nada que crear.** Medido:

| Campo | Valor |
|---|---|
| `id` | **19** |
| `complete_name` | `Virtual Locations/Mercadeo y Muestras` |
| `usage` | `inventory` |
| `valuation_in_account_id` | **6106008** · Gastos de Mercadeo y … |
| `valuation_out_account_id` | **6106008** · Gastos de Mercadeo y … |

Está configurada con la cuenta de gasto en las dos direcciones, así que el asiento
sale solo: con `Producto terminado - Venta` en `real_time`, mover Stock → 19 posta
contra 6106008. **La decisión contable ya está implementada en Odoo**; Truefie
solo tendría que crear el movimiento.

Un matiz de vocabulario que conviene tener claro: `usage = inventory` significa
que Odoo la trata como ubicación de **ajuste**, no como una interna. El movimiento
Stock → 19 es, en el lenguaje de Odoo, un ajuste valorado — no un "traslado
interno" entre dos ubicaciones internas. El efecto contable es el buscado; el
nombre del documento no.

## 2 · Las otras ubicaciones virtuales que ya existen

| id | Ubicación | `usage` | Cuenta |
|---|---|---|---|
| 14 | `Ajustes de inventario` | inventory | 5101098 Pérdidas de inventario |
| 16 | `Desecho` | inventory | 6106016 Pérdida producto defectuoso |
| 15 | `Production` | production | 1103015 Inventario de producción |
| 19 | `Mercadeo y Muestras` | inventory | 6106008 Gastos de Mercadeo |

**Cobertura de los cuatro motivos:**

| Motivo | Destino | Estado |
|---|---|---|
| Regalía | **19** Mercadeo y Muestras | ✅ listo |
| Degustación | **19** Mercadeo y Muestras | ✅ listo (es una muestra) |
| Consumo interno | — | ❌ **no hay ubicación** |
| Reposición | — | ❌ **no hay, y además puede que no corresponda** |

Dos de los cuatro no tienen destino. Y **reposición es distinta de las otras
tres**: reponer producto a un cliente es producto que sale al cliente, no a una
ubicación virtual — el gasto es de garantía/reposición, no de mercadeo. Vale
decidirlo con el contador antes de darle un destino, porque elegir mal manda el
gasto a la cuenta equivocada y eso no se ve en ningún número de inventario.

## 3 · Cómo se crea por API

**No se puede crear ya validado.** Son dos llamadas como mínimo:

1. `stock.picking.create({...})` con el tipo de operación **`5` (Traslados
   internos)**, `location_id = 8` (WH/Stock), `location_dest_id = 19`, y las
   líneas como comandos one2many sobre `move_ids`
   (`product_id`, `product_uom_qty`, `product_uom`, `name`).
2. `stock.picking.button_validate([id])` — el propio `button_validate` confirma y
   reserva lo que esté en `draft`, así que no hacen falta `action_confirm` ni
   `action_assign` por separado.

**Y ahí está la diferencia de riesgo que anticipaste, confirmada:** entre el paso
1 y el 2 existe un documento en Odoo que nadie pidió. Si el paso 2 falla, queda un
picking `draft`/`assigned` fantasma —con stock reservado— que ningún proceso
limpia. En el caso 1 un fallo deja las cosas *como estaban*; acá deja basura.

**Manejo propuesto, más estricto que el caso 1:**

- Guardar el `picking_id` en Supabase **apenas se crea**, antes de intentar
  validar. Sin eso, un fallo de red deja un documento huérfano que nadie puede
  siquiera nombrar.
- Si el paso 2 falla: **no reintentar creando de nuevo** — reintentar la
  *validación* del picking ya creado. Crear dos veces es duplicar la salida.
- Alerta explícita con el número del picking, para que se pueda borrar a mano.
- Y la precondición dura: **una salida de Truefie no puede crear dos pickings.**
  La llave anti-duplicado tiene que existir antes de la primera escritura.

## 4 · El permiso — ¿alcanza con el del caso 1?

**No. Son permisos distintos, y el del caso 2 es estrictamente mayor.**

| | Caso 1 · validar | Caso 2 · crear traslado |
|---|---|---|
| `stock.picking` | **write** | **create + write** |
| `stock.move` | **write** | **create + write** |
| Acotable por `ir.rule` | sí (solo `outgoing`) | sí (solo tipo 5), pero la regla **no** limita el `create` |

`create` es la diferencia, y no es menor: con `write` acotado por regla, el
usuario solo puede tocar documentos que ya existen y que la regla le deja ver. Con
`create` puede fabricar documentos nuevos — y una `ir.rule` no impide crear, solo
condiciona qué se ve después.

**Recomendación: abrirlos por separado y en orden.** Primero el caso 1, que es
`write` acotado a salidas y no crea nada; después, con esa experiencia encima,
decidir el `create`.
