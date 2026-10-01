#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
prueba_empaque_demo.py — ¿Odoo 17 elige SOLO el "Embalaje" en la línea de compra?
SOLO CONTRA LA DEMO (demotruefood). Producción no se toca: usa odoo_demo.py, que
se niega a arrancar si la URL no es la demo.

POR QUÉ (30-sep-2026, opción A de materia prima): si al comprar Odoo pone solo el
empaque cuando la cantidad es múltiplo, la presentación de la última compra sale
sola de Odoo y no depende de que nadie la elija a mano.

QUÉ HACE
  1. Confirma que es la demo y que "Empaquetados del producto" está activo.
  2. Busca Levadura y le asegura un empaque de COMPRA "Paquete 500 g" = 500 (en la
     unidad de stock del producto, gramos). Si ya existe, lo usa.
  3. Arma órdenes de compra EN BORRADOR, una por caso, y lee qué Embalaje quedó:
        25 kg          (= 50 paquetes, calza)
        25.000 g       (lo mismo en gramos, calza)
        25,2 kg        (= 50,4 paquetes, no calza)
  4. Borra las órdenes de prueba y, si lo creó él, el empaque. Con --dejar no borra.

USO
    python3 herramientas/prueba_empaque_demo.py            # corre y limpia
    python3 herramientas/prueba_empaque_demo.py --dejar    # deja todo para mirarlo en la demo

Necesita conexion_demo.env (URL de la demo, DB ACTUAL, usuario, API key de la demo).
"""
import os, sys
RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, RAIZ); os.chdir(RAIZ)
import odoo_demo as D

# Escrituras que esta prueba necesita, SOLO en la demo y por (modelo, método).
D.ESCRITURA_OK.update({
    "product.packaging":   ["create", "unlink"],
    "purchase.order":      ["create", "unlink"],
})
DEJAR = "--dejar" in sys.argv
ES = {"lang": "es_CR"}

def main():
    D._connect()
    print("demo:", D.ENV["ODOO_URL"], "· DB", D.ENV["ODOO_DB"], "· uid", D.uid())

    # 1 · ¿empaques activos? (el grupo que enciende el ajuste)
    g = D.call("ir.model.data", "search_read",
               [["module", "=", "product"], ["name", "=", "group_stock_packaging"]], fields=["res_id"])
    gid = g and g[0]["res_id"]
    u = D.call("res.users", "read", [D.uid()], fields=["groups_id"])[0]
    activo = bool(gid and gid in u["groups_id"])
    print("Empaquetados del producto activo:", "SÍ" if activo else "NO — activarlo en Inventario › Ajustes y volver a correr")
    if not activo:
        sys.exit(1)

    # 2 · Levadura y su empaque de compra
    ps = D.call("product.product", "search_read", [["name", "ilike", "levadura"]],
                fields=["id", "name", "uom_id", "uom_po_id"], context=ES)
    if not ps:
        sys.exit("no encuentro Levadura en la demo")
    p = ps[0]
    print("producto:", p["id"], p["name"], "· stock", p["uom_id"][1], "· compra", p["uom_po_id"][1])
    ex = D.call("product.packaging", "search_read",
                [["product_id", "=", p["id"]], ["purchase", "=", True]], fields=["id", "name", "qty"], context=ES)
    creado = None
    emp = next((e for e in ex if abs(e["qty"] - 500) < 1e-9), None)
    if emp:
        print("empaque existente:", emp)
    else:
        creado = D.call("product.packaging", "create",
                        {"name": "Paquete 500 g", "product_id": p["id"], "qty": 500, "purchase": True})
        emp = {"id": creado, "name": "Paquete 500 g", "qty": 500}
        print("empaque creado:", emp)

    # 3 · órdenes de prueba
    uoms = {x["name"]: x["id"] for x in D.call("uom.uom", "search_read", [["name", "in", ["g", "kg"]]],
                                               fields=["id", "name"], context=ES)}
    prov = D.call("res.partner", "search_read", [["supplier_rank", ">", 0]], fields=["id", "name"], limit=1)
    if not prov:
        prov = D.call("res.partner", "search_read", [["is_company", "=", True]], fields=["id", "name"], limit=1)
    casos = [("25 kg", 25, "kg"), ("25.000 g", 25000, "g"), ("25,2 kg", 25.2, "kg")]
    pos = []
    for rot, q, un in casos:
        po = D.call("purchase.order", "create", {"partner_id": prov[0]["id"], "order_line": [(0, 0, {
            "product_id": p["id"], "product_qty": q, "product_uom": uoms[un]})]})
        pos.append(po)
        ln = D.call("purchase.order.line", "search_read", [["order_id", "=", po]],
                    fields=["product_qty", "product_uom", "product_packaging_id", "product_packaging_qty"], context=ES)[0]
        eleg = ln["product_packaging_id"][1] if ln["product_packaging_id"] else "(ninguno)"
        print("  %-9s → Embalaje: %-16s · cantidad de embalaje: %s" % (rot, eleg, ln["product_packaging_qty"]))

    # 4 · limpieza
    if DEJAR:
        print("--dejar: quedan las órdenes", pos, "y el empaque", emp["id"])
        return
    D.call("purchase.order", "unlink", pos)
    if creado:
        D.call("product.packaging", "unlink", [creado])
    print("limpio: órdenes borradas" + (" y empaque borrado" if creado else ""))

if __name__ == "__main__":
    main()
