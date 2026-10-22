---
name: cierre-dia
description: Cierre del DÍA de Truefie (protocolo de cierre, 21-oct-2026). Lo corre UNA sola sesión cuando Andrea lo pide — git fetch de los 4 repos, commits del día por repo y rama, ramas sin push, worktrees, archivos sin commitear, marcas de turno colgadas, main/dev, BUILD publicado y próximo libre, tickets tocados por chat de origen, decisiones que esperan a una socia, tickets que parecen listos para cerrar con su evidencia y copias de la bitácora. Escribe CIERRE_DIA_<fecha>.md en respaldo-truefie y un bloque para Claude.ai. No escribe el ESTADO. Invocar con /cierre-dia.
---
<!-- CREADA el 2026-10-22 (decisión de Andrea, 21-oct 12:52). Reemplaza, junto con /listo, al
/cierre viejo. Respaldo versionado: Conciliacion/herramientas/skills/cierre-dia/ (rama dev). -->

# /cierre-dia — el cierre del día (una sola sesión)

Solo cuando Andrea lo pide, y una sola vez. El cwd es `Practica CC/`.

## Paso 0 — Turno
```bash
python3 .claude/skills/listo/turno.py tomar --origen "<chat>" --que cierre-dia
```
Si sale 3 (otra sesión está con /listo), esperar y repetir. Al terminar, `… turno.py soltar --origen "<chat>"`.

## Paso 1 — Juntar (solo lectura)
```bash
python3 .claude/skills/cierre-dia/cierre_dia.py
```
Cubre desde el último `CIERRE_DIA_*.md` (o, si no hay, desde el último «DÓNDE QUEDAMOS» de la
bitácora): **si un día quedó sin cierre, entra solo**. `--desde AAAA-MM-DD` lo fuerza.
Escribe `respaldo-truefie/trabajo/cierres/CIERRE_DIA_<fecha>.md` (local, sin commit) e imprime el bloque.

## Paso 2 — Revisar lo que marca con ⚠ antes de mostrarlo
- **ramas del período sin push / sin commitear / worktrees huérfanos:** de quién es cada cosa (no se
  sube ni se borra el trabajo de otra sesión sin preguntar);
- **marca de turno COLGADA:** decir de qué sesión es;
- **copias de la bitácora distintas** o **skills distintas del respaldo:** decirlo. Sincronizar la copia
  de `respaldo-truefie` es un commit en su `main`: solo con el OK de Andrea;
- **main o dev con ⚠** (GitHub distinto del local): traer con `git fetch` antes de cualquier cosa.

## Paso 3 — Mostrar a Andrea, en un solo mensaje
1. El bloque para Claude.ai (copiar tal cual).
2. **Para cerrar con tu OK:** cada T-<n> con su evidencia en una línea. Andrea aprueba en UN mensaje
   («cerrá 236 y 108») y CC los cierra con `tk_estado.py cerrar <n> --evidencia "…" --seco` → sin `--seco`.
   Los «falta evidencia: …» NO se cierran.
3. Lo que espera a una socia.

## Lo que /cierre-dia NO hace
- No escribe el ESTADO: eso lo hace Claude.ai con el bloque y los chats del día.
- No commitea ni publica nada, no cierra tickets sin el OK de Andrea en esta sesión.
