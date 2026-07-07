#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Cruce de DESPACHOS: Excel "Control de pedidos" de Daniel  vs  Odoo producción.
Unidad = el despacho completo (cliente + fecha), NO el producto.
Objetivo #1: cazar despachos SIN factura en Odoo (entregas sin cobrar).

Esta parte (lado Excel) agrupa los despachos en ventana [2026-04-08, 2026-06-26]
y deja listas las columnas factura?/entrega? para llenar con Odoo.
Match contra Odoo = por cliente (vía diccionario de alias) + fecha ±2 días.
"""
import openpyxl, datetime, re, unicodedata, csv
from collections import defaultdict, Counter

XLSX="inventario_daniel.xlsx"
WIN_INI=datetime.date(2026,4,8); WIN_FIN=datetime.date(2026,6,26)

# ── Producto: diccionarios de typos ────────────────────────────────────────
def norm(s):
    s=str(s).strip().lower()
    return "".join(c for c in unicodedata.normalize("NFD",s) if unicodedata.category(c)!="Mn")
PROD_DICT={
 "Blanco":"blanco blancos blqnco blnco boanco balco bkanco blanc0",
 "Semillas":"semillas semilas swmillas se,illas semi;las semillasm s3millas senillas semollas semillaw semillaq semilla",
 "Frances":"frances framces francrs feances fances frqnces franc4s frnces",
 "Buns":"hamb hambur hamburguesa hamburguesas ha,bur h,abur hamcur hambue hanbur hmbur inidad ham buns",
 "Pizza":"pizza",
 "Galletas":"galleta galletas",
}
PLOOK={}
for canon,vs in PROD_DICT.items():
    for v in vs.split(): PLOOK[norm(v)]=canon
def match_prod(raw):
    n=norm(raw)
    if not n: return None
    if n in PLOOK: return PLOOK[n]
    for k,c in PLOOK.items():
        if len(n)>=4 and (n[:4]==k[:4]): return c
    return None

CAJA=set(norm(x) for x in "caja CJ cj Cj CU Ch caha Cajas cjs".split())
def es_caja(raw):
    n=norm(raw); return n in CAJA or n.startswith("caj") or n in ("cj","cu","ch")

# ── Cliente: normalización + merge de typos inequívocos ────────────────────
def cnorm(s):
    n=norm(s); n=re.sub(r"\s+"," ",n).strip(); return n
# alias crudo (normalizado) -> forma canónica (normalizada). Solo merges seguros.
TYPO={
 "auto mercado":"automercado","automercdo":"automercado",
 # Café Oteca y Café con que son DOS clientes distintos (corrección de Andrea):
 "cafe oteca 1":"cafe oteca","cafe oteca 2":"cafe oteca",
 "care oteca":"cafe oteca","care oteca 1":"cafe oteca",
 "cafe o que":"cafe con que","cafe con que":"cafe con que",
 "recolet freses":"recoleta freses",
 "mosaics escalante":"mosaico escalante","mosaics cartago":"mosaico cartago",
 "bm uvir":"bm uvita",
 "sb lincoln mall":"sb lincoln","sb lincoln":"sb lincoln",
 "smash amara":"sb amara",
 "can palmares":"cb palmares",   # "Can" = typo de "CB" = Compre Bien Palmares
}
# nombres bonitos para canónicos cuyo spelling crudo más común queda feo
DISPLAY={"cafe con que":"Café con que","cafe oteca":"Café Oteca","cb palmares":"CB Palmares"}
# "Recoleta" a secas: AMBIGUO real (Recoleta Freses vs Recoleta Cartago) -> resolver
# en el match mirando la factura/entrega de Odoo de esa fecha. NO asignar a ciegas.
AMBIGUOS={"recoleta"}
def cli_canon(s):
    n=cnorm(s); return TYPO.get(n,n)

MES={'ene':1,'feb':2,'mar':3,'abr':4,'may':5,'jun':6,'jul':7,'ago':8,'sep':9,'set':9,'oct':10,'nov':11,'dic':12}
def pdate(v):
    if isinstance(v,(datetime.datetime,datetime.date)): return datetime.date(v.year,v.month,v.day)
    m=re.search(r'(\d{1,2})\s+([a-z]{3,4})\.?\s+(\d{2,4})',str(v).strip().lower())
    if m:
        d=int(m.group(1));mon=MES.get(m.group(2)[:3]);y=int(m.group(3));y=y+2000 if y<100 else y
        if mon:
            try:return datetime.date(y,mon,d)
            except:return None
def num(v):
    try:return float(str(v).replace(",",".").strip())
    except:return None

# ── Recorrer y agrupar por despacho ────────────────────────────────────────
wb=openpyxl.load_workbook(XLSX,data_only=True); ws=wb["Hoja 1"]
rows=[[ (c.value if c.value is not None else "") for c in r] for r in ws.iter_rows()]
cur=None; cli=None
desp=defaultdict(lambda:{"raw":Counter(),"items":[]})  # (fecha,canon) -> {raws, items}
raw_by_canon=defaultdict(Counter)
sin_match=Counter()
for i in range(14,len(rows)):
    r=rows[i]
    dv=pdate(r[0])
    if dv:cur=dv
    if str(r[1]).strip(): cli=str(r[1]).strip()
    praw=str(r[2]).strip()
    if not praw: continue
    if not cur or not(WIN_INI<=cur<=WIN_FIN): continue
    q=num(r[3]); q=num(r[5]) if q is None else q
    if q is None: continue
    canon=match_prod(praw)
    if canon is None: sin_match[praw]+=q; continue
    unit="cj" if es_caja(r[4]) else "u"
    ck=cli_canon(cli)
    key=(cur,ck)
    desp[key]["raw"][cli]+=1
    desp[key]["items"].append((canon,q,unit))
    raw_by_canon[ck][cli]+=1

# nombre display por canónico = override bonito, o el spelling crudo más común
def disp(ck):
    if ck in DISPLAY: return DISPLAY[ck]
    return raw_by_canon[ck].most_common(1)[0][0] if raw_by_canon[ck] else ck

# consolidar items por producto dentro del despacho
def items_str(items):
    agg=defaultdict(lambda:defaultdict(float))
    for canon,q,u in items: agg[canon][u]+=q
    parts=[]
    for p in ["Blanco","Semillas","Frances","Buns","Pizza","Galletas"]:
        if p in agg:
            seg=[]
            if agg[p]["cj"]: seg.append(f"{agg[p]['cj']:.0f}cj")
            if agg[p]["u"]:  seg.append(f"{agg[p]['u']:.0f}u")
            parts.append(f"{p} {'+'.join(seg)}")
    return " · ".join(parts)
def tiene(items,p): return any(c==p for c,_,_ in items)

despachos=[]
for (f,ck),d in desp.items():
    despachos.append({"fecha":f,"canon":ck,"cliente":disp(ck),
                      "items":d["items"],"detalle":items_str(d["items"])})
despachos.sort(key=lambda x:(x["fecha"],x["cliente"]))

# ── Salida ─────────────────────────────────────────────────────────────────
print(f"DESPACHOS en ventana {WIN_INI}..{WIN_FIN}: {len(despachos)} "
      f"(clientes canónicos: {len(raw_by_canon)})")
if sin_match:
    print("[!] productos sin match:", dict(sin_match))

with open("cruce_despachos.csv","w",newline="") as fh:
    w=csv.writer(fh)
    w.writerow(["fecha","cliente","productos","tiene_factura","tiene_entrega_validada"])
    for d in despachos:
        w.writerow([d["fecha"],d["cliente"],d["detalle"],"?","?"])
print("→ cruce_despachos.csv escrito")

# Primero: despachos que incluyen Semillas (validación del método)
sem=[d for d in despachos if tiene(d["items"],"Semillas")]
print(f"\n== Despachos que incluyen SEMILLAS: {len(sem)} ==")
print(f"{'fecha':10} {'cliente':22} {'factura':7} {'entrega':7}  productos")
for d in sem:
    print(f"{str(d['fecha']):10} {d['cliente'][:22]:22} {'?':7} {'?':7}  {d['detalle']}")

# Lista de clientes canónicos para mapear a Odoo (res.partner)
print(f"\n== Clientes canónicos a mapear contra Odoo ({len(raw_by_canon)}) ==")
for ck in sorted(raw_by_canon, key=lambda k:-sum(raw_by_canon[k].values())):
    variantes=", ".join(f"{r}×{n}" for r,n in raw_by_canon[ck].most_common())
    flag=" [AMBIGUO]" if ck in AMBIGUOS else ""
    print(f"  {disp(ck):24} <- {variantes}{flag}")
