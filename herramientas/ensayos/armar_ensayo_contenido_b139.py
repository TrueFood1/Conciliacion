#!/usr/bin/env python3
"""Arma ENSAYO_CONTENIDO_B139.sql: el bloque DDL se COPIA de CAMBIO_CONTENIDO_B139.sql (entre el único
`begin;` y `-- Control:`), así el ensayo no puede probar otra cosa que lo que se va a pegar. Las pruebas
viven en pruebas_contenido_b139_cuerpo.sql. Uso: python3 herramientas/ensayos/armar_ensayo_contenido_b139.py"""
import os, sys
R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
src = open(os.path.join(R, 'CAMBIO_CONTENIDO_B139.sql'), encoding='utf-8').read()
if src.count('\nbegin;\n') != 1 or src.count('\ncommit;\n') != 1 or 'rollback' in src:
    sys.exit('CAMBIO_CONTENIDO_B139.sql tiene que tener UN begin, UN commit y cero rollback')
ddl = src.split('\nbegin;\n', 1)[1].split('\n-- Control:', 1)[0].rstrip() + '\n'
cuerpo = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pruebas_contenido_b139_cuerpo.sql'), encoding='utf-8').read()
cab = """-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_CONTENIDO_B139.sql  ·  27-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Prueba los CHECK nuevos del banco, la migración de categorías y el bucket `contenido-miniaturas`
-- con sus políticas de CAMBIO_CONTENIDO_B139.sql, y lo deshace todo (rollback).
-- Armado por herramientas/ensayos/armar_ensayo_contenido_b139.py: el bloque DDL es COPIA EXACTA de
-- CAMBIO_CONTENIDO_B139.sql. Si se cambia aquél, se vuelve a armar éste; no se edita a mano.
-- ⏳ NO CORRIDO EN PRODUCCIÓN. Corrido en Postgres local (37/37 ok, 27-oct) (respaldo del 23-oct con su
--    esquema storage, + CONTENIDO.sql y la semilla; permisos por defecto de producción y los de Supabase
--    sobre storage.objects/buckets a mano: el respaldo no trae privilegios).
--
-- CÓMO SE LEE
--   Una tabla con TODAS las filas en ok = true. Un RECHAZA da ok solo si el SQLSTATE esperado es
--   el que salió (no vale rechazar por el motivo de al lado). Si el editor dice "Success. No rows
--   returned", no llegó al final y no vale.
--   42501 = RLS, sin permiso o borrado directo de Storage · 23514 = check.
--   ⚠️ Prueba la BASE, no la API de Storage: el tamaño (1 MB) y el tipo (image/jpeg) del bucket los
--   frena la API, y eso solo se ve subiendo desde la pantalla.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼ tres filas con las categorías viejas, para ver que la migración las mueve (ids inventados) ▼
insert into public.contenido_banco (drive_id, nombre, tipo, categoria, creado_por) values
  ('1EnsayoB139Fabrica000000000000aa', 'ensayo-fabrica.jpg', 'foto', 'fabrica', 'ensayo'),
  ('1EnsayoB139PuntoVenta0000000000aa', 'ensayo-punto.jpg', 'foto', 'punto_de_venta', 'ensayo'),
  ('1EnsayoB139Otro0000000000000000aa', 'ensayo-otro.jpg', 'foto', 'otro', 'ensayo');

-- ▼▼▼ BLOQUE DDL (copia de CAMBIO_CONTENIDO_B139.sql, sin begin/commit ni el control) ▼▼▼
"""
out = (cab + ddl + '-- ▲▲▲ FIN BLOQUE DDL ▲▲▲\n\n' + cuerpo.rstrip() + '\n'
       + '-- ESPERADO: 37 filas (35 sin el asistente), todas ok = true.\n\n'
       + 'rollback;\n')
assert out.count('\nbegin;\n') == 1 and out.count('commit;') == 0 and out.rstrip().endswith('rollback;')
open(os.path.join(R, 'ENSAYO_CONTENIDO_B139.sql'), 'w', encoding='utf-8').write(out)
print('ENSAYO_CONTENIDO_B139.sql armado ·', out.count('\n'), 'líneas')
