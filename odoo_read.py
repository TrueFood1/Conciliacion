#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Lector de Odoo producción — SOLO LECTURA, XML-RPC directo (sin proxy).
El proxy truefood-proxy.onrender.com daba Access Denied en prod (está pineado al
demo); la key es válida directo. Candado deny-by-default: allowlist de lectura.
Credenciales desde conexion_prod.env (gitignored). La API key nunca se imprime.

Uso:
    python3 odoo_read.py --probe      # test de conexión + UoM + clientes
"""
import sys, os, xmlrpc.client

# Candado: allowlist de lectura (igual que LECTURA_OK en index.html). Denegar por defecto.
LECTURA_OK = {"search","search_read","read","search_count","read_group","fields_get",
              "name_search","name_get","default_get","get_views","load_views",
              "web_search_read","web_read","web_read_group","read_progress_bar"}

def es_prod(url):
    u = (url or "").lower()
    return "truefood.odoo.com" in u and "demotruefood" not in u

def load_env(path="conexion_prod.env"):
    if not os.path.exists(path):
        sys.exit(f"[FALTA] {path} no existe. Copiá conexion_prod.env.example y llenalo "
                 f"(DB + API key). La key NO va al chat.")
    env = {}
    for line in open(path):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line: continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip()
    for k in ("ODOO_URL","ODOO_DB","ODOO_USER","ODOO_APIKEY"):
        if not env.get(k):
            sys.exit(f"[FALTA] {k} vacío en conexion_prod.env")
    return env

ENV = None; _UID = None; _MODELS = None
def _connect():
    global ENV, _UID, _MODELS
    if _MODELS is not None: return
    if ENV is None: ENV = load_env()
    try:
        common = xmlrpc.client.ServerProxy(f"{ENV['ODOO_URL']}/xmlrpc/2/common", allow_none=True)
        _UID = common.authenticate(ENV["ODOO_DB"], ENV["ODOO_USER"], ENV["ODOO_APIKEY"], {})
    except Exception as e:
        sys.exit(f"[RED] No se pudo contactar Odoo: {type(e).__name__}: {str(e)[:200]}")
    if not _UID:
        sys.exit("[AUTH] Access Denied — revisá DB / usuario / API key en conexion_prod.env")
    _MODELS = xmlrpc.client.ServerProxy(f"{ENV['ODOO_URL']}/xmlrpc/2/object", allow_none=True)

def call(model, method, *args, **kwargs):
    """Llamada read-only a Odoo vía execute_kw. Bloquea métodos fuera de LECTURA_OK."""
    _connect()  # asegura ENV + autenticación
    if es_prod(ENV["ODOO_URL"]) and method not in LECTURA_OK:
        raise RuntimeError(f"🔒 PRODUCCIÓN · solo lectura — bloqueado: {method} ({model})")
    try:
        return _MODELS.execute_kw(ENV["ODOO_DB"], _UID, ENV["ODOO_APIKEY"],
                                  model, method, list(args), kwargs)
    except xmlrpc.client.Fault as e:
        sys.exit(f"[ODOO] {e.faultString.strip().splitlines()[-1][:300]}")

def probe():
    import csv
    env = load_env()
    print(f"URL={env['ODOO_URL']}  DB={env['ODOO_DB']}  USER={env['ODOO_USER']}  "
          f"(prod={es_prod(env['ODOO_URL'])})")
    me = call("res.users","search_read",[["login","=",env["ODOO_USER"]]],fields=["id","name"],limit=1)
    if not me: sys.exit("[AUTH] usuario no verificado")
    print(f"✓ Conectado como {me[0]['name']} (uid={me[0]['id']})")

    # 1) Productos del cruce + unidad de medida (clave para cajas->unidades)
    nombres = ["blanco","semilla","frances","francés","hamburguesa","buns","pizza","galleta"]
    dom = ["|"]*(len(nombres)-1) + [["name","ilike",n] for n in nombres]
    prods = call("product.product","search_read", dom,
                 fields=["id","default_code","name","uom_id","uom_po_id"], limit=80)
    print(f"\nProductos que matchean ({len(prods)}):")
    for p in prods:
        print(f"  [{p['id']}] {p.get('default_code') or '—':10} {p['name'][:40]:40} "
              f"uom={p['uom_id'][1] if p.get('uom_id') else '?'}")

    # 2) Clientes (res.partner) para armar el diccionario alias->Odoo
    parts = call("res.partner","search_read",[["customer_rank",">",0]],
                 fields=["id","name","parent_id"], limit=2000, order="name")
    with open("cruce_partners.csv","w",newline="") as fh:
        w=csv.writer(fh); w.writerow(["id","name","parent"])
        for p in parts:
            w.writerow([p["id"],p["name"],p["parent_id"][1] if p.get("parent_id") else ""])
    print(f"\nClientes (customer_rank>0): {len(parts)}  -> cruce_partners.csv")
    for p in parts[:40]:
        print(f"  [{p['id']}] {p['name']}")
    if len(parts)>40: print(f"  … (+{len(parts)-40} más en el CSV)")

if __name__ == "__main__":
    if "--probe" in sys.argv:
        probe()
    else:
        print(__doc__)
