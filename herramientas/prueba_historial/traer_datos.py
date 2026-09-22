#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Baja de PRODUCCION las filas reales que lee el Historial, con la MISMA
proyeccion que pide el codigo. Solo lectura (pg_lector envuelve en READ ONLY).
El volcado NO se commitea: lleva razones sociales y el repo es publico."""
import sys, json, io
import os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import pg_lector as L

PEDIDOS = [67, 134, 66, 55, 135]
clave, fuente = L.clave()
lec = L.Lector(clave)

def j(sql):
    cols, filas = lec.consulta("select coalesce(json_agg(t),'[]'::json)::text from (%s) t" % sql)
    return json.loads(filas[0][0])

ped = ",".join(str(p) for p in PEDIDOS)
datos = {
  # exactamente el .select() de bsLeer
  "v_ent_pedido_estado": j("""
     select pedido_id, fecha_despacho, factura_id, factura_nombre, cliente_nombre, origen,
            motivo, alisto_id, responsable, preparado_en, salida_en, salida_registrada_en,
            salida_id, estado, fecha_ab_re_04
       from v_ent_pedido_estado where pedido_id in (%s) order by fecha_ab_re_04 desc""" % ped),
  "ent_pedido": j("select id, destinatario from ent_pedido where id in (%s)" % ped),
  "ent_alisto": j("""select id, pedido_id, responsable, creado_en, creado_por, anulado
                       from ent_alisto where pedido_id in (%s)""" % ped),
  "ent_anulacion": j("""select entidad, entidad_id, creado_por, creado_en, motivo
                          from ent_anulacion where entidad='alisto'
                           and entidad_id in (select id from ent_alisto where pedido_id in (%s))""" % ped),
  "ent_alisto_linea": j("""select id, alisto_id, producto_id, cant_uds, cant_uom
                             from ent_alisto_linea
                            where alisto_id in (select id from ent_alisto where pedido_id in (%s))""" % ped),
  "ent_alisto_lote": j("""select linea_id, lote, cant_uds, orden from ent_alisto_lote
                           where linea_id in (select l.id from ent_alisto_linea l
                                 join ent_alisto a on a.id=l.alisto_id where a.pedido_id in (%s))""" % ped),
  "ent_pedido_linea": j("""select pedido_id, producto_id, uom_id, uom_nombre, uom_factor, presentacion
                             from ent_pedido_linea where pedido_id in (%s)""" % ped),
}
lec.cerrar()
io.open(os.path.join(os.path.dirname(os.path.abspath(__file__)),"datos.json"),"w",encoding="utf-8").write(
    json.dumps(datos, ensure_ascii=False, indent=1, default=str))
for k,v in datos.items(): print("  %-24s %d filas" % (k, len(v)))
