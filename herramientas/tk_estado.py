#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
tk_estado.py — CC mueve el estado de un ticket de Truefie con su PROPIO rol,
`truefie_cc`, y deja rastro. Nada mas.

POR QUE EXISTE (27-sep-2026, opcion A de Andrea)
  Hasta hoy cerrar era siempre de Andrea (regla del 19-sep). Desde TICKETS_CC.sql,
  CC puede cerrar un ticket de Truefie que resolvio, con la evidencia (build y/o
  commit) en una linea. Descartar, posponer, reabrir y los pendientes propios
  siguen siendo de Andrea, y eso no lo decide este script: lo deciden los
  guardias de la base y la RLS del rol. Este script es solo la puerta.

QUE PUEDE Y QUE NO (lo hace cumplir la BASE, no este archivo)
  · DESDE EL 19-OCT (TICKETS_CC_AMPLIADO.sql, decision de Andrea): ve y escribe en tickets de Truefie Y en
    los pendientes propios de Andrea: agrega tickets (`nuevo`, `tanda`), marcas (`marcar`), explicaciones,
    anuncios y estados. Antes (27-sep) un propio, para el rol, no existia.
  · estados: cerrado · en_validacion · en_curso · disponible · bloqueado.
  · no toca un ticket cerrado, pospuesto o descartado: eso lo reabre Andrea.
  · al cerrar: evidencia OBLIGATORIA, una linea, con el build (b72) o el commit.
  · firma fija 'cc-truefie'. En el Historial sale "Cerrado · cc-truefie · b72".

COMO SE USA
    python3 herramientas/tk_estado.py ver 115
    python3 herramientas/tk_estado.py mover 116 en_curso --seco
    python3 herramientas/tk_estado.py anunciar 15 --texto "hallazgo…" [--seco]
    python3 herramientas/tk_estado.py explicar 15 \\
        --que-es "…" --por-que "…" --falta "chico. …" --recomienda "HACER. …" [--seco]
    python3 herramientas/tk_estado.py nuevo --ambito truefie --modulo compras --tipo encargo \\
        --descripcion "…" [--build b108] [--seco]          # imprime el T-<n> nuevo
    python3 herramientas/tk_estado.py marcar 148 --prioridad alta --toca-numeros no \\
        --escribe-en-base si --razon "…" [--bloquea-entrega no] [--seco]
    python3 herramientas/tk_estado.py tanda herramientas/tickets/tanda_X.json [--seco]
        # los tickets del /cierre: TODOS en una transaccion (todo o nada), cada uno con su
        # explicacion, su anuncio y su marca; frena si alguna clave ya existe en cualquier estado
    python3 herramientas/tk_estado.py cerrar 116 \\
        --evidencia "Resuelto en b72 (65ac781): el 247 ya aparece en Despachos" \\
        --build b72 [--cierre "texto del detalle de cierre"] [--seco]
    # en un PROPIO la evidencia puede ser tambien "archivo: …", "correo: …" o "enlace: …"

  --seco manda el cambio de verdad adentro de una transaccion y la deshace: los
  guardias y la RLS reales lo juzgan, y no queda nada. Siempre primero --seco.

LA CLAVE — en el LLAVERO de macOS, nunca en un archivo ni en el portapapeles
  Servicio `truefie-cc-db`, cuenta `truefie_cc` (hermana de `truefie-vigia-db`).
  Cada vez que corre, el script la pide al llavero con
      security find-generic-password -s truefie-cc-db -a truefie_cc -w
  la guarda en memoria y se va con el proceso. No se imprime nunca. La primera
  vez macOS pregunta si `security` puede leerla: "Permitir siempre".

  ALTA DE LA CLAVE (una sola vez, despues de pegar TICKETS_CC.sql):
      python3 herramientas/tk_estado.py clave-nueva
    1. genera una clave al azar y la escribe en un archivo temporal con permisos
       600, FUERA del repo;
    2. la pasa del archivo al llavero por la entrada estandar de `security -i`
       (no por la linea de comandos: ahi la veria `ps`);
    3. BORRA el archivo;
    4. calcula el VERIFICADOR SCRAM (lo que Postgres guarda de una clave) y deja
       en el portapapeles UNA linea  alter role truefie_cc with password '…';
       Con el verificador no se puede entrar: la clave no sale del llavero.
  Si el portapapeles se piso antes de pegarla:
      python3 herramientas/tk_estado.py verificador
  (rearma la linea desde el llavero, con sal nueva; la clave no cambia)
  Despues de que Andrea pegue esa linea:
      python3 herramientas/tk_estado.py probar
"""

import base64, hashlib, hmac, os, re, secrets, subprocess, sys, tempfile

_AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _AQUI)
from pg_lector import Lector, tabla, HOST, PUERTO, BASE   # noqa: E402
from probar_conexion import REF                             # noqa: E402

ROL      = "truefie_cc"
USUARIO  = ROL + "." + REF          # Supavisor exige el sufijo del proyecto
SERVICIO = "truefie-cc-db"
FIRMA    = "cc-truefie"
ESTADOS  = ("cerrado", "en_validacion", "en_curso", "disponible", "bloqueado")
# Copia de lo que exige el guardia, SOLO para avisar antes de conectar. La
# regla que manda es la de la base (ticket_estado_guard).
EVIDENCIA = re.compile(r"(^|[^0-9a-z])(b[0-9]{2,3}|[0-9a-f]{7,40})([^0-9a-z]|$)")


# ── la clave ─────────────────────────────────────────────────────────────
def clave_del_llavero():
    r = subprocess.run(["security", "find-generic-password", "-s", SERVICIO, "-a", ROL, "-w"],
                       capture_output=True, text=True)
    c = (r.stdout or "").strip()
    if r.returncode != 0 or not c:
        sys.exit("no encuentro la clave de %s en el llavero (servicio %s). "
                 "¿Se corrio `clave-nueva`?" % (ROL, SERVICIO))
    return c


def verificador_scram(clave, iteraciones=4096):
    """El verificador SCRAM-SHA-256 que Postgres guarda (RFC 5802/7677)."""
    sal = secrets.token_bytes(16)
    salted = hashlib.pbkdf2_hmac("sha256", clave.encode("utf-8"), sal, iteraciones)
    client_key = hmac.new(salted, b"Client Key", hashlib.sha256).digest()
    stored_key = hashlib.sha256(client_key).digest()
    server_key = hmac.new(salted, b"Server Key", hashlib.sha256).digest()
    b = lambda x: base64.b64encode(x).decode()
    return "SCRAM-SHA-256$%d:%s$%s:%s" % (iteraciones, b(sal), b(stored_key), b(server_key))


def verificador_al_portapapeles():
    """Vuelve a armar la linea `alter role` desde la clave del LLAVERO (sal
    nueva, misma clave) y la deja en el portapapeles. Para cuando la primera se
    perdio porque el portapapeles se piso antes de pegarla."""
    linea = "alter role truefie_cc with password '%s';" % verificador_scram(clave_del_llavero())
    subprocess.run(["pbcopy"], input=linea.encode("utf-8"),
                   env=dict(os.environ, LANG="en_US.UTF-8"))
    print("en el portapapeles: UNA linea `alter role truefie_cc with password 'SCRAM-SHA-256$4096:…'`")
    print("Es el verificador, no la clave. Pegarla SOLA en el editor SQL y correrla.")


def clave_nueva():
    if subprocess.run(["security", "find-generic-password", "-s", SERVICIO, "-a", ROL],
                      capture_output=True).returncode == 0:
        sys.exit("ya hay una clave de %s en el llavero. Para cambiarla, borrarla a mano "
                 "primero (Acceso a Llaveros) y volver a correr esto." % ROL)
    clave = secrets.token_urlsafe(36)          # [A-Za-z0-9_-], sin comillas ni espacios
    fd, ruta = tempfile.mkstemp(prefix="tkcc-", dir=os.path.expanduser("~"))
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(clave)
        print("1 · clave generada en un archivo temporal 600, fuera del repo")
        with open(ruta) as f:
            desde_archivo = f.read()
        orden = 'add-generic-password -s %s -a %s -l "Truefie · rol truefie_cc" -w "%s"\n' % (
            SERVICIO, ROL, desde_archivo)
        r = subprocess.run(["security", "-i"], input=orden, capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit("el llavero no la acepto: %s" % (r.stderr or "").strip()[:200])
        print("2 · guardada en el llavero (servicio %s, cuenta %s)" % (SERVICIO, ROL))
    finally:
        try:
            os.remove(ruta)
        except OSError:
            pass
    print("3 · archivo temporal borrado: %s" % ("SI" if not os.path.exists(ruta) else "NO — BORRARLO A MANO"))
    if clave_del_llavero() != clave:
        sys.exit("lo que devuelve el llavero no es lo que se guardo: no seguir")
    linea = "alter role truefie_cc with password '%s';" % verificador_scram(clave)
    subprocess.run(["pbcopy"], input=linea.encode("utf-8"),
                   env=dict(os.environ, LANG="en_US.UTF-8"))
    print("4 · en el portapapeles: UNA linea `alter role truefie_cc with password 'SCRAM-SHA-256$4096:…'`")
    print("    Es el verificador, no la clave. Pegarla SOLA en el editor SQL y correrla.")
    print("    Despues: python3 herramientas/tk_estado.py probar")


# ── la conexion ──────────────────────────────────────────────────────────
def conectar():
    return Lector(clave_del_llavero(), host=HOST, puerto=PUERTO, usuario=USUARIO, base=BASE)


def lit(s):
    return "null" if s is None else "'" + str(s).replace("'", "''") + "'"


def ver(db, t):
    cols, filas = db._crudo(
        "select t.id, t.ambito, t.tipo, left(t.descripcion, 70) as descripcion, "
        "coalesce((select x.estado from ticket_estado x where x.ticket_id = t.id "
        "          order by x.creado_en desc, x.id desc limit 1), 'sin_triar') as estado "
        "from ticket t where t.id = %d" % t)[-1]
    if not filas:
        print("T-%04d: no existe (o truefie_cc no lo ve)." % t)
        return None
    print(tabla(cols, filas, 70))
    return filas[0][4]


def mover(db, t, estado, nota=None, build=None, cierre=None, seco=True):
    sql = ["begin;",
           "insert into ticket_estado (ticket_id, estado, creado_por, nota, build_arreglo) "
           "values (%d, %s, %s, %s, %s) returning id, estado, creado_por, build_arreglo;"
           % (t, lit(estado), lit(FIRMA), lit(nota), lit(build))]
    if cierre:
        sql.append("insert into ticket_detalle (ticket_id, clase, texto, creado_por) "
                   "values (%d, 'cierre', %s, %s);" % (t, lit(cierre), lit(FIRMA)))
    sql.append("rollback;" if seco else "commit;")
    try:
        res = db._crudo("\n".join(sql))
    except RuntimeError as e:
        try:
            db._crudo("rollback;")
        except Exception:
            pass
        print("RECHAZADO por la base: %s" % e)
        return False
    print(tabla(*res[0]))
    print("✓ %s" % ("SECO: la base lo acepto y se deshizo. No quedo nada."
                   if seco else "GUARDADO."))
    return True


def anunciar(db, t, texto, seco=True):
    """Un detalle 'anuncio' (un hallazgo, un dato que se suma). La base solo le
    deja a truefie_cc escribir 'cierre' o 'anuncio'."""
    sql = ("begin;\n"
           "insert into ticket_detalle (ticket_id, clase, texto, creado_por) "
           "values (%d, 'anuncio', %s, %s);\n%s" % (t, lit(texto), lit(FIRMA), "rollback;" if seco else "commit;"))
    try:
        db._crudo(sql)
    except RuntimeError as e:
        try:
            db._crudo("rollback;")
        except Exception:
            pass
        print("RECHAZADO por la base: %s" % e)
        return False
    print("✓ %s" % ("SECO: la base lo acepto y se deshizo. No quedo nada."
                   if seco else "GUARDADO (anuncio)."))
    return True


# ── EN PALABRAS CLARAS (29-sep-2026, TICKETS_EXPLICACION.sql) ──────────────
# Cuatro renglones fijos para Andrea. El texto se ARMA aca, desde cuatro
# opciones, para que nadie escriba los titulos a mano. La regla que manda es
# la de la TABLA (tres CHECK: forma, tamano, recomienda); esto solo avisa antes
# de conectar, con el mismo criterio.
TAMANOS = ("chico", "mediano", "grande")
RECOMIENDA = ("HACER", "CERRAR", "DESCARTAR")


def armar_explicacion(que_es, por_que, falta, recomienda):
    partes = {"--que-es": que_es, "--por-que": por_que, "--falta": falta, "--recomienda": recomienda}
    for nombre, v in partes.items():
        if not v or len(v.strip()) < 3:
            sys.exit("%s es obligatorio (3 caracteres o mas)" % nombre)
        if "\n" in v or "\r" in v:
            sys.exit("%s va en UN renglon" % nombre)
    if not re.match(r"(%s)\b" % "|".join(TAMANOS), falta.strip()):
        sys.exit("--falta empieza con el tamano: %s" % " | ".join(TAMANOS))
    if not re.match(r"(%s)\b" % "|".join(RECOMIENDA), recomienda.strip()):
        sys.exit("--recomienda empieza con: %s" % " | ".join(RECOMIENDA))
    return "\n".join(("Qué es: " + que_es.strip(),
                      "Por qué importa: " + por_que.strip(),
                      "Qué haría falta: " + falta.strip(),
                      "Recomendación: " + recomienda.strip()))


def explicar(db, t, texto, seco=True):
    """Un detalle 'explicacion'. Vale la ULTIMA: reescribir es agregar otra."""
    sql = ("begin;\n"
           "insert into ticket_detalle (ticket_id, clase, texto, creado_por) "
           "values (%d, 'explicacion', %s, %s);\n%s" % (t, lit(texto), lit(FIRMA), "rollback;" if seco else "commit;"))
    try:
        db._crudo(sql)
    except RuntimeError as e:
        try:
            db._crudo("rollback;")
        except Exception:
            pass
        print("RECHAZADO por la base: %s" % e)
        return False
    print(texto)
    print("✓ %s" % ("SECO: la base lo acepto y se deshizo. No quedo nada."
                   if seco else "GUARDADO (explicacion)."))
    return True


# ── TICKETS NUEVOS Y MARCAS (19-oct-2026, TICKETS_CC_AMPLIADO.sql) ─────────
AMBITOS = ("truefie", "propio")
TIPOS = ("no_funciona", "duda", "idea", "encargo")
EVIDENCIA_PROPIO = re.compile(r"^(archivo|correo|enlace): \S", re.I)


def _correr(db, sql, seco):
    """Una transaccion: o entra todo, o nada. En seco, siempre se deshace."""
    try:
        res = db._crudo("begin;\n" + sql + ("\nrollback;" if seco else "\ncommit;"))
        return res
    except RuntimeError as e:
        try:
            db._crudo("rollback;")
        except Exception:
            pass
        print("RECHAZADO por la base: %s" % e)
        return None


def nuevo(db, ambito, modulo, tipo, descripcion, build, seco=True):
    if ambito not in AMBITOS or tipo not in TIPOS or not descripcion or len(descripcion.strip()) < 5:
        sys.exit("nuevo: --ambito truefie|propio, --tipo %s, --descripcion de 5 letras o mas" % "|".join(TIPOS))
    res = _correr(db, "insert into ticket (descripcion, tipo, build, modulo, ambito, creado_por) values "
                      "(%s, %s, %s, %s, %s, %s) returning id;" % (lit(descripcion.strip()), lit(tipo), lit(build),
                      lit(modulo), lit(ambito), lit(FIRMA)), seco)
    if res is None:
        return None
    tid = int(res[0][1][0][0])
    print("✓ %s T-%d (%s%s)" % ("SECO: entraria como" if seco else "CREADO", tid, ambito, (" · " + modulo) if modulo else ""))
    return tid


def marcar(db, t, prioridad, toca, escribe, bloquea, razon, seco=True):
    si = {"si": "true", "sí": "true", "no": "false"}
    if prioridad not in ("alta", "media", "baja") or toca not in si or escribe not in si or bloquea not in si \
            or not razon or len(razon.strip()) < 12:
        sys.exit("marcar: --prioridad alta|media|baja, --toca-numeros si|no, --escribe-en-base si|no, "
                 "--razon de 12 letras o mas")
    res = _correr(db, "insert into ticket_marca (ticket_id, toca_numeros, escribe_en_base, bloquea_entrega, prioridad, "
                      "razon, creado_por) values (%d, %s, %s, %s, %s, %s, %s);" % (t, si[toca], si[escribe], si[bloquea],
                      lit(prioridad), lit(razon.strip()), lit(FIRMA)), seco)
    if res is not None:
        print("✓ %s (marca %s en T-%d)" % ("SECO: la base lo acepto y se deshizo." if seco else "GUARDADO", prioridad, t))
    return res is not None


def tanda(db, ruta, seco=True):
    """Los tickets nuevos del /cierre, desde el JSON de armar_tickets.py, en UNA transaccion."""
    import json
    D = json.load(open(ruta, encoding="utf-8"))
    T, build = D["tickets"], D.get("build")
    claves = ", ".join(lit(x["clave"]) for x in T)
    sql = ["create temp table _tk_nuevos (n int, clave text, id bigint) on commit drop;",
           "do $$ declare v_id bigint; begin",
           "  if exists (select 1 from ticket t, unnest(array[%s]) c where t.descripcion ilike c || '%%') then" % claves,
           # sin el % de Python: un solo % (el lugar del dato en el RAISE)
           "    raise exception 'ya existe un ticket con alguna de estas claves (%): no se carga dos veces',",
           "      (select string_agg(t.id || ' ' || c, ', ') from ticket t, unnest(array[%s]) c where t.descripcion ilike c || '%%');" % claves,
           "  end if;"]
    for n, x in enumerate(T, 1):
        if not x["descripcion"].startswith(x["clave"]):
            sys.exit("la descripcion tiene que empezar por la clave: %s" % x["clave"])
        expl = armar_explicacion(*x["explicacion"])
        sql.append("  insert into ticket (descripcion, tipo, build, modulo, ambito, creado_por) values (%s, %s, %s, %s, %s, %s) "
                   "returning id into v_id;" % (lit(x["descripcion"]), lit(x["tipo"]), lit(build), lit(x.get("modulo")),
                                                lit(x["ambito"]), lit(FIRMA)))
        sql.append("  insert into _tk_nuevos values (%d, %s, v_id);" % (n, lit(x["clave"])))
        sql.append("  insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_id, 'explicacion', %s, %s);"
                   % (lit(expl), lit(FIRMA)))
        if x.get("anuncio"):
            sql.append("  insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_id, 'anuncio', %s, %s);"
                       % (lit(x["anuncio"]), lit(FIRMA)))
        if x.get("marca"):
            m = x["marca"]
            sql.append("  insert into ticket_marca (ticket_id, toca_numeros, escribe_en_base, prioridad, razon, creado_por) "
                       "values (v_id, %s, %s, %s, %s, %s);" % (str(m["toca_numeros"]).lower(), str(m["escribe_en_base"]).lower(),
                                                              lit(m["prioridad"]), lit(m["razon"]), lit(FIRMA)))
    sql += ["end $$;", "select string_agg('T-' || id || ' ' || clave, ' · ' order by n) as tickets from _tk_nuevos;"]
    res = _correr(db, "\n".join(sql), seco)
    if res is not None:
        print("✓ %s %s" % ("SECO (se deshizo):" if seco else "CREADOS:", res[-1][1][0][0]))
    return res is not None


def main():
    a = sys.argv[1:]
    if not a or a[0] in ("-h", "--help"):
        print(__doc__.strip()); return
    cmd = a[0]
    if cmd == "clave-nueva":
        clave_nueva(); return
    if cmd == "verificador":
        verificador_al_portapapeles(); return
    def opt(nombre):
        if nombre in a:
            i = a.index(nombre)
            if i + 1 >= len(a):
                sys.exit("falta el valor de %s" % nombre)
            return a[i + 1]
        return None
    seco = "--seco" in a
    with conectar() as db:
        if cmd == "probar":
            print(tabla(*db._crudo("select current_user as rol, "
                                   "(select count(*) from ticket) as tickets_que_ve;")[-1]))
            return
        if cmd == "nuevo":
            nuevo(db, opt("--ambito"), opt("--modulo"), opt("--tipo") or "encargo", opt("--descripcion"),
                  opt("--build"), seco=seco); return
        if cmd == "tanda":
            if len(a) < 2:
                sys.exit("tanda <archivo.json>")
            tanda(db, a[1], seco=seco); return
        if len(a) < 2 or not a[1].isdigit():
            sys.exit("falta el numero de ticket")
        t = int(a[1])
        if cmd == "ver":
            ver(db, t); return
        if cmd == "mover":
            if len(a) < 3 or a[2] not in ESTADOS or a[2] == "cerrado":
                sys.exit("mover T <estado>, con estado en: %s (para cerrar, usar `cerrar`)"
                         % ", ".join(e for e in ESTADOS if e != "cerrado"))
            if ver(db, t) is None: return
            mover(db, t, a[2], nota=opt("--nota"), seco=seco); return
        if cmd == "anunciar":
            tx = opt("--texto")
            if not tx or len(tx.strip()) < 10:
                sys.exit("--texto es obligatorio (10 caracteres o mas)")
            if ver(db, t) is None: return
            anunciar(db, t, tx, seco=seco); return
        if cmd == "explicar":
            tx = armar_explicacion(opt("--que-es"), opt("--por-que"), opt("--falta"), opt("--recomienda"))
            if ver(db, t) is None: return
            explicar(db, t, tx, seco=seco); return
        if cmd == "marcar":
            if ver(db, t) is None: return
            marcar(db, t, opt("--prioridad"), (opt("--toca-numeros") or "").lower(), (opt("--escribe-en-base") or "").lower(),
                   (opt("--bloquea-entrega") or "no").lower(), opt("--razon"), seco=seco); return
        if cmd == "cerrar":
            ev = opt("--evidencia")
            if not ev or "\n" in ev or not (EVIDENCIA.search(ev) or EVIDENCIA_PROPIO.match(ev)):
                sys.exit("--evidencia es obligatoria, en UNA linea, con el build (b72) o el commit; "
                         "en un propio tambien «archivo: …», «correo: …» o «enlace: …»")
            if ver(db, t) is None: return
            mover(db, t, "cerrado", nota=ev, build=opt("--build"), cierre=opt("--cierre"), seco=seco)
            return
        sys.exit("comando desconocido: %s" % cmd)


if __name__ == "__main__":
    main()
