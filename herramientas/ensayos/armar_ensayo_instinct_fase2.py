#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
armar_ensayo_instinct_fase2.py — arma ENSAYO_INSTINCT_FASE2.sql desde INSTINCT_FASE2.sql (19-oct-2026).

El bloque DDL se copia TAL CUAL de INSTINCT_FASE2.sql (entre las marcas ▼▼▼ / ▲▲▲), así el ensayo
prueba lo mismo que se pegaría. Las pruebas van en una lista: cada una dice qué espera (ENTRA o el
SQLSTATE con que tiene que rebotar). Un RECHAZA vale solo con SU SQLSTATE (regla del 24-sep).

    python3 herramientas/ensayos/armar_ensayo_instinct_fase2.py
"""
import hashlib, os, re

AQUI = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(AQUI))
SQL = open(os.path.join(REPO, "INSTINCT_FASE2.sql"), encoding="utf-8").read()
m = re.search(r"-- ▼▼▼ BLOQUE DDL ▼▼▼\n(.*?)-- ▲▲▲ FIN BLOQUE DDL ▲▲▲\n", SQL, re.S)
DDL = m.group(1)
MD5 = hashlib.md5(DDL.encode()).hexdigest()

PRUEBAS = []          # (id, texto, quién, sql, esperado)


def p(pid, texto, quien, sql, esperado="ENTRA"):
    PRUEBAS.append((pid, texto, quien, sql.strip(), esperado))


PROP = ("insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, "
        "codigo_proveedor, factura_ref, creado_por) values ('{n}', 12, 15, '2363000000000', 1183, 8910.89, '2292', "
        "'00100001010000008144', {por}) returning id into {var};")
VP = ("insert into asistente_vista_previa (id, accion, propuesta_id, huella, codigo, creado_por) "
      "values ({id}, '{acc}', {prop}, 'eb2df9d55fa4451b', '{cod}', {por});")
RASTRO = ("insert into compra_insumo_odoo (propuesta_id, producto_tmpl_id, producto_id, supplierinfo_id, nombre, huella, "
          "creado_por, hecho_por_asistente, vista_previa_id, codigo) values ({prop}, {tmpl}, null, null, 'Cacao Ensayo', "
          "'eb2df9d55fa4451b', {por}, {marca}, {vp}, {cod});")
INTENTO = "insert into asistente_intento (vista_previa_id, creado_por) values ({vp}, {por});"

# ── con el permiso APAGADO (no hay filas) ──
p("A0", "Instinct propone un insumo con el permiso APAGADO", "asis", PROP.format(n="Cacao A0", por="v_asis", var="v_x"), "42501")
p("S1", "una socia ENCIENDE crear_insumo", "socia",
  "insert into asistente_permiso (capacidad, encendido, motivo, creado_por) values ('crear_insumo', true, 'ensayo', v_socia);")
p("S2", "Instinct se enciende un permiso a sí mismo", "asis",
  "insert into asistente_permiso (capacidad, encendido, motivo, creado_por) values ('facturar', true, 'ensayo', v_asis);", "42501")
p("S3", "alguien de equipo enciende un permiso", "equipo",
  "insert into asistente_permiso (capacidad, encendido, motivo, creado_por) values ('crear_insumo', true, 'ensayo', v_equipo);", "42501")
p("S4", "una socia firma el permiso con OTRO nombre", "socia",
  "insert into asistente_permiso (capacidad, encendido, motivo, creado_por) values ('crear_insumo', true, 'ensayo', v_equipo);", "42501")
p("S5", "un permiso con una capacidad mal escrita (mayúsculas y espacio)", "socia",
  "insert into asistente_permiso (capacidad, encendido, motivo, creado_por) values ('Crear Insumo', true, 'ensayo', v_socia);", "23514")
# ── con el permiso ENCENDIDO ──
p("P1", "Instinct propone el cacao con SU correo", "asis", PROP.format(n="Cacao P1", por="v_asis", var="v_pa"))
p("P2", "Instinct propone firmando como la socia", "asis", PROP.format(n="Cacao P2", por="v_socia", var="v_x"), "42501")
p("P3", "la socia sigue proponiendo como siempre", "socia", PROP.format(n="Cacao P3", por="v_socia", var="v_ps"))
p("P4", "Instinct propone otro (para la vista previa vieja)", "asis", PROP.format(n="Cacao P4", por="v_asis", var="v_pb"))
p("P5", "Instinct propone otro (para la agotada)", "asis", PROP.format(n="Cacao P5", por="v_asis", var="v_pc"))
p("V1", "Instinct anota la vista previa de SU propuesta", "asis",
  VP.format(id="v_vp1", acc="crear_insumo", prop="v_pa", cod="4821", por="v_asis"))
p("V2", "vista previa de la propuesta de la SOCIA", "asis",
  VP.format(id="gen_random_uuid()", acc="crear_insumo", prop="v_ps", cod="1111", por="v_asis"), "42501")
p("V3", "vista previa firmada como la socia", "asis",
  VP.format(id="gen_random_uuid()", acc="crear_insumo", prop="v_pa", cod="2222", por="v_socia"), "42501")
p("V4", "código de 3 dígitos", "asis",
  VP.format(id="gen_random_uuid()", acc="crear_insumo", prop="v_pa", cod="482", por="v_asis"), "23514")
p("V5", "código con letras", "asis",
  VP.format(id="gen_random_uuid()", acc="crear_insumo", prop="v_pa", cod="48A1", por="v_asis"), "23514")
p("V6", "MISMO código en otra vista previa de la MISMA propuesta", "asis",
  VP.format(id="gen_random_uuid()", acc="crear_insumo", prop="v_pa", cod="4821", por="v_asis"), "23505")
p("V7", "vista previa para una acción sin permiso (facturar)", "asis",
  VP.format(id="gen_random_uuid()", acc="facturar", prop="v_pa", cod="3333", por="v_asis"), "42501")
p("V8", "alguien de equipo anota una vista previa", "equipo",
  VP.format(id="gen_random_uuid()", acc="crear_insumo", prop="v_pa", cod="4444", por="v_equipo"), "42501")
p("V9", "la socia anota una vista previa (no le toca)", "socia",
  VP.format(id="gen_random_uuid()", acc="crear_insumo", prop="v_ps", cod="5555", por="v_socia"), "42501")
p("V10", "Instinct anota dos vistas previas de la propuesta P4 (vieja y vigente)", "asis",
  VP.format(id="v_vp2", acc="crear_insumo", prop="v_pb", cod="1234", por="v_asis") + "\n    " +
  VP.format(id="v_vp3", acc="crear_insumo", prop="v_pb", cod="5678", por="v_asis"))
p("V11", "Instinct anota la vista previa de la propuesta P5", "asis",
  VP.format(id="v_vp4", acc="crear_insumo", prop="v_pc", cod="9012", por="v_asis"))
p("I1", "Instinct anota un intento fallido sobre SU vista previa", "asis", INTENTO.format(vp="v_vp1", por="v_asis"))
p("I2", "intento firmado como la socia", "asis", INTENTO.format(vp="v_vp1", por="v_socia"), "42501")
p("I3", "intento sobre una vista previa AJENA", "asis", INTENTO.format(vp="v_vp_ajena", por="v_asis"), "42501")
p("I4", "tres intentos sobre la de P5 (queda agotada)", "asis",
  "\n    ".join([INTENTO.format(vp="v_vp4", por="v_asis")] * 3))
p("U1", "Instinct CAMBIA el código de una vista previa", "asis",
  "update asistente_vista_previa set codigo = '0000' where id = v_vp1;", "42501")
p("U2", "Instinct BORRA sus intentos", "asis", "delete from asistente_intento where vista_previa_id = v_vp4;", "42501")
p("U3", "la socia BORRA intentos", "socia", "delete from asistente_intento where vista_previa_id = v_vp4;", "42501")
p("U4", "la socia apaga un permiso CAMBIANDO la fila (no: se agrega otra)", "socia",
  "update asistente_permiso set encendido = false;", "42501")
p("R1", "Instinct deja el rastro con la vista previa vigente y SU código", "asis",
  RASTRO.format(prop="v_pa", tmpl=905, por="v_asis", marca="true", vp="v_vp1", cod="'4821'"))
p("R2", "rastro con el código EQUIVOCADO", "asis",
  RASTRO.format(prop="v_pb", tmpl=906, por="v_asis", marca="true", vp="v_vp3", cod="'0000'"), "42501")
p("R3", "rastro con la vista previa VIEJA (y su código)", "asis",
  RASTRO.format(prop="v_pb", tmpl=906, por="v_asis", marca="true", vp="v_vp2", cod="'1234'"), "42501")
p("R4", "rastro con la vista previa AGOTADA (3 intentos) y su código", "asis",
  RASTRO.format(prop="v_pc", tmpl=907, por="v_asis", marca="true", vp="v_vp4", cod="'9012'"), "42501")
p("R5", "rastro de Instinct SIN la marca", "asis",
  RASTRO.format(prop="v_pb", tmpl=906, por="v_asis", marca="false", vp="null", cod="null"), "42501")
p("R6", "rastro con la vista previa de OTRA propuesta (código de P4 sobre P5)", "asis",
  RASTRO.format(prop="v_pc", tmpl=907, por="v_asis", marca="true", vp="v_vp3", cod="'5678'"), "42501")
p("R7", "la socia firma un rastro «hecho por Instinct»", "socia",
  RASTRO.format(prop="v_ps", tmpl=908, por="v_socia", marca="true", vp="v_vp1", cod="'4821'"), "42501")
p("R8", "la socia deja su rastro de siempre (sin marca)", "socia",
  RASTRO.format(prop="v_ps", tmpl=908, por="v_socia", marca="false", vp="null", cod="null"))
p("R9", "marca sin vista previa (el check)", "postgres",
  RASTRO.format(prop="v_pb", tmpl=909, por="v_socia", marca="true", vp="null", cod="null"), "23514")
p("R10", "Instinct deja el rastro de la vigente de P4 con su código", "asis",
  RASTRO.format(prop="v_pb", tmpl=906, por="v_asis", marca="true", vp="v_vp3", cod="'5678'"))
p("E1", "alguien de equipo propone un insumo", "equipo", PROP.format(n="Cacao E1", por="v_equipo", var="v_x"), "42501")
# ── la socia apaga el permiso / el interruptor general ──
p("S6", "la socia APAGA crear_insumo", "socia",
  "insert into asistente_permiso (capacidad, encendido, motivo, creado_por) values ('crear_insumo', false, 'ensayo', v_socia);")
p("A1", "con el permiso apagado, Instinct propone", "asis", PROP.format(n="Cacao A1", por="v_asis", var="v_x"), "42501")
p("A2", "con el permiso apagado, Instinct anota una vista previa", "asis",
  VP.format(id="gen_random_uuid()", acc="crear_insumo", prop="v_pa", cod="6666", por="v_asis"), "42501")
p("S7", "la socia vuelve a encender crear_insumo", "socia",
  "insert into asistente_permiso (capacidad, encendido, motivo, creado_por) values ('crear_insumo', true, 'ensayo', v_socia);")
p("S8", "la socia apaga el INTERRUPTOR GENERAL del asistente", "socia",
  "insert into asistente_interruptor (encendido, motivo, creado_por) values (false, 'ensayo', v_socia);")
p("A3", "interruptor general apagado (permiso encendido): Instinct propone", "asis",
  PROP.format(n="Cacao A3", por="v_asis", var="v_x"), "42501")


def bloque(pid, texto, quien, sql, esp):
    rol = {"socia": "v_socia", "asis": "v_asis", "equipo": "v_equipo"}.get(quien)
    cab = ("  perform set_config('role', 'postgres', true);\n" if quien == "postgres" else
           "  perform set_config('request.jwt.claims', json_build_object('email', %s, 'role', 'authenticated')::text, true);\n"
           "  perform set_config('role', 'authenticated', true);\n" % rol)
    nom = ("%s %s" % (pid, texto)).replace("'", "''")
    e = "ENTRA" if esp == "ENTRA" else "RECHAZA · " + esp
    if esp == "ENTRA":
        return cab + ("  begin\n    %s\n    v_res := v_res || jsonb_build_object('p','%s','esperado','ENTRA','obtenido','ENTRA','ok',true);\n"
                      "  exception when others then\n    v_res := v_res || jsonb_build_object('p','%s','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);\n"
                      "  end;\n") % (sql, nom, nom)
    return cab + ("  begin\n    %s\n    v_res := v_res || jsonb_build_object('p','%s','esperado','%s','obtenido','ENTRA','ok',false);\n"
                  "  exception when others then\n    v_res := v_res || jsonb_build_object('p','%s','esperado','%s','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='%s');\n"
                  "  end;\n") % (sql, nom, e, nom, e, esp)


N_FIJAS = 5           # X1, X2, Z1, Z2, Z3
total = len(PRUEBAS) + N_FIJAS
out = []
out.append("""-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_INSTINCT_FASE2.sql  ·  19-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA (termina en rollback)
-- Prueba INSTINCT_FASE2.sql: permiso por acción, vista previa con código, intentos y el rastro
-- «hecho por Instinct». Lo arma herramientas/ensayos/armar_ensayo_instinct_fase2.py (md5 del bloque DDL: %s).
-- ✅ CORRIDO el 19-oct-2026 por Andrea en producción: 52 de 52 ok = true, cada RECHAZA con su SQLSTATE y por
--    SU motivo (42501 RLS o sin permiso; 23514 capacidad_check, codigo_check, marca_ok; 23505 el único de
--    código). X2: 9 tablas rebotan antes por su guardia BEFORE INSERT (8 P0001 + rrhh_feriado_trabajado 23514).
--    VERIFICADO desde afuera (pg_lector): el rollback no dejó nada (sin tablas, funciones ni columnas nuevas;
--    permiso vacío; políticas 8 · 8 · 7; interruptor del asistente intacto).
--
-- CÓMO SE LEE
--   Una tabla de %d filas, TODAS con ok = true. Un RECHAZA da ok solo si el SQLSTATE esperado está
--   en `obtenido` (no vale rechazar por el motivo de al lado). Si el editor dice "Success. No rows
--   returned", no llegó al final y no vale.
--   42501 = RLS o sin permiso · 23514 = check · 23505 = único.
--   X1/X2: Instinct intenta un INSERT en CADA tabla de public que no es de esta fase; ninguna lo
--   acepta (X1), y todas rebotan por RLS o permiso, salvo las que tienen una guardia BEFORE INSERT
--   (corre antes que el RLS): esas se nombran aparte en `obtenido` (X2).
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE DDL (copia de INSTINCT_FASE2.sql) ▼▼▼
""" % (MD5, total))
out.append(DDL)
out.append("""-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

do $$
declare
  v_socia text; v_equipo text; v_asis text; v_n int; v_t record; v_otros text := ''; v_guardia text := ''; v_entraron text := '';
  v_pa bigint; v_pb bigint; v_pc bigint; v_ps bigint; v_x bigint;
  v_vp1 uuid := gen_random_uuid(); v_vp2 uuid := gen_random_uuid(); v_vp3 uuid := gen_random_uuid();
  v_vp4 uuid := gen_random_uuid(); v_vp_ajena uuid := gen_random_uuid();
  v_res jsonb := '[]'::jsonb;
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by id limit 1;
  select email into v_equipo from v_acceso_usuario where perfil not in ('socias', 'asistente') and activo order by id limit 1;
  select email into v_asis   from v_acceso_usuario where perfil = 'asistente' and activo order by id limit 1;
  if v_socia is null or v_equipo is null or v_asis is null then
    raise exception 'el ensayo necesita una socia, alguien de equipo y el asistente (%, %, %)', v_socia, v_equipo, v_asis;
  end if;
  -- El interruptor general del asistente ENCENDIDO para el ensayo (se deshace con el rollback).
  insert into asistente_interruptor (encendido, motivo, creado_por) values (true, 'ensayo fase 2', v_socia);
  -- Una vista previa de OTRA persona, para I3 (la escribe el editor, por encima del RLS).
  insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor,
    factura_ref, creado_por) values ('Cacao Ajeno', 12, 15, '2363000000000', 1183, 8910.89, '2292',
    '00100001010000008144', v_socia) returning id into v_x;
  insert into asistente_vista_previa (id, accion, propuesta_id, huella, codigo, creado_por)
    values (v_vp_ajena, 'crear_insumo', v_x, 'eb2df9d55fa4451b', '7777', v_socia);

""")
for t in PRUEBAS:
    out.append(bloque(*t))
out.append("""
  -- ── X · Instinct contra CADA tabla de public que no es de esta fase ──
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  for v_t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
              where n.nspname = 'public' and c.relkind in ('r', 'p')
                and c.relname not in ('compra_insumo_propuesta', 'compra_insumo_odoo', 'asistente_vista_previa', 'asistente_intento')
              order by c.relname loop
    begin
      execute format('insert into public.%%I default values', v_t.relname);
      v_entraron := v_entraron || v_t.relname || ' ';
    exception when others then
      if sqlstate <> '42501' then
        -- Una guardia BEFORE INSERT corre antes que el RLS: si la tabla tiene una, el rechazo es suyo.
        if exists (select 1 from pg_trigger g where g.tgrelid = ('public.' || quote_ident(v_t.relname))::regclass
                     and not g.tgisinternal and (g.tgtype & 2) = 2 and (g.tgtype & 4) = 4) then
          v_guardia := v_guardia || v_t.relname || ' (' || sqlstate || ') ';
        else
          v_otros := v_otros || v_t.relname || ' (' || sqlstate || ') ';
        end if;
      end if;
    end;
  end loop;
  v_res := v_res || jsonb_build_object('p','X1 Instinct no puede insertar en NINGUNA otra tabla de public','esperado','ninguna',
                                       'obtenido',coalesce(nullif(v_entraron,''),'ninguna'),'ok',v_entraron='');
  v_res := v_res || jsonb_build_object('p','X2 todas rebotan por RLS o permiso (42501), o por su guardia BEFORE INSERT','esperado','sin otros motivos',
                                       'obtenido',coalesce(nullif(v_otros,''),'sin otros motivos')
                                         ||coalesce(' · por guardia: '||nullif(v_guardia,''),''),'ok',v_otros='');

  -- ── Z · el editor SQL ──
  perform set_config('role', 'postgres', true);
  select count(*) into v_n from compra_insumo_odoo where hecho_por_asistente and propuesta_id in (v_pa, v_pb);
  v_res := v_res || jsonb_build_object('p','Z1 quedaron 2 rastros «hecho por Instinct» (R1 y R10)','esperado','2','obtenido',v_n::text,'ok',v_n=2);
  select count(*) into v_n from asistente_intento where vista_previa_id in (v_vp1, v_vp4);
  v_res := v_res || jsonb_build_object('p','Z2 quedaron 4 intentos (I1 + I4), ninguno borrado','esperado','4','obtenido',v_n::text,'ok',v_n=4);
  select count(*) into v_n from pg_policy where polname = 'asistente_no_inserta'
     and polrelid in ('public.asistente_vista_previa'::regclass, 'public.asistente_intento'::regclass,
                      'public.compra_insumo_propuesta'::regclass, 'public.compra_insumo_odoo'::regclass);
  v_res := v_res || jsonb_build_object('p','Z3 «asistente_no_inserta» cambiada SOLO en las 4 tablas de la fase','esperado','0','obtenido',v_n::text,'ok',v_n=0);

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: %d filas, todas ok = true.

rollback;
""" % total)
destino = os.path.join(REPO, "ENSAYO_INSTINCT_FASE2.sql")
open(destino, "w", encoding="utf-8").write("".join(out))
print("ENSAYO_INSTINCT_FASE2.sql · %d pruebas · md5 DDL %s" % (total, MD5))
