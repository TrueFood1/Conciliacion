-- ════════════════════════════════════════════════════════════════════════
-- ENSAYO · rrhh_resolver_evento() despues del arreglo · ROLLBACK
-- 7-oct-2026. Va DESPUES de PERSONAL_ARREGLO_RESOLVER.sql, ya pegado.
-- Se corre en el SQL Editor (como postgres).
--
-- ⚠️ TERMINA EN `rollback;`. No deja ni una fila: la persona ficticia, los
-- cuatro eventos y las resoluciones que escriba se deshacen todos.
--
-- ⚠️ NO IMPRIME NINGUN CORREO NI NINGUN MONTO. Las cuentas con las que se
-- impersona salen de acceso_usuario y viajan por un `set_config`, nunca a la
-- salida. La tabla final se puede pegar en un chat.
--
-- QUE SE PRUEBA (y por que cada uno)
--   A · socia APRUEBA .................... 1 fila. Es la prueba de que ahora SI
--       escribe: antes del arreglo esto daba 42501.
--   B · socia RECHAZA con motivo ......... 1 fila, aprobado = f
--   C · socia RECHAZA sin motivo ......... 1 fila. El motivo es OPCIONAL y el
--       servidor no lo exige; si algun dia lo exigiera, Lorena no podria
--       rechazar sin escribir nada y nadie sabria por que.
--   D · segunda resolucion del MISMO evento ... 0 filas, sin error. Es el
--       contrato con la pantalla: cero filas significa «ya la resolvio la otra
--       socia», no «fallo».
--   E · EMPLEADO intenta ................. tiene que FALLAR. Es la prueba de que
--       volver la funcion `security definer` no abrio aprobar a todo el equipo.
--       Sin esta, el arreglo podria ser peor que el bug.
--   F · ANON intenta ..................... tiene que FALLAR, y por el grant, no
--       por el guardia: las dos capas, no una.
--   G · despues de E y F, el evento sigue SIN resolucion. Que fallen no alcanza:
--       hay que comprobar que no escribieron nada.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── 0 · LAS CUENTAS (sin imprimirlas) ───────────────────────────────────
select set_config('ens.socia',
  coalesce((select email from acceso_usuario
             where perfil='socias' and activo order by id limit 1), ''), true);
select set_config('ens.equipo',
  coalesce((select email from acceso_usuario
             where perfil='equipo' and activo order by id limit 1), ''), true);

do $$
begin
  if coalesce(current_setting('ens.socia', true),'') = '' then
    raise exception 'ENSAYO ABORTADO: no hay socia activa en acceso_usuario. Sin eso los '
      'escenarios A, B, C y D no se pueden correr y el ensayo no probaria nada.';
  end if;
  -- El de empleado NO aborta: si no hay cuenta de equipo, el escenario E queda
  -- SIN PROBAR y se reporta asi. Inventar una cuenta falsa probaria otra cosa
  -- (una cuenta desconocida, que no es lo mismo que un empleado real).
  if coalesce(current_setting('ens.equipo', true),'') = '' then
    raise warning 'No hay cuenta de perfil equipo: el escenario E va a salir SIN PROBAR.';
  end if;
end $$;


-- ── 1 · DATOS FICTICIOS ─────────────────────────────────────────────────
with p as (
  insert into rrhh_persona (nombre, email, puesto, ingreso, creado_por)
  values ('ZZ Resolver · ensayo', null, 'ensayo', '2026-01-05', 'ensayo-resolver')
  returning id
)
select set_config('ens.pid', id::text, true) from p;

-- Cuatro solicitudes de vacaciones, una por escenario que escribe.
with e as (
  insert into rrhh_evento (persona_id, fecha, tipo, dias, motivo, creado_por)
  select current_setting('ens.pid', true)::bigint,
         (date '2026-11-02' + (n-1)*7), 'vacaciones', 1,
         'ensayo ' || n, 'ensayo-resolver'
    from generate_series(1,4) n
  returning id
)
select set_config('ens.e' || row_number() over (order by id), id::text, true) from e;


-- ── 2 · A, B, C, D · COMO SOCIA ─────────────────────────────────────────
-- Cada escenario pone el rol y las claims, llama, guarda el resultado y VUELVE a
-- postgres. Volver es legal porque el usuario de sesion sigue siendo postgres.
do $$
declare n int; r record; q text;
begin
  perform set_config('request.jwt.claims',
    json_build_object('email', current_setting('ens.socia', true),
                      'role','authenticated')::text, true);
  perform set_config('role','authenticated', true);

  if not coalesce(acceso_es_socia(), false) then
    perform set_config('role','postgres', true);
    raise exception 'ENSAYO ABORTADO: impersonar a la socia no funciono (acceso_es_socia() '
      'dio false). Los escenarios habrian "pasado" sin medir nada.';
  end if;

  -- A · aprueba el evento 1
  begin
    select count(*) into n from rrhh_resolver_evento(
      current_setting('ens.e1', true)::bigint, true, null, null, null);
    perform set_config('ens.a_filas', n::text, true);
  exception when others then
    -- Si el pegado 8 no entro, aca cae 42501 y esto lo DICE en la tabla en vez
    -- de tumbar el ensayo con un error crudo.
    perform set_config('ens.a_filas', 'ERROR ' || sqlstate || ' · ' || left(sqlerrm, 45), true);
  end;
  perform set_config('ens.a_aprobado',
    coalesce((select a.aprobado::text from rrhh_evento_aprob a
               where a.evento_id = current_setting('ens.e1', true)::bigint), ''), true);

  -- B · rechaza el evento 2 CON motivo
  begin
    select count(*) into n from rrhh_resolver_evento(
      current_setting('ens.e2', true)::bigint, false, null, null, 'se genero doble');
    perform set_config('ens.b_filas', n::text, true);
  exception when others then
    perform set_config('ens.b_filas', 'ERROR ' || sqlstate || ' · ' || left(sqlerrm, 45), true);
  end;
  select a.aprobado, a.motivo into r from rrhh_evento_aprob a
   where a.evento_id = current_setting('ens.e2', true)::bigint;
  perform set_config('ens.b_aprobado', coalesce(r.aprobado::text,''), true);
  perform set_config('ens.b_motivo',   coalesce(r.motivo,''), true);

  -- C · rechaza el evento 3 SIN motivo
  begin
    select count(*) into n from rrhh_resolver_evento(
      current_setting('ens.e3', true)::bigint, false, null, null, null);
    perform set_config('ens.c_filas', n::text, true);
  exception when others then
    perform set_config('ens.c_filas', 'ERROR ' || sqlstate || ' · ' || left(sqlerrm, 45), true);
  end;
  perform set_config('ens.c_motivo_es_null',
    coalesce((select (a.motivo is null)::text from rrhh_evento_aprob a
               where a.evento_id = current_setting('ens.e3', true)::bigint), ''), true);

  -- D · el evento 1 OTRA VEZ -> 0 filas y sin error
  begin
    select count(*) into n from rrhh_resolver_evento(
      current_setting('ens.e1', true)::bigint, false, null, null, 'segunda vuelta');
    perform set_config('ens.d_filas', n::text, true);
    perform set_config('ens.d_error', '', true);
  exception when others then
    perform set_config('ens.d_filas', '-1', true);
    perform set_config('ens.d_error', sqlstate || ' ' || left(sqlerrm, 50), true);
  end;
  -- Y que la resolucion original NO se haya pisado: sigue siendo la aprobacion.
  perform set_config('ens.d_sigue_aprobada',
    coalesce((select a.aprobado::text from rrhh_evento_aprob a
               where a.evento_id = current_setting('ens.e1', true)::bigint
               order by a.creado_en limit 1), ''), true);
  perform set_config('ens.d_cuantas',
    (select count(*)::text from rrhh_evento_aprob a
      where a.evento_id = current_setting('ens.e1', true)::bigint), true);

  perform set_config('role','postgres', true);
end $$;


-- ── 3 · E · COMO EMPLEADO · TIENE QUE FALLAR ────────────────────────────
do $$
declare n int;
begin
  if coalesce(current_setting('ens.equipo', true),'') = '' then
    perform set_config('ens.e_estado',
      'SIN PROBAR · no hay cuenta de perfil equipo en acceso_usuario', true);
    return;
  end if;
  perform set_config('request.jwt.claims',
    json_build_object('email', current_setting('ens.equipo', true),
                      'role','authenticated')::text, true);
  perform set_config('role','authenticated', true);
  begin
    select count(*) into n from rrhh_resolver_evento(
      current_setting('ens.e4', true)::bigint, true, null, null, null);
    perform set_config('ens.e_estado', 'ENTRO (' || n || ' filas) -> FUGA', true);
  exception when others then
    perform set_config('ens.e_estado', 'RECHAZA ' || sqlstate || ' · ' || left(sqlerrm, 55), true);
  end;
  perform set_config('role','postgres', true);
end $$;


-- ── 4 · F · COMO ANON · TIENE QUE FALLAR POR EL GRANT ───────────────────
do $$
declare n int;
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('role','anon', true);
  begin
    select count(*) into n from rrhh_resolver_evento(
      current_setting('ens.e4', true)::bigint, true, null, null, null);
    perform set_config('ens.f_estado', 'ENTRO (' || n || ' filas) -> FUGA', true);
  exception when others then
    perform set_config('ens.f_estado', 'RECHAZA ' || sqlstate || ' · ' || left(sqlerrm, 55), true);
  end;
  perform set_config('role','postgres', true);
end $$;


-- ── 5 · G · LOS DOS INTENTOS FALLIDOS NO ESCRIBIERON NADA ───────────────
select set_config('ens.g_resoluciones',
  (select count(*)::text from rrhh_evento_aprob a
    where a.evento_id = current_setting('ens.e4', true)::bigint), true);


-- ── 6 · LA TABLA ────────────────────────────────────────────────────────
select t.orden, t.prueba, t.esperado, t.obtenido,
       case when t.obtenido like 'SIN PROBAR%' then 'SIN PROBAR'
            when t.ok then 'OK' else 'FALLA' end as veredicto
  from (
  select 1 as orden, 'A · socia APRUEBA -> 1 fila'::text as prueba, '1'::text as esperado,
         coalesce(current_setting('ens.a_filas', true),'SIN CAPTURAR') as obtenido,
         current_setting('ens.a_filas', true) = '1' as ok
  union all
  select 2, 'A · y queda aprobado = t', 't',
         coalesce(nullif(current_setting('ens.a_aprobado', true),''),'SIN FILA'),
         current_setting('ens.a_aprobado', true) = 'true'
  union all
  select 3, 'B · socia RECHAZA con motivo -> 1 fila', '1',
         coalesce(current_setting('ens.b_filas', true),'SIN CAPTURAR'),
         current_setting('ens.b_filas', true) = '1'
  union all
  select 4, 'B · y queda aprobado = f', 'f',
         coalesce(nullif(current_setting('ens.b_aprobado', true),''),'SIN FILA'),
         current_setting('ens.b_aprobado', true) = 'false'
  union all
  select 5, 'B · y el motivo se guardo', 'se genero doble',
         coalesce(nullif(current_setting('ens.b_motivo', true),''),'VACIO'),
         current_setting('ens.b_motivo', true) = 'se genero doble'
  union all
  select 6, 'C · socia RECHAZA sin motivo -> 1 fila (el motivo es opcional)', '1',
         coalesce(current_setting('ens.c_filas', true),'SIN CAPTURAR'),
         current_setting('ens.c_filas', true) = '1'
  union all
  select 7, 'C · y el motivo quedo null, no vacio', 't',
         coalesce(nullif(current_setting('ens.c_motivo_es_null', true),''),'SIN FILA'),
         current_setting('ens.c_motivo_es_null', true) = 'true'
  union all
  select 8, 'D · segunda resolucion del mismo evento -> 0 filas, SIN error', '0',
         coalesce(current_setting('ens.d_filas', true),'SIN CAPTURAR')
           || case when coalesce(current_setting('ens.d_error', true),'') <> ''
                   then ' · ERROR: ' || current_setting('ens.d_error', true) else '' end,
         current_setting('ens.d_filas', true) = '0'
           and coalesce(current_setting('ens.d_error', true),'') = ''
  union all
  select 9, 'D · y no se pisó la resolucion original (sigue 1 sola, aprobada)', '1 / t',
         coalesce(current_setting('ens.d_cuantas', true),'?') || ' / '
           || coalesce(nullif(current_setting('ens.d_sigue_aprobada', true),''),'?'),
         current_setting('ens.d_cuantas', true) = '1'
           and current_setting('ens.d_sigue_aprobada', true) = 'true'
  union all
  select 10, 'E · EMPLEADO intenta -> rechazado por el guardia de la funcion',
         'RECHAZA 42501',
         coalesce(current_setting('ens.e_estado', true),'SIN CAPTURAR'),
         coalesce(current_setting('ens.e_estado', true),'') like 'RECHAZA 42501%'
  union all
  select 11, 'F · ANON intenta -> rechazado (por el grant, antes del guardia)',
         'RECHAZA 42501',
         coalesce(current_setting('ens.f_estado', true),'SIN CAPTURAR'),
         coalesce(current_setting('ens.f_estado', true),'') like 'RECHAZA 42501%'
  union all
  select 12, 'G · los dos intentos fallidos no escribieron nada', '0',
         coalesce(current_setting('ens.g_resoluciones', true),'SIN CAPTURAR'),
         current_setting('ens.g_resoluciones', true) = '0'
) t
 order by t.orden;

rollback;

-- ── DESPUES DEL ROLLBACK ────────────────────────────────────────────────
-- No tiene que quedar nada. Para comprobarlo (otra consulta, ya fuera de la
-- transaccion):
--   select count(*) from rrhh_persona      where creado_por = 'ensayo-resolver'; -- 0
--   select count(*) from rrhh_evento       where creado_por = 'ensayo-resolver'; -- 0
--   select count(*) from rrhh_evento_aprob
--    where evento_id in (select id from rrhh_evento
--                         where creado_por = 'ensayo-resolver');                 -- 0
--
-- ⚠️ Y el rol: el ensayo cambia `role` varias veces con set_config(..., true),
-- que es transaccional, asi que el rollback lo devuelve solo. Si por algo
-- quedara pegado en `anon` o `authenticated`, se destraba con `reset role;`.
