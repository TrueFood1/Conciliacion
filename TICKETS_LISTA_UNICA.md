# Tickets como LISTA ÚNICA de pendientes — propuesta

**Escrito el 21-sep-2026. PROPUESTA: nada de esto está aplicado.**
Decide Andrea antes de pegar una línea.

Lo que se pidió: que Tickets deje de ser solo la cola de hallazgos de Truefie y
pase a ser **la única lista de pendientes**, con dos mitades que no se mezclan:

- **TRUEFIE** → agrupado por módulo (Finanzas, Operaciones, Entregas,
  Conciliación, Ventas) más **"Sin módulo"**;
- **MIS PENDIENTES** → lo que no es Truefie: trámites, empaque, sitio web,
  decisiones.

Y la condición dura: **"Sin módulo" y "Mis pendientes" NO se pueden mezclar.**
Son cosas distintas: una es *"de Truefie, pero no sé de qué parte"*; la otra es
*"esto no es Truefie"*.

---

## 1 · Cómo está definido el módulo HOY, y el cambio mínimo

### Lo medido (21-sep-2026)

La cadena completa, de punta a punta:

```
ACCESO_VISTAS          5 módulos → lista de ids de vista
    ↓ accesoModDeVista(vista)
body[data-mod]         lo pone _modShow(); lo quita volverLobby()
    ↓ tkDondeEstoy()
ticket.modulo
```

- `ACCESO_VISTAS` tiene **cinco**: `finanzas`, `conciliacion`, `operaciones`,
  `entregas`, `personal`.
- `ticket.modulo` es `text` **sin CHECK** — hoy acepta cualquier cosa.
- Valores en uso: `finanzas` 2 · `entregas` 1.

`modulo` queda en **NULL** en dos situaciones que hoy son **indistinguibles**:

1. estás en el **lobby** (`volverLobby()` quita `data-mod`);
2. estás en una vista **que no figura en `ACCESO_VISTAS`** — y eso incluye a
   `vTickets`, excluida a propósito porque *"tickets no es un módulo: es la
   cola"*.

### 🔴 Un hallazgo que cambia la lista pedida: `ventas` no existe

`ACCESO_VISTAS` no tiene `ventas`. Es una **tarjeta del lobby**
(`home-mod-ven`) y tiene color asignado (`#3FB6A8`), pero **cero vistas**. O
sea que hoy **ningún ticket puede nacer con `modulo='ventas'`**.

Hay que elegir, y es decisión de Andrea:

- **(a)** Ventas no es un grupo todavía. Aparece cuando tenga pantallas.
- **(b)** Ventas es un grupo que se llena **solo a mano** (migración o cambio de
  módulo), y queda claro que nunca va a llegar solo desde el ✱.

Recomendación: **(a)**. Un grupo vacío que nadie puede llenar es un renglón que
se aprende a ignorar, que es lo que ya pasó con "Todo al día" en la alerta de
Entregas (regla 1 de las alertas del lobby).

### El cambio mínimo: una columna nueva, sin tocar `modulo`

```sql
alter table ticket
  add column ambito text not null default 'truefie'
    constraint ticket_ambito_ok check (ambito in ('truefie','propio'));
```

Y `v_ticket` que lo exponga.

Con eso:

| grupo en pantalla | condición |
|---|---|
| **TRUEFIE** → Finanzas / Operaciones / Entregas / Conciliación | `ambito='truefie'` y `modulo = <ese>` |
| **TRUEFIE** → Sin módulo | `ambito='truefie'` y `modulo is null` |
| **MIS PENDIENTES** | `ambito='propio'` |

**Costo**: una columna, un CHECK, un default, y `v_ticket`. **Nada que migrar**:
las 3 filas de hoy toman `'truefie'` por el default.

### Por qué NO usar `modulo='mio'`, que sería más barato

Son **dos ejes distintos**:

- `modulo` contesta *"¿qué parte de Truefie?"*
- `ambito` contesta *"¿es Truefie?"*

Metiendo "mío" adentro de `modulo`, **"Sin módulo" y "Mis pendientes" quedan
hermanos en la misma lista** — exactamente lo que se pidió evitar. Además
`v_ticket` ya expone `modulo` y de ahí cuelgan el contador del lobby y la
agrupación: sobrecargarlo contagia el error a todo lo que lea esa columna.

Es la misma forma que el §13 del esquema ya resolvió bien para otra cosa:
*"`encargo` es un TIPO y no un estado… el tipo dice QUÉ es; el estado dice DÓNDE
está. Son ejes distintos y no se mezclan."* Acá el eje nuevo es **de quién es el
asunto**.

---

## 2 · Cómo se crea uno de "Mis pendientes"

**El problema real**: el ✱ captura la pantalla donde estás, y un trámite de
PROCOMER no nace en una pantalla.

**Pero el lobby SÍ es una pantalla, y es justamente la que no tiene módulo.**

### La propuesta

Un **interruptor de dos posiciones arriba de la hoja del ✱**, con el valor
inicial sacado del contexto que la app ya tiene:

| dónde estás | arranca en |
|---|---|
| adentro de un módulo (`data-mod` con valor) | **"De Truefie"** |
| en el lobby (`data-mod` vacío) | **"Pendiente mío"** |

Un toque lo cambia, **siempre**. Eso cubre el caso real de que un trámite se te
ocurra mientras estás mirando Entregas, sin obligarte a salir al lobby para
anotarlo.

### Lo que NO se propone, y por qué

**Un segundo botón ✱ solo en el lobby.** Dos botones para la misma acción se
desincronizan: es el pendiente §23 (el prefijo `rp-` compartido) y es el bug del
guión de las regalías, que se arregló en Pendientes y siguió roto en el
Historial seis días. Un control, dos modos.

### El contexto, cuando el ámbito es `propio`

La hoja **no manda el contexto de pantalla**: `vista`, `miga`, `modulo` y
`sobre` van NULL. Guardar *"estabas en vDespachos"* en un trámite de PROCOMER es
ruido que después alguien tiene que aprender a ignorar.

Lo que **sí** se sigue guardando: `build`, `doc_modificado`, `agente`,
`standalone`, `viewport` y la zona horaria. Eso no dice de qué se trata el
pendiente — dice desde dónde lo escribiste, y sirve igual.

---

## 3 · El ciclo de "Mis pendientes"

No pasan por el diagnóstico de CC. De los ocho estados, **les sobran dos**:

- **`sin_triar` no aplica.** Existe porque un reporte de Daniel necesita que
  alguien lo mire antes de saber qué es. Uno tuyo **nace sabiendo lo que es**.
  Entra directo en `disponible`.
- **`en_validacion` no aplica.** Es el rato entre que CC termina y Andrea
  aprueba. Acá no hay dos lados: el que lo hace y el que lo aprueba son la misma
  persona.

Quedan **cinco**, y los mueve Andrea:

```
disponible ──► en_curso ──► cerrado
     │
     ├──► bloqueado    (espera otra cosa, y esa cosa se escribe)
     ├──► pospuesto    (no ahora, pero vuelve)
     └──► descartado   (no se hace, no vuelve)
```

### 🔴 Una consecuencia del cambio que se acaba de aplicar

`CAMBIO_MARCA_LA_ESCRIBE_CC.sql` (aplicado el 21-sep) le abrió a la firma
`cc-sql` los estados `disponible` y `bloqueado`. **Para `ambito='propio'` eso
está mal**: CC no debería poder tocar el estado de un trámite de Andrea.

El guardia del §2 necesita **una línea más**:

```sql
-- si el ticket es de ambito 'propio', sin sesion no se escribe NINGUN estado
if quien is null then
  if (select t.ambito from ticket t where t.id = new.ticket_id) = 'propio' then
    raise exception 'los pendientes propios los mueve Andrea, no cc-sql. Ticket %',
      new.ticket_id;
  end if;
  ...
```

Lo mismo para `ticket_marca`: **CC no marca un pendiente propio**, porque la
marca es el resultado de abrir el código, y acá no hay código que abrir.

⚠️ **Esto NO está en el pegado del 21-sep** y no se agregó a último momento a
propósito: hoy no hay ni un ticket de ámbito `propio`, así que no hay riesgo, y
meterlo a las apuradas en un pegado ya ensayado habría invalidado el ensayo. Va
**junto con la columna `ambito`**, en su propio pegado y con su propio candado.

---

## 4 · La contradicción del §13, resuelta

### La contradicción, medida por los dos lados

| | |
|---|---|
| **§13 dice** | cada ticket migrado lleva una fila de `ticket_detalle` **clase `'espera'`** con el § de donde salió |
| **El guardia del §4 dice** | sin sesión, `clase` solo puede ser `('cierre','anuncio')` |
| **La migración corre** | desde el SQL Editor, **sin sesión**, firmada `ticket-sql · migracion …` |

Tal como está, **la migración rebota**. No es una duda: es aritmética de las tres
frases.

El motivo del guardia está escrito y es bueno:

> *"«Qué se espera» y «Criterio de terminado» los define una socia: si el mismo
> lado que escribe el criterio es el que lo cumple, el criterio no controla
> nada."*

### La resolución: se cambia el §13, no el guardia

**El § de origen no es una *espera*: es procedencia.** *"Salió del §14 de
`ENTREGAS_PENDIENTES.md`"* no es un juicio sobre qué falta ni un criterio de
terminado — es una nota de dónde vino. Eso es **`anuncio`**, que el guardia ya
acepta.

**Cero cambio de esquema, cero puerta nueva, y el argumento del guardia queda
intacto.**

Las otras dos salidas se descartan, y conviene decir por qué:

- **Abrir `'espera'` al editor** rompe justo la regla que el guardia existe para
  sostener. Sería CC escribiendo lo que después CC tiene que cumplir.
- **Migrar con sesión** no se puede: el SQL Editor entra como `postgres`, sin
  JWT. No hay forma de que `current_setting('request.jwt.claims')` traiga un
  correo.

### El plan de la migración de los 28

1. **Una pasada propia**, con `TICKETS_ESQUEMA §1–§25` y los siete de
   `ENTREGAS_PENDIENTES.md` abiertos al lado. **No se escriben de memoria**: eso
   sería fabricar 28 datos con pinta de medidos, que es lo que este repo pasa el
   día entero evitando. (Ya está escrito así en el §13 y se respeta.)
2. **Orden obligado**: primero los tres que bloquean a otros.
   `bloquea_ticket_id` es una FK, así que el que bloquea tiene que existir antes
   que el bloqueado. **Migrar por número de § lo rompe.**
3. Cada ticket migrado lleva:
   - `build = 'migrado · sin build'` — un pendiente viejo no tiene versión que
     capturar, y ponerle la de hoy sería inventar un dato;
   - `vista`, `miga`, `doc_modificado`, `standalone` y zona horaria en **NULL**,
     porque nadie los midió;
   - `creado_por = 'ticket-sql · migracion …'`, que el guardia del §1 exige;
   - `ambito = 'truefie'` (el default);
   - `modulo` según de dónde salga: los de `ENTREGAS_PENDIENTES.md` son
     `entregas`; los del esquema de tickets, **NULL** → "Sin módulo";
   - y su fila de `ticket_detalle` clase **`anuncio`** (no `'espera'`) con el §
     de origen, para poder volver al original sin buscarlo.
4. **En una sola transacción**, con candado y control adentro, ensayada en
   rollback contra producción antes de pegarse. El control cuenta los 28 y
   verifica que las FK de bloqueo resolvieron.

---

## 5 · La migración de "Mis pendientes"

**El mecanismo es el mismo** y ya está probado: un pegado firmado
`ticket-sql · migracion …`, en una transacción, con candado.

Las diferencias:

- `ambito = 'propio'`;
- `modulo = null` y **sin contexto de pantalla**;
- **estado inicial `disponible`**, escrito explícitamente — no la ausencia de
  eventos. Un pendiente tuyo no está "sin triar": está listo para agarrar.

⚠️ Y el orden importa: **la columna `ambito` y el ajuste del guardia tienen que
estar aplicados ANTES**. Si se cargan con el esquema de hoy, los 'propios'
entrarían como `ambito='truefie'` por el default y quedarían mezclados en la
mitad equivocada — que es el problema que todo esto vino a evitar.

---

## El orden que se propone

1. **La columna `ambito`** + el CHECK + `v_ticket`, con su candado. Solo esquema.
2. **El ajuste de los dos guardias** para que `cc-sql` no toque los `propio`.
3. **La pantalla**: el interruptor del ✱ y la agrupación en dos mitades.
4. **La migración de los 28** de Truefie.
5. **La migración de Mis pendientes**, cuando esté la lista.

Los pasos 1 y 2 pueden ir en el mismo pegado. El 3 es una publicación. El 4 y el
5 son pegados de datos, y van después de que la pantalla exista — migrar antes
dejaría los tickets en una tabla que nadie puede mirar, que es el argumento que
el §13 ya usó para no migrar el 19-sep.


---

## 5-bis · La lista de "Mis pendientes" a cargar

**Confirmada por Andrea el 21-sep-2026. NO cargada** — la columna `ambito` ya
está aplicada, pero la pantalla (b65) todavía no se publicó, y el §13 dice que
migrar antes de que exista la pantalla deja los tickets en una tabla que nadie
puede mirar.

| # | pendiente | tipo | estado inicial |
|---|---|---|---|
| 1 | BRCGS: logo oficial del paquete de marca | encargo | disponible |
| 2 | BRCGS: número de certificado y vencimiento (para `REGISTRO_TÉCNICO`) | encargo | disponible |
| 3 | GS1: convención del código de caja de Pizza | duda | disponible |
| 4 | Caja de Buns: al reimprimir, que diga "Buns" | encargo | **pospuesto** |
| 5 | Bolsa de polipropileno de Pizza (Aida María) | encargo | disponible |
| 6 | Página web: el argumento de los 5 ppm | encargo | disponible |
| 7 | Página web: la pista para hacer scroll en la portada | encargo | disponible |

⚠️ **El 4 nace `pospuesto`, no `disponible`**, y con su razón escrita: se
reactiva cuando se mande a hacer la próxima tanda de cajas. Es justo la
distinción que el §13 defiende entre *pospuesto* (vuelve) y *descartado* (no
vuelve) — y un pendiente que nace pospuesto necesita que la razón diga **qué lo
despierta**, si no es indistinguible de uno olvidado.

Todos van con `ambito='propio'`, `modulo=null`, sin contexto de pantalla,
`build='migrado · sin build'` y `creado_por='ticket-sql · migracion propios'`.
