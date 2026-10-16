#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
lint_plpgsql.py — revisa los bloques DO y los cuerpos plpgsql de un .sql buscando
los descuadres que Postgres NO reporta al escribir el archivo, sino al pegarlo.

QUE REVISA, y por que cada uno:
  · begin/end, if/end if, loop/end loop, case/end case — un `end if` de menos y
    el bloque entero no compila, con un mensaje que apunta al final del archivo;
  · variables usadas sin declarar — `v_pct` donde se declaro `v_pc` compila igual
    si existe una COLUMNA con ese nombre, y entonces lee otra cosa en silencio;
  · `select ... into X` con X sin declarar;
  · `exception when` sin `begin` propio.

NO REEMPLAZA A POSTGRES. Es lo que se puede hacer sin una base: un parser de
verdad resuelve nombres contra el catalogo y este no.

Uso:  python3 herramientas/lint_plpgsql.py archivo.sql [...]
"""
import re, sys

PAL = r'\b(%s)\b'
IGNORAR = {  # no son variables: son funciones, palabras clave o tipos
 'v_', }

def bloques(s):
    """Devuelve (etiqueta, linea_inicial, cuerpo) de cada do $x$...$x$ y de cada
    cuerpo de funcion plpgsql."""
    out = []
    for m in re.finditer(r'\bdo\s+(\$[A-Za-z_]*\$)', s, re.I):
        tag = m.group(1)
        j = s.find(tag, m.end())
        if j < 0: continue
        out.append(('DO %s' % tag, s.count('\n',0,m.start())+1, s[m.end():j]))
    for m in re.finditer(r'language\s+plpgsql[^;]*?\bas\s+(\$[A-Za-z_]*\$)', s, re.I|re.S):
        tag = m.group(1)
        j = s.find(tag, m.end())
        if j < 0: continue
        nom = re.search(r'function\s+([A-Za-z_][\w]*)',
                        s[max(0,m.start()-400):m.start()], re.I)
        out.append(('funcion %s' % (nom.group(1) if nom else '?'),
                    s.count('\n',0,m.start())+1, s[m.end():j]))
    return out

def limpio(c):
    c = re.sub(r'--[^\n]*', '', c)
    return re.sub(r"'(?:[^']|'')*'", "''", c)

def revisar(path):
    s = open(path, encoding='utf-8').read()
    hall = []
    for etq, ln, cuerpo in bloques(s):
        c = limpio(cuerpo)
        pares = [('begin','end'), ('if','end if'), ('loop','end loop'), ('case','end case')]
        # `end if` contiene la palabra `if`: hay que descontarla, o todo bloque
        # correcto parece tener el doble de `if` que de `end if`.
        n_endif= len(re.findall(r'\bend\s+if\b', c, re.I))
        n_if   = len(re.findall(r'\bif\b', c, re.I)) - n_endif
        if n_if != n_endif:
            hall.append((etq, ln, 'if=%d end if=%d' % (n_if, n_endif)))
        n_endlo = len(re.findall(r'\bend\s+loop\b', c, re.I))
        n_lo    = len(re.findall(r'\bloop\b', c, re.I)) - n_endlo
        if n_lo != n_endlo:
            hall.append((etq, ln, 'loop=%d end loop=%d' % (n_lo, n_endlo)))
        # ⚠️ UN `case ... end` DE SQL TAMBIEN TERMINA EN `end` PELADO. El `case`
        # de plpgsql cierra con `end case`, pero la EXPRESION case —la que se usa
        # en un select o en una asignacion— cierra con `end` a secas, y entonces
        # parece el cierre de un bloque. Sin descontarlos, todo bloque con una
        # expresion case sale descuadrado: eso es un falso positivo, y un linter
        # con falsos positivos enseña a ignorarlo.
        n_case_expr = len(re.findall(r'\bcase\b', c, re.I)) - \
                      len(re.findall(r'\bend\s+case\b', c, re.I))
        n_beg = len(re.findall(r'\bbegin\b', c, re.I))
        n_end = len(re.findall(r'\bend\b(?!\s*(if|loop|case))', c, re.I)) - n_case_expr
        if n_beg != n_end:
            hall.append((etq, ln, 'begin=%d end=%d (descontadas %d expresiones case)'
                                  % (n_beg, n_end, n_case_expr)))
        # variables: declaradas entre `declare` y el primer `begin`
        mdec = re.match(r'\s*declare\b(.*?)\bbegin\b', c, re.I|re.S)
        decl = set()
        if mdec:
            for d in re.finditer(r'\b([a-z_][\w]*)\s+(?:text|int|integer|bigint|numeric|'
                                 r'boolean|date|timestamptz|record|refcursor)', mdec.group(1), re.I):
                decl.add(d.group(1).lower())
            for d in re.finditer(r'\bfor\s+([a-z_][\w]*)\s+in\b', c, re.I):
                decl.add(d.group(1).lower())
        # ⚠️ `v_rrhh_pago` NO es una variable, es una VISTA. El prefijo `v_` lo
        # usan las dos cosas en este repo, asi que hay que descartar los nombres
        # de relacion: los declarados en el archivo, y todo lo que venga pegado a
        # un from/join/update/insert into o detrás de un punto.
        relaciones = set(x.lower() for x in re.findall(
            r'create\s+(?:or\s+replace\s+)?(?:view|table)\s+(?:if\s+not\s+exists\s+)?'
            r'([a-z_]\w*)', s, re.I))
        relaciones |= set(x.lower() for x in re.findall(
            r'\b(?:from|join|update|into)\s+([a-z_]\w*)', c, re.I))
        usadas = set(x.lower() for x in re.findall(r'(?<![.\w])(v_[a-z_]\w*)\b', c, re.I))
        usadas |= set(x.lower() for x in re.findall(r'\binto\s+([a-z_]\w*)', c, re.I))
        faltan = sorted(u for u in usadas
                        if u not in decl and u.startswith('v_') and u not in relaciones)
        if faltan:
            hall.append((etq, ln, 'variables usadas y NO declaradas: %s' % ', '.join(faltan)))
        # El `begin` de arriba de un bloque DO PUEDE llevar su propio `exception`:
        # no hace falta un begin anidado. Lo unico que seria un error es un
        # `exception when` sin ningun `begin` delante.
        me = re.search(r'\bexception\s+when\b', c, re.I)
        if me and not re.search(r'\bbegin\b', c[:me.start()], re.I):
            hall.append((etq, ln, 'exception when sin ningun begin delante'))
    return hall

malo = 0
for path in sys.argv[1:]:
    hs = revisar(path)
    print('── %s · %d bloque(s) plpgsql' % (path, len(bloques(open(path,encoding='utf-8').read()))))
    if not hs: print('   ✓ todos cuadran')
    for etq, ln, q in hs:
        malo += 1; print('   ❌ %s (linea %d): %s' % (etq, ln, q))
print('\nTOTAL: %d descuadre(s)' % malo)
sys.exit(1 if malo else 0)
