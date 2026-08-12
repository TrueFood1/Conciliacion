# Entregas — pendientes anotados, no resueltos

## Hueco de trazabilidad · orden WH/MO/01330

**Qué pasó.** La orden de producción `WH/MO/01330` (Galletas, terminada el
13-jun-2026, 160 unidades) **no tiene lote**. El extractor lo detecta y lo deja
explícito en el balde `sin_lote` — nunca lo asume.

**Por qué importa.** Hoy la trazabilidad por lote de True Food depende de que
Keylor escriba el lote a mano en el chatter de la orden. Funciona —49 de 50
órdenes de los últimos 3 meses lo traen bien— pero es frágil: si no lo escribe,
ese lote no existe para nadie. Odoo no lo respalda: los seis productos terminados
tienen `tracking = none` y los 1.604 movimientos de 2026 no llevan `lot_id`.

**Quién lo resuelve.** Andrea con Keylor. No es cosa de código: hay 160 unidades
de galletas producidas el 13-jun que no se pueden rastrear.

**Qué hace el módulo mientras tanto.** Nada de adivinar. La orden aparece en la
lista de casos sin lote, visible, para que se resuelva o se acepte como hueco
conocido.

---

## Trazabilidad: lo frágil que el módulo convierte en estructura

Vale dejarlo escrito porque es el argumento del módulo entero: hoy el lote es
texto libre en un comentario, y lo que sale del congelador no queda ligado a
ningún lote en ningún sistema. El módulo no arregla Odoo —sigue siendo solo
lectura— pero convierte las dos puntas en dato estructurado: qué lote se fabricó
(extractor) y qué lote salió (`ent_alisto_lote`). A partir del 17-ago eso deja de
vivir solo en el Excel de Daniel.
