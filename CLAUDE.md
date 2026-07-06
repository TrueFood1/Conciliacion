# Conciliación / Truefie — instrucciones del repo

## Cierre de sesión (regla fija)

Al cierre de **toda sesión donde se tocó código**, correr el checklist de
[`CIERRE_TECNICO.md`](CIERRE_TECNICO.md) **sin que haya que pedirlo**.

- El **push va a `dev`** (respaldo, siempre).
- A **`main`** solo con **decisión explícita de Andrea** (`main` sirve la versión publicada por GitHub Pages).

## Seguridad

- El repo es **público**. Nunca commitear credenciales, tokens ni datos bancarios/personales.
- `conexion_prod.env`, `.proxy_token`, el extracto bancario (`*.xls`, `extracto_limpio.csv/.js`) y `proxy_lectura/` (repo propio) están en `.gitignore` — mantenerlos ahí.
