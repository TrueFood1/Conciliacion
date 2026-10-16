#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
RE-FACTURAS AUTOMÁTICAS (15-oct-2026) — lo corre GitHub Actions en el repo PRIVADO respaldo-truefie,
cada hora de 6:00 a 20:00 hora de Costa Rica. Decisión de Andrea: opción B, automático.

Una factura nueva REEMPLAZA a la de un pedido entregado si se cumplen TODAS:
  a) la vieja está anulada con una NC publicada;
  b) la vieja es la factura VIGENTE de un pedido ya ENTREGADO en Truefie;
  c) la nueva cubre las mismas líneas del pedido de venta (terminados; el envío no cuenta);
  d) las cantidades de la nueva, en unidades, son iguales a lo que salió del congelador.
Si cumple todo: fila «ligada» en ent_refactura + vínculo en ent_pedido_factura (una transacción).
Si falla alguna: fila «apartada» con el motivo en palabras; NO se liga. Nada se borra.

LO QUE TOCA
  · Odoo: SOLO LECTURA (usuario lector, `ODOO_LECTOR_*`; además una lista de métodos permitidos acá).
  · Supabase: como `truefie_refactura` (REFACTURA_DB_URL). Ese usuario solo puede ejecutar
    refactura_entregas() y AGREGAR filas en ent_refactura y ent_pedido_factura (REFACTURA_AUTO.sql).

INTERRUPTOR
  Sin --escribir (o con REFACTURA_ENCENDIDA distinto de «si») corre EN SECO: lee todo, decide, imprime
  qué haría y no escribe nada. El workflow pasa --escribir solo si la variable del repo está en «si».

    python3 refacturas.py            # en seco
    python3 refacturas.py --escribir # de verdad (solo desde el workflow)
"""
import json, os, sys, time, xmlrpc.client
from collections import Counter

TERMINADOS = {451: "Blanco", 452: "Semillas", 453: "Francés", 503: "Buns", 472: "Pizza", 519: "Galletas"}
LECTURA_OK = {"search_read", "read"}
FIRMA = "automatico-refactura"
T0 = time.time()


def env(k):
    v = os.environ.get(k, "").strip()
    if not v:
        sys.exit("falta %s" % k)
    return v


class Odoo:
    def __init__(self):
        self.url, self.db = env("ODOO_URL").rstrip("/"), env("ODOO_DB")
        self.user, self.key = env("ODOO_LECTOR_USER"), env("ODOO_LECTOR_APIKEY")
        self.uid = xmlrpc.client.ServerProxy(self.url + "/xmlrpc/2/common").authenticate(self.db, self.user, self.key, {})
        if not self.uid:
            sys.exit("Odoo no aceptó al usuario lector")
        self.m = xmlrpc.client.ServerProxy(self.url + "/xmlrpc/2/object", allow_none=True)

    def call(self, modelo, metodo, *args, **kw):
        if metodo not in LECTURA_OK:
            raise RuntimeError("bloqueado: %s.%s (este trabajo solo lee Odoo)" % (modelo, metodo))
        return self.m.execute_kw(self.db, self.uid, self.key, modelo, metodo, list(args), kw)


def corto(nombre):
    return "…" + str(nombre or "")[-4:]


def main():
    escribir = "--escribir" in sys.argv and os.environ.get("REFACTURA_ENCENDIDA", "").strip().lower() == "si"
    import psycopg                                   # pip install 'psycopg[binary]' (lo hace el workflow)
    db = psycopg.connect(env("REFACTURA_DB_URL"), autocommit=False)
    odoo = Odoo()

    # ── Truefie: lo único que este usuario puede leer ──
    with db.cursor() as c:
        c.execute("select pedido_id, factura_vigente, facturas, entregado, salio, revisadas from public.refactura_entregas()")
        filas = c.fetchall()
    db.rollback()
    pedidos = {int(p): {"vig": fv, "fac": set(f or []), "ent": bool(e), "salio": {int(k): float(v) for k, v in (s or {}).items()},
                        "rev": {(int(x["vieja"]), int(x["nueva"]), x["resultado"]) for x in (r or [])}}
               for p, fv, f, e, s, r in filas}
    vig_de = {}                                       # factura vigente → pedido
    for p, d in pedidos.items():
        if d["vig"]:
            vig_de[int(d["vig"])] = p

    # ── Odoo: ¿cuáles vigentes de pedidos ENTREGADOS están anuladas? ──
    vigs = sorted(int(d["vig"]) for d in pedidos.values() if d["ent"] and d["vig"])
    viejas = [m for m in odoo.call("account.move", "read", vigs,
                                   fields=["name", "move_type", "state", "invoice_origin", "reversal_move_id", "create_date"])
              if m["reversal_move_id"]] if vigs else []
    acciones = []
    for v in viejas:
        ped = vig_de[v["id"]]
        so = v["invoice_origin"]
        if not so:
            print("· pedido %d: %s anulada sin pedido de venta: no hay con qué buscar el reemplazo (se mira a mano)" % (ped, corto(v["name"])))
            continue
        cands = odoo.call("account.move", "search_read",
                          [["move_type", "=", "out_invoice"], ["state", "=", "posted"], ["invoice_origin", "=", so],
                           ["reversal_move_id", "=", False], ["id", "!=", v["id"]], ["create_date", ">=", v["create_date"]]],
                          fields=["name", "invoice_origin", "create_date"])
        if not cands:
            print("· pedido %d: %s anulada, todavía sin factura nueva de %s" % (ped, corto(v["name"]), so))
            continue
        ncs = odoo.call("account.move", "read", v["reversal_move_id"], fields=["name", "state", "move_type"])
        a = any(n["state"] == "posted" and n["move_type"] == "out_refund" for n in ncs)
        ids = [v["id"]] + [n["id"] for n in cands]
        lin = {}
        for l in odoo.call("account.move.line", "search_read", [["move_id", "in", ids], ["display_type", "=", "product"]],
                           fields=["move_id", "product_id", "quantity", "product_uom_id", "sale_line_ids"]):
            lin.setdefault(l["move_id"][0], []).append(l)
        uoms = {u["id"]: u for u in odoo.call("uom.uom", "read",
                sorted({l["product_uom_id"][0] for ls in lin.values() for l in ls if l["product_uom_id"]}), fields=["factor"])}
        term = lambda mid: [l for l in lin.get(mid, []) if l["product_id"] and l["product_id"][0] in TERMINADOS]
        uds = lambda l: l["quantity"] / ((uoms.get(l["product_uom_id"][0]) or {}).get("factor") or 1) if l["product_uom_id"] else l["quantity"]
        for n in cands:
            mot = []
            if not a:
                mot.append("la anulación de %s no es una nota de crédito publicada" % corto(v["name"]))
            if len(cands) > 1:
                mot.append("hay %d facturas nuevas del mismo pedido de venta (%s)" % (len(cands), ", ".join(corto(x["name"]) for x in cands)))
            c_ok = sorted(i for l in term(v["id"]) for i in l["sale_line_ids"]) == sorted(i for l in term(n["id"]) for i in l["sale_line_ids"])
            if not c_ok:
                mot.append("no cubre las mismas líneas del pedido de venta")
            qn = Counter()
            for l in term(n["id"]):
                qn[l["product_id"][0]] += uds(l)
            qs = pedidos[ped]["salio"]
            dif = [(TERMINADOS[p], qn.get(p, 0), qs.get(p, 0)) for p in sorted(set(qn) | set(qs)) if abs(qn.get(p, 0) - qs.get(p, 0)) > 1e-6]
            d_ok = not dif
            if dif:
                mot.append("cantidades distintas a lo que salió: " + "; ".join("%s factura %g · salió %g" % x for x in dif))
            if n["id"] in vig_de and vig_de[n["id"]] != ped:
                mot.append("la factura nueva ya es la de otro pedido (#%d)" % vig_de[n["id"]])
            reglas = {"a": a, "b": True, "c": c_ok, "d": d_ok}
            res = "apartada" if mot else "ligada"
            if (v["id"], n["id"], res) in pedidos[ped]["rev"]:
                continue                                  # ya revisada con este resultado: nada que hacer
            acciones.append({"pedido": ped, "vieja": v, "nueva": n, "res": res, "reglas": reglas, "motivo": " · ".join(mot) or None})

    # ── Decidir y (si está encendido) escribir ──
    for x in acciones:
        linea = "%s · pedido %d · %s → %s%s" % (x["res"].upper(), x["pedido"], corto(x["vieja"]["name"]), corto(x["nueva"]["name"]),
                                                (" · " + x["motivo"]) if x["motivo"] else "")
        if not escribir:
            print("EN SECO · " + linea)
            continue
        with db.cursor() as c:
            c.execute("insert into public.ent_refactura (pedido_id, factura_vieja_id, factura_vieja_nombre, factura_nueva_id, "
                      "factura_nueva_nombre, resultado, reglas, motivo, creado_por) values (%s,%s,%s,%s,%s,%s,%s::jsonb,%s,%s) "
                      "on conflict do nothing",
                      (x["pedido"], x["vieja"]["id"], x["vieja"]["name"], x["nueva"]["id"], x["nueva"]["name"], x["res"],
                       json.dumps(x["reglas"]), x["motivo"], FIRMA))
            if x["res"] == "ligada":
                c.execute("insert into public.ent_pedido_factura (pedido_id, factura_id, factura_nombre, anulado, nota, creado_por) "
                          "values (%s,%s,%s,false,%s,%s)",
                          (x["pedido"], x["nueva"]["id"], x["nueva"]["name"],
                           "Re-factura automática: reemplaza %s (anulada con NC)" % corto(x["vieja"]["name"]), FIRMA))
        db.commit()
        print("ESCRITO · " + linea)

    print("pedidos leídos %d · entregados con vigente anulada %d · acciones %d · %s · %.1f s"
          % (len(pedidos), len(viejas), len(acciones), "ESCRIBE" if escribir else "EN SECO", time.time() - T0))
    db.close()


if __name__ == "__main__":
    main()
