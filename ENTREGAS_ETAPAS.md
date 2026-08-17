# ENTREGAS · PREPARAR y ENTREGAR como dos etapas

> **Estado: CONSTRUIDO el 16-ago-2026 (`b20`), en `dev`.** El SQL es
> [`ENTREGAS_ETAPAS.sql`](ENTREGAS_ETAPAS.sql) — **hay que pegarlo en Supabase
> ANTES de publicar el build**: el código escribe en `ent_salida` y sin la tabla
> el botón "Preparar y entregar" falla a mitad de la cadena.
>
> Andrea revisó el módulo con el flujo real en la mano y el resultado fue un
> **rediseño completo**, no solo las dos etapas. Lo que cambió respecto de este
> documento está marcado abajo en **§9 (la pantalla)**; el resto —los tres
> estados, el esquema, el saldo, la anulación— quedó tal cual se había aprobado.
> El flujo real, que es el norte, quedó registrado abajo en **§0**.
>
> Se adelantó al domingo 16 (estaba previsto para el lunes por la tarde) por
> decisión de Andrea. Consecuencia asumida: **§11 no se pudo mirar antes de
> construir** — la mezcla real de pedidos de dos etapas vs simultáneos sigue sin
> medir, y el botón primario se eligió por el razonamiento de §4.1, no por dato.

---

## 0 · EL FLUJO REAL — el norte

*Dictado por Andrea el 16-ago-2026 con la operación en la mano. Es la referencia
contra la que se mide cualquier cambio al módulo: si una pantalla no cae en uno
de estos diez pasos, sobra; si un paso no tiene pantalla, falta.*

1. **Andrea o Lorena reciben pedidos** por WhatsApp o correo.
2. **Preparan el pedido de venta y confirman la factura** en Odoo.
3. **Llega a Truefie.**
4. **Daniel (o las socias) entra a la bandeja "Resumen".**
5. Ahí están separados por **POR PREPARAR / PREPARADO**.
6. **Daniel abre el pedido y asigna lote a cada producto.**
7. **Confirma preparado** → pasa a la lista de pendientes por entregar.
8. **Cuando entrega, confirma la entrega.**
9. **Se guarda con fecha y hora de preparación Y de entrega**, en el formato del
   Excel **AB-RE-04**. Ese detalle **se ve solo si se pide**.
10. **En Buscar:** por cliente, por lote, por producto, por fecha.

> Vive acá y no en `ESPEC_MODULO_ENTREGAS.md` **a propósito**: la ESPEC está en
> `.gitignore` (insumo interno) y el norte del módulo no puede vivir en un
> archivo que el repo no guarda.

---

## 1 · El problema

Hoy el módulo trata la entrega como **un solo momento**: Daniel confirma los
lotes, se escriben cinco filas y el pedido desaparece de la bandeja.

La operación no es así. Palabras de Andrea: *"a veces pasa al mismo tiempo pero
otras prepara temprano y lo despacha luego"*. Con un solo momento **no se puede
saber si un pedido está armado esperando el camión o si ya salió** — y ese es
justo el estado que alguien necesita mirar entre las 6:30 y las 7:30.

Estaba en la visión original (paso 5 del flujo de 7): *"Si prepara → estado
preparado, la entrega se valida cuando sale. Si prepara y entrega junto → se
valida de una vez."* Se implementó como un solo paso. Esto lo corrige.

**El caso de mayor volumen es de dos etapas:** Automercado y Walmart se validan
6:30-7:00 y salen 7:30.

## 2 · Lo que YA existe y no hay que inventar

El evento de preparación **ya se guarda hoy**. `ent_alisto` es exactamente eso
—"Daniel alistó esto, con estos lotes, a esta hora"— y `creado_en` es la hora de
preparación. Lo que falta es **la mitad que sigue**: la salida.

Consecuencia práctica: no se rehace nada, y lo ya guardado no pierde información.

## 3 · Los tres estados NO son tres filas

Dos de los tres se derivan de una **ausencia**. Es lo que mantiene el
append-only sin una columna de estado que haya que actualizar.

| Estado | Cómo se sabe |
|---|---|
| **por preparar** | hay factura en Odoo y **no hay** pedido en Supabase |
| **preparado** | hay alisto vigente y **no hay** salida |
| **entregado** | hay alisto vigente **y** salida |

No se crea fila para "por preparar": escribiría filas para pedidos que quizá
nunca se despachan.

## 4 · Las decisiones tomadas (Andrea, 15-ago)

1. **"Preparar" es el botón PRIMARIO.** El riesgo no es simétrico: si toca
   "preparar y entregar" y en realidad salió una hora después, queda una hora
   falsa en el registro y **nadie se entera**; si toca "preparar" y ya había
   salido, queda un pendiente fantasma que **se ve y se corrige solo**. Dato
   callado mal es peor que dato ruidoso bien. Y el volumen grande —Auto y
   Walmart— es de dos etapas.
2. **El saldo por lote se descuenta al PREPARAR** (§6).
3. **La "Fecha de despacho" del AB-RE-04 sale de `ent_salida.salida_en`**, que es
   la fecha real de salida y es lo que ese registro documenta. Para las filas
   viejas, fallback a `ent_pedido.fecha_despacho`.
4. **La vista se renombra** a `ent_salido_del_congelador_desde_ancla`, con el
   alias viejo vivo **un build**.
5. **Los dos hallazgos del esquema se arreglan en el mismo pegado** (§5.3, §5.4).

## 5 · El esquema (sexto pegado, `ENTREGAS_ETAPAS.sql`)

### 5.1 · Tabla nueva `ent_salida`

```
ent_salida (
  id          bigint generated always as identity primary key,
  alisto_id   bigint not null references ent_alisto(id),
  salida_en   timestamptz not null default now(),   -- la hora REAL de salida
  nota        text,
  creado_en   timestamptz not null default now(),
  creado_por  text not null )
```

**Cuelga del ALISTO, no del pedido.** El alisto es el que lleva los lotes y las
cantidades reales; si Daniel corrige e inserta otro alisto, colgar del pedido
dejaría sin respuesta *"¿cuál alisto fue el que salió?"*.

RLS y grants: `select, insert` a `authenticated`, igual que el resto. Sin update
ni delete — append-only se hace cumplir en el permiso, no por convención.

### 5.2 · Vista nueva `v_ent_pedido_estado`

`pedido_id · factura_id · cliente · alisto_id · preparado_en · salida_en · estado`

Es de la que come la sección "Preparados". **No toca Odoo**: sale entera de
Supabase, así que se dibuja al instante, sin esperar los ~40 s del arranque en
frío del proxy. Con `security_invoker = true`.

### 5.3 · HALLAZGO 1 — `ent_alisto.anulado` no se puede poner en `true`

El comentario del esquema promete *"me equivoqué de pedido: se anula, no se
borra"*, pero las políticas y los grants son `select, insert` y nada más:
Postgres niega el `update`. **Hoy anular un alisto es imposible.**

Salida append-only:

```
ent_anulacion (
  id, entidad text not null check (entidad in ('alisto','salida')),
  entidad_id bigint not null, motivo text,
  creado_en timestamptz not null default now(), creado_por text not null )
```

Las vistas cambian `a.anulado = false` por un `not exists` contra esta tabla. La
columna `anulado` se queda por compatibilidad con lo ya escrito.

**Esto no es cosmético:** habilita el "deshacer preparación", que es lo único que
arregla el caso del producto devuelto al congelador (§7b). Sin esto, un pedido
devuelto deja el saldo mal **para siempre** y nadie tiene cómo corregirlo.

### 5.4 · HALLAZGO 2 — `v_ent_factura_despachada` sin `security_invoker`

Se creó sin `with (security_invoker = true)`, a diferencia de las otras dos
vistas: corre con permisos de quien la creó y se salta el RLS. Acá no expone nada
delicado (ids de factura), pero **contradice la regla escrita en el propio
esquema**. Se corrige con un `create or replace` en el mismo pegado.

### 5.5 · Backfill (obligatorio, va en el pegado)

Todo lo confirmado antes de que esto salga —incluida la factura de Automercado
del lunes— tiene alisto y no tiene salida, o sea que aparecería como "preparado"
**para siempre**. El pegado inserta una `ent_salida` por cada alisto existente
con `salida_en = alisto.creado_en` y nota:

> `backfill: confirmado antes de que existieran las dos etapas`

**La nota importa:** deja dicho que esa hora es la de preparación usada como
aproximación, **no una medición**. (Regla de la bitácora: medido vs objetivo, no
confundirlos.)

## 6 · El saldo se descuenta al PREPARAR

El ancla cuenta lo que está **en el congelador**. Un pedido preparado ya salió de
ahí. Si el saldo no baja al preparar, el siguiente pedido de esa misma mañana ve
un lote que en realidad ya está comprometido, Daniel lo elige, va a buscarlo y no
está — **que es exactamente el error que el selector de lotes existe para
evitar**.

**No requiere ningún cambio de lógica:** `ent_entregado_desde_ancla` ya resta
desde `ent_alisto_lote`, o sea que **ya descuenta al preparar**.

Lo único que cambia es **el nombre**, porque pasó a ser mentira: no es
"entregado", es "salido del congelador" →
**`ent_salido_del_congelador_desde_ancla`**, con el alias viejo vivo un build
para no romper `rpCalcSaldos()` de golpe. En un módulo cuyo punto entero es que
las palabras signifiquen algo, un nombre que miente cuesta caro.

## 7 · Qué pasa si algo se prepara y no sale ese día

Son tres casos y piden respuestas distintas.

**(a) Sale al día siguiente — el normal.** Se queda en "Preparados" cruzando el
día, con la edad a la vista (`preparado ayer 6:42`). El saldo sigue descontado, y
está bien: el producto está físicamente fuera del congelador.

**(b) Se devuelve al congelador** (se canceló, el cliente no recibió). Necesita
**"Deshacer preparación"** explícito — hoy imposible, ver §5.3. Al anular el
alisto el saldo vuelve solo, porque la vista deja de contarlo.

**(c) Nadie lo tocó.** Es la alerta del lobby, §8.

## 8 · La alerta — candidata a REEMPLAZAR la tarjeta de Entregas pendientes

**Anotado por pedido de Andrea (15-ago).** "Preparado y no salió" es **la primera
alerta que cumple las 5 reglas del lobby sin forzar nada**:

| Regla | Cómo la cumple |
|---|---|
| 1 · solo existe si hay algo que hacer | hay que sacarlo o devolverlo al congelador |
| 2 · tiene fecha | el día de preparación, que es un vencimiento real |
| 3 · se apaga sola | al insertarse la `ent_salida` desaparece; nadie "marca como visto" |
| 4 · máximo 3 visibles | lista corta por naturaleza + "y N más →" |
| 5 · ámbar solo lo que urge | ámbar desde "preparado ayer o antes"; hoy en gris |

**Es candidata a reemplazar la tarjeta de Entregas pendientes del pendiente 12**,
que incumple 4 de las 5 (muestra "Todo al día." cuando no hay nada, no tiene
fecha de vencimiento, no tiene el colapso "y N más", y pinta el contador de ámbar
por existir y no por urgir). Decidir al construir: si esta la reemplaza, el
pendiente 12 se cierra por sustitución en vez de por corrección.

## 9 · La pantalla — REDISEÑADA el 16-ago (esto reemplaza lo que decía acá)

Lo de abajo es lo que se construyó. Donde difiere de lo aprobado el 15-ago se
dice por qué.

### 9.1 · Pantalla 1 — "Resumen" (la bandeja)

**DOS secciones vivas, cada una con su contador:**

```
POR PREPARAR        n     ← facturas de Odoo sin pedido
  · · ·
  Anteriores sin despachar   n     (subgrupo demotado, no compite)
PREPARADO           n     ← armado, esperando el camión
  · · ·
Entregados hoy · n        ← una línea al pie, lleva al historial
```

**Cambios respecto de lo aprobado el 15-ago, y por qué:**

- **Dos secciones, no cuatro, y POR PREPARAR va PRIMERO.** El 15-ago se había
  decidido "Preparados arriba de todo" porque es la lista más corta. Con el
  flujo real en la mano gana el orden del día: a las 6:30 se prepara y a las
  7:30 se saca. Las separaciones "Hoy / Días anteriores" se fueron: **cada
  tarjeta ya trae su día** (`hoy`, `ayer`, `vie 15`), así que el rótulo era el
  mismo dato dos veces. "Anteriores sin despachar" **se queda**, porque su
  trabajo no es agrupar sino DEMOTAR.
- **Los entregados no ocupan espacio:** una línea al pie, no una tercera lista.
- **La tarjeta de preparado NO se despacha al tocarla.** Se había aprobado
  "el segundo toque marca la salida". Andrea lo cambió al revisarlo: la tarjeta
  lleva un **botón Entregar** y **pide confirmación**. Un toque accidental no
  puede marcar una salida — y como una hora de salida falsa **no la ve nadie
  después**, el costo de equivocarse es invisible, que es el peor tipo.
- La tarjeta muestra cliente y **`preparado 6:22`**; en ámbar desde
  `preparado ayer 6:42` (regla 5 del lobby: ámbar solo lo que urge).

### 9.2 · Pantalla 2 — Preparar el pedido

- **Productos en grilla de DOS COLUMNAS, también en móvil.** El pedido entero
  entra en una pantalla y se ve de un vistazo qué falta. **Medido en el
  navegador, no supuesto:** a 390px cada tarjeta queda en **175px**, el selector
  en **152px** y `224 / 2-27` mide **78px** sobre 117px disponibles — entra
  completo, y también entraría un juliano de 4 dígitos (90px).
- **Borde izquierdo = estado:** lima = tiene lote · gris = falta.
- **El caso normal es una línea:** un solo selector, **sin campo de cantidad**
  (la cantidad es la de la factura y está arriba, editable al tocarla).
- **La tarjeta con lote partido ocupa el ancho completo.** Necesita selector +
  cantidad + quitar por fila, y eso no cabe en media pantalla.
- **`+ partir` → `+ otro lote`**: dice lo que hace, no la mecánica interna.
- **Se puede QUITAR una línea agregada por error** (× en cada fila del reparto).
  Era un **bug reportado por Andrea**: se agregaba un lote de más y la única
  salida era abandonar el pedido y volver a elegir todo. Al bajar a un solo lote
  la tarjeta **vuelve sola al caso simple** — un lote no es un reparto.
- Al partir aparecen las cantidades por lote y el contador (`6 de 6`).
- **Dos botones al pie, apilados:** `Preparar` (primario) y
  `Preparar y entregar` (secundario). Apilados y no lado a lado: el secundario
  al lado del primario compite, y el volumen grande es de dos etapas.

### 9.3 · Pantalla 3 — Buscar

**UN solo campo**, y al lado se elige por qué se busca: **cliente · lote ·
producto · fecha**. No cuatro campos, que obligan a decidir antes de escribir y
dejan tres huecos inertes en pantalla. Búsqueda sin tildes y sin mayúsculas.

La lista responde *cuándo y a quién*; **el AB-RE-04 se arma solo al abrir una
fila**. Tope de 60 filas dibujadas, y lo que queda afuera **se dice** (`y N más
— afiná la búsqueda`): un corte callado se lee como "esto es todo".

Estilo: sin explicaciones en pantalla. Lima `#E9FE60` como acento; el ámbar
sigue siendo el que avisa.

## 10 · Checklist de construcción — estado al 16-ago

1. ✅ `ENTREGAS_ETAPAS.sql` escrito con §5.1 a §5.5, re-ejecutable. **Falta que
   Andrea lo pegue y verifique.**
2. ✅ `despConfirmar(entregar)` → dos caminos; el de "preparar" corta antes de
   `ent_salida`.
3. ✅ Sección "Preparado" alimentada por `v_ent_pedido_estado` (sin Odoo — se
   dibuja antes que el resto).
4. ❌ **"Deshacer preparación" NO se construyó.** `ent_anulacion` existe y
   funciona en la base, pero **no hay botón**. Queda pendiente: hasta que exista,
   un pedido devuelto al congelador sigue dejando el saldo mal (§7b).
5. ✅ AB-RE-04: la fecha sale de `ent_salida.salida_en` con fallback
   (`v_ent_pedido_estado.fecha_ab_re_04`).
6. ✅ Renombre de la vista + alias vivo. **Borrar el alias el build siguiente:**
   `drop view if exists ent_entregado_desde_ancla;`
7. ✅ `python3 loadcheck.py` pasa. `BUILD` subido a `b20`.
8. ✅ Registro manual (Reporte de despacho) inserta también la salida — si no,
   quedaría en "Preparado" para siempre. La FECHA es la elegida; la HORA se pone
   a mediodía y la nota dice que **no es medida**.

## 11 · Lo que hay que MIRAR el lunes antes de construir esto

- **La mezcla real**: cuántos pedidos son de dos etapas y cuántos simultáneos.
  Confirma o corrige la decisión del botón primario.
- **Cuánto tiempo pasa** entre preparar y salir en Auto y Walmart (se supone una
  hora; medirlo).
- Si aparece algún caso (b) —producto devuelto al congelador— en la primera
  semana. Sube o baja la prioridad del "deshacer preparación".

---

**Nota de higiene, aparte:** el color viejo de `ESPEC_MODULO_ENTREGAS.md` §8 pasó
a [`LIMPIEZA_DOC.md`](LIMPIEZA_DOC.md), que es donde va.
