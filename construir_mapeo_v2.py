#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Diccionario alias(Daniel) -> cliente real Odoo, robusto a 'nombre comercial != razón
social'. Señal principal: HUELLA DE FECHAS (los pedidos/entregas del cliente real caen
en las mismas fechas que los despachos de Daniel). Señales de apoyo: nombre, dirección.
Salida: propuesta por alias con confianza alto/medio/bajo. Los medio/bajo -> revisar.
"""
import csv, json, re, unicodedata, datetime
from collections import defaultdict

def norm(s):
    s=str(s or "").lower()
    return "".join(c for c in unicodedata.normalize("NFD",s) if unicodedata.category(c)!="Mn")
def toks(s):
    return set(t for t in re.split(r"[^a-z0-9]+",norm(s)) if len(t)>=4)
def d(s):
    return datetime.date.fromisoformat(str(s)[:10])
TOL=datetime.timedelta(days=2)

# alias -> fechas de despacho (de cruce_despachos.csv)
alias_dates=defaultdict(list)
for r in csv.DictReader(open("cruce_despachos.csv")):
    alias_dates[r["cliente"].strip()].append(d(r["fecha"]))

# partners: pid -> commercial_pid ; commercial_pid -> info
parts=json.load(open("cache_partners.json"))
comm_of={}; info={}
for p in parts:
    cid=p["commercial_partner_id"][0] if p.get("commercial_partner_id") else p["id"]
    comm_of[p["id"]]=cid
    if cid not in info: info[cid]={"name":"","blob":set(),"addr":set(),"vat":set()}
    # el registro madre define el nombre
    if cid==p["id"]:
        info[cid]["name"]=p["name"]
    info[cid]["blob"]|=toks(p.get("name"))|toks(p.get("commercial_company_name"))
    info[cid]["addr"]|=toks(p.get("street"))|toks(p.get("street2"))|toks(p.get("city"))
    if p.get("vat"): info[cid]["vat"].add(re.sub(r"\D","",str(p["vat"])))
def comm(pid): return comm_of.get(pid,pid)
for cid in info:  # asegurar nombre
    if not info[cid]["name"]:
        info[cid]["name"]=next((p["name"] for p in parts if p["id"]==cid),f"[{cid}]")

# fechas de actividad por commercial_pid (pedidos + pickings)
act=defaultdict(set)
for s in json.load(open("cache_saleorders.json")):
    if s.get("partner_id"):
        act[comm(s["partner_id"][0])].add(d(s["date_order"]))
        if s.get("commitment_date"): act[comm(s["partner_id"][0])].add(d(s["commitment_date"]))
for p in json.load(open("cache_pickings.json")):
    if p.get("partner_id"):
        act[comm(p["partner_id"][0])].add(d(p["scheduled_date"]))

def date_match(adates, pdates):
    m=0
    for a in adates:
        if any(abs(a-pp)<=TOL for pp in pdates): m+=1
    return m

def candidatos(alias):
    adates=alias_dates[alias]; at=toks(alias); n=len(adates)
    res=[]
    for cid,d_act in act.items():
        m=date_match(adates,d_act)
        if m==0: continue
        frac=m/n
        nm=1 if at & info[cid]["blob"] else 0
        ad=1 if at & info[cid]["addr"] else 0
        score=frac*2 + 0.4*nm + 0.4*ad + 0.01*m
        res.append((round(score,3),m,n,nm,ad,cid))
    res.sort(reverse=True)
    return res

ALTO=[]; MEDIO=[]; BAJO=[]
for alias in sorted(alias_dates):
    cs=candidatos(alias)
    if not cs:
        BAJO.append((alias,None,0,0,0,0,[])); continue
    top=cs[0]; sc,m,n,nm,ad,cid=top
    second=cs[1][0] if len(cs)>1 else 0
    margin=sc-second
    # ALTO: calce de fechas fuerte (>=2 fechas y todas) y sin empate, o con apoyo nombre/dir
    if m>=2 and m==n and (margin>=0.4 or nm or ad):
        ALTO.append((alias,cid,m,n,nm,ad,cs))
    elif m>=3 and m/n>=0.8:
        ALTO.append((alias,cid,m,n,nm,ad,cs))
    elif (m>=1 and m/n>=0.5) or nm or ad:
        MEDIO.append((alias,cid,m,n,nm,ad,cs))
    else:
        BAJO.append((alias,cid,m,n,nm,ad,cs))

def nm_name(cid): return info[cid]["name"] if cid else "—"
def ev(m,n,nm,ad): return f"fechas {m}/{n}"+(" +nombre" if nm else "")+(" +dirección" if ad else "")

with open("cruce_mapeo_propuesta.csv","w",newline="") as f:
    w=csv.writer(f); w.writerow(["alias","confianza","partner_id","partner_name","evidencia","alt1","alt2"])
    for tier,rows in [("alto",ALTO),("medio",MEDIO),("bajo",BAJO)]:
        for t in rows:
            alias,cid,m,n,nm,ad,cs=t
            alts=[f"[{c[5]}] {nm_name(c[5])} ({c[1]}/{n})" for c in cs[1:3]]
            w.writerow([alias,tier,cid or "",nm_name(cid),ev(m,n,nm,ad),*(alts+["",""])[:2]])

print(f"ALTO {len(ALTO)} | MEDIO {len(MEDIO)} | BAJO {len(BAJO)}\n")
print("== ALTO (auto) ==")
for alias,cid,m,n,nm,ad,cs in ALTO:
    print(f"  {alias:22} -> [{cid}] {nm_name(cid)[:40]:40} ({ev(m,n,nm,ad)})")
print("\n== MEDIO / BAJO (para Andrea) ==")
for tier,rows in [("MEDIO",MEDIO),("BAJO",BAJO)]:
    for alias,cid,m,n,nm,ad,cs in rows:
        alts=" | ".join(f"[{c[5]}] {nm_name(c[5])[:26]} ({c[1]}/{n})" for c in cs[:3]) if cs else "(sin candidato por fechas)"
        print(f"  [{tier}] {alias:20} -> {alts}")
