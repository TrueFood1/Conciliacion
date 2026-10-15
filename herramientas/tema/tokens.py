# Tabla de tokens del tema: nombre -> (oscuro, claro, nota).
# El valor OSCURO es exactamente el hex que estaba escrito a mano: el modo oscuro no cambia.
NUEVOS = {
  # superficies
  'raise':      ('#1E1E22', '#EEF0F3', 'fondo levantado: hover, chip activo'),
  'raise-2':    ('#1B1B20', '#F1F3F6', 'fondo levantado, más callado'),
  'raise-3':    ('#191920', '#F1F3F6', 'fondo levantado, más callado'),
  'sunk-2':     ('#131316', '#F1F3F6', 'hundido dentro de una tarjeta'),
  'wash-1':     ('rgba(255,255,255,.02)', 'rgba(26,26,23,.025)', 'lavado mínimo'),
  'wash-2':     ('rgba(255,255,255,.03)', 'rgba(26,26,23,.035)', 'lavado de hover'),
  'wash-3':     ('rgba(255,255,255,.06)', 'rgba(26,26,23,.05)', 'lavado marcado'),
  # líneas y bordes
  'line':       ('#232329', '#E8EAEE', 'línea entre filas'),
  'line-soft':  ('#1A1A1E', '#EEF0F3', 'línea muy suave'),
  'line-3':     ('#1C1C20', '#EEF0F3', 'línea muy suave'),
  'line-4':     ('#1F1F24', '#E8EAEE', 'línea entre filas, variante'),
  'border-hi':  ('#3A3A42', '#C7CBD2', 'borde marcado (campo, botón)'),
  'border-hi-2':('#34343C', '#CDD1D7', 'borde marcado'),
  'border-hi-3':('#3E3E47', '#C2C6CD', 'borde marcado'),
  'border-hi-4':('#3E3E46', '#C2C6CD', 'borde marcado'),
  'border-hi-5':('#3A3A44', '#C7CBD2', 'borde marcado'),
  'border-hi-6':('#55555F', '#AEB2BA', 'borde fuerte'),
  # textos
  'text-soft':  ('#A8A6A0', '#5F5D58', 'texto suave (Salir, carga)'),
  'text-hi':    ('#C9C7C1', '#3A3935', 'texto casi principal'),
  'text-hi-2':  ('#C5C2BA', '#45433E', 'texto casi principal'),
  'text-hi-3':  ('#E8E6E0', '#2A2925', 'texto casi principal'),
  'text-dim':   ('#7E7C76', '#8B897F', 'texto apagado'),
  'text-dim-2': ('#7A7A72', '#8B897F', 'texto apagado'),
  'text-dim-3': ('#6F6C66', '#8B897F', 'texto apagado'),
  'text-dim-4': ('#5B5852', '#8B897F', 'texto apagado'),
  'text-dim-5': ('#5A5750', '#8B897F', 'texto apagado'),
  'text-dim-6': ('#57554F', '#8B897F', 'encabezado de tabla chico'),
  'text-dim-7': ('#4A4A50', '#A9ACB3', 'texto casi borrado (deshabilitado)'),
  # señal
  'err-soft':   ('#FFB4B4', '#A32D2D', 'texto de error sobre lavado rojo'),
  'err-2':      ('#FF8A8A', '#B03030', 'texto de error'),
  'err-wash':   ('#3A1B1B', '#FBE9E9', 'lavado de error'),
  'ok-olive':   ('#7E8C5A', '#5F6B3A', 'cuadra / ok, texto oliva'),
  'ok-fill':    ('#7E8C5A', '#B5C493', 'relleno ok con texto oscuro encima'),
  'dot-ok':     ('#5FB37A', '#3E8A57', 'punto verde'),
  'odoo':       ('#9AA7B8', '#5E6B7D', '«faltan compras por cargar»'),
  'lime-hover': ('#DFF04A', '#DFF04A', 'hover del lima (relleno: igual en los dos)'),
  # señal (2): tonos sueltos que estaban escritos a mano (4-oct)
  'warn-3':     ('#F0B45C', '#9A6410', 'ámbar de aviso'),
  'warn-4':     ('#E8C96A', '#8A5A00', 'ámbar claro'),
  'warn-5':     ('#C9A227', '#7A5A00', 'ámbar oscuro'),
  'warn-6':     ('#D9BE8C', '#7A4E08', 'ámbar apagado'),
  'warn-7':     ('#C9B284', '#7A5A20', 'ámbar apagado'),
  'warn-line':  ('#E0A82E', '#B07A10', 'borde ámbar'),
  'err-3':      ('#E7A6A6', '#A32D2D', 'rojo claro'),
  'err-4':      ('#E8A9A9', '#A32D2D', 'rojo claro'),
  'err-5':      ('#FFD9D9', '#8E2525', 'rojo muy claro'),
  'err-6':      ('#E08A8A', '#A83A3A', 'rojo suave'),
  'err-7':      ('#D9776E', '#A8402F', 'rojo ladrillo'),
  'err-8':      ('#E5484D', '#C0393D', 'rojo de borde y texto'),
  'ok-2':       ('#8EDE9F', '#2F7A45', 'verde claro'),
  # acentos de módulo (AA sobre la página clara)
  'm-fin':      ('#378ADD', '#1F66B3', 'Finanzas'),
  'm-ops':      ('#C77DA0', '#9E4C75', 'Operaciones (acento de vista)'),
  'm-ops-2':    ('#D4537E', '#B3325E', 'Operaciones (rosa del sistema)'),
  'm-conc':     ('#84BD00', '#4E7A00', 'Conciliación'),
  'm-comp':     ('#A27FEB', '#6E46CC', 'Compras'),
  'm-per':      ('#FF671D', '#C04400', 'Personal'),
  'magenta':    ('#C964CF', '#A23DA8', 'acento por defecto'),
  'orange-2':   ('#FF751F', '#C85400', 'naranja de Automatización / Pizza'),
  # colores de PRODUCTO (puntos y bordes; la etiqueta va siempre al lado)
  'p-blanco':   ('#378ADD', '#378ADD', 'Pan Blanco'),
  'p-semillas': ('#84BD00', '#5E8C00', 'Pan de Semillas'),
  'p-frances':  ('#D4537E', '#D4537E', 'Pan Francés'),
  'p-buns':     ('#7F77DD', '#7F77DD', 'Buns'),
  'p-pizza':    ('#FF751F', '#D9600E', 'Pizza Crust'),
  'p-galletas': ('#ED93B1', '#E07FA5', 'Cookie Dough'),
}
# Los que YA existen en :root (oscuro) y en el claro de Entregas (24-ago): se reusan.
EXISTENTES = {
  'bg': '#0E0E11', 'surface': '#161619', 'surface-2': '#18181C', 'panel': '#141417',
  'text': '#F5F4F0', 'text-2': '#9A988F', 'text-3': '#6E6C68',
  'border': '#26262C', 'border-strong': '#2C2C33',
  'warn': '#E9A23B', 'warn-2': '#C99A4E', 'warn-tx': '#E8D3AC', 'good': '#8FBF6A',
  'stop-tx': '#E24B4A', 'stop-line': '#E24B4A', 'lime': '#E9FE60', 'ent-line': '#E9FE60',
}
DARK = {**EXISTENTES, **{k: v[0] for k, v in NUEVOS.items()}}

# (color, rol) -> token. Rol: tx (color de texto), bg (fondo), bd (borde/outline), sh (sombra).
# '*' = cualquier rol. Lo que NO está acá queda escrito a mano en los dos modos (texto sobre
# un relleno lima/ámbar, blanco sobre un botón rojo, restos de temas viejos que ya no pintan).
MAPA = {
  ('#0E0E11', 'bg'): 'bg', ('#0E0E11', 'bd'): 'bg', ('#0E0E11', 'sh'): 'bg',
  ('#161619', '*'): 'surface', ('#18181C', '*'): 'surface-2', ('#141417', '*'): 'panel',
  ('#1E1E22', '*'): 'raise', ('#1B1B20', '*'): 'raise-2', ('#191920', '*'): 'raise-3', ('#131316', '*'): 'sunk-2',
  ('RGBA(255,255,255,.02)', 'bg'): 'wash-1', ('RGBA(255,255,255,.03)', 'bg'): 'wash-2', ('RGBA(255,255,255,.06)', 'bg'): 'wash-3',
  ('#232329', '*'): 'line', ('#1A1A1E', '*'): 'line-soft', ('#1C1C20', '*'): 'line-3', ('#1F1F24', '*'): 'line-4',
  ('#26262C', '*'): 'border', ('#2C2C33', '*'): 'border-strong',
  ('#3A3A42', '*'): 'border-hi', ('#34343C', '*'): 'border-hi-2', ('#3E3E47', '*'): 'border-hi-3',
  ('#3E3E46', '*'): 'border-hi-4', ('#3A3A44', '*'): 'border-hi-5', ('#55555F', '*'): 'border-hi-6',
  ('#F5F4F0', 'tx'): 'text', ('#F5F4F0', 'bd'): 'text', ('#9A988F', '*'): 'text-2', ('#6E6C68', '*'): 'text-3',
  ('#A8A6A0', '*'): 'text-soft', ('#C9C7C1', '*'): 'text-hi', ('#C5C2BA', '*'): 'text-hi-2', ('#E8E6E0', '*'): 'text-hi-3',
  ('#7E7C76', '*'): 'text-dim', ('#7A7A72', '*'): 'text-dim-2', ('#6F6C66', '*'): 'text-dim-3', ('#5B5852', '*'): 'text-dim-4',
  ('#5A5750', '*'): 'text-dim-5', ('#57554F', '*'): 'text-dim-6', ('#4A4A50', '*'): 'text-dim-7',
  ('#E9A23B', '*'): 'warn', ('#C99A4E', '*'): 'warn-2', ('#E8D3AC', '*'): 'warn-tx', ('#8FBF6A', '*'): 'good',
  ('#E24B4A', 'tx'): 'stop-tx', ('#E24B4A', 'bd'): 'stop-line', ('#E24B4A', 'bg'): 'stop-line', ('#E24B4A', 'sh'): 'stop-line',
  ('#FFB4B4', '*'): 'err-soft', ('#FF8A8A', '*'): 'err-2', ('#3A1B1B', '*'): 'err-wash',
  ('#7E8C5A', 'tx'): 'ok-olive', ('#7E8C5A', 'bd'): 'ok-olive', ('#7E8C5A', 'bg'): 'ok-fill',
  ('#5FB37A', '*'): 'dot-ok', ('#9AA7B8', '*'): 'odoo',
  ('#E9FE60', 'bg'): 'lime', ('#E9FE60', 'tx'): 'ent-line', ('#E9FE60', 'bd'): 'ent-line', ('#E9FE60', 'sh'): 'ent-line',
  ('#DFF04A', 'bg'): 'lime-hover',
  ('#378ADD', '*'): 'm-fin', ('#C77DA0', '*'): 'm-ops', ('#D4537E', '*'): 'm-ops-2', ('#84BD00', '*'): 'm-conc',
  ('#A27FEB', '*'): 'm-comp', ('#FF671D', '*'): 'm-per', ('#C964CF', '*'): 'magenta', ('#FF751F', '*'): 'orange-2',
  ('#F0B45C', '*'): 'warn-3', ('#E8C96A', '*'): 'warn-4', ('#C9A227', '*'): 'warn-5', ('#D9BE8C', '*'): 'warn-6',
  ('#C9B284', '*'): 'warn-7', ('#E0A82E', '*'): 'warn-line',
  ('#E7A6A6', '*'): 'err-3', ('#E8A9A9', '*'): 'err-4', ('#FFD9D9', '*'): 'err-5', ('#E08A8A', '*'): 'err-6',
  ('#D9776E', '*'): 'err-7', ('#E5484D', '*'): 'err-8', ('#8EDE9F', '*'): 'ok-2',
}

def norm(c):
    c = c.strip()
    if c.startswith('#'):
        h = c[1:].upper()
        if len(h) == 3: h = ''.join(x * 2 for x in h)
        return '#' + h
    return c.replace(' ', '').upper()

def token_para(color, rol):
    k = norm(color)
    return MAPA.get((k, rol)) or MAPA.get((k, '*'))
