-- ════════════════════════════════════════════════════════════════════════
-- EL AMBITO · separar "de Truefie" de "pendiente mio"
-- PREPARADO 21-sep-2026. Diseno aprobado por Andrea, ver TICKETS_LISTA_UNICA.md
--
-- ✅ APLICADO el 21-sep-2026, por Andrea. Los siete cambios esperados, y los
--    cinco que no debian moverse, quietos:
--      col_ambito 0->1 · chk_ambito 0->1 · vista_ambito 0->1
--      e_linea_propio f->t · m_linea_propio f->t
--      e_huella 124d637a -> 64b47d7f · m_huella 5d77e077 -> bfca3ad2
--      tickets 3 · marcas 0 · estados 0 · trg 1 y 1   (sin moverse)
--
--    VERIFICADO DESDE AFUERA con pg_lector, por el CUERPO ENTERO: el md5 del
--    `prosrc` de las dos funciones vivas es identico al que dice este archivo.
--    Ademas: la columna es `text NOT NULL default 'truefie'`, el CHECK acepta
--    los dos valores y nada mas, `v_ticket` expone `ambito`, **sigue con
--    `security_invoker=true`** (no se le cambio el comportamiento) y sigue sin
--    un solo grant para `anon`. Los 3 tickets quedaron en 'truefie'.
--
--    EJERCITADO CONTRA EL ESTADO DEFINITIVO, en rollback, los cinco lados:
--      cc-sql mueve uno de TRUEFIE   -> ENTRA        (id 35)
--      cc-sql mueve uno PROPIO       -> P0001 "los pendientes propios los
--                                       mueve Andrea desde la pantalla"
--      cc-sql MARCA uno PROPIO       -> P0001 "aca no hay codigo"
--      socia  mueve uno PROPIO       -> ENTRA        (id 37)
--      equipo mueve uno PROPIO       -> P0001 "es de un perfil socias"
--
-- ── QUE HACE, Y POR QUE UNA COLUMNA Y NO `modulo='mio'` ─────────────────
-- `modulo` contesta "que parte de Truefie"; `ambito` contesta "es Truefie".
-- Son dos ejes. Metiendo "mio" adentro de `modulo`, "Sin modulo" y "Mis
-- pendientes" quedan HERMANOS en la misma lista — que es exactamente lo que
-- este cambio viene a evitar. Es la misma forma que el §13 ya resolvio para
-- `encargo`: el tipo dice QUE es, el estado dice DONDE esta, y no se mezclan.
--
-- ── 🔴 LA LINEA NUEVA DE LOS DOS GUARDIAS ───────────────────────────────
-- El 21-sep se le abrio a `cc-sql` poner `disponible` y `bloqueado`, porque
-- son el resultado de REVISAR y revisar es de CC. Un pendiente PROPIO no se
-- revisa abriendo codigo: no hay codigo que abrir. Asi que la apertura no
-- corresponde ahi, y se cierra ANTES de que exista el primer ticket propio.
-- La linea va PRIMERA en la rama sin sesion, antes de la firma y de la lista
-- de estados, para que el motivo del rechazo sea el de verdad y no el de al
-- lado.
--
-- ── ENSAYADO EN ROLLBACK CONTRA PRODUCCION, 21-sep · LOS CUATRO LADOS ───
--   cc-sql mueve uno de TRUEFIE  -> ENTRA           (id 31)
--   cc-sql mueve uno PROPIO      -> P0001 "los pendientes propios los mueve
--                                   Andrea desde la pantalla, no cc-sql"
--   socia  mueve uno PROPIO      -> ENTRA           (id 33)
--   equipo mueve uno PROPIO      -> P0001 "es de un perfil socias"
--   Los cuatro hacian falta: con solo los dos primeros, un guardia que
--   rechazara a todos tambien habria dado "verde".
--
-- ── LA VISTA ────────────────────────────────────────────────────────────
-- ⚠️ `v_ticket` NO se reescribio de memoria: se capturo con
--    `pg_get_viewdef('v_ticket', true)` y se le agrego `t.ambito` AL FINAL de
--    la lista de columnas, que es lo unico que `create or replace view`
--    permite sin dropear. Es la regla del §25.
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- §0 · EL TERRENO · SOLO LECTURA · TODO EN UNA SOLA FILA
--
-- El SQL Editor muestra SOLO el resultado de la ULTIMA sentencia, asi que
-- todo va junto en una fila.  No escribe nada: es un solo `select`.
--
-- ── ESPERADO, medido contra produccion el 21-sep-2026 ───────────────────
--   col_ambito       0    ← 🔴 si ya diera 1, EL CAMBIO YA ESTA APLICADO
--   chk_ambito       0
--   vista_ambito     0
--   e_linea_propio   f    el guardia del estado todavia no la trae
--   m_linea_propio   f    el de la marca tampoco
--   e_huella   124d637a   las huellas de HOY, para ver que cambien
--   m_huella   5d77e077
--   tickets          3    marcas 0 · estados 0
--   trg_marca 1 · trg_estado 1
-- ════════════════════════════════════════════════════════════════════════
select
  (select count(*) from information_schema.columns
    where table_name='ticket' and column_name='ambito')                    as col_ambito,
  (select count(*) from pg_constraint
    where conrelid='ticket'::regclass and conname='ticket_ambito_ok')      as chk_ambito,
  (select count(*) from information_schema.columns
    where table_name='v_ticket' and column_name='ambito')                  as vista_ambito,
  (select position('los pendientes propios los mueve Andrea' in prosrc)>0
     from pg_proc where proname='ticket_estado_guard')                     as e_linea_propio,
  (select position('un pendiente propio no lo marca cc-sql' in prosrc)>0
     from pg_proc where proname='ticket_marca_guard')                      as m_linea_propio,
  (select left(md5(prosrc),8) from pg_proc where proname='ticket_estado_guard') as e_huella,
  (select left(md5(prosrc),8) from pg_proc where proname='ticket_marca_guard')  as m_huella,
  (select count(*) from ticket)        as tickets,
  (select count(*) from ticket_marca)  as marcas,
  (select count(*) from ticket_estado) as estados,
  (select count(*) from pg_trigger where tgrelid='public.ticket_marca'::regclass  and not tgisinternal) as trg_marca,
  (select count(*) from pg_trigger where tgrelid='public.ticket_estado'::regclass and not tgisinternal) as trg_estado;


-- ════════════════════════════════════════════════════════════════════════
-- §1 · EL CAMBIO · listo para correr, con candado y commit
--
-- ⚠️ SI EL CANDADO SALTA, LA TRANSACCION QUEDA ABIERTA Y ABORTADA: nada se
--    aplico, pero hay que cerrarla con `rollback;`.
-- ════════════════════════════════════════════════════════════════════════
begin;

-- ── 1 · LA COLUMNA ────────────────────────────────────────────────────
-- `not null default 'truefie'`: las filas de hoy son todas de Truefie, asi
-- que el default las cubre sin migrar nada. El CHECK cierra el dominio a dos
-- valores: un tercero tendria que decidirse, no aparecer por escritura suelta.
alter table ticket
  add column if not exists ambito text not null default 'truefie';

alter table ticket drop constraint if exists ticket_ambito_ok;
alter table ticket
  add constraint ticket_ambito_ok check (ambito in ('truefie','propio'));

-- ── 2 · EL GUARDIA DEL ESTADO · que cc-sql no toque los propios ───────
-- 🔴 LA LINEA NUEVA, Y POR QUE. El 21-sep se le abrio a `cc-sql` poner
-- `disponible` y `bloqueado`, porque son el resultado de REVISAR y revisar es
-- de CC. Un pendiente PROPIO de Andrea no se revisa abriendo codigo: no hay
-- codigo que abrir. Asi que ahi la apertura no corresponde, y se cierra antes
-- de que exista el primer ticket propio.
create or replace function ticket_estado_guard()
returns trigger language plpgsql as $guard$
declare quien text; socia boolean; amb text;
begin
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
$guard$;

-- ── 3 · EL GUARDIA DE LA MARCA · lo mismo ─────────────────────────────
-- La marca es "que midio CC al abrir el codigo". En un pendiente propio no hay
-- codigo, asi que no hay marca que escribir sin sesion.
create or replace function ticket_marca_guard()
returns trigger language plpgsql as $guard$
declare quien text; socia boolean; amb text;
begin
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
$guard$;

-- ── 4 · LA VISTA · que exponga `ambito` ───────────────────────────────
-- ⚠️ La definicion NO se reescribio de memoria: se capturo con
--    `pg_get_viewdef('v_ticket', true)` el 21-sep y se le agrego `t.ambito`
--    AL FINAL de la lista de columnas, que es lo unico que
--    `create or replace view` permite sin dropear. Es la regla del §25.
create or replace view v_ticket with (security_invoker = true) as
 SELECT t.id,
    t.descripcion,
    t.tipo,
    t.build,
    t.doc_modificado,
    t.vista,
    t.miga,
    t.modulo,
    t.sobre,
    t.agente,
    t.standalone,
    t.viewport,
    t.tz_offset_min,
    t.tz_nombre,
    t.creado_en,
    t.creado_por,
    COALESCE(e.estado, 'sin_triar'::text) AS estado,
    e.nota AS ultima_nota,
    e.creado_en AS estado_en,
    e.creado_por AS estado_por,
    e.build_arreglo,
    e.bloquea_ticket_id,
    e.espera,
    COALESCE(des.recien_desbloqueado, false) AS recien_desbloqueado,
    des.estado_anterior,
    m.toca_numeros,
    m.escribe_en_base,
    m.toca_numeros IS NOT NULL AND NOT m.toca_numeros AND NOT m.escribe_en_base AS agente_puede,
    m.prioridad,
    m.bloquea_entrega,
    m.razon AS marca_razon,
    m.creado_por AS marca_por,
    d_esp.texto AS que_se_espera,
    d_cri.texto AS criterio_terminado,
    COALESCE(f.estado_foto, 'sin_foto'::text) AS estado_foto,
    COALESCE(f.fotos, 0::bigint) AS fotos,
    f.ultimo_error AS foto_error,
    t.ambito
   FROM ticket t
     LEFT JOIN LATERAL ( SELECT x.estado,
            x.nota,
            x.creado_en,
            x.creado_por,
            x.build_arreglo,
            x.bloquea_ticket_id,
            x.espera
           FROM ticket_estado x
          WHERE x.ticket_id = t.id
          ORDER BY x.creado_en DESC
         LIMIT 1) e ON true
     LEFT JOIN v_ticket_desbloqueo des ON des.ticket_id = t.id
     LEFT JOIN LATERAL ( SELECT x.toca_numeros,
            x.escribe_en_base,
            x.prioridad,
            x.bloquea_entrega,
            x.razon,
            x.creado_por
           FROM ticket_marca x
          WHERE x.ticket_id = t.id
          ORDER BY x.creado_en DESC
         LIMIT 1) m ON true
     LEFT JOIN LATERAL ( SELECT x.texto
           FROM ticket_detalle x
          WHERE x.ticket_id = t.id AND x.clase = 'espera'::text
          ORDER BY x.creado_en DESC
         LIMIT 1) d_esp ON true
     LEFT JOIN LATERAL ( SELECT x.texto
           FROM ticket_detalle x
          WHERE x.ticket_id = t.id AND x.clase = 'criterio'::text
          ORDER BY x.creado_en DESC
         LIMIT 1) d_cri ON true
     LEFT JOIN v_ticket_foto f ON f.ticket_id = t.id;

-- ── 5 · EL REVOKE · por si naciera algo ───────────────────────────────
-- Ninguno de los cuatro pasos crea un objeto nuevo: la columna cuelga de una
-- tabla que ya existe y `create or replace` conserva el objeto y sus grants.
-- Va igual, porque cuesta cero y porque la leccion del §0d es que el dia que
-- alguien agregue un `create table` aca, el revoke tiene que estar YA escrito
-- y no acordarse despues.
revoke truncate, references, trigger on all tables in schema public
  from anon, authenticated;
revoke all on v_ticket from anon;

-- ── EL CANDADO · adentro de la misma transaccion ────────────────────────
do $candado$
declare
  col int; chk int; vis int;
  e_propio boolean; m_propio boolean;
  n_truefie int; n_propio int;
begin
  select count(*) into col from information_schema.columns
   where table_name='ticket' and column_name='ambito';
  select count(*) into chk from pg_constraint
   where conrelid='ticket'::regclass and conname='ticket_ambito_ok';
  select count(*) into vis from information_schema.columns
   where table_name='v_ticket' and column_name='ambito';
  select position('los pendientes propios los mueve Andrea' in prosrc) > 0
    into e_propio from pg_proc where proname='ticket_estado_guard';
  select position('un pendiente propio no lo marca cc-sql' in prosrc) > 0
    into m_propio from pg_proc where proname='ticket_marca_guard';
  select count(*) filter (where ambito='truefie'), count(*) filter (where ambito='propio')
    into n_truefie, n_propio from ticket;

  if col <> 1 then raise exception 'CANDADO: falta la columna ambito. NO SE APLICO NADA.'; end if;
  if chk <> 1 then raise exception 'CANDADO: falta el CHECK ticket_ambito_ok. NO SE APLICO NADA.'; end if;
  if vis <> 1 then raise exception 'CANDADO: v_ticket no expone ambito. NO SE APLICO NADA.'; end if;
  if not e_propio then
    raise exception 'CANDADO: el guardia del ESTADO no trae la linea de los propios. NO SE APLICO NADA.';
  end if;
  if not m_propio then
    raise exception 'CANDADO: el guardia de la MARCA no trae la linea de los propios. NO SE APLICO NADA.';
  end if;
  -- 🔴 Las filas de hoy tienen que quedar TODAS en 'truefie'. Si alguna cayera
  --    en 'propio', el default no hizo lo que se cree y habria que mirarlo.
  if n_propio <> 0 then
    raise exception 'CANDADO: quedaron % filas en ambito propio y tenian que ser 0. NO SE APLICO NADA.', n_propio;
  end if;

  raise notice 'CANDADO OK: columna y CHECK si · v_ticket la expone · los dos guardias traen la linea · % filas en truefie, 0 en propio', n_truefie;
end
$candado$;

commit;


-- ════════════════════════════════════════════════════════════════════════
-- ESTA ES LA TABLA QUE VAS A VER. Ya con el commit hecho.
-- Misma forma que la del §0, para poner las dos filas al lado.
--
-- ESPERADO, lo que TIENE que haber cambiado:
--   col_ambito     0 -> 1        chk_ambito     0 -> 1
--   vista_ambito   0 -> 1
--   e_linea_propio f -> t        m_linea_propio f -> t
--   e_huella  124d637a -> otra   m_huella  5d77e077 -> otra
-- Y lo que NO tiene que moverse:
--   tickets 3 · marcas 0 · estados 0 · trg 1 y 1
-- ════════════════════════════════════════════════════════════════════════
select
  (select count(*) from information_schema.columns
    where table_name='ticket' and column_name='ambito')                    as col_ambito,
  (select count(*) from pg_constraint
    where conrelid='ticket'::regclass and conname='ticket_ambito_ok')      as chk_ambito,
  (select count(*) from information_schema.columns
    where table_name='v_ticket' and column_name='ambito')                  as vista_ambito,
  (select position('los pendientes propios los mueve Andrea' in prosrc)>0
     from pg_proc where proname='ticket_estado_guard')                     as e_linea_propio,
  (select position('un pendiente propio no lo marca cc-sql' in prosrc)>0
     from pg_proc where proname='ticket_marca_guard')                      as m_linea_propio,
  (select left(md5(prosrc),8) from pg_proc where proname='ticket_estado_guard') as e_huella,
  (select left(md5(prosrc),8) from pg_proc where proname='ticket_marca_guard')  as m_huella,
  (select count(*) from ticket)        as tickets,
  (select count(*) from ticket_marca)  as marcas,
  (select count(*) from ticket_estado) as estados,
  (select count(*) from pg_trigger where tgrelid='public.ticket_marca'::regclass  and not tgisinternal) as trg_marca,
  (select count(*) from pg_trigger where tgrelid='public.ticket_estado'::regclass and not tgisinternal) as trg_estado;
