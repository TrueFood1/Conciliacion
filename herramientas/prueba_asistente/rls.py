#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
¿Qué LEE y qué NO ESCRIBE el perfil «asistente» (Instinct)? Medido con la RLS de verdad.

14-oct-2026. Reusa la sesión y el sobre de `pg_pruebas.py` (rol `truefie_pruebas`, carril B:
`set local role authenticated` + los claims del correo), sin tocar sus pruebas. Cada consulta va en
SU propia transacción y termina en ROLLBACK, en su propio mensaje: no queda nada escrito.

  L · LECTURA. Para cada objeto que lee `index.html` (los `from('…')`, la misma lista que
      esquema_check.py) cuenta filas como asistente y como socia. Lo esperado: LAS MISMAS.
  E · ESCRITURA. Intentos de escribir como asistente: tienen que rebotar (42501 o el guardia).

Los correos salen de la BASE (v_acceso_usuario), no del repo.

    python3 herramientas/prueba_asistente/rls.py
"""
import os, re, sys
AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(os.path.dirname(AQUI))
sys.path.insert(0, os.path.join(RAIZ, "herramientas"))
import pg_pruebas as P                                   # noqa: E402


def filas_de(eventos):
    for e in eventos or []:
        if e[0] == "filas":
            return e[2]
    return None


def error_de(eventos):
    for e in eventos or []:
        if e[0] == "error":
            return e
    return None


def en_sobre(ses, email, sql):
    """begin + identidad (carril B) · la consulta · rollback, cada uno en su mensaje."""
    abrir, _ = P.sobre_abrir("B", email, False)
    ses.consulta(abrir)
    try:
        ev, _ = ses.consulta(sql)
    finally:
        ses.consulta("rollback;")
    return ev


def main():
    clave = P._claves().get("PRUEBAS_ROL_PASSWORD")
    if not clave:
        print("✗ falta PRUEBAS_ROL_PASSWORD en conexion_db.env"); return 1
    ses = P.Sesion(P.USUARIO, clave)
    ev, _ = ses.consulta("select perfil, email from v_acceso_usuario where activo and perfil in ('asistente','socias') "
                         "order by perfil, email;")
    gente = {}
    for f in filas_de(ev) or []:
        gente.setdefault(f[0], f[1])
    if "asistente" not in gente or "socias" not in gente:
        print("✗ faltan identidades: %s" % gente); return 1
    asis, socia = gente["asistente"], gente["socias"]
    print("asistente → %s · socia → %s\n" % (asis, socia))

    # ¿Está encendido el interruptor? (asistente_lee exige asistente_encendido())
    ev = en_sobre(ses, asis, "select asistente_encendido()::text, acceso_perfil()::text, acceso_es_socia()::text;")
    print("asistente_encendido · acceso_perfil · acceso_es_socia (como asistente): %s\n" % (filas_de(ev),))

    txt = open(os.path.join(RAIZ, "index.html"), encoding="utf-8").read()
    objs = sorted(set(re.findall(r"from\('([a-z_][a-z0-9_]*)'\)", txt)) |
                  {"ent_pedido_anulacion", "cont_barrido_odoo"})          # los que se leen por variable
    print("L · LECTURA — filas que ve cada una (mismo objeto, misma consulta)\n")
    print("  %-38s %10s %10s   %s" % ("objeto", "asistente", "socia", ""))
    distintos = 0
    for o in objs:
        r = {}
        for quien, mail in (("a", asis), ("s", socia)):
            ev = en_sobre(ses, mail, "select count(*)::text from public.%s;" % o)
            f, e = filas_de(ev), error_de(ev)
            r[quien] = f[0][0] if f else ("ERR %s" % (e[1].get("C") if e and isinstance(e[1], dict) else e))
        marca = "" if r["a"] == r["s"] else "  ⚠️ distinto"
        distintos += bool(marca)
        print("  %-38s %10s %10s%s" % (o, r["a"], r["s"], marca))
    print("\n  %d objetos · %d con resultado distinto entre asistente y socia\n" % (len(objs), distintos))

    print("E · ESCRITURA como asistente (cada intento en rollback)\n")
    intentos = [
        ("anular una salida (ent_anulacion)", "insert into ent_anulacion (entidad, entidad_id, motivo, creado_por) values ('salida', 1, 'prueba', current_setting('request.jwt.claims')::json->>'email');"),
        ("marcar «Hecho» en la cola de Odoo (ent_odoo_hecho)", "insert into ent_odoo_hecho (pendiente_id, referencia, creado_por) select id, 'prueba', current_setting('request.jwt.claims')::json->>'email' from ent_odoo_pendiente limit 1;"),
        ("guardar una propuesta de compra (compra_propuesta)", "insert into compra_propuesta (proveedor_id, modo, pedido_dia, entrega_dia, lineas, creado_por) values (948, 'pedir', current_date, current_date + 5, '[]', current_setting('request.jwt.claims')::json->>'email');"),
        ("cambiar la configuración de compras (plan_config)", "insert into plan_config (clave, valor) values ('compras_config', '{}'::jsonb);"),
        ("anular un pedido (ent_anular_pedido)", "select ent_anular_pedido(1, 'duplicado', null, false);"),
        ("crear un pedido de Entregas (ent_pedido)", "insert into ent_pedido (fecha_despacho, origen, motivo, creado_por) values (current_date, 'manual', 'regalia', current_setting('request.jwt.claims')::json->>'email');"),
        ("editar un usuario (acceso_usuario)", "update acceso_usuario set nota = 'prueba' where true;"),
        ("borrar un conteo (ent_conteo)", "delete from ent_conteo where true;"),
    ]
    for nombre, sql in intentos:
        ev = en_sobre(ses, asis, sql)
        e = error_de(ev)
        if e:
            d = e[1] if isinstance(e[1], dict) else {}
            print("  RECHAZA  %-52s %s · %s" % (nombre, d.get("C"), (d.get("M") or "")[:90]))
        else:
            n = None
            for x in ev or []:
                if x[0] == "ok": n = x
            print("  ⚠️ ENTRA %-52s %s" % (nombre, n or filas_de(ev)))
    ses.cerrar()
    return 0


if __name__ == "__main__":
    sys.exit(main())
