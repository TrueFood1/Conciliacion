-- SOLO ENSAYO · PRUEBAS_CANCELAR.sql · termina en ROLLBACK, no deja nada
-- ════════════════════════════════════════════════════════════════════════
-- ENSAYO · cancelar lo propio + anti repetidas · CON EL PEGADO 9 ADENTRO
-- GENERADO por herramientas/ensayos/armar_ensayo_cancelar.py — NO editar a
-- mano: se regenera y se pierde. Para cambiar las pruebas, editar
-- herramientas/ensayos/pruebas_cancelar_cuerpo.sql y volver a correrlo.
--
-- ⚠️ ADENTRO VA EL CUERPO REAL DE PERSONAL_CANCELAR_SOLICITUD.sql, extraido
-- del archivo por estructura (el unico begin; y el unico commit;, sin
-- incluirlos). md5 del cuerpo extraido: b7e172792f2132bd5406134dab2095fd
-- O sea que esto NO prueba una copia: prueba byte a byte lo que se va a pegar.
-- Un ensayo que valida una copia se desincroniza en silencio — se arregla el
-- pegado, el ensayo sigue validando lo viejo, y da verde.
--
-- ⚠️ TERMINA EN `rollback;`. Crea y deshace TODO: el esquema del pegado (el
-- CHECK nuevo, la funcion, los dos triggers) y los datos ficticios. No deja
-- ni una fila ni un objeto.
--
-- ⚠️ CUENTAS FICTICIAS. Crea dos empleados y una socia en rrhh_persona y
-- acceso_usuario con correos @example.invalid: no depende de que exista tal
-- cuenta real y no escribe nada a nombre de ninguna persona de verdad.
--
-- ⚠️ SOBRE LA CARRERA: una carrera real necesita DOS sesiones concurrentes y
-- una transaccion no puede tenerlas. Lo que se prueba es su CONSECUENCIA
-- determinista —el segundo encuentra el estado ya cambiado y recibe el mensaje
-- claro—, que es lo que el lock garantiza. No se afirma haber probado
-- concurrencia real.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  CUERPO DE PERSONAL_CANCELAR_SOLICITUD.sql — pegado tal cual         ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- ── 1 · 'cancelado' EN EL CHECK DE rrhh_permiso ─────────────────────────
-- EL CHECK VIEJO NO TIENE NOMBRE PROPIO: nacio inline en el `create table`, asi
-- que Postgres le puso uno generado. Se lo busca POR SU DEFINICION en vez de
-- adivinar el nombre, y se aborta si no aparece exactamente uno — adivinar el
-- nombre es como se dropea el constraint equivocado.
do $$
declare v_n int; v_name text;
begin
  select count(*), min(c.conname) into v_n, v_name
    from pg_constraint c join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
   where n.nspname='public' and t.relname='rrhh_permiso' and c.contype='c'
     and pg_get_constraintdef(c.oid) like '%estado%'
     and pg_get_constraintdef(c.oid) like '%pendiente%'
     and pg_get_constraintdef(c.oid) like '%rechazado%'
     and pg_get_constraintdef(c.oid) not like '%resuelto%';
  if v_n <> 1 then
    raise exception 'ABORTADO: encontre % CHECK(s) candidatos al de estado en rrhh_permiso '
      '(tenia que ser 1). No se dropea a ciegas. Mirá cuales son con: select conname, '
      'pg_get_constraintdef(oid) from pg_constraint where conrelid = ''rrhh_permiso''::regclass;', v_n;
  end if;
  execute format('alter table rrhh_permiso drop constraint %I', v_name);
  raise notice 'CHECK viejo de estado eliminado: %', v_name;
end $$;

alter table rrhh_permiso add constraint rrhh_permiso_estado_ok check (
  estado in ('pendiente','aprobado','rechazado','cancelado'));

comment on constraint rrhh_permiso_estado_ok on rrhh_permiso is
  'Estados de un permiso. ''cancelado'' entro el 15-oct-2026: lo pone quien PIDIO el '
  'permiso, desde «Mis solicitudes», y solo mientras siga pendiente. El trigger '
  'rrhh_permiso_sella ya lo sella (cambia de estado y no es pendiente), y el CHECK '
  'rrhh_permiso_resuelto lo acepta por su segunda rama. Ojo al leer el historial: en una '
  'cancelacion `resuelto_por` es el correo DEL EMPLEADO, no de una socia.';


-- ── 2 · CANCELAR LO PROPIO ──────────────────────────────────────────────
-- SECURITY DEFINER, y por eso el guardia va ADENTRO: corriendo como su dueño la
-- funcion esquiva la RLS y el grant por columna de rrhh_permiso, que es
-- justamente lo que hace falta (el empleado no tiene update sobre esa tabla y no
-- se le va a dar). La contrapartida es que la regla «solo el dueño» no la puede
-- hacer cumplir ninguna politica: la hace cumplir esta funcion o no la hace
-- cumplir nadie.
create or replace function rrhh_cancelar_solicitud(
  p_tipo   text,
  p_id     bigint,
  p_motivo text default null)
returns table (tipo text, id bigint, estado text, resuelto_por text, resuelto_en timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo     bigint := rrhh_mi_persona();
  v_dueno  bigint;
  v_estado text;
  v_quien  text := coalesce(auth.jwt() ->> 'email', 'desconocido');
  v_n      int;
begin
  -- 2.1 · ¿QUIEN LLAMA? `rrhh_mi_persona()` devuelve null para una socia, para
  -- el asistente y para cualquier cuenta que no calce con rrhh_persona. Ninguna
  -- de esas tiene solicitudes propias que cancelar.
  if v_yo is null then
    raise exception 'Tu cuenta no está enlazada a una persona del equipo, así que no tiene '
      'solicitudes propias que cancelar.' using errcode = '42501';
  end if;

  if p_tipo not in ('vacacion','permiso') then
    raise exception 'Tipo de solicitud desconocido: «%». Tiene que ser vacacion o permiso.',
      p_tipo using errcode = '22023';
  end if;

  if p_tipo = 'vacacion' then
    -- 2.2 · EL MISMO LOCK Y LA MISMA LLAVE que rrhh_resolver_evento(). Esto es lo
    -- que serializa a la socia que aprueba contra el dueño que cancela: las dos
    -- escrituras pasan por una funcion que toma este lock, asi que la segunda
    -- espera y despues LEE EL ESTADO YA CAMBIADO. Gana la primera.
    perform pg_advisory_xact_lock(hashtextextended('rrhh_evento_aprob:' || p_id, 0));

    select e.persona_id into v_dueno
      from rrhh_evento e where e.id = p_id and e.tipo = 'vacaciones';
    if v_dueno is null then
      raise exception 'No encontré esa solicitud de vacaciones.' using errcode = '02000';
    end if;
    if v_dueno <> v_yo then
      raise exception 'Esa solicitud es de otra persona: solo quien la pidió puede cancelarla.'
        using errcode = '42501';
    end if;

    -- 2.3 · EL ESTADO SE LEE ADENTRO DEL LOCK, no antes. Leerlo afuera es la
    -- carrera: entre la lectura y la escritura la socia puede haber aprobado.
    select v.estado into v_estado from v_rrhh_evento_estado v where v.id = p_id;
    if v_estado <> 'solicitado' then
      raise exception 'Esa solicitud ya está %: no se puede cancelar. Si fue un error, '
        'hablalo con Andrea o Lorena.', v_estado using errcode = '55000';
    end if;

    -- 2.4 · `anulada => true` EXPLICITO. El default es false y el comentario del
    -- esquema esta al reves: con el default, esta fila no anularia nada y nadie
    -- se enteraria. Ver el encabezado.
    insert into rrhh_evento_anulado (evento_id, anulada, motivo, creado_por)
    values (p_id, true,
            coalesce(nullif(btrim(p_motivo),''), 'Cancelada por quien la pidió'),
            v_quien);

    return query
      select 'vacacion'::text, p_id, v2.estado, v2.anulada_por, v2.anulada_en
        from (select v.estado,
                     (select a.creado_por from rrhh_evento_anulado a
                       where a.evento_id = p_id order by a.creado_en desc limit 1) as anulada_por,
                     (select a.creado_en  from rrhh_evento_anulado a
                       where a.evento_id = p_id order by a.creado_en desc limit 1) as anulada_en
                from v_rrhh_evento_estado v where v.id = p_id) v2;

  else
    -- 2.5 · PERMISOS. Se toma el lock igual, por simetria y para documentar la
    -- intencion, PERO hay que decir la verdad sobre que protege: la socia aprueba
    -- un permiso con un UPDATE DIRECTO desde la app, que NO pasa por ninguna
    -- funcion y por lo tanto NO toma este lock. Lo que serializa de verdad es el
    -- candado de FILA de Postgres mas el `and estado = 'pendiente'` del WHERE:
    -- las dos escrituras compiten por la misma fila, la segunda espera, y cuando
    -- entra ya no encuentra 'pendiente' y afecta CERO filas. De ahi el chequeo de
    -- row_count de abajo, que es el que convierte esa carrera en un mensaje.
    perform pg_advisory_xact_lock(hashtextextended('rrhh_permiso:' || p_id, 0));

    select pm.persona_id, pm.estado into v_dueno, v_estado
      from rrhh_permiso pm where pm.id = p_id for update;
    if v_dueno is null then
      raise exception 'No encontré ese permiso.' using errcode = '02000';
    end if;
    if v_dueno <> v_yo then
      raise exception 'Ese permiso es de otra persona: solo quien lo pidió puede cancelarlo.'
        using errcode = '42501';
    end if;
    if v_estado <> 'pendiente' then
      raise exception 'Ese permiso ya está %: no se puede cancelar. Si fue un error, hablalo '
        'con Andrea o Lorena.', v_estado using errcode = '55000';
    end if;

    -- `resuelto_por` y `resuelto_en` los pone el trigger rrhh_permiso_sella, que
    -- dispara porque el estado cambia y no queda en 'pendiente'. No se tocan aca.
    -- ⚠️ EL ALIAS `pm` NO ES ESTILO: SIN EL, ESTO NO CORRE.
    -- Los cinco nombres de `returns table (tipo, id, estado, resuelto_por,
    -- resuelto_en)` son VARIABLES en alcance dentro de la funcion, y los cinco
    -- coinciden con columnas de las tablas que esta funcion toca. Asi que
    -- `where id = p_id and estado = 'pendiente'` no dice si `id` es la columna o
    -- la variable: PL/pgSQL corta con 42702, column reference "id" is ambiguous.
    -- Lo encontro el ensayo del 15-oct (fila 2). La rama de vacaciones paso de
    -- casualidad, porque ahi cada referencia ya estaba calificada — el riesgo
    -- estaba igual, solo que dormido.
    -- En el `set` NO se califica: ahi Postgres solo admite una columna, y
    -- `set pm.estado` es error de sintaxis. La ambiguedad vive en el WHERE.
    update rrhh_permiso pm
       set estado = 'cancelado',
           resolucion_nota = coalesce(nullif(btrim(p_motivo),''), 'Cancelada por quien la pidió')
     where pm.id = p_id and pm.estado = 'pendiente';
    get diagnostics v_n = row_count;
    if v_n <> 1 then
      raise exception 'No se pudo cancelar: alguien lo resolvió justo en este momento. '
        'Recargá la pantalla para ver cómo quedó.' using errcode = '55000';
    end if;

    return query
      select 'permiso'::text, pm.id, pm.estado, pm.resuelto_por, pm.resuelto_en
        from rrhh_permiso pm where pm.id = p_id;
  end if;
end $$;

comment on function rrhh_cancelar_solicitud(text, bigint, text) is
  'Cancela una solicitud PROPIA mientras siga pendiente. SECURITY DEFINER: el guardia de '
  '«solo el dueño» (rrhh_mi_persona()) vive ADENTRO, porque corriendo como su dueño la '
  'funcion esquiva la RLS y el grant por columna de rrhh_permiso. Vacaciones: inserta en '
  'rrhh_evento_anulado con anulada = true. Permisos: estado -> cancelado. Nunca borra. '
  'Toma el mismo lock que rrhh_resolver_evento() y lee el estado ADENTRO del lock.';


-- ── 3 · ANTI REPETIDAS, AL INSERTAR ────────────────────────────────────
-- POR QUE TRIGGER Y NO INDICE UNICO. Un indice unico parcial no sirve: «sigue
-- viva» depende de rrhh_evento_aprob y rrhh_evento_anulado, que son OTRAS
-- tablas, y el predicado de un indice solo puede mirar la fila propia. Para
-- permisos un indice parcial sobre `estado in ('pendiente','aprobado')` si
-- seria posible, pero se usa trigger en los dos para que la regla y el mensaje
-- vivan en un solo lugar.
--
-- NO ES RETROACTIVA, y es a proposito: un trigger `before insert` solo mira lo
-- que entra de ahora en adelante. Las filas que ya existen no se revisan — la
-- medicion dijo que no hay ninguna que chocara, pero igual: un constraint
-- retroactivo habria rechazado el pegado entero por datos viejos.
--
-- LO QUE NO CUENTA: rechazada, anulada y cancelada. Volver a pedir despues de un
-- rechazo o de una cancelacion SIGUE PERMITIDO, que es el caso legitimo que la
-- medicion encontro (las dos de Daniel del 19-20 nov).
create or replace function rrhh_evento_no_repetida() returns trigger
language plpgsql set search_path = public as $$
declare v_n int;
begin
  select count(*) into v_n
    from v_rrhh_evento_estado v
   where v.persona_id = new.persona_id
     and v.tipo       = new.tipo
     and v.fecha      = new.fecha
     and coalesce(v.dias, -1)  = coalesce(new.dias, -1)
     and coalesce(v.horas, -1) = coalesce(new.horas, -1)
     and v.estado in ('solicitado','aprobado');
  if v_n > 0 then
    raise exception 'Ya hay una solicitud repetida para esas fechas, y todavía está pendiente '
      'o aprobada. Si la anterior se rechazó o se canceló, podés pedir de nuevo.'
      using errcode = '23505';
  end if;
  return new;
end $$;

drop trigger if exists rrhh_evento_no_repetida_tg on rrhh_evento;
create trigger rrhh_evento_no_repetida_tg before insert on rrhh_evento
  for each row execute function rrhh_evento_no_repetida();

create or replace function rrhh_permiso_no_repetida() returns trigger
language plpgsql set search_path = public as $$
declare v_n int;
begin
  select count(*) into v_n
    from rrhh_permiso pm
   where pm.persona_id   = new.persona_id
     and pm.fecha_inicio = new.fecha_inicio
     and pm.fecha_fin    = new.fecha_fin
     and coalesce(pm.horas, -1) = coalesce(new.horas, -1)
     and pm.estado in ('pendiente','aprobado');
  if v_n > 0 then
    raise exception 'Ya hay un permiso repetido para esas fechas, y todavía está pendiente '
      'o aprobado. Si el anterior se rechazó o se canceló, podés pedir de nuevo.'
      using errcode = '23505';
  end if;
  return new;
end $$;

drop trigger if exists rrhh_permiso_no_repetida_tg on rrhh_permiso;
create trigger rrhh_permiso_no_repetida_tg before insert on rrhh_permiso
  for each row execute function rrhh_permiso_no_repetida();


-- ── 4 · GRANTS ──────────────────────────────────────────────────────────
-- `execute` se le da a PUBLIC por defecto, y en una security definer eso es
-- grave: cualquiera con la anon key la llamaria corriendo como el dueño. El
-- guardia de adentro igual lo frenaria (rrhh_mi_persona() da null para anon),
-- pero no se depende de una sola capa — es la leccion del 24-ago.
revoke all on function rrhh_cancelar_solicitud(text, bigint, text) from anon, public;
grant execute on function rrhh_cancelar_solicitud(text, bigint, text) to authenticated;

-- Los triggers no llevan grant: corren como parte del insert. Y las funciones de
-- trigger NO son definer a proposito — leen con los permisos de quien inserta,
-- que es exactamente el recorte que se quiere (cada quien ve lo suyo).
revoke all on function rrhh_evento_no_repetida()  from anon, public;
revoke all on function rrhh_permiso_no_repetida() from anon, public;


-- ── 5 · EL CANDADO ──────────────────────────────────────────────────────
do $candado$
declare
  v_def boolean; v_path text[]; v_src text;
  v_anon boolean; v_auth boolean;
  v_check int; v_tg int;
begin
  select p.prosecdef, p.proconfig, p.prosrc into v_def, v_path, v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='rrhh_cancelar_solicitud';

  v_anon := has_function_privilege('anon',
    'public.rrhh_cancelar_solicitud(text, bigint, text)','EXECUTE');
  v_auth := has_function_privilege('authenticated',
    'public.rrhh_cancelar_solicitud(text, bigint, text)','EXECUTE');

  select count(*) into v_check from pg_constraint
   where conname='rrhh_permiso_estado_ok'
     and pg_get_constraintdef(oid) like '%cancelado%';

  select count(*) into v_tg from pg_trigger
   where tgname in ('rrhh_evento_no_repetida_tg','rrhh_permiso_no_repetida_tg')
     and not tgisinternal;

  if v_def is null then
    raise exception 'CANDADO: rrhh_cancelar_solicitud no existe. NO SE APLICO NADA.';
  end if;
  if not v_def then
    raise exception 'CANDADO: la funcion NO quedo security definer, asi que no podria '
      'escribir (el empleado no tiene update sobre rrhh_permiso). NO SE APLICO NADA.';
  end if;
  -- EL GUARDIA SE BUSCA EN EL CUERPO. Una definer SIN el deja que cualquiera
  -- cancele la solicitud de cualquier otro, que es mucho peor que no tener
  -- cancelar.
  if position('rrhh_mi_persona' in v_src) = 0 then
    raise exception 'CANDADO: la funcion es security definer y NO llama a rrhh_mi_persona(). '
      'Asi cualquiera podria cancelar la solicitud de otro. NO SE APLICO NADA.';
  end if;
  -- Y EL LOCK, que es lo que resuelve la carrera aprobar/cancelar.
  if position('pg_advisory_xact_lock' in v_src) = 0 then
    raise exception 'CANDADO: la funcion no toma el lock, asi que una socia aprobando y el '
      'dueño cancelando podrian pisarse. NO SE APLICO NADA.';
  end if;
  if v_path is null or not (v_path @> array['search_path=public']) then
    raise exception 'CANDADO: falta `set search_path = public`. En una security definer eso '
      'deja que quien llama le cambie que rrhh_mi_persona() ejecuta. NO SE APLICO NADA.';
  end if;
  if v_anon then
    raise exception 'CANDADO: `anon` puede EJECUTAR la funcion. Es security definer y la anon '
      'key es PUBLICA. NO SE APLICO NADA.';
  end if;
  if not v_auth then
    raise exception 'CANDADO: `authenticated` no puede ejecutarla, asi que nadie podria '
      'cancelar. NO SE APLICO NADA.';
  end if;
  if v_check <> 1 then
    raise exception 'CANDADO: el CHECK de estado no acepta ''cancelado''. NO SE APLICO NADA.';
  end if;
  if v_tg <> 2 then
    raise exception 'CANDADO: hay % trigger(s) anti-repetidas en vez de 2. NO SE APLICO NADA.', v_tg;
  end if;

  raise notice 'CANDADO OK: definer con guardia de dueño y lock · search_path fijo · anon sin '
    'execute · CHECK con cancelado · 2 triggers';
end
$candado$;


-- ── 6 · LA FILA DE CONTROL ──────────────────────────────────────────────
-- Regla 🔴 de CLAUDE.md: un "Success" del editor no es evidencia de nada.
-- ESPERADO:  t · t · t · t · f · t · 1 · 2
select
  (select p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='rrhh_cancelar_solicitud')      as es_definer,
  (select p.proconfig @> array['search_path=public'] from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='rrhh_cancelar_solicitud')       as search_path_fijo,
  (select position('rrhh_mi_persona' in p.prosrc) > 0 from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='rrhh_cancelar_solicitud')       as guardia_dueno,
  (select position('pg_advisory_xact_lock' in p.prosrc) > 0 from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='rrhh_cancelar_solicitud')       as toma_el_lock,
  has_function_privilege('anon','public.rrhh_cancelar_solicitud(text, bigint, text)','EXECUTE')
                                                                           as anon_debe_ser_f,
  has_function_privilege('authenticated','public.rrhh_cancelar_solicitud(text, bigint, text)','EXECUTE')
                                                                           as auth_debe_ser_t,
  (select count(*) from pg_constraint where conname='rrhh_permiso_estado_ok'
    and pg_get_constraintdef(oid) like '%cancelado%')                      as check_con_cancelado,
  (select count(*) from pg_trigger where not tgisinternal
    and tgname in ('rrhh_evento_no_repetida_tg','rrhh_permiso_no_repetida_tg')) as triggers;

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  FIN DEL CUERPO DEL PEGADO · desde aca, las PRUEBAS                  ║
-- ╚══════════════════════════════════════════════════════════════════════╝

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
  -- POR ID, no solo el conteo: «una menos» no prueba que la que desaparecio sea
  -- LA QUE SE CANCELO. Podria haberse ido otra y el conteo daria igual.
  perform set_config('cc.a_e1_cal',
    (select count(*)::text from v_rrhh_calendario
      where fuente='vacacion' and ref_id = current_setting('cc.e1',true)::bigint), true);
  perform set_config('cc.a_e1_band',
    (select count(*)::text from v_rrhh_solicitud
      where id = current_setting('cc.e1',true)::bigint), true);
  perform set_config('cc.a_e1_saldo',
    (select count(*)::text from v_rrhh_evento
      where id = current_setting('cc.e1',true)::bigint), true);
  -- Los DIAS PENDIENTES que muestra «Mis vacaciones» (no son los tomados).
  perform set_config('cc.a_pend_dias',
    (select coalesce(sum(dias),0)::text from v_rrhh_solicitud
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
  perform set_config('cc.d_e1_cal',
    (select count(*)::text from v_rrhh_calendario
      where fuente='vacacion' and ref_id = current_setting('cc.e1',true)::bigint), true);
  perform set_config('cc.d_e1_band',
    (select count(*)::text from v_rrhh_solicitud
      where id = current_setting('cc.e1',true)::bigint), true);
  perform set_config('cc.d_e1_saldo',
    (select count(*)::text from v_rrhh_evento
      where id = current_setting('cc.e1',true)::bigint), true);
  perform set_config('cc.d_pend_dias',
    (select coalesce(sum(dias),0)::text from v_rrhh_solicitud
      where persona_id = current_setting('cc.pa',true)::bigint), true);
  -- ⚠️ EL VALOR LITERAL DE `anulada`. El default de la columna es FALSE y el
  -- comentario del esquema esta al reves, asi que una fila insertada sin nombrar
  -- la columna NO anularia nada EN SILENCIO. Esto comprueba que la funcion puso
  -- `true` explicito — no que «la funcion devolvio OK».
  perform set_config('cc.d_anulada',
    coalesce((select an.anulada::text from rrhh_evento_anulado an
               where an.evento_id = current_setting('cc.e1',true)::bigint
               order by an.creado_en desc limit 1), 'SIN FILA'), true);
  perform set_config('cc.d_anulada_n',
    (select count(*)::text from rrhh_evento_anulado an
      where an.evento_id = current_setting('cc.e1',true)::bigint), true);
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
-- ── LA TABLA ────────────────────────────────────────────────────────────
-- EL VEREDICTO VA SEGUNDO, no último, y no es cosmética: el aviso de Supabase
-- tapó el final de varias filas el 15-oct, incluida la 19, así que la columna
-- que dice si pasó o no quedaba fuera de vista. Lo que importa va a la
-- izquierda; el texto largo, a la derecha, donde se puede perder sin costo.
--
-- Y los textos se MUESTRAN cortos pero se COMPARAN completos: `left(...)` va
-- solo en la columna `obtenido`. Recortar antes de comparar habría debilitado
-- la aserción para que entre en la pantalla, que es al revés de lo que se quiere.
select t.orden,
       case when t.prueba like 'INFO%' then 'INFO'
            when t.obtenido like 'SIN PROBAR%' then 'SIN PROBAR'
            when t.ok then 'OK' else 'FALLA' end as veredicto,
       t.prueba, t.esperado, left(t.obtenido, 34) as obtenido
  from (
  select 1 as orden, 'dueño cancela su VACACION pendiente'::text as prueba,
         'anulado'::text as esperado,
         coalesce(current_setting('cc.r1',true),'SIN CAPTURAR') as obtenido,
         current_setting('cc.r1',true) = 'anulado' as ok
  union all
  select 2, 'dueño cancela su PERMISO pendiente', 'cancelado',
         coalesce(current_setting('cc.r2',true),'SIN CAPTURAR'),
         current_setting('cc.r2',true) = 'cancelado'
  union all
  select 3, 'resuelto_por = el correo del EMPLEADO',
         'zz-a@example.invalid',
         coalesce(nullif(current_setting('cc.r2_por',true),''),'VACIO'),
         current_setting('cc.r2_por',true) = 'zz-a@example.invalid'
  union all
  -- LA ANULACION, POR SU VALOR LITERAL. Es la asercion que distingue «la funcion
  -- devolvio OK» de «la base quedo como tiene que quedar».
  select 4, 'anulacion con anulada = TRUE explicito', 'true',
         coalesce(current_setting('cc.d_anulada',true),'SIN CAPTURAR'),
         current_setting('cc.d_anulada',true) = 'true'
  union all
  select 5, 'UNA sola fila de anulacion', '1',
         coalesce(current_setting('cc.d_anulada_n',true),'SIN CAPTURAR'),
         nullif(current_setting('cc.d_anulada_n',true),'')::numeric = 1
  union all
  -- ESA solicitud, POR SU ID, en cada vista: estaba (1) y ya no esta (0).
  select 6, 'ESA solicitud sale del CALENDARIO', '1 -> 0',
         coalesce(current_setting('cc.a_e1_cal',true),'?') || ' -> '
           || coalesce(current_setting('cc.d_e1_cal',true),'?'),
         nullif(current_setting('cc.a_e1_cal',true),'')::numeric = 1
           and nullif(current_setting('cc.d_e1_cal',true),'')::numeric = 0
  union all
  select 7, 'ESA solicitud sale de la BANDEJA', '1 -> 0',
         coalesce(current_setting('cc.a_e1_band',true),'?') || ' -> '
           || coalesce(current_setting('cc.d_e1_band',true),'?'),
         nullif(current_setting('cc.a_e1_band',true),'')::numeric = 1
           and nullif(current_setting('cc.d_e1_band',true),'')::numeric = 0
  union all
  -- EL SALDO. Lo que una PENDIENTE mueve en «Mis vacaciones» son los dias
  -- PENDIENTES, no los tomados: una pendiente nunca conto como tomada. Se miden
  -- las dos cosas, y de paso que nunca entro en v_rrhh_evento (los tomados).
  select 8, 'los DIAS PENDIENTES del saldo bajan 1',
         coalesce((nullif(current_setting('cc.a_pend_dias',true),'')::numeric - 1)::text,'?'),
         coalesce(current_setting('cc.d_pend_dias',true),'SIN DATO'),
         nullif(current_setting('cc.d_pend_dias',true),'')::numeric
           = nullif(current_setting('cc.a_pend_dias',true),'')::numeric - 1
  union all
  select 9, 'nunca entra en v_rrhh_evento (TOMADOS)', '0 -> 0',
         coalesce(current_setting('cc.a_e1_saldo',true),'?') || ' -> '
           || coalesce(current_setting('cc.d_e1_saldo',true),'?'),
         nullif(current_setting('cc.a_e1_saldo',true),'')::numeric = 0
           and nullif(current_setting('cc.d_e1_saldo',true),'')::numeric = 0
  union all
  select 10, 'los dias TOMADOS no se mueven',
         coalesce(nullif(current_setting('cc.a_tom',true),''),'?'),
         coalesce(nullif(current_setting('cc.d_tom',true),''),'SIN DATO'),
         nullif(current_setting('cc.d_tom',true),'')::numeric
           = nullif(current_setting('cc.a_tom',true),'')::numeric
  union all
  select 11, 'el estado de la cancelada es anulado', 'anulado',
         coalesce(nullif(current_setting('cc.d_e1',true),''),'SIN DATO'),
         current_setting('cc.d_e1',true) = 'anulado'
  union all
  select 12, 'OTRO empleado cancela la ajena: NO', 'RECHAZA 42501',
         coalesce(current_setting('cc.r4',true),'SIN CAPTURAR'),
         coalesce(current_setting('cc.r4',true),'') like 'RECHAZA 42501%'
  union all
  select 13, 'cancelar una APROBADA: NO, y lo dice', 'RECHAZA 55000',
         coalesce(current_setting('cc.r5a',true),'SIN CAPTURAR'),
         coalesce(current_setting('cc.r5a',true),'') like 'RECHAZA 55000%'
           and coalesce(current_setting('cc.r5a',true),'') like '%aprobado%'
  union all
  select 14, 'cancelar una RECHAZADA: NO', 'RECHAZA 55000',
         coalesce(current_setting('cc.r5b',true),'SIN CAPTURAR'),
         coalesce(current_setting('cc.r5b',true),'') like 'RECHAZA 55000%'
  union all
  select 15, 'cancelar una YA CANCELADA: NO',
         'RECHAZA 55000',
         coalesce(current_setting('cc.r5c',true),'SIN CAPTURAR'),
         coalesce(current_setting('cc.r5c',true),'') like 'RECHAZA 55000%'
  union all
  select 16, 'ANON cancela: NO', 'RECHAZA 42501',
         coalesce(current_setting('cc.r6',true),'SIN CAPTURAR'),
         coalesce(current_setting('cc.r6',true),'') like 'RECHAZA 42501%'
  union all
  select 17, 'la REPETIDA de una pendiente: NO', 'RECHAZA 23505',
         coalesce(current_setting('cc.r7a',true),'SIN CAPTURAR'),
         coalesce(current_setting('cc.r7a',true),'') like 'RECHAZA 23505%'
  union all
  select 18, 'pedir de nuevo tras cancelar: SI', 'ENTRO (correcto)',
         coalesce(current_setting('cc.r7b',true),'SIN CAPTURAR'),
         current_setting('cc.r7b',true) = 'ENTRO (correcto)'
  union all
  select 19, 'filas de Daniel en rrhh_evento: igual',
         case when coalesce(current_setting('cc.daniel',true),'')=''
              then 'SIN PROBAR' else coalesce(current_setting('cc.a_daniel_ev',true),'?') end,
         case when coalesce(current_setting('cc.daniel',true),'')=''
              then 'SIN PROBAR · no identifique a Daniel'
              else coalesce(current_setting('cc.d_daniel_ev',true),'SIN DATO') end,
         coalesce(current_setting('cc.d_daniel_ev',true),'x')
           = coalesce(current_setting('cc.a_daniel_ev',true),'y')
  union all
  select 20, 'filas de Daniel en rrhh_permiso: igual',
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
-- No tiene que quedar NADA, ni datos ni esquema:
--   select count(*) from acceso_usuario where nota = 'ensayo-cancelar';      -- 0
--   select count(*) from rrhh_persona  where creado_por = 'ensayo-cancelar'; -- 0
--   select count(*) from rrhh_evento   where creado_por = 'ensayo-cancelar'; -- 0
--   select count(*) from rrhh_permiso  where creado_por = 'ensayo-cancelar'; -- 0
--   select count(*) from pg_proc where proname = 'rrhh_cancelar_solicitud';  -- 0
--   select count(*) from pg_constraint where conname='rrhh_permiso_estado_ok'; -- 0
--   select count(*) from pg_trigger where tgname like 'rrhh_%_no_repetida_tg'; -- 0
