#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Constructor del diccionario de clientes (alias Daniel -> cliente Odoo).
Multiseñal: HUELLA DE FECHAS (pedidos/entregas) + nombre/comercial + cédula + dirección.
Sirve los confirmados por Andrea (cruce_overrides.csv + semillas) como verificado=true.
Salida: tf/clientes_dict.json  +  tabla [alias -> candidato -> confianza] de lo NO verificado / medio-bajo.

Reusa caches locales (cache_partners/saleorders/pickings.json). Correr 1 vez / al sumar clientes.
"""
import csv, json, re, unicodedata, datetime, os
from collections import defaultdict

def _n(s):
    s=str(s or "").lower()
    return "".join(c for c in unicodedata.normalize("NFD",s) if unicodedata.category(c)!="Mn")
def toks(s): return set(t for t in re.split(r"[^a-z0-9]+",_n(s)) if len(t)>=4)
def D(s): return datetime.date.fromisoformat(str(s)[:10])
TOL=datetime.timedelta(days=2)

# ── alias + fechas de despacho ──
alias_dates=defaultdict(list)
for r in csv.DictReader(open("cruce_despachos.csv")):
    alias_dates[r["cliente"].strip()].append(D(r["fecha"]))

# ── partners (cache): info por commercial_partner ──
parts=json.load(open("cache_partners.json"))
comm_of={p["id"]:(p["commercial_partner_id"][0] if p.get("commercial_partner_id") else p["id"]) for p in parts}
pname={p["id"]:p["name"] for p in parts}
pvat={p["id"]:(p.get("vat") or "") for p in parts}
name_blob=defaultdict(set); addr_blob=defaultdict(set)
for p in parts:
    c=comm_of[p["id"]]
    name_blob[c]|=toks(p.get("name"))|toks(p.get("commercial_company_name"))
    addr_blob[c]|=toks(p.get("street"))|toks(p.get("street2"))|toks(p.get("city"))
def comm(pid): return comm_of.get(pid,pid)

# ── huella de fechas por commercial_partner ──
act=defaultdict(set)
for s in json.load(open("cache_saleorders.json")):
    if s.get("partner_id"):
        act[comm(s["partner_id"][0])].add(D(s["date_order"]))
        if s.get("commitment_date"): act[comm(s["partner_id"][0])].add(D(s["commitment_date"]))
for p in json.load(open("cache_pickings.json")):
    if p.get("partner_id"): act[comm(p["partner_id"][0])].add(D(p["scheduled_date"]))

# ── mapeos confirmados por Andrea (verificado=true) ──
SEMILLAS={  # confirmados explícitos (los 6 que pasó Andrea)
  "Café Oteca":1179,"Mosaics escalante":666,"BM dominical":1008,"Café con que":1207,
  "Mocapan":662,"Organic market":1153,
}
verificado={}   # alias -> partner_id (o '661|649' / sentinela)
for r in csv.DictReader(open("cruce_overrides.csv")):
    verificado[r["alias_daniel"].strip()]=r["partner_id"].strip()
for a,pid in SEMILLAS.items():
    verificado[a]=str(pid)
# mapa automático (token) como fallback para los no confirmados
auto={}
if os.path.exists("cruce_cliente_map.csv"):
    for r in csv.DictReader(open("cruce_cliente_map.csv")):
        auto[r["alias_daniel"].strip()]=r["partner_id"].strip()

def parse_ids(v):
    if v in ("NO_VENTA","NO_REGISTRADO"): return v
    return [int(x) for x in str(v).split("|")]

def nombre_de(v):
    if v in ("NO_VENTA","NO_REGISTRADO"): return v
    return " / ".join(pname.get(i,f"[{i}]") for i in parse_ids(v))

def evaluar(alias, v):
    """Devuelve (confianza, evidencia) por huella de fechas + nombre + dirección."""
    if v in ("NO_VENTA","NO_REGISTRADO"):
        return "alto", v.lower()
    ids=parse_ids(v); ad=alias_dates.get(alias,[]); n=len(ad) or 1
    dates=set()
    for i in ids: dates|=act.get(comm(i),set())
    m=sum(1 for a in ad if any(abs(a-pp)<=TOL for pp in dates))
    nm=any(toks(alias)&name_blob[comm(i)] for i in ids)
    am=any(toks(alias)&addr_blob[comm(i)] for i in ids)
    frac=m/n
    if frac>=0.8 or (frac>=0.5 and nm) or (frac==1.0 and m>=2): conf="alto"
    elif frac>=0.5 or nm or am: conf="medio"
    else: conf="bajo"
    ev=f"fechas {m}/{len(ad)}"+(" +nombre" if nm else "")+(" +dirección" if am else "")
    return conf, ev

# ── construir registros para los ~58 alias ──
registros=[]; revisar=[]
for alias in sorted(alias_dates):
    v = verificado.get(alias) or auto.get(alias)
    ver = alias in verificado
    if not v:
        revisar.append((alias,"(sin candidato)","bajo","sin fechas/nombre"));
        registros.append({"alias":alias,"partner_id":None,"partner_name":None,"vat":None,
                          "confianza":"bajo","verificado_andrea":False,"evidencia":"sin candidato"})
        continue
    conf,ev = ("alto","confirmado por Andrea") if ver else evaluar(alias,v)
    ids = None if v in ("NO_VENTA","NO_REGISTRADO") else parse_ids(v)
    vat = (pvat.get(ids[0]) if ids else "") or ""
    registros.append({"alias":alias,
        "partner_id": v if v in ("NO_VENTA","NO_REGISTRADO") else (ids[0] if len(ids)==1 else "|".join(map(str,ids))),
        "partner_name": nombre_de(v), "vat": vat,
        "confianza": conf, "verificado_andrea": ver, "evidencia": ev})
    if not ver and conf in ("medio","bajo"):
        revisar.append((alias,nombre_de(v),conf,ev))

json.dump(registros, open("tf/clientes_dict.json","w"), ensure_ascii=False, indent=1)
ver_n=sum(1 for r in registros if r["verificado_andrea"])
print(f"clientes_dict.json: {len(registros)} alias  |  verificados por Andrea: {ver_n}  |  a revisar: {len(revisar)}\n")
print("== A VALIDAR POR ANDREA (no verificados, confianza media/baja) ==")
print(f"{'alias Daniel':22}{'confianza':10}{'evidencia':22} candidato Odoo")
for a,nom,conf,ev in sorted(revisar,key=lambda z:(z[2],z[0])):
    print(f"{a[:21]:22}{conf:10}{ev[:21]:22}{nom}")
