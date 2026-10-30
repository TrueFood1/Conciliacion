#!/bin/bash
# Prueba del plan a 4 meses (calendario de rrhh_feriado, horizonte, cierre, temporada,
# «Volver al plan» acotado). Casos sinteticos: no lleva datos de produccion.
#   herramientas/prueba_plan4m/correr.sh
set -e
D="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$D/../.." && pwd)"; cd "$R"
JSC=/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc
python3 "$D/armar.py" index.html "$D/nuevo.js"
"$JSC" "$D/nuevo.js" "$D/casos.js"
