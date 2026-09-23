#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Baja de Odoo (SOLO LECTURA) las lineas de factura de los 6 terminados, con
los mismos campos que pide `uomBarrerFacturas`. El volcado NO se commitea:
lleva razones sociales de clientes y el repo es publico.

Baja DOS fotos:
  · hoy    — el estado actual (3534 y 3544 ya revertidas)
  · antes  — reconstruido: como estaba el dia que salieron, antes de las NC
             de hoy. Sirve para probar que las cuatro se habrian cazado.
"""
import sys, os, json, io
# la raiz del repo: .../Conciliacion, dos niveles arriba de este archivo
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from odoo_read import call

ENT_PROD=[451,452,453,503,472,519]
DESDE, HASTA = "2026-01-01", "2026-12-31"
# Las NC que se emitieron el 22-sep-2026. Para la foto "antes" se ignoran, o sea
# que la 3534 y la 3544 vuelven a estar vivas, que es como estaban ese dia.
NC_DE_HOY = [41766, 41775]

mv = call("account.move","search_read",
    [["move_type","=","out_invoice"],["state","=","posted"],
     ["invoice_date",">=",DESDE],["invoice_date","<=",HASTA]],
    fields=["id","name","move_type","state","invoice_date","partner_id","reversal_move_id"],
    limit=2000, order="invoice_date, id", context={"lang":"es_CR"})
ls = call("account.move.line","search_read",
    [["move_id","in",[m["id"] for m in mv]],["display_type","=","product"],
     ["product_id","in",ENT_PROD]],
    fields=["move_id","product_id","quantity","product_uom_id","price_subtotal"],
    limit=20000, context={"lang":"es_CR"})
uoms = call("uom.uom","search_read",[["category_id","=",1]],
    fields=["id","name","factor"], context={"lang":"es_CR","active_test":False})

def foto(quitar_nc):
    out=[]
    for m in mv:
        rm=[x for x in (m["reversal_move_id"] or []) if x not in quitar_nc]
        out.append({**m, "reversal_move_id": rm})
    return out

datos = {"uoms":uoms, "lineas":ls,
         "hoy": foto([]), "antes": foto(NC_DE_HOY)}
d=os.path.dirname(os.path.abspath(__file__))
io.open(os.path.join(d,"datos.json"),"w",encoding="utf-8").write(
    json.dumps(datos, ensure_ascii=False, indent=1, default=str))
viv_hoy=sum(1 for m in datos["hoy"] if not m["reversal_move_id"])
viv_ant=sum(1 for m in datos["antes"] if not m["reversal_move_id"])
print(f"  facturas 2026: {len(mv)} · lineas de los 6: {len(ls)} · uoms: {len(uoms)}")
print(f"  no revertidas HOY: {viv_hoy} · no revertidas ANTES del 22-sep: {viv_ant}")
