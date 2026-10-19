-- SOLO SE PEGA DESPUES DEL ENSAYO · PERSONAL_CANCELAR_SOLICITUD.sql
-- ════════════════════════════════════════════════════════════════════════
-- MODULO PERSONAL · CANCELAR LO PROPIO + ANTI REPETIDAS   (PEGADO 9)
-- Preparado el 15-oct-2026. ✅ APLICADO EN PRODUCCION · verificado el 19-oct-2026.
--
-- COMO SE VERIFICO: con la consulta de solo lectura que esta mas abajo en este
-- mismo encabezado. Dio 1 · 1 · 2 — la funcion existe, el CHECK de `estado` ya
-- acepta 'cancelado', y los dos triggers anti repetidas estan puestos. O sea:
-- aplicado y completo, no a medias.
--
-- ⚠️ 19-oct-2026 · Y LA MARCA ANTERIOR ESTABA MAL. Decia «NO SE CORRIO», y lo
-- decia porque yo la escribi el 15-oct y nunca la volvi a tocar. Durante cuatro
-- dias este archivo afirmo algo falso sobre produccion, y de el dependia si se
-- podia construir el boton «Cancelar». La leccion no es «actualizar las marcas»:
-- es que una marca escrita a mano NO ES EVIDENCIA, y que lo unico que sirve es
-- la consulta. Por eso la consulta se queda aca y la marca la cita.
--
-- ⚠️ NO VOLVER A PEGAR ESTE ARCHIVO sin leer antes la nota del final sobre
-- correrlo dos veces. Es seguro —rehace el CHECK identico— pero toma un candado
-- exclusivo sobre rrhh_permiso y no hace falta.
--
-- Lo que sigue es la nota de cuando no se sabia, que se deja porque explica
-- contra que se verifico:
-- ⚠️ 19-oct-2026 · CORRECCION DE ESTA MARCA. Hasta hoy esta linea decia «NO SE
-- CORRIO» a secas, y eso era una AFIRMACION QUE NADIE VERIFICO. La escribi yo el
-- 15-oct, cuando era cierta, y no se volvio a tocar en cuatro dias de trabajo
-- sobre este modulo. Una marca que no se actualiza deja de ser informacion y pasa
-- a ser una suposicion con cara de dato — y de este archivo depende si el boton
-- «Cancelar» de «Mis solicitudes» se puede construir o no.
--
-- LO QUE SE SABE, Y SOBRE QUE:
--   · NO CONSTA que se haya aplicado: en el registro de trabajo no hay ninguna
--     corrida reportada, y la pantalla no tiene ni una llamada a
--     `rrhh_cancelar_solicitud` (verificado en index.html el 19-oct: cero).
--   · TAMPOCO ESTA VERIFICADO CONTRA LA BASE. Aca no hay credenciales de
--     PostgreSQL (no existe `herramientas/conexion_db.env`), y la anon key no
--     sirve: no puede leer nada de `rrhh_` y el esquema de PostgREST devuelve 401.
--     Asi que esta marca NO es evidencia del estado de produccion.
--   · Y no hay señal indirecta: el ensayo de la formula corrio en produccion el
--     16-oct y paso 35 de 35, pero ninguna de sus pruebas toca el CHECK de
--     `estado` ni los dos triggers de este pegado, asi que no delata nada.
--
-- COMO SE RESUELVE EN TRES SEGUNDOS, de solo lectura, en el SQL Editor:
--   select (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--            where n.nspname='public' and p.proname='rrhh_cancelar_solicitud')     as funcion,
--          (select count(*) from pg_constraint
--            where conname='rrhh_permiso_estado_ok'
--              and pg_get_constraintdef(oid) like '%cancelado%')                   as check_nuevo,
--          (select count(*) from pg_trigger where not tgisinternal
--            and tgname in ('rrhh_evento_no_repetida_tg','rrhh_permiso_no_repetida_tg')) as triggers;
--   -- 0 · 0 · 0  => NO esta aplicado, se puede pegar este archivo tal cual.
--   -- 1 · 1 · 2  => YA esta aplicado; NO volver a pegarlo sin leer la nota de
--   --              abajo sobre correrlo dos veces (es seguro, pero conviene saberlo).
--   -- cualquier otra combinacion => esta a medias: avisar antes de tocar nada.
-- Va DESPUES de PERSONAL_ARREGLO_RESOLVER.sql (pegado 8), aplicado. No toca
-- ninguno de los .sql ya pegados.
--
-- MEDIDO ANTES DE ESCRIBIR ESTO (MEDICION_REPETIDAS.sql, 15-oct): 0 grupos que
-- la proteccion rechazaria en rrhh_evento y 0 en rrhh_permiso, 1 grupo legitimo
-- (las dos de Daniel del 19-20 nov: una rechazada y una aprobada), 5 filas vivas
-- en rrhh_evento y 0 en rrhh_permiso. O sea: la proteccion entra sin limpiar
-- nada, y el grupo legitimo es la prueba de que la regla tiene que mirar el
-- ESTADO y no solo las fechas.
--
-- QUE AGREGA
--   · rrhh_permiso.estado acepta 'cancelado' (CHECK reemplazado).
--   · rrhh_cancelar_solicitud(p_tipo, p_id, p_motivo) — security definer,
--     search_path fijo, cerrada a anon, con el guardia del DUEÑO adentro.
--   · dos triggers `before insert` contra solicitudes repetidas.
--
-- ⚠️ EL COMENTARIO DE `rrhh_evento_anulado.anulada` ESTA AL REVES EN EL ESQUEMA
-- APLICADO, y conviene saberlo antes de leer esta funcion. Dice «deshacer la
-- anulación: otra fila con true», pero `v_rrhh_evento_estado` hace
-- `case when coalesce(an.anulada,false) then 'anulado'`: o sea que TRUE ES
-- ANULADO. Manda la vista, que es la que calcula el estado y la que filtra el
-- calendario. Peor todavia: el DEFAULT es `false`, asi que una fila insertada
-- sin nombrar la columna NO anula nada, EN SILENCIO. Por eso la funcion pone el
-- valor explicito y nunca se apoya en el default. El comentario no se corrige
-- aca —no se tocan los .sql pegados— pero queda dicho.
--
-- ⚠️ CANCELAR NO BORRA NADA. Una vacacion cancelada deja su fila en
-- rrhh_evento y una fila nueva en rrhh_evento_anulado; un permiso cancelado
-- cambia de estado y conserva todo. El historial sigue contando lo que paso,
-- que es la regla de todo el modulo.
-- ════════════════════════════════════════════════════════════════════════

begin;

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

commit;


-- ════════════════════════════════════════════════════════════════════════
-- DESPUES DEL COMMIT
-- ════════════════════════════════════════════════════════════════════════
--   1. PRUEBAS_CANCELAR.sql — los 8 escenarios con ROLLBACK. Es lo unico que
--      prueba que el dueño SI puede y que los demas NO.
--   2. esquema_check.py y sonda_columnas.py --nuevas: no agregan objetos, asi
--      que no deberian moverse. Que no se muevan es el resultado correcto.
--   3. Y lo que ningun script da: que las dos filas de Daniel del 19-20 nov
--      sigan como estaban. La proteccion NO es retroactiva, pero conviene
--      mirarlo con MEDICION_REPETIDAS.sql, que ahora tiene que seguir dando
--      0 grupos a rechazar y 1 legitimo.
