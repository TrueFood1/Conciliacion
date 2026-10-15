#!/usr/bin/env python3
# Convierte los colores escritos a mano de index.html en tokens del tema.
# Uso: python3 convertir.py <index.html> [--escribir]
# Sin --escribir solo informa. Con --escribir reescribe el archivo.
# Prueba que el modo OSCURO no cambia: cada línea tocada, con var(--x) reemplazado por el valor
# oscuro del token, tiene que dar EXACTAMENTE los mismos colores que la línea original.
# Un token NUEVO va en tokens.py Y en los dos bloques de index.html (`:root` con el valor oscuro,
# `html[data-tema="claro"]` con el claro): este script no escribe las definiciones.
# No toca la zona de Personal (Lorena) ni las definiciones `--token:valor`, ni los comentarios.
import re, sys, collections
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from tokens import token_para, DARK, norm

RUTA = sys.argv[1]
ESCRIBIR = '--escribir' in sys.argv
L = open(RUTA, encoding='utf-8').read().split('\n')

def rango_de(marca_ini, marca_fin, desde=0):
    a = next(i for i in range(desde, len(L)) if marca_ini(L[i]))
    b = next(i for i in range(a + 1, len(L)) if marca_fin(L[i]))
    return a, b

# Bloques <style> y <script> (por estructura, no por número de línea)
CSS, JS = [], []
i = 0
while i < len(L):
    s = L[i].strip()
    if s == '<style>':
        j = next(k for k in range(i + 1, len(L)) if L[k].strip() == '</style>'); CSS.append((i + 1, j)); i = j
    elif s == '<script>':
        j = next(k for k in range(i + 1, len(L)) if L[k].strip() == '</script>'); JS.append((i + 1, j)); i = j
    i += 1
# HTML = lo que no es ni style ni script, entre <body> y el final
ocupado = set()
for a, b in CSS + JS:
    ocupado.update(range(a, b))

# ZONA DE LORENA (Personal): no se toca. Se ubica por contenido.
def idx(pred, desde=0):
    return next(k for k in range(desde, len(L)) if pred(L[k]))
per_css = (idx(lambda t: '/* ── PERSONAL · MIS VACACIONES' in t), idx(lambda t: t.startswith('.per-go:hover')) + 1)
per_html = (idx(lambda t: '<div id="vVacaciones"' in t), idx(lambda t: 'id="ferBody"' in t) + 2)
per_js = (idx(lambda t: t.startswith('const PER_TABS=')), idx(lambda t: t.startswith('function setProgress(')))
# Las tablas de colores de PRODUCTO se cambian aparte (a var(--p-*)).
ZONAS_NO = [per_css, per_html, per_js]
def en_zona_no(n):
    return any(a <= n < b for a, b in ZONAS_NO)

COLOR = re.compile(r'#[0-9A-Fa-f]{6}\b|#[0-9A-Fa-f]{3}\b|rgba?\(\s*[\d.]+\s*,\s*[\d.]+\s*,\s*[\d.]+\s*(?:,\s*[\d.]+\s*)?\)')
TX = {'color', 'caret-color', '-webkit-text-fill-color', 'fill', 'stroke', 'text-decoration-color', 'accent-color'}
def rol(prop):
    p = prop.lower()
    if p in TX: return 'tx'
    if p.startswith('background'): return 'bg'
    if 'shadow' in p: return 'sh'
    return 'bd'

def sub_valor(prop, valor, stats, sinmapa):
    r = rol(prop)
    def f(m):
        tok = token_para(m.group(0), r)
        if not tok:
            sinmapa[(norm(m.group(0)), r)] += 1
            return m.group(0)
        stats[tok] += 1
        return '\x01var(--%s)' % tok
    return COLOR.sub(f, valor)

DECL_CSS = re.compile(r'(?<![\w-])([A-Za-z-]+)(\s*:\s*)([^;{}]+)')
DECL_JS = re.compile(r'(?<![\w-])(color|background(?:-color)?|border(?:-(?:top|bottom|left|right))?(?:-color)?|outline(?:-color)?|box-shadow|fill|stroke)(\s*:\s*)([^;\'"<>{}]*)')

def procesar_css(texto, stats, sinmapa):
    # Fuera de los comentarios /* */ y sin tocar las definiciones --token:valor
    out, k = [], 0
    for m in re.finditer(r'/\*.*?\*/', texto, flags=re.S):
        out.append(('c', texto[k:m.start()])); out.append(('n', m.group(0))); k = m.end()
    out.append(('c', texto[k:]))
    res = []
    for tipo, t in out:
        if tipo == 'n': res.append(t); continue
        def f(m):
            prop = m.group(1)
            if prop.startswith('--'): return m.group(0)
            return prop + m.group(2) + sub_valor(prop, m.group(3), stats, sinmapa)
        res.append(DECL_CSS.sub(f, t))
    return ''.join(res)

def procesar_js_linea(t, stats, sinmapa):
    t2 = DECL_JS.sub(lambda m: m.group(1) + m.group(2) + sub_valor(m.group(1), m.group(3), stats, sinmapa), t)
    # el.style.color='#...'
    def g(m):
        prop = {'color': 'color', 'background': 'background', 'backgroundColor': 'background', 'borderColor': 'border-color'}[m.group(1)]
        tok = token_para(m.group(3), rol(prop))
        if not tok:
            sinmapa[(norm(m.group(3)), rol(prop))] += 1; return m.group(0)
        stats[tok] += 1
        return '.style.%s=%s\x01var(--%s)%s' % (m.group(1), m.group(2), tok, m.group(2))
    return re.sub(r"\.style\.(color|background|backgroundColor|borderColor)\s*=\s*(['\"])(#[0-9A-Fa-f]{3,6})\2", g, t2)

stats, sinmapa = collections.Counter(), collections.Counter()
nuevo = list(L)
# CSS: por bloque entero (los comentarios cruzan líneas)
for a, b in CSS:
    # se procesa por tramos que no entren en la zona de Personal
    n = a
    while n < b:
        if en_zona_no(n):
            n += 1; continue
        m = n
        while m < b and not en_zona_no(m): m += 1
        texto = '\n'.join(L[n:m])
        nuevo[n:m] = procesar_css(texto, stats, sinmapa).split('\n')
        n = m
# JS y HTML: línea por línea
for n in range(len(L)):
    if en_zona_no(n): continue
    if any(a <= n < b for a, b in CSS): continue
    if n < next(k for k in range(len(L)) if '<body' in L[k]): continue
    nuevo[n] = procesar_js_linea(L[n], stats, sinmapa)

# ── VERIFICACIÓN: el oscuro no cambia ──
def oscurecer(t):
    return re.sub(r'\x01var\(--([\w-]+)\)', lambda m: DARK[m.group(1)], t)
def _nuestro(m):
    return True
malos = 0; tocadas = 0
for n in range(len(L)):
    if nuevo[n] == L[n]: continue
    tocadas += 1
    o = [norm(c) for c in COLOR.findall(L[n])]
    d = [norm(c) for c in COLOR.findall(oscurecer(nuevo[n]))]
    # los var() que ya estaban en la línea original no cuentan: se comparan solo los colores
    if o != d or re.sub(COLOR, '#', L[n]) != re.sub(COLOR, '#', oscurecer(nuevo[n])):
        malos += 1
        if malos <= 10: print('DIFERENCIA en', n + 1, '\n  antes:', L[n][:200], '\n  ahora:', nuevo[n][:200])
print('líneas tocadas:', tocadas, '· diferencias en oscuro:', malos)
print('reemplazos por token:', sum(stats.values()), dict(stats.most_common()))
print('zonas de Personal intactas:', [(a + 1, b) for a, b in ZONAS_NO])
print('sin mapa (quedan a mano, top 40):')
for (c, r), k in sinmapa.most_common(40): print('  ', c, r, k)
if ESCRIBIR and malos == 0:
    open(RUTA, 'w', encoding='utf-8').write('\n'.join(nuevo).replace('\x01', ''))
    print('ESCRITO')
