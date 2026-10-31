---
name: listo
description: Cierre CORTO de una sesión de CC en Truefie (protocolo de cierre, 21-oct-2026). Cada sesión lo corre al terminar SU tarea — toma el turno, verifica que no quede nada sin commitear, sube SU rama (nunca main), comprueba que los tickets tocados lleven su línea [Origen: chat «…»] y deja una entrada en la BITACORA. No escribe el ESTADO ni corre el cierre del día. Invocar con /listo.
---
<!-- CREADA el 2026-10-22 (decisión de Andrea, 21-oct 12:52). Reemplaza, junto con /cierre-dia, al
/cierre viejo. Respaldo versionado: Conciliacion/herramientas/skills/listo/ (rama dev). -->

# /listo — cierre corto de una sesión

**Por qué existe (20-oct):** seis sesiones en paralelo, cuatro ESTADOS el mismo día, un prompt que se
perdió entre chats, el choque de BUILD b114/b115 y un cierre de dos horas. Desde el 22-oct:
**cada sesión cierra lo suyo con /listo, y UNA sola sesión corre /cierre-dia** cuando Andrea lo pide.

El cwd es `Practica CC/`. Los scripts viven al lado de esta skill (no dependen de la rama del repo).

## Reglas que /listo da por cumplidas (si no, primero arreglarlas)
- **Una carpeta por sesión:** si la sesión necesitó otra rama, trabajó en SU worktree
  (`git -C Conciliacion worktree add <scratchpad>/wt-<tarea> <rama>`), nunca cambiando de rama en la
  carpeta compartida. Al terminar, `git worktree remove <ruta>` (sus commits quedan en la rama).
- **El origen:** el chat de origen es el `[Origen: chat «…»]` del prompt. Sin origen, preguntarlo.
- **Tickets:** cada ticket creado o tocado lleva hoy una línea `Origen: chat «…» · …`
  (`tk_estado.py anunciar <n> --texto "Origen: chat «…» · <qué pasó>" --seco` → sin `--seco`).

## Paso 1 — Ensayo en seco
```bash
python3 .claude/skills/listo/listo.py --origen "<chat>" --repo <carpeta> [--repo <otra>] \
  --tickets <n,n> --hecho "<una línea>" --pendiente "<una línea o nada>" --decision "<qué espera a una socia o nada>" --seco
```
`--repo` es la carpeta donde quedó el trabajo: `Conciliacion`, `truefie-escritura` o la ruta del worktree.
El seco revisa repos y tickets y muestra la entrada, sin escribir nada. Si sale un ✗, arreglarlo y repetir.

## Paso 2 — De verdad
El mismo comando sin `--seco`. En orden, y para en el primer ✗:
1. **Turno** (`turno.py`): si otra sesión está cerrando, sale con 3 → decir «espero el turno: lo tiene
   «X» desde HH:MM» y volver a intentar en unos minutos. Una marca de más de 30 min se da por abandonada.
2. **Nada sin commitear** en cada repo (lo no rastreado se avisa y no frena).
3. **Push de SU rama** con nombre explícito (`HEAD:refs/heads/<rama>`) y comprobación en GitHub.
   **Nunca `main`**: publicar es de una socia, con su OK en esta sesión.
4. **Tickets** con su línea de origen de hoy.
5. **Entrada en la BITACORA** (`Conciliacion/BITACORA.md`, arriba de todo): origen, hora, repo, rama,
   commit, tickets, hecho, pendiente y lo que espera a una socia.
6. **Suelta el turno.**

## Paso 3 — Reportar (corto)
Una línea por repo (rama · commit · en GitHub), los tickets, y lo que espera a una socia. Nada más.

## Lo que /listo NO hace
- No escribe el ESTADO (lo hace Claude.ai con el bloque de /cierre-dia).
- No corre /cierre-dia, no publica, no toca `main`, no cierra tickets sin evidencia.
