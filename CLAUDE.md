# Conciliación / Truefie — instrucciones del repo

Truefie: herramienta web de True Food CR (todo en `index.html`) sobre Odoo 17.
Módulos: Finanzas (facturado, costos, rentabilidad, calculadora de precios),
Operaciones (producción, mermas, inventario M7), Conciliación bancaria (BAC)
y Simulador. Acá vive solo lo ESTABLE; el estado de avance vive en `BITACORA.md`
(leerla al arrancar sesión).

## Reglas madre (aplican siempre)

- **Producción es SOLO LECTURA.** Candado de 3 capas: allowlist deny-by-default
  en `odooRpc` + Conciliación bloqueada en prod + banner "⚠ PRODUCCIÓN · solo
  lectura". Nunca debilitarlo ni rodearlo.
- **Diagnosticar antes de arreglar**: ante números raros, primero lectura
  read-only (árbol de MP, script de diagnóstico), después el fix. No adivinar.
- **Validar contra la fuente**: todo número nuevo se cruza contra el pivot
  nativo de Odoo o el Excel de Andrea antes de darse por bueno. La dirección de
  una conversión de UoM (× o ÷ factor) se verifica con un dato real conocido.
- **Cambios visuales no tocan lógica probada**: conservar ids/handlers,
  revalidar sintaxis al final. Al cambiar ids de contenedores, buscar TODOS los
  `getElementById` que los referencian.
- **Antes de publicar, correr `python3 loadcheck.py`**: ejecuta el bloque JS de
  arriba a abajo con un DOM de mentira y falla si algo revienta AL CARGAR.
  Validar sintaxis no alcanza — un `const` usado antes de declararse parsea
  perfecto y mata el bloque entero en el navegador (pasó el 11-ago con el bloque
  de vainilla, y salió publicado). Sintaxis OK ≠ la página carga.
- **Credenciales nunca por el chat** ni impresas en output: van directo a
  `conexion_prod.env`; confirmar presencia con sí/no, sin mostrar la key.
- Explicar en español simple; reportar con evidencia (números, no adjetivos).

## Cierre de sesión (regla fija)

Al cierre de **toda sesión donde se tocó código**, correr el checklist de
[`CIERRE_TECNICO.md`](CIERRE_TECNICO.md) **sin que haya que pedirlo**.

- El **push va a `dev`** (respaldo, siempre).
- A **`main`** solo con **decisión explícita de Andrea** (`main` sirve la versión publicada por GitHub Pages).

## Seguridad

- El repo es **público**. Nunca commitear credenciales, tokens ni datos bancarios/personales.
- `conexion_prod.env`, `.proxy_token`, el extracto bancario (`*.xls`, `extracto_limpio.csv/.js`) y `proxy_lectura/` (repo propio) están en `.gitignore` — mantenerlos ahí.

## Entorno y datos fijos

- Local: `python3 -m http.server 8765` → probar en **Safari**
  (`http://127.0.0.1:8765/index.html`, recarga Cmd+Shift+R). El Chrome
  corporativo bloquea localhost ("Access denied" no es un bug de la herramienta).
- Odoo producción: `truefood.odoo.com` · DB en `conexion_prod.env` (privado, no
  se publica) · vía proxy de lectura. Odoo demo/staging: el nombre de la DB cambia cuando Odoo
  regenera el staging (sufijo numérico); "database not found" = pedir el nombre
  actual, no es error de la herramienta.
- Proxies en Render:
  - `truefood-proxy-lectura.onrender.com` — PRODUCCIÓN, Node (`server.js`),
    valida JWT de Supabase con **ES256 vía JWKS** (no HS256).
  - `truefood-proxy.onrender.com/proxy` — DEMO (viejo, puerta web con
    usuario+contraseña; **rechaza API keys**).
- Supabase (proyecto `tomijkqnmpjcraaoeviq.supabase.co`): login del sistema +
  historial de conteos (tabla con RLS). El anon key es público por diseño.
- Publicación: GitHub Pages sirve `main` → `truefood1.github.io/Conciliacion/`.
  Actualizar la constante `BUILD` (inicio del bloque JS) en cada publicación.
- Consultas Python: `odoo_read.py` + paquete `tf/` (`productos.py`,
  `clientes.py`, `odoo.py`).

## Odoo — trampas conocidas (leer antes de consultar)

- **Ventas**: cada línea de venta genera 2 líneas extra de COGS en
  `account.move.line` (mismo producto y cantidad) → filtrar
  `display_type='product'` o las ventas salen infladas 3×.
- **Facturado por canal**: usar `amount_total` (con IVA). El canal de venta
  está en el cliente (`res.partner.team_id`), NO en `account.move`.
- **Producción y mermas**: filtrar por `date_finished` (calza con el pivot
  nativo de Odoo), no `date_start`.
- **Despachos**: la fecha real es `scheduled_date`; `date_done` es cuando se
  validó en el sistema (llega 3–7 días tarde).
- **Nombres traducidos** (es_CR / en_US): una consulta sin contexto de idioma
  devuelve el nombre en inglés. Trampa mayor: **517 ("Premezcla Galletas") y
  519 ("Cookie Dough") COMPARTEN el nombre en inglés "Prueba Galletas"**.
  Buscar productos por **ID, nunca por nombre**, y cuidado con filtros de
  exclusión tipo `/prueba/`: casi ocultan a Cookie Dough.
- **Pizza**: por nombre se confunde "Pizza Crust" [472] con
  "Premezcla Pizza Crust" [473].
- **Extracto BAC**: la referencia NO es única → llave anti-duplicado =
  fecha + referencia + monto. Los cobros vienen "TEF DE: <nombre cliente>"
  sin número de factura.
- **Clientes**: alias comercial ≠ razón social en Odoo (un mismo café puede
  aparecer con un alias distinto de su S.A.). Fuente de verdad: `tf/clientes_dict.json`
  (gitignored: partner_id + flag verificado; las razones sociales viven ahí, no acá).
  Ojo: alias muy parecidos pueden ser clientes DISTINTOS, y algunos alias no
  están registrados en Odoo. (Ejemplos concretos: ver documento privado.)
- **Fechas**: convertir a hora CR (UTC−6) antes de agrupar por día/mes.
- **UoM — NUNCA leer el nombre, SIEMPRE el id** (regla hermana de "buscar
  productos por ID, nunca por nombre"). Dos pares distintos **comparten nombre en
  inglés**, y en español no: `Paquete de 4` [37] y `Docenas` [2] se muestran los
  dos como **"Dozens"** (4 u vs 12 u), y `Caja` [46] y `Caja (Hamburguesa)` [42]
  se muestran los dos como **"Caja"** (6 u vs 24 u). Siempre
  `product_uom_id` → `factor`, y `1 unidad de esa UoM = 1/factor unidades base`.
  Ejemplo real (factura de Abner, 13-ago-2026): "Buns · 9,00 **Dozens**" son
  **36 unidades, no 108** — la línea usa `Paquete de 4`, que en inglés se
  muestra "Dozens". Leer el nombre descuenta el triple. Al revés pasa en la
  factura de Automercado: "Caja (Hamburguesa)" se muestra "Caja" en inglés, y
  leerlo así da 6 u donde son 24.
  Factores verificados (11-ago-2026): Unidades 1 · Paquete de 2 = 2 ·
  Caja PQ 4 = 3 · Paquete de 4 = 4 · Caja = 6 · Caja (Pizza) = 12 ·
  Paquete de 12 = 12 · Docenas = 12 · Caja (Frances) = 24 · Caja (Hamburguesa) = 24.
- **UoM**: `stock.quant` devuelve la UoM por defecto del producto (paquetes
  para Francés/Buns/Pizza). "Dozens" en esta instancia vale 4, no 12
  (cosmético al facturar Buns/Francés). `standard_price` es por kg/L; las
  recetas vienen en g/mL → convertir SIEMPRE antes de multiplicar.

## Reglas del negocio (validadas contra Odoo, julio 2026)

Productos terminados (IDs de producción):

| Producto | ID | UoM stock | Caja física | Batch (BoM) |
|---|---|---|---|---|
| Pan Blanco | 451 | Units | 6 u | 21 u |
| Pan Semillas | 452 | Units | 6 u | 21 u |
| Pan Francés | 453 | Paquete de 4 | 6 paq = 24 u | 60 u |
| Buns | 503 | Paquete de 4 | 6 paq = 24 u | 75 u |
| Pizza | 472 | Paquete de 2 | 6 paq = 12 u | 20 u |
| Galletas (Cookie Dough) | 519 | Units | 12 potes | 160 u |

- **Batch = la receta base del BoM, NO una orden de producción.** Un MO puede
  ser varios batches: batches = unidades ÷ tamaño de batch (Blanco 63 = 3×21).
  Los batches/día son variables — no asumir una capacidad fija.
- **Premezclas** (1 unidad Odoo = 1 batch): Blanco [468] · Semillas [469] ·
  Francés [470] · Buns [502] · Pizza Crust [473] · Galletas [517] (verificada
  activa en prod: BoM 16 propio + componente del BoM 18 de Cookie Dough).
  Los IDs del demo NO coinciden con producción.
- **Mes cerrado** (gate del indirecto): un mes cuenta solo si tiene registradas
  las 3 cuentas grandes: Cargas Sociales `6101003` (≥ un umbral de planilla,
  señal binaria) + Electricidad `6106005` + Alquiler `6106021`. El mes en curso
  nunca cuenta. La planilla operativa grande (monto en documento privado) NO está en el pozo.
- **Indirecto**: el pozo es la lista `COSTOS_INCLUDE` del `index.html`
  (fuente de verdad; ~25 cuentas). Promedio de los **últimos 3 meses cerrados**
  (ventana rolling que avanza sola). Se reparte por **días de producción**,
  no por batches.
- **Cookie Dough — regla del día compartido**: un día solo se le cuenta a
  Cookie Dough si ese día NO se produjo ningún otro terminado (las galletas
  nunca abren la fábrica un día extra). Simplificación aceptada: cargan ~0 de
  mano de obra del día compartido.
- El contador factura bajo una razón social distinta de la esperada; hay un
  partner viejo/inactivo que NO es el correcto. (Nombres exactos: documento privado.)

## Estándar visual (Truefie)

- Modo oscuro: fondo `#0E0E11` · superficies `#161619` · bordes `#26262C` ·
  texto principal `#F5F4F0` · secundario `#9A988F` · terciario `#6E6C68`.
  DM Sans. Sin emojis en la UI.
- Formato **es-CR** en todo número (₡, coma decimal), incluidos campos editables.
- **El color identifica y señala, nunca decora** — un solo acento por vista,
  el del módulo: Finanzas `#378ADD` · Conciliación `#84BD00` · Operaciones
  `#D4537E` · **Entregas `#E9FE60` (lima True Food)** · Ventas `#3FB6A8` ·
  Automatización `#FF751F`.
  **El morado `#7F77DD` ya NO es color de módulo** (13-ago-2026): Entregas es lo que
  vive en producción frente al congelador y va onbrand. Sigue existiendo como color
  de PRODUCTO (Buns) en las tablas — son dos paletas distintas, no tocar.
  Del lima hay UN tono, `#E9FE60`, más un borde oscuro derivado `#3F4A16`; no se
  inventan tonos intermedios.
- **Lima y ámbar conviven: cuidado.** El lima ya era el color de ACCIÓN del sistema
  (botones primarios), así que dentro de Entregas acento-de-módulo y color-de-acción
  coinciden — está bien, es la misma familia. Pero el ámbar (`#E9A23B` / `#C99A4E`)
  es el que AVISA. Se distinguen porque el lima nunca se usa como fondo lavado: los
  bloques de alerta conservan su lavado naranja y su borde. No poner fondos lima.
- Tablas: encabezado 11px gris terciario con línea 1px debajo, sin bordes entre
  filas, padding vertical ~11px, número principal de la fila en blanco hueso.

### Sin explicaciones en pantalla (estándar del sistema, 14-ago-2026)

**La herramienta no le explica a Andrea su propio trabajo.** Si una pantalla
necesita un párrafo para entenderse, el problema es el diseño, no la falta de
texto. Nada de "para qué sirve esta vista", nada de "tocá X para ver Y", nada de
"arrastrá el archivo", nada de "mové las perillas".

**La línea que separa:**

| Se va | Se queda |
|---|---|
| Instrucciones de uso ("Tocá un canal para ver sus clientes") | **Estado de los datos** ("1 órdenes sin lote legible") |
| Descripción de la pantalla ("La foto del congelador que ancla los saldos…") | **Anomalías** ("facturado 26 · sale 24 — diferencia registrada") |
| Justificaciones de diseño ("Cada cierre se inserta — nada se edita") | **Lo que cambia cómo se LEE un número**: con/sin IVA, qué fecha, qué unidad, solo lectura |

Estado sí, instrucciones no. Y lo que se queda va **comprimido a etiqueta**, no a
párrafo: `Del mes, con IVA · solo lectura.` en vez de tres renglones.

⚠️ Ojo al podar: quitar "con IVA", "por `date_done`" o "en la unidad del
producto" NO es limpieza — deja el número ambiguo. Eso no es explicación, es
definición del dato.

### Alertas del lobby — 5 reglas (estándar del sistema, 13-ago-2026)

Aplican a **todas** las alertas, no al módulo que las inventó. Una alerta que no
cumple las cinco no es una alerta: es información, y la información vive adentro
del módulo.

1. **Una alerta solo existe si hay algo que hacer.** Informar no es alertar.
   Corolario: si no hay nada pendiente, la alerta **no aparece** — no se muestra
   diciendo "todo al día".
2. **Tiene fecha o no es alerta.** Lo que no vence no urge; eso vive adentro
   del módulo.
3. **Se apaga sola al resolverse.** Nunca "marcar como visto": el estado sale
   del dato, no de un gesto.
4. **Máximo 3 visibles.** De la cuarta en adelante, "y N más →".
5. **Ámbar solo lo que vence hoy o mañana.** El resto en gris. El ámbar no
   significa "existe", significa "se te viene encima".

Auditoría de lo que ya existía (13-ago): la tarjeta de **Entregas pendientes**
incumple 1 (muestra "Todo al día." cuando no hay nada), 2 (no tiene fecha de
vencimiento en ninguna parte), 4 (no tiene el colapso "y N más") y 5 (pinta el
contador de ámbar por existir, no por urgir). Sin corregir todavía — el detalle
y las opciones están en `BITACORA.md`.
- Jerarquía tipográfica moderada: títulos de página contenidos, no gigantes.
- Alertas/estados: lo que está OK no muestra texto (celda vacía o punto verde);
  solo lo anómalo llama la atención.
