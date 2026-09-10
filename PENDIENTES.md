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
