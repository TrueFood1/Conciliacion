# Exportación del Historial de Entregas — especificación

**Estado: DECIDIDO, SIN CONSTRUIR.** Se construye en el punto 3 de la cola, en la
misma pasada que el Bloque 4 + 3.2/3.3 — la columna "motivo de excepción" depende
de campos que todavía no existen. **No abrir el exportador dos veces.**

Un solo molde, dos salidas: Excel y PDF con la misma disposición, para que no se
desincronicen.

---

## Las columnas

`fecha` · `cliente` · `factura` · `pedido` · `producto` · `cantidad` · `unidad` ·
`lote` · `motivo de excepción`

**No va "quién preparó"** (decisión de Andrea).

Una fila por **lote**, no por pedido: es el nivel al que se responde una pregunta
de trazabilidad. Un producto repartido entre dos lotes son dos filas.

### Cantidad y unidad

**Siempre en unidad de venta.** Paquetes para Francés, Buns y Pizza; unidades
para Blanco, Semillas y Galletas.

⚠️ **La unidad NO se toma de `uom_nombre`.** Ese campo es la UoM de Odoo, la que
llama **"Dozens"** a un paquete de 4 — leerlo pondría "Dozens" en una columna que
tiene que decir "paquetes". La conversión sale de `NIV_INFO[pid].presDiv` (4/4/2),
que es la misma tabla que usa `_lotUds`.

### Las líneas con excepción SÍ salen

Con su motivo en columna propia. **No se esconden.** Si se escondieran, el Excel
no cuadraría contra la factura — y de cara a BRC, esconder una excepción es peor
que mostrarla.

Son dos motivos distintos y la columna tiene que distinguirlos, porque significan
cosas opuestas para el saldo:

| Lo que dice la columna | Qué pasó | ¿el pan salió del congelador? |
|---|---|---|
| `sin lote imputado · <motivo>` | salió y no se sabe de qué lote | **sí** |
| `no se entrega · <motivo>` | no salió | **no** |

---

## Los filtros

La pantalla **no** puede combinar filtros (sus cuatro chips son excluyentes y se
borran entre sí). **El exportador sí puede**, y esa es una decisión deliberada:
son dos herramientas con dos preguntas distintas.

| filtro | ¿va? | por qué |
|---|---|---|
| **cliente + rango de fechas** | **obligatorio** | es la combinación que Andrea va a usar siempre |
| **lote** | **sí** | es *la* pregunta de un retiro: "¿a dónde fue todo lo del lote 208?". Con BRC Start en proceso, es el filtro que justifica el archivo |
| **producto** | sí, como conveniencia | los datos ya están en la fila, no abre ningún camino nuevo |

**Rango de fechas, no día suelto.** La pantalla filtra un día exacto porque su
campo es un `<input type="date">`; un archivo que va a una auditoría se pide por
mes o por semana.

### ⚠️ Filtrar por lote NO recorta el pedido

Si se filtra por lote (o por producto), se eligen los **pedidos** que lo
contienen y se exporta **el pedido completo**, con una columna que marca qué
líneas calzaron con el filtro.

El motivo es el mismo por el que las excepciones no se esconden: un Excel con
media factura no cuadra contra la factura. La pregunta "¿a dónde fue el lote
208?" se contesta con la columna de coincidencia; la pregunta "¿esto cuadra?" se
contesta con las filas completas. Recortar las líneas hermanas contestaría la
primera y rompería la segunda.

---

## Lo que el archivo tiene que decir de sí mismo

En una cabecera del Excel y en la primera página del PDF. **Esto no contradice la
regla de "sin explicaciones en pantalla"**: esa regla es para pantallas, y esto es
un papel que alguien va a leer sin tener el sistema delante — posiblemente un
auditor, posiblemente dentro de un año.

- **Los filtros aplicados**, con sus valores.
- **Cuándo se exportó** y **quién** lo exportó.
- **Las dos definiciones que no se pueden adivinar:**
  - **"Cliente"** no es solo `cliente_nombre`: también busca el **motivo**
    (Regalía, Reposición, Consumo interno…) y el **destinatario**. Una salida sin
    cliente no tiene nombre que esconder, tiene un motivo.
  - **"Fecha"** no es la fecha del pedido. Es `fecha_ab_re_04` =
    `coalesce(salida_en, fecha_despacho)`: la salida real cuando la hubo, y la
    fecha del pedido para lo que se preparó y todavía no salió.

Quien lea el archivo sin saber estas dos cosas saca conclusiones equivocadas, y
ninguna de las dos se deduce mirando las columnas.

---

## Sin techo silencioso

**El exportador consulta aparte, sin el `.limit(300)` de `bsLeer()`.** Trae todo
lo que el filtro pida. Un Excel que corta en silencio es peor que no tener
exportación, y más aún si va a una auditoría de BRC.

El tope de la pantalla es un problema propio y tiene su pendiente aparte:
`ENTREGAS_PENDIENTES.md` §16. **No se arreglan juntos**: son dos piezas distintas
y mezclarlas haría que un arreglo de pantalla viajara escondido dentro del
exportador.

---

## Los nombres

`exportarHistorial()` **ya existe** (`index.html:17662`) y es del *Historial de
conteos* de Inventario. No se toca.

El módulo ya resuelve esto con prefijos: lo compartido de Entregas lleva `ent`
(`entLotesUnion`, `entPdfBtn`), y lo propio de una pantalla lleva el prefijo de la
pantalla (`bsFiltrar`, `bsRender`, `despRender`). La exportación es propia del
Historial, así que:

```
bsExportar()          el gesto: abre el diálogo de filtros
bsExportModelo()      EL MOLDE: arma cabecera + filas UNA vez
bsExportarXLSX()      pinta el molde como hoja
bsExportarPDF()       pinta el mismo molde como papel
```

`bsExportModelo()` es la pieza que hace verdad "un solo molde": las dos salidas no
pueden desincronizarse si ninguna de las dos arma sus propias filas.

---

## El PDF: hoja de impresión, decidido

**DECIDIDO el 10-sep-2026: opción A — hoja de impresión + `window.print()`.**

El motivo, y es el que manda: **Truefie hoy no depende de ninguna librería
externa**, y esa limpieza vale más que ahorrarle un paso al usuario. Una librería
de PDF por CDN daría el archivo de una vez, pero mete una dependencia que la
herramienta no tiene en ningún otro lado.

Encaja además con el molde único: `bsExportModelo()` arma las filas, se dibujan
como HTML una sola vez, y la hoja de impresión es una capa de CSS sobre ese mismo
HTML. No hay un segundo renderizador que se pueda desincronizar.

### Cuándo se revisa

**Si el diálogo de impresión resulta insoportable en el iPad de Daniel, se cambia
a librería por CDN — con evidencia medida, no por suposición.** Esto no es una
puerta abierta a cambiar de idea: es una condición con un hecho detrás. Hay que
poder decir qué pasó al intentarlo, en el aparato.

Lo concreto a medir, cuando se construya, **en el iPad y desde el ícono** (no en
Safari de escritorio, que es donde todo funciona):

- que `window.print()` haga algo desde el modo standalone;
- cuántos toques hay entre el botón y un PDF guardado;
- que la tabla no salga cortada a lo ancho.

Es el mismo aparato que ya sorprendió una vez reteniendo una versión vieja: lo
que valga en la Mac no dice nada de lo que va a pasar ahí.

### Lo que arrastra la decisión

`window.print()` imprime **la página entera**, no un elemento. Así que la hoja de
impresión tiene que esconder todo lo demás —encabezado, caras, filtros, botón
flotante— y dejar solo la cabecera del archivo y la tabla. Es CSS, no lógica,
pero hay que escribirlo: sin eso el PDF sale con la barra de navegación adentro.
