# A1 · LECTOR factura → pedido de entrega. SOLO LECTURA.
# Trampas cubiertas: display_type='product' (si no, las líneas de COGS inflan 3×),
# producto por ID, y cantidad convertida a unidades individuales con uom.uom.factor
# (uds = qty / factor: "Paquete de 4" tiene factor 0,25).
import odoo_read as o
CTX={'context':{'lang':'es_CR'}}
# caja física por producto (INV_TERM del index.html) — unidades individuales por caja
CAJA={451:6, 452:6, 453:24, 472:12, 503:24, 519:12}
NOM ={451:'Pan Blanco',452:'Pan de Semillas',453:'Pan Francés',472:'Pizza Crust',503:'Buns',519:'Galletas'}
_uf={}
def uomf(uid):
    if uid not in _uf:
        _uf[uid]=o.call('uom.uom','read',[uid],fields=['factor'])[0]['factor'] or 1
    return _uf[uid]

def factura_a_pedido(inv_id):
    m=o.call('account.move','read',[inv_id],
        fields=['id','name','invoice_date','partner_id','amount_total','state','move_type'],**CTX)[0]
    if m['move_type']!='out_invoice' or m['state']!='posted':
        return {'error':'no es una factura de venta posteada'}
    pr=o.call('res.partner','read',[m['partner_id'][0]],fields=['id','name','team_id'],**CTX)[0]
    ls=o.call('account.move.line','search_read',
        [['move_id','=',inv_id],['display_type','=','product']],
        fields=['product_id','quantity','product_uom_id','name','price_subtotal'],**CTX)
    lineas, ajenas = [], []
    for l in ls:
        pid=l['product_id'][0] if l['product_id'] else None
        uds=(l['quantity'] or 0)/ (uomf(l['product_uom_id'][0]) if l['product_uom_id'] else 1)
        if pid not in CAJA:
            ajenas.append({'pid':pid,'nombre':(l['product_id'][1] if l['product_id'] else l['name']),'uds':uds})
            continue
        c=CAJA[pid]; cajas=int(uds//c); sueltas=round(uds-cajas*c, 3)
        lineas.append({'pid':pid,'producto':NOM[pid],
                       'uom_factura':l['product_uom_id'][1] if l['product_uom_id'] else '',
                       'qty_factura':l['quantity'],'uds':uds,'cajas':cajas,'sueltas':sueltas,
                       'exacto_en_cajas': sueltas==0})
    return {'factura':m['name'],'fecha':m['invoice_date'],'cliente':pr['name'],
            'canal':(pr['team_id'][1] if pr['team_id'] else '(sin canal)'),
            'total':m['amount_total'],'lineas':lineas,'ajenas':ajenas}

def resumen(p):
    """La línea corrida que va SIN abrir el acordeón."""
    def uno(l):
        return f"{l['producto'].replace('Pan ','')} {l['cajas']} cj" if l['exacto_en_cajas'] and l['cajas'] \
          else f"{l['producto'].replace('Pan ','')} {int(l['uds']) if l['uds']==int(l['uds']) else l['uds']} uds"
    return ' · '.join(uno(l) for l in p['lineas'])
