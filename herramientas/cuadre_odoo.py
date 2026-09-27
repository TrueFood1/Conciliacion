#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
cuadre_odoo.py — el ORÁCULO de la opción C (27-sep-2026). SOLO LECTURA.

Calcula, por su cuenta y sin pasar por index.html, dónde Truefie y Odoo no dicen
lo mismo sobre la salida de un pedido con factura. La pantalla "Cuadre con Odoo"
(Pendientes) tiene que mostrar EXACTAMENTE lo mismo: si no coinciden, uno de los
dos está mal. Diseño en OPCION_C_CUADRE_ODOO.md.

    python3 herramientas/cuadre_odoo.py            # la lista, legible
    python3 herramientas/cuadre_odoo.py --json     # para comparar con la pantalla

LOS CASOS (C1)
  1 · preparado en Truefie, la salida ya está validada (done) en Odoo
  2 · la salida está sin validar en Odoo (ni done ni cancel)
  3 · entregado en Truefie y Odoo no tiene ninguna salida hecha
  4 · entregado, y por producto lo que salió en Truefie ≠ lo que Odoo descontó
  5 · la factura del pedido está revertida (tiene nota de crédito)

LA CADENA, por ID y nunca por texto (la misma que `despYaEntregado`):
  factura → account.move.line.sale_line_ids → sale.order.line.order_id →
  sale.order.picking_ids → stock.picking (solo `outgoing`) → stock.move
Unidades: Truefie guarda unidades sueltas (`cant_uds`); Odoo, la cantidad en la
UoM de cada movimiento. Se convierte con `quantity / factor` de ESA UoM, por id.
"""
import json, os, sys

_AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _AQUI)
sys.path.insert(0, os.path.dirname(_AQUI))
from pg_lector import Lector, clave     # noqa: E402
import odoo_read as O                   # noqa: E402

DESDE = '2026-08-15'   # = DESP_DESDE de index.html: antes no hay módulo de Entregas
EPS = 1e-6


def leer_truefie():
    with Lector(clave()[0]) as db:
        cols, filas = db.consulta(
            "select pedido_id, estado, factura_id, factura_nombre, cliente_nombre, "
            "preparado_en, salida_en from v_ent_pedido_estado "
            "where factura_id is not null and estado in ('preparado','entregado') "
            "and fecha_despacho >= '%s' order by pedido_id" % DESDE)
        peds = [dict(zip(cols, f)) for f in filas]
        ids = ','.join(str(p['pedido_id']) for p in peds) or '0'
        cols, filas = db.consulta(
            "select av.pedido_id, l.producto_id, sum(l.cant_uds) as uds "
            "from ent_alisto_vigente av join ent_alisto_linea l on l.alisto_id = av.alisto_id "
            "where av.pedido_id in (%s) and not coalesce(l.no_se_entrega, false) "
            "group by 1, 2" % ids)
    salio = {}
    for pid, prod, uds in filas:
        salio.setdefault(int(pid), {})[int(prod)] = float(uds)
    return peds, salio


def leer_odoo(fac_ids):
    ctx = {'lang': 'es_CR'}
    fac = {m['id']: m for m in O.call('account.move', 'read', fac_ids,
           fields=['id', 'name', 'state', 'payment_state', 'reversal_move_id'], context=ctx)}
    lin = O.call('account.move.line', 'search_read',
                 [['move_id', 'in', fac_ids], ['display_type', '=', 'product']],
                 fields=['move_id', 'sale_line_ids'], limit=20000, context=ctx)
    sol = sorted({x for l in lin for x in (l['sale_line_ids'] or [])})
    sol_de_fac = {}
    for l in lin:
        sol_de_fac.setdefault(l['move_id'][0], set()).update(l['sale_line_ids'] or [])
    orden = {r['id']: r['order_id'][0] for r in
             O.call('sale.order.line', 'read', sol, fields=['id', 'order_id'], context=ctx)} if sol else {}
    so_ids = sorted(set(orden.values()))
    pk_de_so = {r['id']: r['picking_ids'] for r in
                O.call('sale.order', 'read', so_ids, fields=['id', 'picking_ids'], context=ctx)} if so_ids else {}
    pk_ids = sorted({p for v in pk_de_so.values() for p in v})
    pks = {p['id']: p for p in O.call('stock.picking', 'read', pk_ids,
           fields=['id', 'name', 'state', 'picking_type_code', 'scheduled_date', 'date_done'],
           context=ctx)} if pk_ids else {}
    mvs = O.call('stock.move', 'search_read', [['picking_id', 'in', pk_ids]],
                 fields=['picking_id', 'product_id', 'quantity', 'product_uom', 'state'],
                 limit=20000, context=ctx) if pk_ids else []
    uoms = sorted({m['product_uom'][0] for m in mvs})
    fac_uom = {u['id']: u['factor'] or 1 for u in
               O.call('uom.uom', 'read', uoms, fields=['id', 'factor'], context=ctx)} if uoms else {}
    # por factura: sus salidas (solo outgoing) y lo descontado por producto
    out = {}
    for fid in fac_ids:
        sos = {orden[s] for s in sol_de_fac.get(fid, ()) if s in orden}
        salidas = [pks[p] for so in sos for p in pk_de_so.get(so, ()) if p in pks
                   and pks[p]['picking_type_code'] == 'outgoing']
        desc = {}
        hechas = {p['id'] for p in salidas if p['state'] == 'done'}
        for m in mvs:
            if m['picking_id'] and m['picking_id'][0] in hechas and m['state'] == 'done':
                uds = (m['quantity'] or 0) / fac_uom.get(m['product_uom'][0], 1)
                desc[m['product_id'][0]] = desc.get(m['product_id'][0], 0) + uds
        f = fac.get(fid, {})
        out[fid] = {'factura': f.get('name'), 'revertida': bool(f.get('reversal_move_id'))
                    or f.get('payment_state') == 'reversed',
                    'salidas': salidas, 'descontado': desc}
    return out


def cuadre():
    peds, salio = leer_truefie()
    od = leer_odoo(sorted({int(p['factura_id']) for p in peds}))
    casos = []
    for p in peds:
        pid, est, fid = int(p['pedido_id']), p['estado'], int(p['factura_id'])
        o = od.get(fid, {})
        sal = o.get('salidas', [])
        hechas = [s for s in sal if s['state'] == 'done']
        abiertas = [s for s in sal if s['state'] not in ('done', 'cancel')]
        motivos = []
        if est == 'preparado' and hechas:
            motivos.append({'caso': 1, 'que': 'preparado en Truefie, validado en Odoo',
                            'odoo': ', '.join('%s el %s' % (s['name'], s['date_done']) for s in hechas)})
        if abiertas:
            motivos.append({'caso': 2, 'que': 'salida sin validar en Odoo',
                            'odoo': ', '.join('%s (%s, programada %s)' % (s['name'], s['state'], s['scheduled_date'])
                                              for s in abiertas)})
        if est == 'entregado' and not hechas and not abiertas:
            motivos.append({'caso': 3, 'que': 'entregado en Truefie, sin salida hecha en Odoo',
                            'odoo': ', '.join('%s (%s)' % (s['name'], s['state']) for s in sal) or 'sin salida'})
        if est == 'entregado' and hechas:
            t, d = salio.get(pid, {}), o.get('descontado', {})
            dif = {pr: (t.get(pr, 0), d.get(pr, 0)) for pr in set(t) | set(d)
                   if abs(t.get(pr, 0) - d.get(pr, 0)) > EPS}
            if dif:
                motivos.append({'caso': 4, 'que': 'cantidad distinta',
                                'odoo': '; '.join('producto %d: Truefie %g u · Odoo %g u' % (pr, a, b)
                                                  for pr, (a, b) in sorted(dif.items()))})
        if o.get('revertida'):
            motivos.append({'caso': 5, 'que': 'la factura del pedido está revertida',
                            'odoo': o.get('factura')})
        if motivos:
            casos.append({'pedido': pid, 'estado': est, 'factura': p['factura_nombre'],
                          'motivos': motivos})
    return casos


if __name__ == '__main__':
    c = cuadre()
    if '--json' in sys.argv:
        print(json.dumps(c, ensure_ascii=False, indent=1, default=str))
    else:
        print('%d pedidos con algo que no cuadra' % len(c))
        for x in c:
            print('· pedido %d (%s, …%s)' % (x['pedido'], x['estado'], str(x['factura'])[-4:]))
            for m in x['motivos']:
                print('    caso %d · %s · %s' % (m['caso'], m['que'], m['odoo']))
