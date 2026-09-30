#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Arma ENSAYO_TICKETS_CC.sql a partir de TICKETS_CC.sql.

El bloque DDL se copia BYTE A BYTE del pegado, cortado por sus dos marcas,
nunca por numero de linea (CLAUDE.md, 16-sep).

Cada RECHAZA lleva el SQLSTATE y un pedazo del mensaje, y el `ok` compara los
dos: un rechazo solo vale si rebota por SU razon (la X6 del 24-sep).

    python3 herramientas/ensayos/armar_ensayo_tickets_cc.py
"""
import hashlib, os, re, sys

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
PEGADO = os.path.join(RAIZ, 'TICKETS_CC.sql')
ENSAYO = os.path.join(RAIZ, 'ENSAYO_TICKETS_CC.sql')

txt = open(PEGADO, encoding='utf-8').read()
A, B = '-- ═══ DDL · DESDE ACA', '-- ═══ DDL · HASTA ACA ═══'
if txt.count(A) != 1 or txt.count(B) != 1 or txt.find(B) < txt.find(A):
    sys.exit('no encuentro las dos marcas del bloque DDL, una sola vez cada una')
ddl = txt[txt.find(A):txt.find(B) + len(B)]
for mala in ('begin;', 'commit;', 'rollback;'):
    if re.search(r'^\s*' + mala, ddl, re.M | re.I):
        sys.exit('el bloque DDL trae un %s suelto: no se arma' % mala)
huella = hashlib.md5(ddl.encode('utf-8')).hexdigest()

GUARDIA, PERMISO = 'P0001', '42501'
P = []
N = [0]   # filas de resultado: una por intento() y una por fila()

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
    if quien == 'cc':
        P.append("  perform set_config('request.jwt.claims', '', true);\n"
                 "  perform set_config('role', 'truefie_cc', true);")
    elif quien == 'postgres':
        P.append("  perform set_config('request.jwt.claims', '', true);\n"
                 "  perform set_config('role', 'postgres', true);")
    elif quien == 'socia':
        P.append("  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);\n"
                 "  perform set_config('role', 'authenticated', true);")
    else:
        raise ValueError(quien)

EST = "insert into ticket_estado (ticket_id, estado, creado_por%s) values (%s, %s, %s%s)"
def est(ticket, estado, firma="'cc-truefie'", nota=None, build=None):
    cols, vals = '', ''
    if nota is not None:
        cols += ', nota'; vals += ', ' + nota
    if build is not None:
        cols += ', build_arreglo'; vals += ', ' + build
    return EST % (cols, ticket, q(estado), firma, vals)

DET = "insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (%s, %s, %s, %s)"
def det(ticket, clase, texto='Cerrado en el ensayo: b72 (65ac781).', firma="'cc-truefie'"):
    return DET % (ticket, q(clase), q(texto), firma)

EVID = "'Resuelto en b72 (65ac781): prueba del ensayo'"
NO_EVID = "'truefie_cc no ve el ticket'"
PROPIO = 'no existe o no es de Truefie'

# ── V · QUE VE ─────────────────────────────────────────────────────────────
com('── V · QUE VE truefie_cc: todos los de Truefie, ningun propio ──')
como('cc')
P.append("  select count(*), count(*) filter (where ambito = 'propio') into v_x1, v_x2 from ticket;")
fila('V1 · tickets que ve · de ellos propios', 'todos los de truefie · 0 propios',
     "v_x1 || ' (truefie: ' || v_n_truefie || ') · ' || v_x2 || ' propios'",
     "v_x1 = v_n_truefie and v_x2 = 0")

# ── R · LAS REGLAS DEL GUARDIA ─────────────────────────────────────────────
com('── R · LAS REGLAS: cada una rebota por SU motivo, sobre un ticket que si podria moverse ──')
intento('R1 cerrar sin nota', 'RECHAZA', est('v_tv', 'cerrado'),
        (GUARDIA, 'cerrar sin evidencia no'))
intento('R2 cerrar con nota sin build ni commit', 'RECHAZA',
        est('v_tv', 'cerrado', nota="'Listo, ya quedó resuelto.'"),
        (GUARDIA, 'cerrar sin evidencia no'))
intento('R3 cerrar con la evidencia en dos lineas', 'RECHAZA',
        est('v_tv', 'cerrado', nota="'Resuelto en b72' || chr(10) || '(65ac781)'"),
        (GUARDIA, 'va en UNA linea'))
intento('R4 cerrar con build_arreglo mal escrito', 'RECHAZA',
        est('v_tv', 'cerrado', nota=EVID, build="'72'"),
        (GUARDIA, 'build_arreglo es un build como'))
intento('R5 descartar', 'RECHAZA', est('v_tv', 'descartado', nota=EVID),
        (GUARDIA, 'no pone "descartado"'))
intento('R6 posponer', 'RECHAZA', est('v_tv', 'pospuesto', nota=EVID),
        (GUARDIA, 'no pone "pospuesto"'))
intento('R7 firmar como cc-sql', 'RECHAZA', est('v_tv', 'en_curso', firma="'cc-sql'"),
        (GUARDIA, 'firma creado_por = "cc-truefie"'))
intento('R8 mover un pendiente propio', 'RECHAZA', est('v_tp', 'en_curso'),
        (GUARDIA, PROPIO))
intento('R9 mover uno que Andrea pospuso o descarto', 'RECHAZA', est('v_tc', 'disponible'),
        (GUARDIA, 'lo reabre Andrea'))
intento('R10 detalle "criterio"', 'RECHAZA', det('v_tv', 'criterio', 'Criterio de prueba del ensayo.'),
        (GUARDIA, 'solo escribe cierres y anuncios'))
intento('R11 detalle en un pendiente propio', 'RECHAZA', det('v_tp', 'cierre'),
        (GUARDIA, PROPIO))

# ── N · NADA MAS LE ES ACCESIBLE ───────────────────────────────────────────
com('── N · NADA MAS: ni editar, ni borrar, ni leer otra cosa ──')
def no(p, stmt, objeto):
    intento(p, 'RECHAZA', stmt, (PERMISO, 'permission denied for ' + objeto))
no('N1 update de ticket_estado', "update ticket_estado set nota = 'x' where ticket_id = v_tv", 'table ticket_estado')
no('N2 delete de ticket_estado', 'delete from ticket_estado where ticket_id = v_tv', 'table ticket_estado')
no('N3 truncate de ticket_estado', 'truncate ticket_estado', 'table ticket_estado')
no('N4 update de ticket', "update ticket set descripcion = 'x' where id = v_tv", 'table ticket')
no('N5 crear un ticket', "insert into ticket (descripcion, tipo, ambito, creado_por) values ('prueba del ensayo', 'duda', 'truefie', 'cc-truefie')", 'table ticket')
no('N6 marcar (ticket_marca)', "insert into ticket_marca (ticket_id, toca_numeros, escribe_en_base, prioridad, bloquea_entrega, razon, creado_por) values (v_tv, false, false, 'baja', false, 'prueba del ensayo, no va', 'cc-truefie')", 'table ticket_marca')
no('N7 leer ticket_detalle', 'perform count(*) from ticket_detalle', 'table ticket_detalle')
no('N8 leer v_ticket', 'perform count(*) from v_ticket', 'view v_ticket')
no('N9 leer acceso_usuario', 'perform count(*) from acceso_usuario', 'table acceso_usuario')
no('N10 leer ent_pedido', 'perform count(*) from ent_pedido', 'table ent_pedido')
no('N11 escribir revision_unidades', "insert into revision_unidades (creado_por) values ('ticket-sql-unidades')", 'table revision_unidades')
no('N12 ejecutar acceso_es_socia()', 'perform acceso_es_socia()', 'function acceso_es_socia')

# ── C · EL CAMINO BUENO ────────────────────────────────────────────────────
com('── C · EL CAMINO BUENO: tomarlo, cerrarlo con evidencia, dejar el cierre ──')
intento('C1 ponerlo en_curso', 'ENTRA', est('v_tv', 'en_curso'))
intento('C2 cerrar con evidencia en una linea', 'ENTRA', est('v_tv', 'cerrado', nota=EVID, build="'b72'"))
intento('C3 detalle "cierre"', 'ENTRA', det('v_tv', 'cierre'))
intento('C4 volver a tocarlo ya cerrado', 'RECHAZA', est('v_tv', 'disponible'),
        (GUARDIA, 'lo reabre Andrea'))
como('postgres')
P.append("""  select h.que, h.quien, h.build_arreglo into v_t1, v_t2, v_t3
    from v_ticket_historial h where h.ticket_id = v_tv and h.que = 'Cerrado'
   order by h.cuando desc limit 1;""")
fila('C5 · en el historial', 'Cerrado · cc-truefie · b72',
     "coalesce(v_t1, '(nada)') || ' · ' || coalesce(v_t2, '') || ' · ' || coalesce(v_t3, '')",
     "v_t1 = 'Cerrado' and v_t2 = 'cc-truefie' and v_t3 = 'b72'")

# ── A · ANDREA REABRE, Y NADIE MAS PUEDE USAR LA FIRMA ─────────────────────
com('── A · Andrea reabre desde la app (sesion de socia, con RLS) ──')
como('socia')
intento('A1 la socia lo reabre (disponible)', 'ENTRA', est('v_tv', 'disponible', firma='v_socia'))
intento('A2 la socia NO puede firmar como cc-truefie', 'RECHAZA', est('v_tv', 'en_curso'),
        (GUARDIA, 'La firma no se elige'))
como('postgres')
intento('A3 el editor SQL NO puede firmar como cc-truefie', 'RECHAZA', est('v_tv', 'en_curso'),
        (GUARDIA, 'empezando con "cc-sql"'))
como('cc')
intento('A4 reabierto, truefie_cc puede volver a tomarlo', 'ENTRA', est('v_tv', 'en_curso'))

# ── L · LA SEGUNDA CAPA SOLA ───────────────────────────────────────────────
com('── L · LA RLS SOLA: se apagan los dos guardias (se vuelven a prender abajo) ──')
como('postgres')
P.append("  alter table ticket_estado  disable trigger ticket_estado_guard_trg;\n"
         "  alter table ticket_detalle disable trigger ticket_detalle_guard_trg;")
como('cc')
RLS_E = 'new row violates row-level security policy for table "ticket_estado"'
RLS_D = 'new row violates row-level security policy for table "ticket_detalle"'
intento('L1 sin guardia: mover un propio', 'RECHAZA', est('v_tp', 'en_curso'), (PERMISO, RLS_E))
intento('L2 sin guardia: descartar', 'RECHAZA', est('v_tv', 'descartado', nota=EVID), (PERMISO, RLS_E))
intento('L3 sin guardia: firmar como cc-sql', 'RECHAZA', est('v_tv', 'en_curso', firma="'cc-sql'"), (PERMISO, RLS_E))
intento('L4 sin guardia: detalle "criterio"', 'RECHAZA', det('v_tv', 'criterio', 'Criterio de prueba del ensayo.'), (PERMISO, RLS_D))
como('postgres')
P.append("  alter table ticket_estado  enable trigger ticket_estado_guard_trg;\n"
         "  alter table ticket_detalle enable trigger ticket_detalle_guard_trg;")

n_filas = N[0] + 1   # + la fila Z de contexto
cuerpo = '\n'.join(P)

out = f"""-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_TICKETS_CC.sql  ·  27-sep-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- El rol truefie_cc y sus dos guardias (que CC cierre tickets de Truefie)
--
-- ⚠️ ARCHIVO GENERADO. No se edita a mano: se regenera con
--     python3 herramientas/ensayos/armar_ensayo_tickets_cc.py
--   El bloque DDL es el de TICKETS_CC.sql BYTE A BYTE, cortado por sus
--   marcas. md5 del bloque: {huella}
--
-- QUE HACE
--   1. Crea todo, igual que el pegado.
--   2. Le da a `postgres` permiso de ponerse el rol (SOLO para ensayar: se va
--      con el rollback; el pegado no lo trae).
--   3. Prueba como truefie_cc, como socia (sesion simulada, con RLS) y como
--      el editor SQL. Ningun correo va escrito: la socia sale de
--      v_acceso_usuario. Los tickets de prueba se eligen solos: uno abierto de
--      Truefie, uno propio, y uno de Truefie que Andrea pospuso o descarto.
--   4. Apaga los dos guardias un momento para probar que la RLS SOLA frena.
--   5. rollback. No queda nada: ni el rol, ni las filas.
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
  v_tc bigint;           -- uno de Truefie que Andrea pospuso o descarto
  v_n_truefie bigint;
  v_x1 bigint; v_x2 bigint;
  v_t1 text; v_t2 text; v_t3 text;
  v_res jsonb := '[]'::jsonb;
begin
  if not pg_has_role('postgres', 'truefie_cc', 'SET') then
    raise exception 'postgres no puede ponerse truefie_cc: el ensayo no puede probar nada';
  end if;
  select email into v_socia from v_acceso_usuario where perfil = 'socias' and activo order by email limit 1;
  select id into v_tv from v_ticket
   where ambito = 'truefie' and estado not in ('cerrado','pospuesto','descartado') order by id limit 1;
  select id into v_tp from ticket where ambito = 'propio' order by id limit 1;
  select id into v_tc from v_ticket
   where ambito = 'truefie' and estado in ('pospuesto','descartado') order by id limit 1;
  select count(*) into v_n_truefie from ticket where ambito = 'truefie';
  if v_socia is null or v_tv is null or v_tp is null or v_tc is null then
    raise exception 'falta algo para ensayar (socia %, abierto %, propio %, pospuesto/descartado %)',
      v_socia is not null, v_tv, v_tp, v_tc;
  end if;
{cuerpo}

  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('ensayo.res', v_res::text, true);
  perform set_config('ensayo.tickets', 'abierto T-' || v_tv || ' · propio T-' || v_tp || ' · pospuesto/descartado T-' || v_tc, true);
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
-- select count(*) from pg_roles where rolname = 'truefie_cc';   -> 0: no dejo nada.
"""
open(ENSAYO, 'w', encoding='utf-8').write(out)
print('escrito', os.path.basename(ENSAYO), '·', n_filas, 'filas (con la Z de contexto) · md5 DDL', huella)
