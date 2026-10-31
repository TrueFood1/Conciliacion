---
name: cierre
description: RETIRADA el 22-oct-2026 (protocolo de cierre de Andrea, 21-oct). Ya no se usa — cada sesión cierra con /listo y una sola sesión corre /cierre-dia cuando Andrea lo pide. Si alguien pide /cierre, explicar eso y ofrecer /listo.
---
<!-- RETIRADA el 2026-10-22 (decisión de Andrea, 21-oct 12:52). El texto completo de la versión
anterior está en el historial de git: `git -C Conciliacion log -p -- herramientas/skills/cierre/SKILL.md`. -->

# /cierre — retirada

El 20-oct seis sesiones cerraron a la vez con este `/cierre`: cuatro ESTADOS el mismo día, un choque de
BUILD b114/b115 y un cierre de dos horas. Desde el 22-oct se reemplaza por dos:

- **`/listo`** — cada sesión, al terminar SU tarea: turno, nada sin commitear, push de SU rama (nunca
  main), tickets con su origen y una entrada en la bitácora.
- **`/cierre-dia`** — UNA sola sesión, cuando Andrea lo pide: junta el día de todos los repos y arma el
  `CIERRE_DIA_<fecha>.md` y el bloque para Claude.ai. El ESTADO lo escribe Claude.ai.

Si te pidieron `/cierre`: decilo en una línea y ofrecé `/listo` (o `/cierre-dia`, si es el cierre del día).
