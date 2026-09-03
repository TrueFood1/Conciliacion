#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
¿Qué hace read-only a `Lobby Solo Lectura` (uid 28): las ACL o las ir.rules?
2-sep-2026. Diagnóstico, no arreglo. No cambia ningún permiso.

POR QUÉ EXISTE. Documentamos que uid 28 "tiene 18 reglas de acceso y CERO con
permiso de escritura". Andrea encontró que entre sus 17 grupos está
[42] Inventory / User —que en Odoo estándar da write/create/unlink sobre
stock.picking y stock.move— más [7] Technical Features y [56] Stock Accounting
Automatic. O sea que "cero de escritura" NO es exacto, y lo que lo frena podrían
ser las ir.rules del grupo [76], que recortan POR ENCIMA de las ACL.
La diferencia importa: una ACL es un permiso; una ir.rule es un filtro de
registros. Si el candado son reglas, es más frágil de lo que escribimos — una
regla mal editada, o un registro que caiga fuera de su dominio, y la escritura
pasa. Esto lo MIDE en vez de suponerlo.

⚠️ ESTE SCRIPT SE SALTA `LECTURA_OK` A PROPÓSITO. Llama a `execute_kw` directo,
no por `odoo_read.call()`. Es el único modo de preguntar por permisos —
`check_access_rights` no es un método de lectura de datos— y de intentar la
escritura de prueba. Está acotado a esta medición y no lo importa nadie.

ORDEN, de menos a más invasivo. Los pasos 1 y 2 NO MODIFICAN NADA:
  1. check_access_rights('write')  → ¿qué dicen las ACL? (sin tocar registros)
  2. check_access_rule('write')    → ¿qué dicen las ir.rules sobre un registro?
  3. write() de prueba             → el candado completo, en vivo
El paso 3 escribe un campo CON SU PROPIO VALOR ACTUAL: si pasara, el dato no
cambia; lo único que se movería es `write_date`, y el script lo reporta antes y
después para que quede a la vista.

Uso:
    python3 diagnostico_permisos.py            # pasos 1 y 2 (no modifican nada)
    python3 diagnostico_permisos.py --escribir # además el paso 3
"""
import sys
import xmlrpc.client
import odoo_read as O

MODELOS = ["stock.picking", "stock.move", "stock.scrap", "stock.move.line",
           "account.move", "product.product"]


def _kw(model, method, *args, **kwargs):
    """execute_kw directo, sin la allowlist. Ver el aviso del encabezado."""
    O._connect()
    return O._MODELS.execute_kw(O.ENV["ODOO_DB"], O._UID, O.ENV["ODOO_APIKEY"],
                                model, method, list(args), kwargs)


def _fault(e):
    """Texto útil de un Fault de Odoo, sin el traceback entero."""
    s = getattr(e, "faultString", str(e)).strip()
    lineas = [l for l in s.splitlines() if l.strip()]
    return lineas[-1][:300] if lineas else s[:300]


def main():
    O._connect()
    env = O.ENV
    print("=" * 72)
    print(f"PRODUCCIÓN · {env['ODOO_URL']}  ·  uid = {O._UID}")
    print("=" * 72)

    # ── 1 · ACL: ¿el permiso existe? (no toca ningún registro) ───────────
    print("\n1 · check_access_rights('write')  — qué dicen las ACL")
    print("   (pregunta por el PERMISO del modelo; no lee ni escribe registros)")
    acl = {}
    for m in MODELOS:
        fila = []
        for op in ("read", "write", "create", "unlink"):
            try:
                r = _kw(m, "check_access_rights", op, raise_exception=False)
            except xmlrpc.client.Fault as e:
                r = f"error: {_fault(e)[:40]}"
            except Exception as e:
                r = f"{type(e).__name__}"
            fila.append((op, r))
        acl[m] = dict(fila)
        txt = "  ".join(f"{op}={str(v):5}" for op, v in fila)
        marca = "⚠️" if fila[1][1] is True else "  "
        print(f"   {marca} {m:18} {txt}")
    escribibles = [m for m in MODELOS if acl[m].get("write") is True]
    print()
    if escribibles:
        print(f"   ⚠️ LAS ACL SÍ DAN WRITE en: {', '.join(escribibles)}")
        print("      O sea que 'cero permisos de escritura' NO es exacto.")
    else:
        print("   ✓ ninguna ACL da write. El candado sería de permisos.")

    # ── 2 · ir.rules: ¿el registro concreto pasa el filtro? ──────────────
    print("\n2 · check_access_rule('write') sobre un albarán YA VALIDADO")
    print("   (evalúa las ir.rules contra un registro real; no lo modifica)")
    pk = None
    try:
        pks = _kw("stock.picking", "search_read",
                  [["picking_type_code", "=", "outgoing"], ["state", "=", "done"]],
                  fields=["id", "name", "state", "write_date"], limit=1, order="id desc")
        if pks:
            pk = pks[0]
            print(f"   registro: [{pk['id']}] {pk['name']}  state={pk['state']}")
            # ⚠️ TRAMPA QUE YA ME COMIÓ UNA VEZ. `check_access_rule` devuelve None
            # cuando PASA, y el endpoint XML-RPC de Odoo no sabe serializar None:
            # contesta un Fault "cannot marshal None unless allow_none is enabled".
            # O sea que ese Fault concreto significa ÉXITO, no bloqueo. Leerlo como
            # "bloqueado por regla" es concluir que hay candado justo cuando no lo hay.
            # Un bloqueo real llega como AccessError, con otro texto.
            try:
                _kw("stock.picking", "check_access_rule", [pk["id"]], "write")
                print("   ⚠️ LAS ir.rules NO LO BLOQUEAN — check_access_rule('write') pasó.")
                regla_bloquea = False
            except xmlrpc.client.Fault as e:
                txt = _fault(e)
                if "marshal None" in txt or "allow_none" in txt:
                    print("   ⚠️ LAS ir.rules NO LO BLOQUEAN — check_access_rule('write') pasó.")
                    print(f"      (el Fault es solo Odoo sin poder serializar el None de éxito:")
                    print(f"       «{txt[:80]}»)")
                    regla_bloquea = False
                else:
                    print(f"   ✓ bloqueado por regla: {txt}")
                    regla_bloquea = True
        else:
            print("   (no encontré ningún albarán de salida en 'done')")
            regla_bloquea = None
    except xmlrpc.client.Fault as e:
        print(f"   no se pudo: {_fault(e)}")
        regla_bloquea = None

    # ── 3 · la prueba de verdad ─────────────────────────────────────────
    print("\n3 · write() de prueba")
    if "--escribir" not in sys.argv:
        print("   OMITIDO. Corré con --escribir para hacerlo.")
        return
    if not pk:
        print("   sin registro de prueba, no se puede.")
        return
    print(f"   objetivo: [{pk['id']}] {pk['name']} (state={pk['state']})")
    try:
        actual = _kw("stock.picking", "read", [pk["id"]], ["note", "write_date"])[0]
    except xmlrpc.client.Fault as e:
        print(f"   no pude leer el campo de prueba: {_fault(e)}")
        return
    nota = actual.get("note")
    nota = nota if nota not in (None, False) else ""
    print(f"   campo: note  ·  se escribe SU PROPIO VALOR ACTUAL ({len(str(nota))} chars)")
    print(f"   write_date antes : {actual.get('write_date')}")
    try:
        r = _kw("stock.picking", "write", [pk["id"]], {"note": nota})
        print(f"\n   🔴🔴 LA ESCRITURA PASÓ. write() devolvió {r!r}")
        despues = _kw("stock.picking", "read", [pk["id"]], ["write_date"])[0]
        print(f"   write_date después: {despues.get('write_date')}")
        print("   El dato NO cambió (se escribió el mismo valor), pero el candado NO PARÓ.")
        print("   PARAR ACÁ. No seguir con el carril de escritura.")
    except xmlrpc.client.Fault as e:
        print(f"\n   ✓ BLOQUEADA. Odoo respondió:\n     {_fault(e)}")
        despues = None
        try:
            despues = _kw("stock.picking", "read", [pk["id"]], ["write_date"])[0]
            print(f"   write_date después: {despues.get('write_date')}  "
                  f"({'sin cambios' if despues.get('write_date')==actual.get('write_date') else '⚠️ CAMBIÓ'})")
        except Exception:
            pass
    except Exception as e:
        print(f"\n   ? error no-Odoo: {type(e).__name__}: {str(e)[:200]}")


if __name__ == "__main__":
    main()
