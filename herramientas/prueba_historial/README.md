# Prueba del Historial de Entregas

Prueba la pantalla **con la lectura real**, no con datos inventados a mano.

## Por que existe

b63 salio con «Sale otro dia» roto —el `.select()` no pedia `salida_id`— y la
prueba de pantalla no lo agarro porque usaba un fixture escrito a mano: el
fixture traia el campo que la lectura real no traia. El que escribe el fixture
es el mismo que escribio el `select`, asi que repite el olvido en los dos lados.

Aca el cliente de mentira **respeta la proyeccion**: si el codigo no pide una
columna en su `.select()`, no la recibe — y si la usa igual, la prueba revienta
diciendo que columna falta. Ya cazo una: `salida_id`.

## Como se corre

    python3 herramientas/prueba_historial/traer_datos.py   # baja filas reales (solo lectura)
    herramientas/prueba_historial/correr.sh

`traer_datos.py` entra por `pg_lector.py`, que envuelve todo en
`BEGIN TRANSACTION READ ONLY`. No escribe nada.

## Que hace

1. **Recorta** las funciones de `index.html` tal cual estan — no las reescribe.
   Si una falta, lo dice en `FALTAN` en vez de seguir como si nada.
2. Corre `bsLeer()` de verdad contra el PostgREST de mentira.
3. Renderiza `bsDetalle()` de cada pedido y compara contra lo esperado.
4. **Repite todo contra `main`.** Si las assertions nuevas pasaran tambien alla,
   la prueba no estaria midiendo el cambio.

## Los casos

| pedido | por que esta |
|---|---|
| 67  | el corregido (3534 -> 3546): unidad, quien preparo, linea de correccion |
| 134 | el gemelo SIN corregir — control, y la unidad nueva delata su error |
| 66  | los seis productos, para ejercitar cada envase |
| 55  | cinco productos, uno sin lote |
| 135 | preparado sin salida |

## Lo que NO cubre

- `bsDeshacerHTML` esta stubbeado en `''`: no esta bajo prueba aca (es de b64) y
  ninguna assertion lo mira.
- `bsEnriquecerFacturas` lee Odoo y no entra: se verifica aparte, corriendo su
  misma logica contra Odoo real.
- Esto NO reemplaza abrir la pantalla en el aparato. Prueba el armado del HTML,
  no que se vea bien (la leccion de b32).

## datos.json

Gitignored a proposito: son entregas reales con razones sociales de clientes y
el repo es publico. Se vuelve a bajar con `traer_datos.py` cuando haga falta.
