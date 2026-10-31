#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Arma ENSAYO_REFACTURA_AUTO.sql a partir de REFACTURA_AUTO.sql (15-oct-2026).

El bloque DDL se copia BYTE A BYTE del pegado, cortado por sus dos marcas, nunca por número de
línea. Mismo molde que armar_ensayo_cont_barrido.py y el de truefie_cc.

    python3 herramientas/ensayos/armar_ensayo_refactura.py
"""
import hashlib, os, re, sys

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
PEGADO = os.path.join(RAIZ, 'REFACTURA_AUTO.sql')
ENSAYO = os.path.join(RAIZ, 'ENSAYO_REFACTURA_AUTO.sql')

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
CHECK, UNICO, PERMISO = '23514', '23505', '42501'
RLS = 'row-level security'
FIRMA = "'automatico-refactura'"
LIGADA = '\'{"a": true, "b": true, "c": true, "d": true}\'::jsonb'


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


def como_rol():
    P.append("  perform set_config('request.jwt.claims', '', true);")
    P.append("  perform set_config('role', 'truefie_refactura', true);")


def como_postgres():
    P.append("  perform set_config('request.jwt.claims', '', true);")
    P.append("  perform set_config('role', 'postgres', true);")


def como(quien):
    P.append("  perform set_config('role', 'authenticated', true);")
    P.append("  perform set_config('request.jwt.claims', json_build_object('email', %s, 'role', 'authenticated')::text, true);" % quien)


def rastro(pedido, vieja, nueva, resultado='ligada', reglas=LIGADA, motivo='null', firma=FIRMA, extra=''):
    return ("insert into ent_refactura (pedido_id, factura_vieja_id, factura_vieja_nombre, factura_nueva_id, factura_nueva_nombre, "
            "resultado, reglas, motivo, creado_por) values (%s, %s, 'ENSAYO-VIEJA', %s, 'ENSAYO-NUEVA', %s, %s, %s, %s)%s"
            % (pedido, vieja, nueva, q(resultado), reglas, motivo, firma, extra))


def vinculo(pedido, factura, firma=FIRMA):
    return ("insert into ent_pedido_factura (pedido_id, factura_id, factura_nombre, anulado, nota, creado_por) "
            "values (%s, %s, 'ENSAYO-NUEVA', false, 'Re-factura automática (ensayo)', %s)" % (pedido, factura, firma))


com('── los datos de prueba salen de la base: dos pedidos entregados con su factura vigente ──')
P.append("  select pedido_id, factura_id into v_p, v_f from v_ent_pedido_estado where estado = 'entregado' and factura_id is not null order by pedido_id limit 1;")
P.append("  select pedido_id, factura_id into v_p2, v_f2 from v_ent_pedido_estado where estado = 'entregado' and factura_id is not null and pedido_id <> v_p order by pedido_id limit 1;")
P.append("  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by email limit 1;")
P.append("  select email into v_equipo from v_acceso_usuario where perfil = 'equipo' and activo order by email limit 1;")
P.append("  if v_p is null or v_p2 is null or v_socia is null or v_equipo is null then raise exception 'falta algo para ensayar'; end if;")
P.append("  if not pg_has_role('postgres', 'truefie_refactura', 'SET') then raise exception 'postgres no puede ponerse truefie_refactura'; end if;")

com('── L · el usuario LEE solo por su función ──')
como_rol()
P.append("  select count(*), count(*) filter (where entregado) into v_n, v_n2 from refactura_entregas();")
fila('L1 la función devuelve pedidos (y algunos entregados)', '> 0 · > 0', "v_n::text || ' · ' || v_n2::text", "v_n > 0 and v_n2 > 0")
P.append("  select salio::text into v_t from refactura_entregas() where pedido_id = 185;")
fila('L2 pedido 185: lo que salió del congelador', '{"451": 3, "453": 4, "503": 4}', "coalesce(v_t, '(nada)')",
     "v_t::jsonb = '{\"451\": 3, \"453\": 4, \"503\": 4}'::jsonb")
intento('L3 leer ent_pedido directo', 'RECHAZA', 'perform 1 from ent_pedido limit 1', (PERMISO, 'permission denied for table ent_pedido'))
intento('L4 leer ent_pedido_factura directo', 'RECHAZA', 'perform 1 from ent_pedido_factura limit 1', (PERMISO, 'permission denied for table ent_pedido_factura'))
intento('L5 leer ent_refactura directo', 'RECHAZA', 'perform 1 from ent_refactura limit 1', (PERMISO, 'permission denied for table ent_refactura'))

com('── R · el rastro: solo agregar, y con sus reglas ──')
intento('R1 apartada SIN motivo', 'RECHAZA', rastro('v_p', 'v_f', 999999990, resultado='apartada', reglas="'{\"a\": true, \"b\": true, \"c\": true, \"d\": false}'::jsonb"),
        (CHECK, 'ent_refactura_ok'))
intento('R2 ligada con una regla en false', 'RECHAZA', rastro('v_p', 'v_f', 999999990, reglas="'{\"a\": true, \"b\": true, \"c\": true, \"d\": false}'::jsonb"),
        (CHECK, 'ent_refactura_ok'))
intento('R3 ligada con las 4 reglas (pedido 1, su vigente → nueva)', 'ENTRA', rastro('v_p', 'v_f', 999999990))
intento('R4 la misma otra vez', 'RECHAZA', rastro('v_p', 'v_f', 999999990), (UNICO, 'ent_refactura_una'))
intento('R5 la misma con on conflict do nothing (corrida repetida)', 'ENTRA', rastro('v_p', 'v_f', 999999990, extra=' on conflict do nothing'))
intento('R6 firmada por una persona', 'RECHAZA', rastro('v_p', 'v_f', 999999993, firma='v_socia'), (PERMISO, RLS))
intento('R7 apartada con su motivo en palabras', 'ENTRA',
        rastro('v_p2', 'v_f2', 999999994, resultado='apartada', reglas="'{\"a\": true, \"b\": true, \"c\": true, \"d\": false}'::jsonb",
               motivo="'cantidades distintas a lo que salió: Blanco factura 6 · salió 3'"))

com('── V · el vínculo: solo si reemplaza a la vigente con su fila «ligada» ──')
intento('V1 ligar el pedido 1 a la nueva', 'ENTRA', vinculo('v_p', 999999990))
intento('V2 ligar el pedido 2 sin fila «ligada»', 'RECHAZA', vinculo('v_p2', 999999991), (PERMISO, RLS))
intento('V3 ligar firmando como persona', 'RECHAZA', vinculo('v_p', 999999990, firma='v_socia'), (PERMISO, RLS))
intento('V4 rastro «ligada» con una vieja que YA no es la vigente', 'ENTRA', rastro('v_p', 'v_f', 999999992))
intento('V5 … y su vínculo', 'RECHAZA', vinculo('v_p', 999999992), (PERMISO, RLS))
intento('V6 rastro: el pedido 2 «pasa» a la nueva del pedido 1', 'ENTRA', rastro('v_p2', 'v_f2', 999999990))
intento('V7 … y su vínculo (la nueva ya es vigente del pedido 1)', 'RECHAZA', vinculo('v_p2', 999999990), (PERMISO, RLS))

com('── N · no cambia ni borra nada, ni toca otras tablas ──')
intento('N1 cambiar una fila del rastro', 'RECHAZA', 'update ent_refactura set motivo = null', (PERMISO, 'permission denied for table ent_refactura'))
intento('N2 borrar un vínculo', 'RECHAZA', 'delete from ent_pedido_factura where factura_id = 999999990', (PERMISO, 'permission denied for table ent_pedido_factura'))
intento('N3 escribir en otra tabla (ent_pedido)', 'RECHAZA',
        "insert into ent_pedido (fecha_despacho, origen, creado_por) values (current_date, 'ensayo', 'automatico-refactura')",
        (PERMISO, 'permission denied for table ent_pedido'))

com('── E · el efecto, visto con el editor ──')
como_postgres()
P.append("  select factura_id into v_n from ent_pedido_factura_vigente where pedido_id = v_p;")
fila('E1 la vigente del pedido 1 pasó a la nueva', '999999990', "v_n::text", "v_n = 999999990")
P.append("  select count(*) into v_n from v_ent_factura_despachada where factura_id = 999999990;")
fila('E2 la nueva cuenta como despachada (sale de «Por preparar»)', '1', "v_n::text", "v_n = 1")
P.append("  select factura_id into v_n from ent_pedido_factura_vigente where pedido_id = v_p2;")
fila('E3 el pedido 2 sigue con su factura', 'la de antes', "v_n::text", "v_n = v_f2")

com('── S · socias y equipo leen el rastro; nadie más escribe ──')
como('v_socia')
P.append("  select count(*) into v_n from ent_refactura;")
fila('S1 socia ve el rastro (R3, R7, V4, V6)', '4', "v_n::text", "v_n = 4")
intento('S2 socia agrega al rastro', 'RECHAZA', rastro('v_p', 'v_f', 999999995, firma='v_socia'), (PERMISO, 'permission denied for table ent_refactura'))
intento('S3 socia usa la función del trabajo', 'RECHAZA', 'perform 1 from refactura_entregas()', (PERMISO, 'permission denied for function refactura_entregas'))
como('v_equipo')
P.append("  select count(*) into v_n from ent_refactura;")
fila('S4 equipo ve el rastro', '4', "v_n::text", "v_n = 4")

com('── A · el usuario y los permisos, en frío ──')
como_postgres()
P.append("  select count(*) into v_n from pg_roles where rolname = 'truefie_refactura' and rolcanlogin and not rolsuper and not rolbypassrls and not rolinherit and not rolcreaterole;")
fila('A1 usuario: entra, sin superusuario, sin saltear RLS, sin heredar', '1', "v_n::text", "v_n = 1")
P.append("  select count(*) into v_n from information_schema.role_table_grants where table_name = 'ent_refactura' and grantee = 'anon';")
fila('A2 anon: permisos sobre el rastro', '0', "v_n::text", "v_n = 0")
P.append("  select string_agg(privilege_type, ',' order by privilege_type) into v_t from information_schema.role_table_grants where grantee = 'truefie_refactura';")
fila('A3 todo lo que puede el usuario sobre tablas', 'INSERT,INSERT', "coalesce(v_t, '(nada)')", "v_t = 'INSERT,INSERT'")
P.append("  select count(*) into v_n from pg_policy where polrelid = 'public.ent_refactura'::regclass;")
fila('A4 políticas del rastro: 2 propias + 5 del asistente', '7', "v_n::text", "v_n = 7")

cuerpo = '\n'.join(P)
out = f"""-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_REFACTURA_AUTO.sql · 15-oct-2026 · ENSAYO EN SECO · TERMINA EN ROLLBACK
-- Re-facturas automáticas · REFACTURA_AUTO.sql
--
-- ⚠️ ARCHIVO GENERADO. Se regenera con
--     python3 herramientas/ensayos/armar_ensayo_refactura.py
--   El bloque DDL es el de REFACTURA_AUTO.sql BYTE A BYTE. md5: {huella}
--
-- Prueba como el usuario nuevo (truefie_refactura), como socia y como equipo (sesiones simuladas
-- con RLS) y con el editor. Las facturas de prueba son números que no existen (999999990…); todo
-- se va con el rollback, también el usuario.
-- TIENE QUE DAR {N[0]} filas, TODAS con ok = true. Si dice "Success. No rows returned",
-- no llegó al final y no vale.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

{ddl}

-- ── SOLO PARA ENSAYAR: que el editor pueda ponerse el usuario. Se va con el rollback.
grant truefie_refactura to postgres with set true, inherit false;

do $$
declare
  v_res jsonb := '[]'::jsonb;
  v_p bigint; v_f integer; v_p2 bigint; v_f2 integer;
  v_socia text; v_equipo text; v_n bigint; v_n2 bigint; v_t text;
begin
{cuerpo}

  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('ensayo.res', v_res::text, true);
end $$;

-- ── EL RESULTADO. Esta tabla ES el ensayo. ESPERADO: {N[0]} filas, todas ok = true.
select r.p as prueba, r.esperado, r.obtenido, r.ok
  from jsonb_to_recordset(current_setting('ensayo.res')::jsonb)
       as r(p text, esperado text, obtenido text, ok boolean);

rollback;
"""
open(ENSAYO, 'w', encoding='utf-8').write(out)
print('ENSAYO_REFACTURA_AUTO.sql armado · %d pruebas · md5 DDL %s' % (N[0], huella))
