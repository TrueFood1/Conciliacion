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
