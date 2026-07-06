#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Genera reporte_cruce.md legible a partir de cruce_resultado.csv."""
import csv, re

rows=list(csv.DictReader(open("cruce_resultado.csv")))
def dias(n):
    m=re.search(r"\((\d+)d",n); return int(m.group(1)) if m else None

sinf=[r for r in rows if r["factura"]=="NO"]
fac_real=[r for r in sinf if "ninguna" in r["nota"] or (dias(r["nota"]) or 99)>7]
fac_timing=[r for r in sinf if r not in fac_real]

sin_ent=[r for r in rows if r["entrega_validada"]=="NO"]
ent_real=[r for r in sin_ent if "ningún" in r["nota_entrega"] or (dias(r["nota_entrega"]) or 99)>7]
ent_timing=[r for r in sin_ent if r not in ent_real]

# convergencia: ni factura ni entrega (reales en ambos) = ausente de Odoo
key=lambda r:(r["fecha"],r["cliente"])
ausentes=[r for r in fac_real if r in ent_real]
especiales=[r for r in rows if r["factura"] in ("N/A (reposición)","sin cliente en Odoo")]

L=["# Cruce de despachos (Excel Daniel ↔ Odoo) — ventana 8-abr a 26-jun 2026\n",
   f"Match por cliente + fecha ±2 días. **{len(rows)}** despachos, **145 mapeados** a cliente de Odoo.\n",
   "Dos lecturas independientes por despacho: ¿tiene **factura** (account.move)? y ¿tiene **entrega validada** (stock.picking salida done, por fecha planificada)?\n"]

L.append("## 🔴 Despachos AUSENTES de Odoo — ni factura ni salida de stock\n")
L.append("Lo más fuerte: Daniel los despachó pero en Odoo no hay **ni factura ni movimiento de inventario**. "
         "Explican plata sin cobrar **y** stock inflado a la vez.\n")
L.append("| Fecha | Cliente | Productos |")
L.append("|---|---|---|")
for r in sorted(ausentes,key=key):
    L.append(f"| {r['fecha']} | {r['cliente']} | {r['productos']} |")

L.append("\n## 🟠 Facturado pero sin descontar stock (o viceversa)\n")
L.append("| Fecha | Cliente | Productos | Situación |")
L.append("|---|---|---|---|")
for r in sorted([x for x in fac_real if x not in ausentes],key=key):
    L.append(f"| {r['fecha']} | {r['cliente']} | {r['productos']} | sin factura, pero sí salió de stock |")
for r in sorted([x for x in ent_real if x not in ausentes],key=key):
    L.append(f"| {r['fecha']} | {r['cliente']} | {r['productos']} | facturado, pero stock NO descontado |")

L.append("\n## 🟡 Timing (±2d muy estricto — el documento existe a 3–7 días)\n")
L.append(f"No son huecos: la factura y/o el picking existen, solo a 3–7 días de la fecha que anota Daniel. "
         f"Sin factura por timing: {len(fac_timing)}. Sin entrega por timing: {len(ent_timing)}.\n")
L.append("| Fecha | Cliente | Factura cercana | Picking cercano |")
L.append("|---|---|---|---|")
tim={}
for r in fac_timing+ent_timing: tim[key(r)]=r
for k in sorted(tim):
    r=tim[k]
    L.append(f"| {r['fecha']} | {r['cliente']} | {r['nota'].replace('factura más cercana: ','') or '—'} | {r['nota_entrega'].replace('picking más cercano: ','') or '—'} |")

L.append("\n## ⚪ Casos especiales\n| Fecha | Cliente | Estado |\n|---|---|---|")
for r in sorted(especiales,key=key):
    L.append(f"| {r['fecha']} | {r['cliente']} | {r['factura']} |")

L.append(f"\n## Resumen\n")
L.append(f"- Despachos ausentes de Odoo (ni factura ni stock): **{len(ausentes)}**")
L.append(f"- Sin factura real (a cobrar): **{len(fac_real)}**  | sin entrega real: **{len(ent_real)}**")
L.append(f"- Timing (no son huecos): factura {len(fac_timing)}, entrega {len(ent_timing)}")
L.append(f"- ⚠️ Estos despachos ausentes son de clientes chicos y pesan poco: NO alcanzan a explicar "
         f"el faltante físico grande (Semillas 70u). La causa de ese faltante hay que buscarla en "
         f"traslados internos (mermas), devoluciones o diferencias de cantidad — fase siguiente.")
L.append(f"\nDetalle de los 145 despachos: `cruce_resultado.csv`.\n")
open("reporte_cruce.md","w").write("\n".join(L))
print("reporte_cruce.md escrito.")
print(f"ausentes(ni fact ni stock)={len(ausentes)} | fac_real={len(fac_real)} ent_real={len(ent_real)} | fac_timing={len(fac_timing)} ent_timing={len(ent_timing)}")
print("\nAUSENTES de Odoo:")
for r in sorted(ausentes,key=key): print(f"  {r['fecha']}  {r['cliente']:20} {r['productos']}")