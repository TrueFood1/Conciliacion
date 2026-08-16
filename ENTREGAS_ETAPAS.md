# ENTREGAS · PREPARAR y ENTREGAR como dos etapas

> **Estado: DISEÑO APROBADO POR ANDREA, SIN CONSTRUIR.** 15-ago-2026.
>
> ⛔ **NO va antes del lunes 17.** El lunes corre lo que ya está probado (`b19`).
> Esto se construye el **lunes por la tarde o el martes**, con lo que se vea el
> lunes ya sabido. El pegado de SQL (`ENTREGAS_ETAPAS.sql`) **todavía no existe a
> propósito**: escribirlo hoy lo congelaría antes de la única corrida real que
> puede corregirlo.

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

## 9 · La pantalla

**Al confirmar los lotes, dos botones** en lugar de uno:

- **Preparar** — *primario*. Inserta la cadena de alisto. El pedido pasa a
  "Preparados".
- **Preparar y entregar** — *secundario*. Inserta la cadena **y** la salida.

**La bandeja pasa a cuatro secciones, con "Preparados" ARRIBA de todo:**

```
Preparados                  ← armado, esperando el camión
Hoy
Días anteriores
Anteriores sin despachar
```

Arriba porque es la lista más corta y la única con algo que hacer *ahora mismo*.

**La tarjeta de un preparado** muestra cliente y hora (`preparado 6:42`), y **el
segundo toque marca la salida sin abrir pantalla** — tocar la tarjeta la
despacha. Abrirla para revisar lotes o corregir es un gesto aparte.

Estilo: sin explicaciones en pantalla (el rótulo de sección es `Preparados` a
secas). Lima `#E9FE60` como acento; el ámbar sigue siendo el que avisa.

## 10 · Checklist de construcción (lunes tarde / martes)

1. Escribir `ENTREGAS_ETAPAS.sql` con §5.1 a §5.5, re-ejecutable
   (`if not exists` / `or replace`), y que Andrea lo pegue y verifique.
2. `_despEst` / `despConfirmar()` → dos caminos; el de "preparar" corta antes de
   `ent_salida`.
3. Sección "Preparados" en la bandeja, alimentada por `v_ent_pedido_estado`
   (sin Odoo — se dibuja antes que el resto).
4. "Deshacer preparación" contra `ent_anulacion`.
5. AB-RE-04: la fecha sale de `ent_salida.salida_en` con fallback.
6. Renombre de la vista + alias, y borrar el alias el build siguiente.
7. `python3 loadcheck.py` antes de publicar. Subir `BUILD`.

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
