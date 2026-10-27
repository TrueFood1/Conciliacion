#!/usr/bin/env python3
"""Arma ENSAYO_CONTENIDO.sql: el bloque DDL se COPIA de CONTENIDO.sql (entre el único `begin;` y
`-- Control:`), así el ensayo no puede probar otra cosa que lo que se va a pegar. Las pruebas
viven en pruebas_contenido_cuerpo.sql. Uso: python3 herramientas/ensayos/armar_ensayo_contenido.py"""
import os, re, sys
R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
src = open(os.path.join(R, 'CONTENIDO.sql'), encoding='utf-8').read()
if src.count('\nbegin;\n') != 1 or src.count('\ncommit;\n') != 1 or 'rollback' in src:
    sys.exit('CONTENIDO.sql tiene que tener UN begin, UN commit y cero rollback')
ddl = src.split('\nbegin;\n', 1)[1].split('\n-- Control:', 1)[0].rstrip() + '\n'
cuerpo = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pruebas_contenido_cuerpo.sql'), encoding='utf-8').read()
cab = """-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_CONTENIDO.sql  ·  27-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Prueba las tablas, vistas y políticas de CONTENIDO.sql y lo deshace todo (rollback).
-- Armado por herramientas/ensayos/armar_ensayo_contenido.py: el bloque DDL es COPIA EXACTA de
-- CONTENIDO.sql. Si se cambia aquél, se vuelve a armar éste; no se edita a mano.
-- ⏳ NO CORRIDO EN PRODUCCIÓN. Corrido en Postgres local (esquema público del respaldo del 23-oct, sin
--    datos, con los dos event triggers de producción y los permisos por defecto de producción).
--
-- CÓMO SE LEE
--   Una tabla con TODAS las filas en ok = true. Un RECHAZA da ok solo si el SQLSTATE esperado es
--   el que salió (no vale rechazar por el motivo de al lado). Si el editor dice "Success. No rows
--   returned", no llegó al final y no vale.
--   42501 = RLS o sin permiso · 23514 = check · 23505 = repetido.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE DDL (copia de CONTENIDO.sql, sin begin/commit ni el control) ▼▼▼
"""
out = (cab + ddl + '-- ▲▲▲ FIN BLOQUE DDL ▲▲▲\n\n' + cuerpo.rstrip() + '\n'
       + '-- ESPERADO: 50 filas (49 sin una segunda socia activa, 48 sin además el asistente), todas ok = true.\n\n'
       + 'rollback;\n')
assert out.count('\nbegin;\n') == 1 and out.count('commit;') == 0 and out.rstrip().endswith('rollback;')
open(os.path.join(R, 'ENSAYO_CONTENIDO.sql'), 'w', encoding='utf-8').write(out)
print('ENSAYO_CONTENIDO.sql armado ·', out.count('\n'), 'líneas')
