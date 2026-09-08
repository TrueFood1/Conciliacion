#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Cliente de la instancia DEMO de Odoo — el único lugar del repo donde se ESCRIBE.

⚠️ NO SIRVE PARA PRODUCCIÓN, A PROPÓSITO. `_guard()` corta si la URL no contiene
"demotruefood". Es el espejo de `odoo_read.py`: aquel bloquea escritura contra
prod; éste bloquea prod entero. Los dos candados son deny-by-default y ninguno
se debilita para "probar rápido".

Credenciales en conexion_demo.env (cubierto por `*.env` del .gitignore).
La API key nunca se imprime.

Uso:
    python3 odoo_demo.py --recon     # Paso 1: versión, tipos de picking, productos, usuario
"""
import sys, os, json, xmlrpc.client

# ── Candado 1: sin esto no se habla con nadie ────────────────────────────
def es_demo(url):
    return "demotruefood" in (url or "").lower()

# ── Candado 2: qué se puede ESCRIBIR, por modelo y método ────────────────
# Mapa explícito {modelo: [métodos]}. NO es un Set plano de nombres: un Set
# habilita el método para cualquier modelo, que es justo lo que no queremos.
# Es la misma forma que el carril del proxy (server.js), a propósito.
ESCRITURA_OK = {
    "stock.picking": ["button_validate", "create", "write"],
    "stock.move":    ["create", "write"],
    "stock.move.line": ["create", "write"],
}
LECTURA_OK = {"search","search_read","read","search_count","read_group","fields_get",
              "name_search","name_get","default_get","get_views","load_views",
              "web_search_read","web_read","web_read_group","read_progress_bar"}

def load_env(path="conexion_demo.env"):
    if not os.path.exists(path):
        sys.exit(f"[FALTA] {path} no existe. Copiá conexion_demo.env.example y llenalo "
                 f"(DB + usuario + API key de la DEMO). La key NO va al chat.")
    env = {}
    for line in open(path):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line: continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip()
    for k in ("ODOO_URL","ODOO_DB","ODOO_USER","ODOO_APIKEY"):
        if not env.get(k):
            sys.exit(f"[FALTA] {k} vacío en conexion_demo.env")
    if not es_demo(env["ODOO_URL"]):
        sys.exit(f"🔒 ABORTADO: ODOO_URL={env['ODOO_URL']} no es la demo.\n"
                 f"   Este script escribe. Solo corre contra *demotruefood*.")
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
        sys.exit(f"[RED] No se pudo contactar la demo: {type(e).__name__}: {str(e)[:200]}")
    if not _UID:
        sys.exit("[AUTH] Access Denied — revisá DB / usuario / API key en conexion_demo.env")
    _MODELS = xmlrpc.client.ServerProxy(f"{ENV['ODOO_URL']}/xmlrpc/2/object", allow_none=True)

def call(model, method, *args, **kwargs):
    """Llamada a la DEMO. Lectura libre; escritura solo si el par (modelo, método)
    está en ESCRITURA_OK. Devuelve el resultado CRUDO, sin interpretar."""
    _connect()
    if not es_demo(ENV["ODOO_URL"]):
        raise RuntimeError("🔒 la URL dejó de ser la demo — abortado")
    if method not in LECTURA_OK and method not in ESCRITURA_OK.get(model, []):
        raise RuntimeError(f"🔒 bloqueado: {method} sobre {model} "
                           f"(no está en LECTURA_OK ni en ESCRITURA_OK[{model}])")
    return _MODELS.execute_kw(ENV["ODOO_DB"], _UID, ENV["ODOO_APIKEY"],
                              model, method, list(args), kwargs)

def uid():
    _connect(); return _UID


# ════════════════════════════════════════════════════════════════════════
# PASO 1 · Reconocer la demo. No se asume NADA de producción.
# ════════════════════════════════════════════════════════════════════════
NOMBRES_TERM = ["blanco","semilla","frances","francés","hamburguesa","buns",
                "pizza","galleta","cookie"]

def recon():
    env = load_env()
    print(f"URL = {env['ODOO_URL']}")
    print(f"DB  = {env['ODOO_DB']}")
    print(f"demo confirmada = {es_demo(env['ODOO_URL'])}\n")

    # ── versión ──
    common = xmlrpc.client.ServerProxy(f"{env['ODOO_URL']}/xmlrpc/2/common", allow_none=True)
    v = common.version()
    print("── VERSIÓN ──")
    print(f"  server_version      = {v.get('server_version')}")
    print(f"  server_serie        = {v.get('server_serie')}")
    print(f"  protocol_version    = {v.get('protocol_version')}")
    es17 = str(v.get('server_serie','')).startswith('17')
    print(f"  ¿es 17?             = {es17}\n")

    # ── usuario y permisos ──
    print("── USUARIO ──")
    me = call("res.users","read",[uid()],
              fields=["id","login","name","groups_id","share","active"])
    u = me[0]
    print(f"  uid   = {u['id']}")
    print(f"  login = {u['login']}")
    print(f"  name  = {u['name']}")
    print(f"  share = {u.get('share')}  ·  active = {u.get('active')}")
    gs = call("res.groups","read",u["groups_id"], fields=["id","full_name"])
    print(f"  grupos ({len(gs)}):")
    for g in sorted(gs, key=lambda x: x["full_name"]):
        print(f"    [{g['id']:4}] {g['full_name']}")

    # ¿tiene escritura sobre stock.picking?
    print("\n  ACL sobre stock.picking / stock.move (ir.model.access de sus grupos):")
    gids = [g["id"] for g in gs]
    acls = call("ir.model.access","search_read",
                [["model_id.model","in",["stock.picking","stock.move"]]],
                fields=["name","model_id","group_id","perm_read","perm_write",
                        "perm_create","perm_unlink"])
    for a in acls:
        mio = (a.get("group_id") and a["group_id"][0] in gids) or not a.get("group_id")
        marca = "★" if mio else " "
        g = a["group_id"][1] if a.get("group_id") else "(sin grupo = TODOS)"
        print(f"    {marca} {a['model_id'][1][:22]:22} {g[:40]:40} "
              f"r{int(a['perm_read'])} w{int(a['perm_write'])} "
              f"c{int(a['perm_create'])} u{int(a['perm_unlink'])}")
    print("    ★ = aplica a este usuario")

    # ── tipos de picking ──
    print("\n── stock.picking.type ──")
    tipos = call("stock.picking.type","search_read",[],
                 fields=["id","name","code","sequence_code","warehouse_id","active"],
                 context={"lang":"es_CR"})
    for t in tipos:
        wh = t["warehouse_id"][1] if t.get("warehouse_id") else "—"
        flag = "  ← OUTGOING" if t["code"]=="outgoing" else ""
        print(f"  [{t['id']:3}] {t['code']:12} {str(t['name'])[:28]:28} "
              f"wh={wh[:18]:18} activo={t.get('active')}{flag}")
    outs = [t for t in tipos if t["code"]=="outgoing"]
    print(f"  → {len(outs)} tipo(s) con code='outgoing': {[t['id'] for t in outs]}")

    # ── productos terminados ──
    print("\n── PRODUCTOS TERMINADOS (mapeo por nombre SOLO acá) ──")
    dom = ["|"]*(len(NOMBRES_TERM)-1) + [["name","ilike",n] for n in NOMBRES_TERM]
    prods = call("product.product","search_read", dom,
                 fields=["id","default_code","name","uom_id","type","qty_available"],
                 limit=100, context={"lang":"es_CR"})
    for p in sorted(prods, key=lambda x: x["id"]):
        uom = p["uom_id"] if p.get("uom_id") else [None,"?"]
        print(f"  [{p['id']:4}] {str(p.get('default_code') or '—')[:10]:10} "
              f"{p['name'][:34]:34} uom=[{uom[0]}] {str(uom[1])[:16]:16} "
              f"tipo={p.get('type')} on_hand={p.get('qty_available')}")
    print(f"\n  IDs de producción (451/452/453/503/472/519) presentes en la demo:")
    ids_prod = [451,452,453,503,472,519]
    hay = call("product.product","search_read",[["id","in",ids_prod]],
               fields=["id","name"], context={"lang":"es_CR"})
    encontrados = {h["id"]: h["name"] for h in hay}
    for i in ids_prod:
        print(f"    {i} → {encontrados.get(i, '❌ NO EXISTE con ese id en la demo')}")

    # ── pickings de salida que ya existen ──
    print("\n── stock.picking de salida por estado ──")
    if outs:
        oids = [t["id"] for t in outs]
        for st in ["draft","waiting","confirmed","assigned","done","cancel"]:
            n = call("stock.picking","search_count",
                     [["picking_type_id","in",oids],["state","=",st]])
            print(f"  {st:10} {n}")
        asg = call("stock.picking","search_read",
                   [["picking_type_id","in",oids],["state","=","assigned"]],
                   fields=["id","name","partner_id","scheduled_date","state"], limit=10)
        print(f"  en 'assigned' ({len(asg)}):")
        for a in asg:
            print(f"    [{a['id']}] {a['name']}  {a.get('scheduled_date')}")

if __name__ == "__main__":
    if "--recon" in sys.argv:
        recon()
    else:
        print(__doc__)
