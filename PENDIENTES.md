# Pendientes de otros módulos

Anotados para cuando se retomen. **No construidos.** Entregas tiene su propio
archivo: `ENTREGAS_PENDIENTES.md`.

---

## F1 · Finanzas · Los montos se muestran REDONDEADOS

Reportado por Andrea el 26-ago-2026 probando desde el teléfono.

**Qué pasa.** Los montos a pagar —y probablemente también los de cobrar— se
muestran redondeados. Andrea necesita el **monto exacto**: un total redondeado no
cuadra contra el banco y **rompe el match en conciliación**, que es el trabajo
que ese número existe para permitir.

### ⚠️ Lo PRIMERO al retomarlo, antes de tocar nada

Averiguar si el redondeo es **solo de presentación** o si el número redondeado
**entra en cálculos**. Son dos problemas de gravedad muy distinta:

- **Solo presentación** → se arregla en el formateo. Molesto, no peligroso.
- **Entra en cálculos** → *más grave que lo reportado*: los totales, los saldos y
  cualquier comparación contra el banco estarían construidos sobre números que no
  son los de Odoo. Habría que revisar hacia atrás qué se decidió con ellos.

La forma de saberlo: seguir el número desde la lectura de Odoo hasta la pantalla y
ver **dónde** se redondea. Si se redondea al leer o al sumar, es el segundo caso.
Si se redondea solo en el `toLocaleString` de la vista, es el primero.

**No asumir que es presentación porque parezca presentación.** El caso de la UoM
(b34) también parecía cosmético y la cuenta estaba bien; acá puede ser al revés.

---

## O1 · Operaciones · El Planificador BLOQUEA el tope de batches, y debería avisar

Reportado por Andrea el 26-ago-2026.

**Qué pasa.** El Planificador no deja pasar del máximo de capacidad por producto
(con tres personas: Blanco 8, Semillas 10, Pizza 12, Francés 10, Buns 10).

**Decisión de Andrea: advertir y dejar pasar, con el motivo escrito. No bloquear.**

**El razonamiento, que es lo que hay que conservar:** ese tope es una **estimación
de capacidad**, no un límite físico. Se puede trabajar más horas o meter más
gente, y entonces el número deja de valer. Un bloqueo convierte una estimación en
una ley, y obliga a mentirle al sistema para reflejar lo que de verdad va a pasar.

**Es lo CONTRARIO del bloqueo de inventario**, y la diferencia es el punto:

| | Tope de batches | Saldo por lote |
|---|---|---|
| Qué es el límite | una estimación de capacidad | un hecho físico |
| ¿Se puede superar en la vida real? | **sí** — más horas, más gente | **no** — no se puede sacar pan que no existe |
| Qué debe hacer el sistema | **advertir** y dejar pasar | **bloquear** |

Al construirlo: el aviso tiene que decir **cuánto** se está pasando y **de qué
supuesto** (cuántas personas), no solo "te pasaste". Y el motivo de haberlo
superado se escribe, como todo lo demás del proyecto.

---

## P1 · Personal · `PERSONAL_STORAGE.sql` está aprobado y nunca se estrenó

Detectado el 10-sep-2026 diseñando el bucket de los tickets, buscando un
precedente de subida de archivos.

**Qué pasa.** `PERSONAL_STORAGE.sql` lleva escrito *"✅ APROBADO POR ANDREA
24-ago-2026 — se levanta el STOP de diseño"* y diseña dos buckets privados
(`justificantes`, `aguinaldos`) con sus políticas, sus funciones de carpeta y su
paso manual en el panel. **El código nunca lo usó.** Medido: `grep` de `.upload(`
y de `createSignedUrl` sobre `index.html` el 10-sep-2026 → **cero apariciones de
cada uno**. Ni una pantalla sube ni muestra un archivo.

**Es el CUARTO caso del mismo patrón** — una decisión escrita, aprobada, y nunca
implementada, con los documentos hablando de ella como si existiera. Los tres
anteriores, todos ya documentados:

| | Qué se dio por hecho | Cómo se descubrió |
|---|---|---|
| El bloqueo duro de Despachos | "impide despachar sin saldo" | preguntando por un lote en −4 (`ENTREGAS_PENDIENTES.md` §13) |
| La capa 3 del candado de producción | "el usuario de Odoo no puede escribir" | midiendo un `write()` real, que devolvió `True` (`CLAUDE.md`) |
| La CUARTA PUNTA del saldo | `ent_devuelto_desde_ancla`, pegada y sin lector | buscando a mano al preparar la primera devolución (`CLAUDE.md`) |
| **`PERSONAL_STORAGE.sql`** | "Truefie ya guarda archivos" | buscando un precedente para los tickets |

Los cuatro tienen la misma forma: **el esquema o el permiso existen en el papel,
y lo que falta es el código que los usaría** — o al revés. Y en los cuatro, lo
que lo destapó fue ir a mirar, nunca una alerta.

### Lo PRIMERO al retomarlo

**Medir si los dos buckets existen de verdad**, antes de decidir nada:

```sql
select id, public, file_size_limit from storage.buckets order by id;
```

Son tres cosas distintas y hay que separarlas:

- **No existen** → el pegado del 24-ago no llegó a correrse, o falló en el
  `insert into storage.buckets` por permisos (el propio archivo lo prevé).
- **Existen y `public = false`** → todo bien: hay esquema esperando código.
- **Existen y `public = true`** → 🔴 **urgente**. El bucket serviría las fotos de
  notas médicas y la hoja del aguinaldo a cualquiera con la URL, sin login. Hoy
  no hay archivos adentro porque nada sube — o sea que el riesgo es de mañana,
  no de hoy, pero se arregla ahora.

Nada de esto se puede contestar leyendo: ver **H1**, que es la razón por la que
nadie se habría enterado.

---

## H1 · Herramientas · `esquema_check.py` NO MIRA STORAGE

Detectado el 10-sep-2026, junto con **P1**.

**Qué pasa.** `esquema_check.py` saca los objetos de los `from('tabla')` del
`index.html` y los sondea por REST. **Los buckets de Storage no son tablas y no
aparecen en ningún `from()`**, así que quedan enteramente fuera de su alcance: el
chequeo puede dar ✓ con un bucket inexistente, o —peor— con uno **público**.

**Esto no es un pendiente de código, es un punto ciego de la herramienta de
seguridad.** El chequeo tiene ya dos puntos ciegos documentados en `CLAUDE.md`
(no ve lo que el código todavía no llama; no ve las llamadas por variable). Éste
es el tercero, y es el único que puede callar sobre una **exposición de datos**:
desde el 26-ago el archivo lee los objetos sensibles **al revés** —`permission
denied` = ✓, filas = 🔴 fuga— justamente por la lección de `v_acceso_usuario`, y
esa lógica no llega a Storage.

### Qué habría que agregarle

- Leer `storage.buckets` y **bloquear si alguno tiene `public = true`**. Es el
  equivalente exacto de la regla de los objetos sensibles: en un bucket privado,
  "no puedo entrar" es el resultado bueno.
- Comprobar que cada bucket declarado en los `.sql` del repo **existe**, con la
  misma distinción de siempre entre deuda nueva (bloquea) y deuda vieja (avisa).
- Comprobar que no hay políticas de `update` ni `delete` sobre `storage.objects`
  para esos buckets — el append-only de archivos hoy se sostiene solo en que
  nadie las escribió.

⚠️ **Ojo con la anon key acá.** Preguntarle a Storage con la anon key tiene la
misma trampa que preguntarle a una tabla con RLS: puede contestar "vacío" en vez
de "no tenés permiso", y ese vacío no prueba nada. La comprobación de `public`
necesita SQL (`pg_lector.py`), no REST.

---

## H2 · 🟠 ABIERTO · `esquema_check.py` no ve NINGUNA de las cuatro tablas donde se ESCRIBE

Anotado el 16-sep-2026, preparando b60. **Pedido por Andrea.**

### Qué pasa

El chequeo saca los objetos con un regex de literales:

```python
def objetos_de(txt): return set(re.findall(r"from\('([a-z_][a-z0-9_]*)'\)", txt))
```

Así que `c.from(t)` dentro de un helper se le escapa. **Esto no es nuevo**: es el
punto ciego 2 que `CLAUDE.md` ya documenta, con su incidente del 19-ago
(`ent_pedido_motivo_vigente` y `ent_pedido_valida_vigente` — Pendientes caída en
producción y el chequeo en ✓).

### Lo que sí es nuevo, y es la razón de anotarlo aparte

**Los objetos que se le escapan son justamente los de ESCRITURA.** Medido hoy:
`index.html` tiene exactamente **dos** llamadas por variable, y no es casualidad
cuáles son:

| línea | helper | qué hace |
|---|---|---|
| 13090 | `q(t,sel)` | **lee** cuatro vistas de Pendientes |
| 13602 | `pdInsert(tabla,fila,texto)` | **escribe**, y es el único `insert` genérico del archivo |

Por `pdInsert` pasan **cuatro tablas, las cuatro invisibles para el chequeo**:

- `ent_alisto_linea_autorizacion` ← el «Visto» de b60
- `ent_pedido_valida` ← "Ya validé"
- `ent_pedido_motivo` ← "Clasificar"
- `ent_pedido_factura` ← "Vincular"

De los 27 `.insert(` del archivo, éstas son las que el portón no mira. Las otras
23 escriben con el nombre puesto y sí se ven.

### Por qué importa más que un punto ciego de lectura

**La dirección del daño es distinta.** Un objeto de LECTURA que falta rompe una
pantalla entera y a la vista: es lo que pasó el 19-ago, Pendientes no cargaba y
se notó el mismo día. Un objeto de ESCRITURA que falta no rompe nada hasta que
alguien **toca el botón** — después de haber tomado la decisión y escrito la
nota, sobre un caso real, y en un camino que se recorre pocas veces (el «Visto»
lo tocan dos personas y solo cuando hay excepciones abiertas).

El paso 6 del `CIERRE_TECNICO.md` existe por el incidente del 17-ago: se publicó
código que dependía de un `.sql` sin pegar. **Ese portón hoy no cubre ninguna de
las cuatro escrituras del módulo.**

### Estado hoy (medido el 16-sep, sondeo REST con la anon key)

Las cuatro existen — ninguna devuelve `42P01` ni `PGRST205`. O sea que **no hay
nada roto ahora**: esto es el portón, no un incendio.

⚠️ Y ese sondeo prueba EXISTENCIA y nada más. Un `200` con lista vacía no
distingue "legible" de "la RLS filtró todo" cuando la tabla puede estar vacía.

### Qué habría que agregarle

- Sumar al regex las llamadas con literal dentro de los helpers de escritura:
  `pdInsert('tabla'` es un literal, solo que no pegado a `.from(`. Un segundo
  patrón lo caza hoy mismo y cuesta una línea.
- Mejor todavía, y más a prueba del próximo helper: **sacar los literales de
  cualquier llamada que termine en un objeto de Supabase**, no solo de `from(`.
- Y dejar escrito en la salida **cuántos objetos se vieron por cada camino**.
  Como en el punto ciego 1: si el contador no se mueve cuando se agrega una
  escritura nueva, el chequeo está mirando para otro lado.


---

## O2 · 🟠 ABIERTO · Un Buns facturado en "Caja" de 6 cuando la caja de Buns son 24

Encontrado el 17-sep-2026 midiendo los factores de unidad para Devoluciones.
**El dato malo está en ODOO, no en Truefie** — Truefie lo copió fielmente.

### La fila

| | |
|---|---|
| pedido | **67** |
| factura | `00100001010000003534` |
| cliente | Arrendadora Bm Pz Sociedad |
| fecha | 2026-09-14 |
| producto | **503 · Buns** |
| unidad | `uom_id 46` · **"Caja"** · factor 1/6 → **6 unidades** |
| cantidad | 1 caja = 6 unidades |

### Por qué está mal

Buns se factura normalmente en **`Caja (Hamburguesa)` (uom 42) = 24 unidades**, o
en `Paquete de 4` (uom 37). La unidad `Caja` (uom 46) es la de **Pan Blanco y Pan
Semillas**, que sí traen 6 por caja.

Medido sobre `ent_pedido_linea`: Buns aparece con **tres** unidades distintas —
`Paquete de 4` (30 líneas), `Caja (Hamburguesa)` (11) y **`Caja` (1 sola línea,
ésta)**. Las otras dos son correctas.

### Qué corregir, y dónde

**En Odoo**, en la factura `…3534`: la línea de Buns debería ir en
`Caja (Hamburguesa)` (1 caja = 24 u) o en `Paquete de 4`. Como está, esa entrega
dice que salieron **6 unidades** de Buns cuando es probable que hayan salido
**24** — hay que confirmarlo contra lo que realmente se despachó antes de tocar
nada.

⚠️ **No se corrige desde Truefie.** `ent_pedido_linea` copia la unidad de la
factura en el momento del despacho, a propósito: es el dato tal como se facturó.
Cambiarlo acá dejaría a Truefie diciendo una cosa y a Odoo otra.

### Qué NO rompe

- El **saldo por lote** usa `cant_uds` (6), que es lo que Truefie registró como
  salido. Si de verdad salieron 24, el saldo de ese lote está **18 unidades alto**.
- **Devoluciones** no se ve afectada desde el 17-sep: la unidad de entrada pasó a
  ser la de manejo del producto, así que un Buns que vuelve se escribe en paquetes
  sin importar cómo se facturó (ver `ENTREGAS_PENDIENTES` §12).

---

## S1 · 🟠 ABIERTO · Datos de clientes en el repo PÚBLICO — el repaso sigue sin hacerse

Anotado el 17-sep-2026 al chequear secretos para b61. **No es exposición nueva**,
pero la lista crece build a build y nadie la ha revisado entera.

### El repo es público y sirve GitHub Pages

`TrueFood1/Conciliacion` es público. `BITACORA.md` está gitignored **precisamente
por esto** — su encabezado lo dice: *"el repo es público y esto lleva razones
sociales de clientes"*. Pero esa decisión se tomó para la bitácora y **nunca se
extendió al resto de los archivos versionados**.

### Lo medido el 17-sep

| qué | dónde | ¿nuevo? |
|---|---|---|
| `andrea@truefoodcr.com` | `index.html` (4 veces en `main`) + `ANULAR_DEVOLUCION.sql` | no |
| consecutivos de factura `001000010100000…` | `CORRECCION_B56_PEDIDO44.sql`, `ENTREGAS_EXCEPCIONES_LINEA.sql` (en `main`) y ahora **`PENDIENTES.md` §O2** | el de O2 sí |
| razones sociales | `ENTREGAS_PENDIENTES.md` (Automercado, Green Center, Mentha…), y §O2 agrega *Arrendadora Bm Pz Sociedad* | se suman |

**El correo no es el problema**: la regla del repo ya lo resuelve —los
`@truefoodcr.com` van en claro porque son direcciones de empresa, y los
personales van por huella (`SALUDO_HUELLAS`)—. Está aplicada y es consistente.

**Lo que no tiene regla es el resto**: número de factura + razón social + fecha +
qué se le vendió. Eso, junto, es información comercial de un tercero.

### Por qué no bloqueó b61

Porque **no es una puerta nueva**: cada cosa que se agregó es de la misma clase
que lo que ya está publicado desde hace semanas. Bloquear el build por un
consecutivo más, dejando los que ya están, no protege nada — solo da la sensación
de haber hecho algo.

⚠️ Y ése es justamente el riesgo de este pendiente: **cada build individual
siempre va a parecer "una más"**, y así es como la lista crece sin que ninguna
decisión la autorice.

### Qué hay que hacer cuando se retome

1. **Barrer los archivos versionados** buscando consecutivos, razones sociales y
   cédulas. No solo `.md`: los `.sql` de corrección y verificación llevan casos
   reales con nombre y número.
2. **Decidir la regla**, que hoy no existe:
   - ¿los ejemplos de un pendiente van con el cliente real, o anonimizados?
   - ¿los `.sql` de corrección —que necesitan el id real para correrse— van al
     repo, o al lado de la bitácora, gitignored?
3. **Aplicarla hacia atrás**, sabiendo que reescribir la historia de git es otra
   conversación: lo que ya se publicó siguió publicado aunque se borre el archivo.
4. **Y dejarla en `CLAUDE.md`**, junto a la de credenciales, para que el chequeo
   de secretos del cierre técnico tenga contra qué medir. Hoy ese paso busca
   claves y tokens, no datos de clientes.

---

## P2 · ✅ DECIDIDO · Instinct lee el neto de quincena y los feriados trabajados

Decisión de Lorena, **16-oct-2026**. No es un pendiente de construcción: es una
decisión tomada, anotada acá para que no haya que volver a discutirla y para que
nadie la "corrija" por creerla un descuido.

> **Instinct puede leer el neto de quincena y los feriados trabajados en la base
> (solo lectura); la pestaña de Pago sigue escondida en la pantalla para el
> perfil asistente.**

### Cómo apareció

El candado del pegado 10 (`PERSONAL_NETO_QUINCENA.sql`) abortó diciendo «hay 14
políticas en las dos tablas nuevas, tenían que ser 4». El pegado escribe 2 por
tabla. Las otras 5 por tabla las pone **solo** el disparador de eventos
`asistente_politicas` (`ASISTENTE_ROL.sql` §7), que corre en cada `create table`
de `public` y llama a `asistente_crear_politicas()`. O sea que aparecen en el
mismo instante en que el pegado crea las tablas, sin que el pegado las pida.

**El error era del candado, no de las reglas.** Contaba un número fijo —y encima
contaba políticas de otro. Ahora compara el **conjunto exacto** de tabla +
política + comando, así que sigue detectando una de más, una de menos o una
cambiada, pero ya no se pelea con el disparador.

### Las dos tablas nuevas quedan así, y es lo que Lorena decidió

| política | tipo | comando | efecto sobre el asistente |
|---|---|---|---|
| `rrhh_*_sel` (propia) | permisiva | SELECT | nada: pide socia |
| `rrhh_*_ins` (propia) | permisiva | INSERT | **lo frena** |
| `asistente_ve_todo` | permisiva | SELECT | **le abre la lectura** |
| `asistente_lee` | restrictiva | SELECT | lo deja leer **solo con el interruptor encendido** |
| `asistente_no_inserta` | restrictiva | INSERT | **lo frena** |
| `asistente_no_actualiza` | restrictiva | UPDATE | lo frena |
| `asistente_no_borra` | restrictiva | DELETE | lo frena |

Siete por tabla, catorce en total.

### Lo que NO hay que perder de vista al retomar esto

- **La lectura depende del interruptor.** `asistente_lee` es restrictiva y dice
  `not acceso_es_asistente() or asistente_encendido()`. Con Instinct apagado,
  Instinct **no** lee estas dos tablas, aunque `asistente_ve_todo` se lo permita:
  las restrictivas se exigen TODAS. No es un acceso permanente.
- **Nadie actualiza ni borra, tampoco las socias.** No hay ninguna política
  permisiva de UPDATE ni de DELETE en estas dos tablas, y `authenticated` no
  tiene el grant. Eso es lo que sostiene el append-only del neto, de donde
  cuelgan transferencias ya hechas. Si alguna vez hace falta corregir un neto,
  se agrega una fila con otra vigencia — no se edita la vieja.
- **La pantalla y la base dicen cosas distintas, a propósito.** En
  `index.html:6321` la pestaña «Pago de quincena» pide perfil `socia`, así que el
  asistente no la ve. Que pueda leer la tabla por SQL y no ver la pestaña es la
  decisión, no una inconsistencia: si algún día se le quiere mostrar la pantalla,
  hay que cambiar `PER_TABS` a mano y eso es otra decisión de Lorena.

---

## P3 · 🟠 ABIERTO · El 12-oct-2026 no está cargado como feriado en ninguna parte

Encontrado el **16-oct-2026** corriendo el ensayo del pegado 10 contra un
PostgreSQL local. Cuatro pruebas daban rojo y las cuatro por lo mismo: yo había
escrito los esperados dando por hecho que el 12 de octubre era feriado.

**No lo es, en los datos.** La semilla de `PERSONAL_CALENDARIO.sql` carga cuatro
filas en `rrhh_feriado`: 31-ago, 15-sep, 1-dic y el cierre de planta. La lista
`FERIADOS` del `index.html:9584` tiene las mismas tres fechas. El 12-oct aparece
**solo** en la tabla de `PREGUNTAS_contadora_feriados.md`, marcado «ya pasó».

### Por qué importa, aunque ya pasó

Mientras el día no esté en `rrhh_feriado`, `rrhh_es_dia_descontable()` lo
considera un día hábil común. O sea: **a quien faltó el 12 de octubre se le
descuenta el día.** Si para True Food ese día fue feriado, el descuento está mal.

Y hacia adelante es peor que un error puntual: los feriados de 2027 no están
cargados tampoco. El primero que caiga en lunes a viernes va a descontar.

### ⚠️ Lo que cambió el 16-oct, y acota este pendiente

Desde la decisión de Lorena de ese día, **lo que no descuenta es el feriado de
pago obligatorio**; uno no obligatorio se trata como día normal. El 12-oct es **no
obligatorio**, así que **cargarlo ya no cambiaría el descuento**: a quien faltó ese
día se le descuenta igual, esté cargado o no.

Eso no cierra el pendiente, lo acota. Lo que sigue abierto es el **calendario**
—que el día aparezca pintado y que la lista de la base y la del `index.html` dejen
de ser dos— y los feriados **obligatorios** de 2027, que sí cambian plata.

### Qué hay que decidir, y no lo decide un script

1. **¿El 12-oct-2026 fue día cerrado en la planta?** Si sí, cargarlo y revisar si
   alguien tuvo una ausencia ese día.
2. **Cargar los feriados de 2027** antes de que empiece el año. Son datos, no
   código: van por la pantalla «Días cerrados» o por un pegado de semilla.
3. **Y las dos listas tienen que dejar de ser dos.** `rrhh_feriado` y la constante
   `FERIADOS` del `index.html` se mantienen a mano, por separado, y ya no
   coinciden del todo (a la del HTML le falta el 25-dic). Una de las dos tiene
   que desaparecer; la de la base es la que puede editarse sin publicar.

### Y el 1 de enero de 2027, que es el caso urgente

Agregado el **16-oct-2026** por decisión de Lorena. **No implementado.**

El **1-ene-2027 es viernes** y es feriado de **pago obligatorio** (art. 148 del
Código de Trabajo). Tiene exactamente el mismo conflicto que el 25-dic:

| | 25-dic-2026 | 1-ene-2027 |
|---|---|---|
| día de la semana | viernes | **viernes** |
| pago obligatorio | sí | **sí** |
| ¿está cargado en `rrhh_feriado`? | **no** | **no** |
| por qué no se puede cargar | está dentro del cierre de planta | **está dentro del cierre de planta** |

El cierre va del 18-dic-2026 al 11-ene-2027, así que **contiene a los dos**, y la
exclusión por rangos solapados de `rrhh_feriado` no deja que un feriado viva
adentro de un cierre. Los dos quedan fuera de la tabla por el mismo motivo.

**Por qué es el caso urgente y el 12-oct no.** El 12-oct ya pasó: lo que haya
quedado mal es un descuento a revisar hacia atrás. El 1-ene todavía no, y es el
primer feriado de pago obligatorio del año nuevo. Mientras no esté cargado:

- `rrhh_feriado_paga_doble('2027-01-01')` devuelve **false**, así que si alguien
  trabaja ese día el pago doble **no se puede cargar** — el trigger lo rechaza;
- y `rrhh_es_dia_descontable('2027-01-01')` devuelve **true**, así que a quien
  falte ese día **se le descuenta**, siendo un feriado pagado.

Las dos cosas van en la dirección que le cuesta plata a la persona.

**La decisión es la misma que para el 25-dic, y es de Lorena:** partir el cierre
de planta en tramos para que los dos feriados existan como filas propias
(18–24 dic · **25-dic** · 26-dic–31-dic · **1-ene** · 2–11 ene), o dejar la regla
del pago doble sin poder dispararse. Se ve en la pantalla «Días cerrados», así que
no es un efecto secundario de un pegado.

> **16-oct-2026 · Lorena eligió PARTIR EL CIERRE (opción A).** Esto **reemplaza** el
> párrafo de arriba, que dejaba la segunda salida abierta (opción B: no partirlo y
> que la regla del pago doble no pudiera dispararse). El párrafo queda a la vista a
> propósito: sin él no se entiende contra qué se decidió.
>
> Los cinco tramos, como los fijó: **18–24 dic** (cierre) · **25-dic** (feriado,
> `pago_obligatorio = true`) · **26–31 dic** (cierre) · **1-ene-2027** (feriado,
> `pago_obligatorio = true`) · **2–11 ene** (cierre). Los tres tramos de cierre
> conservan el tratamiento que tienen hoy.
>
> Va en un pegado **aparte y posterior** al de la fórmula, porque necesita la
> columna `pago_obligatorio`: `PERSONAL_CIERRE_TRAMOS.sql`. Escrito y ensayado el
> 16-oct, **sin aplicar**.
>
> **16-oct-2026 · el rango original, para que quede registrado:** el cierre de
> planta era **una sola fila** de `rrhh_feriado`, del **18-dic-2026 al
> 11-ene-2027** — 25 días corridos, sembrada por `PERSONAL_CALENDARIO.sql`. Se
> parte en cinco tramos **para poder cargar el 25-dic y el 1-ene como feriados de
> pago obligatorio**, que es lo único que la exclusión por rangos solapados no
> permitía mientras fueran una fila. Los 25 días cerrados siguen siendo los
> mismos: el candado los compara día por día antes y después, y el ensayo lo
> verificó (prueba 1, `0 · 0 · 25`). Nada se borra de esta nota: el rango original
> es el dato contra el que se compara si algún día hay que deshacerlo.

### Lo que sí quedó arreglado

El ensayo ahora mide el caso «feriado» con el **1-dic-2026**, que es martes y sí
está cargado, así que la prueba se apoya en un dato real. Y el candado del pegado
10 también: preguntaba por el 12-oct y **pasaba porque el 12-oct es lunes**, no
porque fuera feriado — una salvaguarda que pasa por el motivo equivocado no está
probando lo que dice probar.

---

## P10 · ✅ CONFIRMADA POR LORENA · La regla de feriados, y de quién viene

Regla confirmada por **Lorena el 19-oct-2026** — un feriado de pago obligatorio en
día no laborable no cambia nada, el doble corre solo si cae en día laboral **y** la
persona trabaja, y solo pagan doble los obligatorios —; el cálculo **cumple los
cuatro casos**, medido con `PRUEBAS_FERIADOS_REGLA.sql`, que corrió en producción el
**20-oct-2026 con TODO VERDE, 14/14** y rollback. ⚠️ La fuente es Lorena: **no está
confirmado que la contadora haya confirmado esta regla.**

---

## P11 · 🟠 ABIERTO · El selector de origen de la incapacidad arranca SIEMPRE vacío (va con la opción A)

**Síntoma exacto:** en la bandeja de aprobación de las socias (Calendario), cuando
una solicitud es una incapacidad, el **selector de origen arranca vacío** aunque la
empleada haya elegido «enfermedad» o «accidente de trabajo» al pedirla; y el renglón
nunca muestra el paréntesis con el origen. **No da ningún error**, por eso nadie lo
reportó.

**Causa**, medida el 20-oct-2026: `index.html:6813` lee `v_rrhh_permiso` **sin pedir**
`incapacidad_origen` ni `incapacidad_boleta`, pero las mapea igual en 6825. PostgREST
solo falla con las columnas que uno NOMBRA, así que las dos llegan `undefined` en
silencio. `_perOrgCur` (6884) cae entonces a `s.origen||null` = null y el selector
abre sin nada marcado. La raíz es la misma que el bug de «Mis solicitudes» que arregló
b114: **`v_rrhh_permiso` nunca tuvo la columna `incapacidad_origen`** — está en la
tabla `rrhh_permiso` y en `v_rrhh_permiso_dia`, no en esa vista.

**Por qué no se arregló en b114.** Decisión de Lorena (20-oct): opción B ahora —una
línea, que devuelve la lista y el botón Cancelar— y opción A después. Arreglar esto
requiere **A**: agregarle la columna a la vista con `create or replace view ... ,
pm.incapacidad_origen` **al final** (sólo se puede agregar al final), y en el mismo
cambio ampliar el `select` de 6813. Es un cambio de esquema sobre una columna de
**datos de salud**, con la decisión de privacidad todavía abierta, y por eso no se
apuró. Hay que decidir explícitamente si `incapacidad_boleta` entra o no.

⚠️ El renglón de 7525 en «Mis solicitudes» quedó leyendo `s.origen`, que hoy es
`undefined`, y **está bien así**: degrada a «Incapacidad» sin paréntesis (probado,
`armar_prueba_render.py` lo mide desde b114) y vuelve a tener sentido solo cuando A
devuelva la columna. Borrarlo ahora obligaría a reescribirlo en A.

---

## P4 · 🔴 ABIERTO · Cualquier cuenta con sesión puede VACIAR nueve tablas de Personal

Encontrado el **16-oct-2026**, reproducido contra PostgreSQL 17 con la
configuración de Supabase. Es lo más grave anotado en este archivo.

### Qué pasa

Supabase trae configurado `alter default privileges in schema public grant all on
tables to anon, authenticated, service_role`. **Toda tabla nueva nace con TODOS
los privilegios** para esos tres roles. Un `grant select, insert` después no quita
nada: agrega sobre lo que ya estaba.

`PERSONAL_ESQUEMA.sql:663` revoca **solo de `anon`**. Así que `authenticated` —el
rol de cualquier persona con sesión abierta, sea del equipo o socia— conserva
`UPDATE`, `DELETE` y `TRUNCATE` sobre las nueve tablas de Personal, incluida
`rrhh_salario`.

### Por qué el `truncate` es distinto del resto

Para `update` y `delete` da igual: sin política permisiva afectan **0 filas**. La
seguridad por filas aguanta.

**El `truncate` no lo frena la seguridad por filas.** No borra filas una por una:
vacía la tabla, y las políticas no lo ven pasar. Medido:

```
update → 0 filas · delete → 0 filas · TRUNCATE → PASÓ, la tabla quedó vacía
```

O sea: una cuenta del equipo con sesión abierta puede vaciar el histórico de
salarios de un solo comando, y no hay nada que lo registre.

### Qué falta, y qué ya está hecho

- **Hecho:** `PERSONAL_NETO_QUINCENA.sql` (pegado 10, sin aplicar) revoca de
  `anon` **y de `authenticated`**, y su candado verifica los tres privilegios en
  las dos tablas nuevas. Las dos tablas del neto nacen cerradas.
- **Falta:** el mismo `revoke` sobre las nueve tablas ya aplicadas. Es un pegado
  propio, corto, y hay que revisar antes si algún camino del código escribe por
  `update` en alguna de ellas — `rrhh_permiso` sí tiene política de `UPDATE`
  (`rrhh_permiso_upd`), así que ahí el `revoke` tiene que dejar el `update` puesto
  y quitar solo `delete` y `truncate`.
- **Y revisar los otros módulos:** Entregas, Compras, Finanzas y Tickets tienen
  tablas en el mismo esquema, creadas con el mismo default. El problema no es de
  Personal, es del esquema entero.

### Lo primero al retomarlo

Medir, no suponer: `select relname, has_table_privilege('authenticated',
oid,'TRUNCATE') from pg_class where relnamespace='public'::regnamespace and
relkind='r'` dice exactamente cuántas tablas están así.

---

## P6 · ✅ APLICADO · La fórmula del neto, los netos reales y el cierre en cinco tramos

**16-oct-2026 · aplicado en producción por Lorena, en este orden y con su fila de
control verificada cada uno.** Nada de esto está publicado en `main`: lo que
cambió es la **base**, no la pantalla.

| paso | archivo | qué quedó | cómo se verificó |
|---|---|---|---|
| 2 | `PERSONAL_NETO_QUINCENA.sql` | el neto de quincena pasa a ser un **dato**; valor del día = neto ÷ días hábiles de esa quincena | fila de control completa + ensayo de 35 pruebas, todo verde |
| 3 | `PEGADO_NETO_QUINCENA.sql` *(no está en el repo)* | los tres netos cargados con vigencia **1-oct-2026** | `cuadra = sí` en las tres personas, divisor **11** |
| 5 | `PERSONAL_CIERRE_TRAMOS.sql` | el cierre partido en **cinco tramos**; el 25-dic y el 1-ene como feriados de pago obligatorio | **25 días** cerrados antes y después, sin cambios · ensayo de 12 pruebas, todo verde |

El paso 1 y el 4 eran los ensayos con `rollback` de cada pegado, y los dos dieron
verde en producción antes de aplicar nada.

> **19-oct-2026 · `PERSONAL_CANCELAR_SOLICITUD.sql` (pegado 9) está APLICADO.**
> Verificado con la consulta de solo lectura que vive en el encabezado de ese
> archivo: dio **`1 · 1 · 2`** — la función `rrhh_cancelar_solicitud` existe, el
> CHECK de `estado` ya acepta `'cancelado'`, y los dos triggers anti repetidas
> están puestos. Aplicado y completo, no a medias.
>
> **Y durante cuatro días este repo dijo lo contrario.** El encabezado de ese
> archivo decía «NO SE CORRIÓ» porque lo escribí el 15-oct y nunca lo volví a
> tocar; en la respuesta del 19-oct lo di como «no consta que esté aplicado»
> basándome en esa misma marca. Era falso, y de ese dato dependía si se podía
> construir el botón «Cancelar» de «Mis solicitudes» — o sea que la marca mal
> puesta **frenó trabajo** cuatro días. No se borra ninguna de las dos notas: la
> lección es que **una marca escrita a mano no es evidencia**, y que lo único que
> sirve es la consulta. Por eso la consulta se queda en el archivo y la marca la
> cita, en vez de afirmar por su cuenta.

**Lo que esto cambió de fondo:** se fue el `÷15`, el `÷30` y la rebaja del 6,49 %
que salía de una observación y nunca cuadró para las tres personas. Ahora el neto
es el dato y de ahí sale todo. `rrhh_salario` quedó intacta: sigue siendo la
historia del bruto.

**Lo que queda abierto, y está anotado aparte:** P5 (dónde vive el archivo con los
tres sueldos), P3 (los feriados sin cargar y las dos listas que no coinciden) y
P4 (el `truncate` en las nueve tablas ya aplicadas). Y en la pantalla: la pestaña
de Pago todavía no lee las columnas nuevas y el renglón de «feriado trabajado» se
rotula como «Ajuste» — ver el final de esta nota en la rama `mis-solicitudes-b98`.

---

## P9 · 🗑️ BORRADA · la rama `personal-b108`, y como recrearla

**Borrada del remoto el 19-oct-2026**, por pedido de Andrea y con OK de Lorena: su
`/retomar` la leía y avisaba de un número de BUILD repetido.

> **SHA: `138ae37c24e8f07632165e1cdcde08c3331b5df9`**
> `b108: cancelar lo propio, y la pestaña de Pago al dia con el neto fijo`
> Lorena Madrid · 19-oct-2026 13:50:00 −0600

**Se puede recrear con ese SHA:** `git branch personal-b108 138ae37c`. Y aunque no
se recree, el commit **sigue alcanzable desde `main`**: medido antes de borrar,
`git merge-base --is-ancestor` dice que es ancestro de `main` **y** de
`personal-b109`, y `git rev-list --count personal-b108 --not main personal-b109`
dio **0 commits únicos**. Borrar la rama no perdió nada: solo quitó un nombre.

⚠️ **Una cosa que conviene saber si el aviso del `/retomar` sigue:** hay una
**segunda** rama remota con «b108» en el nombre, **`publicar-b108`**, en
`4921e3f` — que es exactamente el commit que era `main` antes de publicar b109.
Esa es la rama de publicación de **Andrea** y **no se tocó**. Si el aviso del
número repetido persiste, es por esa, y borrarla es decisión de ella.

La rama local ya no existía desde antes: el 19-oct se renombró a `personal-b109`
con `git branch -m`, así que de este lado no quedó nada que borrar.

---

## P8 · ✅ PUBLICADO · Personal en main · BUILD b109 · 19-oct-2026

**Publicado el 19-oct-2026.** `main` pasó de `4921e3f` (b108) a **`7d453fa`**, y
GitHub Pages lo sirve: verificado desde afuera, el archivo servido es idéntico
byte a byte al `index.html` de `main`.

### La autorización

> **OK de Andrea, relayed por Lorena, 19-oct**, para dos cosas:
> **(a)** publicar la pantalla de Personal **sin más pruebas manuales**, y
> **(b)** que Instinct (perfil asistente) vea la pestaña de Pago con **solo el
> total a pagar por persona, sin explicación**.

Queda anotado que llegó **relayed** y no de Andrea directo, porque es el dato que
hace falta si alguna vez se discute qué se autorizó. La regla del proyecto —`main`
solo se mueve con decisión explícita de Andrea— se cumplió por esa vía.

### Qué se publicó

| | |
|---|---|
| rama | `personal-b109` (también empujada a `origin` como respaldo) |
| commit de `main` | **`7d453fa`** |
| `BUILD` | `v 19 oct 2026 · b109: cancelar lo propio en «Mis solicitudes» · Pago de quincena con el neto fijo · Instinct ve solo el total` |
| `main` anterior | `4921e3f` (b108) |

**En la pantalla**, el diff de `index.html` son **28 hunks, todos de Personal**
(revisados a mano los que el clasificador no reconoció: `vPagoQuincena` en
`ACCESO_VISTAS` y el toggle de `solPerm`). Los otros tres archivos que sirve Pages
—`prueba.html` y los dos `correr.js`— **sin cambios**.

- «Mis solicitudes» gana el botón **Cancelar** en lo propio y pendiente, con
  confirmación, anti doble toque por solicitud y «Cancelada por vos».
- La pestaña de **Pago** lee el neto fijo (divisor, valor del día, feriado
  trabajado), rotula «Feriado trabajado» en vez de «Ajuste» y se le fue el aviso
  del 6,49 % que ya no aplica.
- Y para el **asistente** dibuja una lista «persona · total» y nada más.

### Lo que entró además, y conviene saberlo

El merge trajo a `main` **80 archivos que no sirve Pages**: los `.sql` de los
pegados y sus ensayos, las herramientas y la documentación. No cambian ninguna
conducta, pero quedan en el historial público del repo, y entre ellos hay dos
cosas que antes no estaban ahí:

- **`instinct@truefoodcr.com`**, que antes estaba en 0 archivos de `main`
  (`andrea@truefoodcr.com` ya estaba en 10, así que no es una clase nueva de
  exposición, pero sí es nuevo);
- **códigos CABYS y de proveedor** de los ensayos de Compras. Se verificó qué
  eran: **no son datos bancarios**, son del catálogo CABYS, que es público.

**Lo que NO entró:** ni un sueldo (`205000`/`180000`: cero apariciones en el
diff), ni un JWT, ni `service_role`, ni cadenas de conexión.
`PEGADO_NETO_QUINCENA.sql` sigue fuera de git — ver P5.

Lo planteé antes de publicar porque el historial de git no se borra, y Andrea
reafirmó la instrucción de publicar la rama completa. Queda dicho acá para que la
decisión tenga fecha y motivo, no para reabrirla.

### Lo que sostiene esto en la base, aplicado antes y por separado

Pegado 10 (el neto de quincena como dato) · la carga de los tres netos · pegado 11
(el cierre de planta en cinco tramos) · pegado 12 (la puerta angosta del
asistente). Los cuatro con su ensayo en verde y su fila de control verificada
columna por columna.

### Chequeos, antes de tocar `main`

`esquema_check.py` salida **0** —y `v_rrhh_pago_total` sale **cerrada a la anon
key**— · `loadcheck.py` pasa · `sonda_columnas --nuevas`: **0** columnas abiertas
a anon · **33** pruebas de render en verde.

⚠️ **`dev` no se tocó.** Está en `5750edc` y quedó **atrás** de `main`: lo que se
publicó no está ahí. Sincronizarla es una decisión aparte y no se tomó.

---

## P7 · ✅ APLICADO · Instinct ve solo el total a pagar

**19-oct-2026.** Decidido por Andrea (que Instinct vea el Pago, dicho a Lorena) y
precisado por Lorena el mismo día: **solo el total a pagar de cada persona por
quincena**, nada de la explicación. Ni descuentos, ni permisos, ni incapacidades,
ni ajustes, ni notas, ni tarifa, ni divisor, ni desglose.

`PERSONAL_PAGO_ASISTENTE.sql` (pegado 12) y `PRUEBAS_PAGO_ASISTENTE.sql`
—**19 de 19 en verde**, el ensayo en producción— **aplicados el 19-oct**: la fila
de control dio `2 · 0 · 3 · quincena,persona_id,nombre,total · t · f · f · 2 · 0`,
igual a la esperada. La pantalla
ya está en la rama `personal-b109`, y `esquema_check.py` **bloquea la publicación
a propósito** hasta que el pegado entre: la pantalla pide `v_rrhh_pago_total` y
esa vista todavía no existe. Ese es el orden que eligió Lorena (opción B).

### Relación con el ticket de Andrea «permisos por rol»

Este pegado es **un caso particular resuelto a mano de lo que ese ticket quiere
resolver en general.** Hoy el módulo tiene cuatro formas distintas de decir «quién
puede ver qué», y ninguna sabe de las otras:

| mecanismo | dónde vive | quién lo evalúa |
|---|---|---|
| `acceso_es_socia()` / `acceso_es_asistente()` | dentro del cuerpo de cada vista | el **JWT** |
| políticas RLS | por tabla | el rol de Postgres + el JWT |
| `grant` / `revoke` | por tabla y por rol | el **rol** de Postgres |
| `PER_TABS` | la pantalla | `_perEsSocia` / `_perLectora` |

**Lo que este pegado aprendió y el ticket debería heredar:** que `acceso_es_socia()`
mira el **correo del JWT y no el rol**, así que una función `security definer` *no*
esquiva esa guardia — fue el primer diseño y no servía. Y que las dos cosas se
mezclan mal: con `security_invoker`, una vista pública que lee una interna sin
grants choca contra el `revoke` **aunque quien pregunte tenga permiso sobre la
pública**. Las dos las encontré midiendo, no leyendo.

Mientras no exista «permisos por rol», **cada perfil nuevo cuesta un pegado como
este**: una puerta angosta, con su candado y su ensayo. Funciona, y no escala.

### Relación con P4

P4 es el otro lado del mismo problema: `authenticated` conserva `UPDATE`,
`DELETE` y `TRUNCATE` sobre nueve tablas porque el módulo revoca **solo de
`anon`**. Este pegado **no lo arrastra** —las dos vistas `_calc` nacen sin un solo
grant, y el candado lo verifica contra `anon` **y** `authenticated`— pero tampoco
lo arregla para las nueve de antes.

⚠️ **Y agrega una pieza que P4 tiene que mirar cuando se retome:** las dos vistas
`_calc` corren **como su dueño**, así que **no pasan por la RLS**. Su único cierre
es el `revoke`. Si el arreglo de P4 toca los grants del esquema en bloque, tiene
que dejarlas afuera — un `grant select ... to authenticated` sobre ellas le
mostraría a Instinct el desglose entero, que es justo lo que este pegado existe
para evitar. Está dicho en el comentario de cada una, en el pegado.

---

## P5 · 🟡 DECIDE LORENA · Qué hacer con `PEGADO_NETO_QUINCENA.sql`, que ya se usó

Anotado el **16-oct-2026**, el día que se aplicó. **No es una tarea técnica: es una
decisión de Lorena.**

### Qué es ese archivo

El que cargó los tres netos de quincena en producción, con vigencia 1-oct-2026.
**Tiene los tres sueldos adentro**, en texto plano, y el candado que exigió que la
quincena 1–15 de octubre cuadrara al colón con lo que Lorena transfiere.

Ya corrió y ya cumplió. Lo que sigue abierto es dónde vive de acá en adelante.

### Por qué no está en el repo, y tiene que seguir así

El repo de Truefie es **público** y sirve GitHub Pages. Tres sueldos en un commit
quedan en el historial de GitHub para siempre, y un `git rm` después **no los
borra**: siguen en los objetos de git y en cualquier copia que alguien haya
clonado. Por eso el patrón `PEGADO_*.sql` está en `.gitignore` (línea 14), y por
eso este archivo nunca entró.

**Está en el disco local, en la carpeta del proyecto, y ahí sigue.** No se borró
ni se movió: borrarlo perdería el registro de con qué números y con qué vigencia
se cargó, que es justamente lo que hace reconstruible una transferencia ya hecha.

### Las tres salidas, y ninguna es «no hacer nada»

1. **Guardarlo donde van los datos de salarios** — junto a la planilla, en el
   lugar privado que ya use Lorena. Es lo más coherente: el archivo es un
   documento de planilla, no código.
2. **Archivarlo cifrado** en la máquina, fuera de la carpeta del repo. Saca el
   riesgo de que un `git add -f` o una herramienta que ignore `.gitignore` lo
   levante por error.
3. **Dejarlo donde está**, sabiendo que depende de una sola línea de `.gitignore`.
   Funciona hoy —verificado con `git check-ignore` cada vez que se tocó— pero es
   una sola capa, y la regla del proyecto es no depender de una sola.

### Lo que no hay que hacer

- **No borrarlo** sin haber guardado los números en otro lado.
- **No commitearlo**, ni con `git add -f`, ni «solo para tenerlo versionado».
- **No pegarlo en un chat.** La primera línea del archivo lo dice.

Y el mismo criterio vale para cualquier `PEGADO_*.sql` que venga: son archivos de
carga con datos reales, de un solo uso, y el repo no es su lugar.
