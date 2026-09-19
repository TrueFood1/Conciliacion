-- ════════════════════════════════════════════════════════════════════════
-- LA MARCA LA ESCRIBE CC · abrir el guardia del §3 a la firma `cc-sql`,
-- y sumarle `disponible` y `bloqueado` a los que el §2 ya acepta.
-- PROPUESTA 19-sep-2026.
--
-- ⚠️ NO PEGADO TODAVIA. Este encabezado NO dice "aplicado" hasta DESPUES de
--    correrlo y de haber mirado la verificacion del §2. Regla del 16-sep:
--    sobre un "Success" sin verificar se escribio que algo estaba aplicado, y
--    durante unos minutos el archivo y la bitacora afirmaban las dos algo falso.
--
-- ── DE DONDE SALE ───────────────────────────────────────────────────────
-- La pantalla de tickets tuvo, el 19-sep, un formulario que le preguntaba a
-- Andrea "¿el arreglo toca numeros?" y "¿escribe en la base?". Se saco entero
-- el mismo dia: **eso no se contesta mirando el ticket, se contesta abriendo
-- el codigo**. Es el trabajo de CC, no el de ella.
--   Andrea, 19-sep: "yo estoy bien con tener la lista, separada por modulos, y
--   yo le digo a CC que los revise y me muestre su diagnostico, y que el mismo
--   decida en que estatus quedan."
-- La marca pasa a ser un DATO MEDIDO que escribe quien puede medirlo. Y el
-- guardia del §3 no lo deja: rechaza toda escritura sin sesion.
--
-- ── 🔴 EL CANDADO DEL §3 SE ABRE A CONCIENCIA · 19-sep-2026 ─────────────
-- El §3 se escribio el 17-sep con este argumento, y hay que leerlo entero
-- antes de tocarlo:
--     "Triar es decidir, y decidir es de las socias. Ni siquiera por SQL
--      Editor: ahi no se sabe quien escribe, y el triaje es justamente un
--      juicio."
-- ESE ARGUMENTO ERA CORRECTO CUANDO LA MARCA LA PONIA UNA SOCIA. Hoy la
-- escribe CC despues de investigar, y medir no es juzgar. Por eso se abre.
-- ⚠️ PERO NO SE ABRE SOLO LO MEDIDO: `ticket_marca` es UNA fila con las cinco
--    columnas NOT NULL, asi que abrir el guardia abre tambien `prioridad` y
--    `bloquea_entrega`, que SI son juicio. Se acepta a sabiendas porque Andrea
--    delego las dos cosas el 19-sep — no porque no importe.
--
-- ── 🔴 SI ALGUN DIA LA PRIORIDAD VUELVE A SER DE ANDREA ─────────────────
-- EL CAMINO ES PARTIR LA TABLA, NO VOLVER A CERRAR ESTE GUARDIA A LO BRUTO.
-- Cerrarlo de nuevo dejaria a CC sin poder escribir lo medido, que es lo que
-- este cambio vino a habilitar, y el problema volveria al punto de partida.
-- Lo que corresponde es separar en dos eventos:
--     · lo MEDIDO      (toca_numeros, escribe_en_base) → lo escribe CC, firma
--       `cc-sql`, sin sesion;
--     · el JUICIO      (prioridad, bloquea_entrega)    → lo escribe una socia,
--       con sesion, como hoy.
-- Con `v_ticket` tomando DOS laterales, uno por evento. Es mas caro —tabla
-- nueva, guardia nuevo, cuatro vistas a reescribir— y por eso no se hace hoy:
-- seria construir una puerta para una pantalla que no existe, que es
-- exactamente como llego el `with check (true)` de `ent_anulacion_ins`.
--
-- ── ⚠️ LO QUE QUEDA PROTEGIENDO ES UNA CONVENCION, NO UN CANDADO ────────
-- Despues de esto, lo unico que separa a CC de cualquier otro es que la firma
-- empiece con `cc-sql`. **EL TRIGGER NO PUEDE VERIFICAR QUIEN ESCRIBE.**
-- Cualquiera con acceso al SQL Editor puede escribir esa cadena, y el editor
-- entra como `postgres`, que saltea la RLS de largo.
-- Que nadie lea esto como "ahora solo CC puede marcar". Lo correcto es: la
-- fila DICE de donde vino, y eso sirve para leer el historial — no para
-- impedir nada. Quien tiene el SQL Editor ya puede hacer cualquier cosa con la
-- base, y agregarle un candado ahi seria teatro.
-- La proteccion de verdad, la de la APP, no se toca: la RLS sigue exigiendo
-- `acceso_es_socia()` para escribir en `ticket_marca` y `ticket_estado`.
--
-- ── EL RECORTE DEL §2, Y POR QUE NO SE ABRE ENTERO ──────────────────────
-- Decision de Andrea, 19-sep: CC decide el estado DEL TRABAJO. CERRAR no.
--     se abre  →  disponible · bloqueado   (mas en_curso y en_validacion,
--                                           que el §2 ya aceptaba)
--     NO se abre → cerrado · pospuesto · descartado
-- "Cerrar es decir «esto ya esta», y sigue siendo de ella." Abrirlo seria
-- poder cerrar un ticket sin que Andrea lo vea.
-- 🔴 Y ESO DEJA UN FLUJO SIN PANTALLA, dicho de frente: hoy `index.html` no
--    escribe `ticket_estado` en ninguna linea (medido el 19-sep: cero
--    apariciones). O sea que `cerrado`, `pospuesto` y `descartado` no los
--    puede poner NADIE hasta que existan los tres botones de la lista. Van en
--    la misma pasada que este pegado, pero son cosas separadas: si los botones
--    no estuvieran, los tickets se acumularian en "En validacion".
--
-- ── DE PASO, LA PALABRA ─────────────────────────────────────────────────
-- Los dos guardias decian "triar" en sus mensajes de error, y esos textos
-- LLEGAN A LA PANTALLA. Andrea pregunto el 19-sep que significaba. Como estas
-- dos funciones se reescriben igual, los mensajes pasan a decir "revisar".
-- El estado sigue llamandose 'sin_triar' y la tabla `ticket_marca`: cambiar
-- eso es otro pegado y no lo vale.
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- §0 · EL TERRENO · SOLO LECTURA. Correr ENTERO antes de pegar nada.
-- ════════════════════════════════════════════════════════════════════════
-- MEDIDO EL 19-sep-2026 al escribir esto: son los valores que tienen que
-- salir hoy, salvo que algo haya cambiado en el medio.

-- 0a · LAS DOS FUNCIONES, COMO ESTAN AHORA. Es el "antes" contra el que se
--      compara el "despues".
--      MEDIDO 19-sep:
--        ticket_estado_guard · largo 1901 · acepta_cc t · nombra_disponible t
--        ticket_marca_guard  · largo  950 · acepta_cc f · nombra_disponible f
--      ⚠️ `ticket_estado_guard` YA dice 'cc-sql' y YA nombra 'disponible' —
--         pero lo nombra en el MENSAJE DE ERROR, no en la lista de permitidos.
--         Por eso el control del §2 no mira si la palabra aparece: mira la
--         lista entera, textual. Una palabra suelta no prueba nada.
select proname,
       length(prosrc)                        as largo,
       (position('cc-sql' in prosrc) > 0)    as acepta_cc,
       (position('disponible' in prosrc) > 0) as nombra_disponible,
       md5(prosrc)                           as huella
  from pg_proc
 where proname in ('ticket_marca_guard','ticket_estado_guard')
 order by proname;

-- 0b · LA LISTA DE ESTADOS QUE EL §2 ACEPTA HOY SIN SESION, textual.
--      MEDIDO 19-sep: la linea existe con los DOS de siempre.
select (position('not in (''en_curso'',''en_validacion'')' in prosrc) > 0)
         as acepta_solo_los_dos_viejos
  from pg_proc where proname = 'ticket_estado_guard';

-- 0c · QUE HAY ESCRITO. Si hubiera filas, este cambio deja de ser "abrir una
--      puerta" y pasa a ser "cambiar las reglas con datos adentro".
--      MEDIDO 19-sep: tickets 2 · marcas 0 · estados 0
select (select count(*) from ticket)        as tickets,
       (select count(*) from ticket_marca)  as marcas,
       (select count(*) from ticket_estado) as estados;

-- 0d · LOS TRIGGERS, QUE TIENEN QUE SOBREVIVIR. `create or replace function`
--      no los toca, pero si el nombre o la firma cambiaran, se caerian.
--      MEDIDO 19-sep: 1 y 1.
select (select count(*) from pg_trigger
         where tgrelid='public.ticket_marca'::regclass  and not tgisinternal) as trg_marca,
       (select count(*) from pg_trigger
         where tgrelid='public.ticket_estado'::regclass and not tgisinternal) as trg_estado;


-- ════════════════════════════════════════════════════════════════════════
-- §1 · EL GUARDIA DE LA MARCA · abrirlo a `cc-sql`
-- ════════════════════════════════════════════════════════════════════════
-- ⚠️ SELECCIONA DESDE `begin;` HASTA `commit;` Y NADA MAS.
begin;

create or replace function ticket_marca_guard()
returns trigger language plpgsql as $guard$
declare quien text; socia boolean;
begin
  if not exists (select 1 from ticket t where t.id = new.ticket_id) then
    raise exception 'no existe el ticket %', new.ticket_id;
  end if;
  quien := nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email';

  if quien is null then
    -- ── EL CAMINO DE CC · por el SQL Editor · ABIERTO EL 19-sep-2026 ───
    -- Hasta hoy esto rebotaba SIEMPRE, con el argumento de que revisar es un
    -- juicio y desde aca no se sabe quien lo toma. Cambio el reparto: la marca
    -- es un DATO MEDIDO —hay que abrir el codigo para contestarla— y la
    -- escribe CC. Medir no es juzgar.
    -- ⚠️ ESTO NO ES UN CANDADO. El trigger NO puede verificar quien es CC:
    --    solo comprueba que la firma empiece con `cc-sql`, y cualquiera con el
    --    SQL Editor puede escribirla. Es una CONVENCION para que la fila diga
    --    de donde vino. La proteccion real es la RLS, que cubre la APP y no se
    --    toca: por ahi sigue exigiendo `acceso_es_socia()`.
    -- ⚠️ Y abre tambien `prioridad` y `bloquea_entrega`, que son juicio, porque
    --    viven en la MISMA fila. A sabiendas. Si eso se quiere separar, el
    --    camino esta escrito en el encabezado: partir la tabla, NO volver a
    --    cerrar este guardia.
    if new.creado_por not like 'cc-sql%' then
      raise exception 'una revision sin sesion de Supabase (SQL Editor) tiene que firmar '
        'creado_por empezando con "cc-sql". Vino: %', new.creado_por;
    end if;
    return new;
  end if;

  -- ── EL CAMINO DE LA APP · con sesion · NO CAMBIA ──────────────────────
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

-- ── EL CONTROL · ADENTRO Y ANTES DEL COMMIT ─────────────────────────
-- O se ven estos valores, o esto no llego. "Success. No rows returned" no
-- prueba nada: un tramo de puro comentario devuelve exactamente eso.
-- ESPERADO: funcion 1 · acepta_cc_sql t · dice_triar f · trigger 1
select
  (select count(*) from pg_proc where proname='ticket_marca_guard')          as funcion,
  (select position('cc-sql' in prosrc) > 0
     from pg_proc where proname='ticket_marca_guard')                        as acepta_cc_sql,
  (select position('triar' in prosrc) > 0
     from pg_proc where proname='ticket_marca_guard')                        as dice_triar,
  (select count(*) from pg_trigger
    where tgrelid='public.ticket_marca'::regclass and not tgisinternal)      as trigger;

commit;


-- ════════════════════════════════════════════════════════════════════════
-- §2 · EL GUARDIA DEL ESTADO · sumarle `disponible` y `bloqueado`
-- ════════════════════════════════════════════════════════════════════════
begin;

create or replace function ticket_estado_guard()
returns trigger language plpgsql as $guard$
declare
  quien text;
  socia boolean;
begin
  if not exists (select 1 from ticket t where t.id = new.ticket_id) then
    raise exception 'no existe el ticket %', new.ticket_id;
  end if;

  quien := nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email';

  if quien is null then
    -- ── EL CAMINO DE CC · por el SQL Editor ───────────────────────────
    -- ✅ APROBADO 10-sep y confirmado el 17-sep: CC no escribe en Supabase.
    -- Escribe el INSERT y Andrea lo pega. `pg_lector.py` sigue siendo SOLO
    -- LECTURA con sus dos candados, y `pg_pruebas.py` solo hace rollback.
    if new.creado_por not like 'cc-sql%' then
      raise exception 'un cambio de estado sin sesion de Supabase (SQL Editor) tiene que '
        'firmar creado_por empezando con "cc-sql". Vino: %', new.creado_por;
    end if;
    -- 🔴 LOS CUATRO QUE PUEDE PONER CC, Y LOS TRES QUE NO · 19-sep-2026.
    -- Se sumaron `disponible` y `bloqueado` a los dos que ya estaban: son el
    -- resultado de revisar, y revisar es de CC desde hoy.
    -- CERRAR NO SE ABRE, Y NO ES UN OLVIDO: 'cerrado', 'pospuesto' y
    -- 'descartado' dicen "esto ya esta" o "esto no se hace", y eso sigue
    -- siendo de las socias. Abrirlo seria poder cerrar un ticket sin que
    -- Andrea lo vea.
    if new.estado not in ('en_curso','en_validacion','disponible','bloqueado') then
      raise exception 'desde el SQL Editor se puede poner en_curso, en_validacion, '
        'disponible o bloqueado. Cerrar, posponer y descartar es de las socias, y desde '
        'aca no se sabe cual socia es. Vino: %', new.estado;
    end if;
    return new;
  end if;

  -- ── EL CAMINO DE LA APP · con sesion · NO CAMBIA ──────────────────────
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

-- ── EL CONTROL · ADENTRO Y ANTES DEL COMMIT ─────────────────────────
-- ESPERADO: funcion 1 · lista_nueva t · lista_vieja f · trigger 1
-- ⚠️ Se mira LA LISTA ENTERA, textual, y no si aparece la palabra
--    'disponible': esa palabra ya estaba en el mensaje de error de antes. Un
--    contador que se conforma con la palabra habria dado verde sin el cambio.
select
  (select count(*) from pg_proc where proname='ticket_estado_guard')         as funcion,
  (select position('not in (''en_curso'',''en_validacion'',''disponible'',''bloqueado'')'
            in prosrc) > 0
     from pg_proc where proname='ticket_estado_guard')                       as lista_nueva,
  (select position('not in (''en_curso'',''en_validacion'')' in prosrc) > 0
     from pg_proc where proname='ticket_estado_guard')                       as lista_vieja,
  (select count(*) from pg_trigger
    where tgrelid='public.ticket_estado'::regclass and not tgisinternal)     as trigger;

commit;


-- ════════════════════════════════════════════════════════════════════════
-- §3 · DESPUES · VERIFICAR. Solo lectura.
-- ════════════════════════════════════════════════════════════════════════

-- V1 · Las dos funciones, y que ninguna diga ya "triar".
--      ESPERADO: las dos con dice_triar en `f`.
select proname, length(prosrc) as largo,
       (position('triar' in prosrc) > 0) as dice_triar,
       (position('cc-sql' in prosrc) > 0) as acepta_cc
  from pg_proc
 where proname in ('ticket_marca_guard','ticket_estado_guard')
 order by proname;

-- V2 · Los dos triggers, intactos. ESPERADO: 1 y 1.
select (select count(*) from pg_trigger
         where tgrelid='public.ticket_marca'::regclass  and not tgisinternal) as trg_marca,
       (select count(*) from pg_trigger
         where tgrelid='public.ticket_estado'::regclass and not tgisinternal) as trg_estado;

-- V3 · La RLS de la APP, que NO se toco. ESPERADO: las dos en
--      `acceso_es_socia()`. Si alguna dijera `true`, algo mas se movio.
select tablename, policyname, cmd, with_check
  from pg_policies
 where schemaname='public' and policyname in ('ticket_marca_ins','ticket_estado_ins')
 order by policyname;

-- V4 · 🔴 LO QUE ESTE ARCHIVO NO PUEDE PROBAR SOLO.
--      Todo lo de arriba lee el CATALOGO: dice que la funcion cambio, no que
--      el guardia deje pasar lo que tiene que dejar y rechace lo que no. Eso
--      se ejercita con `pg_pruebas.py`, carril B, y hay que correrlo:
--        · firma `cc-sql…` sin sesion → la marca ENTRA
--        · firma cualquier otra sin sesion → REBOTA
--        · sin sesion, estado 'disponible' y 'bloqueado' → ENTRAN
--        · sin sesion, estado 'cerrado' → REBOTA (es de las socias)
--        · con sesion de socia, todo sigue como antes
--      Sin esa corrida, "V1 en verde" es un catalogo leido — el error del
--      16-sep.
