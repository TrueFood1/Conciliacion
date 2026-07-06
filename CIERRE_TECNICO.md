# Cierre técnico de sesión

Este checklist se corre al final de **toda sesión donde se tocó código**, sin que haya que pedirlo.

1. **`git status`** — ¿quedó algo sin commitear?
2. **Chequeo de secretos** sobre lo modificado: API keys, tokens, datos bancarios, correos personales. Ojo especial con archivos de **datos** que el `.gitignore` no matchea (el repo es público y sirve GitHub Pages).
3. **Commit** con mensaje descriptivo de la sesión.
4. **Push a `dev`** — respaldo, **SIEMPRE**.
5. **Actualizar la constante `BUILD`** (al inicio del bloque JS de `index.html`) con la fecha del día.
6. **¿Publicar?** Solo si Andrea lo dice explícito → `merge dev → main` + push. Si no, `main` se queda sirviendo la versión publicada vieja.

## Contexto de ramas

- **`dev`** — respaldo del trabajo en curso. Todo commit de sesión va acá primero.
- **`main`** — la versión publicada. GitHub Pages la sirve. Solo se mueve con decisión explícita de Andrea.
