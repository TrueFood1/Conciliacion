# Cierre técnico de sesión

Este checklist se corre al final de **toda sesión donde se tocó código**, sin que haya que pedirlo.

1. **`git status`** — ¿quedó algo sin commitear?
2. **Chequeo de secretos** sobre lo modificado: API keys, tokens, datos bancarios, correos personales. Ojo especial con archivos de **datos** que el `.gitignore` no matchea (el repo es público y sirve GitHub Pages).
3. **Commit** con mensaje descriptivo de la sesión.
4. **Que el trabajo quede fuera del disco.** El objetivo del paso es ése y no una
   rama en particular: si la sesión se pierde, nada puede vivir sólo acá.

   Se cumple de cualquiera de estas dos formas:
   - **push de la rama de trabajo a `origin`** (`git push -u origin <rama>`), y
     **si además se publicó**, el `merge` a `main` + push. Las dos juntas son
     respaldo y publicación: el paso está cumplido y **`dev` no se toca**.
   - **push a `dev`**, cuando el trabajo va a seguir ahí y no tiene rama propia.

   ⚠️ **`dev` NO es el destino por defecto.** Decidido por Andrea el
   15-sep-2026, después de b59. **`dev` tiene el calendario de Lorena sin
   publicar** (entró por el merge `fa0b1b1` y se quedó ahí cuando b57 salió sin
   él). Empujar el trabajo de Andrea a `dev` mezcla el trabajo de dos personas
   en una rama sin que nadie lo haya decidido, y la próxima publicación tiene
   que volver a separarlos — que es exactamente lo que costó armar `b57` a mano,
   con cherry-picks, el 14-sep.

   Este checklist decía "Push a `dev` — respaldo, **SIEMPRE**". Lo decía por una
   razón buena (que nada se pierda) y con un destino que dejó de ser el
   correcto. La razón se queda; el destino se elige.
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

8. **Respaldar lo que git NO respalda.** `BITACORA.md`, los `PEGADO_*.sql` y los
   `CAMBIO_*.sql` que todavía no entraron a una rama están **gitignored** —el repo
   es público y llevan razones sociales, montos y SQL de producción—, así que un
   `push` no los salva. Van al repo **privado** `TrueFood1/respaldo-truefie`, en
   `trabajo/`:

   ```bash
   cd respaldo-truefie && git pull --ff-only
   cp ../Conciliacion/PEGADO_*.sql trabajo/pegados/
   cp ../Conciliacion/BITACORA.md trabajo/
   git add trabajo && git commit -m "Respaldo del trabajo local: <fecha>" && git push
   ```

   ⚠️ **Antes de copiar, comparar contra los `.env`.** Ningún archivo puede llevar
   adentro una clave, API key o cadena de conexión. Privado no quiere decir que dé
   lo mismo: una credencial en un repo sobrevive a su propia rotación. Los
   identificadores (correos, nombre de la base) sí pueden ir.

   ⚠️ **Este paso existe por un agujero real, encontrado el 22-sep-2026.** Se
   midió `git ls-tree origin/main` del repo de respaldo: 20 archivos, 16 dumps y
   4 del propio repo. **Ni un `PEGADO_*.sql`, ni `BITACORA.md`.** El respaldo
   diario es un `pg_dump` que corre en un runner de GitHub, y ese runner no tiene
   forma de ver la Mac de Andrea — nunca pudo haber copiado un archivo local.
   Peor: la skill `/retomar` afirmaba que la bitácora se respaldaba ahí. Era
   falso, y se creyó durante semanas. La base sí estaba cubierta; el trabajo del
   día, no.

7. **¿Publicar?** Solo si Andrea lo dice explícito → `merge dev → main` + push. Si no, `main` se queda sirviendo la versión publicada vieja.

## Contexto de ramas

- **`dev`** — respaldo del trabajo en curso **que no tiene rama propia**. Desde el
  15-sep-2026 ya no es el destino por defecto: hoy además carga el calendario de
  Lorena sin publicar, así que empujar ahí mezcla trabajo de dos personas. Ver el
  paso 4.
- **rama de trabajo** (`lotes-disponibles`, `publicar-b57`, …) — lo normal. Nace
  de `main`, se respalda en `origin` con su propio nombre, y de ahí se publica.
  ⚠️ `git branch X origin/main` deja el upstream apuntando a **`main`**: un
  `git push` pelado publica sin querer. Medido al armar b57. Se desarma con
  `git branch --unset-upstream`, o se evita creando la rama con `--no-track`.
- **`main`** — la versión publicada. GitHub Pages la sirve. Solo se mueve con decisión explícita de Andrea.
