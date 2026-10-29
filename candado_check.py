# CERCA DEL CANDADO DE ODOO (E1, 29-oct-2026). Falla si en index.html vuelve a aparecer
# un camino de ESCRITURA a Odoo desde el navegador, o un camino que mande usuario/clave.
#
# Por qué existe: hasta b145 la "capa 2" del candado ("Conciliación bloqueada en prod")
# era un selector, `.face-concil`, que ningún elemento tenía. Se citó durante semanas como
# salvaguarda sin que existiera. Ahora la regla es que Conciliación NO PUEDE escribir por
# construcción —no queda código que escriba— y este chequeo es lo que lo sostiene.
#
# Lo corre loadcheck.py al final. Solo:  python3 candado_check.py [ruta/a/index.html]
#
# Qué mira (en el código, sin comentarios):
#  1. El proxy viejo `truefood-proxy.onrender.com` (puerta con usuario + clave).
#  2. `tf_conn` guardado con setItem (usuario y clave de Odoo en claro).
#  3. Credenciales a Odoo: `Authorization: Basic …` y los encabezados `x-odoo-url/db`.
#  4. Cada llamada odooCall / lecturaRpc / odooRpc: el método tiene que ser de LECTURA
#     (lista fija acá abajo). Un método que no sea literal solo se acepta en los dos
#     envoltorios conocidos; cualquier otro, falla: no se puede verificar.
#  5. LECTURA_OK del index.html no puede tener nada fuera de esa lista.
#  6. Nombres de métodos de escritura de Odoo como texto (js_assign_outstanding_line,
#     action_post, reconcile, unlink, button_*, …), y endpoints `call_kw/<modelo>/<método>`.
#     `'create'` y `'write'` NO se buscan sueltos: Supabase y el resto del código los usan
#     con otro sentido; para Odoo ya los caza el punto 4.
import re, sys

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

def sin_comentarios(txt):
    txt = re.sub(r'<!--.*?-->', '', txt, flags=re.S)
    txt = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group(0).count('\n'), txt, flags=re.S)
    return '\n'.join(re.sub(r'(^|[^:\\\'"])//.*$', r'\1', l) for l in txt.splitlines())

def args_de_llamada(txt, i):
    """Texto entre el '(' en i y su ')' (cuenta paréntesis; las comillas no importan acá)."""
    d = 0
    for j in range(i, len(txt)):
        c = txt[j]
        if c == '(': d += 1
        elif c == ')':
            d -= 1
            if d == 0: return txt[i + 1:j]
    return txt[i + 1:]

def revisar(ruta):
    crudo = open(ruta, encoding='utf-8').read()
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

    ok = re.search(r'const\s+LECTURA_OK\s*=\s*new\s+Set\(\[(.*?)\]\)', s, re.S)
    if not ok:
        malos.append('LECTURA_OK no encontrada: el candado de odooRpc no se puede verificar')
    else:
        extra = set(re.findall(r"""['"`]([^'"`]+)['"`]""", ok.group(1))) - LECTURA
        if extra: malos.append('LECTURA_OK deja pasar métodos que no son de lectura: ' + ', '.join(sorted(extra)))
    return malos

if __name__ == '__main__':
    ruta = sys.argv[1] if len(sys.argv) > 1 else 'index.html'
    malos = revisar(ruta)
    if malos:
        print('✗ CANDADO DE ODOO: el navegador volvió a tener un camino de escritura o de credenciales:')
        for x in malos[:12]: print('   ' + x)
        if len(malos) > 12: print('   … y %d más' % (len(malos) - 12))
        sys.exit(1)
    print('✓ candado de Odoo: sin escrituras ni credenciales desde el navegador (solo lectura por el proxy)')
