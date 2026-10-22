#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
cierre_dia.py — el cierre del DÍA (/cierre-dia; protocolo de cierre, decisión de Andrea 21-oct-2026).

Lo corre UNA sola sesión, cuando Andrea lo pide. Solo LEE (git fetch, git, tickets con pg_lector) y
escribe UN archivo local: respaldo-truefie/trabajo/cierres/CIERRE_DIA_<fecha>.md, con un bloque corto
al final para pegar en el chat de Claude.ai. NO escribe el ESTADO (eso lo hace Claude.ai con el bloque
y los chats del día), NO commitea, NO cierra tickets (propone; Andrea aprueba en un mensaje).

Cubre desde el último cierre: el último CIERRE_DIA_*.md, o si no hay, el último «DÓNDE QUEDAMOS» de
la bitácora. Si un día quedó sin cierre, entra solo.

    python3 cierre_dia.py [--desde 2026-10-21] [--hasta 2026-10-22] [--salida RUTA] [--sin-fetch]
"""
import glob, hashlib, json, os, re, subprocess, sys, time
from collections import OrderedDict

PRACTICA = "/Users/andrea/Desktop/Practica CC"
REPOS = OrderedDict([("Conciliacion", os.path.join(PRACTICA, "Conciliacion")),
                     ("truefie-escritura", os.path.join(PRACTICA, "truefie-escritura")),
                     ("respaldo-truefie", os.path.join(PRACTICA, "respaldo-truefie")),
                     ("proxy de lectura", os.path.join(PRACTICA, "Conciliacion", "proxy_lectura"))])
BITACORA = os.path.join(PRACTICA, "Conciliacion", "BITACORA.md")
BITACORA_RESPALDO = os.path.join(PRACTICA, "respaldo-truefie", "trabajo", "BITACORA.md")
CIERRES = os.path.join(PRACTICA, "respaldo-truefie", "trabajo", "cierres")
SKILLS_VIVAS = os.path.join(PRACTICA, ".claude", "skills")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "listo"))
import turno                                                     # noqa: E402

RX_ORIGEN = re.compile(r"Origen: chat «([^»]+)»")
RX_EVIDENCIA = re.compile(r"\bb1\d\d\b|\b[0-9a-f]{7}\b|https?://\S+|archivo: |correo: ")
RX_FALTA = re.compile(r"\bFalta[n]?\b|PENDIENTE|sin publicar|NO se (?:corrió|aplicó|publicó)|no publicado", re.I)
RX_LISTO = re.compile(r"VERIFICADO|APLICAD[OA]|PUBLICAD[OA]|Arreglado|Cerrado|resuelto", re.I)


def _arg(n, d=None):
    return sys.argv[sys.argv.index(n) + 1] if n in sys.argv else d


def git(repo, *a):
    r = subprocess.run(["git", "-C", repo] + list(a), capture_output=True, text=True)
    return (r.stdout or "").strip() if r.returncode == 0 else ""


def sha(path_o_texto, es_texto=False):
    b = path_o_texto.encode() if es_texto else open(path_o_texto, "rb").read()
    return hashlib.sha256(b).hexdigest()[:12]


def desde_por_defecto(hasta):
    hechos = sorted(f for f in glob.glob(os.path.join(CIERRES, "CIERRE_DIA_*.md")) if hasta not in os.path.basename(f))
    if hechos:
        ult = re.search(r"(\d{4}-\d{2}-\d{2})", hechos[-1]).group(1)
        fuente = "último cierre del día (%s)" % os.path.basename(hechos[-1])
    else:
        m = re.search(r"# 📍 DÓNDE QUEDAMOS — (\d{4}-\d{2}-\d{2})", open(BITACORA, encoding="utf-8").read())
        ult, fuente = m.group(1), "último /cierre de la bitácora (%s)" % m.group(1)
    t = time.mktime(time.strptime(ult, "%Y-%m-%d")) + 86400 * 1.5
    return time.strftime("%Y-%m-%d", time.localtime(t)), fuente


def repo_info(nombre, repo, desde, fetch):
    if not os.path.isdir(os.path.join(repo, ".git")) and not os.path.isfile(os.path.join(repo, ".git")):
        return {"nombre": nombre, "falta": True}
    if fetch:
        subprocess.run(["git", "-C", repo, "fetch", "-q", "--prune", "origin"], capture_output=True)
    out = {"nombre": nombre, "commits": OrderedDict(), "sin_push": [], "worktrees": [], "sucio": [], "ramas": {}}
    vistos = set()
    for l in git(repo, "log", "--all", "--since=%s 00:00" % desde, "--date=format:%d-%m %H:%M",
                 "--format=%H\t%h\t%ad\t%an\t%s\t%S").splitlines():
        h, c, f, a, s, ref = (l.split("\t") + [""] * 6)[:6]
        if h in vistos or ref.startswith("refs/stash"):
            continue
        vistos.add(h)
        rama = re.sub(r"^refs/(remotes/origin/|heads/)", "", ref)
        if rama in ("HEAD", ""):
            rama = git(repo, "branch", "--show-current") or "HEAD"
        out["commits"].setdefault(rama, []).append("%s %s · %s · %s" % (c, f, a, s[:90]))
    viejas = 0
    for l in git(repo, "for-each-ref", "refs/heads", "--format=%(refname:short)").splitlines():
        if git(repo, "log", "-1", "--format=%cd", "--date=format:%Y-%m-%d", "refs/heads/" + l) < desde:
            viejas += (not git(repo, "rev-parse", "-q", "--verify", "refs/remotes/origin/" + l)) or \
                git(repo, "rev-list", "--count", "refs/remotes/origin/%s..refs/heads/%s" % (l, l)) not in ("", "0")
            continue
        rem = git(repo, "rev-parse", "-q", "--verify", "refs/remotes/origin/" + l)
        if not rem:
            out["sin_push"].append("%s (solo local)" % l)
        else:
            n = git(repo, "rev-list", "--count", "refs/remotes/origin/%s..refs/heads/%s" % (l, l))
            if n and n != "0":
                out["sin_push"].append("%s (%s commit%s sin subir)" % (l, n, "" if n == "1" else "s"))
    out["viejas_sin_push"] = int(viejas)
    wt = git(repo, "worktree", "list", "--porcelain").split("\n\n")
    for bloque in wt:
        d = dict((x.split(" ", 1) + [""])[:2] for x in bloque.splitlines() if x)
        if not d.get("worktree"):
            continue
        p = d["worktree"]
        rama = d.get("branch", "").replace("refs/heads/", "") or "(suelto)"
        st = git(p, "status", "--porcelain") if os.path.isdir(p) else ""
        mod = [x for x in st.splitlines() if not x.startswith("??")]
        nue = [x for x in st.splitlines() if x.startswith("??")]
        out["worktrees"].append({"ruta": p, "rama": rama, "prunable": "prunable" in d, "principal": p == repo})
        if mod or nue:
            out["sucio"].append("%s [%s]: %d cambiado(s), %d sin rastrear%s" % (
                "carpeta compartida" if p == repo else p, rama, len(mod), len(nue),
                (" — " + ", ".join(x[3:] for x in mod[:4])) if mod else ""))
    for r in ("main", "dev"):
        loc, rem = git(repo, "rev-parse", "--short", "refs/heads/" + r), git(repo, "rev-parse", "--short", "refs/remotes/origin/" + r)
        if loc or rem:
            out["ramas"][r] = (loc or "—", rem or "—")
    return out


def builds(repo):
    pub = git(repo, "show", "refs/remotes/origin/main:index.html")
    m = re.search(r"const BUILD = '[^']*?b(\d+)", pub)
    nums = []
    for ref in git(repo, "for-each-ref", "refs/remotes/origin", "--format=%(refname)").splitlines():
        t = re.search(r"const BUILD = '[^']*?b(\d+)", git(repo, "show", ref + ":index.html"))
        if t:
            nums.append((int(t.group(1)), ref.replace("refs/remotes/origin/", "")))
    usado = max(nums) if nums else (0, "")
    return (int(m.group(1)) if m else None), usado, usado[0] + 1


def tickets(desde):
    sys.path.insert(0, os.path.join(PRACTICA, "Conciliacion", "herramientas"))
    from pg_lector import Lector, clave
    sql = """
    with ev as (
      select ticket_id id, texto, creado_en from ticket_detalle where (creado_en at time zone 'America/Costa_Rica') >= '%(d)s'::date
      union all select ticket_id, coalesce(nota,''), creado_en from ticket_estado where (creado_en at time zone 'America/Costa_Rica') >= '%(d)s'::date
      union all select ticket_id, coalesce(razon,''), creado_en from ticket_marca where (creado_en at time zone 'America/Costa_Rica') >= '%(d)s'::date
      union all select id, descripcion, creado_en from ticket where (creado_en at time zone 'America/Costa_Rica') >= '%(d)s'::date)
    select v.id, v.estado, coalesce(v.modulo,''), t.ambito, left(regexp_replace(v.descripcion,'\\s+',' ','g'),90),
           string_agg(ev.texto, ' ¦ ' order by ev.creado_en),
           ((t.creado_en at time zone 'America/Costa_Rica') >= '%(d)s'::date), v.descripcion
      from ev join v_ticket v on v.id = ev.id join ticket t on t.id = ev.id
     group by v.id, v.estado, v.modulo, t.ambito, v.descripcion, t.creado_en order by v.id""" % {"d": desde}
    with Lector(clave()[0]) as db:
        _, filas = db.consulta(sql)
    out = []
    for tid, est, mod, amb, tit, textos, nuevo, desc in filas:
        origenes = sorted(set(RX_ORIGEN.findall((textos or "") + " " + (desc or ""))))
        out.append({"id": int(tid), "estado": est, "modulo": "Mis pendientes" if amb == "propio" else (mod or "General"),
                    "titulo": tit, "desc": desc or "", "textos": textos or "", "nuevo": nuevo in (True, "t"), "origenes": origenes})
    return out


def listos_para_cerrar(ts):
    out = []
    for t in ts:
        if t["estado"] in ("cerrado", "pospuesto", "descartado"):
            continue
        partes = [p.strip() for p in t["textos"].split(" ¦ ") if RX_LISTO.search(p)]
        if t["estado"] != "en_validacion" and not partes:
            continue
        ev = next((p for p in reversed(partes) if RX_EVIDENCIA.search(p)), None)
        trozos = t["textos"].split(" ¦ ")
        despues = trozos[trozos.index(ev) + 1:] if ev in trozos else trozos[-1:]
        falta = RX_FALTA.search(" ".join(despues + ([ev] if ev else []))) or re.search(r"\bFalta:", t["desc"])
        if falta:
            out.append((t, "falta evidencia: el último avance dice «%s»" % falta.group(0)))
            continue
        out.append((t, ("evidencia: " + re.sub(r"^Origen: chat «[^»]+» · ", "", ev)[:220]) if ev else
                    "falta evidencia: un build, un commit o un enlace que muestre que quedó resuelto"))
    return out


def listos_bitacora(desde):
    txt = open(BITACORA, encoding="utf-8").read()
    out = []
    for m in re.finditer(r"(?ms)^## ✅ LISTO · (\d{4}-\d{2}-\d{2} \d{2}:\d{2}) · chat «([^»]+)»\n(.*?)(?=^## |^# |\Z)", txt):
        if m.group(1)[:10] >= desde:
            dec = re.search(r"(?m)^- Espera a una socia: (.*)$", m.group(3))
            pen = re.search(r"(?m)^- Pendiente: (.*)$", m.group(3))
            out.append({"hora": m.group(1), "origen": m.group(2), "decision": dec.group(1) if dec else "",
                        "pendiente": pen.group(1) if pen else ""})
    return out


def skills_respaldo():
    """Cada archivo de las skills vivas contra su respaldo en origin/dev (sin depender de la rama local)."""
    repo = REPOS["Conciliacion"]
    dif = []
    for raiz, _, archivos in os.walk(SKILLS_VIVAS):
        for a in archivos:
            p = os.path.join(raiz, a); rel = os.path.relpath(p, SKILLS_VIVAS)
            r = subprocess.run(["git", "-C", repo, "show", "refs/remotes/origin/dev:herramientas/skills/" + rel],
                               capture_output=True)
            if r.returncode != 0:
                dif.append(rel + " (no está en el respaldo de dev)")
            elif r.stdout != open(p, "rb").read():
                dif.append(rel + " (distinta de la de dev)")
    return dif


def main():
    hasta = _arg("--hasta", time.strftime("%Y-%m-%d"))
    if _arg("--desde"):
        desde, fuente = _arg("--desde"), "pedido (--desde)"
    else:
        desde, fuente = desde_por_defecto(hasta)
    if desde > hasta:
        sys.exit("✗ desde %s es después de hasta %s: ¿ya se cerró este día?" % (desde, hasta))
    fetch = "--sin-fetch" not in sys.argv
    L = ["# Cierre del día · %s → %s" % (desde, hasta), "",
         "Generado por /cierre-dia el %s. Desde: %s. Solo lectura: NO escribe el ESTADO." % (time.strftime("%Y-%m-%d %H:%M"), fuente), ""]
    R = {n: repo_info(n, p, desde, fetch) for n, p in REPOS.items()}
    pub, usado, libre = builds(REPOS["Conciliacion"])
    L += ["## 1 · Repos", ""]
    for n, r in R.items():
        if r.get("falta"):
            L += ["### %s — no está en esta Mac" % n, ""]; continue
        L.append("### %s" % n)
        L.append("- " + " · ".join("%s local %s · GitHub %s%s" % (k, a, b, "" if a == b else " ⚠") for k, (a, b) in r["ramas"].items()))
        if n == "Conciliacion":
            L.append("- BUILD publicado (main): **b%s** · el más alto en uso: b%s (%s) · **próximo libre: b%d**" % (pub, usado[0], usado[1], libre))
        if r["commits"]:
            for rama, cs in r["commits"].items():
                L.append("- `%s` · %d commit%s" % (rama, len(cs), "" if len(cs) == 1 else "s"))
                L += ["    - " + c for c in cs[:12]] + (["    - … y %d más" % (len(cs) - 12)] if len(cs) > 12 else [])
        else:
            L.append("- sin commits en el período")
        if r["sin_push"]:
            L.append("- ⚠ ramas del período sin push: " + ", ".join(r["sin_push"]))
        if r.get("viejas_sin_push"):
            L.append("- (y %d ramas viejas, sin trabajo en el período, con algo sin subir)" % r["viejas_sin_push"])
        extra = [w for w in r["worktrees"] if not w["principal"]]
        if extra:
            L.append("- worktrees abiertos: " + ", ".join("%s [%s]%s" % (w["ruta"], w["rama"], " (huérfano, prunable)" if w["prunable"] else "") for w in extra))
        if r["sucio"]:
            L += ["- ⚠ sin commitear: " + s for s in r["sucio"]]
        L.append("")
    m = turno.leer(turno.ARCHIVO)
    L += ["## 2 · Turno para cerrar", "",
          ("- marca de «%s» (%s) desde %s, hace %d min%s" % (m.get("origen"), m.get("que"), turno._hora(m.get("desde") or 0),
           (time.time() - float(m.get("desde") or 0)) / 60, " ⚠ COLGADA" if (time.time() - float(m.get("desde") or 0)) / 60 > turno.VENCE_MIN else ""))
          if m else "- sin marcas colgadas", ""]
    try:
        T = tickets(desde)
    except Exception as e:                                   # sin clave o sin red: se dice, no se calla
        T = None
        L += ["## 3 · Tickets", "", "⚠ no pude leer los tickets: %s" % type(e).__name__, ""]
    if T is not None:
        grupos = OrderedDict()
        for t in T:
            for o in (t["origenes"] or ["sin origen"]):
                grupos.setdefault(o, []).append(t)
        L += ["## 3 · Tickets tocados (%d), por chat de origen" % len(T), ""]
        for o, ts in grupos.items():
            L.append("### %s" % o)
            L += ["- T-%d · %s · %s%s · %s" % (t["id"], t["modulo"], t["estado"].replace("_", " "), " · NUEVO" if t["nuevo"] else "",
                                             t["titulo"]) for t in ts]
            L.append("")
        cand = listos_para_cerrar(T)
        L += ["## 4 · Parecen listos para cerrar (Andrea aprueba en un solo mensaje)", ""]
        L += ["- T-%d · %s — %s" % (t["id"], t["titulo"][:60], e) for t, e in cand] or ["- ninguno"]
        L.append("")
    LB = listos_bitacora(desde)
    dec = [x for x in LB if x["decision"] and x["decision"].lower() not in ("nada", "—")]
    L += ["## 5 · Decisiones que esperan a una socia", ""]
    L += ["- %s · chat «%s»: %s" % (x["hora"], x["origen"], x["decision"]) for x in dec] or \
         ["- ninguna anotada con /listo en el período"]
    en_val = [t for t in (T or []) if t["estado"] == "en_validacion"]
    L += ["- T-%d en validación: la cierra una socia · %s" % (t["id"], t["titulo"][:70]) for t in en_val]
    L += ["", "## 6 · Entradas /listo del período: %d" % len(LB), ""]
    L += ["- %s · chat «%s» · pendiente: %s" % (x["hora"], x["origen"], x["pendiente"] or "nada") for x in LB] or ["- ninguna"]
    L += ["", "## 7 · Copias", ""]
    resp_git = git(REPOS["respaldo-truefie"], "show", "refs/remotes/origin/main:trabajo/BITACORA.md")
    copias = [("Conciliacion/BITACORA.md", sha(BITACORA) if os.path.exists(BITACORA) else "—"),
              ("respaldo-truefie/trabajo/BITACORA.md (local)", sha(BITACORA_RESPALDO) if os.path.exists(BITACORA_RESPALDO) else "—"),
              ("respaldo-truefie en GitHub", sha(resp_git + "\n", True) if resp_git else "—")]
    iguales = len({c[1] for c in copias}) == 1
    L += ["- %s · sha256[12] %s" % c for c in copias]
    L.append("- %s" % ("✓ las tres copias de la bitácora son idénticas" if iguales else "⚠ las copias de la bitácora NO son iguales: sincronizar desde Conciliacion/BITACORA.md"))
    dif = skills_respaldo()
    L.append("- %s" % ("✓ skills vivas = respaldo en dev" if not dif else "⚠ skills distintas del respaldo en dev: " + ", ".join(dif)))
    # el bloque corto para Claude.ai
    B = ["[Cierre del día · %s → %s · generado por CC]" % (desde, hasta)]
    c = R["Conciliacion"]
    B.append("Truefie: publicado b%s · próximo libre b%d · main %s · dev %s" % (pub, libre, c["ramas"].get("main", ("—", "—"))[1],
                                                                              c["ramas"].get("dev", ("—", "—"))[1]))
    for n, r in R.items():
        if r.get("falta"):
            continue
        tot = sum(len(v) for v in r["commits"].values())
        if tot or r["sin_push"]:
            B.append("%s: %d commit%s en %s%s" % (n, tot, "" if tot == 1 else "s", ", ".join(r["commits"]) or "—",
                                                 (" · sin push: " + ", ".join(x.split(" ")[0] for x in r["sin_push"])) if r["sin_push"] else ""))
    if T is not None:
        B.append("Tickets tocados: %d · cerrados: %s · nuevos: %s" % (
            len(T), ", ".join("T-%d" % t["id"] for t in T if t["estado"] == "cerrado") or "—",
            ", ".join("T-%d" % t["id"] for t in T if t["nuevo"]) or "—"))
        for o, ts in grupos.items():
            B.append("· %s: %s" % (o, ", ".join("T-%d" % t["id"] for t in ts)))
        if cand:
            B.append("Para cerrar con tu OK: " + ", ".join("T-%d" % t["id"] for t, e in cand if e.startswith("evidencia")))
    if dec or en_val:
        B.append("Esperan a una socia: " + "; ".join([x["decision"] for x in dec] + ["T-%d" % t["id"] for t in en_val]))
    B.append("Bitácora: %s · skills: %s" % ("copias iguales" if iguales else "copias DISTINTAS", "ok" if not dif else "distintas"))
    L += ["", "## Bloque para el chat de Claude.ai", "", "```", *B, "```", ""]
    salida = _arg("--salida", os.path.join(CIERRES, "CIERRE_DIA_%s.md" % hasta))
    os.makedirs(os.path.dirname(salida), exist_ok=True)
    open(salida, "w", encoding="utf-8").write("\n".join(L))
    print("\n".join(B)); print("\n→ %s (local, sin commitear)" % salida)


if __name__ == "__main__":
    main()
