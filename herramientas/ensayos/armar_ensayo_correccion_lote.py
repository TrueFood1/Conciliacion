#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Arma ENSAYO_CORRECCION_LOTE.sql a partir de ENTREGAS_CORRECCION_LOTE.sql.

El bloque DDL se copia BYTE A BYTE del pegado, cortado por sus dos marcas
(`═══ DDL · DESDE ACA` y `═══ DDL · HASTA ACA ═══`), nunca por numero de
linea (CLAUDE.md, 16-sep). Asi el ensayo prueba exactamente lo que se va a
pegar, y si alguien toca el pegado, se vuelve a correr esto y listo.

    python3 herramientas/ensayos/armar_ensayo_correccion_lote.py
"""
import hashlib, os, re, sys

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
PEGADO = os.path.join(RAIZ, 'ENTREGAS_CORRECCION_LOTE.sql')
ENSAYO = os.path.join(RAIZ, 'ENSAYO_CORRECCION_LOTE.sql')

txt = open(PEGADO, encoding='utf-8').read()
i = txt.find('-- ═══ DDL · DESDE ACA')
j = txt.find('-- ═══ DDL · HASTA ACA ═══')
if i < 0 or j < 0 or j < i or txt.count('-- ═══ DDL · DESDE ACA') != 1 or txt.count('-- ═══ DDL · HASTA ACA ═══') != 1:
    sys.exit('no encuentro las dos marcas del bloque DDL, una sola vez cada una')
j += len('-- ═══ DDL · HASTA ACA ═══')
ddl = txt[i:j]
for mala in ('begin;', 'commit;', 'rollback;'):
    if re.search(r'^\s*' + mala, ddl, re.M | re.I):
        sys.exit('el bloque DDL trae un %s suelto: no se arma' % mala)
huella = hashlib.md5(ddl.encode('utf-8')).hexdigest()

P = []   # las pruebas, en orden

def fila(p, esp, obt_sql, ok_sql):
    P.append("  v_res := v_res || jsonb_build_object('p', %s, 'esperado', %s, 'obtenido', %s, 'ok', %s);"
             % (q(p), q(esp), obt_sql, ok_sql))

def q(s):
    return "'" + s.replace("'", "''") + "'"

def intento(p, esp, stmt):
    """Un insert/update/delete en su propio savepoint. ENTRA o RECHAZA."""
    P.append("""  begin
    %s;
    v_res := v_res || jsonb_build_object('p', %s, 'esperado', %s, 'obtenido', 'ENTRA', 'ok', %s);
  exception when others then
    v_res := v_res || jsonb_build_object('p', %s, 'esperado', %s, 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', %s);
  end;""" % (stmt, q(p), q(esp), 'true' if esp == 'ENTRA' else 'false',
             q(p), q(esp), 'true' if esp == 'RECHAZA' else 'false'))

def com(t):
    P.append('\n  -- ' + t)

def como(quien):
    P.append("  perform set_config('request.jwt.claims', json_build_object('email', %s, 'role', 'authenticated')::text, true);" % quien)

INS = ("insert into ent_conteo_correccion (conteo_id, producto_id, lote_origen, lote_destino, uds, "
       "contado_por, contado_en, motivo%s) values (%s, 452, %s, %s, %s, 'Daniel', %s, %s%s)")

def ins(origen, destino, uds, motivo="'ensayo'", conteo='v_anc', fecha='v_hoy', extra_cols='', extra_vals='', ret=''):
    return INS % (extra_cols, conteo, q(origen), q(destino), uds, fecha, motivo, extra_vals) + ret

# ── A · SIN SESION ─────────────────────────────────────────────────────────
com('── A · SIN SESION (todavia como postgres) ──')
intento('A1 sin sesion · 245→247 30 u', 'RECHAZA', ins('245 / 6-27', '247 / 6-27', 30))

# ── T · EL CASO REAL ───────────────────────────────────────────────────────
com('── T · EL CASO REAL, como socia. De aca en adelante la RLS aplica. ──')
como('v_socia')
P.append("  perform set_config('role', 'authenticated', true);")
com('T0 · el terreno: si esto no da, los datos se movieron y R1/R2 no aplican')
P.append("""  select a.ancla, a.salidas, b.ancla, b.salidas into v_x1, v_x2, v_x3, v_x4
    from ent_conteo_lote_neto(v_anc, 452, '245 / 6-27') a, ent_conteo_lote_neto(v_anc, 452, '247 / 6-27') b;""")
fila('T0 terreno · 245 ancla·salidas / 247 ancla·salidas', '114 · 78 / 12 · 12',
     "v_x1 || ' · ' || v_x2 || ' / ' || v_x3 || ' · ' || v_x4",
     "(v_x1, v_x2, v_x3, v_x4) = (114, 78, 12, 12)")
P.append("""  select sum(n.ancla_corregida), sum(n.saldo_visible) into v_tot_a0, v_tot_s0
    from (select lote from ent_conteo_linea where conteo_id = v_anc and producto_id = 452
          union select lote_destino from ent_conteo_correccion_vigente where conteo_id = v_anc and producto_id = 452) l,
         lateral ent_conteo_lote_neto(v_anc, 452, l.lote) n;""")
intento('T1 socia · 245→247 30 u (5 cajas), contó Daniel', 'ENTRA',
        ins('245 / 6-27', '247 / 6-27', 30,
            motivo="'Cinco cajas de 247 anotadas como 245 en el conteo del 10-sep'",
            ret=' returning id into v_t1'))
P.append("  select n.ancla_corregida, n.saldo_visible into v_x1, v_x2 from ent_conteo_lote_neto(v_anc, 452, '245 / 6-27') n;")
fila('R1 · 245 ancla corregida · saldo', '84 · 6  (14 cajas · 1 caja)',
     "v_x1 || ' · ' || v_x2", "(v_x1, v_x2) = (84, 6)")
P.append("  select n.ancla_corregida, n.saldo_visible into v_x1, v_x2 from ent_conteo_lote_neto(v_anc, 452, '247 / 6-27') n;")
fila('R2 · 247 ancla corregida · saldo', '42 · 30  (7 cajas · 5 cajas)',
     "v_x1 || ' · ' || v_x2", "(v_x1, v_x2) = (42, 30)")
P.append("""  select sum(n.ancla_corregida), sum(n.saldo_visible) into v_tot_a1, v_tot_s1
    from (select lote from ent_conteo_linea where conteo_id = v_anc and producto_id = 452
          union select lote_destino from ent_conteo_correccion_vigente where conteo_id = v_anc and producto_id = 452) l,
         lateral ent_conteo_lote_neto(v_anc, 452, l.lote) n;""")
fila('R3 · total Semillas, ancla y saldo, antes → después', 'no cambia',
     "'ancla ' || v_tot_a0 || '→' || v_tot_a1 || ' · saldo ' || v_tot_s0 || '→' || v_tot_s1",
     "v_tot_a0 = v_tot_a1 and v_tot_s0 = v_tot_s1")
P.append("  select autorizado_por = v_socia into v_b from ent_conteo_correccion where id = v_t1;")
fila('R4 · autorizado_por sale de la sesion', 'la socia de la sesion',
     "case when v_b then 'la socia de la sesion' else 'OTRO' end", "coalesce(v_b, false)")

# ── N · LAS GUARDAS ────────────────────────────────────────────────────────
com('── N · LAS GUARDAS ──')
como('v_equipo')
intento('N1 equipo · 252→244 1 u', 'RECHAZA', ins('252 / 6-27', '244 / 3-27', 1))
como('v_socia')
intento('N2 origen fuera del ancla (999 / 1-27)', 'RECHAZA', ins('999 / 1-27', '247 / 6-27', 1))
intento('N3 origen = destino', 'RECHAZA', ins('252 / 6-27', '252 / 6-27', 1))
intento('N4 cantidad 0', 'RECHAZA', ins('252 / 6-27', '244 / 3-27', 0))
intento('N5 245 queda negativo (saldo 6, mover 7)', 'RECHAZA', ins('245 / 6-27', '247 / 6-27', 7))
intento('N6 destino fuera del ancla SIN huella', 'RECHAZA', ins('252 / 6-27', '250 / 6-27', 6))
intento('N7 destino fuera del ancla, huella de OTRO producto', 'RECHAZA',
        ins('252 / 6-27', '250 / 6-27', 6, extra_cols=', destino_orden_id, destino_orden, destino_producto_id',
            extra_vals=", 99999999, 'WH/MO/ENSAYO', 451"))
intento('N8 destino fuera del ancla, huella completa', 'ENTRA',
        ins('252 / 6-27', '250 / 6-27', 6, extra_cols=', destino_orden_id, destino_orden, destino_producto_id',
            extra_vals=", 99999999, 'WH/MO/ENSAYO', 452", ret=' returning id into v_n8'))
intento('N9 huella a medias (sin nombre de orden)', 'RECHAZA',
        ins('252 / 6-27', '250 / 6-27', 1, extra_cols=', destino_orden_id, destino_producto_id',
            extra_vals=", 99999999, 452"))
intento('N10 sobre un conteo que no es el ancla', 'RECHAZA', ins('252 / 6-27', '244 / 3-27', 1, conteo='v_otro'))
intento('N11 motivo en blanco', 'RECHAZA', ins('252 / 6-27', '244 / 3-27', 1, motivo="'   '"))
intento('N12 motivo de 1 caracter (sin minimo)', 'ENTRA', ins('252 / 6-27', '244 / 3-27', 1, motivo="'x'"))
intento('N13 autorizado_por de otra persona', 'RECHAZA',
        ins('252 / 6-27', '244 / 3-27', 1, extra_cols=', autorizado_por', extra_vals=', v_equipo'))
intento('N14 fecha del recuento mañana', 'RECHAZA', ins('252 / 6-27', '244 / 3-27', 1, fecha='v_hoy + 1'))
intento('N15 editar una correccion (update)', 'RECHAZA',
        "update ent_conteo_correccion set motivo = 'otro' where id = v_t1")
intento('N16 borrar una correccion (delete)', 'RECHAZA',
        "delete from ent_conteo_correccion where id = v_t1")

# ── X · ANULAR ─────────────────────────────────────────────────────────────
com('── X · ANULAR ──')
intento('X1 socia anula la del N8 (250 no se usó)', 'ENTRA',
        "insert into ent_conteo_correccion_anulacion (correccion_id, motivo) values (v_n8, 'ensayo')")
P.append("  select count(*) into v_x1 from ent_conteo_correccion_vigente where id = v_n8;")
P.append("  select n.ancla_corregida into v_x2 from ent_conteo_lote_neto(v_anc, 452, '250 / 6-27') n;")
fila('X2 · la anulada sale de la vista y el 250 vuelve a 0', '0 filas · 250 en 0',
     "v_x1 || ' filas · 250 en ' || v_x2", "v_x1 = 0 and v_x2 = 0")
intento('X3 anularla otra vez', 'RECHAZA',
        "insert into ent_conteo_correccion_anulacion (correccion_id, motivo) values (v_n8, 'ensayo')")
intento('X4 mover las 30 u del 247 al 252 (247 queda en 0)', 'ENTRA', ins('247 / 6-27', '252 / 6-27', 30))
intento('X5 anular la T1: el 247 quedaria en −30', 'RECHAZA',
        "insert into ent_conteo_correccion_anulacion (correccion_id, motivo) values (v_t1, 'ensayo')")
intento('X6 anular sin motivo', 'RECHAZA',
        "insert into ent_conteo_correccion_anulacion (correccion_id, motivo) values (v_t1, '')")
como('v_equipo')
intento('X7 equipo anula', 'RECHAZA',
        "insert into ent_conteo_correccion_anulacion (correccion_id, motivo) values (v_t1, 'ensayo')")
como('v_socia')
intento('X8 editar una anulacion (delete)', 'RECHAZA',
        "delete from ent_conteo_correccion_anulacion where correccion_id = v_n8")

# ── P · PERMISOS DE anon ───────────────────────────────────────────────────
com('── P · anon no toca nada ──')
P.append("""  select count(*) into v_x1 from unnest(array['public.ent_conteo_correccion',
      'public.ent_conteo_correccion_anulacion', 'public.ent_conteo_correccion_vigente']) t
   where has_table_privilege('anon', t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE');
  select count(*) into v_x2 from unnest(array['public.ent_conteo_lote_neto(bigint,integer,text)',
      'public.ent_conteo_correccion_guard()', 'public.ent_conteo_correccion_anulacion_guard()']) f
   where has_function_privilege('anon', f, 'EXECUTE');""")
fila('P1 · anon: tablas con algun permiso · funciones con EXECUTE', '0 · 0',
     "v_x1 || ' · ' || v_x2", "v_x1 = 0 and v_x2 = 0")

n_filas = sum(1 for x in P if "jsonb_build_object('p'" in x)

cuerpo = '\n'.join(P)
out = f"""-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_CORRECCION_LOTE.sql  ·  24-sep-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Correcciones de conteo por lote · Paso A
--
-- ⚠️ ARCHIVO GENERADO. No se edita a mano: se regenera con
--     python3 herramientas/ensayos/armar_ensayo_correccion_lote.py
--   El bloque DDL de abajo es el de ENTREGAS_CORRECCION_LOTE.sql BYTE A BYTE,
--   cortado por sus marcas. md5 del bloque: {huella}
--
-- QUE HACE
--   1. Crea todo, igual que el pegado.
--   2. Prueba sin sesion, como socia y como equipo (sesion simulada con
--      `request.jwt.claims` + `set local role authenticated`, o sea CON RLS).
--      Las identidades salen de `v_acceso_usuario`; ningun correo va escrito
--      aca porque el repo es publico.
--   3. El caso real del ticket 30: 30 u (5 cajas) de Semillas 245 -> 247.
--   4. rollback. No queda nada.
--
-- COMO SE LEE
--   Una tabla de {n_filas} filas, TODAS con ok = true. Si el editor dice
--   "Success. No rows returned", no llego al final y no vale.
--   Si T0 no da, los datos se movieron desde el 24-sep (una salida nueva de
--   245 o 247): R1 y R2 dejan de aplicar tal cual y hay que volver a medir.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

{ddl}


-- ── LAS PRUEBAS ───────────────────────────────────────────────────────────
do $$
declare
  v_socia  text;
  v_equipo text;
  v_anc    bigint;
  v_otro   bigint;
  v_hoy    date := (now() at time zone 'America/Costa_Rica')::date;
  v_t1     bigint;
  v_n8     bigint;
  v_x1 numeric; v_x2 numeric; v_x3 numeric; v_x4 numeric;
  v_tot_a0 numeric; v_tot_s0 numeric; v_tot_a1 numeric; v_tot_s1 numeric;
  v_b      boolean;
  v_res    jsonb := '[]'::jsonb;
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by email limit 1;
  select email into v_equipo from v_acceso_usuario where perfil = 'equipo' and activo order by email limit 1;
  select id into v_anc from ent_ancla;
  select max(id) into v_otro from ent_conteo where id <> v_anc;
  if v_socia is null or v_equipo is null or v_anc is null or v_otro is null then
    raise exception 'falta algo para ensayar (socia %, equipo %, ancla %, otro conteo %)',
      v_socia is not null, v_equipo is not null, v_anc, v_otro;
  end if;
{cuerpo}

  perform set_config('ensayo.res', v_res::text, true);
end $$;


-- ── EL RESULTADO. Esta tabla ES el ensayo. ────────────────────────────────
-- ESPERADO: {n_filas} filas, todas con ok = true.
select r.p as prueba, r.esperado, r.obtenido, r.ok
  from jsonb_to_recordset(current_setting('ensayo.res')::jsonb)
       as r(p text, esperado text, obtenido text, ok boolean);

rollback;

-- ── DESPUES DEL ROLLBACK (opcional, con pg_lector) ────────────────────────
-- select to_regclass('public.ent_conteo_correccion');   -> NULL: el ensayo no dejo nada.
"""
open(ENSAYO, 'w', encoding='utf-8').write(out)
print('escrito', os.path.basename(ENSAYO), '·', n_filas, 'filas de prueba · md5 DDL', huella)
