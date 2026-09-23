#!/bin/bash
# Prueba de la deteccion de unidades, contra las 1.444 lineas reales de 2026.
#   1) python3 herramientas/prueba_unidades/traer_datos.py   (una vez)
#   2) herramientas/prueba_unidades/correr.sh
# datos.json NO se commitea: lleva razones sociales.
set -e
D="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$D/../.." && pwd)"; cd "$R"
[ -f "$D/datos.json" ] || { echo "falta $D/datos.json — corre primero traer_datos.py"; exit 1; }
python3 "$D/armar.py" index.html "$D/nuevo.js"
printf 'var SALIDA="%s/out.txt";\n' "$D" > "$D/run.js"
cat "$D/nuevo.js" "$D/correr.js" >> "$D/run.js"
rm -f "$D/out.txt"
osascript -l JavaScript "$D/run.js" >/dev/null 2>"$D/err.txt" || true
sleep 1
cat "$D/out.txt" 2>/dev/null || cat "$D/err.txt"
