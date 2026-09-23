#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
revisar_unidades.py — la revision diaria de unidades en facturas.

QUE HACE, EN ORDEN
  1. Lee Odoo (SOLO LECTURA, usuario `Lobby Solo Lectura`).
  2. Aplica la regla y arma un aviso por factura con problema.
  3. Crea un ticket por factura, SIN DUPLICAR: si ya hay uno para esa factura,
     no crea otro.
  4. Anota la corrida en `revision_unidades`, HAYA O NO hallazgos. La fila de
     "no encontre nada" es la que permite distinguir "todo limpio" de "no corrio".

⚠️ LA REGLA NO SE DUPLICA: SE EXTRAE DE index.html
  `UOM_OK` vive en index.html y es la unica definicion. Este script la RECORTA
  del archivo con una expresion regular y se cae ruidosamente si no la
  encuentra. Escribir la tabla dos veces —una en JS y otra en Python— es el modo
  de falla favorito de este repo: coinciden hasta el dia que alguien toca una.

CREDENCIALES — NINGUNA EN EL REPO
  Todo sale del entorno. Este archivo vive en el repo PUBLICO; el workflow que
  lo corre y los secrets viven en el repo PRIVADO respaldo-truefie.
    ODOO_URL, ODOO_DB, ODOO_LECTOR_USER, ODOO_LECTOR_APIKEY   (lectura de Odoo)
    VIGIA_DB_URL                                              (rol truefie_vigia)
  El rol `truefie_vigia` solo puede SELECT/INSERT sobre `ticket` y
  `revision_unidades`. No puede leer entregas, ni clientes, ni borrar nada.

USO
    python3 revisar_unidades.py --index /ruta/a/index.html [--dias 30] [--seco]
    --seco : no escribe nada, solo imprime lo que haria.
"""
import os, re, sys, json, ast, datetime, urllib.request, urllib.error

FIRMA = "ticket-sql-unidades"

# ── LA REGLA, EXTRAIDA DE index.html ─────────────────────────────────────
def leer_uom_ok(path):
    txt = open(path, encoding="utf-8").read()
    m = re.search(r"const UOM_OK = \{(.*?)\n\};", txt, re.S)
    if not m:
        sys.exit("[REGLA] no encontre `const UOM_OK` en %s. No invento la tabla: "
                 "si la regla se movio, este script tiene que saberlo." % path)
    cuerpo = re.sub(r"//[^\n]*", "", m.group(1))
    reglas = {}
    for pid, lista in re.findall(r"(\d+)\s*:\s*\[([^\]]*)\]", cuerpo):
        reglas[int(pid)] = [int(x) for x in re.findall(r"\d+", lista)]
    if not reglas: sys.exit("[REGLA] `UOM_OK` salio vacia")
    return reglas

def leer_cajas(path):
    """cajaU por producto, de NIV_INFO — la misma tabla que usa la app."""
    txt = open(path, encoding="utf-8").read()
    m = re.search(r"const NIV_INFO=\{(.*?)\n\};", txt, re.S)
    if not m: sys.exit("[REGLA] no encontre `NIV_INFO`")
    out = {}
    for pid, cuerpo in re.findall(r"(\d+):\{([^}]*)\}", m.group(1)):
        c = re.search(r"cajaU:\s*(\d+)", cuerpo)
        if c: out[int(pid)] = int(c.group(1))
    return out

# ── ODOO, SOLO LECTURA ───────────────────────────────────────────────────
def odoo():
    import xmlrpc.client
    url = os.environ["ODOO_URL"]; db = os.environ["ODOO_DB"]
    usr = os.environ["ODOO_LECTOR_USER"]; key = os.environ["ODOO_LECTOR_APIKEY"]
    uid = xmlrpc.client.ServerProxy(url+"/xmlrpc/2/common").authenticate(db, usr, key, {})
    if not uid: sys.exit("[ODOO] Access Denied")
    mod = xmlrpc.client.ServerProxy(url+"/xmlrpc/2/object")
    LECTURA_OK = {"search_read","read","search","search_count","read_group"}
    def call(modelo, metodo, *a, **kw):
        if metodo not in LECTURA_OK:
            raise RuntimeError("bloqueado: %s" % metodo)
        return mod.execute_kw(db, uid, key, modelo, metodo, list(a), kw)
    return call

# ── EL BARRIDO · mismo orden y mismas condiciones que uomBarrerFacturas ──
def barrer(call, uom_ok, cajas, desde, hasta):
    prods = sorted(uom_ok)
    mv = call("account.move","search_read",
        [["move_type","=","out_invoice"],["state","=","posted"],
         ["invoice_date",">=",desde],["invoice_date","<=",hasta]],
        fields=["id","name","invoice_date","partner_id","invoice_origin","reversal_move_id"],
        limit=2000, order="invoice_date, id", context={"lang":"es_CR"})
    por_origen = {}
    for m in mv:
        if m["invoice_origin"]: por_origen.setdefault(m["invoice_origin"], []).append(m)
    vivas = {m["id"]: m for m in mv if not m["reversal_move_id"]}
    if not vivas: return [], 0
    ls = call("account.move.line","search_read",
        [["move_id","in",list(vivas)],["display_type","=","product"],["product_id","in",prods]],
        fields=["move_id","product_id","quantity","product_uom_id"],
        limit=20000, context={"lang":"es_CR"})
    uids = sorted({l["product_uom_id"][0] for l in ls if l["product_uom_id"]})
    fac = {u["id"]: (u["factor"] or 1) for u in
           call("uom.uom","read", uids, fields=["id","factor"], context={"lang":"es_CR"})}
    nom = {u["id"]: u["name"] for u in
           call("uom.uom","read", uids + [x for v in uom_ok.values() for x in v],
                fields=["id","name"], context={"lang":"es_CR"})}
    def es_reemplazo(m):
        if not m["invoice_origin"]: return False
        return any(g["id"] != m["id"] and g["reversal_move_id"]
                   for g in por_origen.get(m["invoice_origin"], []))
    reemp = {i: es_reemplazo(vivas[i]) for i in vivas}
    por_fac = {}
    for l in ls:
        pid = l["product_id"][0]; uid = l["product_uom_id"][0]
        if uid in uom_ok.get(pid, []): continue                  # unidad permitida
        uds = (l["quantity"] or 0) / (fac.get(uid) or 1)
        c = cajas.get(pid, 0)
        entera = c > 0 and uds > 0 and abs(uds % c) < 1e-9
        m = vivas[l["move_id"][0]]
        if reemp[m["id"]] and entera: continue                   # el perdon, las DOS
        por_fac.setdefault(m["id"], {"factura_id":m["id"], "factura":m["name"],
            "fecha":m["invoice_date"], "lineas":[]})["lineas"].append(
            {"producto_id":pid, "uom_id":uid, "uds":uds,
             "usa":nom.get(uid,"uom %d"%uid), "por_uom":round(1/(fac.get(uid) or 1)),
             "deben":[nom.get(x,"uom %d"%x) for x in uom_ok[pid]]})
    return list(por_fac.values()), len(vivas)

NOMBRE = {451:"Pan Blanco",452:"Pan Semillas",453:"Pan Francés",
          503:"Buns",472:"Pizza",519:"Galletas"}
def texto(f):
    partes = ["%s en %s (%d u) · le corresponde %s" %
              (NOMBRE.get(l["producto_id"], "id %d"%l["producto_id"]),
               l["usa"], l["por_uom"], " o ".join(l["deben"])) for l in f["lineas"]]
    return "Factura %s · %s" % (f["factura"][-4:], " · ".join(partes))

# ── SUPABASE, por el pooler, con el rol del vigia ────────────────────────
def conectar_db():
    import psycopg  # el workflow lo instala; aca no se usa si va --seco
    return psycopg.connect(os.environ["VIGIA_DB_URL"])

def main():
    a = sys.argv[1:]
    idx  = a[a.index("--index")+1] if "--index" in a else "index.html"
    dias = int(a[a.index("--dias")+1]) if "--dias" in a else 30
    seco = "--seco" in a
    hoy = datetime.date.today()
    desde = (hoy - datetime.timedelta(days=dias)).isoformat(); hasta = hoy.isoformat()

    uom_ok = leer_uom_ok(idx); cajas = leer_cajas(idx)
    print("regla leida de %s: %d productos" % (idx, len(uom_ok)))
    hallazgos, n_rev = barrer(odoo(), uom_ok, cajas, desde, hasta)
    print("revisadas %d facturas vivas · %d con problema" % (n_rev, len(hallazgos)))
    for f in hallazgos: print("   " + texto(f))
    if seco:
        print("--seco: no se escribio nada"); return 0

    creados = []
    with conectar_db() as cx, cx.cursor() as cur:
        for f in hallazgos:
            # SIN DUPLICAR: si ya hay un ticket que nombra esta factura, se salta.
            cur.execute("select id from ticket where descripcion like %s limit 1",
                        ("Factura " + f["factura"][-4:] + " ·%",))
            if cur.fetchone(): continue
            cur.execute(
                "insert into ticket (descripcion, tipo, build, modulo, ambito, creado_por)"
                " values (%s,'no_funciona','vigia-unidades','finanzas','truefie',%s)"
                " returning id", (texto(f), FIRMA))
            creados.append(cur.fetchone()[0])
        cur.execute(
            "insert into revision_unidades (desde, hasta, facturas_revisadas,"
            " avisos_creados, tickets, creado_por) values (%s,%s,%s,%s,%s,%s)",
            (desde, hasta, n_rev, len(creados), creados, FIRMA))
        cx.commit()
    print("tickets creados: %d %s" % (len(creados), creados or ""))
    return 0

if __name__ == "__main__":
    sys.exit(main())
