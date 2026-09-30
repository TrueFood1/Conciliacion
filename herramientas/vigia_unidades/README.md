# Vigia de unidades en facturas

Revisa todos los dias que ninguna factura use una unidad que no le corresponde
al producto, y abre un ticket en Finanzas cuando encuentra una.

## Donde vive cada cosa

| | donde | por que |
|---|---|---|
| La regla (`UOM_OK`) | `index.html`, repo publico | es la MISMA que usa la app; una sola definicion |
| `revisar_unidades.py` | aca, repo publico | no lleva ninguna credencial |
| El workflow | repo **privado** `respaldo-truefie` | ahi viven los secrets |
| Los secrets | repo **privado** | credencial de escritura a la base |

`revisar-unidades.yml` esta aca solo como **plantilla para copiar** al repo
privado. No corre desde este repo.

## La regla no se duplica

El script **recorta** `UOM_OK` y `NIV_INFO` de `index.html` con una expresion
regular, y se cae ruidosamente si no las encuentra. Escribir la tabla dos veces
—una en JS y otra en Python— es el modo de falla favorito de este repo:
coinciden hasta el dia que alguien toca una.

## La credencial, con el minimo

El rol `truefie_vigia` (lo crea `PEGADO_VIGIA_UNIDADES.sql`) puede **SELECT e
INSERT sobre `ticket` y `revision_unidades`, y nada mas**. Medido: no hay ni un
grant a PUBLIC en el esquema, asi que un rol nuevo arranca sin poder tocar nada.
No puede leer entregas, ni clientes, ni lotes, ni borrar nada.

Para Odoo usa el mismo usuario de solo lectura que ya usa el proxy.

## La ventana: 30 dias

Medido contra produccion:

| ventana | facturas vivas | con problema |
|---|---|---|
| 30 dias | 56 | 1 |
| 120 dias | 233 | 2 |
| 400 dias | 800 | **8** |

Los 30 dias son para la corrida diaria: alcanza de sobra para cazar una factura
el dia que sale. La ventana larga destapa un atraso historico de 2025 — seis
casos mas (2949, 2893, 2845, 2844, 2843, 2741) — que conviene mirar UNA vez a
mano y no que aparezcan de golpe como ocho tickets el primer dia.

    python3 revisar_unidades.py --index ../../index.html --dias 400 --seco

`--seco` no escribe nada: solo imprime lo que haria.

## Sin duplicados

Antes de crear un ticket busca uno que ya nombre esa factura. Si existe, no crea
otro. Por eso el texto empieza SIEMPRE con `Factura <4 digitos> ·`.

## La bitacora

Cada corrida deja una fila en `revision_unidades`, **haya o no hallazgos**. Sin
la fila de "no encontre nada" no se distingue "todo limpio" de "no corrio", que
son estados opuestos y se ven igual. La pantalla de Tickets muestra la ultima, y
la pone en rojo si paso mas de un dia.
