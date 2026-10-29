# CERCA DEL CANDADO DE ODOO (E1, 29-oct-2026). Falla si en un .html publicado de la raíz
# del repo vuelve a aparecer un camino de ESCRITURA a Odoo desde el navegador, o un camino
# que mande usuario/clave.
#
# Por qué existe: hasta b145 la "capa 2" del candado ("Conciliación bloqueada en prod")
# era un selector, `.face-concil`, que ningún elemento tenía. Se citó durante semanas como
# salvaguarda sin que existiera. Ahora la regla es que Conciliación NO PUEDE escribir por
# construcción —no queda código que escriba— y este chequeo es lo que lo sostiene.
#
# Lo corre loadcheck.py al final, sobre TODOS los .html de la raíz (GitHub Pages los
# publica todos), más dos pruebas negativas que demuestran que el chequeo ve el archivo
# entero. Solo:  python3 candado_check.py            (todos los .html de la raíz)
#                python3 candado_check.py otra.html  (uno)
#
# Los comentarios se quitan con un LEXER que respeta comillas simples, dobles, backticks
# (con ${…}) y regex literales, y conserva los saltos de línea (los números de línea que
# reporta son los reales). La primera versión los quitaba con una regex: el texto
# `accept="image/*,video/*"` de un string abría un falso /* y el chequeo dejaba de ver
# ~2.800 líneas de index.html (auditoría del 29-oct).
#
# Qué mira (en el código, sin comentarios; los strings SÍ cuentan):
#  1. El proxy viejo `truefood-proxy.onrender.com` (puerta con usuario + clave).
#  2. `tf_conn` guardado con setItem (usuario y clave de Odoo en claro).
#  3. Credenciales a Odoo: `Authorization: Basic …` y los encabezados `x-odoo-url/db`.
#  4. Cada llamada odooCall / lecturaRpc / odooRpc: el método tiene que ser de LECTURA
#     (lista fija acá abajo). Un método que no sea literal solo se acepta en los dos
#     envoltorios conocidos; cualquier otro, falla: no se puede verificar.
#  5. LECTURA_OK del archivo no puede tener nada fuera de esa lista.
#  6. Nombres de métodos de escritura de Odoo como texto (js_assign_outstanding_line,
#     action_post, reconcile, unlink, button_*, …), y endpoints `call_kw/<modelo>/<método>`.
#     `'create'` y `'write'` NO se buscan sueltos: Supabase y el resto del código los usan
#     con otro sentido; para Odoo ya los caza el punto 4.
#  7. Salidas de red: todo `fetch(` tiene que empezar por PROXY_LECTURA_URL o ESCRITURA_URL
#     (y esas dos constantes no pueden apuntar a *.odoo.com); `fetch` sin llamar (alias),
#     XMLHttpRequest y sendBeacon fallan siempre; y fallan los textos '/jsonrpc', '/xmlrpc',
#     'execute_kw', '/web/session/authenticate', y '/web/dataset/call_kw' fuera del
#     envoltorio `odooCall` (que ya no sale a la red: odooRpc lo ignora).
import re, sys, os, glob

LECTURA = {'search', 'search_read', 'read', 'search_count', 'read_group',
           'fields_get', 'name_search', 'name_get', 'default_get', 'get_views', 'load_views',
           'web_search_read', 'web_read', 'web_read_group', 'read_progress_bar'}
# Las únicas llamadas con el método en una variable: los envoltorios que ya pasan por LECTURA_OK.
ENVOLTORIOS = {
    "odooRpc('/web/dataset/call_kw',{model,method,args,kwargs})",
    "lecturaRpc(params.model, params.method, params.args||[], params.kwargs||{})",
}
ESCRITURA_NOMBRES = re.compile(
    r"""['"`](js_assign_outstanding_line|action_post|reconcile|unlink|message_post|"""
    r"""button_[a-z_]+|action_(?:register_payment|reconcile|validate|confirm|cancel|draft|done)[a-z_]*|"""
    r"""_?cron_[a-z_]+)['"`]""")
RUTAS_ODOO = re.compile(r'/jsonrpc|/xmlrpc|execute_kw|/web/session/authenticate|/web/dataset/call_kw')
FETCH_OK = ('PROXY_LECTURA_URL', 'ESCRITURA_URL')

# .html de la raíz que el chequeo NO revisa. Vacía a propósito: agregar uno es una
# decisión de la dueña (prueba.html, copia de b55, se borró en b147).
EXCEPCIONES = set()

# ── lexer: quita comentarios de JS respetando strings, templates y regex ──
_ANTES_DE_REGEX = set('(,=:[!&|?{};+-*%<>~^')
_PALABRAS_REGEX = {'return', 'typeof', 'case', 'in', 'of', 'new', 'delete', 'void', 'throw', 'else', 'do', 'yield', 'await'}

def _blanco(t):
    return ''.join('\n' if c == '\n' else ' ' for c in t)

def js_sin_comentarios(js, strings=False):
    """strings=True: además blanquea el CONTENIDO de strings, templates y regex (mismas posiciones)."""
    lit = (lambda t: t[0] + _blanco(t[1:-1]) + t[-1] if len(t) > 1 else t) if strings else (lambda t: t)
    out = []; i = 0; n = len(js)
    pila = []          # templates abiertos: cada uno guarda la profundidad de llaves de su ${
    llaves = 0
    ult = ''           # último carácter significativo de CÓDIGO (para decidir regex o división)
    ultpal = ''
    def es_regex():
        if ult == '' or ult in _ANTES_DE_REGEX: return True
        return ultpal in _PALABRAS_REGEX and ult.isalpha()
    def string(i, q):  # ' o " : no cruzan línea (si quedan abiertos, cortan ahí)
        j = i + 1
        while j < n:
            c = js[j]
            if c == '\\': j += 2; continue
            if c == q: return j + 1
            if c == '\n': return j
            j += 1
        return n
    def template(i):   # devuelve (fin, abrió_${)
        j = i
        while j < n:
            c = js[j]
            if c == '\\': j += 2; continue
            if c == '`': return j + 1, False
            if c == '$' and j + 1 < n and js[j + 1] == '{': return j + 2, True
            j += 1
        return n, False
    def regex(i):
        j = i + 1; clase = False
        while j < n:
            c = js[j]
            if c == '\\': j += 2; continue
            if c == '\n': return j
            if clase:
                if c == ']': clase = False
            elif c == '[': clase = True
            elif c == '/':
                j += 1
                while j < n and (js[j].isalnum() or js[j] == '_'): j += 1
                return j
            j += 1
        return n
    while i < n:
        c = js[i]
        if c == '/' and i + 1 < n and js[i + 1] == '/':
            j = js.find('\n', i); j = n if j < 0 else j
            out.append(_blanco(js[i:j])); i = j; continue
        if c == '/' and i + 1 < n and js[i + 1] == '*':
            j = js.find('*/', i + 2); j = n if j < 0 else j + 2
            out.append(_blanco(js[i:j])); i = j; continue
        if c in '\'"':
            j = string(i, c); out.append(lit(js[i:j])); i = j; ult = 'x'; ultpal = ''; continue
        if c == '`':
            j, abrio = template(i + 1); out.append(lit(js[i:j])); i = j
            if abrio: pila.append(llaves); llaves = 0; ult = '{'
            else: ult = 'x'
            ultpal = ''; continue
        if c == '/' and es_regex():
            j = regex(i); out.append(lit(js[i:j])); i = j; ult = 'x'; ultpal = ''; continue
        if c == '{': llaves += 1
        elif c == '}':
            if pila and llaves == 0:   # cierra un ${…}: sigue el template
                llaves = pila.pop()
                j, abrio = template(i + 1); out.append(lit(js[i:j])); i = j
                if abrio: pila.append(llaves); llaves = 0; ult = '{'
                else: ult = 'x'
                ultpal = ''; continue
            llaves -= 1
        if c.isalnum() or c in '_$':
            j = i
            while j < n and (js[j].isalnum() or js[j] in '_$'): j += 1
            ultpal = js[i:j]; ult = js[j - 1]; out.append(ultpal); i = j; continue
        if not c.isspace(): ult = c; ultpal = ''
        out.append(c); i += 1
    return ''.join(out)

def sin_comentarios(html, strings=False):
    """HTML: quita <!-- --> y los comentarios de cada <script> inline; los saltos de línea y las
    posiciones quedan iguales (strings=True: además blanquea los literales del JS)."""
    partes = []; pos = 0
    for m in re.finditer(r'(<script\b[^>]*>)(.*?)(</script>)', html, re.S | re.I):
        partes.append(re.sub(r'<!--.*?-->', lambda x: _blanco(x.group(0)), html[pos:m.start()], flags=re.S))
        partes.append(m.group(1) + js_sin_comentarios(m.group(2), strings) + m.group(3))
        pos = m.end()
    partes.append(re.sub(r'<!--.*?-->', lambda x: _blanco(x.group(0)), html[pos:], flags=re.S))
    out = ''.join(partes)
    assert len(out) == len(html) and out.count('\n') == html.count('\n'), 'el lexer cambió posiciones'
    return out

def args_de_llamada(txt, i):
    """Texto entre el '(' en i y su ')' (cuenta paréntesis)."""
    d = 0
    for j in range(i, len(txt)):
        c = txt[j]
        if c == '(': d += 1
        elif c == ')':
            d -= 1
            if d == 0: return txt[i + 1:j]
    return txt[i + 1:]

def revisar_texto(crudo):
    s = sin_comentarios(crudo)
    lineas = s.splitlines()
    nlin = lambda pos: s.count('\n', 0, pos) + 1
    malos = []
    def mal(pos, que):
        malos.append('l. %d · %s · %s' % (nlin(pos), que, lineas[nlin(pos) - 1].strip()[:110]))

    for m in re.finditer(r'truefood-proxy\.onrender\.com', s): mal(m.start(), 'proxy viejo')
    for m in re.finditer(r"""setItem\(\s*['"`]tf_conn""", s): mal(m.start(), 'tf_conn guardado')
    for m in re.finditer(r"""['"`]Basic ['"`]|Authorization['"`]?\s*:\s*['"`]Basic|x-odoo-(url|db)""", s):
        mal(m.start(), 'credenciales a Odoo')

    for m in re.finditer(r'\b(odooCall|lecturaRpc|odooRpc)\s*\(', s):
        nombre = m.group(1)
        if re.search(r'(async\s+)?function\s*$', s[max(0, m.start() - 20):m.start()]):
            continue                                     # la definición, no una llamada
        a = args_de_llamada(s, m.end() - 1)
        llamada = (nombre + '(' + a + ')')
        if nombre == 'odooRpc':
            meth = re.search(r"""\bmethod\s*:\s*(['"`])([^'"`]+)\1""", a)
            met = meth.group(2) if meth else None
            if met is None and re.search(r'\bmethod\b', a) is None:
                mal(m.start(), 'odooRpc sin método legible'); continue
        else:
            partes = re.match(r"""\s*[^,]+,\s*(['"`])([^'"`]+)\1""", a)
            met = partes.group(2) if partes else None
        if met is None:
            if llamada not in ENVOLTORIOS: mal(m.start(), 'método de Odoo no verificable')
        elif met not in LECTURA:
            mal(m.start(), 'ESCRITURA a Odoo (%s)' % met)

    for m in re.finditer(r'call_kw/[A-Za-z_.]+/[A-Za-z_]+', s): mal(m.start(), 'endpoint call_kw de un método')
    for m in ESCRITURA_NOMBRES.finditer(s): mal(m.start(), 'método de escritura de Odoo (%s)' % m.group(1))

    # 7. salidas de red (se buscan en el CÓDIGO, sin el contenido de strings ni regex)
    cod = sin_comentarios(crudo, strings=True)
    for m in re.finditer(r'\bfetch\b', cod):
        resto = cod[m.end():]
        if not re.match(r'\s*\(', resto):
            if re.search(r'function\s*$', cod[max(0, m.start() - 20):m.start()]) is None:
                mal(m.start(), 'fetch sin llamar (alias)')
            continue
        a = args_de_llamada(s, m.end() + resto.index('('))
        if not a.strip().startswith(FETCH_OK): mal(m.start(), 'fetch fuera de PROXY_LECTURA_URL/ESCRITURA_URL')
        elif RUTAS_ODOO.search(a) or re.search(r'odoo\.com', a): mal(m.start(), 'fetch hacia Odoo')
    for m in re.finditer(r'\bXMLHttpRequest\b|\bsendBeacon\b', cod): mal(m.start(), 'salida de red no permitida (%s)' % m.group(0))
    for k in FETCH_OK:
        d = re.search(r'const\s+' + k + r'\s*=([^;]*);', s)
        if d and re.search(r'odoo\.com', d.group(1)): mal(d.start(), k + ' apunta a Odoo')
    envoltorio = s.find(next(e for e in ENVOLTORIOS if e.startswith('odooRpc')))
    for m in RUTAS_ODOO.finditer(s):
        if envoltorio >= 0 and envoltorio <= m.start() < envoltorio + 40: continue
        mal(m.start(), 'ruta de Odoo (%s)' % m.group(0))

    ok = re.search(r'const\s+LECTURA_OK\s*=\s*new\s+Set\(\[(.*?)\]\)', s, re.S)
    if not ok:
        malos.append('LECTURA_OK no encontrada: el candado de odooRpc no se puede verificar')
    else:
        extra = set(re.findall(r"""['"`]([^'"`]+)['"`]""", ok.group(1))) - LECTURA
        if extra: malos.append('LECTURA_OK deja pasar métodos que no son de lectura: ' + ', '.join(sorted(extra)))
    return malos

def revisar(ruta):
    return revisar_texto(open(ruta, encoding='utf-8').read())

def html_de_la_raiz():
    raiz = os.path.dirname(os.path.abspath(__file__))
    return sorted(p for p in glob.glob(os.path.join(raiz, '*.html')) if os.path.basename(p) not in EXCEPCIONES)

if __name__ == '__main__':
    rutas = sys.argv[1:] or html_de_la_raiz()
    falla = False
    for ruta in rutas:
        malos = revisar(ruta)
        nom = os.path.basename(ruta)
        if malos:
            falla = True
            print('✗ CANDADO DE ODOO · %s: camino de escritura o de credenciales desde el navegador (%d):' % (nom, len(malos)))
            for x in malos[:12]: print('   ' + x)
            if len(malos) > 12: print('   … y %d más' % (len(malos) - 12))
        else:
            print('✓ candado de Odoo · %s: sin escrituras ni credenciales desde el navegador' % nom)
    sys.exit(1 if falla else 0)
