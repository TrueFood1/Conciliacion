-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_TICKETS_CC.sql  ·  27-sep-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- El rol truefie_cc y sus dos guardias (que CC cierre tickets de Truefie)
--
-- ⚠️ ARCHIVO GENERADO. No se edita a mano: se regenera con
--     python3 herramientas/ensayos/armar_ensayo_tickets_cc.py
--   El bloque DDL es el de TICKETS_CC.sql BYTE A BYTE, cortado por sus
--   marcas. md5 del bloque: c085b2a72c0fa91e3b7673fa84296056
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
--   Una tabla de 38 filas, TODAS con ok = true. Un RECHAZA da ok solo si
--   el SQLSTATE y el pedazo de mensaje de `esperado` estan en `obtenido`.
--   Si el editor dice "Success. No rows returned", no llego al final y no vale.
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

  -- ── V · QUE VE truefie_cc: todos los de Truefie, ningun propio ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'truefie_cc', true);
  select count(*), count(*) filter (where ambito = 'propio') into v_x1, v_x2 from ticket;
  v_res := v_res || jsonb_build_object('p', 'V1 · tickets que ve · de ellos propios', 'esperado', 'todos los de truefie · 0 propios', 'obtenido', v_x1 || ' (truefie: ' || v_n_truefie || ') · ' || v_x2 || ' propios', 'ok', v_x1 = v_n_truefie and v_x2 = 0);

  -- ── R · LAS REGLAS: cada una rebota por SU motivo, sobre un ticket que si podria moverse ──
  begin
    insert into ticket_estado (ticket_id, estado, creado_por) values (v_tv, 'cerrado', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'R1 cerrar sin nota', 'esperado', 'RECHAZA · P0001 · cerrar sin evidencia no', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R1 cerrar sin nota', 'esperado', 'RECHAZA · P0001 · cerrar sin evidencia no', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'cerrar sin evidencia no') > 0);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, creado_por, nota) values (v_tv, 'cerrado', 'cc-truefie', 'Listo, ya quedó resuelto.');
    v_res := v_res || jsonb_build_object('p', 'R2 cerrar con nota sin build ni commit', 'esperado', 'RECHAZA · P0001 · cerrar sin evidencia no', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R2 cerrar con nota sin build ni commit', 'esperado', 'RECHAZA · P0001 · cerrar sin evidencia no', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'cerrar sin evidencia no') > 0);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, creado_por, nota) values (v_tv, 'cerrado', 'cc-truefie', 'Resuelto en b72' || chr(10) || '(65ac781)');
    v_res := v_res || jsonb_build_object('p', 'R3 cerrar con la evidencia en dos lineas', 'esperado', 'RECHAZA · P0001 · va en UNA linea', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R3 cerrar con la evidencia en dos lineas', 'esperado', 'RECHAZA · P0001 · va en UNA linea', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'va en UNA linea') > 0);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, creado_por, nota, build_arreglo) values (v_tv, 'cerrado', 'cc-truefie', 'Resuelto en b72 (65ac781): prueba del ensayo', '72');
    v_res := v_res || jsonb_build_object('p', 'R4 cerrar con build_arreglo mal escrito', 'esperado', 'RECHAZA · P0001 · build_arreglo es un build como', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R4 cerrar con build_arreglo mal escrito', 'esperado', 'RECHAZA · P0001 · build_arreglo es un build como', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'build_arreglo es un build como') > 0);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, creado_por, nota) values (v_tv, 'descartado', 'cc-truefie', 'Resuelto en b72 (65ac781): prueba del ensayo');
    v_res := v_res || jsonb_build_object('p', 'R5 descartar', 'esperado', 'RECHAZA · P0001 · no pone "descartado"', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R5 descartar', 'esperado', 'RECHAZA · P0001 · no pone "descartado"', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'no pone "descartado"') > 0);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, creado_por, nota) values (v_tv, 'pospuesto', 'cc-truefie', 'Resuelto en b72 (65ac781): prueba del ensayo');
    v_res := v_res || jsonb_build_object('p', 'R6 posponer', 'esperado', 'RECHAZA · P0001 · no pone "pospuesto"', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R6 posponer', 'esperado', 'RECHAZA · P0001 · no pone "pospuesto"', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'no pone "pospuesto"') > 0);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, creado_por) values (v_tv, 'en_curso', 'cc-sql');
    v_res := v_res || jsonb_build_object('p', 'R7 firmar como cc-sql', 'esperado', 'RECHAZA · P0001 · firma creado_por = "cc-truefie"', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R7 firmar como cc-sql', 'esperado', 'RECHAZA · P0001 · firma creado_por = "cc-truefie"', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'firma creado_por = "cc-truefie"') > 0);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, creado_por) values (v_tp, 'en_curso', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'R8 mover un pendiente propio', 'esperado', 'RECHAZA · P0001 · no existe o no es de Truefie', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R8 mover un pendiente propio', 'esperado', 'RECHAZA · P0001 · no existe o no es de Truefie', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'no existe o no es de Truefie') > 0);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, creado_por) values (v_tc, 'disponible', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'R9 mover uno que Andrea pospuso o descarto', 'esperado', 'RECHAZA · P0001 · lo reabre Andrea', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R9 mover uno que Andrea pospuso o descarto', 'esperado', 'RECHAZA · P0001 · lo reabre Andrea', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'lo reabre Andrea') > 0);
  end;
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tv, 'criterio', 'Criterio de prueba del ensayo.', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'R10 detalle "criterio"', 'esperado', 'RECHAZA · P0001 · solo escribe cierres y anuncios', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R10 detalle "criterio"', 'esperado', 'RECHAZA · P0001 · solo escribe cierres y anuncios', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'solo escribe cierres y anuncios') > 0);
  end;
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tp, 'cierre', 'Cerrado en el ensayo: b72 (65ac781).', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'R11 detalle en un pendiente propio', 'esperado', 'RECHAZA · P0001 · no existe o no es de Truefie', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R11 detalle en un pendiente propio', 'esperado', 'RECHAZA · P0001 · no existe o no es de Truefie', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'no existe o no es de Truefie') > 0);
  end;

  -- ── N · NADA MAS: ni editar, ni borrar, ni leer otra cosa ──
  begin
    update ticket_estado set nota = 'x' where ticket_id = v_tv;
    v_res := v_res || jsonb_build_object('p', 'N1 update de ticket_estado', 'esperado', 'RECHAZA · 42501 · permission denied for table ticket_estado', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N1 update de ticket_estado', 'esperado', 'RECHAZA · 42501 · permission denied for table ticket_estado', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table ticket_estado') > 0);
  end;
  begin
    delete from ticket_estado where ticket_id = v_tv;
    v_res := v_res || jsonb_build_object('p', 'N2 delete de ticket_estado', 'esperado', 'RECHAZA · 42501 · permission denied for table ticket_estado', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N2 delete de ticket_estado', 'esperado', 'RECHAZA · 42501 · permission denied for table ticket_estado', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table ticket_estado') > 0);
  end;
  begin
    truncate ticket_estado;
    v_res := v_res || jsonb_build_object('p', 'N3 truncate de ticket_estado', 'esperado', 'RECHAZA · 42501 · permission denied for table ticket_estado', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N3 truncate de ticket_estado', 'esperado', 'RECHAZA · 42501 · permission denied for table ticket_estado', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table ticket_estado') > 0);
  end;
  begin
    update ticket set descripcion = 'x' where id = v_tv;
    v_res := v_res || jsonb_build_object('p', 'N4 update de ticket', 'esperado', 'RECHAZA · 42501 · permission denied for table ticket', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N4 update de ticket', 'esperado', 'RECHAZA · 42501 · permission denied for table ticket', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table ticket') > 0);
  end;
  begin
    insert into ticket (descripcion, tipo, ambito, creado_por) values ('prueba del ensayo', 'duda', 'truefie', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'N5 crear un ticket', 'esperado', 'RECHAZA · 42501 · permission denied for table ticket', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N5 crear un ticket', 'esperado', 'RECHAZA · 42501 · permission denied for table ticket', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table ticket') > 0);
  end;
  begin
    insert into ticket_marca (ticket_id, toca_numeros, escribe_en_base, prioridad, bloquea_entrega, razon, creado_por) values (v_tv, false, false, 'baja', false, 'prueba del ensayo, no va', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'N6 marcar (ticket_marca)', 'esperado', 'RECHAZA · 42501 · permission denied for table ticket_marca', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N6 marcar (ticket_marca)', 'esperado', 'RECHAZA · 42501 · permission denied for table ticket_marca', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table ticket_marca') > 0);
  end;
  begin
    perform count(*) from ticket_detalle;
    v_res := v_res || jsonb_build_object('p', 'N7 leer ticket_detalle', 'esperado', 'RECHAZA · 42501 · permission denied for table ticket_detalle', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N7 leer ticket_detalle', 'esperado', 'RECHAZA · 42501 · permission denied for table ticket_detalle', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table ticket_detalle') > 0);
  end;
  begin
    perform count(*) from v_ticket;
    v_res := v_res || jsonb_build_object('p', 'N8 leer v_ticket', 'esperado', 'RECHAZA · 42501 · permission denied for view v_ticket', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N8 leer v_ticket', 'esperado', 'RECHAZA · 42501 · permission denied for view v_ticket', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for view v_ticket') > 0);
  end;
  begin
    perform count(*) from acceso_usuario;
    v_res := v_res || jsonb_build_object('p', 'N9 leer acceso_usuario', 'esperado', 'RECHAZA · 42501 · permission denied for table acceso_usuario', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N9 leer acceso_usuario', 'esperado', 'RECHAZA · 42501 · permission denied for table acceso_usuario', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table acceso_usuario') > 0);
  end;
  begin
    perform count(*) from ent_pedido;
    v_res := v_res || jsonb_build_object('p', 'N10 leer ent_pedido', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_pedido', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N10 leer ent_pedido', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_pedido', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table ent_pedido') > 0);
  end;
  begin
    insert into revision_unidades (creado_por) values ('ticket-sql-unidades');
    v_res := v_res || jsonb_build_object('p', 'N11 escribir revision_unidades', 'esperado', 'RECHAZA · 42501 · permission denied for table revision_unidades', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N11 escribir revision_unidades', 'esperado', 'RECHAZA · 42501 · permission denied for table revision_unidades', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table revision_unidades') > 0);
  end;
  begin
    perform acceso_es_socia();
    v_res := v_res || jsonb_build_object('p', 'N12 ejecutar acceso_es_socia()', 'esperado', 'RECHAZA · 42501 · permission denied for function acceso_es_socia', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N12 ejecutar acceso_es_socia()', 'esperado', 'RECHAZA · 42501 · permission denied for function acceso_es_socia', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for function acceso_es_socia') > 0);
  end;

  -- ── C · EL CAMINO BUENO: tomarlo, cerrarlo con evidencia, dejar el cierre ──
  begin
    insert into ticket_estado (ticket_id, estado, creado_por) values (v_tv, 'en_curso', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'C1 ponerlo en_curso', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'C1 ponerlo en_curso', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, creado_por, nota, build_arreglo) values (v_tv, 'cerrado', 'cc-truefie', 'Resuelto en b72 (65ac781): prueba del ensayo', 'b72');
    v_res := v_res || jsonb_build_object('p', 'C2 cerrar con evidencia en una linea', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'C2 cerrar con evidencia en una linea', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tv, 'cierre', 'Cerrado en el ensayo: b72 (65ac781).', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'C3 detalle "cierre"', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'C3 detalle "cierre"', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, creado_por) values (v_tv, 'disponible', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'C4 volver a tocarlo ya cerrado', 'esperado', 'RECHAZA · P0001 · lo reabre Andrea', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'C4 volver a tocarlo ya cerrado', 'esperado', 'RECHAZA · P0001 · lo reabre Andrea', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'lo reabre Andrea') > 0);
  end;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);
  select h.que, h.quien, h.build_arreglo into v_t1, v_t2, v_t3
    from v_ticket_historial h where h.ticket_id = v_tv and h.que = 'Cerrado'
   order by h.cuando desc limit 1;
  v_res := v_res || jsonb_build_object('p', 'C5 · en el historial', 'esperado', 'Cerrado · cc-truefie · b72', 'obtenido', coalesce(v_t1, '(nada)') || ' · ' || coalesce(v_t2, '') || ' · ' || coalesce(v_t3, ''), 'ok', v_t1 = 'Cerrado' and v_t2 = 'cc-truefie' and v_t3 = 'b72');

  -- ── A · Andrea reabre desde la app (sesion de socia, con RLS) ──
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into ticket_estado (ticket_id, estado, creado_por) values (v_tv, 'disponible', v_socia);
    v_res := v_res || jsonb_build_object('p', 'A1 la socia lo reabre (disponible)', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'A1 la socia lo reabre (disponible)', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, creado_por) values (v_tv, 'en_curso', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'A2 la socia NO puede firmar como cc-truefie', 'esperado', 'RECHAZA · P0001 · La firma no se elige', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'A2 la socia NO puede firmar como cc-truefie', 'esperado', 'RECHAZA · P0001 · La firma no se elige', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'La firma no se elige') > 0);
  end;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);
  begin
    insert into ticket_estado (ticket_id, estado, creado_por) values (v_tv, 'en_curso', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'A3 el editor SQL NO puede firmar como cc-truefie', 'esperado', 'RECHAZA · P0001 · empezando con "cc-sql"', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'A3 el editor SQL NO puede firmar como cc-truefie', 'esperado', 'RECHAZA · P0001 · empezando con "cc-sql"', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'empezando con "cc-sql"') > 0);
  end;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'truefie_cc', true);
  begin
    insert into ticket_estado (ticket_id, estado, creado_por) values (v_tv, 'en_curso', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'A4 reabierto, truefie_cc puede volver a tomarlo', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'A4 reabierto, truefie_cc puede volver a tomarlo', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;

  -- ── L · LA RLS SOLA: se apagan los dos guardias (se vuelven a prender abajo) ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);
  alter table ticket_estado  disable trigger ticket_estado_guard_trg;
  alter table ticket_detalle disable trigger ticket_detalle_guard_trg;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'truefie_cc', true);
  begin
    insert into ticket_estado (ticket_id, estado, creado_por) values (v_tp, 'en_curso', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'L1 sin guardia: mover un propio', 'esperado', 'RECHAZA · 42501 · new row violates row-level security policy for table "ticket_estado"', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'L1 sin guardia: mover un propio', 'esperado', 'RECHAZA · 42501 · new row violates row-level security policy for table "ticket_estado"', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'new row violates row-level security policy for table "ticket_estado"') > 0);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, creado_por, nota) values (v_tv, 'descartado', 'cc-truefie', 'Resuelto en b72 (65ac781): prueba del ensayo');
    v_res := v_res || jsonb_build_object('p', 'L2 sin guardia: descartar', 'esperado', 'RECHAZA · 42501 · new row violates row-level security policy for table "ticket_estado"', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'L2 sin guardia: descartar', 'esperado', 'RECHAZA · 42501 · new row violates row-level security policy for table "ticket_estado"', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'new row violates row-level security policy for table "ticket_estado"') > 0);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, creado_por) values (v_tv, 'en_curso', 'cc-sql');
    v_res := v_res || jsonb_build_object('p', 'L3 sin guardia: firmar como cc-sql', 'esperado', 'RECHAZA · 42501 · new row violates row-level security policy for table "ticket_estado"', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'L3 sin guardia: firmar como cc-sql', 'esperado', 'RECHAZA · 42501 · new row violates row-level security policy for table "ticket_estado"', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'new row violates row-level security policy for table "ticket_estado"') > 0);
  end;
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tv, 'criterio', 'Criterio de prueba del ensayo.', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'L4 sin guardia: detalle "criterio"', 'esperado', 'RECHAZA · 42501 · new row violates row-level security policy for table "ticket_detalle"', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'L4 sin guardia: detalle "criterio"', 'esperado', 'RECHAZA · 42501 · new row violates row-level security policy for table "ticket_detalle"', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'new row violates row-level security policy for table "ticket_detalle"') > 0);
  end;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);
  alter table ticket_estado  enable trigger ticket_estado_guard_trg;
  alter table ticket_detalle enable trigger ticket_detalle_guard_trg;

  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('ensayo.res', v_res::text, true);
  perform set_config('ensayo.tickets', 'abierto T-' || v_tv || ' · propio T-' || v_tp || ' · pospuesto/descartado T-' || v_tc, true);
end $$;


-- ── EL RESULTADO. Esta tabla ES el ensayo. ────────────────────────────────
-- ESPERADO: 38 filas, todas con ok = true.
select r.p as prueba, r.esperado, r.obtenido, r.ok
  from jsonb_to_recordset(current_setting('ensayo.res')::jsonb)
       as r(p text, esperado text, obtenido text, ok boolean)
union all
select 'Z · tickets usados', current_setting('ensayo.tickets'), '', true;

rollback;

-- ── DESPUES DEL ROLLBACK (opcional, con pg_lector) ────────────────────────
-- select count(*) from pg_roles where rolname = 'truefie_cc';   -> 0: no dejo nada.
