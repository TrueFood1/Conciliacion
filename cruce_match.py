#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Match por DESPACHO: ¿cada despacho del Excel tiene factura en Odoo? (objetivo #1)
y de paso ¿tiene entrega validada? (explica inventario inflado).
Match por cliente (vía cruce_cliente_map.csv) + fecha ±2 días. Read-only.
"""
import csv, datetime
from collections import defaultdict
from odoo_read import call

TOL=datetime.timedelta(days=2)
WIN_INI=datetime.date(2026,4,8); WIN_FIN=datetime.date(2026,6,26)
Q_INI=(WIN_INI-TOL).isoformat(); Q_FIN=(WIN_FIN+TOL).isoformat()

def d(s):  # 'YYYY-MM-DD' -> date
    return datetime.date.fromisoformat(str(s)[:10])

# 1) mapa alias->partner (int | lista de ints | sentinela 'NO_VENTA'/'NO_REGISTRADO')
def parse_pid(v):
    v=v.strip()
    if v in ("NO_VENTA","NO_REGISTRADO"): return v
    if "|" in v: return [int(x) for x in v.split("|")]
    return int(v)
amap={}
for r in csv.DictReader(open("cruce_cliente_map.csv")):
    amap[r["alias_daniel"].strip()]=int(r["partner_id"])
import os
if os.path.exists("cruce_overrides.csv"):
    for r in csv.DictReader(open("cruce_overrides.csv")):
        amap[r["alias_daniel"].strip()]=parse_pid(r["partner_id"])  # override gana

# 2) despachos del Excel
desp=[]
for r in csv.DictReader(open("cruce_despachos.csv")):
    desp.append({"fecha":d(r["fecha"]),"cliente":r["cliente"].strip(),
                 "productos":r["productos"],"pid":amap.get(r["cliente"].strip())})

# 3) Odoo: facturas de cliente en ventana ±2
print("Leyendo facturas de cliente de Odoo…")
inv=call("account.move","search_read",
    [["move_type","in",["out_invoice","out_receipt"]],
     ["invoice_date",">=",Q_INI],["invoice_date","<=",Q_FIN]],
    fields=["partner_id","commercial_partner_id","invoice_date","name","amount_total","state"],
    limit=5000)
print(f"  facturas traídas: {len(inv)}")
inv_by_partner=defaultdict(list)
for m in inv:
    for key in ("partner_id","commercial_partner_id"):
        if m.get(key): inv_by_partner[m[key][0]].append(m)

# 4) Odoo: entregas (pickings salientes done). Match por SCHEDULED_DATE (fecha
#    planificada = fecha de despacho), NO date_done: validan días tarde y date_done
#    queda 3-7d después → daba falsos "sin entrega". Verificado contra Automercado.
print("Leyendo entregas validadas (stock.picking outgoing done, por scheduled_date)…")
pick=call("stock.picking","search_read",
    [["picking_type_id.code","=","outgoing"],["state","=","done"],
     ["scheduled_date",">=",Q_INI+" 00:00:00"],["scheduled_date","<=",Q_FIN+" 23:59:59"]],
    fields=["partner_id","scheduled_date","date_done","origin","name"],limit=5000)
print(f"  entregas traídas: {len(pick)}")
pick_by_partner=defaultdict(list)
for p in pick:
    if p.get("partner_id"): pick_by_partner[p["partner_id"][0]].append(p)

def cerca(fecha, registros, campo):
    for r in registros:
        rf=r.get(campo)
        if rf and abs(d(rf)-fecha)<=TOL: return r
    return None

def mas_cercana(fecha, registros, campo):
    mejor=None; mejorg=None
    for r in registros:
        rf=r.get(campo)
        if not rf: continue
        g=abs((d(rf)-fecha).days)
        if mejorg is None or g<mejorg: mejorg=g; mejor=r
    return mejor,mejorg

def recolectar(pid, by):
    ids = pid if isinstance(pid,list) else [pid]
    out=[]
    for i in ids: out += by.get(i,[])
    return out

# 5) evaluar cada despacho
for x in desp:
    pid=x["pid"]; x["nota"]=""; x["nota_ent"]=""
    if pid is None:
        x["factura"]="sin_mapear"; x["entrega"]="sin_mapear"; continue
    if pid=="NO_VENTA":
        x["factura"]="N/A (reposición)"; x["entrega"]="-"; x["nota"]="reposición sin FE — no es venta"; continue
    if pid=="NO_REGISTRADO":
        x["factura"]="sin cliente en Odoo"; x["entrega"]="-"; x["nota"]="cliente no registrado en Odoo"; continue
    invs=recolectar(pid, inv_by_partner); picks=recolectar(pid, pick_by_partner)
    fi=cerca(x["fecha"], invs, "invoice_date")
    en=cerca(x["fecha"], picks, "scheduled_date")
    x["factura"]= ("SI "+fi["name"]) if fi else "NO"
    x["entrega"]= "SI" if en else "NO"
    if not fi:  # mostrar la factura más cercana y a cuántos días (timing vs sin cobrar)
        nf,ng=mas_cercana(x["fecha"], invs, "invoice_date")
        x["nota"]= (f"factura más cercana: {nf['invoice_date']} ({ng}d, ₡{nf['amount_total']:,.0f})"
                    if nf else "ninguna factura de este cliente en la ventana")
    x["nota_ent"]=""
    if not en:  # picking más cercano (timing vs sin entrega real)
        npk,npg=mas_cercana(x["fecha"], picks, "scheduled_date")
        x["nota_ent"]= (f"picking más cercano: {str(npk['scheduled_date'])[:10]} ({npg}d)"
                        if npk else "ningún picking de salida de este cliente en la ventana")

# 6) salida: primero los que incluyen Semillas
def es_sem(p): return "Semillas" in p["productos"]
sem=[x for x in desp if es_sem(x)]
def mark(v): return v if v.startswith("SI") or v=="sin_mapear" else ("*** "+v+" ***")
print(f"\n== DESPACHOS con SEMILLAS ({len(sem)}) — *** NO *** = sin factura ==")
print(f"{'fecha':11}{'cliente':22}{'factura':16}{'entrega':9} productos")
for x in sorted(sem,key=lambda z:(z['fecha'],z['cliente'])):
    print(f"{str(x['fecha']):11}{x['cliente'][:21]:22}{mark(x['factura'])[:15]:16}{x['entrega']:9} {x['productos'][:46]}")

# 7) SIN FACTURA (lo que importa) — despachos mapeados sin factura ±2d
mapd=[x for x in desp if x["pid"] is not None]
sinf=[x for x in mapd if x["factura"]=="NO"]
print(f"\n== *** DESPACHOS SIN FACTURA (mapeados) — {len(sinf)} === plata a revisar ==")
print(f"{'fecha':11}{'cliente':22}{'entrega':9} productos / nota")
for x in sorted(sinf,key=lambda z:(z['fecha'],z['cliente'])):
    print(f"{str(x['fecha']):11}{x['cliente'][:21]:22}{x['entrega']:9} {x['productos'][:40]}")
    print(f"{'':11}└─ {x['nota']}")

sine=[x for x in mapd if x["entrega"]=="NO"]
sine=[x for x in mapd if x["entrega"]=="NO"]
nomap=[x for x in desp if x["pid"] is None]
print(f"\n== RESUMEN (todos los despachos) ==")
print(f"  despachos totales: {len(desp)}  | mapeados: {len(mapd)}  | sin mapear cliente: {len(nomap)}")
print(f"  mapeados SIN factura: {len(sinf)}   <-- plata sin cobrar (revisar)")
print(f"  mapeados SIN entrega validada: {len(sine)}   <-- inventario inflado")
with open("cruce_resultado.csv","w",newline="") as f:
    w=csv.writer(f); w.writerow(["fecha","cliente","productos","factura","entrega_validada","nota","nota_entrega"])
    for x in sorted(desp,key=lambda z:(z['fecha'],z['cliente'])):
        w.writerow([x["fecha"],x["cliente"],x["productos"],x["factura"],x["entrega"],x.get("nota",""),x.get("nota_ent","")])
print("→ cruce_resultado.csv")
