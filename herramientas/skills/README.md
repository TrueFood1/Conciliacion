# Respaldo de las skills locales

Copia versionada de las skills `/cierre` y `/retomar`. **Esta carpeta es el
respaldo, no la copia viva.**

La copia viva va en `Practica CC/.claude/skills/<nombre>/SKILL.md` — o sea
FUERA de este repo, un nivel arriba. Ahí es donde Claude Code las lee, y ahí
ningún commit las cubre: por eso se borraron el 2026-09-02 sin red.

## Por qué acá y no en `Conciliacion/.claude/skills/`

Dos razones:

1. El `.gitignore` de este repo ignora `.claude/` (línea 43) — una copia ahí
   tampoco quedaría versionada.
2. Si alguien abriera Claude Code con `cwd = Conciliacion/`, esa ruta las
   cargaría de verdad, y adentro asumen `cwd = Practica CC` (`git -C
   Conciliacion …`). Todos los comandos apuntarían mal.

## Restaurar

Desde esta carpeta:

```bash
VIVA="$(git rev-parse --show-toplevel)/../.claude/skills" && mkdir -p "$VIVA" && cp -R cierre retomar "$VIVA/"
```

Después hay que reiniciar la sesión: las skills se leen al arrancar.

## Mantener las dos copias iguales

```bash
R="$(git rev-parse --show-toplevel)" && diff -r "$R/../.claude/skills" "$R/herramientas/skills" --exclude=README.md
```

`/cierre` ya corre ese `diff` solo: es su **Paso 0**, y va antes del commit, así
que lo que cambie en la copia viva entra en el mismo commit. La skill se
respalda a sí misma.

Los cuatro casos están probados (4-sep-2026): copias iguales, copia viva
editada, falta una skill en la viva (el escenario del 2-sep — sale
`Only in …/herramientas/skills`), y carpeta viva inexistente. En los dos
últimos el Paso 0 manda **parar y avisar**, y nunca borrar del respaldo.
