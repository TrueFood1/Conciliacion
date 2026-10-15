# Instinct · fase 2 · primera escritura: crear insumo — PLAN (15-oct-2026, sin construir)

> Nada de esto está hecho. No se tocó Render ni Supabase. Es para que Andrea decida.

## Cómo es hoy (medido el 15-oct)

- Instinct entra con su propia sesión de Supabase (perfil `asistente`). Ve todo y **no escribe nada**:
  - `asistente_no_inserta`, `_actualiza` y `_borra` son políticas RESTRICTIVAS en cada tabla.
  - En el servicio de escritura (`truefie-escritura`), cada ruta pasa por `_sesion_socia()` → 403 `sin_rol`.
- El carril `/insumo` ya existe y está probado (Cacao en Polvo, 13-oct):
  1. `compra_insumo_propuesta`: lo inserta la socia y la base exige `creado_por` = su correo.
  2. `POST /insumo {propuesta_id}`: devuelve la vista previa (`legible` + `huella`).
  3. `POST /insumo {propuesta_id, confirmar:true, huella}`: crea en Odoo, lee lo creado de vuelta, deja nota en el chatter y rastro en `compra_insumo_odoo`.
  - Para crear de verdad hace falta `INSUMO_ENCENDIDO=si` en Render. Hoy está encendido, solo para socias.

## El flujo propuesto

```
Instinct arma la propuesta ──► fila en compra_insumo_propuesta (creado_por = instinct@…)
        │
        ▼
POST /insumo {propuesta_id}  ──► vista previa + huella (solo lee Odoo)
        │
        ▼
Instinct se la lee a Andrea (nombre, unidad, IVA, Cabys, proveedor, precio)
        │
        ▼
Andrea dice «sí»  ──► [DECISIÓN 1: cómo queda probado ese «sí»]
        │
        ▼
POST /insumo {propuesta_id, confirmar:true, huella} ──► crea en Odoo
        │
        ▼
Rastro «hecho por Instinct · aprobado por andrea@» + aviso a Andrea
```

## DECISIÓN 1 — cómo queda probado el «sí» (recomiendo B)

- **A · El «sí» por WhatsApp.** Instinct confirma solo, después de que Andrea le contestó «sí».
  - Ventaja: lo más simple.
  - Problema: el «sí» vale lo que vale la palabra de Instinct. Si entiende mal un «sí, pero…» o se confunde de propuesta, nada lo frena.
- **B · El «sí» con la sesión de Andrea (recomendado).** Instinct le manda un enlace a Truefie, que abre la vista previa con un solo botón: «Sí, que Instinct lo cree».
  - El toque deja una fila en `asistente_aprobacion` (propuesta, huella y `aprobado_por` = el correo del token, que tiene que ser de socia).
  - El servidor **no crea** si no encuentra esa aprobación para esa huella exacta.
  - Si la propuesta o Odoo cambian, cambia la huella y la aprobación vieja ya no sirve.
  - Instinct puede preparar todo, pero no puede inventar el «sí».
- **C · Las dos.** El «sí» por WhatsApp para la conversación y el toque para la escritura. En la práctica es igual a B.

## Lo que cambiaría (con B)

### Supabase (un SQL con su ensayo, como siempre)

1. **`asistente_permiso`** (tabla nueva, append-only, igual que `asistente_interruptor`):
   - Columnas: `accion` ('crear_insumo'), `encendido`, `creado_por`, `creado_en`.
   - Solo una socia inserta. Sin filas = apagado.
   - Función `asistente_puede(accion)`: devuelve la fila más reciente de esa acción, y además exige que `asistente_bloqueado()` sea falso (el interruptor general sigue mandando).
2. **`compra_insumo_propuesta`**:
   - Se cambia **solo en esta tabla** la restrictiva `asistente_no_inserta` por `NOT acceso_es_asistente() OR asistente_puede('crear_insumo')`.
   - Política permisiva nueva: el asistente inserta si `asistente_puede('crear_insumo')` y `creado_por` = su correo.
   - Las otras 60 tablas quedan exactamente igual.
3. **`asistente_aprobacion`** (tabla nueva):
   - Columnas: `propuesta_id`, `huella`, `aprobado_por`, `creado_en`.
   - Insert solo de socia, con `aprobado_por` = correo del token. El asistente la lee y no la escribe.
4. **`compra_insumo_odoo`**:
   - Columna nueva `aprobado_por` (null cuando la crea una socia).
   - El servidor inserta el rastro con el token de quien ejecuta, así que hace falta permitirle al asistente ese insert, con permiso y con `aprobado_por` que exista en `asistente_aprobacion`.

### Render (`truefie-escritura`) — un cambio, en una rama, con su ensayo

- `_sesion_socia()` se queda igual para **todas** las rutas.
- Solo `/insumo` pasa a usar `_sesion_insumo()`, que acepta a una socia (como hoy) o al asistente si se cumplen las cinco condiciones:
  - a. `INSUMO_ASISTENTE_ENCENDIDO=si`: **interruptor propio, apagado por defecto**.
  - b. `asistente_puede('crear_insumo')` con su token.
  - c. La propuesta es suya: `creado_por` = su correo. No puede ejecutar propuestas de socias.
  - d. Al confirmar, hay una `asistente_aprobacion` con esa huella, y es de socia.
  - e. `INSUMO_ENCENDIDO=si`, como siempre.
- Rastro en Odoo: «Creado desde Truefie por Instinct (asistente) · aprobado por andrea@… · propuesta N».
- **Aviso de lo que hizo**:
  - La respuesta del servicio trae el producto creado, y Instinct se lo dice a Andrea en el momento.
  - En Truefie (Compras › Ajustes) el insumo lleva el chip «Instinct».
  - Pendiente: ¿también un correo diario? (DECISIÓN 2).

### Truefie (`index.html`)

- La pantalla del enlace: la vista previa de la propuesta N con «Sí, que Instinct lo cree» y «No».
  - Solo socias. «No» no escribe nada: la propuesta queda sin aprobar.
- El chip «Instinct» en el insumo creado.

## Permisos nuevos del perfil asistente (y nada más)

| Dónde | Hoy | Con el plan |
|---|---|---|
| `compra_insumo_propuesta` | lee | lee + **inserta las suyas**, solo con el permiso encendido |
| `compra_insumo_odoo` | lee | lee + el rastro de lo que creó, solo con aprobación de socia |
| `asistente_aprobacion` | — | lee |
| `/insumo` (Render) | 403 | vista previa y creación de **sus** propuestas, con los dos interruptores y la aprobación |
| las otras 60 tablas, `/validar`, `/trasladar`, `/pedir`, `/tarifas`, `/barrido`, `/quien` | solo lectura / 403 | **igual** |

## Cómo se prueba que fuera de esa acción sigue en solo lectura

1. **Ensayo SQL (termina en ROLLBACK)**, haciéndose pasar por Instinct (`request.jwt.claims` con su correo):
   - Recorre **todas** las tablas de `public` e intenta un INSERT en cada una. Espera 42501 en todas menos `compra_insumo_propuesta`, y ahí solo con el permiso encendido.
   - Con el permiso apagado: 42501 también ahí.
   - Intenta insertar una propuesta con `creado_por` de otra persona: 42501.
   - Intenta insertar una `asistente_aprobacion`: 42501.
   - Cada RECHAZA se lee **por el motivo**, no por el texto (regla del 24-sep).
2. **Ensayo del servidor** (`ensayo.py`, sin Odoo real):
   - Asistente en `/validar`, `/trasladar`, `/pedir`, `/tarifas` y `/barrido`: 403.
   - `/insumo` con `INSUMO_ASISTENTE_ENCENDIDO` apagado: 403.
   - Con permiso pero sin aprobación: 409.
   - Con una aprobación de otra huella: 409.
   - Sobre una propuesta de socia: 403.
   - Todo en regla: crea.
3. **`verificar_instinct.py` extendido**, con la sesión real de Instinct y corrido por Andrea:
   - Los 15 chequeos de hoy, más: inserta su propuesta y la vista previa responde.
   - Sin aprobación no crea.
   - Todas las demás escrituras siguen dando 42501 / 403.
4. **Apagar en un minuto**, cualquiera de las tres llaves por separado:
   - `asistente_permiso` (fila nueva «apagado»).
   - `INSUMO_ASISTENTE_ENCENDIDO` en Render.
   - El interruptor general `asistente_interruptor`.

## Orden de despliegue, cada paso con OK de Andrea

1. SQL + ensayo → pegado → verificación desde afuera.
2. Rama `insumo-asistente` en `truefie-escritura` + ensayo → merge → Render, **con `INSUMO_ASISTENTE_ENCENDIDO` apagado**.
3. Truefie: pantalla de aprobación + chip → publicar.
4. `verificar_instinct.py` con la sesión real.
5. Encender: el permiso en Supabase y el interruptor de Render.
6. Primer insumo real, con Andrea mirando.
