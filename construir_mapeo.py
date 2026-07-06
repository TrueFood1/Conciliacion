#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Mapea los alias de cliente de Daniel (de cruce_despachos.csv) a clientes reales
de Odoo (cruce_partners.csv) por coincidencia de tokens. Marca confianza.
Salida: cruce_cliente_map.csv  +  lista de inseguros para que Andrea resuelva.
"""
import csv, re, unicodedata
from collections import defaultdict

def norm(s):
    s=str(s).lower()
    s="".join(c for c in unicodedata.normalize("NFD",s) if unicodedata.category(c)!="Mn")
    return s
def concat(s):  # solo letras/números, sin espacios
    return re.sub(r"[^a-z0-9]","",norm(s))
STOP=set("sa s a sociedad anonima limitada srl sr l de del la el los las responsabilidad "
         "inc cia ltda y dba sas s.a société societe corporacion".split())
def tokens(s):
    return [t for t in re.split(r"[^a-z0-9]+",norm(s)) if t and t not in STOP and len(t)>=2]

# alias de Daniel (nombres display distintos en los despachos)
aliases=[]
seen=set()
for row in csv.DictReader(open("cruce_despachos.csv")):
    c=row["cliente"].strip()
    if c and c not in seen: seen.add(c); aliases.append(c)

partners=[]
for row in csv.DictReader(open("cruce_partners.csv")):
    partners.append((int(row["id"]),row["name"]))
P=[(pid,name,concat(name),set(tokens(name))) for pid,name in partners]

def candidatos(alias):
    at=tokens(alias); ac=concat(alias)
    res=[]
    for pid,name,pc,pt in P:
        if not at: continue
        # señal por token: whole-token (fuerte) o substring SOLO si el token es largo (>=5)
        hits=0
        for t in at:
            if t in pt: hits+=1
            elif len(t)>=5 and t in pc: hits+=1
        base=hits/len(at)
        # señal fuerte: el concat del alias completo (>=6) aparece dentro del concat del partner
        concat_hit = len(ac)>=6 and ac in pc
        score = 2.0 if concat_hit else base
        if score>0: res.append((round(score,3),pid,name))
    res.sort(reverse=True)
    return res

CONF=[]; INSEG=[]
for a in aliases:
    cs=candidatos(a)
    if not cs: INSEG.append((a,[])); continue
    top=cs[0]; second=cs[1][0] if len(cs)>1 else 0
    # confiable: concat-hit (2.0) único, o todos los tokens presentes con margen claro
    confiable = (top[0]>=2.0 and second<2.0) or (top[0]>=1.0 and top[0]-second>=0.5)
    if confiable: CONF.append((a,top[1],top[2],top[0]))
    else: INSEG.append((a,cs[:3]))

with open("cruce_cliente_map.csv","w",newline="") as f:
    w=csv.writer(f); w.writerow(["alias_daniel","partner_id","partner_name","score"])
    for a,pid,name,sc in CONF: w.writerow([a,pid,name,sc])

print(f"Alias totales: {len(aliases)}   confiables: {len(CONF)}   inseguros: {len(INSEG)}\n")
print("== MAPEOS CONFIABLES ==")
for a,pid,name,sc in sorted(CONF,key=lambda x:x[0].lower()):
    print(f"  {a:24} -> [{pid}] {name}   (score {sc})")
print("\n== INSEGUROS (para Andrea) ==")
for a,cs in sorted(INSEG,key=lambda x:x[0].lower()):
    if not cs:
        print(f"  {a:24} -> (sin candidato)"); continue
    op=" | ".join(f"[{pid}] {name} ({sc})" for sc,pid,name in cs)
    print(f"  {a:24} -> {op}")
