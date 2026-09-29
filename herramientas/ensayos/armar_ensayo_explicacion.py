#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Arma ENSAYO_TICKETS_EXPLICACION.sql a partir de TICKETS_EXPLICACION.sql.

El bloque DDL se copia BYTE A BYTE del pegado, cortado por sus dos marcas,
nunca por numero de linea (CLAUDE.md, 16-sep). La fila de control del pegado
tambien se copia de ahi, para que el ensayo mida lo MISMO que va a medir el
pegado de verdad.

Cada RECHAZA lleva el SQLSTATE y un pedazo del mensaje, y el `ok` compara los
dos: un rechazo solo vale si rebota por SU razon (la X6 del 24-sep).

Los textos de prueba van con los acentos como codigos (U&'…' UESCAPE '!') y
los saltos de linea con chr(10): el mismo viaje por el portapapeles que podria
romper un acento en el pegado no puede, ademas, "arreglar" el ensayo.

    python3 herramientas/ensayos/armar_ensayo_explicacion.py
"""
import hashlib, os, re, sys

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
PEGADO = os.path.join(RAIZ, 'TICKETS_EXPLICACION.sql')
ENSAYO = os.path.join(RAIZ, 'ENSAYO_TICKETS_EXPLICACION.sql')

txt = open(PEGADO, encoding='utf-8').read()
A, B = '-- ═══ DDL · DESDE ACA', '-- ═══ DDL · HASTA ACA ═══'
if txt.count(A) != 1 or txt.count(B) != 1 or txt.find(B) < txt.find(A):
    sys.exit('no encuentro las dos marcas del bloque DDL, una sola vez cada una')
ddl = txt[txt.find(A):txt.find(B) + len(B)]
for mala in ('begin;', 'commit;', 'rollback;'):
    if re.search(r'^\s*' + mala, ddl, re.M | re.I):
        sys.exit('el bloque DDL trae un %s suelto: no se arma' % mala)
huella = hashlib.md5(ddl.encode('utf-8')).hexdigest()

# La fila de control del pegado: desde su titulo hasta el ';' antes del commit.
K0 = txt.find('-- 🔴 LA PRUEBA DE QUE ENTRO')
K1 = txt.find('\ncommit;', K0)
if K0 < 0 or K1 < 0:
    sys.exit('no encuentro la fila de control del pegado')
control = txt[txt.find('select', K0):K1].strip().rstrip(';')
CONTROL_ESPERADO = '3 · true · true · 2 · true · 1 · 3 · true · true · 0'

GUARDIA, PERMISO, CHECK = 'P0001', '42501', '23514'
P = []
N = [0]

def q(s):
    return "'" + s.replace("'", "''") + "'"

def intento(p, esp, stmt, motivo=None):
    N[0] += 1
    if esp == 'ENTRA':
        assert motivo is None, p
        P.append("""  begin
    %s;
    v_res := v_res || jsonb_build_object('p', %s, 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', %s, 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;""" % (stmt, q(p), q(p)))
        return
    assert esp == 'RECHAZA' and motivo and len(motivo) == 2, p
    estado, frag = motivo
    e = q('RECHAZA · %s · %s' % (estado, frag))
    P.append("""  begin
    %s;
    v_res := v_res || jsonb_build_object('p', %s, 'esperado', %s, 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', %s, 'esperado', %s, 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = %s and strpos(sqlerrm, %s) > 0);
  end;""" % (stmt, q(p), e, q(p), e, q(estado), q(frag)))

def fila(p, esp, obt_sql, ok_sql):
    N[0] += 1
    P.append("  v_res := v_res || jsonb_build_object('p', %s, 'esperado', %s, 'obtenido', %s, 'ok', %s);"
             % (q(p), q(esp), obt_sql, ok_sql))

def com(t):
    P.append('\n  -- ' + t)

def como(quien):
    if quien in ('cc', 'postgres', 'anon'):
        rol = {'cc': 'truefie_cc', 'postgres': 'postgres', 'anon': 'anon'}[quien]
        P.append("  perform set_config('request.jwt.claims', '', true);\n"
                 "  perform set_config('role', '%s', true);" % rol)
    elif quien == 'socia':
        P.append("  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);\n"
                 "  perform set_config('role', 'authenticated', true);")
    else:
        raise ValueError(quien)

# ── los textos, armados en SQL: acentos por codigo, renglones con chr(10) ──
def u(s):
    """Un literal U&'…' UESCAPE '!' con los no-ASCII como !XXXX."""
    cuerpo = ''.join(c if ord(c) < 128 else '!%04X' % ord(c) for c in s.replace("'", "''"))
    return "U&'%s' UESCAPE '!'" % cuerpo

def texto(*renglones):
    return ' || chr(10) || '.join(u(r) for r in renglones)

BUENO1 = texto('Qué es: prueba del ensayo, no queda nada.',
               'Por qué importa: prueba que el formato entra.',
               'Qué haría falta: chico. Nada, es un ensayo.',
               'Recomendación: HACER, prioridad 1.')
BUENO2 = texto('Qué es: segunda prueba del ensayo.',
               'Por qué importa: tiene que ganar la ultima.',
               'Qué haría falta: grande. Nada, es un ensayo.',
               'Recomendación: DESCARTAR.')
SIN_RENGLON = texto('Qué es: le falta el segundo renglon.',
                    'Qué haría falta: chico. Nada.',
                    'Recomendación: HACER.')
POSPONER = texto('Qué es: recomienda algo que no es de tres.',
                 'Por qué importa: posponer lo decide Andrea.',
                 'Qué haría falta: chico. Nada.',
                 'Recomendación: POSPONER.')
ENORME = texto('Qué es: un tamaño que no existe.',
               'Por qué importa: el tamaño es de tres.',
               'Qué haría falta: enorme. Nada.',
               'Recomendación: HACER.')

DET = "insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (%s, %s, %s, %s)"
def det(ticket, clase, texto_sql, firma="'cc-truefie'"):
    return DET % (ticket, q(clase), texto_sql, firma)

PROPIO = 'no existe o no es de Truefie'
FORMA = 'ticket_detalle_explicacion_forma"'
TAMANO = 'ticket_detalle_explicacion_tamano"'
RECOM = 'ticket_detalle_explicacion_recomienda"'
SOCIA = 'lo define una socia'

# ── E1–E7 · truefie_cc y anon ─────────────────────────────────────────────
com('── E1–E6 · como truefie_cc ──')
como('cc')
intento('E1 explicacion bien formada, ticket de Truefie abierto', 'ENTRA', det('v_tv', 'explicacion', BUENO1))
intento('E2 explicacion en un pendiente propio', 'RECHAZA', det('v_tp', 'explicacion', BUENO1), (GUARDIA, PROPIO))
intento('E3 le falta un renglon', 'RECHAZA', det('v_tv', 'explicacion', SIN_RENGLON), (CHECK, FORMA))
intento('E4 recomienda POSPONER', 'RECHAZA', det('v_tv', 'explicacion', POSPONER), (CHECK, RECOM))
intento('E5 tamaño "enorme"', 'RECHAZA', det('v_tv', 'explicacion', ENORME), (CHECK, TAMANO))
intento('E6 truefie_cc escribe "espera"', 'RECHAZA', det('v_tv', 'espera', q('Espera de prueba del ensayo.')), (GUARDIA, SOCIA))
intento('E8a segunda explicacion (tiene que ganar esta)', 'ENTRA', det('v_tv', 'explicacion', BUENO2))
com('── E7 · anon ──')
como('anon')
intento('E7 anon escribe una explicacion', 'RECHAZA', det('v_tv', 'explicacion', BUENO1, firma="'anon'"),
        (PERMISO, 'permission denied for table ticket_detalle'))

# ── E8–E9 · lo que se lee ─────────────────────────────────────────────────
com('── E8–E9 · lo que se lee despues ──')
como('postgres')
P.append("  select en_claro into v_t1 from v_ticket where id = v_tv;")
fila('E8 v_ticket.en_claro devuelve la ULTIMA', 'la segunda (DESCARTAR)',
     "coalesce(replace(v_t1, chr(10), ' / '), '(nada)')",
     "v_t1 = " + BUENO2)
P.append("  select count(*) filter (where que = 'En palabras claras'),\n"
         "         count(*) filter (where que = 'Anuncio' and detalle in (" + BUENO1 + ", " + BUENO2 + "))\n"
         "    into v_x1, v_x2 from v_ticket_historial where ticket_id = v_tv;")
fila('E9 historial: «En palabras claras» · rotuladas «Anuncio»', '2 · 0',
     "v_x1 || ' · ' || v_x2", "v_x1 = 2 and v_x2 = 0")

# ── E10 · que nada de lo que andaba dejo de andar ─────────────────────────
com('── E10 · regresion: lo que ya andaba, sigue igual ──')
como('cc')
intento('E10a truefie_cc: anuncio', 'ENTRA', det('v_tv', 'anuncio', q('Anuncio de prueba del ensayo, no queda.')))
intento('E10b truefie_cc: cierre', 'ENTRA', det('v_tv', 'cierre', q('Cerrado en el ensayo: b73 (e75fa4c).')))
intento('E10c truefie_cc: "criterio"', 'RECHAZA', det('v_tv', 'criterio', q('Criterio de prueba del ensayo.')), (GUARDIA, SOCIA))
como('socia')
P.append("  select en_claro into v_t2 from v_ticket where id = v_tv;")
fila('E10d la socia LEE en_claro (lo que va a pedir la pantalla)', 'la segunda',
     "coalesce(left(replace(v_t2, chr(10), ' / '), 60), '(nada)')", "v_t2 = " + BUENO2)
intento('E10e la socia escribe una explicacion desde la app', 'ENTRA', det('v_tv', 'explicacion', BUENO1, firma='v_socia'))
intento('E10f la socia NO escribe con formato libre', 'RECHAZA',
        det('v_tv', 'explicacion', q('Texto libre, sin los cuatro renglones.'), firma='v_socia'),
        (CHECK, 'violates check constraint "ticket_detalle_explicacion_'))   # choca con los tres: vale cualquiera
como('postgres')
intento('E10g editor SQL (firma cc-sql): explicacion', 'ENTRA', det('v_tv', 'explicacion', BUENO1, firma="'cc-sql-ensayo'"))
intento('E10h editor SQL: "criterio" sigue afuera', 'RECHAZA',
        det('v_tv', 'criterio', q('Criterio de prueba del ensayo.'), firma="'cc-sql-ensayo'"),
        (GUARDIA, 'solo se escriben cierres, anuncios y explicaciones'))
P.append("  select contenido into v_t3 from v_ticket_export where id = v_tv;")
fila('E10i export: la seccion, antes del criterio', '## En palabras claras < ## Criterio de terminado',
     "strpos(v_t3, '## En palabras claras') || ' < ' || strpos(v_t3, '## Criterio de terminado')",
     "strpos(v_t3, '## En palabras claras') > 0 and strpos(v_t3, '## En palabras claras') < strpos(v_t3, '## Criterio de terminado')")
P.append("  select " + control.replace('\n', '\n         ').replace('select\n', '', 1) + "\n    into v_k1, v_k2, v_k3, v_k4, v_k5, v_k6, v_k7, v_k8, v_k9, v_k10;")
fila('E10j la fila de control del pegado', CONTROL_ESPERADO,
     "concat_ws(' · ', v_k1, v_k2, v_k3, v_k4, v_k5, v_k6, v_k7, v_k8, v_k9, v_k10)",
     "concat_ws(' · ', v_k1, v_k2, v_k3, v_k4, v_k5, v_k6, v_k7, v_k8, v_k9, v_k10) = " + q(CONTROL_ESPERADO))

com('── E10k · LA RLS SOLA: se apaga el guardia (se vuelve a prender abajo) ──')
P.append("  alter table ticket_detalle disable trigger ticket_detalle_guard_trg;")
como('cc')
RLS_D = 'new row violates row-level security policy for table "ticket_detalle"'
intento('E10k sin guardia: truefie_cc escribe "espera"', 'RECHAZA',
        det('v_tv', 'espera', q('Espera de prueba del ensayo.')), (PERMISO, RLS_D))
intento('E10l sin guardia: explicacion en un propio', 'RECHAZA', det('v_tp', 'explicacion', BUENO1), (PERMISO, RLS_D))
como('postgres')
P.append("  alter table ticket_detalle enable trigger ticket_detalle_guard_trg;")

n_filas = N[0] + 1
cuerpo = '\n'.join(P)

out = f"""-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_TICKETS_EXPLICACION.sql  ·  29-sep-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- El tipo de detalle 'explicacion' («En palabras claras»)
--
-- ⚠️ ARCHIVO GENERADO. No se edita a mano: se regenera con
--     python3 herramientas/ensayos/armar_ensayo_explicacion.py
--   El bloque DDL es el de TICKETS_EXPLICACION.sql BYTE A BYTE, cortado por
--   sus marcas. md5 del bloque: {huella}
--
-- QUE HACE
--   1. Aplica todo, igual que el pegado (incluido su candado de entrada).
--   2. Le da a `postgres` permiso de ponerse truefie_cc (SOLO para ensayar: se
--      va con el rollback; el pegado no lo trae).
--   3. Prueba como truefie_cc, como anon, como socia (sesion simulada, con RLS)
--      y como el editor SQL. Ningun correo va escrito: la socia sale de
--      v_acceso_usuario. Los tickets se eligen solos: uno abierto de Truefie y
--      uno propio.
--   4. Apaga el guardia un momento para probar que la RLS SOLA frena.
--   5. rollback. No queda nada: ni las filas, ni los CHECK, ni las vistas nuevas.
--
-- ⚠️ E10 NO ES "volver a correr ENSAYO_TICKETS_CC.sql": ese ensayo CREA el rol
--   truefie_cc, y su candado de entrada frena si el rol ya existe (existe desde
--   el 27-sep). E10 repite ADENTRO de este lo que podria haberse roto: cierre y
--   anuncio siguen entrando, criterio sigue afuera, la socia lee y escribe, el
--   editor SQL tambien, y la RLS sola sigue frenando.
--
-- COMO SE LEE
--   Una tabla de {n_filas} filas, TODAS con ok = true. Un RECHAZA da ok solo si
--   el SQLSTATE y el pedazo de mensaje de `esperado` estan en `obtenido`.
--   Si el editor dice "Success. No rows returned", no llego al final y no vale.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

{ddl}


-- ── SOLO PARA ENSAYAR: que el editor pueda ponerse el rol. Se va con el rollback.
grant truefie_cc to postgres with set true, inherit false;


-- ── LAS PRUEBAS ───────────────────────────────────────────────────────────
do $$
declare
  v_socia text;
  v_tv bigint;           -- un ticket de Truefie ABIERTO
  v_tp bigint;           -- un pendiente PROPIO
  v_x1 bigint; v_x2 bigint;
  v_t1 text; v_t2 text; v_t3 text;
  v_k1 text; v_k2 text; v_k3 text; v_k4 text; v_k5 text;
  v_k6 text; v_k7 text; v_k8 text; v_k9 text; v_k10 text;
  v_res jsonb := '[]'::jsonb;
begin
  if not pg_has_role('postgres', 'truefie_cc', 'SET') then
    raise exception 'postgres no puede ponerse truefie_cc: el ensayo no puede probar nada';
  end if;
  select email into v_socia from v_acceso_usuario where perfil = 'socias' and activo order by email limit 1;
  select id into v_tv from v_ticket
   where ambito = 'truefie' and estado not in ('cerrado','pospuesto','descartado') order by id limit 1;
  select id into v_tp from ticket where ambito = 'propio' order by id limit 1;
  if v_socia is null or v_tv is null or v_tp is null then
    raise exception 'falta algo para ensayar (socia %, abierto %, propio %)', v_socia is not null, v_tv, v_tp;
  end if;
{cuerpo}

  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('ensayo.res', v_res::text, true);
  perform set_config('ensayo.tickets', 'abierto T-' || v_tv || ' · propio T-' || v_tp, true);
end $$;


-- ── EL RESULTADO. Esta tabla ES el ensayo. ────────────────────────────────
-- ESPERADO: {n_filas} filas, todas con ok = true.
select r.p as prueba, r.esperado, r.obtenido, r.ok
  from jsonb_to_recordset(current_setting('ensayo.res')::jsonb)
       as r(p text, esperado text, obtenido text, ok boolean)
union all
select 'Z · tickets usados', current_setting('ensayo.tickets'), '', true;

rollback;

-- ── DESPUES DEL ROLLBACK (opcional, con pg_lector) ────────────────────────
-- select count(*) from pg_constraint where conname like 'ticket_detalle_explicacion%';  -> 0
"""
open(ENSAYO, 'w', encoding='utf-8').write(out)
print('escrito', os.path.basename(ENSAYO), '·', n_filas, 'filas (con la Z de contexto) · md5 DDL', huella)
