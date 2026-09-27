#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Arma ENSAYO_VISTAS_INVOKER.sql a partir de ENTREGAS_VISTAS_INVOKER.sql.

El bloque DDL se copia BYTE A BYTE del pegado, cortado por sus dos marcas,
nunca por numero de linea (CLAUDE.md, 16-sep).

QUE MIDE, dentro de UNA transaccion que termina en rollback:
  1_antes          las seis vistas, como postgres, anon, socia y equipo
  (el bloque DDL del pegado, entero)
  2_solo_invoker   SOLO anon, con un `grant select` de mentira que devuelve el
                   permiso a las dos vistas: prueba que `security_invoker` SOLO
                   ya cierra la fuga (0 filas), independiente del revoke
  3_final          las seis vistas otra vez, como los cuatro

Cada medicion guarda cantidad de filas y un md5 del contenido ordenado: "la
misma cantidad" no alcanza, porque una vista del saldo podria devolver las
mismas filas con otro numero adentro.

    python3 herramientas/ensayos/armar_ensayo_vistas_invoker.py
"""
import hashlib, os, re, sys

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
PEGADO = os.path.join(RAIZ, 'ENTREGAS_VISTAS_INVOKER.sql')
ENSAYO = os.path.join(RAIZ, 'ENSAYO_VISTAS_INVOKER.sql')

txt = open(PEGADO, encoding='utf-8').read()
A, B = '-- ═══ DDL · DESDE ACA', '-- ═══ DDL · HASTA ACA ═══'
if txt.count(A) != 1 or txt.count(B) != 1 or txt.find(B) < txt.find(A):
    sys.exit('no encuentro las dos marcas del bloque DDL, una sola vez cada una')
ddl = txt[txt.find(A):txt.find(B) + len(B)]
for mala in ('begin;', 'commit;', 'rollback;'):
    if re.search(r'^\s*' + mala, ddl, re.M | re.I):
        sys.exit('el bloque DDL trae un %s suelto: no se arma' % mala)
huella = hashlib.md5(ddl.encode('utf-8')).hexdigest()

LAS_DOS = ['ent_alisto_lote_efectivo', 'v_ent_indeterminado_pendiente']
# Las que dependen de ent_alisto_lote_efectivo (medido con pg_depend el 27-sep).
DEPENDIENTES = ['ent_salido_del_congelador_desde_ancla', 'ent_entregado_desde_ancla',
                'v_ent_excepcion_pendiente', 'v_ent_excepcion_pendiente_pedido']
SEIS = LAS_DOS + DEPENDIENTES

def arr(xs):
    return "array[" + ", ".join("'%s'" % x for x in xs) + "]"

out = f"""-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_VISTAS_INVOKER.sql  ·  27-sep-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- security_invoker + revoke de anon en ent_alisto_lote_efectivo y
-- v_ent_indeterminado_pendiente
--
-- ⚠️ ARCHIVO GENERADO. No se edita a mano: se regenera con
--     python3 herramientas/ensayos/armar_ensayo_vistas_invoker.py
--   El bloque DDL es el de ENTREGAS_VISTAS_INVOKER.sql BYTE A BYTE, cortado
--   por sus marcas. md5 del bloque: {huella}
--
-- QUE HACE
--   Mide SEIS vistas (las dos del cambio y las cuatro que dependen de
--   ent_alisto_lote_efectivo) como postgres, anon, una socia y una persona de
--   equipo, ANTES y DESPUES del bloque DDL. Cada medicion: filas y md5 del
--   contenido. Las sesiones se simulan con `request.jwt.claims` + `role`, como
--   la app (con RLS). Ningun correo va escrito: la socia sale de
--   v_acceso_usuario y la de equipo es la que mas preparaciones registro.
--   Todo adentro de una transaccion, y rollback.
--
-- COMO SE LEE
--   Una tabla, TODAS las filas con ok = true.
--   · S  (socia / equipo / postgres): mismas filas Y mismo contenido antes y
--        despues. 🔴 Si alguna da false, la app perderia o cambiaria datos:
--        NO se pega.
--   · A0 (anon, antes): la foto de hoy. En ent_alisto_lote_efectivo tiene que
--        verse la FUGA (anon ve lo mismo que postgres).
--   · A1 (anon, solo security_invoker): 0 filas en las dos, sin error.
--   · A2 (anon, final): RECHAZA con 42501 y el nombre de la vista que lo frena.
--   · E  (estructura): invoker en las dos, anon sin permisos, authenticated lee.
--   Si el editor dice "Success. No rows returned", no llego al final y no vale.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ── QUIEN ES QUIEN (sin correos escritos) ─────────────────────────────────
select set_config('ensayo.socia',
  (select email from public.v_acceso_usuario where perfil = 'socias' and activo order by email limit 1), true);
select set_config('ensayo.equipo',
  (select a.creado_por from public.ent_alisto a
     join public.v_acceso_usuario u on lower(u.email) = lower(a.creado_por)
    where u.perfil = 'equipo' and u.activo
    group by a.creado_por order by count(*) desc limit 1), true);
select set_config('ensayo.med', '[]', true);

-- ── LA MEDICION (funcion temporal: se va con el rollback) ─────────────────
create function pg_temp.medir(p_etapa text, p_quienes text[], p_vistas text[]) returns void
language plpgsql as $$
declare
  v_quien text; v_vista text; v_n bigint; v_h text;
  v_res jsonb := current_setting('ensayo.med')::jsonb;
begin
  if coalesce(current_setting('ensayo.socia', true), '') = ''
     or coalesce(current_setting('ensayo.equipo', true), '') = '' then
    raise exception 'falta la socia o la persona de equipo para ensayar';
  end if;
  foreach v_quien in array p_quienes loop
    foreach v_vista in array p_vistas loop
      if v_quien = 'postgres' then
        perform set_config('request.jwt.claims', '', true);
        perform set_config('role', 'postgres', true);
      elsif v_quien = 'anon' then
        perform set_config('request.jwt.claims', '{{"role":"anon"}}', true);
        perform set_config('role', 'anon', true);
      else
        perform set_config('request.jwt.claims',
          json_build_object('email', current_setting('ensayo.' || v_quien), 'role', 'authenticated')::text, true);
        perform set_config('role', 'authenticated', true);
      end if;
      begin
        execute format('select count(*), md5(coalesce(string_agg(t::text, ''|'' order by t::text), '''')) from public.%I t', v_vista)
          into v_n, v_h;
        v_res := v_res || jsonb_build_object('etapa', p_etapa, 'quien', v_quien, 'vista', v_vista,
                                             'n', v_n, 'h', v_h, 'est', null, 'err', null);
      exception when others then
        v_res := v_res || jsonb_build_object('etapa', p_etapa, 'quien', v_quien, 'vista', v_vista,
                                             'n', null, 'h', null, 'est', sqlstate, 'err', sqlerrm);
      end;
    end loop;
  end loop;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('ensayo.med', v_res::text, true);
end $$;

select pg_temp.medir('1_antes', array['postgres','anon','socia','equipo'], {arr(SEIS)});


{ddl}


-- ── SOLO LA PRIMERA CAPA: se le devuelve a anon el SELECT (de mentira, se va
-- con el rollback) para medir que security_invoker SOLO ya da 0 filas.
grant select on table public.ent_alisto_lote_efectivo, public.v_ent_indeterminado_pendiente to anon;
select pg_temp.medir('2_solo_invoker', array['anon'], {arr(LAS_DOS)});
revoke select on table public.ent_alisto_lote_efectivo, public.v_ent_indeterminado_pendiente from anon;

select pg_temp.medir('3_final', array['postgres','anon','socia','equipo'], {arr(SEIS)});


-- ── EL RESULTADO. Esta tabla ES el ensayo. ────────────────────────────────
with m as (select * from jsonb_to_recordset(current_setting('ensayo.med')::jsonb)
             as r(etapa text, quien text, vista text, n bigint, h text, est text, err text)),
a as (select * from m where etapa = '1_antes'),
s as (select * from m where etapa = '2_solo_invoker'),
f as (select * from m where etapa = '3_final'),
filas as (
  -- E · la estructura que dejo el bloque DDL
  select 0 as ord, 'E · estructura' as prueba,
         'invoker 2 · anon con permiso 0 · authenticated lee 2' as esperado,
         'invoker ' || (select count(*) from pg_class
                         where oid in ('public.ent_alisto_lote_efectivo'::regclass, 'public.v_ent_indeterminado_pendiente'::regclass)
                           and 'security_invoker=true' = any(reloptions))
         || ' · anon con permiso ' || (select count(*) from unnest({arr(['public.' + x for x in LAS_DOS])}) v
                                        where has_table_privilege('anon', v, 'SELECT,INSERT,UPDATE,DELETE'))
         || ' · authenticated lee ' || (select count(*) from unnest({arr(['public.' + x for x in LAS_DOS])}) v
                                        where has_table_privilege('authenticated', v, 'SELECT')) as obtenido,
         ((select count(*) from pg_class
            where oid in ('public.ent_alisto_lote_efectivo'::regclass, 'public.v_ent_indeterminado_pendiente'::regclass)
              and 'security_invoker=true' = any(reloptions)) = 2
          and (select count(*) from unnest({arr(['public.' + x for x in LAS_DOS])}) v
                where has_table_privilege('anon', v, 'SELECT,INSERT,UPDATE,DELETE')) = 0
          and (select count(*) from unnest({arr(['public.' + x for x in LAS_DOS])}) v
                where has_table_privilege('authenticated', v, 'SELECT')) = 2) as ok
  union all
  -- S · la app no pierde ni cambia nada
  select 1, 'S · ' || a.quien || ' · ' || a.vista,
         'mismas filas y mismo contenido',
         coalesce(a.n::text, 'ERROR ' || a.est) || ' → ' || coalesce(f.n::text, 'ERROR ' || f.est)
           || case when a.h = f.h then ' · contenido igual' else ' · contenido DISTINTO' end,
         (a.est is null and f.est is null and a.n = f.n and a.h = f.h)
    from a join f on f.quien = a.quien and f.vista = a.vista
   where a.quien <> 'anon'
  union all
  -- A0 · la foto de hoy con la llave publica
  select 2, 'A0 · anon antes · ' || a.vista,
         case when a.vista = 'ent_alisto_lote_efectivo' then 'FUGA: las mismas filas que postgres'
              else 'foto de antes, sin error' end,
         coalesce(a.n::text || ' filas', 'ERROR ' || a.est || ' · ' || a.err) || ' (postgres ve ' || p.n || ')',
         case when a.vista = 'ent_alisto_lote_efectivo' then a.est is null and a.n = p.n and p.n > 0
              else a.est is null end
    from a join a p on p.vista = a.vista and p.quien = 'postgres'
   where a.quien = 'anon'
  union all
  -- A1 · security_invoker solo
  select 3, 'A1 · anon, solo security_invoker · ' || s.vista, '0 filas, sin error',
         coalesce(s.n::text || ' filas', 'ERROR ' || s.est || ' · ' || s.err),
         s.est is null and s.n = 0
    from s
  union all
  -- A2 · las dos capas: rechaza, y por la vista que corresponde
  select 4, 'A2 · anon, final · ' || f.vista,
         'RECHAZA · 42501 · permission denied for view '
           || case when f.vista = 'v_ent_indeterminado_pendiente' then f.vista else 'ent_alisto_lote_efectivo' end,
         coalesce('RECHAZA · ' || f.est || ' · ' || f.err, 'ENTRA · ' || f.n || ' filas'),
         f.est = '42501'
           and strpos(f.err, 'permission denied for view '
                 || case when f.vista = 'v_ent_indeterminado_pendiente' then f.vista else 'ent_alisto_lote_efectivo' end) > 0
    from f
   where f.quien = 'anon'
)
select prueba, esperado, obtenido, ok from filas order by ord, prueba;

rollback;

-- ── DESPUES DEL ROLLBACK (opcional, con pg_lector) ────────────────────────
-- select reloptions from pg_class where relname = 'ent_alisto_lote_efectivo';  -> NULL: no dejo nada.
"""
open(ENSAYO, 'w', encoding='utf-8').write(out)
n = 1 + 3 * len(SEIS) + len(SEIS) + len(LAS_DOS) + len(SEIS)
print('escrito', os.path.basename(ENSAYO), '·', n, 'filas esperadas · md5 DDL', huella)
