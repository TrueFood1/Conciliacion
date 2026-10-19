#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Arma ENSAYO_CONT_BARRIDO_ODOO.sql a partir de CONT_BARRIDO_ODOO.sql (14-oct-2026).

El bloque DDL se copia BYTE A BYTE del pegado, cortado por sus dos marcas, nunca
por número de línea. Mismo molde que armar_ensayo_anular_pedido.py.

    python3 herramientas/ensayos/armar_ensayo_cont_barrido.py
"""
import hashlib, os, re, sys

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
PEGADO = os.path.join(RAIZ, 'CONT_BARRIDO_ODOO.sql')
ENSAYO = os.path.join(RAIZ, 'ENSAYO_CONT_BARRIDO_ODOO.sql')

txt = open(PEGADO, encoding='utf-8').read()
M1, M2 = '-- ═══ DDL · DESDE ACA', '-- ═══ DDL · HASTA ACA ═══'
i, j = txt.find(M1), txt.find(M2)
if i < 0 or j < 0 or j < i or txt.count(M1) != 1 or txt.count(M2) != 1:
    sys.exit('no encuentro las dos marcas del bloque DDL, una sola vez cada una')
j += len(M2)
ddl = txt[i:j]
for mala in ('begin;', 'commit;', 'rollback;'):
    if re.search(r'^\s*' + mala, ddl, re.M | re.I):
        sys.exit('el bloque DDL trae un %s suelto: no se arma' % mala)
huella = hashlib.md5(ddl.encode('utf-8')).hexdigest()

P, N = [], [0]
q = lambda s: "'" + s.replace("'", "''") + "'"
GUARDIA, CHECK, UNICO, PERMISO = 'P0001', '23514', '23505', '42501'


def com(t):
    P.append('\n  -- ' + t)


def fila(p, esp, obt_sql, ok_sql):
    N[0] += 1
    P.append("  v_res := v_res || jsonb_build_object('p', %s, 'esperado', %s, 'obtenido', %s, 'ok', coalesce(%s, false));"
             % (q(p), q(esp), obt_sql, ok_sql))


def intento(p, esp, stmt, motivo=None):
    N[0] += 1
    if esp == 'ENTRA':
        P.append("""  begin
    %s;
    v_res := v_res || jsonb_build_object('p', %s, 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', %s, 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;""" % (stmt, q(p), q(p)))
        return
    estado, frag = motivo
    e = q('RECHAZA · %s · %s' % (estado, frag))
    P.append("""  begin
    %s;
    v_res := v_res || jsonb_build_object('p', %s, 'esperado', %s, 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', %s, 'esperado', %s, 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = %s and strpos(sqlerrm, %s) > 0);
  end;""" % (stmt, q(p), e, q(p), e, q(estado), q(frag)))


def como(quien):
    P.append("  perform set_config('request.jwt.claims', json_build_object('email', %s, 'role', 'authenticated')::text, true);" % quien)


def ins(mes, quien='v_socia', monto='113.26'):
    return ("insert into cont_barrido_odoo (mes, asiento_id, asiento_nombre, fecha, lineas, monto, excluidos, huella, creado_por) "
            "values (%s, 99999, 'MISC/ENSAYO', current_date, 26, %s, 0, 'fc659c00c4175e84', %s)" % (q(mes), monto, quien))


com('── las identidades salen de la base ──')
P.append("  select email into v_socia  from v_acceso_usuario where perfil = 'socias'    and activo order by email limit 1;")
P.append("  select email into v_equipo from v_acceso_usuario where perfil = 'equipo'    and activo order by email limit 1;")
P.append("  select email into v_asist  from v_acceso_usuario where perfil = 'asistente' and activo order by email limit 1;")
P.append("  if v_socia is null or v_equipo is null or v_asist is null then raise exception 'falta una identidad para ensayar'; end if;")
P.append("  perform set_config('role', 'authenticated', true);")

com('── R · el servicio registra un barrido, con el token de la socia ──')
como('v_socia')
intento('R1 socia · octubre 2026, firmado por ella', 'ENTRA', ins('2026-10'))
intento('R2 socia · octubre otra vez', 'RECHAZA', ins('2026-10'), (UNICO, 'cont_barrido_odoo_mes_un'))
intento('R3 socia · septiembre (antes del inicio)', 'RECHAZA', ins('2026-09'), (CHECK, 'cont_barrido_odoo_mes_check'))
intento('R4 socia · un mes mal escrito («2026-1»)', 'RECHAZA', ins('2026-1'), (CHECK, 'cont_barrido_odoo_mes_check'))
intento('R5 socia · firmado con OTRO correo', 'RECHAZA', ins('2026-11', quien='v_equipo'), (PERMISO, 'row-level security'))
intento('R6 socia · neto negativo (noviembre, −₡5)', 'ENTRA', ins('2026-11', monto='-5'))

com('── N · nadie más escribe, y nadie edita ──')
como('v_equipo')
intento('N1 equipo · registrar diciembre', 'RECHAZA', ins('2026-12', quien='v_equipo'), (PERMISO, 'row-level security'))
como('v_asist')
intento('N2 asistente · registrar diciembre', 'RECHAZA', ins('2026-12', quien='v_asist'), (PERMISO, 'row-level security'))
como('v_socia')
intento('N3 socia · editar un barrido (update)', 'RECHAZA', "update cont_barrido_odoo set monto = 0 where mes = '2026-10'",
        (PERMISO, 'permission denied for table cont_barrido_odoo'))
intento('N4 socia · borrar un barrido (delete)', 'RECHAZA', "delete from cont_barrido_odoo where mes = '2026-10'",
        (PERMISO, 'permission denied for table cont_barrido_odoo'))

com('── V · quién lo ve ──')
P.append("  select count(*) into v_n from cont_barrido_odoo;")
fila('V1 socia ve los 2 barridos', '2', "v_n::text", "v_n = 2")
como('v_equipo')
P.append("  select count(*) into v_n from cont_barrido_odoo;")
fila('V2 equipo no ve ninguno', '0', "v_n::text", "v_n = 0")
como('v_asist')
P.append("  select count(*) into v_n from cont_barrido_odoo;")
fila('V3 asistente los ve (Instinct ve todo, con su interruptor encendido)', '2', "v_n::text", "v_n = 2")

com('── P · anon no toca nada ──')
P.append("  select count(*) into v_n from information_schema.role_table_grants where table_name = 'cont_barrido_odoo' and grantee = 'anon';")
fila('P1 anon: permisos sobre la tabla', '0', "v_n::text", "v_n = 0")
P.append("  select count(*) into v_n from pg_policy where polrelid = 'public.cont_barrido_odoo'::regclass;")
fila('P2 políticas: 2 propias + 5 del asistente', '7', "v_n::text", "v_n = 7")

cuerpo = '\n'.join(P)
out = f"""-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_CONT_BARRIDO_ODOO.sql · 14-oct-2026 · ENSAYO EN SECO · TERMINA EN ROLLBACK
-- El rastro del barrido de 1103030 · CONT_BARRIDO_ODOO.sql
--
-- ⚠️ ARCHIVO GENERADO. Se regenera con
--     python3 herramientas/ensayos/armar_ensayo_cont_barrido.py
--   El bloque DDL es el de CONT_BARRIDO_ODOO.sql BYTE A BYTE. md5: {huella}
--
-- Sesiones simuladas (request.jwt.claims + rol authenticated, o sea CON RLS) de una
-- socia, alguien del equipo y el asistente, sacadas de v_acceso_usuario.
-- TIENE QUE DAR {N[0]} filas, TODAS con ok = true. Si dice "Success. No rows returned",
-- no llegó al final y no vale.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

{ddl}

do $$
declare
  v_res jsonb := '[]'::jsonb;
  v_socia text; v_equipo text; v_asist text; v_n bigint;
begin
{cuerpo}

  perform set_config('ensayo.res', v_res::text, true);
end $$;

-- ── EL RESULTADO. Esta tabla ES el ensayo. ESPERADO: {N[0]} filas, todas ok = true.
select r.p as prueba, r.esperado, r.obtenido, r.ok
  from jsonb_to_recordset(current_setting('ensayo.res')::jsonb)
       as r(p text, esperado text, obtenido text, ok boolean);

rollback;
"""
open(ENSAYO, 'w', encoding='utf-8').write(out)
print('ENSAYO_CONT_BARRIDO_ODOO.sql armado · %d pruebas · md5 DDL %s' % (N[0], huella))
