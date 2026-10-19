-- ═══════════════════════════════════════════════════════════════════════════
-- TICKETS_CC_AMPLIADO.sql  ·  19-oct-2026  ·  truefie_cc AMPLIADO: tickets de Truefie y pendientes propios
-- ⛔ NO SE CORRIÓ. Ensayo ✅ 26/26 el 19-oct (corrido por CC, rollback verificado). Armado por herramientas/tickets/armar_cc_ampliado.py desde las guardias VIVAS del 19-oct
--    (md5 del bloque DDL: 350cd7bbcca6be2cdd784889268feccf). Antes: ENSAYO_TICKETS_CC_AMPLIADO.sql en verde.
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
begin;

do $$ begin
  if (select md5(prosrc) from pg_proc where oid = 'public.ticket_firma_guard()'::regprocedure) <> '018189af7cbea55ce31ce3d5f649c2b1' then
    raise exception 'ticket_firma_guard cambió desde el 19-oct: parar y volver a armar este archivo';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.ticket_detalle_guard()'::regprocedure) <> '00c71e82f346a69da6500d247e6bac85' then
    raise exception 'ticket_detalle_guard cambió desde el 19-oct: parar y volver a armar este archivo';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.ticket_estado_guard()'::regprocedure) <> '21f275c871fb097fb011d8daf249b151' then
    raise exception 'ticket_estado_guard cambió desde el 19-oct: parar y volver a armar este archivo';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.ticket_marca_guard()'::regprocedure) <> 'bfca3ad23b542094c47c5eb20d29f007' then
    raise exception 'ticket_marca_guard cambió desde el 19-oct: parar y volver a armar este archivo';
  end if;
end $$;

-- ▼▼▼ BLOQUE DDL ▼▼▼
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
CREATE OR REPLACE FUNCTION public.ticket_firma_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare quien text;
begin
  -- ══ CC CON ROL PROPIO · truefie_cc (19-oct-2026): agrega tickets, de Truefie y propios ══
  if current_user = 'truefie_cc' then
    if new.creado_por is distinct from 'cc-truefie' then
      raise exception 'truefie_cc firma creado_por = "cc-truefie". Vino: %', new.creado_por;
    end if;
    return new;
  end if;
  quien := nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email';
  if quien is null then
    if new.creado_por not like 'ticket-sql%' then
      raise exception 'un ticket sin sesion de Supabase (SQL Editor) tiene que firmar '
        'creado_por empezando con "ticket-sql". Vino: %', new.creado_por;
    end if;
    return new;
  end if;
  if lower(btrim(new.creado_por)) <> lower(btrim(quien)) then
    raise exception 'creado_por dice % y la sesion es de %. La firma no se elige.',
      new.creado_por, quien;
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.ticket_detalle_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare quien text; socia boolean; amb text;
begin
  -- ══ CC CON ROL PROPIO · truefie_cc (27-sep-2026) ═══════════════════════
  -- Primero, por la misma razon que en ticket_estado_guard: un propio no lo ve.
  if current_user = 'truefie_cc' then
    -- 19-oct-2026 (decisión de Andrea): truefie_cc trabaja en Truefie Y en los pendientes propios.
    select t.ambito into amb from ticket t where t.id = new.ticket_id;
    if amb is null then
      raise exception 'no existe el ticket %', new.ticket_id;
    end if;
    if new.creado_por is distinct from 'cc-truefie' then
      raise exception 'truefie_cc firma creado_por = "cc-truefie". Vino: %', new.creado_por;
    end if;
    if new.clase not in ('cierre','anuncio','explicacion') then
      raise exception 'truefie_cc solo escribe cierres, anuncios y explicaciones; "%" lo define una socia.', new.clase;
    end if;
    return new;
  end if;

  if not exists (select 1 from ticket t where t.id = new.ticket_id) then
    raise exception 'no existe el ticket %', new.ticket_id;
  end if;
  quien := nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email';

  if quien is null then
    -- Mismo aviso que en §2: esto NO es un candado, es una convencion para
    -- que la fila diga de donde vino. El trigger no puede saber quien es CC.
    if new.creado_por not like 'cc-sql%' then
      raise exception 'sin sesion de Supabase (SQL Editor) hay que firmar creado_por '
        'empezando con "cc-sql". Vino: %', new.creado_por;
    end if;
    if new.clase not in ('cierre','anuncio','explicacion') then
      raise exception 'desde el SQL Editor solo se escriben cierres, anuncios y explicaciones. '
        '"Qué se espera" y "Criterio de terminado" los define una socia: si el mismo '
        'lado que escribe el criterio es el que lo cumple, el criterio no controla nada. '
        'Vino: %', new.clase;
    end if;
    return new;
  end if;

  if lower(btrim(new.creado_por)) <> lower(btrim(quien)) then
    raise exception 'creado_por dice % y la sesion es de %. La firma no se elige.',
      new.creado_por, quien;
  end if;
  socia := exists (select 1 from acceso_usuario a
                    where lower(a.email) = lower(quien)
                      and a.perfil = 'socias' and a.activo);
  if not socia and new.clase in ('espera','criterio') then
    raise exception '"%" lo define una socia, y % no lo es.', new.clase, quien;
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.ticket_estado_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare quien text; socia boolean; amb text; ult text;
begin
  -- ══ CC CON ROL PROPIO · truefie_cc (27-sep-2026, opcion A de Andrea) ═══
  -- Va PRIMERO, antes que el "no existe": la RLS le esconde a truefie_cc los
  -- pendientes propios, asi que para el un propio no existe, y el rechazo
  -- tiene que decir el motivo de verdad y no el de al lado.
  if current_user = 'truefie_cc' then
    -- 19-oct-2026 (decisión de Andrea): truefie_cc trabaja en Truefie Y en los pendientes propios.
    select t.ambito into amb from ticket t where t.id = new.ticket_id;
    if amb is null then
      raise exception 'no existe el ticket %', new.ticket_id;
    end if;
    if new.creado_por is distinct from 'cc-truefie' then
      raise exception 'truefie_cc firma creado_por = "cc-truefie". Vino: %', new.creado_por;
    end if;
    if new.estado not in ('cerrado','en_validacion','en_curso','disponible','bloqueado') then
      raise exception 'truefie_cc no pone "%": descartar y posponer son decisiones de Andrea.',
        new.estado;
    end if;
    select x.estado into ult from ticket_estado x
     where x.ticket_id = new.ticket_id order by x.creado_en desc, x.id desc limit 1;
    if ult in ('cerrado','pospuesto','descartado') then
      raise exception 'el ticket % esta "%": lo reabre Andrea desde la pantalla, no truefie_cc.',
        new.ticket_id, ult;
    end if;
    if new.estado = 'cerrado' then
      if strpos(coalesce(new.nota, ''), chr(10)) > 0 then
        raise exception 'la evidencia del cierre va en UNA linea.';
      end if;
      -- Un pendiente propio puede cerrarse también con un archivo, un correo o un enlace (19-oct).
      if coalesce(new.nota, '') !~ '(^|[^0-9a-z])(b[0-9]{2,3}|[0-9a-f]{7,40})([^0-9a-z]|$)'
         and not (amb = 'propio' and coalesce(new.nota, '') ~* '^(archivo|correo|enlace): [^ ]') then
        raise exception 'cerrar sin evidencia no: la nota tiene que nombrar el build (b72) o el '
          'commit (7 a 40 hex) donde quedo resuelto; en un propio vale también "archivo: …", '
          '"correo: …" o "enlace: …". Vino: %', coalesce(new.nota, '(vacia)');
      end if;
      if new.build_arreglo is not null and new.build_arreglo !~ '^b[0-9]{2,3}$' then
        raise exception 'build_arreglo es un build como "b72". Vino: %', new.build_arreglo;
      end if;
    end if;
    return new;
  end if;

  if not exists (select 1 from ticket t where t.id = new.ticket_id) then
    raise exception 'no existe el ticket %', new.ticket_id;
  end if;
  select t.ambito into amb from ticket t where t.id = new.ticket_id;
  quien := nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email';

  if quien is null then
    -- 🔴 LO PRIMERO: un pendiente PROPIO no se mueve sin sesion, nunca.
    -- Va ANTES que la firma y que la lista de estados a proposito: no es "cc-sql
    -- puede poner estos estados menos en los propios", es "en los propios no
    -- entra por aca". Que el motivo del rechazo sea el de verdad y no el de al lado.
    if amb = 'propio' then
      raise exception 'los pendientes propios los mueve Andrea desde la pantalla, '
        'no cc-sql. Un pendiente propio no se revisa abriendo codigo. Ticket %',
        new.ticket_id;
    end if;
    if new.creado_por not like 'cc-sql%' then
      raise exception 'un cambio de estado sin sesion de Supabase (SQL Editor) tiene que '
        'firmar creado_por empezando con "cc-sql". Vino: %', new.creado_por;
    end if;
    if new.estado not in ('en_curso','en_validacion','disponible','bloqueado') then
      raise exception 'desde el SQL Editor se puede poner en_curso, en_validacion, '
        'disponible o bloqueado. Cerrar, posponer y descartar es de las socias, y desde '
        'aca no se sabe cual socia es. Vino: %', new.estado;
    end if;
    return new;
  end if;

  if lower(btrim(new.creado_por)) <> lower(btrim(quien)) then
    raise exception 'creado_por dice % y la sesion es de %. La firma no se elige.',
      new.creado_por, quien;
  end if;

  socia := exists (select 1 from acceso_usuario a
                    where lower(a.email) = lower(quien)
                      and a.perfil = 'socias' and a.activo);
  if not socia then
    raise exception 'mover el estado de un ticket es de un perfil socias, y % no lo es. '
      'Reportar es de todos; decidir que pasa con lo reportado, no.', quien;
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.ticket_marca_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare quien text; socia boolean; amb text;
begin
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
  end if;
  select t.ambito into amb from ticket t where t.id = new.ticket_id;
  quien := nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email';

  if quien is null then
    if amb = 'propio' then
      raise exception 'un pendiente propio no lo marca cc-sql: la marca es lo que CC '
        'midio abriendo el codigo, y aca no hay codigo. Ticket %', new.ticket_id;
    end if;
    if new.creado_por not like 'cc-sql%' then
      raise exception 'una revision sin sesion de Supabase (SQL Editor) tiene que firmar '
        'creado_por empezando con "cc-sql". Vino: %', new.creado_por;
    end if;
    return new;
  end if;

  if lower(btrim(new.creado_por)) <> lower(btrim(quien)) then
    raise exception 'creado_por dice % y la sesion es de %. La firma no se elige.',
      new.creado_por, quien;
  end if;
  socia := exists (select 1 from acceso_usuario a
                    where lower(a.email) = lower(quien)
                      and a.perfil = 'socias' and a.activo);
  if not socia then
    raise exception 'revisar un ticket desde la pantalla es de un perfil socias, y % no lo es.', quien;
  end if;
  return new;
end
$function$;
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

-- CONTROL, justo antes del commit.
-- ESPERADO: 6 · ticket:INSERT ticket:SELECT ticket_detalle:INSERT ticket_estado:INSERT ticket_estado:SELECT ticket_marca:INSERT · 4 · 0
select (select count(*) from pg_policy where (select oid from pg_roles where rolname = 'truefie_cc') = any(polroles)) as politicas_cc,
       (select string_agg(t || ':' || p, ' ' order by t, p) from (select tb as t, unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) as p
          from unnest(array['ticket','ticket_detalle','ticket_estado','ticket_marca']) tb) x
         where has_table_privilege('truefie_cc', 'public.' || t, p)) as permisos_cc,
       (select count(*) from pg_proc where proname in ('ticket_firma_guard','ticket_detalle_guard','ticket_estado_guard','ticket_marca_guard')
          and strpos(prosrc, 'truefie_cc') > 0) as guardias_con_cc,
       (select count(*) from pg_policy where (select oid from pg_roles where rolname = 'truefie_cc') = any(polroles)
          and coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), '') ~ 'descartado|pospuesto') as cc_descarta_o_pospone;
commit;
