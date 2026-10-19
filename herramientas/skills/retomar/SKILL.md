---
name: retomar
description: Arranque de sesión en el repo Conciliacion. Lee el bloque más reciente de BITACORA.md y, en un solo turno, reporta dónde quedamos, los pendientes y el estado de ramas — comparando lo que la bitácora grabó contra el estado REAL del remoto con git ls-remote (caza si main se movió por web entre sesiones) — y revisa los tickets no resueltos (los que cambiaron y los sin revisar). Invocar con /retomar al empezar a trabajar.
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

    · Fuente     : sesión 0f9cd68f, invocación del 2026-09-02T22:21Z
                   (la más reciente de las que hay en disco)
    · Verificado : 21 copias en los transcripts, las 21 idénticas byte por byte
    · sha256[12] del cuerpo: 9b99fd4a75c8

  Lo único que NO estaba en los transcripts es el frontmatter: el loader
  guarda el cuerpo ya sin él. El `description:` de arriba se recuperó aparte,
  textual, del listado de skills (`skill_listing`) de esos mismos transcripts.
  El `name:` es el nombre de la carpeta. Si el frontmatter original tenía
  algún otro campo, ese dato se perdió.

  Dato medido, por si sirve: entre el 16-jul y el 2-sep esta skill se invocó
  21 veces, y las 21 desde la app de escritorio
  (`entrypoint: claude-desktop`). O sea que sí cargaba en la app.

  ⚠ MODIFICADA el 2026-09-04, después de restaurarla: se le agregó el
  «Paso 0 — Sello del respaldo», que NO venía en el original y está
  rotulado como agregado ahí mismo.
  ⚠ MODIFICADA el 2026-10-19 (decisiones de Andrea): se le agregó el «Paso 2b —
  Tickets: los revisa y los escribe CC», el «Paso 2c — De Lorena, solo para
  información» y sus partes del reporte, rotulados ahí mismo. Más tarde ese día, la «Regla de cierre»
  del Paso 2b (preguntas respondidas y lo que se ve en pantalla los cierra CC) y «explicado → disponible». CC escribe directo con truefie_cc (TICKETS_CC_AMPLIADO.sql). Reemplaza,
  por ahora, al revisor diario por GitHub Actions (T-149, pospuesto). El resto
  del cuerpo sigue siendo textual.
─────────────────────────────────────────────────────────────────────── -->

# /retomar — cargar contexto al abrir sesión

Devolvé todo en **un solo turno**. No hace falta que Andrea pida "leé la
bitácora primero".

## Contexto de rutas

- El repo git es la subcarpeta `Conciliacion/` → git con `git -C Conciliacion …`.
- La bitácora es `Conciliacion/BITACORA.md` (gitignored).

## Paso 0 — Sello del respaldo (AGREGADO el 2026-09-04, no venía en el original)

Desde el 28-ago-2026 Truefie es el **único** registro de entregas, y el
proyecto de Supabase está en plan Free, que no tiene respaldo automático. El
respaldo diario corre en GitHub Actions, en el repo privado
`TrueFood1/respaldo-truefie`, y deja la fecha de la última corrida buena en
`SELLO.md`.

Este paso existe porque las otras tres alarmas viven adentro de GitHub: el
correo de fallo, el vigía semanal y el propio workflow. **Si lo que se cae es
Actions, las tres se caen juntas y en silencio.** Esta es la única que mira
desde afuera, y aprovecha que Andrea abre sesión casi todos los días.

```bash
git -C respaldo-truefie fetch -q origin main && git -C respaldo-truefie show origin/main:SELLO.md | grep '^ULTIMO_RESPALDO_OK:'
```

- **Fecha de hoy o de ayer** → todo bien. Una línea en el reporte del Paso 3:
  "respaldo al día (<fecha>)". Nada más.
- **Más de 2 días** → **decilo fuerte, arriba de todo el reporte**, antes de la
  bitácora. No es un detalle: significa que el respaldo dejó de correr y que
  la base viva volvió a ser la única copia. Ofrecé correr el workflow a mano
  desde la pestaña Actions del repo privado (`workflow_dispatch`).
- **No existe la carpeta `respaldo-truefie`** → el clon local no está hecho.
  Decilo, no lo trates como que el respaldo falló: son cosas distintas.
- **El `fetch` falla** → puede ser falta de red o de credenciales. Distinguilo
  del caso anterior antes de alarmar.

No “arregles” el sello a mano nunca: lo escribe el workflow, y editarlo es
apagar la alarma en vez de atender el fuego.

## Paso 1 — Leer la bitácora

Leé `Conciliacion/BITACORA.md` y tomá el **bloque `# 📍 DÓNDE QUEDAMOS` más
reciente** (el de más arriba). De ahí salen: la fecha/título, "Dónde quedamos",
"Pendientes" y el "Estado de ramas" que grabó el último `/cierre`.

## Paso 2 — Chequeo de sanidad del remoto (en vivo)

La bitácora es una foto vieja. Verificá la realidad de HOY:

```bash
git -C Conciliacion ls-remote origin refs/heads/dev refs/heads/main
git -C Conciliacion rev-parse dev main
git -C Conciliacion status --porcelain
```

Compará los hashes de `dev` y `main` que grabó el "Estado de ramas" de la
bitácora contra los de ahora (local y origin). Lo que se busca cazar: que
alguien haya movido `main` (u otra rama) por la web **entre sesiones** — el
agujero del 6-jul, pero detectado al abrir en vez de al cerrar.

## Paso 2b — Tickets: los revisa y los escribe CC (AGREGADO el 2026-10-19, decisiones de Andrea)

CC escribe **directo en la base con su rol `truefie_cc`** (TICKETS_CC_AMPLIADO.sql, 19-oct), en tickets de
Truefie **y** en los pendientes propios de Andrea. La clave está en el llavero de la Mac de Andrea y la lee
`tk_estado.py`: nunca aparece en pantalla, en el chat ni en el repo. **Todo cambio va primero con `--seco`**
(la base lo juzga y lo deshace) y después de verdad.

**¿Hay clave?** `security find-generic-password -s truefie-cc-db -a truefie_cc >/dev/null 2>&1`.
Si **no** está (por ejemplo, en la compu de Lorena): este paso **solo lee y propone**; no escribe nada y lo
dice en el reporte.

**Lo que la base NO deja, nunca:** descartar, posponer, reabrir algo cerrado/pospuesto/descartado, escribir
«qué se espera» o «criterio», cambiar o borrar. Eso es de las socias, desde la pantalla.

### 1 · Leer (solo lectura)
```bash
python3 Conciliacion/herramientas/tickets/revisar_tickets.py --desde <fecha del último DÓNDE QUEDAMOS>
```
Se revisan dos grupos: los marcados `CAMBIÓ` y todos los «sin revisar». Los demás no se tocan.

### 2 · Tickets de Truefie
- **Explicar** cada «sin revisar» sin «En palabras claras» (cuatro renglones, en el lenguaje de Andrea, medido):
  `python3 Conciliacion/herramientas/tk_estado.py explicar <n> --que-es "…" --por-que "…" --falta "chico|mediano|grande. …" --recomienda "HACER|CERRAR|DESCARTAR. …" --seco` → sin `--seco`.
  **Y después pasarlo a «disponible»** (Andrea, 19-oct): un ticket explicado ya está revisado, salvo que en
  esta misma vuelta CC lo cierre o lo bloquee. `tk_estado.py mover <n> disponible --nota "Revisado y explicado
  por CC el <fecha>." --seco` → sin `--seco`. Vale también para los propios.
- **Cerrar con evidencia** los ya resueltos: solo si se puede nombrar en una línea el build (`b108`) o el
  commit donde quedó resuelto, y se verificó en el código o en git. Sin eso, no se cierra.
  `python3 Conciliacion/herramientas/tk_estado.py cerrar <n> --evidencia "<qué y dónde>" --build b<NN> --cierre "<una línea>" --seco` → sin `--seco`.
- **Regla de cierre (Andrea, 19-oct), vale también para los propios:**
  - **Preguntas** (tipo `duda`): si CC la responde, la respuesta escrita en el ticket (su «En palabras
    claras») **es** la evidencia, y CC lo cierra. La guarda de la base igual pide el build/commit (o
    `archivo:` en un propio) dentro de la evidencia: `--evidencia "respuesta: <en una línea>, medido en b<NN>"`.
  - **Lo que se ve en pantalla**: antes de dejárselo a Andrea, CC lo comprueba **él mismo en Truefie con su
    navegador** (Pages, con la sesión ya abierta), y si se ve bien lo cierra:
    `--evidencia "pantalla: <url> · <qué se vio> · b<NN>"`. **Solo mirar**: nunca tocar un botón que escribe
    (Revisar, Crear, Guardar, Validar…). Si no hay sesión o no se puede ver, queda para Andrea con una línea.
- **Marcar** (prioridad y riesgos) si hace falta: `tk_estado.py marcar <n> --prioridad … --toca-numeros si|no --escribe-en-base si|no --razon "…" --seco`.

### 3 · Pendientes propios de Andrea, EN ESTE ORDEN
**(a) Primero CC.** Si se resuelve con las herramientas de esta sesión (leer el repo, Drive, Zoho, Odoo en
solo lectura, armar un archivo o un borrador), CC lo resuelve y lo **cierra con evidencia verificable**: un
commit o build, o una línea `archivo: <ruta>`, `correo: <de quién, asunto, fecha>`, `enlace: <url>`.
- CC **no manda nada a terceros** (correos, WhatsApp) sin el OK de Andrea en esta sesión, ni escribe en
  Odoo o Supabase fuera de sus carriles.
- Si CC lo hizo pero la evidencia no es verificable desde afuera: **`en_validacion`** con una nota de 20
  letras o más (`tk_estado.py mover <n> en_validacion --nota "…" --seco`), para que Andrea lo cierre.

**(b) Después, Instinct.** Solo lo que CC **no** puede y Instinct **sí** podría (correo, calendario,
averiguar algo, escribirle a alguien): un mensaje **listo para que Andrea se lo mande a Instinct por
WhatsApp**, con este formato:
```
Instinct: <qué hacer, en una o dos líneas>.
Resultado que esperamos: <qué tiene que quedar hecho o qué dato traer>.
Antes de mandar cualquier correo a otra persona, mostrámelo y esperá mi OK.
(Ticket T-<n>)
```
Sin claves, sin montos de salarios ni datos sensibles. Al ticket se le agrega un anuncio
(`tk_estado.py anunciar <n> --texto "Mensaje para Instinct listo el <fecha>." --seco`).

**(c) Lo demás, para Andrea.** Lo que ni CC ni Instinct pueden: queda para ella, con **una línea** de qué
necesita de ella.

### 4 · Nunca
Cerrar porque «parece viejo», recomendar CERRAR sin la evidencia escrita, ni escribir sin `--seco` antes.

## Paso 2c — De Lorena, solo para información (AGREGADO el 2026-10-19, decisión de Andrea)

**Lorena no usa Tickets.** Anota sus pendientes en `PENDIENTES.md`, con títulos `## P<n> · <estado> · <título>`,
y trabaja en sus propias ramas. Este paso **solo lee** y lo muestra **al final del reporte**, en un grupo aparte.

1. **Sus ramas**: las del remoto cuyo último commit es de ella.
   ```bash
   git -C Conciliacion fetch -q origin
   git -C Conciliacion for-each-ref refs/remotes/origin --format='%(refname:short)|%(authorname)|%(committerdate:short)' | grep -i '|lorena'
   ```
2. **De cada rama**, lo justo:
   - el BUILD: `git -C Conciliacion show <rama>:index.html | grep -o "const BUILD = '[^']*'"`;
   - lo que no está en dev: `git -C Conciliacion log --oneline origin/dev..<rama>` (hasta 5);
   - sus pendientes: `git -C Conciliacion show <rama>:PENDIENTES.md | grep '^## P'` (solo el título y el estado).
   Y los `## P…` que ya estén en el `PENDIENTES.md` de dev.
   ⚠️ En zsh, con la rama en una variable, escribir `"${rama}:PENDIENTES.md"` con llaves: `$rama:P…` es un
   modificador de zsh (`:P` = ruta real) y git recibe otra cosa (pasó al armar este paso, 19-oct).
3. **Las reglas del grupo**:
   - **NO** se cargan como tickets, **NO** se resuelven, **NO** van a «Andrea decide» ni a ningún resumen de
     tareas, y **NO** se toca nada en las ramas de Lorena. Decide ella.
   - Solo títulos y estados: **nunca montos, salarios ni datos de personas**, aunque estén en el archivo.
   - Un aviso, una línea y solo si pasa: si una rama de Lorena usa un número de BUILD que **ya está publicado en
     main** (o que usa otra rama), decirlo dentro del grupo, como dato para coordinar, no como tarea.
4. **Sin cambios desde el último cierre** (ninguna rama de ella con commits más nuevos que la bitácora):
   «De Lorena: sin cambios desde el <fecha>.», en una línea.

## Paso 3 — Reportar (un solo turno)

Formato:

```
📍 Retomando — última bitácora: <fecha> (<título>)

Dónde quedamos
  <texto de la sección>

Pendientes
  1. <...>
  2. <...>

Estado de ramas (bitácora vs realidad ahora)
  dev  → grabado <hash7> · hoy <hash7>   <✓ sin cambios | ⚠ ...>
  main → grabado <hash7> · hoy <hash7>   <✓ sin cambios | ⚠ ...>
  <línea final: "Nadie tocó el remoto desde el último cierre, podés seguir."
   o el aviso: "⚠ origin/main cambió desde el cierre — traé con git fetch
   antes de seguir.">

Tickets (Paso 2b · lo que CC escribió con truefie_cc)
  Explicaciones escritas      T-<n> · <recomendación en una línea>
  Marcas puestas              T-<n> · <prioridad> · <razón corta>
  Cerrados con evidencia      T-<n> · <título corto> · <evidencia>
  Propios
    (a) resueltos por CC      T-<n> · <qué se hizo> · <evidencia, o «en validación: cerralo vos»>
    (b) para Instinct         T-<n> · <qué> — mensaje listo para copiar:
                              «Instinct: … Resultado que esperamos: … Antes de mandar cualquier
                               correo a otra persona, mostrámelo y esperá mi OK. (Ticket T-<n>)»
    (c) para Andrea           T-<n> · <una línea: qué necesita de ella>
  Cambiaron desde el último cierre (sin acción)   T-<n> · <qué cambió>
  revisé N · escribí X (explicaciones E · marcas M · cierres C) · Instinct I · Andrea decide Y
  <si no había clave: «Sin la clave de truefie_cc en esta compu: no escribí nada, solo propongo.»>

De Lorena (solo para información · Paso 2c)
  <rama> · <fecha> · <BUILD> · <N> commits que no están en dev
    P<n> · <estado> · <título>
  <si pasa: ⚠ <rama> usa el número <bNN>, que ya está publicado en main>
```

Si `BITACORA.md` no existe o no tiene ningún bloque `DÓNDE QUEDAMOS`, decilo
claro y ofrecé correr igual el chequeo de ramas del Paso 2.
