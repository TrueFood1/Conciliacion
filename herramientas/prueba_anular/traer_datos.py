#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Baja las filas REALES que lee «Anular pedido» (§29), con la MISMA proyeccion
que pide el codigo. Supabase por pg_lector (READ ONLY) y Odoo por odoo_read
(solo lectura). El volcado NO se commitea: lleva razones sociales.

  Supabase: lo que lee bsLeer() para los pedidos de la prueba.
  Odoo:     las mismas lecturas que hace entOdooSalidas() para la factura de
            cada pedido con factura, guardadas por modelo|metodo.
"""
import sys, json, io, os
AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(os.path.dirname(AQUI))
sys.path.insert(0, os.path.join(RAIZ, 'herramientas'))
sys.path.insert(0, RAIZ)
import pg_lector as L

# 194 traslado hecho desde Truefie · 198 regalía sin nada en Odoo · 185 validado
# desde Truefie · 135 con factura, WH/OUT hecho A MANO en Odoo · 197 con factura y WH/OUT sin validar.
PEDIDOS = [194, 198, 185, 135, 197]
lec = L.Lector(L.clave()[0])
def j(sql):
    cols, filas = lec.consulta("select coalesce(json_agg(t),'[]'::json)::text from (%s) t" % sql)
    return json.loads(filas[0][0])
ped = ",".join(str(p) for p in PEDIDOS)
sub_al = "select id from ent_alisto where pedido_id in (%s)" % ped
datos = {
  "v_ent_pedido_estado": j("""select pedido_id, fecha_despacho, factura_id, factura_nombre, cliente_nombre, origen,
        motivo, alisto_id, responsable, preparado_en, salida_id, salida_en, salida_registrada_en, estado, fecha_ab_re_04
        from v_ent_pedido_estado where pedido_id in (%s)""" % ped),
  "ent_pedido": j("select id, destinatario from ent_pedido where id in (%s)" % ped),
  "ent_devolucion_vigente": j("select devolucion_id, pedido_id from ent_devolucion_vigente where pedido_id in (%s)" % ped),
  "ent_odoo_validacion": j("""select pedido_id, picking_nombre, validado_por, validado_en
        from ent_odoo_validacion where pedido_id in (%s)""" % ped),
  "ent_odoo_traslado": j("""select pedido_id, picking_nombre, creado_por, creado_en
        from ent_odoo_traslado where pedido_id in (%s)""" % ped),
  "ent_alisto": j("select id, pedido_id, responsable, creado_en, creado_por, anulado from ent_alisto where pedido_id in (%s)" % ped),
  "ent_anulacion": j("""select entidad, entidad_id, creado_por, creado_en, motivo from ent_anulacion
        where entidad='alisto' and entidad_id in (%s)""" % sub_al),
  "ent_alisto_linea": j("select id, alisto_id, producto_id, cant_uds, cant_uom from ent_alisto_linea where alisto_id in (%s)" % sub_al),
  "ent_alisto_lote": j("""select linea_id, lote, cant_uds, orden from ent_alisto_lote where linea_id in
        (select id from ent_alisto_linea where alisto_id in (%s))""" % sub_al),
  "ent_pedido_linea": j("""select pedido_id, producto_id, uom_id, uom_nombre, uom_factor, presentacion, cant_uds
        from ent_pedido_linea where pedido_id in (%s)""" % ped),
}
lec.cerrar()

# ── ODOO: la misma secuencia que entOdooSalidas, factura por factura ──
os.chdir(RAIZ)
import odoo_read as O
ctx = {"lang": "es_CR"}
odoo = {}
for f in datos["v_ent_pedido_estado"]:
    fid = f.get("factura_id")
    if not fid: continue
    R = {}
    R["account.move|read"] = O.call("account.move", "read", [fid], fields=["id","name","state","payment_state","reversal_move_id"], context=ctx)
    lin = O.call("account.move.line", "search_read", [["move_id","in",[fid]],["display_type","=","product"]],
                 fields=["move_id","sale_line_ids"], limit=20000, context=ctx)
    R["account.move.line|search_read"] = lin
    sol = sorted({x for l in lin for x in (l.get("sale_line_ids") or [])})
    sl = O.call("sale.order.line", "read", sol, fields=["id","order_id"], context=ctx) if sol else []
    R["sale.order.line|read"] = sl
    so = sorted({r["order_id"][0] for r in sl if r.get("order_id")})
    sor = O.call("sale.order", "read", so, fields=["id","picking_ids"], context=ctx) if so else []
    R["sale.order|read"] = sor
    pk = sorted({p for r in sor for p in (r.get("picking_ids") or [])})
    R["stock.picking|read"] = O.call("stock.picking", "read", pk, fields=["id","name","state","picking_type_code","scheduled_date","date_done"], context=ctx) if pk else []
    mv = O.call("stock.move", "search_read", [["picking_id","in",pk]], fields=["picking_id","product_id","quantity","product_uom","state"], limit=20000, context=ctx) if pk else []
    R["stock.move|search_read"] = mv
    us = sorted({m["product_uom"][0] for m in mv if m.get("product_uom")})
    R["uom.uom|read"] = O.call("uom.uom", "read", us, fields=["id","factor"], context=ctx) if us else []
    odoo[str(fid)] = R
    print("  odoo factura %s · %d salidas: %s" % (fid, len(R["stock.picking|read"]),
          ", ".join("%s=%s" % (p["name"], p["state"]) for p in R["stock.picking|read"])))

datos["_odoo"] = odoo
io.open(os.path.join(AQUI, "datos.json"), "w", encoding="utf-8").write(json.dumps(datos, ensure_ascii=False, indent=1, default=str))
for k, v in datos.items():
    print("  %-24s %d" % (k, len(v)))
