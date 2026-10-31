#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
revisar_tickets.py — la revisión de tickets del /retomar (19-oct-2026). SOLO LECTURA (pg_lector).

Lista los tickets NO resueltos (sin revisar · disponible · bloqueado · en curso · en validación) y marca:
  · CAMBIÓ   si el ticket, su estado, su marca o un detalle es posterior a --desde (la fecha del último /cierre);
  · SIN EXPLICACIÓN  si es «sin revisar» y no tiene «En palabras claras»;
  · PROPIO   los de «Mis pendientes»: los ve CC con pg_lector, pero no los mueve nadie más que Andrea.
No escribe nada: cerrar va por tk_estado.py (truefie_cc, con evidencia y con OK de Andrea) y explicar por
`tk_estado.py explicar` (solo Truefie). Los propios solo se proponen en el reporte.

    python3 herramientas/tickets/revisar_tickets.py --desde 2026-10-15
    python3 herramientas/tickets/revisar_tickets.py --desde 2026-10-15 --json   # para armar el reporte
    python3 herramientas/tickets/revisar_tickets.py --todos --buscar "permisos"  # ¿ya existe? (también cerrados,
                                                                                 #  pospuestos y descartados)
"""
import json, os, sys
AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(AQUI))
from pg_lector import Lector, clave                      # noqa: E402

ABIERTOS = ("sin_triar", "disponible", "bloqueado", "en_curso", "en_validacion")
NOMBRE = {"sin_triar": "sin revisar", "disponible": "disponible", "bloqueado": "bloqueado",
          "en_curso": "en curso", "en_validacion": "en validación", "cerrado": "cerrado",
          "pospuesto": "pospuesto", "descartado": "descartado"}

SQL = """
with u as (
  select t.id,
         greatest(t.creado_en,
                  coalesce((select max(e.creado_en) from ticket_estado e where e.ticket_id = t.id), t.creado_en),
                  coalesce((select max(m.creado_en) from ticket_marca m where m.ticket_id = t.id), t.creado_en),
                  coalesce((select max(d.creado_en) from ticket_detalle d where d.ticket_id = t.id), t.creado_en)) as ultimo
    from ticket t)
select v.id, t.ambito, coalesce(v.modulo, ''), v.estado, v.prioridad,
       left(regexp_replace(v.descripcion, '\\s+', ' ', 'g'), 140),
       (v.en_claro is not null) as explicada,
       (u.ultimo at time zone 'America/Costa_Rica')::text,
       v.espera, (v.criterio_terminado is not null) as con_criterio
  from v_ticket v join ticket t on t.id = v.id join u on u.id = v.id
 where (%(todos)s or v.estado in ('sin_triar','disponible','bloqueado','en_curso','en_validacion'))
   and (%(buscar)s is null or v.descripcion ilike '%%' || %(buscar)s || '%%'
        or exists (select 1 from ticket_detalle d where d.ticket_id = v.id and d.texto ilike '%%' || %(buscar)s || '%%'))
 order by v.id
"""


def main():
    desde = None
    if "--desde" in sys.argv:
        desde = sys.argv[sys.argv.index("--desde") + 1]
    todos = "--todos" in sys.argv
    buscar = sys.argv[sys.argv.index("--buscar") + 1] if "--buscar" in sys.argv else None
    lit = "null" if buscar is None else "'" + buscar.replace("'", "''") + "'"
    with Lector(clave()[0]) as db:
        cols, filas = db.consulta(SQL % {"todos": "true" if todos else "false", "buscar": lit})
    out = []
    for (tid, amb, mod, est, prio, desc, expl, ultimo, espera, crit) in filas:
        modulo = "Mis pendientes" if amb == "propio" else (mod.capitalize() if mod else "General")
        out.append({"id": int(tid), "modulo": modulo, "propio": amb == "propio", "estado": NOMBRE.get(est, est),
                    "prioridad": prio, "titulo": desc, "explicada": expl in (True, "t"), "ultimo": ultimo,
                    "cambio": bool(desde) and ultimo[:10] >= desde, "espera": espera, "con_criterio": crit in (True, "t")})
    if "--json" in sys.argv:
        print(json.dumps(out, ensure_ascii=False, indent=1)); return
    n_cambio = sum(x["cambio"] for x in out); sin = [x for x in out if x["estado"] == "sin revisar"]
    print(("tickets encontrados (cualquier estado)" if todos else "tickets no resueltos") + ": %d · cambiaron desde %s: %d · sin revisar: %d (sin explicación: %d) · propios: %d\n"
          % (len(out), desde or "—", n_cambio, len(sin), sum(not x["explicada"] for x in sin), sum(x["propio"] for x in out)))
    for x in out:
        marcas = " ".join(m for m, c in (("CAMBIÓ", x["cambio"]), ("SIN-EXPLICACIÓN", x["estado"] == "sin revisar" and not x["explicada"]),
                                          ("PROPIO", x["propio"])) if c)
        print("T-%-4d %-15s %-14s %-5s %s  %s" % (x["id"], x["modulo"][:15], x["estado"], x["prioridad"] or "", marcas, x["titulo"][:90]))


if __name__ == "__main__":
    main()
