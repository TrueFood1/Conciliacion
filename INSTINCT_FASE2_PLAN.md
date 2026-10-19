# Instinct · escrituras con «sí + código» — PLAN (15-oct-2026, corregido y aprobado el 19-oct)

> **Fase 2 CONSTRUIDA en la rama `instinct-fase2` (19-oct), sin publicar ni pegar:** `INSTINCT_FASE2.sql` + su ensayo
> (sin correr), el carril en `truefie-escritura` (rama `instinct-fase2`, `INSUMO_ASISTENTE_ENCENDIDO` apagado) y la
> lista «Hecho por Instinct» (b108). Al construir se corrigió un dato: la huella es de 16 caracteres (64 bits), no 64.

> Nada de esto está hecho. No se tocó Render ni Supabase. Es para que Andrea lo apruebe.
> Primera acción: **crear insumo** (fase 2). La misma forma sirve después para la fase 3: facturar, validar entregas y confirmar OC.

## Decisiones de Andrea

**15-oct, tarde:**
- Para **todas** las fases, la confirmación es el «sí» explícito de Andrea **por WhatsApp**. No hay toque en Truefie.
- Amarre:
  - Cada vista previa lleva un **código corto**.
  - Instinct le lee la vista previa **completa** y Andrea responde **«sí + código»**.
  - Sin el código correcto, o si la vista previa cambió, **no se ejecuta**.
  - Todo queda marcado «hecho por Instinct», con aviso de lo que hizo.

**19-oct:**
- **El código son 4 dígitos, solo números** (0000–9999). Cada vista previa acepta **como máximo 3 intentos** con
  código equivocado; al tercero se invalida y hay que pedir una vista previa nueva.
- **Credencial de Odoo:** Instinct sigue entrando a Odoo con el usuario de Andrea durante las fases 2 y 3. El acceso
  directo se le quita en el **último paso de la fase 3**, cuando `/venta` ande en producción. Ver «Instinct y Odoo».

## Cómo es hoy (medido el 15-oct)

- **En Supabase**, Instinct entra con su propia sesión (perfil `asistente`). Ve todo y no escribe nada: hay políticas RESTRICTIVAS en cada tabla.
- **En el servicio de escritura** (`truefie-escritura`), cada ruta pasa por `_sesion_socia()` y devuelve 403 `sin_rol`.
- **El carril `/insumo`** ya existe:
  1. Una propuesta en `compra_insumo_propuesta`.
  2. La vista previa con `huella`.
  3. El create, con lectura de vuelta, nota en el chatter y rastro en `compra_insumo_odoo`.
- El servicio **no guarda estado**: entra a Supabase con el token de quien llama. Por eso los intentos del código
  necesitan una tabla propia (abajo).
- ⚠️ **Instinct YA escribe en Odoo por fuera de todo esto.** El 15-oct creó el presupuesto **S02447** (Automercado)
  directo en Odoo, con la identidad de **Andrea** (`create_uid` 23), sin ninguna marca de Instinct. Andrea decidió
  dejar ese acceso hasta el final de la fase 3: ver «Instinct y Odoo».

## El código de confirmación

- **Qué es.** 4 dígitos, solo números (0000–9999). Ejemplo: `4821`.
- **De dónde sale.** De la `huella` que ya calcula el servidor (sha256 de la propuesta y de lo que se escribiría en
  Odoo), mezclada con el **número de esa vista previa**:
  - código = los primeros 32 bits de `sha256(huella · id de la vista previa)`, módulo 10.000, con ceros a la izquierda;
  - si sale igual al código de una vista previa anterior **de la misma propuesta**, se vuelve a sacar (con un
    contador al final) hasta que sea distinto.
  - Así, pedir una vista previa nueva **siempre** da un código nuevo, aunque la propuesta no haya cambiado.
- **Cómo amarra.** La huella cambia si cambia cualquier dato: nombre, unidad, IVA, Cabys, proveedor o precio en fase 2;
  cliente, productos, cantidades, precio o descuento en fase 3.
- **Cada vista previa queda anotada** en `asistente_vista_previa`: propuesta, huella, código, quién y cuándo.
  **Vale solo la última de cada propuesta**: pedir una nueva invalida las anteriores.
- **Lo que pide el servidor.** Para ejecutar exige `{propuesta_id, confirmar:true, vista_previa_id, huella, codigo}`.
  Los chequeos van en este orden; el primero que falla corta:
  1. La vista previa es la **última** de esa propuesta → si no, **409 `vista_previa_vieja`**.
  2. Tiene **menos de 3 intentos fallidos** → si no, **409 `vista_previa_agotada`**: hay que pedir otra.
  3. Recalcula la vista previa **desde cero** y la huella tiene que ser la misma → si no, **409 `huella_vieja`**.
  4. El código coincide con el de esa vista previa → si no, anota el intento y **409 `codigo_incorrecto`**, diciendo
     cuántos quedan. El tercero la invalida.
  5. Recién ahí ejecuta.
- **Los 3 intentos.** Cada código equivocado es una fila en `asistente_intento`, append-only. Ni Instinct ni nadie
  puede borrar intentos. Instinct sí podría agregar filas, pero eso solo lo bloquea a él. Con 3 intentos, la chance de
  acertar un código al azar es 3 en 10.000 por vista previa.
- **Qué prueba y qué no.** El código prueba **qué** vista previa se aprobó. **No** prueba que Andrea haya dicho que sí,
  porque Instinct también ve el código. Eso queda en la palabra de Instinct. Así lo decidió Andrea, y por eso el aviso
  de abajo va por un camino que Instinct no controla.

### Si dos vistas previas dan el mismo código

Con 10.000 códigos posibles, dos vistas previas distintas **pueden** dar el mismo número. Eso no alcanza para ejecutar
la equivocada, por tres razones:

1. **El código nunca elige qué se ejecuta.** Lo que se ejecuta lo nombra la vista previa (su id y su huella), y el
   servidor la recalcula desde cero. El código solo se compara contra **esa** vista previa. Un «sí 4821» que vale para
   la propuesta A no hace nada sobre la propuesta B: B tiene su propio código y se compara contra el suyo.
2. **Si la vista previa cambió entre que Instinct la leyó y el «sí», la frena la huella, no el código.** La huella es
   los primeros 16 caracteres de un sha256 (64 bits: una coincidencia por azar es de 1 en 18 trillones), y
   cualquier cambio de dato da otra. Ese chequeo va **antes** que el del código,
   así que una coincidencia de 4 dígitos nunca llega a importar.
3. **Dentro de la misma propuesta no puede haber coincidencia.** Una vista previa nueva invalida las anteriores y
   tiene, por construcción, un código distinto de todos los de antes. Un «sí» dado a la vieja no pasa en la nueva.

**Lo que queda:** entre propuestas **distintas**, una coincidencia solo serviría si Instinct ejecuta una propuesta
diferente de la que le leyó a Andrea. Eso el código nunca lo impidió, porque Instinct ve todos los códigos. Lo cubren el
rastro y el aviso: cada ejecución deja la vista previa completa con su código, a la vista de Andrea en Odoo y en Truefie.

## El flujo (fase 2, crear insumo)

```
Instinct arma la propuesta ──► fila en compra_insumo_propuesta (creado_por = instinct@…)
        │
        ▼
POST /insumo {propuesta_id}  ──► vista previa + huella + código (solo lee Odoo;
        │                        anota la vista previa en asistente_vista_previa)
        ▼
Instinct le lee a Andrea la vista previa COMPLETA y el código
        │
        ▼
Andrea: «sí 4821»   (cualquier otra cosa = no)
        │
        ▼
POST /insumo {propuesta_id, confirmar:true, vista_previa_id, huella, codigo}
        │       ├─ código equivocado → intento anotado (al 3.º, vista previa nueva)
        ▼       └─ vista previa vieja o cambiada → no ejecuta
crea en Odoo ──► Rastro «hecho por Instinct · sí 4821» + aviso
```

## Lo que cambiaría

### Supabase (un SQL con su ensayo)

1. **`asistente_permiso`** — ⚠️ corregido el 19-oct: **ya existe** (ASISTENTE_ROL.sql, 12-oct, vacía) con la columna
   `capacidad`, y `asistente_puede(p_capacidad)` también. Se usan tal cual, sin tocarlas:
   - Columnas: `accion` ('crear_insumo'; más adelante 'facturar', 'validar_entrega', 'confirmar_oc'), `encendido`, `creado_por`, `creado_en`.
   - Solo una socia inserta. Sin filas = apagado.
   - `asistente_puede(accion)` exige además que `asistente_bloqueado()` sea falso: el interruptor general sigue mandando.
2. **`asistente_vista_previa`** (tabla nueva, append-only): `id`, `accion`, `propuesta_id`, `huella`, `codigo`,
   `creado_por`, `creado_en`.
   - El asistente inserta las de **sus** propuestas, con el permiso de esa acción encendido.
   - Nadie actualiza ni borra.
3. **`asistente_intento`** (tabla nueva, append-only): `vista_previa_id`, `creado_por`, `creado_en`.
   - Una fila por código equivocado. El asistente inserta, nadie actualiza ni borra.
   - La cuenta (3 = agotada) la hace el servidor al ejecutar.
4. **`compra_insumo_propuesta`**: se cambia **solo en esta tabla** la restrictiva `asistente_no_inserta` por `NOT acceso_es_asistente() OR asistente_puede('crear_insumo')`. Además, una política permisiva para que el asistente inserte las suyas (`creado_por` = su correo). Las otras tablas que ya existen quedan igual.
5. **`compra_insumo_odoo`**:
   - Columnas nuevas `hecho_por_asistente bool`, `vista_previa_id` y `codigo text`.
   - El asistente puede insertar el rastro de **su** propuesta, con el permiso encendido.

### Render (`truefie-escritura`), en una rama con su ensayo

- `_sesion_socia()` queda igual para **todas** las rutas.
- Solo `/insumo` usa `_sesion_insumo()`, que acepta a una socia (como hoy, sin código) o al asistente si se cumplen cinco condiciones:
  - a. `INSUMO_ASISTENTE_ENCENDIDO=si`: **interruptor propio, apagado por defecto**.
  - b. `asistente_puede('crear_insumo')` con su token.
  - c. La propuesta es suya.
  - d. Al confirmar, pasan los cuatro chequeos del código (vista previa vigente, sin agotar, huella, código).
  - e. `INSUMO_ENCENDIDO=si`, como siempre.
- La vista previa del asistente devuelve `vista_previa_id` y `codigo`, y la anota.

### El aviso de lo que hizo, por un camino que no es Instinct

- **En Odoo:** la nota del chatter «Creado desde Truefie por Instinct (asistente) · confirmado por WhatsApp con el código 4821 · propuesta N». Andrea sigue el producto o el documento, así que le llega la notificación de Odoo aunque Instinct no diga nada.
- **En Truefie:** una lista «Hecho por Instinct» (hoy y los últimos 7 días) en el inicio de las socias, que sale de los rastros. Un «sí» que Andrea no dio se ve ahí al día siguiente.
- **Instinct** además se lo cuenta por WhatsApp en el momento.

## Fase 3 (misma forma, a construir después de que la fase 2 ande)

| Acción | Vista previa que Instinct le lee | Carril |
|---|---|---|
| Presupuesto + factura | cliente, productos, cantidades, **precio y descuento de las listas de Odoo** (nunca escritos a mano), total con IVA | nuevo `/venta` |
| Validar entrega | pedido, albarán, lo que sale por producto | `/validar` (existe) |
| Confirmar OC | proveedor, líneas, día, total | `/pedir` (existe) |

Cada una con su permiso en `asistente_permiso` y su interruptor en Render, apagados por defecto, y con el mismo código
de 4 dígitos y los mismos 3 intentos.

**Último paso de la fase 3:** cuando `/venta` ande en producción, se le quita a Instinct el acceso directo a Odoo. Ver
«Instinct y Odoo».

## Instinct y Odoo (decidido por Andrea el 19-oct)

> **Mientras exista el acceso directo, el «sí + código» deja registro pero no frena a Instinct en Odoo.**

- **Durante las fases 2 y 3**, Instinct sigue entrando a Odoo con el **usuario de Andrea**, como hoy.
  - Lo que haga por los carriles de Truefie queda con código, rastro y aviso.
  - Lo que haga directo en Odoo queda como hecho por Andrea (`create_uid` 23), sin marca de Instinct, como S02447.
- **Requisito antes de quitarlo:** identificar con qué credencial **exacta** entra hoy Instinct, para saber qué se
  revoca:
  - **Clave API de Andrea:** Andrea la ve en Odoo → Mi perfil → Seguridad de la cuenta → Claves API (nombre y fecha de
    cada una). Revocar es borrar **esa** clave sola.
  - **Contraseña de Andrea:** revocar es cambiar la contraseña. Eso cierra también las otras sesiones de Andrea y
    cualquier otra cosa que use esa contraseña.
  - Para saber cuál es, Andrea revisa las claves API y le pregunta a Instinct con qué entra. El lector (uid 28) no
    puede verlo: no ve las claves API de otros usuarios, y Odoo SaaS no muestra sesiones.
- **Último paso de la fase 3**, cuando `/venta` (presupuesto y factura) ande en producción: se revoca esa credencial
  y se comprueba que Instinct ya no entra a Odoo con ella. Desde ahí, todo lo que haga pasa por `truefie-escritura`.
- Aparte de este plan: en la hoja de ruta sigue el usuario de Odoo propio **para el servicio** («Truefie»), para que
  el autor en Odoo deje de ser Andrea en todo lo que entra por Truefie.

## Permisos nuevos del perfil asistente (fase 2)

| Dónde | Hoy | Con el plan |
|---|---|---|
| `compra_insumo_propuesta` | lee | lee + **inserta las suyas**, con el permiso encendido |
| `compra_insumo_odoo` | lee | lee + el rastro de lo que creó |
| `asistente_vista_previa`, `asistente_intento` | — (no existen) | lee + inserta las de **sus** propuestas; nunca cambia ni borra |
| `/insumo` (Render) | 403 | vista previa y creación de **sus** propuestas, con los dos interruptores y «sí + código» |
| las otras tablas, `/validar`, `/trasladar`, `/pedir`, `/tarifas`, `/barrido`, `/quien` | solo lectura / 403 | **igual** |
| **Odoo directo** | ⚠️ escribe como Andrea (S02447) | **igual hasta el último paso de la fase 3** |

## Cómo se prueba que fuera de esa acción sigue en solo lectura

1. **Ensayo SQL (termina en ROLLBACK)**, haciéndose pasar por Instinct (`request.jwt.claims` con su correo):
   - Un INSERT en **cada** tabla de `public`. Espera 42501 en todas menos `compra_insumo_propuesta`,
     `asistente_vista_previa` y `asistente_intento`, y ahí solo con el permiso encendido y sobre sus propuestas.
   - Una propuesta con `creado_por` de otra persona: 42501.
   - UPDATE y DELETE en `asistente_vista_previa` y `asistente_intento`: rechazados, para todos.
   - Cada RECHAZA se lee **por el motivo** (regla del 24-sep).
2. **Ensayo del servidor** (`ensayo.py`):
   - Asistente en las otras cinco rutas: 403.
   - `/insumo` con el interruptor apagado: 403.
   - Sin código, o con una vista previa que cambió (huella vieja): 409.
   - Código equivocado: 409 `codigo_incorrecto` con 2 y después 1 intento restante; al tercero, 409
     `vista_previa_agotada`, y el código bueno **ya no** ejecuta esa vista previa.
   - Vista previa nueva después de agotada: código distinto, y con el código nuevo ejecuta.
   - Una vista previa anterior de la misma propuesta: 409 `vista_previa_vieja`, aunque el código sea el suyo.
   - Código de la propuesta A sobre la propuesta B: 409.
   - Sobre una propuesta de socia: 403.
   - Todo en regla: crea, y el rastro dice «hecho por Instinct» con su código.
3. **`verificar_instinct.py` extendido**, con la sesión real de Instinct y corrido por Andrea: los 15 chequeos de hoy más los de este carril.
4. **Apagar en un minuto**, cualquiera de las tres llaves por separado:
   - `asistente_permiso`.
   - `INSUMO_ASISTENTE_ENCENDIDO`.
   - `asistente_interruptor`.
5. **Al cerrar la fase 3:** con la credencial revocada, comprobar que Instinct ya no entra a Odoo con ella.

## Orden de despliegue, cada paso con OK de Andrea

**Fase 2 (crear insumo):**
1. SQL + ensayo → pegado → verificación desde afuera.
2. Rama `insumo-asistente` en `truefie-escritura` + ensayo → merge → Render, **con `INSUMO_ASISTENTE_ENCENDIDO` apagado**.
3. Truefie: la lista «Hecho por Instinct» → publicar.
4. `verificar_instinct.py` con la sesión real.
5. Encender: el permiso y el interruptor.
6. Primer insumo real: Instinct lee, Andrea responde «sí + código».

**Fase 3 (con la misma forma, cada carril por separado):**
7. `/venta` (presupuesto y factura), `/validar` y `/pedir` para el asistente, cada uno con su SQL, ensayo, interruptor
   apagado, verificación y encendido.
8. Identificar con qué credencial exacta entra hoy Instinct a Odoo (clave API o contraseña de Andrea).
9. **Último paso:** con `/venta` andando en producción, revocar esa credencial y comprobar que ya no entra. Desde ahí,
   todo lo de Instinct pasa por `truefie-escritura`.
