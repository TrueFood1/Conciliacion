#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Lector de Odoo producción — SOLO LECTURA, XML-RPC directo (sin proxy).
El proxy truefood-proxy.onrender.com daba Access Denied en prod (está pineado al
demo); la key es válida directo. Credenciales desde conexion_prod.env (gitignored).
La API key nunca se imprime.

⚠️ ENTRA COMO `Lobby Solo Lectura` (uid 28), NO COMO Andrea (uid 23).
Hasta el 2-sep-2026 entraba con la cuenta de Andrea, que TIENE permisos de
escritura en Odoo, y lo único que impedía un `write` desde acá era la lista
`LECTURA_OK` de abajo — o sea, una salvaguarda CITADA, no un permiso. Bastaba un
método fuera de la lista, o un descuido al editar la lista, para escribir en
producción con credenciales de dueña.
Ahora el candado es de Odoo: uid 28 pertenece al grupo `Solo Lectura Lobby` [76],
que tiene 18 reglas de acceso y CERO con permiso de escritura. Aunque alguien
borrara `LECTURA_OK` entero, Odoo rechazaría la escritura. `LECTURA_OK` se queda
igual, como segunda capa — pero ya no es la única.

Uso:
    python3 odoo_read.py --probe      # test de conexión + UoM + clientes
    python3 odoo_read.py --quien      # con qué usuario entra y qué permisos tiene
"""
import sys, os, xmlrpc.client

# Candado 2 (defensa en profundidad): allowlist de lectura, igual que LECTURA_OK en
# index.html y en el proxy. Denegar por defecto. NO es el candado principal: el
# principal es el usuario de Odoo (ver el aviso de arriba).
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
    for k in ("ODOO_URL","ODOO_DB"):
        if not env.get(k):
            sys.exit(f"[FALTA] {k} vacío en conexion_prod.env")
    # ── El usuario: SIEMPRE el de solo lectura ────────────────────────────
    # Sin fallback silencioso a ODOO_USER. Un fallback dejaría el agujero abierto
    # justo el día que alguien borre una línea del .env, y sin decir nada.
    if not env.get("ODOO_LECTOR_USER") or not env.get("ODOO_LECTOR_APIKEY"):
        sys.exit(
            "[FALTA] ODOO_LECTOR_USER / ODOO_LECTOR_APIKEY en conexion_prod.env.\n"
            "  Son las credenciales de `Lobby Solo Lectura` (uid 28) — las mismas que\n"
            "  usa el proxy en Render (ODOO_LOGIN / ODOO_APIKEY).\n"
            "  Este lector ya NO entra con la cuenta de Andrea: esa tiene permisos de\n"
            "  escritura y el candado quedaba en una lista de Python.\n"
            "  Ver conexion_prod.env.example."
        )
    env["ODOO_USER"]   = env["ODOO_LECTOR_USER"]
    env["ODOO_APIKEY"] = env["ODOO_LECTOR_APIKEY"]
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

def quien():
    """Con qué usuario entra y QUÉ PUEDE ESCRIBIR — medido en Odoo, no citado.

    Es el chequeo que convierte la frase "entra como solo lectura" en un hecho
    verificable. Si alguna vez vuelve a aparecer un permiso de escritura, esto lo
    dice; leer otro documento que afirma que no lo hay, no."""
    env = load_env()
    _connect()
    print(f"URL = {env['ODOO_URL']}  ·  DB = {env['ODOO_DB']}")
    me = call("res.users", "read", [_UID], fields=["id","login","name","groups_id","active"])
    u = me[0]
    print(f"\n── USUARIO ──\n  uid   = {u['id']}\n  login = {u['login']}\n  name  = {u['name']}")
    if u["id"] == 28:
        print("  ✓ es el uid 28 esperado (Lobby Solo Lectura)")
    else:
        print(f"  ⚠️ NO es el uid 28 — revisá ODOO_LECTOR_USER en conexion_prod.env")

    gs = call("res.groups", "read", u["groups_id"], fields=["id","full_name"])
    print(f"\n── GRUPOS ({len(gs)}) ──")
    for g in sorted(gs, key=lambda x: x["full_name"]):
        print(f"  [{g['id']:4}] {g['full_name']}")

    gids = [g["id"] for g in gs]
    acls = call("ir.model.access", "search_read",
                ["|", ["group_id", "in", gids], ["group_id", "=", False]],
                fields=["name","model_id","group_id","perm_write","perm_create","perm_unlink"])
    escribe = [a for a in acls if a["perm_write"] or a["perm_create"] or a["perm_unlink"]]
    print(f"\n── ACL QUE ALCANZAN A ESTE USUARIO: {len(acls)} ──")
    print(f"  con permiso de escritura/creación/borrado: {len(escribe)}")
    if not escribe:
        print("  ✓ CERO. El candado es de Odoo, no de la lista de Python.")
    else:
        print("  ⚠️ hay escritura alcanzable — el candado NO es solo de Odoo:")
        for a in sorted(escribe, key=lambda x: x["model_id"][1]):
            g = a["group_id"][1] if a.get("group_id") else "(sin grupo = TODOS los internos)"
            print(f"     {a['model_id'][1][:34]:34} {g[:38]:38} "
                  f"w{int(a['perm_write'])} c{int(a['perm_create'])} u{int(a['perm_unlink'])}")

    # ── ¿sigue leyendo lo que el proyecto necesita? ──
    print("\n── LECTURA DE LOS MODELOS QUE USA EL PROYECTO ──")
    for modelo, dom in [("stock.scrap", []), ("product.product", []), ("stock.picking", []),
                        ("mrp.production", []), ("account.move", []), ("res.partner", []),
                        ("uom.uom", []), ("stock.quant", []), ("stock.move", [])]:
        try:
            n = call(modelo, "search_count", dom)
            print(f"  ✓ {modelo:20} {n:>7} filas legibles")
        except SystemExit as e:
            print(f"  ❌ {modelo:20} NO SE PUEDE LEER — {e}")
        except Exception as e:
            print(f"  ❌ {modelo:20} NO SE PUEDE LEER — {type(e).__name__}: {str(e)[:90]}")


if __name__ == "__main__":
    if "--probe" in sys.argv:
        probe()
    elif "--quien" in sys.argv:
        quien()
    else:
        print(__doc__)
