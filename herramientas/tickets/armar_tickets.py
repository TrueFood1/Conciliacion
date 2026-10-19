#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
armar_tickets.py — arma el ENSAYO y el PEGADO de tickets nuevos desde un JSON (19-oct-2026).
Lo usa el /cierre (cada pendiente nuevo de la sesión → un ticket) y sirvió para la tanda del 19-oct.

    python3 herramientas/tickets/armar_tickets.py herramientas/tickets/tanda_19oct.json PEGADO_TICKETS_19OCT

Escribe <SALIDA>.sql (el pegado) y <SALIDA>_ENSAYO.sql (lo mismo + pruebas + rollback). Los dos empiezan
con PEGADO_ → gitignored: un ticket puede nombrar brechas de seguridad, y el repo es PÚBLICO.

LAS FIRMAS DEL EDITOR SQL (las hacen cumplir las guardias vivas; medido el 19-oct):
  · el ticket firma creado_por 'ticket-sql…'; marca, estado y detalles firman 'cc-sql…'.
  · desde el editor NO se cierra, NO se pospone y NO se descarta (ticket_estado_guard): eso es de las socias.
  · en un pendiente PROPIO («Mis pendientes») el editor no pone marca ni estado: solo nace, con su
    explicación. Lo triá Andrea.
  · la explicación va en los cuatro renglones fijos que exige ticket_detalle (Qué es · Por qué importa ·
    Qué haría falta: chico|mediano|grande · Recomendación: HACER|CERRAR|DESCARTAR).

LA GUARDA: antes de insertar, el pegado busca cada ticket por su `clave` (un texto corto que va al
principio de la descripción). Si ya hay un ticket con esa clave —abierto, cerrado o descartado— PARA
todo. Así una tanda pegada dos veces no duplica nada.

JSON: [{"clave": "Permisos por rol", "ambito": "truefie|propio", "modulo": null|"compras"|…, "tipo": "encargo",
        "descripcion": "…", "explicacion": ["Qué es…", "Por qué…", "chico. …", "HACER. …"],
        "marca": {"prioridad": "alta", "toca_numeros": false, "escribe_en_base": true, "razon": "…"} | null,
        "anuncio": "…" | null}]
"""
import hashlib, json, os, re, sys

ESTADO_OK = {"truefie", "propio"}
TIPOS = {"no_funciona", "duda", "idea", "encargo"}


def q(t):
    return "'" + str(t).replace("'", "''") + "'"


def validar(T):
    for x in T:
        assert x["ambito"] in ESTADO_OK and x["tipo"] in TIPOS, x["clave"]
        assert x["descripcion"].startswith(x["clave"]), "la descripción tiene que empezar por la clave: " + x["clave"]
        e = x["explicacion"]
        assert len(e) == 4 and all("\n" not in l and len(l) >= 3 for l in e), x["clave"]
        # Igual que los CHECK de ticket_detalle: la palabra al principio y después un fin de palabra.
        assert re.match(r"(chico|mediano|grande)\b", e[2]), x["clave"]
        assert re.match(r"(HACER|CERRAR|DESCARTAR)\b", e[3]), x["clave"]
        if x.get("marca"):
            assert x["ambito"] == "truefie", "un propio no lleva marca desde el editor: " + x["clave"]
            assert x["marca"]["prioridad"] in ("alta", "media", "baja") and len(x["marca"]["razon"]) >= 12


def cuerpo(T, build, firma_t, firma_d):
    s = ["create temp table _tk_nuevos (n int, clave text, id bigint) on commit drop;",
         "do $$",
         "declare v_id bigint;",
         "begin"]
    claves = ", ".join(q(x["clave"]) for x in T)
    s += ["  -- LA GUARDA: ninguna clave puede existir ya, en ningún estado.",
          "  if exists (select 1 from ticket t, unnest(array[%s]) c where t.descripcion ilike c || '%%') then" % claves,
          "    raise exception 'ya existe un ticket con alguna de estas claves: no se pega dos veces (%%)',",
          "      (select string_agg(t.id || ' ' || c, ', ') from ticket t, unnest(array[%s]) c where t.descripcion ilike c || '%%');" % claves,
          "  end if;"]
    for n, x in enumerate(T, 1):
        expl = "Qué es: %s\nPor qué importa: %s\nQué haría falta: %s\nRecomendación: %s" % tuple(x["explicacion"])
        s.append("  -- %d · %s" % (n, x["clave"]))
        s.append("  insert into ticket (descripcion, tipo, build, modulo, ambito, creado_por) values (%s, %s, %s, %s, %s, %s) returning id into v_id;"
                 % (q(x["descripcion"]), q(x["tipo"]), q(build), "null" if not x.get("modulo") else q(x["modulo"]), q(x["ambito"]), q(firma_t)))
        s.append("  insert into _tk_nuevos values (%d, %s, v_id);" % (n, q(x["clave"])))
        s.append("  insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_id, 'explicacion', %s, %s);"
                 % ("E" + q(expl.replace("\\", "\\\\").replace("\n", "\\n")), q(firma_d)))
        if x.get("anuncio"):
            s.append("  insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_id, 'anuncio', %s, %s);" % (q(x["anuncio"]), q(firma_d)))
        if x.get("marca"):
            m = x["marca"]
            s.append("  insert into ticket_marca (ticket_id, toca_numeros, escribe_en_base, prioridad, razon, creado_por) values (v_id, %s, %s, %s, %s, %s);"
                     % (str(m["toca_numeros"]).lower(), str(m["escribe_en_base"]).lower(), q(m["prioridad"]), q(m["razon"]), q(firma_d)))
    s += ["end $$;"]
    return "\n".join(s)


def main():
    spec, salida = sys.argv[1], sys.argv[2]
    D = json.load(open(spec, encoding="utf-8"))
    T, build, fecha = D["tickets"], D["build"], D["fecha"]
    validar(T)
    firma_t, firma_d = "ticket-sql · CC %s" % fecha, "cc-sql · CC %s" % fecha
    c = cuerpo(T, build, firma_t, firma_d)
    md5 = hashlib.md5(c.encode()).hexdigest()
    n = len(T); nm = sum(1 for x in T if x.get("marca")); na = sum(1 for x in T if x.get("anuncio"))
    lista = "\n".join("--   %d · [%s · %s] %s" % (i, "Mis pendientes" if x["ambito"] == "propio" else (x.get("modulo") or "General"),
                                                  x["tipo"], x["clave"]) for i, x in enumerate(T, 1))
    cab = ("-- ═══════════════════════════════════════════════════════════════════════════\n"
           "-- %s  ·  %s  ·  %d tickets nuevos (armado por herramientas/tickets/armar_tickets.py)\n"
           "-- ⛔ NO SE CORRIÓ. md5 del cuerpo: %s\n%s\n"
           "-- Firmas: ticket 'ticket-sql · CC %s' · detalles y marcas 'cc-sql · CC %s'. Sin estado: nacen «sin revisar»\n"
           "-- (cerrar, posponer y descartar son de las socias, desde la pantalla).\n"
           "-- ═══════════════════════════════════════════════════════════════════════════\n") % ("%s", fecha, n, md5, lista, fecha, fecha)
    control = ("select count(*) as tickets_nuevos,\n"
               "       count(*) filter (where v.estado = 'sin_triar') as sin_revisar,\n"
               "       count(*) filter (where v.en_claro is not null) as con_explicacion,\n"
               "       (select count(*) from ticket_marca m where m.ticket_id in (select id from _tk_nuevos)) as con_marca,\n"
               "       (select count(*) from ticket_detalle d where d.clase = 'anuncio' and d.ticket_id in (select id from _tk_nuevos)) as anuncios,\n"
               "       string_agg('T-' || n.id || ' ' || n.clave, ' · ' order by n.n) as ids\n"
               "  from _tk_nuevos n join v_ticket v on v.id = n.id;")
    esperado = "-- ESPERADO: %d · %d · %d · %d · %d · (los T-… nuevos, en orden)" % (n, n, n, nm, na)
    open(salida + ".sql", "w", encoding="utf-8").write(
        cab % (salida + ".sql") + "begin;\n\n" + c + "\n\n-- CONTROL, justo antes del commit.\n" + esperado + "\n" + control + "\ncommit;\n")
    open(salida + "_ENSAYO.sql", "w", encoding="utf-8").write(
        (cab % (salida + "_ENSAYO.sql")).replace("⛔ NO SE CORRIÓ.", "ENSAYO EN SECO · termina en ROLLBACK · ⛔ NO SE CORRIÓ.")
        + "begin;\n\n" + c + "\n\n-- RESULTADO del ensayo (mismo control que el pegado).\n" + esperado + "\n" + control + "\nrollback;\n")
    print("%s.sql + %s_ENSAYO.sql · %d tickets · %d con marca · %d anuncios · md5 %s" % (salida, salida, n, nm, na, md5[:8]))


if __name__ == "__main__":
    main()
