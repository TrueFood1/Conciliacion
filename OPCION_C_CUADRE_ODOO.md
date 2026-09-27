# Opción C · El cuadre Truefie ↔ Odoo (diseño para construir)

**27-sep-2026 · PROPUESTA, sin construir.** Sale del relevamiento del mismo día
(`DIAGNOSTICO_ESCRITURA_ODOO_27SEP.md`, recomendación "C ahora, B después").

**Qué es:** Truefie deja de suponer que lo que marcó "Hecho" está bien en Odoo y
**lee el estado real de cada salida** (y de cada traslado interno) por el proxy
de lectura, y muestra dónde los dos registros no dicen lo mismo.
**No escribe en Odoo. No cuesta licencia. No abre ninguna puerta nueva.** Usa
métodos que ya están en `LECTURA_OK` (`search_read`, `read`).

## Lo que mostraría HOY (medido el 27-sep)

| # | Caso | Regla | Hoy | Qué hay que hacer |
|---|---|---|---|---|
| 1 | **Preparado en Truefie, validado en Odoo** | pedido `preparado` y su salida `done` | **pedidos 140, 141 y 142** (Odoo los validó el 24-sep 20:15 CR = 25-sep 02:15 UTC) | Confirmar si salieron y registrar la salida en Truefie **con la fecha real**, no la de Odoo |
| 2 | **Salida sin validar en Odoo** | salida `assigned` de un pedido de Truefie | **`WH/OUT/02378` ↔ pedido 135**, sin validar desde el 21-sep; en Truefie `preparado` desde el 21-sep 09:56 CR | Si salió: registrar en Truefie y validar en Odoo. Si no: decidir |
| 3 | **Entregado en Truefie, cancelado en Odoo** | pedido `entregado` y su salida `cancel` (y ninguna otra `done` que lo cubra) | **pedido 11** (19-ago) | Decisión contable (pregunta 3 a la contadora): ajuste de inventario o dejarlo |
| 4 | **Cantidad distinta** | por producto: lo que salió en Truefie (alisto vigente) ≠ lo que Odoo descontó (suma de `stock.move.product_qty` `done` de TODAS las salidas del pedido), en unidades base | **0** de 68 | Ver cuál de los dos está mal |
| 5 | **La factura del pedido está revertida** | la factura vigente de Truefie tiene NC / `reversal_move_id` | **pedido 67** (la re-factura existe y no se vinculó) | Re-vincular el pedido a la factura nueva |
| 6 | **Traslado interno sin emparejar** | pedido sin factura con su pendiente "Hecho" y **ningún** traslado con `origin = 'Truefie pedido <id>'` | solo cuenta **desde el 27-sep** (ver abajo); hoy **0** (el 145 empareja con `WH/INT/00145`) | Poner el número en Odoo o en Truefie |
| — | Consigna / excepción aceptada | una socia ya decidió que está bien así | **pedido 68** | Nada: no se muestra |

**Por qué el 6 arranca el 27-sep:** los 9 traslados anteriores no tienen
`Documento origen` y no hay forma honesta de emparejarlos (el 00144 además junta
dos pedidos). Mostrarlos sería una alarma que suena siempre. Constante con fecha
y razón escrita, como `DESP_DESDE`.

## Dónde y para quién

- **Entregas → Pendientes**, sección nueva **"Cuadre con Odoo"**, al lado de
  "Traslados internos por crear". **Solo socias** (igual que esa tarjeta).
- Cumple las **5 reglas de alerta**:
  1. aparece **solo si hay algo que hacer** (sin casos, la sección no existe);
  2. **con fecha**: la del caso más viejo;
  3. **se apaga sola** cuando el dato cambia (no hay "marcar visto");
  4. máximo 3 visibles, "y N más";
  5. **ámbar** solo lo que vence: caso 1 (el inventario ya está mal hoy) y
     caso 2 con más de 2 días. El resto en gris.
- Una tarjeta por caso, con el pedido, el número de Odoo (`WH/OUT/…`,
  `WH/INT/…`) y qué dice cada lado. En unidad de venta.

## Cómo lee (la cadena ya existe, no se inventa)

`despYaEntregado` (index.html ~l. 10343) ya sigue **factura → `account.move.line.sale_line_ids`
→ `sale.order.line.order_id` → `sale.order.picking_ids` → `stock.picking`**, por
ID y nunca por el texto de `invoice_origin`. La opción C usa la misma cadena
para los pedidos de Truefie con factura, y agrega:

- `stock.picking`: `state`, `name`, `scheduled_date`, `date_done`, `picking_type_code`;
- `stock.move` de esas salidas: `product_id`, `product_qty` (unidad base), `state`;
- `account.move` de la factura: `reversal_move_id`, `state`;
- traslados: `stock.picking` interno con `origin like 'Truefie pedido %'`.

**Una sola función**, `entOdooSalidas(facturaIds)`, devuelve todo eso por
factura. 🔴 La regla del CLAUDE.md dice que la segunda copia de una lectura se
desincroniza, así que `despYaEntregado` tiene que terminar usando la misma. Para
no tocar lógica probada en el primer paso: C1 la escribe al lado, C3 hace que
`despYaEntregado` la use **y se mide que dé lo mismo** sobre las facturas de 2026.

**Si Odoo no contesta**, la sección lo dice ("no pude leer Odoo, el cuadre no
está al día") y nunca se muestra como "todo cuadra".

## El oráculo: `herramientas/cuadre_odoo.py`

Script de solo lectura (Odoo con `odoo_read.py`, Supabase con `pg_lector`) que
calcula **los mismos casos** por su cuenta. Sirve para dos cosas:
- verificar la pantalla contra algo que no salió del mismo código (hoy tiene que
  dar exactamente la tabla de arriba);
- ser, después, el corazón de la opción B (el lote nocturno solo validaría lo
  que el oráculo dice que calza).

## Por pasos

| Paso | Qué | Toca la base | Publica |
|---|---|---|---|
| **C1** | `entOdooSalidas` + oráculo + sección con los casos 1 a 5 | no | sí (build) |
| **C2** | tabla `ent_cuadre_aceptado` (append-only, socias, con motivo) para sacar excepciones como la consigna; y **"Hecho" pide el número del traslado** (`ent_odoo_hecho.referencia`, que existe y hoy queda vacía) + caso 6 | sí (pegado con ensayo) | sí |
| **C3** | el **descuadre** (`_entColgarDetalle`) compara contra la demanda viva de la salida y no contra la foto de la factura (saca los falsos del 67 y el 134); `despYaEntregado` usa `entOdooSalidas` | no | sí |

Sin C2, el pedido 68 (consigna) aparecería en la sección hasta que exista la
tabla. Se puede arrancar con C1 igual: son 5 tarjetas reales y 1 conocida.

## Lo que NO hace

- No valida nada en Odoo ni crea traslados (eso es B o A, más adelante).
- No corrige el inventario de Odoo (el pedido 11 y la 3385 son decisión contable).
- No mira facturas que no están en Truefie (ya lo hace Despachos al leer la bandeja).

## Decisiones que necesito de Andrea antes de construir

1. ¿Sección en **Pendientes** (socias) o además un contador en el lobby?
2. ¿El caso 1 (preparado en Truefie, validado en Odoo) es **ámbar**?
3. ¿Arrancamos por **C1 solo**, o C1 + C2 juntos (con pegado)?
4. Fecha de corte del caso 6: **27-sep** (el primer traslado con número).
