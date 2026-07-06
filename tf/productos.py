#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Normalizador de productos de Daniel (typos) + configuración por producto.

UoM (aclarado por Andrea): Odoo reporta el stock YA EN PAQUETES (la unidad de
stock del producto). NO se aplica ningún factor interno de paquete (nada de
"Dozens ×4" / "Paquete de 2 ×2"). La conciliación compara paquetes vs paquetes.

Conteo de Andrea: "cajas + sueltos". Una caja trae:
  - 6 paquetes/unidades para Blanco, Semillas, Francés, Buns, Pizza
  - 12 para Galletas
=> fisico_en_unidad_odoo = cajas*caja + sueltos   (queda en la MISMA unidad que el on-hand)

PENDIENTES (cosmético en Odoo, NO tocar ahora, revisar en lectura después):
  - Galletas real = [519] "Prueba Galletas" (353 on-hand, 19 ventas). Duplicado
    muerto [517]. Conviene renombrar [519] y archivar [517].
  - Al facturar Buns/Francés la UoM sale como "Dozens" en vez de "Paquete de 4"
    (cosmético; la cantidad es correcta).
"""
import re, unicodedata

def _n(s):
    s = str(s or "").strip().lower()
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")

# ── Diccionario de typos (alias Daniel -> producto canónico) ───────────────
PROD_DICT = {
    "Blanco":   "blanco blancos blqnco blnco boanco balco bkanco blanc0",
    "Semillas": "semillas semilas swmillas se,illas semi;las semillasm s3millas "
                "senillas semollas semillaw semillaq semilla",
    "Frances":  "frances framces francrs feances fances frqnces franc4s frnces",
    "Buns":     "hamb hambur hamburguesa hamburguesas ha,bur h,abur hamcur hambue "
                "hanbur hmbur inidad ham buns",
    "Pizza":    "pizza",
    "Galletas": "galleta galletas",
}
_LOOKUP = {}
for _canon, _vs in PROD_DICT.items():
    for _v in _vs.split():
        _LOOKUP[_n(_v)] = _canon

def normalizar_producto(raw):
    """'swmillas' -> 'Semillas'. None si no matchea."""
    n = _n(raw)
    if not n:
        return None
    if n in _LOOKUP:
        return _LOOKUP[n]
    for k, c in _LOOKUP.items():
        if len(n) >= 4 and n[:4] == k[:4]:
            return c
    return None

# ── Unidad: caja vs suelta ─────────────────────────────────────────────────
_CAJA = set(_n(x) for x in "caja CJ cj Cj CU Ch caha Cajas cjs".split())
def es_caja(raw):
    n = _n(raw)
    return n in _CAJA or n.startswith("caj") or n in ("cj", "cu", "ch")

# ── Configuración por producto ─────────────────────────────────────────────
# odoo_id  : product.product id
# uom_odoo : unidad de stock en Odoo (lo que devuelve stock.quant, ya en paquetes)
# caja     : paquetes/unidades por caja física en el conteo de Andrea
CONFIG = {
    "Blanco":   {"odoo_id": 451, "uom_odoo": "Units",            "caja": 6},
    "Semillas": {"odoo_id": 452, "uom_odoo": "Units",            "caja": 6},
    "Frances":  {"odoo_id": 453, "uom_odoo": "Paquete de 4",     "caja": 6},
    "Buns":     {"odoo_id": 503, "uom_odoo": "Paquete de 4",     "caja": 6},
    "Pizza":    {"odoo_id": 472, "uom_odoo": "Paquete de 2",     "caja": 6},
    "Galletas": {"odoo_id": 519, "uom_odoo": "Units",            "caja": 12},
}
ORDEN = ["Blanco", "Semillas", "Frances", "Buns", "Pizza", "Galletas"]

def fisico_en_unidad_odoo(canon, cajas, sueltos):
    """Conteo físico (cajas + sueltos) -> stock en la unidad de Odoo (paquetes).
    Se compara DIRECTO contra el on-hand de stock.quant (sin más conversión)."""
    return cajas * CONFIG[canon]["caja"] + sueltos
