# Instinct · escrituras con «sí + código» — PLAN (15-oct-2026, sin construir)

> Nada de esto está hecho. No se tocó Render ni Supabase. Es para que Andrea lo apruebe.
> Primera acción: **crear insumo** (fase 2). La misma forma sirve después para la fase 3: facturar, validar entregas y confirmar OC.

## Decisión de Andrea (15-oct, tarde)

- Para **todas** las fases, la confirmación es el «sí» explícito de Andrea **por WhatsApp**. No hay toque en Truefie.
- Amarre:
  - Cada vista previa lleva un **código corto**.
  - Instinct le lee la vista previa **completa** y Andrea responde **«sí + código»**.
  - Sin el código correcto, o si la vista previa cambió, **no se ejecuta**.
  - Todo queda marcado «hecho por Instinct», con aviso de lo que hizo.

## Cómo es hoy (medido el 15-oct)

- **En Supabase**, Instinct entra con su propia sesión (perfil `asistente`). Ve todo y no escribe nada: hay políticas RESTRICTIVAS en cada tabla.
- **En el servicio de escritura** (`truefie-escritura`), cada ruta pasa por `_sesion_socia()` y devuelve 403 `sin_rol`.
- **El carril `/insumo`** ya existe:
  1. Una propuesta en `compra_insumo_propuesta`.
  2. La vista previa con `huella`.
  3. El create, con lectura de vuelta, nota en el chatter y rastro en `compra_insumo_odoo`.
- ⚠️ **Pero Instinct YA escribe en Odoo por fuera de todo esto.** El 15-oct creó el presupuesto **S02447** (Automercado) directo en Odoo, con la identidad de **Andrea** (`create_uid` 23), sin ninguna marca de Instinct. Ver «El presupuesto del 15-oct» abajo: esa puerta hay que cerrarla antes de abrir las de este plan.

## El código corto

- **Qué es.** Salen 4 caracteres de la `huella` que ya calcula el servidor (sha256 de la propuesta y de lo que se escribiría en Odoo), en un alfabeto sin letras confundibles (sin 0/O, 1/I/L). Ejemplo: `K7Q2`.
- **Cómo amarra.** La huella cambia si cambia cualquier dato: nombre, unidad, IVA, Cabys, proveedor o precio en fase 2; cliente, productos, cantidades, precio o descuento en fase 3. Si cambia la huella, cambia el código.
- **Lo que pide el servidor.** Para ejecutar exige `{propuesta_id, confirmar:true, huella, codigo}`:
  - Recalcula la vista previa desde cero.
  - Si la huella no es la misma: **409 `huella_vieja`**.
  - Si el código no es el de esa huella: **409 `codigo_incorrecto`**.
- **Qué prueba y qué no.** El código prueba **qué** vista previa se aprobó. **No** prueba que Andrea haya dicho que sí, porque Instinct también ve el código. Eso queda en la palabra de Instinct. Así lo decidió Andrea, y por eso el aviso de abajo va por un camino que Instinct no controla.

## El flujo (fase 2, crear insumo)

```
Instinct arma la propuesta ──► fila en compra_insumo_propuesta (creado_por = instinct@…)
        │
        ▼
POST /insumo {propuesta_id}  ──► vista previa + huella + código (solo lee Odoo)
        │
        ▼
Instinct le lee a Andrea la vista previa COMPLETA y el código
        │
        ▼
Andrea: «sí K7Q2»   (cualquier otra cosa = no)
        │
        ▼
POST /insumo {propuesta_id, confirmar:true, huella, codigo} ──► crea en Odoo
        │
        ▼
Rastro «hecho por Instinct · sí K7Q2» + aviso
```

## Lo que cambiaría

### Supabase (un SQL con su ensayo)

1. **`asistente_permiso`** (tabla nueva, append-only, igual que `asistente_interruptor`):
   - Columnas: `accion` ('crear_insumo'; más adelante 'facturar', 'validar_entrega', 'confirmar_oc'), `encendido`, `creado_por`, `creado_en`.
   - Solo una socia inserta. Sin filas = apagado.
   - `asistente_puede(accion)` exige además que `asistente_bloqueado()` sea falso: el interruptor general sigue mandando.
2. **`compra_insumo_propuesta`**: se cambia **solo en esta tabla** la restrictiva `asistente_no_inserta` por `NOT acceso_es_asistente() OR asistente_puede('crear_insumo')`. Además, una política permisiva para que el asistente inserte las suyas (`creado_por` = su correo). Las otras 60 tablas quedan igual.
3. **`compra_insumo_odoo`**:
   - Columnas nuevas `hecho_por_asistente bool` y `codigo text`.
   - El asistente puede insertar el rastro de **su** propuesta, con el permiso encendido.

### Render (`truefie-escritura`), en una rama con su ensayo

- `_sesion_socia()` queda igual para **todas** las rutas.
- Solo `/insumo` usa `_sesion_insumo()`, que acepta a una socia (como hoy, sin código) o al asistente si se cumplen cinco condiciones:
  - a. `INSUMO_ASISTENTE_ENCENDIDO=si`: **interruptor propio, apagado por defecto**.
  - b. `asistente_puede('crear_insumo')` con su token.
  - c. La propuesta es suya.
  - d. Al confirmar, la huella **y** el código son correctos.
  - e. `INSUMO_ENCENDIDO=si`, como siempre.
- La vista previa del asistente devuelve `codigo`.

### El aviso de lo que hizo, por un camino que no es Instinct

- **En Odoo:** la nota del chatter «Creado desde Truefie por Instinct (asistente) · confirmado por WhatsApp con el código K7Q2 · propuesta N». Andrea sigue el producto o el documento, así que le llega la notificación de Odoo aunque Instinct no diga nada.
- **En Truefie:** una lista «Hecho por Instinct» (hoy y los últimos 7 días) en el inicio de las socias, que sale de los rastros. Un «sí» que Andrea no dio se ve ahí al día siguiente.
- **Instinct** además se lo cuenta por WhatsApp en el momento.

## Fase 3 (misma forma, a construir después de que la fase 2 ande)

| Acción | Vista previa que Instinct le lee | Carril |
|---|---|---|
| Presupuesto + factura | cliente, productos, cantidades, **precio y descuento de las listas de Odoo** (nunca escritos a mano), total con IVA | nuevo `/venta` |
| Validar entrega | pedido, albarán, lo que sale por producto | `/validar` (existe) |
| Confirmar OC | proveedor, líneas, día, total | `/pedir` (existe) |

Cada una con su permiso en `asistente_permiso` y su interruptor en Render, apagados por defecto.

## Permisos nuevos del perfil asistente (fase 2)

| Dónde | Hoy | Con el plan |
|---|---|---|
| `compra_insumo_propuesta` | lee | lee + **inserta las suyas**, con el permiso encendido |
| `compra_insumo_odoo` | lee | lee + el rastro de lo que creó |
| `/insumo` (Render) | 403 | vista previa y creación de **sus** propuestas, con los dos interruptores y «sí + código» |
| las otras 60 tablas, `/validar`, `/trasladar`, `/pedir`, `/tarifas`, `/barrido`, `/quien` | solo lectura / 403 | **igual** |
| **Odoo directo** | ⚠️ **hoy escribe como Andrea** (S02447) | **cerrado**: ver abajo |

## Cómo se prueba que fuera de esa acción sigue en solo lectura

1. **Ensayo SQL (termina en ROLLBACK)**, haciéndose pasar por Instinct (`request.jwt.claims` con su correo):
   - Un INSERT en **cada** tabla de `public`. Espera 42501 en todas menos `compra_insumo_propuesta`, y ahí solo con el permiso encendido.
   - Una propuesta con `creado_por` de otra persona: 42501.
   - Cada RECHAZA se lee **por el motivo** (regla del 24-sep).
2. **Ensayo del servidor** (`ensayo.py`):
   - Asistente en las otras cinco rutas: 403.
   - `/insumo` con el interruptor apagado: 403.
   - Sin código, con código equivocado, o con código de una huella vieja: 409.
   - Sobre una propuesta de socia: 403.
   - Todo en regla: crea, y el rastro dice «hecho por Instinct».
3. **`verificar_instinct.py` extendido**, con la sesión real de Instinct y corrido por Andrea: los 15 chequeos de hoy más los de este carril.
4. **Odoo:** la credencial con la que Instinct escribió el 15-oct revocada, y comprobado que con lo que le queda no puede escribir (un `create` de prueba que tiene que rebotar).
5. **Apagar en un minuto**, cualquiera de las tres llaves por separado:
   - `asistente_permiso`.
   - `INSUMO_ASISTENTE_ENCENDIDO`.
   - `asistente_interruptor`.

## El presupuesto del 15-oct y cómo se ordena Odoo — OPCIONES (Andrea decide)

**Lo medido (solo lectura):**
- **S02447**, Automercado, borrador, `client_order_ref` A004083826-1 (la OC de Automercado), 6 líneas con la tarifa «Automercado (CRC)» y 12,6 % de descuento, ₡1.323.660,32.
- `create_uid` = **23 (Andrea)** en la orden, las líneas y la nota del chatter. **No hay marca de Instinct**: ni nota, ni origen, ni fuente o medio.
- Las líneas nacieron en el mismo segundo que la orden, así que no se distingue si fue por API o por pantalla.
- Qué credencial usó **no se puede ver con el lector**: no ve las claves API de otros usuarios, y Odoo SaaS no expone sesiones. Andrea lo puede ver en Odoo → Mi perfil → Seguridad de la cuenta → Claves API.

**Las opciones:**

- **1 · Usuario de Odoo propio para Instinct.**
  - Odoo marca solo lo que hace (`create_uid` = Instinct).
  - Pero:
    - cuesta una licencia de usuario interno;
    - los grupos de Odoo son gruesos: «Ventas / usuario» crea y confirma pedidos, no hay un «solo borradores»;
    - **ninguna** de las cercas de Truefie (vista previa, código, precios de lista, interruptores) estaría en el medio.
  - Sería un segundo camino de escritura que vigilar.
- **2 · Todo por `truefie-escritura` (recomendado).**
  - Instinct pierde toda credencial directa de Odoo. Cada escritura pasa por un carril con vista previa, «sí + código», cerca y rastro.
  - Hoy el autor en Odoo saldría Andrea, porque el servicio usa su llave. La marca de Instinct va en la nota del chatter y en el rastro.
  - Es el mismo modelo que ya protege a las socias.
- **3 · La 2, con un usuario de Odoo propio para el SERVICIO** («Truefie», ya está en la hoja de ruta).
  - El autor en Odoo deja de ser Andrea para todo lo que entra por Truefie, y la nota dice quién: Instinct, Andrea o Lorena.
  - Una sola licencia, sin abrirle Odoo a Instinct.

**Lo urgente, sea cual sea la opción:** cerrar ya la credencial con la que Instinct escribió el 15-oct. Mientras exista, todo lo de este plan se puede saltear.

## Orden de despliegue, cada paso con OK de Andrea

1. Cerrar la credencial directa de Instinct en Odoo y comprobar que rebota.
2. SQL + ensayo → pegado → verificación desde afuera.
3. Rama `insumo-asistente` en `truefie-escritura` + ensayo → merge → Render, **con `INSUMO_ASISTENTE_ENCENDIDO` apagado**.
4. Truefie: la lista «Hecho por Instinct» → publicar.
5. `verificar_instinct.py` con la sesión real.
6. Encender: el permiso y el interruptor.
7. Primer insumo real: Instinct lee, Andrea responde «sí + código».
