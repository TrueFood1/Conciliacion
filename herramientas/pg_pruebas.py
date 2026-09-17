#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pg_pruebas.py — correr las pruebas de Truefie contra la base, en transacciones
que SIEMPRE terminan en rollback.

POR QUE EXISTE
  Hasta hoy las pruebas se pegaban a mano en el editor de SQL, una por una. Eso
  tiene dos problemas y el segundo es el grave:
    1. son diez bloques y pegarlos cansa, y lo que cansa se saltea;
    2. el editor entra como `postgres`, que SALTEA LA RLS. El 16-sep D8 paso en
       verde sin ejercitar `acceso_es_socia()` ni una vez. Una prueba de
       permisos corrida con la llave maestra no prueba permisos.

LOS DOS CARRILES, Y CADA PRUEBA DICE CON CUAL CORRE
  A · llave maestra. El rol `truefie_pruebas` tiene `bypassrls`, asi que la RLS
      no le aplica. Prueba reglas de CONTENIDO: candados, constraints, triggers.
  B · como usuario real. El MISMO rol que, ya adentro del sobre, hace
      `set local role authenticated` y se pone encima los claims de una persona.
      Ahi la RLS SI aplica. Prueba reglas de PERMISO.

  El carril sale del encabezado de cada archivo (`-- PRUEBA D5 · CARRIL A`). Si
  un archivo no lo dice, NO SE CORRE: una prueba que no declara su carril falla
  por el motivo de al lado y nadie se entera.

🔴 LA PRUEBA CERO VA PRIMERA Y ES UN CANDADO, NO UNA PRUEBA MAS
  `b0.sql` comprueba que el carril B EXISTA — que `set local role` de verdad
  apague el bypass. Si un select sobre `acceso_usuario` devuelve 6 filas en vez
  de 1, el bypass sigue puesto y NINGUNA prueba de permiso significa nada. En
  ese caso esta herramienta PARA y no corre nada mas. Es el fracaso de D8
  mudado al lugar nuevo, y la unica defensa es medirlo antes de empezar.

LOS CANDADOS DE LA ENTRADA
  1. Deny-by-default sobre palabras: `begin`, `commit`, `rollback`, `savepoint`,
     `release`, `set`, `set_config`, `reset`, `call`, `do`. Se revisa DESPUES de
     sacar comentarios y literales de texto, para no rechazar una prueba solo
     porque la palabra aparece adentro de un string.
     ⚠️ EL CASO QUE MOTIVO ESTO: `CAMBIO_DEVOLUCIONES.sql` tiene un `commit;`
     embebido (linea 533). Un `commit` a mitad del sobre lo ROMPE: lo que venga
     despues queda escrito en produccion. Se detecta ACA y no se manda.
  2. El sobre y la identidad los emite la herramienta, nunca la prueba. Por eso
     `set` esta prohibido en la entrada aunque el sobre lo use: si una prueba
     pudiera elegir con que identidad corre, el carril B no probaria nada.

UNA PRUEBA POR TRANSACCION, Y EL ROLLBACK VA EN SU PROPIO MENSAJE
  ⚠️ Esto no es un detalle de estilo. En el protocolo simple de Postgres, si un
  mensaje trae varias sentencias y una falla, EL RESTO DEL MENSAJE NO SE
  EJECUTA. O sea que mandar `begin; <prueba>; rollback;` junto significa que
  cuando la prueba falla —que es lo que ESPERAN siete de las diez— el
  `rollback` nunca corre. Por eso van tres mensajes separados: abrir, probar,
  cerrar. El cierre va en un `finally`, siempre.

  Y como varias pruebas terminan en error a proposito, cada una necesita su
  propia transaccion: un statement que falla aborta todo lo que sigue (25P02).

SE DISTINGUE "SE CORTO LA CONEXION" DE "LA PRUEBA FALLO"
  · La prueba fallo   → el servidor contesto un ErrorResponse con su SQLSTATE.
                        Eso es un RESULTADO, y en siete de diez es el esperado.
  · Se corto          → el socket murio, o salto
                        `idle_in_transaction_session_timeout`. No hay resultado
                        de nada, y lo que se haya medido antes no es confiable.
                        Se dice con todas las letras y se para.

🔴 IMPRIME LA SALIDA CRUDA
  Esta herramienta NO dice "pasó" ni "falló" ni "9/9 en verde". Imprime lo que
  el servidor contesto: las filas, los SQLSTATE, el DETAIL, el HINT, y el
  estado de la transaccion que informa cada ReadyForQuery. Un marcador verde
  esconde justo lo que hace que Andrea encuentre cosas.

USO
    python3 herramientas/pg_pruebas.py --clave
    python3 herramientas/pg_pruebas.py --clave --solo d5
    python3 herramientas/pg_pruebas.py --clave --identidad socia --solo d8
    python3 herramientas/pg_pruebas.py --clave --plan-b        (ver abajo)

LA CLAVE
  Sale de `conexion_db.env`, al lado de este script, de la llave
  `PRUEBAS_ROL_PASSWORD`. Nunca como argumento (no sale en `ps`), nunca en el
  historial del shell, nunca impresa.

EL POOLER, Y EL PLAN B
  `pg_lector.py` entra como `postgres.<ref>`; este entra como
  `truefie_pruebas.<ref>`. Supavisor deberia aceptar un rol propio, pero eso no
  se probo nunca en este proyecto. Si rechaza la conexion, la herramienta lo
  dice y NO se cae sola a otra cosa: hay que volver a correrla con `--plan-b`,
  que entra como `postgres` y hace `set local role truefie_pruebas` adentro del
  sobre. Funciona igual, pero la contencion queda una capa mas fina, y eso
  tiene que ser una decision escrita y no un silencio.
"""

import os
import re
import sys

_AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_AQUI, "respaldo"))
from probar_conexion import (                      # noqa: E402
    abrir, paquete, leer_mensaje, REF, HOST, PUERTO, BASE,
)

ARCHIVO_CLAVE = os.path.join(_AQUI, "conexion_db.env")
PRUEBAS       = os.path.join(os.path.dirname(_AQUI), "pruebas_h3")

ROL      = "truefie_pruebas"
USUARIO  = ROL + "." + REF
USUARIO_MAESTRO = "postgres." + REF

# Candado 1. Deny-by-default.
PROHIBIDO = re.compile(
    r"(?i)(?<![a-z_])(begin|commit|rollback|savepoint|release|set|set_config|reset|call|do)(?![a-z_])")

# El orden importa: b0 primero, siempre.
ORDEN = ["b0", "d0", "d1", "d2", "d3", "d3_bis", "d4", "d5", "d6", "d7",
         "d8", "d9_anulacion"]


# ══════════════════════════════════════════════════════════════════════════
# LA CLAVE
# ══════════════════════════════════════════════════════════════════════════
def _claves(path=ARCHIVO_CLAVE):
    """Todas las llaves del .env. Mismo parseo que pg_lector."""
    d = {}
    if not os.path.exists(path):
        return d
    for linea in open(path, encoding="utf-8"):
        linea = linea.strip()
        if not linea or linea.startswith("#") or "=" not in linea:
            continue
        k, v = linea.split("=", 1)
        d[k.strip()] = v.strip()
    return d


# ══════════════════════════════════════════════════════════════════════════
# CANDADO 1 · revisar la entrada ANTES de mandarla
# ══════════════════════════════════════════════════════════════════════════
def _desnudar(sql):
    """Saca comentarios y literales para que la revision mire solo el codigo.

    Una prueba puede decir 'prueba-d0 set' adentro de un string y eso no es
    control de transaccion. Rechazarla seria un falso positivo, y un porton que
    da falsos positivos se termina apagando.
    """
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)     # comentarios de bloque
    sql = re.sub(r"--[^\n]*", " ", sql)                  # comentarios de linea
    sql = re.sub(r"\$([A-Za-z_]*)\$.*?\$\1\$", " '' ", sql, flags=re.S)
    sql = re.sub(r"'(?:[^']|'')*'", " '' ", sql, flags=re.S)
    return sql


def revisar(sql):
    """None si pasa, o el motivo del rechazo."""
    limpio = _desnudar(sql)
    if not limpio.strip():
        return "el archivo no tiene una sola sentencia"
    hits = sorted(set(m.group(1).lower() for m in PROHIBIDO.finditer(limpio)))
    if hits:
        extra = ""
        if "commit" in hits:
            extra = ("  ⚠️ UN `commit` EMBEBIDO ROMPE EL SOBRE: lo que venga "
                     "despues queda ESCRITO en produccion. Por esto existe "
                     "este candado.")
        return ("trae %s, y el SQL de entrada no puede traer control de "
                "transaccion ni cambiar quien corre. El sobre y la identidad "
                "son de la herramienta.%s" % (", ".join(hits), extra))
    return None


def carril_de(texto, nombre):
    m = re.search(r"--\s*PRUEBA\s+\S+\s+·\s+CARRIL\s+([AB])", texto)
    if not m:
        return None, ("%s no declara su carril. Una prueba que no dice con cual "
                      "corre falla por el motivo de al lado y nadie se entera."
                      % nombre)
    return m.group(1), None


# ══════════════════════════════════════════════════════════════════════════
# LA CONEXION
# ══════════════════════════════════════════════════════════════════════════
class ConexionCortada(Exception):
    """El socket murio. NO es que una prueba fallara: no hay resultado."""


def _campos_error(cuerpo):
    """TODOS los campos del ErrorResponse, no solo tres. Salida cruda."""
    campos, pos = {}, 0
    while pos < len(cuerpo) and cuerpo[pos:pos + 1] != b"\x00":
        cod = cuerpo[pos:pos + 1].decode("ascii", "replace")
        fin = cuerpo.index(b"\x00", pos + 1)
        campos[cod] = cuerpo[pos + 1:fin].decode("utf-8", "replace")
        pos = fin + 1
    return campos


NOMBRE_CAMPO = {"S": "sev", "C": "sqlstate", "M": "mensaje", "D": "DETAIL",
                "H": "HINT", "n": "constraint", "t": "tabla", "c": "columna"}


class Sesion:
    def __init__(self, usuario, clave):
        self.usuario = usuario
        s, fallo = abrir(HOST, PUERTO, usuario, BASE, clave)
        if fallo:
            raise ConnectionError(fallo)
        self.s = s
        self._drenar()

    def _drenar(self):
        while True:
            tipo, cuerpo = leer_mensaje(self.s)
            if tipo == b"Z":
                return cuerpo[:1].decode("ascii", "replace")
            if tipo == b"E":
                c = _campos_error(cuerpo)
                raise RuntimeError("%s %s: %s" % (c.get("S"), c.get("C"), c.get("M")))

    def consulta(self, sql):
        """Manda UN mensaje y devuelve todo lo que contesto el servidor.

        Devuelve (eventos, estado_tx). `eventos` es la lista cruda, en orden:
          ('filas', columnas, filas) · ('error', campos) · ('aviso', campos)
          ('ok', 'INSERT 0 1')
        `estado_tx` es el byte del ReadyForQuery: I libre · T en transaccion ·
        E transaccion abortada. Ese byte es evidencia: despues de una prueba
        que tiene que fallar, tiene que decir E.
        """
        try:
            self.s.sendall(paquete(b"Q", sql.encode("utf-8") + b"\x00"))
        except OSError as e:
            raise ConexionCortada(str(e))

        eventos, cols, filas = [], None, []
        while True:
            try:
                tipo, cuerpo = leer_mensaje(self.s)
            except (OSError, ValueError, IndexError) as e:
                raise ConexionCortada("%s: %s" % (type(e).__name__, e))
            if tipo is None or tipo == b"":
                raise ConexionCortada("el servidor cerro la conexion sin contestar")

            if tipo == b"T":
                import struct
                n = struct.unpack("!H", cuerpo[:2])[0]
                cols, pos = [], 2
                for _ in range(n):
                    fin = cuerpo.index(b"\x00", pos)
                    cols.append(cuerpo[pos:fin].decode("utf-8", "replace"))
                    pos = fin + 1 + 18
                filas = []
            elif tipo == b"D":
                import struct
                n = struct.unpack("!H", cuerpo[:2])[0]
                fila, pos = [], 2
                for _ in range(n):
                    largo = struct.unpack("!i", cuerpo[pos:pos + 4])[0]
                    pos += 4
                    if largo == -1:
                        fila.append(None)
                    else:
                        fila.append(cuerpo[pos:pos + largo].decode("utf-8", "replace"))
                        pos += largo
                filas.append(fila)
            elif tipo == b"C":
                etiqueta = cuerpo.rstrip(b"\x00").decode("utf-8", "replace")
                if cols is not None:
                    eventos.append(("filas", cols, filas))
                else:
                    eventos.append(("ok", etiqueta))
                cols, filas = None, []
            elif tipo == b"E":
                eventos.append(("error", _campos_error(cuerpo)))
            elif tipo == b"N":
                eventos.append(("aviso", _campos_error(cuerpo)))
            elif tipo == b"Z":
                return eventos, cuerpo[:1].decode("ascii", "replace")

    def cerrar(self):
        try:
            self.s.sendall(paquete(b"X", b""))
            self.s.close()
        except Exception:
            pass


# ══════════════════════════════════════════════════════════════════════════
# EL SOBRE · lo emite la herramienta, nunca la prueba
# ══════════════════════════════════════════════════════════════════════════
def _lit(s):
    """Un literal de SQL, con las comillas escapadas."""
    return "'" + str(s).replace("'", "''") + "'"


def sobre_abrir(carril, email, plan_b):
    """El `begin` y la identidad. Devuelve (sql, descripcion_para_imprimir)."""
    lineas = ["begin;", "set local statement_timeout = '15s';"]
    if carril == "A":
        if plan_b:
            lineas.append("set local role %s;" % ROL)
        quien = "%s%s · bypassrls, la RLS no aplica" % (
            ROL, " (via set local role)" if plan_b else "")
    else:
        claims = '{"email": %s, "role": "authenticated"}' % ('"%s"' % email)
        lineas.append("set local request.jwt.claims = %s;" % _lit(claims))
        lineas.append("set local role authenticated;")
        quien = "authenticated · claims email=%s · la RLS SI aplica" % email
    return "\n".join(lineas), quien


# ══════════════════════════════════════════════════════════════════════════
# IMPRIMIR · crudo. Sin marcadores, sin verdictos.
# ══════════════════════════════════════════════════════════════════════════
def _tabla(cols, filas):
    if not cols:
        return ["(sin columnas)"]
    anchos = [len(c) for c in cols]
    for f in filas:
        for i, v in enumerate(f):
            anchos[i] = max(anchos[i], len("NULL" if v is None else str(v)))
    anchos = [min(a, 60) for a in anchos]
    out = ["  " + " | ".join(c.ljust(anchos[i])[:anchos[i]] for i, c in enumerate(cols)),
           "  " + "-+-".join("-" * a for a in anchos)]
    for f in filas:
        out.append("  " + " | ".join(
            ("NULL" if v is None else str(v)).ljust(anchos[i])[:anchos[i]]
            for i, v in enumerate(f)))
    out.append("  (%d fila%s)" % (len(filas), "" if len(filas) == 1 else "s"))
    return out


def imprimir(eventos, estado):
    for ev in eventos:
        if ev[0] == "filas":
            for l in _tabla(ev[1], ev[2]):
                print(l)
        elif ev[0] == "ok":
            print("  %s" % ev[1])
        elif ev[0] in ("error", "aviso"):
            c = ev[1]
            cab = "  ── %s del servidor ──" % ("ERROR" if ev[0] == "error" else "AVISO")
            print(cab)
            for cod, nombre in NOMBRE_CAMPO.items():
                if cod in c:
                    print("     %-11s %s" % (nombre + ":", c[cod]))
    print("  [ReadyForQuery] estado de la transaccion: %s   (%s)" % (
        estado, {"I": "libre", "T": "abierta", "E": "ABORTADA"}.get(estado, "?")))


# ══════════════════════════════════════════════════════════════════════════
# CORRER UNA PRUEBA
# ══════════════════════════════════════════════════════════════════════════
def correr(ses, nombre, sql, carril, email, plan_b):
    """Abre, prueba, y cierra SIEMPRE. Devuelve los eventos de la prueba."""
    abrir_sql, quien = sobre_abrir(carril, email, plan_b)

    print()
    print("═" * 74)
    print("PRUEBA %s · CARRIL %s" % (nombre.upper(), carril))
    print("  corre como: %s" % quien)
    print("═" * 74)

    ev_abrir, est = ses.consulta(abrir_sql)
    if any(e[0] == "error" for e in ev_abrir):
        print("  el SOBRE no abrio — esto no es un resultado de la prueba:")
        imprimir(ev_abrir, est)
        try:
            ses.consulta("rollback;")
        except ConexionCortada:
            pass
        return None

    try:
        eventos, estado = ses.consulta(sql)
        imprimir(eventos, estado)
        return eventos
    finally:
        # ⚠️ EN SU PROPIO MENSAJE, SIEMPRE. Si la prueba fallo, el resto del
        # mensaje anterior no se ejecuto: el rollback tiene que ir aparte o la
        # transaccion queda abierta y el `idle_in_transaction` termina matando
        # la conexion a mitad de la corrida.
        try:
            _, est_fin = ses.consulta("rollback;")
            print("  [rollback] estado despues: %s" % est_fin)
        except ConexionCortada as e:
            print("  ⚠️ no se pudo cerrar la transaccion: %s" % e)
            raise


# ══════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════
def main():
    args = sys.argv[1:]
    if "--clave" not in args:
        print(__doc__)
        return 2
    plan_b = "--plan-b" in args
    solo = None
    if "--solo" in args:
        solo = args[args.index("--solo") + 1]
    identidad = "equipo"
    if "--identidad" in args:
        identidad = args[args.index("--identidad") + 1]

    claves = _claves()
    llave = "SUPABASE_DB_PASSWORD" if plan_b else "PRUEBAS_ROL_PASSWORD"
    clave = claves.get(llave)
    if not clave:
        print("✗ falta %s en conexion_db.env" % llave)
        return 1
    usuario = USUARIO_MAESTRO if plan_b else USUARIO
    print("clave leida del archivo: %d caracteres (no se imprime)" % len(clave))

    # ── LA PRIMERA CONEXION · aca se sabe lo del pooler ──────────────────
    try:
        ses = Sesion(usuario, clave)
    except ConnectionError as e:
        print()
        print("✗ NO SE PUDO CONECTAR COMO %s" % usuario)
        print("   %s" % e)
        if not plan_b:
            print()
            print("   Si el pooler rechaza el rol propio, el plan B es entrar como")
            print("   `postgres` y hacer `set local role %s` adentro del sobre." % ROL)
            print("   NO se cae solo a eso: la contencion queda una capa mas fina y")
            print("   esa tiene que ser una decision escrita. Volve a correr con:")
            print("       python3 herramientas/pg_pruebas.py --clave --plan-b")
        return 1
    print("✅ conectado como %s%s" % (usuario, "   [PLAN B]" if plan_b else ""))

    # ── LAS IDENTIDADES · salen de la BASE, no del repo ──────────────────
    # Asi ningun correo queda escrito en un repo publico ni pasa por argv.
    ev, _ = ses.consulta(
        "select nombre, email, perfil from v_acceso_usuario "
        "where activo and (nombre = 'PRUEBAS-H3' or perfil = 'socias') "
        "order by (perfil = 'socias'), email;")
    gente = {}
    for e in ev:
        if e[0] == "filas":
            for fila in e[2]:
                gente["equipo" if fila[0] == "PRUEBAS-H3" else "socia"] = fila[1]
    if "equipo" not in gente:
        print("✗ no encuentro al usuario PRUEBAS-H3 en v_acceso_usuario.")
        ses.cerrar()
        return 1
    email = gente.get(identidad)
    if not email:
        print("✗ no hay identidad %r. Hay: %s" % (identidad, ", ".join(sorted(gente))))
        ses.cerrar()
        return 1
    print("identidad del carril B: %s → %s" % (identidad, email))

    # ── CARGAR LOS ARCHIVOS Y REVISARLOS ANTES DE MANDAR NADA ────────────
    lista = []
    for n in ORDEN:
        ruta = os.path.join(PRUEBAS, n + ".sql")
        if not os.path.exists(ruta):
            print("✗ falta %s" % ruta)
            ses.cerrar()
            return 1
        txt = open(ruta, encoding="utf-8").read()
        carril, fallo = carril_de(txt, n)
        if fallo:
            print("✗ %s" % fallo)
            ses.cerrar()
            return 1
        motivo = revisar(txt)
        if motivo:
            print("✗ %s RECHAZADA ANTES DE ENVIAR: %s" % (n, motivo))
            ses.cerrar()
            return 1
        lista.append((n, txt, carril))
    print("candado 1: %d archivos revisados, ninguno trae control de transaccion" % len(lista))

    # ── 🔴 LA PRUEBA CERO · si no da 1, se para ──────────────────────────
    if solo is None:
        n, txt, carril = lista[0]
        assert n == "b0" and carril == "B"
        try:
            eventos = correr(ses, n, txt, carril, gente["equipo"], plan_b)
        except ConexionCortada as e:
            print("\n🔴 SE CORTO LA CONEXION durante la prueba cero: %s" % e)
            return 1
        visible = None
        for e in (eventos or []):
            if e[0] == "filas" and e[2]:
                visible = e[2][0][0]
                break
        print()
        if visible != "1":
            print("🔴 PARA ACA. La prueba cero devolvio %r y tenia que devolver '1'." % visible)
            print("   El carril B NO esta apagando el bypass de la RLS, asi que")
            print("   NINGUNA prueba de permiso significaria nada: pasarian todas en")
            print("   verde sin ejercitar una sola politica. Es el fracaso de D8 del")
            print("   16-sep en el lugar nuevo.")
            print("   No se corre nada mas.")
            ses.cerrar()
            return 1
        print("   la prueba cero devolvio 1: el carril B apaga el bypass. Sigo.")
        lista = lista[1:]

    if solo:
        lista = [x for x in lista if x[0] == solo]
        if not lista:
            print("✗ no hay una prueba %r" % solo)
            ses.cerrar()
            return 1

    # ── EL RESTO ─────────────────────────────────────────────────────────
    corridas = 0
    try:
        for n, txt, carril in lista:
            correr(ses, n, txt, carril, email, plan_b)
            corridas += 1
    except ConexionCortada as e:
        print()
        print("🔴 SE CORTO LA CONEXION — esto NO es que una prueba fallara.")
        print("   %s" % e)
        print("   Puede ser el `idle_in_transaction_session_timeout` de 30s, o la red.")
        print("   Lo medido hasta acá vale; lo de después no se midió.")
        print("   Corridas antes del corte: %d" % corridas)
        return 1
    finally:
        ses.cerrar()

    print()
    print("═" * 74)
    print("se corrieron %d prueba(s). Arriba esta lo que contesto el servidor," % corridas)
    print("crudo. Esta herramienta no dice si esta bien: eso se lee.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
