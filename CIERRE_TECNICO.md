# Cierre técnico de sesión

Este checklist se corre al final de **toda sesión donde se tocó código**, sin que haya que pedirlo.

1. **`git status`** — ¿quedó algo sin commitear?
2. **Chequeo de secretos** sobre lo modificado: API keys, tokens, datos bancarios, correos personales. Ojo especial con archivos de **datos** que el `.gitignore` no matchea (el repo es público y sirve GitHub Pages).
3. **Commit** con mensaje descriptivo de la sesión.
4. **Push a `dev`** — respaldo, **SIEMPRE**.
5. **Actualizar la constante `BUILD`** (al inicio del bloque JS de `index.html`) con la fecha del día.
6. **Chequeo de ESQUEMA — `python3 esquema_check.py`. OBLIGATORIO antes de tocar `main`.**
   Saca los `from('tabla')` del `index.html` y verifica que cada objeto exista en
   Supabase. Si falta alguno, **no se publica**: primero se pega el `.sql` que lo
   crea. Sale con código 1 cuando falta algo, así que se puede encadenar.

   ⚠️ **Este paso existe por un incidente real.** El 17-ago se publicó a `main`
   código que dependía de `ENTREGAS_ETAPAS.sql` sin pegar. Andrea lo descubrió al
   día siguiente registrando entregas reales: tres errores encadenados en
   producción, y una factura a medio registrar. La bitácora del 16-ago lo
   advertía con todas las letras —"primero pegar el SQL, después publicar"— y
   aun así pasó, porque el checklist no lo pedía.

   **`loadcheck.py` no puede cazarlo**: corre el JS con un DOM de mentira y nunca
   toca la red. Sintaxis OK ≠ la página carga, y la página carga ≠ las tablas
   existen. Son tres chequeos distintos y hacen falta los tres.

7. **¿Publicar?** Solo si Andrea lo dice explícito → `merge dev → main` + push. Si no, `main` se queda sirviendo la versión publicada vieja.

## Contexto de ramas

- **`dev`** — respaldo del trabajo en curso. Todo commit de sesión va acá primero.
- **`main`** — la versión publicada. GitHub Pages la sirve. Solo se mueve con decisión explícita de Andrea.
