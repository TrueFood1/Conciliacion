#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
armar_cc_ampliado.py — arma TICKETS_CC_AMPLIADO.sql (pegado) y ENSAYO_TICKETS_CC_AMPLIADO.sql (19-oct-2026)
desde las CUATRO guardias VIVAS de los tickets (solo lectura con pg_lector), con cambios mínimos y
comprobados uno por uno. El pegado y el ensayo frenan si alguna guardia viva ya no tiene el md5 medido acá.

Decisión de Andrea (19-oct): truefie_cc, en tickets de Truefie Y en los pendientes propios, puede leer,
agregar tickets, explicaciones, marcas y estados (en_curso · en_validacion · disponible · bloqueado ·
cerrado), firmado 'cc-truefie'. Descartar y posponer siguen siendo solo de las socias. Revierte a propósito
«truefie_cc no ve los propios» (27-sep) y «cc-sql no toca propios» (23-sep) — para truefie_cc; cc-sql
(el editor SQL) queda igual.

    python3 herramientas/tickets/armar_cc_ampliado.py
"""
import hashlib, os, sys
AQUI = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(AQUI))
sys.path.insert(0, os.path.dirname(AQUI))
from pg_lector import Lector, clave                         # noqa: E402

GUARDIAS = ("ticket_firma_guard", "ticket_detalle_guard", "ticket_estado_guard", "ticket_marca_guard")
with Lector(clave()[0]) as db:
    VIVO = {g: db.consulta("select pg_get_functiondef('public.%s()'::regprocedure), md5(prosrc) from pg_proc "
                           "where oid = 'public.%s()'::regprocedure" % (g, g))[1][0] for g in GUARDIAS}


def cambiar(nombre, pares):
    d = VIVO[nombre][0]
    for a, b in pares:
        assert d.count(a) == 1, "%s: el pedazo a cambiar no está una vez: %r" % (nombre, a[:60])
        d = d.replace(a, b)
    return d.rstrip() + ";\n"


AMB_VIEJO = """    select t.ambito into amb from ticket t where t.id = new.ticket_id;
    if amb is distinct from 'truefie' then
      raise exception 'truefie_cc no ve el ticket %: no existe o no es de Truefie. '
        'Los pendientes propios los mueve Andrea.', new.ticket_id;
    end if;"""
AMB_NUEVO = """    -- 19-oct-2026 (decisión de Andrea): truefie_cc trabaja en Truefie Y en los pendientes propios.
    select t.ambito into amb from ticket t where t.id = new.ticket_id;
    if amb is null then
      raise exception 'no existe el ticket %', new.ticket_id;
    end if;"""

firma = cambiar("ticket_firma_guard", [("""begin
  quien := nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email';""",
"""begin
  -- ══ CC CON ROL PROPIO · truefie_cc (19-oct-2026): agrega tickets, de Truefie y propios ══
  if current_user = 'truefie_cc' then
    if new.creado_por is distinct from 'cc-truefie' then
      raise exception 'truefie_cc firma creado_por = "cc-truefie". Vino: %', new.creado_por;
    end if;
    return new;
  end if;
  quien := nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email';""")])

detalle = cambiar("ticket_detalle_guard", [(AMB_VIEJO, AMB_NUEVO)])

estado = cambiar("ticket_estado_guard", [(AMB_VIEJO, AMB_NUEVO),
  ("""      if coalesce(new.nota, '') !~ '(^|[^0-9a-z])(b[0-9]{2,3}|[0-9a-f]{7,40})([^0-9a-z]|$)' then
        raise exception 'cerrar sin evidencia no: la nota tiene que nombrar el build (b72) o el '
          'commit (7 a 40 hex) donde quedo resuelto. Vino: %', coalesce(new.nota, '(vacia)');
      end if;""",
   """      -- Un pendiente propio puede cerrarse también con un archivo, un correo o un enlace (19-oct).
      if coalesce(new.nota, '') !~ '(^|[^0-9a-z])(b[0-9]{2,3}|[0-9a-f]{7,40})([^0-9a-z]|$)'
         and not (amb = 'propio' and coalesce(new.nota, '') ~* '^(archivo|correo|enlace): [^ ]') then
        raise exception 'cerrar sin evidencia no: la nota tiene que nombrar el build (b72) o el '
          'commit (7 a 40 hex) donde quedo resuelto; en un propio vale también "archivo: …", '
          '"correo: …" o "enlace: …". Vino: %', coalesce(new.nota, '(vacia)');
      end if;""")])

marca = cambiar("ticket_marca_guard", [("""begin
  if not exists (select 1 from ticket t where t.id = new.ticket_id) then
    raise exception 'no existe el ticket %', new.ticket_id;
  end if;""",
"""begin
  -- ══ CC CON ROL PROPIO · truefie_cc (19-oct-2026): marca tickets, de Truefie y propios ══
  if current_user = 'truefie_cc' then
    if not exists (select 1 from ticket t where t.id = new.ticket_id) then
      raise exception 'no existe el ticket %', new.ticket_id;
    end if;
    if new.creado_por is distinct from 'cc-truefie' then
      raise exception 'truefie_cc firma creado_por = "cc-truefie". Vino: %', new.creado_por;
    end if;
    return new;
  end if;
  if not exists (select 1 from ticket t where t.id = new.ticket_id) then
    raise exception 'no existe el ticket %', new.ticket_id;
  end if;""")])

GUARDA = "do $$ begin\n" + "".join(
    "  if (select md5(prosrc) from pg_proc where oid = 'public.%s()'::regprocedure) <> '%s' then\n"
    "    raise exception '%s cambió desde el 19-oct: parar y volver a armar este archivo';\n  end if;\n" % (g, VIVO[g][1], g)
    for g in GUARDIAS) + "end $$;\n"

DDL = """-- ▼▼▼ BLOQUE DDL ▼▼▼
-- §1 · permisos: agregar tickets y marcas (lo demás ya lo tenía)
grant insert on table public.ticket, public.ticket_marca to truefie_cc;
grant execute on function public.ticket_firma_guard(), public.ticket_marca_guard() to truefie_cc;

-- §2 · RLS: ve y escribe en Truefie Y en propios, siempre con SU firma
alter policy ticket_cc_sel on public.ticket using (ambito in ('truefie', 'propio'));
create policy ticket_cc_ins on public.ticket for insert to truefie_cc
  with check (creado_por = 'cc-truefie' and ambito in ('truefie', 'propio'));
alter policy ticket_detalle_cc_ins on public.ticket_detalle
  with check (creado_por = 'cc-truefie' and clase = any (array['cierre', 'anuncio', 'explicacion'])
              and exists (select 1 from ticket t where t.id = ticket_detalle.ticket_id));
alter policy ticket_estado_cc_sel on public.ticket_estado
  using (exists (select 1 from ticket t where t.id = ticket_estado.ticket_id));
alter policy ticket_estado_cc_ins on public.ticket_estado
  with check (creado_por = 'cc-truefie'
              and estado = any (array['cerrado', 'en_validacion', 'en_curso', 'disponible', 'bloqueado'])
              and exists (select 1 from ticket t where t.id = ticket_estado.ticket_id));
create policy ticket_marca_cc_ins on public.ticket_marca for insert to truefie_cc
  with check (creado_por = 'cc-truefie' and exists (select 1 from ticket t where t.id = ticket_marca.ticket_id));

-- §3 · las cuatro guardias: SOLO el bloque de truefie_cc (y la evidencia de cierre de un propio)
""" + firma + "\n" + detalle + "\n" + estado + "\n" + marca + "-- ▲▲▲ FIN BLOQUE DDL ▲▲▲\n"

CONTROL = """select (select count(*) from pg_policy where (select oid from pg_roles where rolname = 'truefie_cc') = any(polroles)) as politicas_cc,
       (select string_agg(t || ':' || p, ' ' order by t, p) from (select tb as t, unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) as p
          from unnest(array['ticket','ticket_detalle','ticket_estado','ticket_marca']) tb) x
         where has_table_privilege('truefie_cc', 'public.' || t, p)) as permisos_cc,
       (select count(*) from pg_proc where proname in ('ticket_firma_guard','ticket_detalle_guard','ticket_estado_guard','ticket_marca_guard')
          and strpos(prosrc, 'truefie_cc') > 0) as guardias_con_cc,
       (select count(*) from pg_policy where (select oid from pg_roles where rolname = 'truefie_cc') = any(polroles)
          and coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), '') ~ 'descartado|pospuesto') as cc_descarta_o_pospone;
"""
ESPERADO = ("-- ESPERADO: 6 · ticket:INSERT ticket:SELECT ticket_detalle:INSERT ticket_estado:INSERT ticket_estado:SELECT "
            "ticket_marca:INSERT · 4 · 0")
md5 = hashlib.md5(DDL.encode()).hexdigest()

CAB = """-- ═══════════════════════════════════════════════════════════════════════════
-- %s  ·  19-oct-2026  ·  truefie_cc AMPLIADO: tickets de Truefie y pendientes propios
-- ⛔ NO SE CORRIÓ. Armado por herramientas/tickets/armar_cc_ampliado.py desde las guardias VIVAS del 19-oct
--    (md5 del bloque DDL: %s). Antes: ENSAYO_TICKETS_CC_AMPLIADO.sql en verde.
--
-- DECISIÓN DE ANDREA (19-oct): truefie_cc, en Truefie Y en propios: lee, agrega tickets, explicaciones,
--   marcas y estados (en_curso · en_validacion · disponible · bloqueado · cerrado), firmado 'cc-truefie'.
--   Descartar y posponer: solo socias. Revierte A PROPÓSITO «truefie_cc no ve propios» (TICKETS_CC.sql, 27-sep)
--   y la regla del 23-sep de que CC no toca propios — para truefie_cc; el editor SQL (cc-sql) queda IGUAL.
--
-- QUÉ CAMBIA, Y NADA MÁS
--   §1  grant INSERT en ticket y ticket_marca (ya tenía: SELECT ticket · INSERT detalle · INSERT/SELECT estado).
--   §2  sus políticas: sin el «solo truefie»; dos nuevas (agregar ticket, agregar marca). Nunca update/delete.
--   §3  las cuatro guardias: el bloque de truefie_cc. Siguen: firma fija 'cc-truefie'; estados SIN descartado
--       ni pospuesto; no toca lo ya cerrado/pospuesto/descartado (lo reabre Andrea); cerrar con evidencia en
--       una línea (build o commit; en un propio también «archivo: …», «correo: …» o «enlace: …»).
--       Los caminos de las socias (app) y del editor SQL: byte a byte los vivos.
-- ═══════════════════════════════════════════════════════════════════════════
"""

PEGADO = (CAB % ("TICKETS_CC_AMPLIADO.sql", md5) + "begin;\n\n" + GUARDA + "\n" + DDL +
          "\n-- CONTROL, justo antes del commit.\n" + ESPERADO + "\n" + CONTROL + "commit;\n")
open(os.path.join(REPO, "TICKETS_CC_AMPLIADO.sql"), "w", encoding="utf-8").write(PEGADO)
open(os.path.join(AQUI, "_ddl_cc_ampliado.sql"), "w", encoding="utf-8").write(GUARDA + "\n" + DDL)
print("TICKETS_CC_AMPLIADO.sql · md5 DDL %s · md5 vivos: %s" % (md5[:8], " ".join("%s=%s" % (g.split('_')[1], VIVO[g][1][:8]) for g in GUARDIAS)))
