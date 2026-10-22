#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
listo.py — el cierre CORTO de una sesión (/listo; protocolo de cierre, Andrea 21-oct-2026).

Cada sesión lo corre al terminar SU tarea. Hace, en orden, y para en el primer ✗:
  1. el turno: lo toma con su origen (si otra sesión está cerrando, espera: salida 3);
  2. nada sin commitear en cada repo que tocó (lo no rastreado se avisa, no frena);
  3. push de SU rama, con nombre explícito (nunca `main`: eso es de una socia), y lo comprueba en GitHub;
  4. los tickets que tocó llevan hoy su línea «Origen: chat «…»» (si no, frena: anotarla y volver);
  5. una entrada en la BITACORA: origen, hora, repo, rama, commit, tickets, pendiente y decisión;
  6. suelta el turno.
NO escribe el ESTADO ni corre el cierre del día (/cierre-dia).

    python3 listo.py --origen "Retomar 21-oct" --repo Conciliacion --repo truefie-escritura \\
        --tickets 256,187 --hecho "…" --pendiente "…" --decision "…" [--seco] [--bitacora RUTA]
`--repo` es una carpeta (relativa a Practica CC o absoluta): la compartida o el worktree de la sesión.
`--seco` revisa todo y muestra la entrada, sin push, sin bitácora y sin tocar el turno.
"""
import os, re, subprocess, sys, time

PRACTICA = "/Users/andrea/Desktop/Practica CC"
BITACORA = os.path.join(PRACTICA, "Conciliacion", "BITACORA.md")
AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import turno                                                     # noqa: E402


def _args(nombre):
    return [sys.argv[i + 1] for i, a in enumerate(sys.argv) if a == nombre and i + 1 < len(sys.argv)]


def _arg(nombre, defecto=None):
    v = _args(nombre)
    return v[-1] if v else defecto


def git(repo, *a):
    r = subprocess.run(["git", "-C", repo] + list(a), capture_output=True, text=True)
    return r.returncode, (r.stdout or "").strip(), (r.stderr or "").strip()


def revisar_repo(repo, seco):
    """{repo, rama, commit, push} o sale con el motivo del ✗."""
    nombre = os.path.basename(repo.rstrip("/"))
    _, rama, _ = git(repo, "branch", "--show-current")
    _, sucio, _ = git(repo, "status", "--porcelain")
    cambios = [l for l in sucio.splitlines() if not l.startswith("??")]
    nuevos = [l[3:] for l in sucio.splitlines() if l.startswith("??")]
    if cambios:
        sys.exit("✗ %s: hay cambios sin commitear:\n   %s\n  Commitealos (o descartalos con criterio) y volvé a correr /listo."
                 % (nombre, "\n   ".join(cambios[:10])))
    if nuevos:
        print("  · %s: archivos sin rastrear (no frena, pero mirá si alguno debía ir): %s" % (nombre, ", ".join(nuevos[:6])))
    if not rama:
        sys.exit("✗ %s: no está en ninguna rama (HEAD suelto)." % nombre)
    _, head, _ = git(repo, "rev-parse", "HEAD")
    if rama == "main":
        sys.exit("✗ %s: estás en main. /listo nunca empuja main: publicar es de una socia. Pasá tu trabajo a tu rama." % nombre)
    if seco:
        _, rem, _ = git(repo, "ls-remote", "origin", "refs/heads/" + rama)
        return {"repo": nombre, "rama": rama, "commit": head[:7],
                "push": "ya en GitHub" if rem[:40] == head else "SE SUBIRÍA (seco)"}
    c, _, err = git(repo, "push", "-q", "origin", "HEAD:refs/heads/" + rama)
    if c:
        sys.exit("✗ %s: el push de %s falló: %s" % (nombre, rama, err[-300:]))
    _, rem, _ = git(repo, "ls-remote", "origin", "refs/heads/" + rama)
    if rem[:40] != head:
        sys.exit("✗ %s: GitHub tiene %s en %s y el local %s: no coincide." % (nombre, rem[:7], rama, head[:7]))
    return {"repo": nombre, "rama": rama, "commit": head[:7], "push": "en GitHub ✓"}


def revisar_tickets(ids, origen):
    """Cada ticket tiene HOY una línea con su origen (o la trae en la descripción). {id: True/False}."""
    if not ids:
        return {}
    sys.path.insert(0, os.path.join(PRACTICA, "Conciliacion", "herramientas"))
    from pg_lector import Lector, clave
    hoy = time.strftime("%Y-%m-%d")
    lista = ",".join(str(int(i)) for i in ids)
    with Lector(clave()[0]) as db:
        _, d = db.consulta("select ticket_id, texto from ticket_detalle where ticket_id in (%s) "
                           "and (creado_en at time zone 'America/Costa_Rica')::date = '%s'" % (lista, hoy))
        _, t = db.consulta("select id, descripcion, (creado_en at time zone 'America/Costa_Rica')::date::text "
                           "from ticket where id in (%s)" % lista)
    aguja = "chat «%s»" % origen
    ok = {int(i): False for i in ids}
    for tid, texto in d:
        if aguja in (texto or ""):
            ok[int(tid)] = True
    for tid, desc, creado in t:
        if aguja in (desc or "") and creado == hoy:
            ok[int(tid)] = True
    return ok


def entrada(origen, repos, tickets, hecho, pendiente, decision):
    h = ["## ✅ LISTO · %s · chat «%s»" % (time.strftime("%Y-%m-%d %H:%M"), origen)]
    for r in repos:
        h.append("- **%s** · rama `%s` · commit `%s` · %s" % (r["repo"], r["rama"], r["commit"], r["push"]))
    h.append("- Tickets: %s" % (", ".join("T-%d" % t for t in tickets) if tickets else "ninguno"))
    h.append("- Hecho: %s" % (hecho or "—"))
    h.append("- Pendiente: %s" % (pendiente or "nada"))
    h.append("- Espera a una socia: %s" % (decision or "nada"))
    return "\n".join(h) + "\n"


def escribir_bitacora(ruta, texto):
    """Debajo del encabezado y ARRIBA de los bloques: lo más nuevo, primero. El /cierre-dia las junta."""
    viejo = open(ruta, encoding="utf-8").read()
    m = re.search(r"(?m)^---\s*$", viejo)
    corte = m.end() if m else 0
    open(ruta, "w", encoding="utf-8").write(viejo[:corte] + "\n\n" + texto.rstrip("\n") + "\n\n" + viejo[corte:].lstrip("\n"))


if __name__ == "__main__":
    origen = _arg("--origen")
    repos = [r if os.path.isabs(r) else os.path.join(PRACTICA, r) for r in _args("--repo")]
    if not origen or not repos:
        print(__doc__); sys.exit(2)
    seco = "--seco" in sys.argv
    tickets = [int(x.strip().lstrip("Tt-")) for x in (_arg("--tickets") or "").split(",") if x.strip()]
    if not seco:
        c = turno.tomar(_arg("--turno", turno.ARCHIVO), origen, "listo")
        if c:
            sys.exit(c)
    try:
        print("1 · repos")
        hechos = [revisar_repo(r, seco) for r in repos]
        for x in hechos:
            print("  ✓ %s · %s · %s · %s" % (x["repo"], x["rama"], x["commit"], x["push"]))
        print("2 · tickets")
        ok = revisar_tickets(tickets, origen)
        for t, v in ok.items():
            print("  %s T-%d %s" % ("✓" if v else "✗", t, "tiene hoy su línea de origen" if v else
                                    "NO tiene hoy la línea «Origen: chat «%s»»" % origen))
        if not all(ok.values()):
            sys.exit("✗ anotá el origen en esos tickets (tk_estado.py anunciar <n> --texto \"Origen: chat «%s» · …\") y volvé a correr /listo." % origen)
        txt = entrada(origen, hechos, tickets, _arg("--hecho"), _arg("--pendiente"), _arg("--decision"))
        print("3 · bitácora%s\n" % (" (seco: NO se escribe)" if seco else "") + txt)
        if not seco:
            escribir_bitacora(_arg("--bitacora", BITACORA), txt)
            print("  ✓ escrita en %s" % _arg("--bitacora", BITACORA))
    finally:
        if not seco:
            turno.soltar(_arg("--turno", turno.ARCHIVO), origen)
