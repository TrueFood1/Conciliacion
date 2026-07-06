#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Valida el diccionario VIGENTE (cruce_cliente_map.csv + cruce_overrides.csv):
para cada alias, ¿las fechas de pedidos/entregas del cliente ASIGNADO calzan con
los despachos de Daniel? Bajo calce + sin match de nombre = SOSPECHOSO (revisar).
"""
import csv, json, re, unicodedata, datetime
from collections import defaultdict

def norm(s):
    s=str(s or "").lower()
    return "".join(c for c in unicodedata.normalize("NFD",s) if unicodedata.category(c)!="Mn")
def toks(s): return set(t for t in re.split(r"[^a-z0-9]+",norm(s)) if len(t)>=4)
def d(s): return datetime.date.fromisoformat(str(s)[:10])
TOL=datetime.timedelta(days=2)

# diccionario vigente
amap={}
for r in csv.DictReader(open("cruce_cliente_map.csv")): amap[r["alias_daniel"].strip()]=r["partner_id"]
for r in csv.DictReader(open("cruce_overrides.csv")):    amap[r["alias_daniel"].strip()]=r["partner_id"]

alias_dates=defaultdict(list)
for r in csv.DictReader(open("cruce_despachos.csv")):
    alias_dates[r["cliente"].strip()].append(d(r["fecha"]))

parts=json.load(open("cache_partners.json"))
comm_of={p["id"]:(p["commercial_partner_id"][0] if p.get("commercial_partner_id") else p["id"]) for p in parts}
pname={p["id"]:p["name"] for p in parts}
name_blob=defaultdict(set); addr_blob=defaultdict(set)
for p in parts:
    cid=comm_of[p["id"]]
    name_blob[cid]|=toks(p.get("name"))|toks(p.get("commercial_company_name"))
    addr_blob[cid]|=toks(p.get("street"))|toks(p.get("street2"))|toks(p.get("city"))
def comm(pid): return comm_of.get(pid,pid)
act=defaultdict(set)
for s in json.load(open("cache_saleorders.json")):
    if s.get("partner_id"):
        act[comm(s["partner_id"][0])].add(d(s["date_order"]))
        if s.get("commitment_date"): act[comm(s["partner_id"][0])].add(d(s["commitment_date"]))
for p in json.load(open("cache_pickings.json")):
    if p.get("partner_id"): act[comm(p["partner_id"][0])].add(d(p["scheduled_date"]))

rows=[]
for alias in sorted(alias_dates):
    pid=amap.get(alias,"")
    ad=alias_dates[alias]; n=len(ad)
    if pid in ("NO_VENTA","NO_REGISTRADO"):
        rows.append((alias,pid,pid,n,n,"-","-","ok-especial")); continue
    if not pid:
        rows.append((alias,"","SIN MAPEAR",0,n,"no","no","SOSPECHOSO")); continue
    ids=[int(x) for x in str(pid).split("|")]
    dates=set()
    for i in ids: dates|=act.get(comm(i),set())
    m=sum(1 for a in ad if any(abs(a-pp)<=TOL for pp in dates))
    nm="sí" if any(toks(alias)&name_blob[comm(i)] for i in ids) else "no"
    am="sí" if any(toks(alias)&addr_blob[comm(i)] for i in ids) else "no"
    frac=m/n
    if frac>=0.8 or (frac>=0.5 and nm=="sí"): estado="ok"
    elif nm=="sí" or am=="sí": estado="probable"
    else: estado="SOSPECHOSO"
    nm_disp=" / ".join(pname.get(i,f"[{i}]") for i in ids)
    rows.append((alias,pid,nm_disp,m,n,nm,am,estado))

orden={"SOSPECHOSO":0,"probable":1,"ok":2,"ok-especial":3}
rows.sort(key=lambda r:(orden.get(r[7],9),-r[4]))
print(f"{'alias':22}{'fechas':8}{'nombre':7}{'dir':5}{'estado':12} -> cliente asignado")
for alias,pid,nom,m,n,nm,am,est in rows:
    print(f"{alias[:21]:22}{f'{m}/{n}':8}{nm:7}{am:5}{est:12} -> [{pid}] {nom[:34]}")
susp=[r for r in rows if r[7]=="SOSPECHOSO"]
print(f"\nSOSPECHOSOS (revisar): {len(susp)}")
with open("cruce_validacion.csv","w",newline="") as f:
    w=csv.writer(f); w.writerow(["alias","partner_id","partner_name","fechas_match","fechas_total","name_match","addr_match","estado"])
    for r in rows: w.writerow(r)
