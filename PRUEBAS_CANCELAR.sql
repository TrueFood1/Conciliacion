-- SOLO ENSAYO · PRUEBAS_CANCELAR.sql · termina en ROLLBACK, no deja nada
-- ════════════════════════════════════════════════════════════════════════
-- ENSAYO · cancelar lo propio + anti repetidas
-- 15-oct-2026. Va DESPUES de PERSONAL_CANCELAR_SOLICITUD.sql (pegado 9).
--
-- ⚠️ TODO FICTICIO, INCLUIDAS LAS CUENTAS. A diferencia de los ensayos
-- anteriores, este NO impersona a nadie real: crea dos personas y una socia
-- ficticias en rrhh_persona y acceso_usuario, con correos @example.invalid, y
-- trabaja con esas. Asi no depende de que exista tal o cual cuenta, y sobre todo
-- no escribe nada a nombre de una persona de verdad. Todo se va con el rollback.
--
-- ⚠️ NO TOCA las filas de Daniel. El escenario 8 las cuenta antes y despues.
--
-- ⚠️ SOBRE LA CARRERA (escenario 6), dicho derecho: una carrera de verdad
-- necesita DOS sesiones concurrentes, y una sola transaccion no puede tenerlas.
-- Lo que se prueba aca es su CONSECUENCIA determinista —el que llega segundo
-- encuentra el estado ya cambiado y recibe el mensaje claro— que es lo que el
-- lock garantiza. No se afirma haber probado concurrencia real.
--
-- QUE SE PRUEBA
--   1 · el dueño cancela su VACACION pendiente
--   2 · y su PERMISO pendiente
--   3 · cancelada, desaparece del calendario, de la bandeja y de lo pendiente
--       del saldo (y los dias TOMADOS no se mueven: una pendiente nunca contaba)
--   4 · otro empleado intenta cancelar la ajena -> falla
--   5 · cancelar una aprobada / rechazada / ya cancelada -> falla, con el estado
--       en el mensaje
--   6 · anon -> falla
--   7 · la proteccion rechaza la repetida, y deja pedir de nuevo tras cancelar
--   8 · las filas de Daniel quedan intactas
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── 0 · ESTADO DE DANIEL, ANTES ─────────────────────────────────────────
select set_config('cc.daniel_n',
  (select count(*)::text from rrhh_persona p
    where lower(split_part(btrim(p.nombre),' ',1)) = 'daniel'), true);
do $$
begin
  if coalesce(nullif(current_setting('cc.daniel_n',true),'')::numeric,-1) = 1 then
    perform set_config('cc.daniel',
      (select p.id::text from rrhh_persona p
        where lower(split_part(btrim(p.nombre),' ',1)) = 'daniel'), true);
    perform set_config('cc.a_daniel_ev',
      (select count(*)::text from rrhh_evento
        where persona_id = current_setting('cc.daniel',true)::bigint), true);
    perform set_config('cc.a_daniel_pm',
      (select count(*)::text from rrhh_permiso
        where persona_id = current_setting('cc.daniel',true)::bigint), true);
  else
    perform set_config('cc.daniel','', true);
  end if;
end $$;


-- ── 1 · LAS CUENTAS Y LAS PERSONAS FICTICIAS ────────────────────────────
insert into acceso_usuario (email, nombre, perfil, activo, nota, creado_por) values
  ('zz-a@example.invalid',     'ZZ Ensayo A',     'equipo', true, 'ensayo-cancelar', 'ensayo'),
  ('zz-b@example.invalid',     'ZZ Ensayo B',     'equipo', true, 'ensayo-cancelar', 'ensayo'),
  ('zz-socia@example.invalid', 'ZZ Ensayo Socia', 'socias', true, 'ensayo-cancelar', 'ensayo');

with p as (
  insert into rrhh_persona (nombre, email, puesto, ingreso, creado_por) values
    ('ZZ Ensayo A', 'zz-a@example.invalid', 'ensayo', '2026-01-05', 'ensayo-cancelar'),
    ('ZZ Ensayo B', 'zz-b@example.invalid', 'ensayo', '2026-01-05', 'ensayo-cancelar')
  returning id, email
)
select set_config('cc.' || case when email like 'zz-a%' then 'pa' else 'pb' end,
                  id::text, true) from p;

insert into rrhh_salario (persona_id, salario_mensual, vigente_desde, nota, creado_por)
select current_setting('cc.'||k,true)::bigint, 1, '2026-01-05', 'FICTICIO', 'ensayo-cancelar'
  from (values ('pa'),('pb')) v(k);

-- Los eventos y permisos, todos de 2027 para no pisarse con nada real.
with e as (
  insert into rrhh_evento (persona_id, fecha, tipo, dias, motivo, creado_por) values
    (current_setting('cc.pa',true)::bigint, '2027-03-01','vacaciones',1,'e1 pendiente','ensayo-cancelar'),
    (current_setting('cc.pb',true)::bigint, '2027-03-05','vacaciones',1,'e3 de B','ensayo-cancelar'),
    (current_setting('cc.pa',true)::bigint, '2027-03-10','vacaciones',1,'e4 aprobada','ensayo-cancelar'),
    (current_setting('cc.pa',true)::bigint, '2027-03-15','vacaciones',1,'e5 rechazada','ensayo-cancelar'),
    (current_setting('cc.pa',true)::bigint, '2027-03-20','vacaciones',1,'e6 para anon','ensayo-cancelar')
  returning id, motivo
)
select set_config('cc.'||split_part(motivo,' ',1), id::text, true) from e;

with m as (
  insert into rrhh_permiso (persona_id, fecha_inicio, fecha_fin, motivo, estado, creado_por)
  values (current_setting('cc.pa',true)::bigint,'2027-04-01','2027-04-01','p1 pendiente','pendiente','ensayo-cancelar')
  returning id
)
select set_config('cc.p1', id::text, true) from m;

-- e4 aprobada y e5 rechazada, por el camino real: como la socia ficticia.
select set_config('request.jwt.claims',
  json_build_object('email','zz-socia@example.invalid','role','authenticated')::text, true);
select set_config('role','authenticated', true);
do $$
begin
  if not coalesce(acceso_es_socia(), false) then
    perform set_config('role','postgres', true);
    raise exception 'ENSAYO ABORTADO: la socia ficticia no quedo reconocida por '
      'acceso_es_socia(). Sin eso los escenarios 5 y 6 no probarian nada.';
  end if;
  perform rrhh_resolver_evento(current_setting('cc.e4',true)::bigint, true,  null,null,'ensayo');
  perform rrhh_resolver_evento(current_setting('cc.e5',true)::bigint, false, null,null,'ensayo');
end $$;
select set_config('role','postgres', true);


-- ── 2 · EL ESTADO DE A, ANTES DE CANCELAR (como socia, que ve todo) ─────
select set_config('request.jwt.claims',
  json_build_object('email','zz-socia@example.invalid','role','authenticated')::text, true);
select set_config('role','authenticated', true);
do $$
begin
  perform set_config('cc.a_cal',
    (select count(*)::text from v_rrhh_calendario
      where persona_id = current_setting('cc.pa',true)::bigint), true);
  perform set_config('cc.a_band',
    (select count(*)::text from v_rrhh_solicitud
      where persona_id = current_setting('cc.pa',true)::bigint), true);
  perform set_config('cc.a_tom',
    (select dias_tomados::text from v_rrhh_vacacion_saldo
      where persona_id = current_setting('cc.pa',true)::bigint), true);
end $$;
select set_config('role','postgres', true);


-- ── 3 · A CANCELA LO SUYO ───────────────────────────────────────────────
select set_config('request.jwt.claims',
  json_build_object('email','zz-a@example.invalid','role','authenticated')::text, true);
select set_config('role','authenticated', true);

do $$
declare r record; v_n int;
begin
  if rrhh_mi_persona() is distinct from current_setting('cc.pa',true)::bigint then
    perform set_config('role','postgres', true);
    raise exception 'ENSAYO ABORTADO: rrhh_mi_persona() no devolvio la persona A, asi que '
      'nada de lo que sigue probaria lo que dice.';
  end if;

  -- 1 · la vacacion pendiente
  begin
    select * into r from rrhh_cancelar_solicitud('vacacion', current_setting('cc.e1',true)::bigint, 'me equivoque');
    perform set_config('cc.r1', coalesce(r.estado,'SIN FILA'), true);
  exception when others then
    perform set_config('cc.r1', 'ERROR '||sqlstate||' · '||left(sqlerrm,45), true);
  end;

  -- 2 · el permiso pendiente
  begin
    select * into r from rrhh_cancelar_solicitud('permiso', current_setting('cc.p1',true)::bigint, null);
    perform set_config('cc.r2', coalesce(r.estado,'SIN FILA'), true);
    perform set_config('cc.r2_por', coalesce(r.resuelto_por,''), true);
  exception when others then
    perform set_config('cc.r2', 'ERROR '||sqlstate||' · '||left(sqlerrm,45), true);
    perform set_config('cc.r2_por','', true);
  end;

  -- 4 · la ajena (de B)
  begin
    perform rrhh_cancelar_solicitud('vacacion', current_setting('cc.e3',true)::bigint, null);
    perform set_config('cc.r4','ENTRO -> FUGA', true);
  exception when others then
    perform set_config('cc.r4','RECHAZA '||sqlstate||' · '||left(sqlerrm,50), true);
  end;

  -- 5a · la aprobada · 5b · la rechazada · 5c · la ya cancelada
  begin
    perform rrhh_cancelar_solicitud('vacacion', current_setting('cc.e4',true)::bigint, null);
    perform set_config('cc.r5a','ENTRO -> FUGA', true);
  exception when others then
    perform set_config('cc.r5a','RECHAZA '||sqlstate||' · '||left(sqlerrm,55), true);
  end;
  begin
    perform rrhh_cancelar_solicitud('vacacion', current_setting('cc.e5',true)::bigint, null);
    perform set_config('cc.r5b','ENTRO -> FUGA', true);
  exception when others then
    perform set_config('cc.r5b','RECHAZA '||sqlstate||' · '||left(sqlerrm,55), true);
  end;
  begin
    perform rrhh_cancelar_solicitud('vacacion', current_setting('cc.e1',true)::bigint, null);
    perform set_config('cc.r5c','ENTRO -> FUGA', true);
  exception when others then
    perform set_config('cc.r5c','RECHAZA '||sqlstate||' · '||left(sqlerrm,55), true);
  end;

  -- 7 · anti repetidas: la misma que e6 (pendiente) -> tiene que fallar
  begin
    insert into rrhh_evento (persona_id, fecha, tipo, dias, motivo, creado_por)
    values (current_setting('cc.pa',true)::bigint,'2027-03-20','vacaciones',1,'repetida','ensayo-cancelar');
    perform set_config('cc.r7a','ENTRO -> la proteccion NO freno', true);
  exception when others then
    perform set_config('cc.r7a','RECHAZA '||sqlstate||' · '||left(sqlerrm,50), true);
  end;
  -- y la misma fecha de e1, que YA ESTA CANCELADA -> tiene que entrar
  begin
    insert into rrhh_evento (persona_id, fecha, tipo, dias, motivo, creado_por)
    values (current_setting('cc.pa',true)::bigint,'2027-03-01','vacaciones',1,'tras cancelar','ensayo-cancelar');
    perform set_config('cc.r7b','ENTRO (correcto)', true);
  exception when others then
    perform set_config('cc.r7b','RECHAZA '||sqlstate||' · '||left(sqlerrm,50), true);
  end;
end $$;
select set_config('role','postgres', true);


-- ── 4 · ANON ────────────────────────────────────────────────────────────
do $$
begin
  perform set_config('request.jwt.claims','{"role":"anon"}', true);
  perform set_config('role','anon', true);
  begin
    perform rrhh_cancelar_solicitud('vacacion', current_setting('cc.e6',true)::bigint, null);
    perform set_config('cc.r6','ENTRO -> FUGA', true);
  exception when others then
    perform set_config('cc.r6','RECHAZA '||sqlstate||' · '||left(sqlerrm,50), true);
  end;
  perform set_config('role','postgres', true);
end $$;


-- ── 5 · EL ESTADO DE A, DESPUES (como socia) ───────────────────────────
select set_config('request.jwt.claims',
  json_build_object('email','zz-socia@example.invalid','role','authenticated')::text, true);
select set_config('role','authenticated', true);
do $$
begin
  perform set_config('cc.d_cal',
    (select count(*)::text from v_rrhh_calendario
      where persona_id = current_setting('cc.pa',true)::bigint), true);
  perform set_config('cc.d_band',
    (select count(*)::text from v_rrhh_solicitud
      where persona_id = current_setting('cc.pa',true)::bigint), true);
  perform set_config('cc.d_tom',
    (select dias_tomados::text from v_rrhh_vacacion_saldo
      where persona_id = current_setting('cc.pa',true)::bigint), true);
  perform set_config('cc.d_e1',
    (select estado from v_rrhh_evento_estado where id = current_setting('cc.e1',true)::bigint), true);
end $$;
select set_config('role','postgres', true);

-- Daniel, despues
do $$
begin
  if coalesce(current_setting('cc.daniel',true),'') <> '' then
    perform set_config('cc.d_daniel_ev',
      (select count(*)::text from rrhh_evento
        where persona_id = current_setting('cc.daniel',true)::bigint), true);
    perform set_config('cc.d_daniel_pm',
      (select count(*)::text from rrhh_permiso
        where persona_id = current_setting('cc.daniel',true)::bigint), true);
  end if;
end $$;


-- ── 6 · LA TABLA ────────────────────────────────────────────────────────
select t.orden, t.prueba, t.esperado, t.obtenido,
       case when t.prueba like 'INFO%' then 'INFO'
            when t.obtenido like 'SIN PROBAR%' then 'SIN PROBAR'
            when t.ok then 'OK' else 'FALLA' end as veredicto
  from (
  select 1 as orden, 'el dueño cancela su VACACION pendiente'::text as prueba,
         'anulado'::text as esperado,
         coalesce(current_setting('cc.r1',true),'SIN CAPTURAR') as obtenido,
         current_setting('cc.r1',true) = 'anulado' as ok
  union all
  select 2, 'el dueño cancela su PERMISO pendiente', 'cancelado',
         coalesce(current_setting('cc.r2',true),'SIN CAPTURAR'),
         current_setting('cc.r2',true) = 'cancelado'
  union all
  select 3, 'y resuelto_por queda con el correo DEL EMPLEADO, no de una socia',
         'zz-a@example.invalid',
         coalesce(nullif(current_setting('cc.r2_por',true),''),'VACIO'),
         current_setting('cc.r2_por',true) = 'zz-a@example.invalid'
  union all
  select 4, 'la cancelada sale del CALENDARIO (una menos)',
         coalesce((nullif(current_setting('cc.a_cal',true),'')::numeric - 1)::text,'?'),
         coalesce(nullif(current_setting('cc.d_cal',true),''),'SIN DATO'),
         nullif(current_setting('cc.d_cal',true),'')::numeric
           = nullif(current_setting('cc.a_cal',true),'')::numeric - 1
  union all
  select 5, 'y sale de la BANDEJA (una menos)',
         coalesce((nullif(current_setting('cc.a_band',true),'')::numeric - 1)::text,'?'),
         coalesce(nullif(current_setting('cc.d_band',true),''),'SIN DATO'),
         nullif(current_setting('cc.d_band',true),'')::numeric
           = nullif(current_setting('cc.a_band',true),'')::numeric - 1
  union all
  select 6, 'los dias TOMADOS no se mueven (una pendiente nunca contaba)',
         coalesce(nullif(current_setting('cc.a_tom',true),''),'?'),
         coalesce(nullif(current_setting('cc.d_tom',true),''),'SIN DATO'),
         nullif(current_setting('cc.d_tom',true),'')::numeric
           = nullif(current_setting('cc.a_tom',true),'')::numeric
  union all
  select 7, 'y el estado de la cancelada es anulado', 'anulado',
         coalesce(nullif(current_setting('cc.d_e1',true),''),'SIN DATO'),
         current_setting('cc.d_e1',true) = 'anulado'
  union all
  select 8, 'OTRO empleado intenta cancelar la ajena -> rechazado', 'RECHAZA 42501',
         coalesce(current_setting('cc.r4',true),'SIN CAPTURAR'),
         coalesce(current_setting('cc.r4',true),'') like 'RECHAZA 42501%'
  union all
  select 9, 'cancelar una APROBADA -> rechazado, con el estado en el mensaje', 'RECHAZA 55000',
         coalesce(current_setting('cc.r5a',true),'SIN CAPTURAR'),
         coalesce(current_setting('cc.r5a',true),'') like 'RECHAZA 55000%'
           and coalesce(current_setting('cc.r5a',true),'') like '%aprobado%'
  union all
  select 10, 'cancelar una RECHAZADA -> rechazado', 'RECHAZA 55000',
         coalesce(current_setting('cc.r5b',true),'SIN CAPTURAR'),
         coalesce(current_setting('cc.r5b',true),'') like 'RECHAZA 55000%'
  union all
  select 11, 'cancelar una YA CANCELADA -> rechazado (es la carrera, en diferido)',
         'RECHAZA 55000',
         coalesce(current_setting('cc.r5c',true),'SIN CAPTURAR'),
         coalesce(current_setting('cc.r5c',true),'') like 'RECHAZA 55000%'
  union all
  select 12, 'ANON intenta cancelar -> rechazado', 'RECHAZA 42501',
         coalesce(current_setting('cc.r6',true),'SIN CAPTURAR'),
         coalesce(current_setting('cc.r6',true),'') like 'RECHAZA 42501%'
  union all
  select 13, 'la REPETIDA de una pendiente -> rechazada', 'RECHAZA 23505',
         coalesce(current_setting('cc.r7a',true),'SIN CAPTURAR'),
         coalesce(current_setting('cc.r7a',true),'') like 'RECHAZA 23505%'
  union all
  select 14, 'pedir de nuevo DESPUES de cancelar -> permitido', 'ENTRO (correcto)',
         coalesce(current_setting('cc.r7b',true),'SIN CAPTURAR'),
         current_setting('cc.r7b',true) = 'ENTRO (correcto)'
  union all
  select 15, 'las filas de Daniel en rrhh_evento, intactas',
         case when coalesce(current_setting('cc.daniel',true),'')=''
              then 'SIN PROBAR' else coalesce(current_setting('cc.a_daniel_ev',true),'?') end,
         case when coalesce(current_setting('cc.daniel',true),'')=''
              then 'SIN PROBAR · no identifique a Daniel'
              else coalesce(current_setting('cc.d_daniel_ev',true),'SIN DATO') end,
         coalesce(current_setting('cc.d_daniel_ev',true),'x')
           = coalesce(current_setting('cc.a_daniel_ev',true),'y')
  union all
  select 16, 'las filas de Daniel en rrhh_permiso, intactas',
         case when coalesce(current_setting('cc.daniel',true),'')=''
              then 'SIN PROBAR' else coalesce(current_setting('cc.a_daniel_pm',true),'?') end,
         case when coalesce(current_setting('cc.daniel',true),'')=''
              then 'SIN PROBAR · no identifique a Daniel'
              else coalesce(current_setting('cc.d_daniel_pm',true),'SIN DATO') end,
         coalesce(current_setting('cc.d_daniel_pm',true),'x')
           = coalesce(current_setting('cc.a_daniel_pm',true),'y')
  ) t
 order by t.orden;

rollback;

-- ── DESPUES DEL ROLLBACK ────────────────────────────────────────────────
-- No tiene que quedar nada:
--   select count(*) from acceso_usuario where nota = 'ensayo-cancelar';      -- 0
--   select count(*) from rrhh_persona  where creado_por = 'ensayo-cancelar'; -- 0
--   select count(*) from rrhh_evento   where creado_por = 'ensayo-cancelar'; -- 0
--   select count(*) from rrhh_permiso  where creado_por = 'ensayo-cancelar'; -- 0
