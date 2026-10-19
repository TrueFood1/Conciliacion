-- ════════════════════════════════════════════════════════════════════════
-- ARREGLO · rrhh_resolver_evento() NO PODIA INSERTAR  (PEGADO 8)
-- Preparado el 7-oct-2026. NO SE CORRIO.
-- Va DESPUES de PERSONAL_CALENDARIO.sql (pegado 4), que NO SE TOCA.
-- Solo redefine UNA funcion y repone sus privilegios. No crea tablas, no
-- cambia vistas, no toca ninguna politica.
--
-- ════════════════════════════════════════════════════════════════════════
-- EL BUG, MEDIDO EL 7-OCT-2026
-- ════════════════════════════════════════════════════════════════════════
-- Lorena rechazo dos veces una solicitud de vacaciones duplicada y la bandeja
-- siguio mostrando las dos. Medido con DIAGNOSTICO_PERMISOS_RESOLVER.sql:
--     authenticated puede INSERT en rrhh_evento_aprob .... f
--     rrhh_resolver_evento es security definer ........... f
-- y con el detalle de las solicitudes: las dos existen, NINGUNA tiene
-- resolucion. O sea que los dos rechazos nunca se guardaron.
--
-- LA CADENA, ENTERA. `rrhh_resolver_evento()` inserta en `rrhh_evento_aprob`.
-- El pegado 4 le quito el INSERT a `authenticated` a proposito, para que la
-- unica entrada fuera esta funcion — pero la funcion NO ES `security definer`,
-- asi que su insert corre con los permisos de quien llama y entra por la MISMA
-- puerta que le acababan de cerrar. Resultado: 42501 para todo el mundo, socias
-- incluidas. No es un problema de la cuenta de Lorena: ninguna cuenta podia.
--
-- El pegado 4 lo dijo con todas las letras y se equivoco en una sola frase:
-- «Qué NO rompe: hoy nada inserta ahí. La herramienta publicada no tiene
-- pantalla de aprobación (esta es la primera)». El MISMO pegado que revoco el
-- privilegio trajo la pantalla que lo necesitaba. Es la regla de CLAUDE.md
-- —una salvaguarda citada no es una salvaguarda verificada— aplicada al efecto
-- COLATERAL de una salvaguarda: el revoke era correcto, lo que nadie corrio fue
-- el camino que quedaba del otro lado.
--
-- POR QUE NUNCA SE NOTO HASTA HOY. Aprobar o rechazar un PERMISO si funciona:
-- es un UPDATE directo sobre `rrhh_permiso`, cuyo grant por columna si esta
-- puesto. Mismo boton, misma cuenta, otra tabla. Las vacaciones eran el unico
-- camino roto, y hasta esta semana nadie habia rechazado una.
--
-- ════════════════════════════════════════════════════════════════════════
-- QUE CAMBIA, Y QUE NO
-- ════════════════════════════════════════════════════════════════════════
--   · La funcion pasa a `security definer`, asi que su insert corre con los
--     permisos de su DUEÑO y el revoke deja de frenarla.
--   · Y porque pasa a security definer, LA FUNCION TIENE QUE PONER EL GUARDIA
--     ELLA MISMA: `acceso_es_socia()` al principio, antes de cualquier
--     escritura. Sin eso, volverla definer abriria el aprobar a todo el equipo,
--     que es MUCHO peor que el bug que arregla — la politica
--     `rrhh_evento_aprob_ins` ya no la frena, porque un definer la esquiva.
--     El guardia no es un extra: es la condicion para que este cambio sea seguro.
--   · `set search_path = public` ya estaba y se mantiene. En una funcion
--     `security definer` eso no es estilo: sin el, quien llama puede poner un
--     esquema propio adelante y hacer que la funcion ejecute SU `acceso_es_socia`.
--   · El `revoke insert on rrhh_evento_aprob from authenticated` del pegado 4
--     SE MANTIENE TAL CUAL. La funcion vuelve a ser la unica entrada, que era
--     la intencion original — ahora de verdad.
--   · `execute` cerrado a `anon` y a `public`, abierto solo a `authenticated`.
--
-- ⚠️ EL CUERPO SALIO DEL PEGADO 4, no reescrito de memoria: el lock, el
-- `if exists … return` y el INSERT dentro del CTE son identicos. Lo unico nuevo
-- son las dos primeras lineas del guardia y la cabecera.
--
-- ⚠️ ESTO NO ARREGLA LA SOLICITUD DUPLICADA. Despues de pegar esto, Lorena puede
-- rechazar las dos, pero van a quedar las dos rechazadas en el historial: hoy no
-- hay forma de borrar ni anular una duplicada (ver el reporte aparte). Rechazar
-- las dos es el camino correcto y deja el rastro honesto de lo que paso.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── 1 · LA FUNCION ──────────────────────────────────────────────────────
create or replace function rrhh_resolver_evento(
  p_evento_id     bigint,
  p_aprobado      boolean,
  p_tipo_final    text default null,     -- null = se queda el tipo solicitado
  p_destino_final text default null,
  p_motivo        text default null)
returns table (id bigint, evento_id bigint, aprobado boolean,
               creado_por text, creado_en timestamptz)
language plpgsql
security definer                          -- ⚠️ LO NUEVO. Ver el guardia de abajo.
set search_path = public
as $$
begin
  -- EL GUARDIA, Y VA PRIMERO. Con `security definer` la politica
  -- `rrhh_evento_aprob_ins` (with check acceso_es_socia()) ya NO se evalua: la
  -- funcion corre como su dueño y la esquiva. Entonces la regla tiene que vivir
  -- aca, antes de cualquier escritura, o aprobar se abriria a todo el equipo.
  --
  -- `coalesce(..., false)` porque acceso_es_socia() devuelve NULL cuando la
  -- cuenta no esta en acceso_usuario, y `if not null` no entra al then: una
  -- cuenta desconocida pasaria de largo. Es el mismo hueco del NULL que ya
  -- aparecio en los CHECK de este modulo.
  if not coalesce(acceso_es_socia(), false) then
    raise exception 'Solo una socia puede aprobar o rechazar una solicitud.'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('rrhh_evento_aprob:' || p_evento_id, 0));

  if exists (select 1 from rrhh_evento_aprob a where a.evento_id = p_evento_id) then
    return;                                  -- 0 filas = ya estaba resuelto
  end if;

  -- El INSERT va adentro de un CTE y no suelto detrás del `return query`. Las dos
  -- formas hacen lo mismo, pero esta es indiscutiblemente un SELECT: no depende
  -- de que `return query` acepte una sentencia que escribe, y de paso los
  -- nombres salen calificados por `ins`, sin poder chocar con los parámetros de
  -- salida de la función, que se llaman igual (id, evento_id, aprobado…).
  return query
  with ins as (
    insert into rrhh_evento_aprob (evento_id, aprobado, tipo_final, destino_final,
                                   motivo, creado_por)
    values (p_evento_id, p_aprobado, p_tipo_final, p_destino_final, p_motivo,
            coalesce(auth.jwt() ->> 'email', 'desconocido'))
    returning rrhh_evento_aprob.id, rrhh_evento_aprob.evento_id,
              rrhh_evento_aprob.aprobado, rrhh_evento_aprob.creado_por,
              rrhh_evento_aprob.creado_en
  )
  select ins.id, ins.evento_id, ins.aprobado, ins.creado_por, ins.creado_en from ins;
end $$;

comment on function rrhh_resolver_evento(bigint, boolean, text, text, text) is
  'Aprueba o rechaza una solicitud de rrhh_evento insertando en rrhh_evento_aprob. '
  'SECURITY DEFINER desde el 7-oct-2026: hasta entonces era invoker y el revoke de '
  'INSERT del pegado 4 la dejaba sin poder escribir — todo rechazo de vacacion '
  'fallaba con 42501, para cualquier cuenta. Por ser definer, el permiso de socia '
  'lo comprueba ELLA MISMA con acceso_es_socia(): la politica rrhh_evento_aprob_ins '
  'ya no se evalua. Es la UNICA entrada a esa tabla, a proposito. '
  'El motivo es OPCIONAL, tanto para aprobar como para rechazar.';


-- ── 2 · LOS PRIVILEGIOS DE LA FUNCION ───────────────────────────────────
-- `create or replace function` conserva la ACL, asi que esto es reponer lo del
-- pegado 4 por si acaso, no corregir nada. Idempotente y cuesta nada.
--
-- ⚠️ `execute` se le da a PUBLIC por defecto en toda funcion nueva, y en una
-- `security definer` eso es mucho mas grave que en una normal: cualquiera con la
-- anon key la llamaria y correria con los permisos del dueño. El guardia de
-- adentro igual lo frenaria (anon no es socia), pero no se depende de una sola
-- capa — es la leccion del 24-ago.
revoke all on function rrhh_resolver_evento(bigint, boolean, text, text, text)
  from anon, public;
grant execute on function rrhh_resolver_evento(bigint, boolean, text, text, text)
  to authenticated;

-- EL REVOKE DEL PEGADO 4 NO SE TOCA, y se deja escrito para que nadie lo
-- "arregle" pensando que fue el culpable: el revoke era correcto. Lo que faltaba
-- era que la funcion no entrara por esa puerta.
--   revoke insert on rrhh_evento_aprob from authenticated;   <- SIGUE VIGENTE


-- ── 3 · EL CANDADO ──────────────────────────────────────────────────────
-- Lo que no se puede dejar pasar: una funcion `security definer` SIN el guardia
-- de socia adentro (seria aprobar abierto a todo el equipo), o sin search_path
-- fijo, o con execute para anon. Si algo de eso falla, la transaccion se cae
-- entera y no se aplica NADA.
do $candado$
declare
  v_def   boolean;
  v_path  text[];
  v_src   text;
  v_anon  boolean;
  v_auth  boolean;
  v_ins   boolean;
begin
  select p.prosecdef, p.proconfig, p.prosrc into v_def, v_path, v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'rrhh_resolver_evento';

  v_anon := has_function_privilege('anon',
    'public.rrhh_resolver_evento(bigint, boolean, text, text, text)', 'EXECUTE');
  v_auth := has_function_privilege('authenticated',
    'public.rrhh_resolver_evento(bigint, boolean, text, text, text)', 'EXECUTE');
  v_ins  := has_table_privilege('authenticated','public.rrhh_evento_aprob','INSERT');

  if v_def is null then
    raise exception 'CANDADO: rrhh_resolver_evento no existe. NO SE APLICO NADA.';
  end if;
  if not v_def then
    raise exception 'CANDADO: la funcion NO quedo security definer, que es justo lo que '
      'este pegado viene a arreglar. NO SE APLICO NADA.';
  end if;
  -- EL GUARDIA SE BUSCA EN EL CUERPO, no se da por puesto. Una definer sin el
  -- deja que cualquier empleado se apruebe sus propias vacaciones.
  if position('acceso_es_socia' in v_src) = 0 then
    raise exception 'CANDADO: la funcion es security definer y NO llama a '
      'acceso_es_socia(). Asi aprobar quedaria abierto a todo el equipo, porque un '
      'definer esquiva la politica rrhh_evento_aprob_ins. NO SE APLICO NADA.';
  end if;
  if v_path is null or not (v_path @> array['search_path=public']) then
    raise exception 'CANDADO: la funcion no tiene `set search_path = public`. En una '
      'security definer eso deja que quien llama le cambie que acceso_es_socia() '
      'ejecuta. NO SE APLICO NADA.';
  end if;
  if v_anon then
    raise exception 'CANDADO: `anon` puede EJECUTAR la funcion. Es security definer y la '
      'anon key es PUBLICA. NO SE APLICO NADA.';
  end if;
  if not v_auth then
    raise exception 'CANDADO: `authenticated` NO puede ejecutarla, asi que la pantalla '
      'seguiria rota. NO SE APLICO NADA.';
  end if;
  -- Y que el revoke del pegado 4 siga en pie: la funcion es la UNICA entrada.
  if v_ins then
    raise exception 'CANDADO: `authenticated` recupero INSERT directo en '
      'rrhh_evento_aprob. Con esa puerta abierta el guardia de la funcion es un '
      'adorno: se puede insertar una aprobacion por REST sin pasar por ella. '
      'NO SE APLICO NADA.';
  end if;

  raise notice 'CANDADO OK: definer con guardia de socia · search_path fijo · anon sin execute · '
    'authenticated con execute · insert directo sigue cerrado';
end
$candado$;


-- ── 4 · LA PRUEBA DE QUE LA TRANSACCION LLEGO HASTA ACA ─────────────────
-- Regla 🔴 de CLAUDE.md: un "Success" del editor no es evidencia de nada.
-- ESPERADO:  t · t · t · f · t · f
select
  (select p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='rrhh_resolver_evento')      as es_security_definer,
  (select p.proconfig @> array['search_path=public'] from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='rrhh_resolver_evento')       as search_path_fijo,
  (select position('acceso_es_socia' in p.prosrc) > 0 from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='rrhh_resolver_evento')       as tiene_guardia,
  has_function_privilege('anon',
    'public.rrhh_resolver_evento(bigint, boolean, text, text, text)','EXECUTE')
                                                                        as anon_execute_debe_ser_f,
  has_function_privilege('authenticated',
    'public.rrhh_resolver_evento(bigint, boolean, text, text, text)','EXECUTE')
                                                                        as auth_execute_debe_ser_t,
  has_table_privilege('authenticated','public.rrhh_evento_aprob','INSERT')
                                                                        as insert_directo_debe_ser_f;

commit;


-- ════════════════════════════════════════════════════════════════════════
-- DESPUES DEL COMMIT
-- ════════════════════════════════════════════════════════════════════════
--   1. PRUEBAS_RESOLVER.sql — cinco escenarios con datos ficticios y ROLLBACK.
--      Es lo unico que prueba que ahora SI escribe, y que el empleado NO puede.
--   2. `python3 esquema_check.py` y `python3 herramientas/sonda_columnas.py
--      --nuevas`: no deberian moverse (esto no agrega objetos ni columnas). Que
--      no se muevan es el resultado correcto.
--   3. Y la prueba real: Lorena entra al Calendario y rechaza las DOS solicitudes
--      duplicadas del 19-20 de nov. Las dos tienen que desaparecer de la bandeja
--      y quedar como «rechazado» en «Lo que pediste» de Daniel.
--      ⚠️ Si el aviso de error vuelve a aparecer, NO es esto: el aviso vive en
--      #calStatus, arriba del calendario, y la bandeja esta abajo — queda a una
--      pantalla de distancia del boton. Eso sigue sin arreglar (reporte aparte).
