#!/usr/bin/env python3
"""Re-facturas automáticas · CORRIDA EN SECO (15-oct-2026). SOLO LECTURA: Odoo (lector) + Supabase (pg_lector).

Para cada factura de cliente de 2026 anulada (reversal_move_id) busca su reemplazo y aplica las 4 reglas:
  a) la vieja está anulada con NC (publicada)
  b) la vieja ya está entregada en un pedido de Truefie
  c) la nueva cubre las mismas líneas del pedido de venta (sale_line_ids), sin contar envío ni lo que no es terminado
  d) las cantidades de la nueva (en unidades) son iguales a lo que salió del congelador (alisto − no entregado)
Clasifica: LIGARÍA · YA LIGADO · APARTARÍA (con el motivo) · NO APLICA.
"""
import os, sys, collections
REPO = "/Users/andrea/Desktop/Practica CC/Conciliacion"
sys.path.insert(0, REPO); sys.path.insert(0, REPO + "/herramientas")
os.chdir(REPO)
from tf.odoo import call
from pg_lector import Lector, clave

TERMINADOS = {451, 452, 453, 503, 472, 519}
NOMBRE = {451: "Blanco", 452: "Semillas", 453: "Francés", 503: "Buns", 472: "Pizza", 519: "Galletas"}

# ── Truefie ───────────────────────────────────────────────────────────────
with Lector(clave()[0]) as db:
    _, pf = db.consulta("select pedido_id, factura_id, factura_nombre, id from public.ent_pedido_factura order by id")
    _, vig = db.consulta("select pedido_id, factura_id from public.ent_pedido_factura_vigente")
    _, est = db.consulta("select pedido_id, estado, alisto_id, salida_id from public.v_ent_pedido_estado")
    # El alisto VIGENTE del pedido (el de v_ent_pedido_estado): 67 y 134 tienen el original y el corregido.
    _, al = db.consulta("select e.pedido_id, l.producto_id, l.cant_uds, coalesce(l.no_se_entrega,false)::text, coalesce(l.cant_no_entregada,0) "
                        "from public.v_ent_pedido_estado e join public.ent_alisto_linea l on l.alisto_id=e.alisto_id")
pedidos_de = collections.defaultdict(set)            # factura_id → pedidos que la tuvieron alguna vez
for p, f, n, i in pf:
    if f: pedidos_de[int(f)].add(int(p))
vigente = {int(p): (int(f) if f else None) for p, f in vig}
estado = {int(p): (e, a, s) for p, e, a, s in est}
salio = collections.defaultdict(lambda: collections.Counter())   # pedido → {producto: uds que salieron}
for p, prod, uds, no, nd in al:
    if str(no).lower() in ('t', 'true'): continue      # pg_lector devuelve el booleano como texto
    salio[int(p)][int(prod)] += float(uds or 0) - float(nd or 0)

# ── Odoo ──────────────────────────────────────────────────────────────────
viejas = call("account.move", "search_read",
              [["move_type", "=", "out_invoice"], ["state", "=", "posted"], ["reversal_move_id", "!=", False],
               ["invoice_date", ">=", "2026-01-01"]],
              fields=["name", "invoice_origin", "invoice_date", "reversal_move_id", "partner_id", "create_date"], order="invoice_date asc")
origenes = sorted({v["invoice_origin"] for v in viejas if v["invoice_origin"]})
nuevas_todas = call("account.move", "search_read",
                    [["move_type", "=", "out_invoice"], ["state", "=", "posted"], ["invoice_origin", "in", origenes]],
                    fields=["name", "invoice_origin", "invoice_date", "reversal_move_id", "create_date"]) if origenes else []
ncs = {}
ids_nc = [i for v in viejas for i in v["reversal_move_id"]]
for n in call("account.move", "read", ids_nc, fields=["name", "state", "move_type"]) if ids_nc else []:
    ncs[n["id"]] = n
ids_lin = [v["id"] for v in viejas] + [n["id"] for n in nuevas_todas]
lineas = collections.defaultdict(list)
for l in call("account.move.line", "search_read", [["move_id", "in", ids_lin], ["display_type", "=", "product"]],
              fields=["move_id", "product_id", "quantity", "product_uom_id", "sale_line_ids"], limit=20000):
    lineas[l["move_id"][0]].append(l)
uoms = {u["id"]: u for u in call("uom.uom", "read", sorted({l["product_uom_id"][0] for ls in lineas.values() for l in ls if l["product_uom_id"]}),
                                  fields=["name", "factor", "uom_type"])}
def uds(l):
    u = uoms.get(l["product_uom_id"][0]) if l["product_uom_id"] else None
    return l["quantity"] / (u["factor"] or 1) if u else l["quantity"]
def terminados(mid):
    return [l for l in lineas[mid] if l["product_id"] and l["product_id"][0] in TERMINADOS]

res = collections.defaultdict(list)
for v in viejas:
    vid, so = v["id"], v["invoice_origin"]
    peds = sorted(pedidos_de.get(vid, set()))
    entregados = [p for p in peds if estado.get(p, (None,))[0] == "entregado"]
    if not entregados:
        res["NO APLICA"].append((v, None, "la vieja no está entregada en Truefie" + (" (está en pedido sin entregar)" if peds else ""))); continue
    ped = entregados[0]
    nc_ok = any(ncs.get(i, {}).get("state") == "posted" and ncs[i]["move_type"] == "out_refund" for i in v["reversal_move_id"])
    cands = [n for n in nuevas_todas if n["invoice_origin"] == so and n["id"] != vid and not n["reversal_move_id"]
             and n["create_date"] >= v["create_date"]] if so else []
    if not so:
        res["APARTARÍA"].append((v, None, "pedido %d: la vieja no tiene pedido de venta: no hay con qué buscar el reemplazo" % ped)); continue
    if not cands:
        res["NO APLICA"].append((v, None, "pedido %d: entregada y anulada, pero todavía no hay factura nueva del pedido de venta %s" % (ped, so))); continue
    motivos = []
    if not nc_ok: motivos.append("la anulación no es una NC publicada")
    if len(cands) > 1: motivos.append("hay %d facturas nuevas del mismo pedido de venta (%s)" % (len(cands), ", ".join(c["name"][-4:] for c in cands)))
    n = cands[0]
    sl_v = sorted(i for l in terminados(vid) for i in l["sale_line_ids"])
    sl_n = sorted(i for l in terminados(n["id"]) for i in l["sale_line_ids"])
    if sl_v != sl_n: motivos.append("no cubre las mismas líneas del pedido de venta")
    q_n = collections.Counter()
    for l in terminados(n["id"]): q_n[l["product_id"][0]] += uds(l)
    q_s = salio[ped]
    dif = [(NOMBRE[p], round(q_n.get(p, 0), 2), round(q_s.get(p, 0), 2)) for p in sorted(set(q_n) | set(q_s))
           if abs(q_n.get(p, 0) - q_s.get(p, 0)) > 1e-6]
    if dif: motivos.append("cantidades distintas a lo que salió: " + "; ".join("%s factura %s · salió %s" % d for d in dif))
    if vigente.get(ped) == n["id"]:
        res["YA LIGADO"].append((v, n, "pedido %d ya apunta a la nueva (ligado a mano) · las reglas: %s" % (ped, ("cumple las 4" if not motivos else " · ".join(motivos))))); continue
    if motivos: res["APARTARÍA"].append((v, n, "pedido %d: " % ped + " · ".join(motivos)))
    else:       res["LIGARÍA"].append((v, n, "pedido %d: cumple las 4 reglas" % ped))

print("Reversiones de facturas de cliente 2026:", len(viejas))
for k in ("LIGARÍA", "YA LIGADO", "APARTARÍA", "NO APLICA"):
    print("\n== %s · %d" % (k, len(res[k])))
    for v, n, m in res[k]:
        if k == "NO APLICA" and "no está entregada" in m: continue
        print("  …%s (%s, %s) → %s · %s" % (v["name"][-4:], v["invoice_date"], v["invoice_origin"] or "sin SO",
                                          ("…" + n["name"][-4:]) if n else "—", m))
print("\n(NO APLICA por no estar entregada en Truefie: %d — anulaciones administrativas o de antes de Truefie)"
      % sum(1 for v, n, m in res["NO APLICA"] if "no está entregada" in m))
