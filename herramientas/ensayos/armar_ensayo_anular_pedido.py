#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Arma ENSAYO_ANULAR_PEDIDO.sql a partir de ENTREGAS_ANULAR_PEDIDO.sql (§29, 14-oct-2026).

El bloque DDL se copia BYTE A BYTE del pegado, cortado por sus dos marcas
(`═══ DDL · DESDE ACA` y `═══ DDL · HASTA ACA ═══`), nunca por numero de
linea (CLAUDE.md, 16-sep). Mismo molde que armar_ensayo_correccion_lote.py.

    python3 herramientas/ensayos/armar_ensayo_anular_pedido.py

Los pedidos del ensayo se crean ADENTRO de la transaccion (destinatario
'ENSAYO', firma 'ensayo') y se van con el rollback. Ningun pedido real se toca.

Los datos de prueba respetan las restricciones MEDIDAS (14-oct): ent_odoo_traslado
exige contacto 1260-1263, destino 16/19, lineas no vacias y picking_id unico (de
ahi el -1); ent_odoo_validacion, lineas no vacias y picking_id unico (-2). El
segundo ensayo choco contra el contacto 0: se midio despues de fallar.
"""
import hashlib, os, re, sys

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
PEGADO = os.path.join(RAIZ, 'ENTREGAS_ANULAR_PEDIDO.sql')
ENSAYO = os.path.join(RAIZ, 'ENSAYO_ANULAR_PEDIDO.sql')

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

P = []
N = [0]   # cuántas filas va a tener el resultado

def q(s):
    return "'" + s.replace("'", "''") + "'"

def com(t):
    P.append('\n  -- ' + t)

def fila(p, esp, obt_sql, ok_sql):
    N[0] += 1
    P.append("  v_res := v_res || jsonb_build_object('p', %s, 'esperado', %s, 'obtenido', %s, 'ok', coalesce(%s, false));"
             % (q(p), q(esp), obt_sql, ok_sql))

GUARDIA, PERMISO = 'P0001', '42501'

def intento(p, esp, stmt, motivo=None):
    """ENTRA, o RECHAZA por SU razon (sqlstate + pedazo del mensaje)."""
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

def anular(var, motivo, nota='null', confirmar='true'):
    return "v_r := ent_anular_pedido(%s, %s, %s, %s)" % (var, q(motivo), nota, confirmar)

# Un pedido de ensayo: Semillas 281 / 7-27, 1 u (el lote existe y es de despues del ancla).
def pedido(var, motivo='regalia', alisto=True, salida=True, ali_var='v_ali', hace=None):
    P.append("  insert into ent_pedido (fecha_despacho, origen, motivo, destinatario, creado_por) "
             "values (current_date, 'manual', %s, 'ENSAYO', 'ensayo') returning id into %s;" % (q(motivo), var))
    if not alisto:
        return
    cre = (", creado_en) values (%s, 'ensayo', 'ensayo', now() - interval '%s')" % (var, hace)) if hace else \
          (") values (%s, 'ensayo', 'ensayo')" % var)
    P.append("  insert into ent_alisto (pedido_id, responsable, creado_por%s returning id into %s;" % (cre, ali_var))
    P.append("  insert into ent_alisto_linea (alisto_id, producto_id, cant_uds) values (%s, 452, 1) returning id into v_lin;" % ali_var)
    P.append("  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden) values (v_lin, '281 / 7-27', 1, 1);")
    if salida:
        P.append("  insert into ent_salida (alisto_id, creado_por) values (%s, 'ensayo');" % ali_var)

def pendiente(var, ret=''):
    P.append("  insert into ent_odoo_pendiente (tipo, pedido_id, fecha, destinatario, creado_por) "
             "values ('traslado_interno', %s, current_date, 'ENSAYO', 'ensayo')%s;" % (var, ret))

SAL281 = "(select coalesce(sum(uds),0) from ent_salido_del_congelador_desde_ancla where producto_id = 452 and lote = '281 / 7-27')"
RESTO = ("(select md5(coalesce(string_agg(producto_id||'|'||lote||'|'||uds, ',' order by producto_id, lote),'')) "
         "from ent_salido_del_congelador_desde_ancla where (producto_id, lote) <> (452, '281 / 7-27'))")

# ── PREPARAR (como postgres: los pedidos de ensayo) ─────────────────────────
com('── PREPARAR · los pedidos del ensayo, como postgres ──')
P.append("  select email into v_socia  from v_acceso_usuario where perfil = 'socias'    and activo order by email limit 1;")
P.append("  select email into v_equipo from v_acceso_usuario where perfil = 'equipo'    and activo order by email limit 1;")
P.append("  select email into v_asist  from v_acceso_usuario where perfil = 'asistente' and activo order by email limit 1;")
P.append("  if v_socia is null or v_equipo is null or v_asist is null then\n"
         "    raise exception 'falta una identidad para ensayar (socia %, equipo %, asistente %)', v_socia is not null, v_equipo is not null, v_asist is not null;\n"
         "  end if;")
com('A · regalía entregada, sin nada en Odoo, con su traslado por crear (el caso de la #195)')
pedido('v_a', ali_var='v_ali_a'); pendiente('v_a')
com('B · con traslado creado desde Truefie')
pedido('v_b'); P.append("  insert into ent_odoo_traslado (pedido_id, picking_id, picking_nombre, motivo, destino_id, contacto_id, lineas, creado_por) "
                        "values (v_b, -1, 'WH/INT/ENSAYO', 'regalia', 19, 1260, '[{\"ensayo\": true}]', 'ensayo');")
com('C · validado en Odoo desde Truefie')
pedido('v_c', motivo='venta'); P.append("  insert into ent_odoo_validacion (pedido_id, factura_id, picking_id, picking_nombre, lineas, validado_por) "
                                      "values (v_c, 0, -2, 'WH/OUT/ENSAYO', '[{\"ensayo\": true}]', 'ensayo');")
com('D · con devolución')
pedido('v_d'); P.append("  insert into ent_devolucion (fecha, cliente_id, cliente_nombre, creado_por, pedido_id, causa) "
                        "values (current_date, 0, 'ENSAYO', 'ensayo', v_d, 'producto_equivocado');")
com('E · su traslado marcado «Hecho» a mano')
pedido('v_e'); pendiente('v_e', ' returning id into v_pend')
P.append("  insert into ent_odoo_hecho (pendiente_id, referencia, creado_por) values (v_pend, 'WH/INT/MANO', 'ensayo');")
com('F · preparado, sin salida')
pedido('v_f', salida=False)
com('G · dos alistos sin anular (uno viejo y el vigente): los dos tienen que caer')
pedido('v_g', ali_var='v_ali_g1', hace='1 hour')
P.append("  insert into ent_alisto (pedido_id, responsable, creado_por) values (v_g, 'ensayo', 'ensayo') returning id into v_ali_g2;")
P.append("  insert into ent_alisto_linea (alisto_id, producto_id, cant_uds) values (v_ali_g2, 452, 1) returning id into v_lin;")
P.append("  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden) values (v_lin, '281 / 7-27', 1, 1);")
com('H · solo la cabecera, sin alisto')
pedido('v_h', alisto=False)
com('I · venta sin factura vinculada · J · sin clasificar')
pedido('v_i', motivo='venta'); pedido('v_j', motivo='sin_clasificar')

# ── S · SIN SESION ─────────────────────────────────────────────────────────
com('── S · SIN SESION (todavia como postgres) ──')
intento('S1 sin sesión · anular A', 'RECHAZA', 'perform ' + anular('v_a', 'duplicado')[7:],
        (GUARDIA, 'sin sesion no se sabe quien anula'))

# ── DE ACÁ EN ADELANTE, CON RLS ────────────────────────────────────────────
com('── De aca en adelante la RLS aplica ──')
P.append("  perform set_config('role', 'authenticated', true);")
como('v_equipo')
intento('Q1 equipo · anular A', 'RECHAZA', 'perform ' + anular('v_a', 'duplicado')[7:],
        (GUARDIA, 'anular un pedido es de un perfil socias'))
como('v_asist')
intento('Q2 asistente · anular A', 'RECHAZA', 'perform ' + anular('v_a', 'duplicado')[7:],
        (GUARDIA, 'anular un pedido es de un perfil socias'))
como('v_socia')

com('── N · LO QUE FRENA, como socia ──')
intento('N1 motivo inválido', 'RECHAZA', 'perform ' + anular('v_a', 'x')[7:], (GUARDIA, 'motivo invalido: x'))
intento('N2 «Otro» sin texto', 'RECHAZA', 'perform ' + anular('v_a', 'otro')[7:],
        (GUARDIA, 'con el motivo Otro hace falta explicar por que'))
intento('N3 «Otro» con 5 letras', 'RECHAZA', 'perform ' + anular('v_a', 'otro', "'corto'")[7:],
        (GUARDIA, 'con el motivo Otro hace falta explicar por que'))
intento('N4 pedido inexistente', 'RECHAZA', 'perform ent_anular_pedido(999999999, \'duplicado\', null, true)',
        (GUARDIA, 'el pedido 999999999 no existe'))
intento('N5 B · traslado creado desde Truefie', 'RECHAZA', 'perform ' + anular('v_b', 'duplicado')[7:],
        (GUARDIA, 'ya tiene el traslado interno WH/INT/ENSAYO en Odoo'))
intento('N6 C · validado en Odoo', 'RECHAZA', 'perform ' + anular('v_c', 'duplicado')[7:],
        (GUARDIA, 'ya esta validado en Odoo (WH/OUT/ENSAYO)'))
intento('N7 D · con devolución', 'RECHAZA', 'perform ' + anular('v_d', 'duplicado')[7:],
        (GUARDIA, 'tiene una devolucion registrada'))
intento('N8 E · traslado marcado «Hecho» a mano', 'RECHAZA', 'perform ' + anular('v_e', 'duplicado')[7:],
        (GUARDIA, 'su traslado se marco hecho en Odoo (WH/INT/MANO)'))
intento('N9 H · sin alisto', 'RECHAZA', 'perform ' + anular('v_h', 'duplicado')[7:],
        (GUARDIA, 'no tiene nada vigente que anular'))

com('── V · VISTA PREVIA de A: dice lo que pasaría y NO deja nada ──')
P.append("  v_x1 := %s;" % SAL281)
intento('V1 previa de A (duplicado)', 'ENTRA', anular('v_a', 'duplicado', confirmar='false'))
fila('V2 previa · devuelve', 'previa · Semillas 281 / 7-27 · 1 u',
     "coalesce((v_r ->> 'previa') || ' · ' || (v_r -> 'devuelve')::text, 'null')",
     "(v_r ->> 'previa')::boolean and (v_r -> 'devuelve') = '[{\"producto_id\": 452, \"lote\": \"281 / 7-27\", \"uds\": 1}]'::jsonb")
P.append("  select count(*) into v_n1 from ent_pedido_anulacion where pedido_id = v_a;")
P.append("  select count(*) into v_n2 from ent_alisto_vigente where pedido_id = v_a;")
P.append("  select count(*) into v_n3 from v_ent_odoo_pendiente where pedido_id = v_a;")
fila('V3 después de la previa · anulaciones · alisto vigente · en la cola · lote 281',
     '0 · 1 · 1 · sin cambio',
     "v_n1 || ' · ' || v_n2 || ' · ' || v_n3 || ' · ' || case when %s = v_x1 then 'sin cambio' else 'CAMBIO' end" % SAL281,
     "v_n1 = 0 and v_n2 = 1 and v_n3 = 1 and %s = v_x1" % SAL281)

com('── R · ANULAR A DE VERDAD ──')
P.append("  v_x1 := %s; v_md5 := %s;" % (SAL281, RESTO))
intento('R1 anular A (duplicado)', 'ENTRA', anular('v_a', 'duplicado', "'ensayo: registrado dos veces'"))
fila('R2 respuesta · previa · anulacion_id', 'false · con id',
     "coalesce((v_r ->> 'previa') || ' · ' || coalesce(v_r ->> 'anulacion_id', 'sin id'), 'null')",
     "not (v_r ->> 'previa')::boolean and (v_r ->> 'anulacion_id') is not null")
P.append("  select count(*) into v_n1 from ent_pedido_anulacion where pedido_id = v_a and creado_por = lower(v_socia) and motivo = 'duplicado'"
         " and alistos = array[v_ali_a] and cardinality(salidas) = 1;")
P.append("  select count(*) into v_n2 from ent_anulacion x where x.creado_por = lower(v_socia)"
         " and ((x.entidad = 'alisto' and x.entidad_id = v_ali_a) or (x.entidad = 'salida' and x.entidad_id in (select id from ent_salida where alisto_id = v_ali_a)));")
fila('R3 quién sale de la sesión · ent_pedido_anulacion · ent_anulacion', '1 · 2', "v_n1 || ' · ' || v_n2", "v_n1 = 1 and v_n2 = 2")
P.append("  select count(*) into v_n1 from ent_alisto_vigente where pedido_id = v_a;")
P.append("  select count(*) into v_n2 from v_ent_pedido_estado where pedido_id = v_a;")
P.append("  select count(*) into v_n3 from v_ent_odoo_pendiente where pedido_id = v_a;")
fila('R4 alisto vigente · historial · cola de Odoo', '0 · 0 · 0', "v_n1 || ' · ' || v_n2 || ' · ' || v_n3", "v_n1 = 0 and v_n2 = 0 and v_n3 = 0")
fila('R5 lote 281 vuelve 1 u · el resto igual', '1 · igual',
     "(v_x1 - %s) || ' · ' || case when %s = v_md5 then 'igual' else 'CAMBIO' end" % (SAL281, RESTO),
     "v_x1 - %s = 1 and %s = v_md5" % (SAL281, RESTO))
intento('R6 anular A otra vez', 'RECHAZA', 'perform ' + anular('v_a', 'duplicado')[7:], (GUARDIA, 'ya esta anulado'))

com('── O · LOS OTROS CASOS QUE SÍ SE ANULAN ──')
intento('O1 F · preparado sin salida (no salió)', 'ENTRA', anular('v_f', 'no_salio'))
fila('O2 F · salidas · devuelve', '[] · 1 u',
     "coalesce((v_r -> 'salidas')::text || ' · ' || (v_r -> 'devuelve')::text, 'null')",
     "(v_r -> 'salidas') = '[]'::jsonb and jsonb_array_length(v_r -> 'devuelve') = 1 and (v_r -> 'devuelve' -> 0 ->> 'uds')::numeric = 1")
intento('O3 G · «Otro» con texto', 'ENTRA', anular('v_g', 'otro', "'ensayo: dos alistos vivos'"))
P.append("  select count(*) into v_n1 from ent_alisto_vigente where pedido_id = v_g;")
fila('O4 G · los dos alistos anulados · alisto vigente', '2 · 0',
     "coalesce(jsonb_array_length(v_r -> 'alistos'), -1) || ' · ' || v_n1",
     "jsonb_array_length(v_r -> 'alistos') = 2 and v_n1 = 0")
P.append("  select count(*) into v_n1 from ent_salida_sin_factura where id = v_i;")
P.append("  select count(*) into v_n2 from ent_salida_sin_clasificar where id = v_j;")
fila('O5 I y J figuran antes de anular', '1 · 1', "v_n1 || ' · ' || v_n2", "v_n1 = 1 and v_n2 = 1")
intento('O6 I · datos equivocados', 'ENTRA', anular('v_i', 'datos_mal'))
intento('O7 J · registrado dos veces', 'ENTRA', anular('v_j', 'duplicado'))
P.append("  select count(*) into v_n1 from ent_salida_sin_factura where id = v_i;")
P.append("  select count(*) into v_n2 from ent_salida_sin_clasificar where id = v_j;")
fila('O8 I y J ya no figuran', '0 · 0', "v_n1 || ' · ' || v_n2", "v_n1 = 0 and v_n2 = 0")

com('── U · APPEND-ONLY: nadie escribe directo en la tabla ──')
intento('U1 socia · insert directo', 'RECHAZA',
        "insert into ent_pedido_anulacion (pedido_id, motivo, alistos, salidas, creado_por) values (v_h, 'duplicado', array[1], '{}', v_socia)",
        (PERMISO, 'permission denied for table ent_pedido_anulacion'))
intento('U2 socia · update', 'RECHAZA', "update ent_pedido_anulacion set nota = 'otra' where pedido_id = v_a",
        (PERMISO, 'permission denied for table ent_pedido_anulacion'))
intento('U3 socia · delete', 'RECHAZA', "delete from ent_pedido_anulacion where pedido_id = v_a",
        (PERMISO, 'permission denied for table ent_pedido_anulacion'))

com('── P · anon no toca nada (al final: cambia el rol) ──')
P.append("""  select count(*) into v_n1 from unnest(array['public.ent_pedido_anulacion']) t
   where has_table_privilege('anon', t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE');""")
fila('P1 anon: permisos sobre la tabla · EXECUTE de la función', '0 · false',
     "v_n1 || ' · ' || has_function_privilege('anon', 'public.ent_anular_pedido(bigint,text,text,boolean)', 'EXECUTE')",
     "v_n1 = 0 and not has_function_privilege('anon', 'public.ent_anular_pedido(bigint,text,text,boolean)', 'EXECUTE')")
P.append("  perform set_config('role', 'anon', true);")
intento('P2 anon · llamar la función', 'RECHAZA', 'perform ' + anular('v_h', 'duplicado')[7:],
        (PERMISO, 'permission denied for function ent_anular_pedido'))

n_pruebas = N[0]

cuerpo = '\n'.join(P)
out = f"""-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_ANULAR_PEDIDO.sql · 14-oct-2026 · ENSAYO EN SECO · TERMINA EN ROLLBACK
-- ✅ CORRIDO el 14-oct-2026 por Andrea (tercer intento): 34/34 ok = true, md5 DDL c8f09ae9a0f6.
--    Verificado desde afuera despues: ni la tabla ni la funcion ni los pedidos de ensayo quedaron.
-- «Anular pedido» (§29) · ENTREGAS_ANULAR_PEDIDO.sql
--
-- ⚠️ ARCHIVO GENERADO. No se edita a mano: se regenera con
--     python3 herramientas/ensayos/armar_ensayo_anular_pedido.py
--   El bloque DDL de abajo es el de ENTREGAS_ANULAR_PEDIDO.sql BYTE A BYTE,
--   cortado por sus marcas. md5 del bloque: {huella}
--
-- QUE HACE
--   1. Crea todo, igual que el pegado.
--   2. Arma pedidos de ensayo ADENTRO de la transaccion (destinatario ENSAYO).
--   3. Prueba sin sesion, como equipo, como asistente, como socia y como anon
--      (sesion simulada con `request.jwt.claims` + rol `authenticated`, o sea
--      CON RLS). Las identidades salen de `v_acceso_usuario`: ningun correo va
--      escrito aca porque el repo es publico.
--   4. rollback. No queda nada: ni el esquema ni los pedidos de ensayo.
--
-- COMO SE LEE
--   Una tabla de {n_pruebas} filas, TODAS con ok = true. Si el editor dice
--   "Success. No rows returned", no llego al final y no vale.
--   Un RECHAZA da ok SOLO si rebota por SU razon (SQLSTATE + pedazo del mensaje).
-- ═══════════════════════════════════════════════════════════════════════════

begin;

{ddl}

do $$
declare
  v_res jsonb := '[]'::jsonb;
  v_r   jsonb;
  v_socia text; v_equipo text; v_asist text;
  v_a bigint; v_b bigint; v_c bigint; v_d bigint; v_e bigint; v_f bigint; v_g bigint; v_h bigint; v_i bigint; v_j bigint;
  v_ali bigint; v_ali_a bigint; v_ali_g1 bigint; v_ali_g2 bigint; v_lin bigint; v_pend bigint;
  v_n1 bigint; v_n2 bigint; v_n3 bigint; v_x1 numeric; v_md5 text;
begin
{cuerpo}

  perform set_config('ensayo.res', v_res::text, true);
end $$;


-- ── EL RESULTADO. Esta tabla ES el ensayo. ────────────────────────────────
-- ESPERADO: {n_pruebas} filas, todas con ok = true.
select r.p as prueba, r.esperado, r.obtenido, r.ok
  from jsonb_to_recordset(current_setting('ensayo.res')::jsonb)
       as r(p text, esperado text, obtenido text, ok boolean);

rollback;
"""
open(ENSAYO, 'w', encoding='utf-8').write(out)
print('ENSAYO_ANULAR_PEDIDO.sql armado · %d pruebas · md5 DDL %s' % (n_pruebas, huella))
