# Molde · traslado interno de una salida SIN factura

**Leído de Odoo el 27-sep-2026** (solo lectura, `odoo_read.py`, uid 28) sobre
`WH/INT/00145`, el traslado del **pedido 145 de Truefie** (regalía, 23-sep), que
Andrea creó y validó A MANO ese día siguiendo la guía de la sesión. Es el primer
traslado con `Documento origen` lleno: los 9 anteriores (desde el 25-ago) lo
dejaron vacío y no hay forma de emparejarlos con su pedido.

Sirve de molde para la versión automática: dice QUÉ campos y valores deja un
traslado bien hecho. **No trae montos**: el asiento muestra el costo de cada
producto y este repo es público. La lectura cruda completa (con el asiento)
vive en el repo PRIVADO `respaldo-truefie`, `trabajo/odoo/`.

## De dónde sale cada valor en Truefie

| Truefie | Odoo |
|---|---|
| `ent_odoo_pendiente` id 26, `tipo = 'traslado_interno'` | un `stock.picking` interno |
| `ent_pedido.id` = 145 (`origen = 'manual'`, `motivo = 'regalia'`) | `origin = 'Truefie pedido 145'` ← **la llave para emparejar** |
| `ent_pedido.fecha_despacho` = 2026-09-23 | `scheduled_date` = 2026-09-23 (la hora sale del reloj al crear: 22:10 UTC = 16:10 CR) |
| `ent_odoo_pendiente.destinatario` (texto libre) | `partner_id`: un contacto de Odoo elegido a mano. Hoy **994 «Influencers»** para influencers; «Andrea Fernandez», «Lorena Madrid» para consumo interno. No hay regla escrita |
| `ent_odoo_pendiente_linea`: `producto_id`, `cant_uds`, `uom_factor` | una `stock.move` por producto: `product_uom_qty = cant_uds × uom_factor`, en la UoM de stock del producto |
| `ent_odoo_pendiente_linea.lote` | **no va a Odoo**: los seis terminados tienen `tracking = none`, `lot_id` queda vacío |
| «Hecho» en Pendientes → `ent_odoo_hecho` | `referencia` quedó **vacía**: la pantalla no la pide. Debería guardar `WH/INT/00145` |

## El traslado (cabecera)

| Campo | Valor |
|---|---|
| `picking_type_id` | **5** · «True Food: Traslados internos» (secuencia `INT`) |
| `location_id` | **8** · `WH/Stock` |
| `location_dest_id` | **19** · `Virtual Locations/Mercadeo y Muestras` (`usage = inventory`) |
| `origin` | `Truefie pedido <id>` |
| `partner_id` | el contacto del destinatario (ver arriba) |
| `move_type` | `direct` |
| `note` | vacía (los lotes se pueden dejar acá como texto; esta vez no se hizo) |
| `backorder_id` | ninguno |
| `state` al terminar | `done` |

## Las líneas (una `stock.move` por producto)

Cantidad y UoM **por id**, nunca por nombre (CLAUDE.md). Para el pedido 145:

| producto_id | Producto | `product_uom_qty` | `product_uom` |
|---|---|---|---|
| 451 | Pan Blanco | 1 | 1 · Unidades |
| 452 | Pan de Semillas | 1 | 1 · Unidades |
| 453 | Pan Francés | 1 | 37 · Paquete de 4 |
| 503 | Buns | 1 | 37 · Paquete de 4 |
| 472 | Pizza Crust | 1 | 38 · Paquete de 2 |
| 519 | Cookie Dough | 1 | 1 · Unidades |

En todas: `quantity = product_uom_qty`, `picked = true`, `state = done`,
origen 8 → destino 19. Una `stock.move.line` por movimiento, sin lote.
⚠️ El `name` de la línea sale de la descripción del producto y **no** es el
nombre: Buns dice «Hamburguesas 75 buns» y Cookie Dough dice «Prueba Galletas».
No leerlo.

## Lo que hace Odoo al validar (medido sobre este traslado)

- **Un asiento por producto** (6), diario de valoración de stock, `ref` =
  `WH/INT/00145 - <producto>`, estado `posted`.
- Cada uno: **Debe 6106008 Gastos de Mercadeo y Ventas / Haber 1103020
  Inventario de Producto final**, por el costo del producto. Las cuentas salen
  de la ubicación 19 (`valuation_in/out_account_id` = 6106008).
- **La fecha del asiento es la del día en que se VALIDA** (27-sep), no la de la
  salida (23-sep). Mismo comportamiento que las salidas con factura.
- Uno trajo `Rounding Adjustment: +0.01 ₡` en la `ref`.

## Para la versión automática

1. Leer la cola `v_ent_odoo_pendiente` (tipo `traslado_interno`) y sus líneas.
2. Armar el picking con los valores de arriba. `origin = 'Truefie pedido <id>'`
   es obligatorio: sin eso no se empareja.
3. El contacto NO sale de Truefie (el destinatario es texto libre): hace falta
   una tabla de equivalencias o que alguien lo elija.
4. Validar, y guardar en `ent_odoo_hecho.referencia` el `name` que asignó Odoo.
5. Antes de crear: buscar si ya existe un picking con ese `origin` (idempotencia).
6. Un traslado por pedido. El 27-sep `WH/INT/00144` juntó los pedidos 143 y 144
   en uno solo: a mano se puede, pero rompe el emparejamiento uno a uno.

## El contacto · decisión de Andrea (27-sep-2026)

**Truefie CREA el contacto en Odoo si no existe**, porque Daniel no sabe
clasificar al destinatario. Con tres cuidados:

a) **Mientras Daniel escribe, Truefie sugiere los contactos que ya existen.** Si
   elige uno, no se crea nada. (Lectura: `res.partner` `name_search`, ya dentro
   de `LECTURA_OK`.)
b) **Los contactos nuevos nacen con la etiqueta «Creado por Truefie» y sin marca
   de cliente**, para que no aparezcan al facturar.
c) **El usuario automático solo puede CREAR contactos**, nunca editarlos ni
   borrarlos.

### Medido en solo lectura el 27-sep (uid 28)

- **La etiqueta «Creado por Truefie» NO existe.** `res.partner.category` tiene
  una sola etiqueta en toda la base, y ninguna con "truefie". Hay que crearla una
  vez, a mano (Contactos → Configuración → Etiquetas), antes de construir.
- **"Marca de cliente" en Odoo 17 = `customer_rank`** (entero; Odoo lo sube solo
  cada vez que se le factura a ese contacto). Hoy: 371 contactos activos, 155 con
  `customer_rank > 0`, 216 en 0. «Influencers» (994) está en 0.
- ⚠️ **`customer_rank = 0` NO ALCANZA para que no aparezca al facturar.** El
  campo cliente de la factura (`account.move.partner_id`) y del pedido de venta
  (`sale.order.partner_id`) solo filtran por compañía (medido con `fields_get`),
  y `name_search` en modo cliente (`res_partner_search_mode = 'customer'`, el que
  usa ese campo) **devuelve «Influencers» escribiendo "Influ"** aunque su rank
  sea 0. El rank solo ordena y alimenta el filtro por defecto del menú Clientes.
- **Lo que sí lo saca de todas las listas: crearlo ARCHIVADO (`active = false`).**
  Un contacto archivado no sale en ningún buscador, y un traslado ya creado con
  él sigue siendo válido. Se pasa en el mismo `create`, así que no choca con (c):
  no hace falta editarlo después. Para la sugerencia de (a), Truefie busca
  incluyendo archivados (`active_test: false`) y así reusa los que creó antes.
  **Pendiente de decisión de Andrea:** archivado sí o no.
- No se pudo medir con el usuario de lectura: la acción del menú Clientes
  (`ir.actions.act_window`, acceso denegado) ni los permisos de creación.

### El permiso para (c)

El usuario automático necesita `create` en `res.partner` y **nada** de `write`
ni `unlink` sobre ese modelo. En Odoo las ACL son por modelo y por operación, así
que se puede dar `create` sin `write`. ⚠️ Pero el grupo "Contactos / Creación" y
los grupos de Ventas o Inventario suelen traer `write` también: hay que armar un
grupo propio y medirlo con `check_access_rights` (como `diagnostico_permisos.py`)
antes de encenderlo. No medido todavía: hace falta el usuario nuevo.
