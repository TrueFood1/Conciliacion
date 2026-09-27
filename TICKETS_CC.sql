-- ═══════════════════════════════════════════════════════════════════════════
-- TICKETS_CC.sql  ·  27-sep-2026  ·  SIN APLICAR
-- Que CC cierre tickets de Truefie solo, con rastro (opcion A de Andrea)
--
-- CAMBIA LA REGLA DEL 19-SEP ("cerrar es siempre de Andrea"). Desde este
-- pegado, CC puede cerrar un ticket de Truefie que resolvio, con evidencia.
-- Andrea sigue siendo la unica que descarta, pospone, reabre y toca sus
-- pendientes propios.
--
-- QUE TRAE
--   · el rol `truefie_cc`: login, noinherit, nobypassrls, sin clave.
--       SELECT en ticket y ticket_estado · INSERT en ticket_estado y
--       ticket_detalle · EXECUTE en sus dos guardias. Nada mas.
--   · RLS: ve SOLO los tickets de ambito truefie (un propio, para el, no
--     existe); inserta estados y detalles SOLO en esos, SOLO con su firma.
--   · los dos guardias, con un bloque nuevo al principio para truefie_cc.
--
-- LAS REGLAS DE truefie_cc (en el guardia, con su mensaje; la RLS de respaldo)
--   · solo ambito truefie. Nunca un pendiente propio.
--   · estados: cerrado, en_validacion, en_curso, disponible, bloqueado.
--     NUNCA descartado ni pospuesto (son decisiones de Andrea).
--   · no toca un ticket que YA esta cerrado, pospuesto o descartado: eso lo
--     reabre Andrea. Si no, CC podria deshacer una decision de ella.
--   · al cerrar: nota OBLIGATORIA, en UNA linea, que nombre el build (b72) o
--     el commit (7 a 40 hex). `build_arreglo`, si va, tiene forma "b72".
--   · firma fija: creado_por = 'cc-truefie'. Nadie mas puede usarla: una
--     sesion de la app exige su correo, y el editor SQL exige "cc-sql…".
--   · detalles: solo 'cierre' y 'anuncio'.
--
-- POR QUE NO v_ticket: es security_invoker y lee seis objetos (ticket,
--   ticket_estado, ticket_marca, ticket_detalle y dos vistas de fotos). Darle
--   v_ticket obligaba a darle lectura sobre los seis. Para saber en que estado
--   esta un ticket alcanza con ticket + ticket_estado.
--
-- LO QUE NO TOCA: ninguna tabla, ninguna otra politica ni funcion; ningun
--   permiso de authenticated, anon ni de los otros roles propios.
--
-- ANTES DE PEGAR: correr ENSAYO_TICKETS_CC.sql (el mismo bloque DDL, byte a
--   byte, mas las pruebas, y rollback).
-- SE PEGA ENTERO: un `begin`, un `commit`, cero `rollback`.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ═══ DDL · DESDE ACA (ENSAYO_TICKETS_CC.sql copia este bloque tal cual) ═══

-- §0 · CANDADO DE ENTRADA: el rol no existe, y los dos guardias son EXACTAMENTE
-- los que se leyeron el 27-sep (si alguien los cambio, esto no los pisa).
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'truefie_cc') then
    raise exception 'el rol truefie_cc ya existe: este pegado no pisa nada';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.ticket_estado_guard()'::regprocedure)
       is distinct from '64b47d7f82d221003bb860beb900372a' then
    raise exception 'ticket_estado_guard no es el que se leyo el 27-sep: volver a medir antes de pegar';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.ticket_detalle_guard()'::regprocedure)
       is distinct from '706a4f6fd7d1c8e126e65f337f8915dd' then
    raise exception 'ticket_detalle_guard no es el que se leyo el 27-sep: volver a medir antes de pegar';
  end if;
end $$;


-- §1 · EL ROL. Igual de angosto que truefie_vigia: login, sin heredar de nadie,
-- sin saltarse la RLS, sin clave (la clave va aparte, ver §CLAVE al final).
create role truefie_cc with login nosuperuser nocreatedb nocreaterole
                            noinherit nobypassrls noreplication;
grant usage on schema public to truefie_cc;
grant select on table public.ticket, public.ticket_estado to truefie_cc;
grant insert on table public.ticket_estado, public.ticket_detalle to truefie_cc;
grant execute on function public.ticket_estado_guard(), public.ticket_detalle_guard() to truefie_cc;


-- §2 · LA RLS. Segunda capa: lo que importa esta TAMBIEN en el guardia, que
-- corre primero y dice el motivo; si un dia el guardia fallara, esto frena igual.
create policy ticket_cc_sel on public.ticket
  for select to truefie_cc using (ambito = 'truefie');
create policy ticket_estado_cc_sel on public.ticket_estado
  for select to truefie_cc
  using (exists (select 1 from public.ticket t
                  where t.id = ticket_estado.ticket_id and t.ambito = 'truefie'));
create policy ticket_estado_cc_ins on public.ticket_estado
  for insert to truefie_cc
  with check (creado_por = 'cc-truefie'
              and estado in ('cerrado','en_validacion','en_curso','disponible','bloqueado')
              and exists (select 1 from public.ticket t
                           where t.id = ticket_estado.ticket_id and t.ambito = 'truefie'));
create policy ticket_detalle_cc_ins on public.ticket_detalle
  for insert to truefie_cc
  with check (creado_por = 'cc-truefie'
              and clase in ('cierre','anuncio')
              and exists (select 1 from public.ticket t
                           where t.id = ticket_detalle.ticket_id and t.ambito = 'truefie'));


-- §3 · LOS DOS GUARDIAS. Son los vivos del 27-sep con UN bloque nuevo al
-- principio (el de truefie_cc) y una variable mas en el declare; el resto,
-- byte a byte igual. `create or replace` conserva dueño y permisos.
create or replace function public.ticket_estado_guard()
returns trigger
language plpgsql
as $fn$
declare quien text; socia boolean; amb text; ult text;
begin
  -- ══ CC CON ROL PROPIO · truefie_cc (27-sep-2026, opcion A de Andrea) ═══
  -- Va PRIMERO, antes que el "no existe": la RLS le esconde a truefie_cc los
  -- pendientes propios, asi que para el un propio no existe, y el rechazo
  -- tiene que decir el motivo de verdad y no el de al lado.
  if current_user = 'truefie_cc' then
    select t.ambito into amb from ticket t where t.id = new.ticket_id;
    if amb is distinct from 'truefie' then
      raise exception 'truefie_cc no ve el ticket %: no existe o no es de Truefie. '
        'Los pendientes propios los mueve Andrea.', new.ticket_id;
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
      if coalesce(new.nota, '') !~ '(^|[^0-9a-z])(b[0-9]{2,3}|[0-9a-f]{7,40})([^0-9a-z]|$)' then
        raise exception 'cerrar sin evidencia no: la nota tiene que nombrar el build (b72) o el '
          'commit (7 a 40 hex) donde quedo resuelto. Vino: %', coalesce(new.nota, '(vacia)');
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
$fn$;

create or replace function public.ticket_detalle_guard()
returns trigger
language plpgsql
as $fn$
declare quien text; socia boolean; amb text;
begin
  -- ══ CC CON ROL PROPIO · truefie_cc (27-sep-2026) ═══════════════════════
  -- Primero, por la misma razon que en ticket_estado_guard: un propio no lo ve.
  if current_user = 'truefie_cc' then
    select t.ambito into amb from ticket t where t.id = new.ticket_id;
    if amb is distinct from 'truefie' then
      raise exception 'truefie_cc no ve el ticket %: no existe o no es de Truefie. '
        'Los pendientes propios los mueve Andrea.', new.ticket_id;
    end if;
    if new.creado_por is distinct from 'cc-truefie' then
      raise exception 'truefie_cc firma creado_por = "cc-truefie". Vino: %', new.creado_por;
    end if;
    if new.clase not in ('cierre','anuncio') then
      raise exception 'truefie_cc solo escribe cierres y anuncios; "%" lo define una socia.', new.clase;
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
    if new.clase not in ('cierre','anuncio') then
      raise exception 'desde el SQL Editor solo se escriben cierres y anuncios. '
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
$fn$;

-- ═══ DDL · HASTA ACA ═══


-- 🔴 LA PRUEBA DE QUE ENTRO, ADENTRO DE LA TRANSACCION.
-- ESPERADO: t · f · f · 2 · 4 · 2 · 2 · t · t
select
  (select rolcanlogin from pg_roles where rolname = 'truefie_cc')                  as puede_entrar,
  (select rolinherit or rolbypassrls from pg_roles where rolname = 'truefie_cc')  as hereda_o_saltea,
  (select exists (select 1 from pg_auth_members m join pg_roles r on r.oid = m.member
                   where r.rolname = 'truefie_cc'))                                as es_miembro_de_algo,
  (select count(distinct table_name) from information_schema.role_table_grants
    where grantee = 'truefie_cc' and privilege_type = 'SELECT')                   as tablas_que_lee,
  (select count(*) from information_schema.role_table_grants
    where grantee = 'truefie_cc')                                                  as permisos_total,
  (select count(*) from pg_policy p join pg_roles r on r.oid = any(p.polroles)
    where r.rolname = 'truefie_cc' and p.polcmd = 'a')                             as politicas_insert,
  (select count(*) from pg_policy p join pg_roles r on r.oid = any(p.polroles)
    where r.rolname = 'truefie_cc' and p.polcmd = 'r')                             as politicas_select,
  (select strpos(prosrc, 'truefie_cc') > 0 from pg_proc
    where oid = 'public.ticket_estado_guard()'::regprocedure)                      as guardia_estado,
  (select strpos(prosrc, 'truefie_cc') > 0 from pg_proc
    where oid = 'public.ticket_detalle_guard()'::regprocedure)                     as guardia_detalle;

commit;


-- ── §CLAVE · VA APARTE, DESPUES, Y NO POR EL PORTAPAPELES ─────────────────
-- La clave la genera CC en la Mac y la guarda en el llavero de macOS
-- (servicio truefie-cc-db, cuenta truefie_cc). Al editor SQL NO viaja la
-- clave: viaja su VERIFICADOR SCRAM (lo que Postgres guarda de una clave),
-- en una sola linea que Andrea pega sola:
--   alter role truefie_cc with password 'SCRAM-SHA-256$4096:…';
-- Con el verificador no se puede entrar: hace falta la clave, y la clave
-- no sale del llavero.

-- ── VERIFICACION DE DESPUES (con pg_lector, fuera de la transaccion) ──────
-- select rolname, rolcanlogin, rolinherit, rolbypassrls from pg_roles where rolname = 'truefie_cc';
-- select table_name, privilege_type from information_schema.role_table_grants
--  where grantee = 'truefie_cc' order by 1, 2;
--   -> ticket SELECT · ticket_detalle INSERT · ticket_estado INSERT + SELECT
-- select polname from pg_policy p join pg_roles r on r.oid = any(p.polroles)
--  where r.rolname = 'truefie_cc';                                   -> 4 politicas
