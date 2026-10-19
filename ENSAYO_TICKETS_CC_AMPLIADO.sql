-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_TICKETS_CC_AMPLIADO.sql  ·  19-oct-2026  ·  ENSAYO EN SECO · termina en ROLLBACK
-- Prueba TICKETS_CC_AMPLIADO.sql actuando COMO truefie_cc (sin sesión: firma 'cc-truefie').
-- Lo corre CC con herramientas/pg_ensayo.py (decisión de Andrea, 19-oct).
-- ✅ CORRIDO por CC el 19-oct: 26 de 26 ok = true, cada RECHAZA con su SQLSTATE y su motivo; transacción abierta
--    después: ninguna. VERIFICADO desde afuera (pg_lector): guardias con el md5 de antes, 4 políticas de truefie_cc,
--    sus mismos permisos, 0 tickets de prueba (último 152).
-- Cada RECHAZA vale solo con SU SQLSTATE y SU motivo (un pedazo del mensaje), no con el de al lado.
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

-- Para actuar como truefie_cc: postgres lo administra pero no puede «ponérselo» (medido: set=false).
-- Se lo da dentro de la transacción; el rollback lo deshace.
grant truefie_cc to postgres with set true;

do $$
declare
  v_t bigint; v_p bigint; v_t2 bigint; v_p2 bigint; v_x bigint; v_n int; v_np int; v_vp int;
  v_res jsonb := '[]'::jsonb;
begin
  if not pg_has_role('postgres', 'truefie_cc', 'SET') then
    raise exception 'postgres no puede ponerse truefie_cc: el ensayo no puede probar nada';
  end if;
  select count(*) into v_np from ticket where ambito = 'propio';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'truefie_cc', true);
  select count(*) into v_vp from ticket where ambito = 'propio';
  v_res := v_res || jsonb_build_object('p','E1 truefie_cc VE los pendientes propios','esperado',v_np::text,'obtenido',v_vp::text,'ok',v_vp = v_np and v_np > 0);
  begin
    insert into ticket (descripcion, tipo, build, modulo, ambito, creado_por) values ('Ensayo CC ampliado · truefie', 'encargo', 'b108', null, 'truefie', 'cc-truefie') returning id into v_t;
    v_res := v_res || jsonb_build_object('p','E2 agrega un ticket de TRUEFIE','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E2 agrega un ticket de TRUEFIE','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ticket (descripcion, tipo, build, modulo, ambito, creado_por) values ('Ensayo CC ampliado · propio', 'encargo', 'b108', null, 'propio', 'cc-truefie') returning id into v_p;
    v_res := v_res || jsonb_build_object('p','E3 agrega un pendiente PROPIO','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E3 agrega un pendiente PROPIO','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ticket (descripcion, tipo, build, modulo, ambito, creado_por) values ('Ensayo CC ampliado · truefie 2', 'encargo', 'b108', null, 'truefie', 'cc-truefie') returning id into v_t2;
    v_res := v_res || jsonb_build_object('p','E3b agrega otro de Truefie (para los rechazos)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E3b agrega otro de Truefie (para los rechazos)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ticket (descripcion, tipo, build, modulo, ambito, creado_por) values ('Ensayo CC ampliado · propio 2', 'encargo', 'b108', null, 'propio', 'cc-truefie') returning id into v_p2;
    v_res := v_res || jsonb_build_object('p','E3c agrega otro propio (para la evidencia)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E3c agrega otro propio (para la evidencia)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ticket (descripcion, tipo, build, modulo, ambito, creado_por) values ('Ensayo CC ampliado · firma', 'encargo', 'b108', null, 'truefie', 'cc-sql · prueba') returning id into v_x;
    v_res := v_res || jsonb_build_object('p','E4 ticket firmado con OTRO nombre','esperado','RECHAZA · P0001 (cc-truefie)','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E4 ticket firmado con OTRO nombre','esperado','RECHAZA · P0001 (cc-truefie)','obtenido','RECHAZA: '||sqlstate||' · '||left(sqlerrm,120),'ok',sqlstate='P0001' and strpos(sqlerrm,'cc-truefie')>0);
  end;
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_t, 'explicacion', E'Qué es: prueba del ensayo de truefie_cc.\nPor qué importa: comprueba que el rol escribe solo.\nQué haría falta: chico. Nada.\nRecomendación: DESCARTAR. Es un ensayo.', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p','E5 explicación en el de Truefie','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E5 explicación en el de Truefie','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_p, 'explicacion', E'Qué es: prueba del ensayo de truefie_cc.\nPor qué importa: comprueba que el rol escribe solo.\nQué haría falta: chico. Nada.\nRecomendación: DESCARTAR. Es un ensayo.', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p','E6 explicación en el PROPIO','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E6 explicación en el PROPIO','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ticket_marca (ticket_id, toca_numeros, escribe_en_base, prioridad, razon, creado_por) values (v_t, false, false, 'baja', 'ensayo del rol truefie_cc', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p','E7 marca en el de Truefie','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E7 marca en el de Truefie','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ticket_marca (ticket_id, toca_numeros, escribe_en_base, prioridad, razon, creado_por) values (v_p, false, false, 'baja', 'ensayo del rol truefie_cc', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p','E8 marca en el PROPIO','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E8 marca en el PROPIO','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ticket_marca (ticket_id, toca_numeros, escribe_en_base, prioridad, razon, creado_por) values (v_t, false, false, 'baja', 'ensayo del rol truefie_cc', 'cc-sql · prueba');
    v_res := v_res || jsonb_build_object('p','E8b marca firmada con OTRO nombre','esperado','RECHAZA · P0001 (cc-truefie)','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E8b marca firmada con OTRO nombre','esperado','RECHAZA · P0001 (cc-truefie)','obtenido','RECHAZA: '||sqlstate||' · '||left(sqlerrm,120),'ok',sqlstate='P0001' and strpos(sqlerrm,'cc-truefie')>0);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, nota, build_arreglo, creado_por) values (v_p, 'en_curso', null, null, 'cc-truefie');
    v_res := v_res || jsonb_build_object('p','E9 en_curso en el PROPIO','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E9 en_curso en el PROPIO','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, nota, build_arreglo, creado_por) values (v_t, 'cerrado', 'Resuelto en b108 (b77f801): ensayo', 'b108', 'cc-truefie');
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_t, 'cierre', 'Cerrado en el ensayo del rol.', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p','E10 CIERRA el de Truefie con evidencia (build y commit) + su detalle de cierre','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E10 CIERRA el de Truefie con evidencia (build y commit) + su detalle de cierre','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, nota, build_arreglo, creado_por) values (v_p, 'cerrado', 'correo: respuesta del proveedor del 19-oct (ensayo)', null, 'cc-truefie');
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_p, 'cierre', 'Cerrado en el ensayo del rol.', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p','E11 CIERRA el PROPIO con «correo: …» + su detalle de cierre','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E11 CIERRA el PROPIO con «correo: …» + su detalle de cierre','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, nota, build_arreglo, creado_por) values (v_t2, 'cerrado', 'ya está', null, 'cc-truefie');
    v_res := v_res || jsonb_build_object('p','E12 cerrar SIN evidencia (Truefie)','esperado','RECHAZA · P0001 (sin evidencia)','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E12 cerrar SIN evidencia (Truefie)','esperado','RECHAZA · P0001 (sin evidencia)','obtenido','RECHAZA: '||sqlstate||' · '||left(sqlerrm,120),'ok',sqlstate='P0001' and strpos(sqlerrm,'sin evidencia')>0);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, nota, build_arreglo, creado_por) values (v_p2, 'cerrado', 'lo hice ayer', null, 'cc-truefie');
    v_res := v_res || jsonb_build_object('p','E12b cerrar un PROPIO con texto suelto, sin archivo/correo/enlace','esperado','RECHAZA · P0001 (sin evidencia)','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E12b cerrar un PROPIO con texto suelto, sin archivo/correo/enlace','esperado','RECHAZA · P0001 (sin evidencia)','obtenido','RECHAZA: '||sqlstate||' · '||left(sqlerrm,120),'ok',sqlstate='P0001' and strpos(sqlerrm,'sin evidencia')>0);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, nota, build_arreglo, creado_por) values (v_t2, 'descartado', null, null, 'cc-truefie');
    v_res := v_res || jsonb_build_object('p','E13 DESCARTAR (Truefie)','esperado','RECHAZA · P0001 (descartar y posponer)','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E13 DESCARTAR (Truefie)','esperado','RECHAZA · P0001 (descartar y posponer)','obtenido','RECHAZA: '||sqlstate||' · '||left(sqlerrm,120),'ok',sqlstate='P0001' and strpos(sqlerrm,'descartar y posponer')>0);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, nota, build_arreglo, creado_por) values (v_p2, 'descartado', null, null, 'cc-truefie');
    v_res := v_res || jsonb_build_object('p','E13b DESCARTAR (propio)','esperado','RECHAZA · P0001 (descartar y posponer)','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E13b DESCARTAR (propio)','esperado','RECHAZA · P0001 (descartar y posponer)','obtenido','RECHAZA: '||sqlstate||' · '||left(sqlerrm,120),'ok',sqlstate='P0001' and strpos(sqlerrm,'descartar y posponer')>0);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, nota, build_arreglo, creado_por) values (v_t2, 'pospuesto', null, null, 'cc-truefie');
    v_res := v_res || jsonb_build_object('p','E14 POSPONER (Truefie)','esperado','RECHAZA · P0001 (descartar y posponer)','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E14 POSPONER (Truefie)','esperado','RECHAZA · P0001 (descartar y posponer)','obtenido','RECHAZA: '||sqlstate||' · '||left(sqlerrm,120),'ok',sqlstate='P0001' and strpos(sqlerrm,'descartar y posponer')>0);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, nota, build_arreglo, creado_por) values (v_p2, 'pospuesto', null, null, 'cc-truefie');
    v_res := v_res || jsonb_build_object('p','E14b POSPONER (propio)','esperado','RECHAZA · P0001 (descartar y posponer)','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E14b POSPONER (propio)','esperado','RECHAZA · P0001 (descartar y posponer)','obtenido','RECHAZA: '||sqlstate||' · '||left(sqlerrm,120),'ok',sqlstate='P0001' and strpos(sqlerrm,'descartar y posponer')>0);
  end;
  begin
    insert into ticket_estado (ticket_id, estado, nota, build_arreglo, creado_por) values (v_t, 'en_curso', null, null, 'cc-truefie');
    v_res := v_res || jsonb_build_object('p','E15 reabrir uno que YA cerró (en_curso sobre el de E10)','esperado','RECHAZA · P0001 (lo reabre Andrea)','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E15 reabrir uno que YA cerró (en_curso sobre el de E10)','esperado','RECHAZA · P0001 (lo reabre Andrea)','obtenido','RECHAZA: '||sqlstate||' · '||left(sqlerrm,120),'ok',sqlstate='P0001' and strpos(sqlerrm,'lo reabre Andrea')>0);
  end;
  begin
    update ticket set descripcion = descripcion where id = v_t;
    v_res := v_res || jsonb_build_object('p','E16 CAMBIAR un ticket (update)','esperado','RECHAZA · 42501 (permission denied)','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E16 CAMBIAR un ticket (update)','esperado','RECHAZA · 42501 (permission denied)','obtenido','RECHAZA: '||sqlstate||' · '||left(sqlerrm,120),'ok',sqlstate='42501' and strpos(sqlerrm,'permission denied')>0);
  end;
  begin
    delete from ticket_detalle where ticket_id = v_t;
    v_res := v_res || jsonb_build_object('p','E17 BORRAR un detalle (delete)','esperado','RECHAZA · 42501 (permission denied)','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E17 BORRAR un detalle (delete)','esperado','RECHAZA · 42501 (permission denied)','obtenido','RECHAZA: '||sqlstate||' · '||left(sqlerrm,120),'ok',sqlstate='42501' and strpos(sqlerrm,'permission denied')>0);
  end;
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_t2, 'criterio', 'Criterio puesto por CC en el ensayo.', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p','E18 escribir el «criterio» (lo define una socia)','esperado','RECHAZA · P0001 (lo define una socia)','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E18 escribir el «criterio» (lo define una socia)','esperado','RECHAZA · P0001 (lo define una socia)','obtenido','RECHAZA: '||sqlstate||' · '||left(sqlerrm,120),'ok',sqlstate='P0001' and strpos(sqlerrm,'lo define una socia')>0);
  end;

  perform set_config('role', 'postgres', true);
  select count(*) into v_n from ticket where descripcion like 'Ensayo CC ampliado%';
  v_res := v_res || jsonb_build_object('p','Z1 adentro del ensayo quedaron 4 tickets de prueba (E2, E3, E3b, E3c)','esperado','4','obtenido',v_n::text,'ok',v_n = 4);
  select count(*) into v_n from ticket_estado where ticket_id in (v_t, v_p) and estado = 'cerrado' and creado_por = 'cc-truefie';
  v_res := v_res || jsonb_build_object('p','Z2 y 2 cierres firmados cc-truefie (E10, E11)','esperado','2','obtenido',v_n::text,'ok',v_n = 2);
  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;

rollback;
