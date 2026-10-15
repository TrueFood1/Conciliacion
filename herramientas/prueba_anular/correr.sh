#!/bin/bash
# Corre la prueba de «Anular pedido» (§29) contra la version de trabajo Y contra `main`.
# Que falle contra main es el punto: una prueba que pasa en las dos no prueba nada.
#
#   1) python3 herramientas/prueba_anular/traer_datos.py   (baja filas reales, solo lectura)
#   2) herramientas/prueba_anular/correr.sh
#
# datos.json NO se commitea: lleva razones sociales y el repo es publico.
set -e
D="$(cd "$(dirname "$0")" && pwd)"
R="$(cd "$D/../.." && pwd)"
cd "$R"
[ -f "$D/datos.json" ] || { echo "falta $D/datos.json — corre primero traer_datos.py"; exit 1; }
python3 "$D/armar.py" index.html "$D/nuevo.js"
git show main:index.html > "$D/index_main.html"
python3 "$D/armar.py" "$D/index_main.html" "$D/viejo.js"
for v in nuevo viejo; do
  printf 'var SALIDA="%s/out_%s.txt";\n' "$D" "$v" > "$D/run_$v.js"
  cat "$D/$v.js" "$D/correr.js" >> "$D/run_$v.js"
  rm -f "$D/out_$v.txt"
  osascript -l JavaScript "$D/run_$v.js" >/dev/null 2>"$D/err_$v.txt" || true
done
sleep 1
echo "══ version de trabajo ══"; tail -3 "$D/out_nuevo.txt" 2>/dev/null || cat "$D/err_nuevo.txt"
echo; echo "══ main (tiene que fallar lo nuevo) ══"; tail -3 "$D/out_viejo.txt" 2>/dev/null || tail -3 "$D/err_viejo.txt"
echo; echo "detalle completo: $D/out_nuevo.txt"
