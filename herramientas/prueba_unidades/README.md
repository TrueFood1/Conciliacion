# Prueba de la deteccion de unidad equivocada

Corre `uomBarrerFacturas()` de verdad contra un Odoo de mentira alimentado con
**las 1.444 lineas reales de facturas de 2026**. Sin fixtures escritos a mano.

## Como se corre

    python3 herramientas/prueba_unidades/traer_datos.py   # baja de Odoo, solo lectura
    herramientas/prueba_unidades/correr.sh

## Las dos fotos

`traer_datos.py` baja el mismo juego de lineas dos veces:

- **hoy** — el estado actual. La 3534 y la 3544 ya estan revertidas por sus notas
  de credito del 22-sep, asi que el detector NO tiene que marcarlas: una factura
  anulada no cobra nada y avisar sobre ella es ruido sobre un documento muerto.
- **antes** — la misma base ignorando esas dos NC, o sea como estaba el dia que
  salieron. Ahi las cuatro tienen que aparecer. Es la prueba de que el detector
  las habria cazado el mismo dia, que era el pedido.

## Que comprueba

| | hoy | antes |
|---|---|---|
| marca | 3385, 3504 | 3385, 3504, 3534, 3544 |
| no marca | 3546, 3547, 3507, 3130, 3424, 3543, 3545 | idem |
| ninguna otra de las 512 / 514 | ✓ | ✓ |

La 3547 esta en la lista de "no marcar" a proposito: dice `4 × Caja [46]` = 24 u
y esta BIEN facturada. La emitimos asi el 22-sep porque Odoo no deja poner `[42]`
en un pedido confirmado (`product_uom_readonly`), y esa forma se va a repetir
cada vez que se corrija una factura vieja. El escape de "cajas enteras" existe
por eso — y no tapa ninguno de los cuatro errores, porque 6 de 24 no es una caja
entera y 6 de 12 tampoco.

## Lo que NO cubre

- No prueba la creacion del ticket: eso escribe en produccion.
- El Odoo de mentira respeta la proyeccion (si el codigo pide un campo que los
  datos no traen, revienta diciendo cual). Ya cazo uno: `move_type`.

## datos.json

Gitignored: son facturas reales con razones sociales y el repo es publico.
