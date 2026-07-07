#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Diccionario de clientes (alias de Daniel -> cliente real de Odoo) como módulo.
Fuente de verdad: clientes_dict.json (al lado de este archivo).
Lo construye/actualiza build_clientes.py; lo consumen todos los cruces.

Uso:
    from tf import clientes
    pid, conf = clientes.resolver("Cafe o que")   # -> (1207, "alto")
"""
import os, json, re, unicodedata, functools

_DIR = os.path.dirname(os.path.abspath(__file__))
DICT_PATH = os.path.join(_DIR, "clientes_dict.json")

def _n(s):
    s = str(s or "").strip().lower()
    s = "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")
    return re.sub(r"\s+", " ", s).strip()

# Merges de typos/variantes inequívocos (alias normalizado -> alias canónico normalizado).
TYPO = {
    "auto mercado": "automercado", "automercdo": "automercado",
    "cafe oteca 1": "cafe oteca", "cafe oteca 2": "cafe oteca",
    "care oteca": "cafe oteca", "care oteca 1": "cafe oteca",
    "cafe o que": "cafe con que",
    "recolet freses": "recoleta freses",
    "mosaics escalante": "mosaico escalante", "mosaics cartago": "mosaico cartago",
    "bm uvir": "bm uvita",
    "sb lincoln mall": "sb lincoln",
    "smash amara": "sb amara",
    "can palmares": "cb palmares",
}

def canon_alias(raw):
    """Normaliza + aplica merges. 'Auto mercado' -> 'automercado'."""
    n = _n(raw)
    return TYPO.get(n, n)

@functools.lru_cache(maxsize=1)
def _load():
    if not os.path.exists(DICT_PATH):
        return {}
    data = json.load(open(DICT_PATH, encoding="utf-8"))
    # index por alias canónico
    idx = {}
    for rec in data:
        idx[canon_alias(rec["alias"])] = rec
    return idx

def resolver(alias_raw):
    """Devuelve (partner_id, confianza) o (None, None) si no está en el diccionario.
    partner_id puede ser int, lista de ints ('661|649'), o sentinela ('NO_VENTA')."""
    rec = _load().get(canon_alias(alias_raw))
    if not rec:
        return None, None
    return rec.get("partner_id"), rec.get("confianza")

def registro(alias_raw):
    """Registro completo del alias (dict) o None."""
    return _load().get(canon_alias(alias_raw))

def todos():
    return list(_load().values())
