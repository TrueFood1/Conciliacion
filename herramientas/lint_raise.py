#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
lint_raise.py — cuenta los % de cada RAISE de plpgsql y los compara con sus
argumentos. Postgres NO avisa de esto al escribir el archivo: el cuerpo de una
funcion o de un DO se compila cuando se EJECUTA, asi que un RAISE con un
argumento de mas explota recien al pegarlo, y aborta la transaccion entera.

LA TRAMPA PRINCIPAL: en el formato de RAISE, `%%` es un signo de porcentaje
LITERAL, no un hueco. Entonces
    raise exception 'quedo en %% y tenia que ser 0', v_pct;
tiene CERO huecos y UN argumento -> «too many parameters specified for RAISE».
Y es facil de escribir, porque en castellano uno quiere imprimir «6,49%».

Uso:  python3 herramientas/lint_raise.py archivo.sql [archivo2.sql ...]
"""
import re, sys

NIVELES = ('exception','notice','warning','info','log','debug')

def literales_y_resto(s, i):
    """Lee los literales pegados desde i y devuelve (texto, i_despues).

    Entiende tres formas, porque las tres aparecen en este repo y las tres
    cuentan igual para los %:
      · 'normal'      con '' para la comilla
      · E'con \\n'      el prefijo E hay que saltarlo o el literal se pierde
                      ENTERO y el RAISE queda sin auditar, en silencio
      · $tag$ ... $tag$
    """
    txt = ''
    while True:
        while i < len(s) and s[i] in ' \t\r\n': i += 1
        if s.startswith('--', i):                      # comentario entre literales
            j = s.find('\n', i)
            i = len(s) if j < 0 else j + 1
            continue
        # prefijos de literal: E'' (escapes), U&'' (unicode), B''/X'' (bits)
        m = re.match(r"(?:[EeUuBbXx]&?|[Uu]&)'", s[i:])
        if m:
            i += m.end() - 1                           # cae sobre la comilla
        if i >= len(s): break
        if s[i] == '$':                                # literal $tag$...$tag$
            m2 = re.match(r'\$([A-Za-z_][A-Za-z0-9_]*)?\$', s[i:])
            if not m2: break
            cierre = m2.group(0)
            j = s.find(cierre, i + len(cierre))
            if j < 0: break
            txt += s[i + len(cierre):j]
            i = j + len(cierre)
            continue
        if s[i] != "'": break
        i += 1
        esc = bool(m)                                  # en E'' la barra escapa
        while i < len(s):
            if esc and s[i] == '\\' and i + 1 < len(s):
                txt += s[i:i+2]; i += 2; continue
            if s[i] == "'":
                if i + 1 < len(s) and s[i+1] == "'":
                    txt += "'"; i += 2; continue
                i += 1; break
            txt += s[i]; i += 1
    return txt, i

def huecos(fmt):
    """Cuenta los % que son huecos de verdad: %% es un porcentaje literal."""
    n, k = 0, 0
    while k < len(fmt):
        if fmt[k] == '%':
            if k + 1 < len(fmt) and fmt[k+1] == '%': k += 2; continue
            n += 1
        k += 1
    return n

def argumentos(s, i):
    """Cuenta los argumentos despues del formato, hasta el ; o el USING."""
    while i < len(s) and s[i] in ' \t\r\n': i += 1
    if i >= len(s) or s[i] == ';': return 0, None
    if s[i] != ',':
        return 0, 'no entendi como sigue el RAISE (%r)' % s[i:i+30]
    i += 1
    n, prof, enlit = 1, 0, False
    while i < len(s):
        c = s[i]
        if enlit:
            if c == "'":
                if i+1 < len(s) and s[i+1] == "'": i += 2; continue
                enlit = False
            i += 1; continue
        if c == "'": enlit = True; i += 1; continue
        if c in '([': prof += 1
        elif c in ')]':
            prof -= 1
            # El parentesis que cierra el format() termina la lista. Sin esto el
            # contador se sigue comiendo las comas del resto del archivo y
            # declara «24 argumentos» donde hay tres.
            if prof < 0: break
        elif c == ',' and prof == 0: n += 1
        elif c == ';' and prof == 0: break
        elif prof == 0 and re.match(r'\busing\b', s[i:], re.I) and not s[i-1:i].isalnum():
            return n, 'tiene USING'
        i += 1
    return n, None

def revisar(path):
    s = open(path, encoding='utf-8').read()
    # mapa de posicion -> numero de linea
    hallazgos, total = [], 0
    for m in re.finditer(r'\braise\s+(' + '|'.join(NIVELES) + r')\b', s, re.I):
        i = m.end()
        fmt, i2 = literales_y_resto(s, i)
        if not fmt:
            continue                      # `raise` a secas, o re-raise
        total += 1
        h = huecos(fmt)
        a, nota = argumentos(s, i2)
        ln = s.count('\n', 0, m.start()) + 1
        if h != a:
            hallazgos.append((ln, m.group(1).lower(), h, a, fmt[:70], nota))
        elif re.search(r'%[sIL]', fmt):
            # Cuadra en cantidad pero el mensaje sale mal: `%s` imprime el
            # argumento y despues una `s` de regalo.
            hallazgos.append((ln, m.group(1).lower(), h, a, fmt[:70],
                              'usa %s/%I/%L, que en RAISE no son especificadores'))
    return total, hallazgos

def revisar_format(path):
    """format() tiene el mismo problema y la misma hora: revienta al ejecutarse.
    Sus huecos son %s %I %L (y %% literal); un % suelto seguido de otra cosa es
    un error aparte que Postgres llama «unrecognized format() type specifier»."""
    s = open(path, encoding='utf-8').read()
    hall = []
    for m in re.finditer(r'\bformat\s*\(', s, re.I):
        fmt, i2 = literales_y_resto(s, m.end())
        if not fmt: continue
        n, k = 0, 0
        raro = None
        while k < len(fmt):
            if fmt[k] == '%':
                if k+1 < len(fmt) and fmt[k+1] == '%': k += 2; continue
                if k+1 < len(fmt) and fmt[k+1] in 'sIL': n += 1; k += 2; continue
                raro = fmt[k:k+2]
            k += 1
        a, _ = argumentos(s, i2)
        ln = s.count('\n', 0, m.start()) + 1
        if n != a or raro:
            hall.append((ln, n, a, fmt[:70], raro))
    return hall

malo = 0
for path in sys.argv[1:]:
    total, hs = revisar(path)
    print('── %s · %d RAISE con formato' % (path, total))
    if not hs:
        print('   ✓ todos cuadran: tantos argumentos como huecos')
    for ln, niv, h, a, fmt, nota in hs:
        malo += 1
        print('   ❌ linea %-5d raise %-9s huecos=%d argumentos=%d%s'
              % (ln, niv, h, a, '  (%s)' % nota if nota else ''))
        print('      %s…' % fmt.replace('\n', ' '))
        if re.search(r'%[sIL]', fmt):
            print('      → OJO: en RAISE el hueco es `%` solo. `%s` es de format(): '
                  'el `%` consume el argumento y la `s` se imprime suelta.')
        if h == 0 and a > 0 and '%%' in fmt:
            print('      → el `%%` es un porcentaje LITERAL, no un hueco. '
                  'Postgres dira «too many parameters specified for RAISE».')
    for ln, n, a, fmt, raro in revisar_format(path):
        malo += 1
        print('   ❌ linea %-5d format()  huecos=%d argumentos=%d%s'
              % (ln, n, a, '  (especificador raro: %r)' % raro if raro else ''))
        print('      %s…' % fmt.replace('\n', ' '))
print()
print('TOTAL: %d RAISE descuadrado(s)' % malo)
sys.exit(1 if malo else 0)
