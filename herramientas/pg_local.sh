#!/bin/sh
# pg_local.sh — levanta un PostgreSQL temporal con el modulo Personal cargado,
# para correr los ensayos ACA en vez de en produccion.
#
# POR QUE: hasta el 16-oct-2026 los pegados se probaban pegandolos en Supabase.
# Un error de ejecucion (no de sintaxis) solo aparecia ahi. Con esto el ensayo del
# pegado 10 corrio local y encontro cinco fallas que ninguna lectura habia visto.
#
# NO ES PRODUCCION: los roles anon/authenticated existen, los dos disparadores de
# eventos (ensure_rls y asistente_politicas) estan replicados, y auth.jwt() es un
# stub que lee request.jwt.claims. No hay datos reales de nadie.
#
#   sh herramientas/pg_local.sh up      crea y carga
#   sh herramientas/pg_local.sh psql     abre una sesion
#   sh herramientas/pg_local.sh run X.sql
#   sh herramientas/pg_local.sh down     apaga y borra
set -e
PG=/opt/homebrew/opt/postgresql@17/bin
D="${TMPDIR:-/tmp}/zzpg_data"; S=/tmp/zzpg
CONN="host=$S port=55432 user=postgres dbname=truefie"
case "$1" in
  up)
    rm -rf "$D" "$S"; mkdir -p "$S"
    "$PG/initdb" -D "$D" -U postgres --auth=trust -E UTF8 >/dev/null
    "$PG/pg_ctl" -D "$D" -o "-k $S -h '' -p 55432" -l "$D/log" start >/dev/null
    sleep 2
    "$PG/psql" "host=$S port=55432 user=postgres dbname=postgres" -qc \
      "create database truefie;" \
      -c "do \$\$ begin
            if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
            if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
            if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin; end if;
          end \$\$;"
    echo "clúster arriba · cargá el módulo con los .sql del repo en orden"
    ;;
  psql) exec "$PG/psql" "$CONN" ;;
  run)  shift; exec "$PG/psql" "$CONN" -f "$1" ;;
  down) "$PG/pg_ctl" -D "$D" stop >/dev/null 2>&1 || true; rm -rf "$D" "$S"; echo "apagado y borrado" ;;
  *) echo "uso: sh herramientas/pg_local.sh up|psql|run <archivo>|down"; exit 1 ;;
esac
