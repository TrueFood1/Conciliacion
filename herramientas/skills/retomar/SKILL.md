---
name: retomar
description: Arranque de sesión en el repo Conciliacion. Lee el bloque más reciente de BITACORA.md y, en un solo turno, reporta dónde quedamos, los pendientes y el estado de ramas — comparando lo que la bitácora grabó contra el estado REAL del remoto con git ls-remote (caza si main se movió por web entre sesiones). Invocar con /retomar al empezar a trabajar.
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
  rotulado como agregado ahí mismo. El resto del cuerpo sigue siendo textual.
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
```

Si `BITACORA.md` no existe o no tiene ningún bloque `DÓNDE QUEDAMOS`, decilo
claro y ofrecé correr igual el chequeo de ramas del Paso 2.
