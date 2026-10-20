---
name: cierre
description: Ritual de cierre de una sesión donde se tocó código en el repo Conciliacion. Corre el checklist técnico (commit + push a dev), verifica el estado REAL de las ramas dev/main contra GitHub con git ls-remote, arma un bloque de bitácora con 4 secciones fijas, lo muestra y espera OK antes de escribirlo en BITACORA.md. Invocar con /cierre al terminar de trabajar.
---

<!-- ───────────────────────────────────────────────────────────────────────
  RESTAURADA el 2026-09-04 — y conviene decir con precisión qué significa eso.

  El 2026-09-02 esta skill se borró junto con todo `Practica CC/.claude/`
  (un `rm -rf` al limpiar la config de un servidor de pruebas). Esa carpeta
  está FUERA del repo `Conciliacion/`, así que ningún commit la respaldaba,
  la Papelera estaba vacía, iCloud no la tenía y no hay Time Machine.

  El cuerpo de abajo NO es una reconstrucción: es el ORIGINAL, textual.
  Se recuperó de los transcripts de sesión que Claude Code guarda en
  `~/.claude/projects/-Users-andrea-Desktop-Practica-CC/*.jsonl`, donde el
  texto completo de la skill queda grabado cada vez que se la invoca.

    · Fuente     : sesión 574504e7, invocación del 2026-08-27T19:47Z
                   (la más reciente de las que hay en disco)
    · Verificado : 18 copias en los transcripts (17 idénticas + 1 que difiere solo en
     una línea en blanco al final)
    · sha256[12] del cuerpo: 99e5f2fb3003

  Lo único que NO estaba en los transcripts es el frontmatter: el loader
  guarda el cuerpo ya sin él. El `description:` de arriba se recuperó aparte,
  textual, del listado de skills (`skill_listing`) de esos mismos transcripts.
  El `name:` es el nombre de la carpeta. Si el frontmatter original tenía
  algún otro campo, ese dato se perdió.

  Dato medido, por si sirve: entre el 16-jul y el 2-sep esta skill se invocó
  18 veces, y las 18 desde la app de escritorio
  (`entrypoint: claude-desktop`). O sea que sí cargaba en la app.

  ⚠ MODIFICADA el 2026-09-04, después de restaurarla: se le agregó el
  «Paso 0 — Respaldo de las skills», que NO venía en el original y está
  rotulado como agregado ahí mismo.
  ⚠ MODIFICADA el 2026-10-19 (decisiones de Andrea): se le agregó el «Paso 2b —
  Pendientes → tickets» (CC los carga directo con truefie_cc; sin la clave, ensayo
  + pegado) y la sección Pendientes del bloque lleva el T-<n> de cada línea.
  Rotulados ahí mismo.
  ⚠ MODIFICADA el 2026-10-20 (decisión de Andrea, T-171): Andrea y Lorena publican a
  main sin el OK de la otra (Contexto de rutas y Paso 1) y se agregó el «Paso 2c — Aviso
  a la otra socia». Rotulado ahí mismo. El resto del cuerpo sigue siendo textual.
─────────────────────────────────────────────────────────────────────── -->

# /cierre — cierre técnico + bitácora

Un solo flujo secuencial. El objetivo es que no se pueda hacer la bitácora sin
antes verificar y pushear las ramas: así se tapa el agujero del 6-jul (un cierre
que se olvidó → `main` se movió por web sin que nadie lo notara).

## Contexto de rutas (importante)

- El cwd de la sesión es `Practica CC/`. El **repo git es la subcarpeta
  `Conciliacion/`** → todos los comandos git van con `git -C Conciliacion …`.
- La bitácora es `Conciliacion/BITACORA.md` (gitignored → escribirla NO genera
  commit). El checklist técnico es `Conciliacion/CIERRE_TECNICO.md`.
- Ramas: `dev` = respaldo del trabajo en curso (push SIEMPRE acá). `main` = lo
  que GitHub Pages publica (lo mueve Andrea o Lorena, cualquiera de las dos sin
  autorización de la otra; se avisan si toca el trabajo de la otra — 20-oct, T-171).

## Paso 0 — Respaldo de las skills (AGREGADO el 2026-09-04, no venía en el original)

Estas skills viven en `Practica CC/.claude/skills/`, **fuera del repo**: ningún
commit las cubre. El 2026-09-02 un `rm -rf .claude` las borró sin red. La copia
versionada es `Conciliacion/herramientas/skills/`; este paso existe para que las
dos no se separen, y va **antes** del Paso 1 para que lo que cambie entre en el
mismo commit.

```bash
diff -r .claude/skills Conciliacion/herramientas/skills --exclude=README.md
```

Según lo que devuelva:

- **Sin salida** → las dos copias coinciden. Seguí al Paso 1.
- **Sale la diferencia** (una línea `diff -r … viva repo` y abajo las líneas con
  `<` y `>`) o **`Only in .claude/skills`** → la copia viva cambió, o hay una
  skill nueva. Sincronizá, y que entre en el commit del Paso 1:
  ```bash
  cp -R .claude/skills/. Conciliacion/herramientas/skills/
  ```
- **`Only in Conciliacion/herramientas/skills`** → falta algo en la copia viva.
  **PARÁ y avisá antes de tocar nada.** Puede ser que Andrea la borró a
  propósito, o que se perdió como el 2-sep. **No la borres del respaldo**: es el
  único lugar donde queda. Se restaura al revés:
  ```bash
  cp -R Conciliacion/herramientas/skills/<nombre> .claude/skills/
  ```
- **`.claude/skills` no existe** → se perdió la copia viva entera. Mismo caso que
  el anterior: restaurar desde el respaldo, nunca al revés.

Este archivo se respalda a sí mismo: si editás `/cierre`, el `diff` del próximo
cierre lo detecta. Lo que el respaldo **no** cubre es el frontmatter perdido de
una skill que nunca se haya commiteado — para eso están los transcripts
(`~/.claude/projects/*.jsonl`, ahí queda el cuerpo entero de cada invocación).

Decilo en el reporte del Paso 4, aunque sea una línea: "respaldo de skills: sin
cambios".

## Paso 1 — Checklist técnico

Leé y ejecutá `Conciliacion/CIERRE_TECNICO.md` en orden: `git status` → chequeo
de secretos sobre el diff (keys, tokens, datos bancarios, correos personales) →
commit con mensaje descriptivo → **push a `dev`** → actualizar la constante
`BUILD` (inicio del bloque JS de `index.html`) a la fecha de hoy.

- **NO publicar a `main`** salvo que la socia de la sesión —Andrea o Lorena— lo diga
  explícito en esta sesión. Ninguna necesita el OK de la otra (20-oct, T-171).
- Si el chequeo de secretos encuentra algo, PARÁ y avisá antes de commitear.

## Paso 2 — Estado REAL del remoto (no suponer el local)

Consultá GitHub directo, no la vista local:

```bash
git -C Conciliacion ls-remote origin refs/heads/dev refs/heads/main
git -C Conciliacion rev-parse dev main HEAD
git -C Conciliacion status --porcelain
```

Para `dev` y `main`, compará hash **local vs origin** (los primeros 7 chars).
Detectá y marcá:
- **origin adelante del local** (el caso 6-jul: alguien editó por web). Marcalo
  ⚠ y aclarar que hay que `git fetch` antes de mergear.
- **local adelante del origin** (commits sin pushear).
- **working tree sucio** (archivos sin commitear tras el Paso 1 — no debería,
  pero verificar).

## Paso 2b — Pendientes → tickets (AGREGADO el 2026-10-19, decisiones de Andrea)

**Nada queda pendiente solo en la bitácora.** Cada pendiente NUEVO de la sesión va como ticket, en su
módulo (Finanzas, Operaciones, Entregas, Compras, Personal, o General si no tiene) o en «Mis pendientes»
(ámbito `propio`) si es algo que hace Andrea fuera de Truefie.

1. **Juntar** los pendientes nuevos: lo que quedó abierto, lo que se decidió hacer después, lo que se
   encontró de paso.
2. **¿Ya existe?** Buscarlo en TODOS los tickets, en cualquier estado:
   `python3 Conciliacion/herramientas/tickets/revisar_tickets.py --todos --buscar "<palabra clave>"`.
   Si existe: no se duplica; si cambió algo, `tk_estado.py anunciar <n> --texto "…" --seco` → sin `--seco`,
   y la bitácora lleva ese T-<n>.
3. **Armar la tanda** de los que faltan en `Conciliacion/herramientas/tickets/tanda_<fecha>.json`
   (gitignored: un ticket puede nombrar una brecha y el repo es público), cada uno con su explicación en
   los cuatro renglones y, si hace falta, su marca.
4. **Cargarla.**
   - **Con la clave de truefie_cc** (la Mac de Andrea: `security find-generic-password -s truefie-cc-db -a truefie_cc`):
     ```bash
     python3 Conciliacion/herramientas/tk_estado.py tanda Conciliacion/herramientas/tickets/tanda_<fecha>.json --seco
     python3 Conciliacion/herramientas/tk_estado.py tanda Conciliacion/herramientas/tickets/tanda_<fecha>.json
     ```
     Todo en una transacción (todo o nada), firmado `cc-truefie`; frena si una clave ya existe. Devuelve los T-<n>.
   - **Sin la clave** (la compu de Lorena): ensayo + pegado para que ella los pegue en el editor:
     ```bash
     python3 Conciliacion/herramientas/tickets/armar_tickets.py Conciliacion/herramientas/tickets/tanda_<fecha>.json Conciliacion/PEGADO_TICKETS_<FECHA>
     ```
     (firmas del editor: `ticket-sql…` y `cc-sql…`; desde el editor un propio solo nace, sin marca).
     Ensayo al portapapeles → su tabla → pegado → fila de control → verificar con `revisar_tickets.py`.
5. **Verificar desde afuera** con `revisar_tickets.py --todos --buscar "<clave>"`. Recién ahí los T-<n> van a
   la sección Pendientes. Si no se cargó hoy: `⏳ ticket por cargar (<archivo>)`.
6. **Resumen para Andrea** al final del cierre: tickets creados (T-<n> · módulo · título), marcas puestas,
   cierres con su evidencia, y —si se revisaron propios— los tres grupos (CC · Instinct · Andrea) con los
   mensajes para Instinct listos para copiar (mismo formato que el /retomar).

## Paso 2c — Aviso a la otra socia (AGREGADO el 2026-10-20, decisión de Andrea, T-171)

Andrea y Lorena tienen el mismo poder de decisión: cualquiera publica a `main` sin el OK de la otra.
A cambio, **se avisan** cuando lo publicado toca o puede tocar el trabajo de la otra. Este paso arma
ese aviso; **no lo manda** (mandarlo es de la socia).

1. **¿Se publicó hoy?** Si `main` no se movió en esta sesión, el paso termina acá: sin aviso.
2. **¿Toca lo de la otra?** Mirar lo publicado (`git -C Conciliacion diff --stat <main antes> <main ahora>`
   y el diff de `index.html`). Toca si cae en cualquiera de estos:
   - la zona o el módulo de la otra (Lorena: Personal —CSS `.vac-`/`.cal-`/`.per-`, sus vistas,
     `PER_TABS`…—; Andrea: el resto, salvo que la bitácora diga otra cosa);
   - una rama de la otra que ahora tenga conflicto con `main`, o un número de BUILD que ella esté usando;
   - algo compartido: el login, el inicio, los tokens del tema, `CLAUDE.md`, `CIERRE_TECNICO.md`, las
     skills, o un SQL / esquema que lean sus pantallas.
   Si no toca nada: una línea en el resumen, «Publicado b<NN>: no toca el trabajo de <la otra>.»
3. **Si toca**: el aviso, listo para copiar, en el lenguaje de las socias (sin hashes ni nombres de
   funciones, sin montos ni datos de personas):
   ```
   <Lorena|Andrea>: publiqué b<NN> en Truefie.
   Qué cambia: <una o dos líneas, en palabras de pantalla>.
   Te toca porque: <qué de tu trabajo roza: módulo, rama, número de BUILD>.
   Qué conviene que hagas: <nada | traer main a tu rama antes de seguir | usar el b<NN+1> | mirar X>.
   ```
4. Va al final del Paso 4, junto al resumen de tickets, con un renglón: «Aviso para <la otra>, listo para
   mandar». En la bitácora, una línea en «Qué se hizo hoy»: «Aviso a <la otra> por b<NN>: armado».

## Paso 3 — Armar el bloque de bitácora

Formato fijo, 4 secciones. Redactá el contenido a partir de lo que pasó en la
sesión (no inventar; si una sección queda vacía, escribí "—").

```markdown
# 📍 DÓNDE QUEDAMOS — <YYYY-MM-DD> (<título corto de la sesión>)

### Qué se hizo hoy
- <cambios concretos, con hash de commit cuando aplique>

### Dónde quedamos
<el punto exacto para retomar, 1-2 frases>

### Pendientes
- T-<n> · <módulo o Mis pendientes> · <lo que quedó abierto>   ← cada línea con su ticket (Paso 2b)
- ⏳ ticket por cargar (<archivo>) · <lo que quedó abierto>   ← solo si no se cargó hoy

### Estado de ramas
- `dev`  → <hash7> · <"sincronizado con origin" | "N commits sin pushear">
- `main` → <hash7> local · <hash7> origin · <"en sync" | "⚠ dev adelantado, falta merge+push" | "⚠ ORIGIN ADELANTE — hacé git fetch antes de mergear">
- Working tree: <"limpio" | "N archivos sin commitear">
```

## Paso 4 — Mostrar y ESPERAR OK

Mostrá el resultado del Paso 1 (checklist), el del Paso 2 (estado real), el aviso
del Paso 2c si lo hay, y el bloque del Paso 3. Terminá preguntando si lo escribe tal cual o si quiere
ajustar. **No escribas nada en BITACORA.md todavía.**

## Paso 5 — Escribir (solo con OK explícito)

Con el OK de Andrea, **prepender** el bloque en `Conciliacion/BITACORA.md`
justo después del encabezado del archivo (el `# Bitácora del proyecto` + la nota
de gitignored + el primer `---`), de modo que quede **lo más nuevo arriba**. No
tocar los bloques históricos. No commitear (la bitácora es gitignored).
