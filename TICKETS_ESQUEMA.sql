-- ════════════════════════════════════════════════════════════════════════
-- TICKETS · el canal de Daniel, y el lugar donde deja de perderse un hallazgo
-- PROPUESTA. NO PEGAR. Andrea aprueba antes.
--
-- ⚠️ REESCRITO EL 17-sep-2026. La version anterior (10-sep) esta viva en git.
--    Este encabezado NO se toca para decir "aplicado" hasta DESPUES de pegar y
--    de haber mirado la verificacion del §9. Es la regla del 16-sep.
--
-- ── LO QUE RESUELVE ─────────────────────────────────────────────────────
--   1. los hallazgos quedan enterrados en prosa dentro de los ESTADO_ACTUAL;
--   2. Daniel encuentra los problemas y su unico canal es Andrea. El 8-sep se
--      fue media mañana reconstruyendo que paso en una pantalla que nadie
--      fotografio a tiempo.
--
-- ── QUE CAMBIO EL 17-sep, Y POR DECISION DE QUIEN ───────────────────────
-- Las cinco son de Andrea, el 17-sep, despues de revisar la version del 10-sep:
--
--   1. ESTADOS · se mantienen los cuatro de adentro y cambian los NOMBRES de
--      pantalla. Ver el mapa en §2. "Visto" es el gesto que vacia la lista.
--   2. QUIEN VE · TODOS VEN TODOS. ⚠️ Esto NO es un cambio: es una correccion
--      que Andrea se hizo a si misma. Llego a pedir "cada uno ve los suyos" y
--      lo revirtio con su razon escrita: *un ticket no tiene nada privado, y el
--      duplicado si cuesta — si Daniel ve que alguien ya lo reporto, no lo
--      reporta dos veces*. Queda anotado para que nadie lo "arregle" despues.
--      La FOTO es otra cosa y sigue siendo mas estricta: ver §8.
--   3. QUIEN MUEVE EL ESTADO · SOLO SOCIAS, **y en la RLS, no en la pantalla**.
--      Es la leccion del 17-sep con `ent_anulacion_ins`: ese dia se midio que
--      la politica decia `with check (true)` mientras la pantalla decia "solo
--      socias". Una garantia de pantalla no es una garantia.
--   4. LA MARCA AUTOMATIZABLE ES UN EVENTO, NO UNA COLUMNA (§3). Daniel no
--      puede ponerla —no sabe si algo toca numeros, por eso lo reporta—, asi
--      que nace cuando Andrea mira el ticket. Si fuera columna de `ticket`,
--      el ticket dejaria de ser append-only.
--   5. EL BOTON NO VA JUNTO A "Salir". Medido: `#btnSalir` es position:fixed y
--      el encabezado de telefono le reserva 78px exactos. Un segundo boton ahi
--      se come la reserva y la miga empieza a cortarse — y el 17-sep Andrea
--      verifico EN EL APARATO que hoy no se corta. Ver la propuesta en §10.
--
-- ── EL TERRENO, MEDIDO EL 17-sep (no citado) ────────────────────────────
--   · `index.html` sigue en CERO `.upload(` y CERO `createSignedUrl` en b61.
--     Truefie nunca subio un archivo. Este modulo seria el estreno del codigo.
--   · PERO el terreno de Storage YA EXISTE: los buckets `justificantes` y
--     `aguinaldos` estan creados y son PRIVADOS (`public = f`, 10 MB).
--     ⚠️ Eso CONTESTA la pregunta que la version del 10-sep dejaba abierta y
--     que el ticket T6 pedia medir: el pegado de PERSONAL_STORAGE.sql SI se
--     corrio. Lo que nunca se estreno es el codigo, no el esquema.
--   · Cero tablas `ticket*` en la base: este archivo nunca se pego.
--   · `const BUILD = 'v 17 sep 2026 · b61'` (index.html:4028).
--   · `body[data-mod]` existe y se usa.
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- 1 · EL TICKET · lo que se escribe una vez y no se toca mas
-- ════════════════════════════════════════════════════════════════════════
-- Append-only como todo el sistema: el ticket no cambia nunca. Lo que cambia
-- es su ESTADO (§2) y su MARCA (§4), y eso son eventos aparte. Un `estado`
-- como columna obligaria a un UPDATE, y este proyecto no da grant de update en
-- ninguna tabla de datos.
create table if not exists ticket (
  id           bigint generated always as identity primary key,

  -- ── LO QUE ESCRIBE LA PERSONA · tres cosas y nada mas ────────────────
  descripcion  text not null,
  tipo         text not null,

  -- ⚠️ EL MINIMO BAJO DE 15 A 5 CARACTERES, por decision de Andrea el 17-sep.
  -- El reporte se hace con el problema en la mano y puede ser dictado: "no va"
  -- son 5 caracteres y es un reporte legitimo. El minimo NO esta para exigir
  -- calidad —la calidad la pone el contexto que el sistema captura solo, que
  -- es el punto entero del modulo— sino para frenar el toque accidental.
  -- El `coalesce` no es decorativo aunque la columna sea NOT NULL: es la misma
  -- forma que D3-bis caza en `ent_devolucion`, donde sin el la conjuncion queda
  -- NULL y Postgres DEJA PASAR la fila. Se escribe asi siempre, por costumbre.
  constraint ticket_descripcion_ok
    check (length(btrim(coalesce(descripcion,''))) >= 5),

  -- Los tres de la pantalla. Nombres de adentro estables, nombres de pantalla
  -- en el comentario: si mañana cambia el texto del boton, no se migra la base.
  --   no_funciona → "Algo no funciona"
  --   duda        → "Tengo una duda"
  --   idea        → "Se me ocurrió algo"
  constraint ticket_tipo_ok
    check (tipo in ('no_funciona','duda','idea')),

  -- ── LO QUE CAPTURA EL SISTEMA, SIN QUE NADIE ESCRIBA ─────────────────
  build            text not null,   -- la constante BUILD del index.html que corria
  doc_modificado   text,            -- document.lastModified — ver el comentario de abajo
  vista            text,            -- id del <div> visible (vDespachos, vConteoLote, …)
  miga             text,            -- el texto de la miga: 'Entregas · Sin factura'
  modulo           text,            -- body[data-mod]: entregas | finanzas | …
  sobre            text,            -- el modal encima, si habia (rpSheet, vHistorial, …)
  agente           text,            -- navigator.userAgent
  standalone       boolean,         -- abierto desde el icono de iOS, o desde Safari
  viewport         text,            -- '820x1180 @2' — para leer un reporte de layout

  -- ── LA HORA, CON LA ZONA DEL APARATO ─────────────────────────────────
  -- ⚠️ AGREGADO EL 17-sep. `creado_en` es timestamptz: guarda el INSTANTE, en
  -- UTC, y PIERDE la zona de quien reporto. Hoy casi no muerde porque Costa
  -- Rica es UTC−6 fijo y sin horario de verano. Pero el dia que el iPad tenga
  -- la zona mal —que es exactamente la clase de bug que un ticket vendria a
  -- reportar— el dato que lo probaria no estaria. Se guarda lo que dice el
  -- aparato, no lo que deberia decir.
  --   tz_offset_min: -(new Date()).getTimezoneOffset()  → -360 en Costa Rica
  --   tz_nombre    : Intl.DateTimeFormat().resolvedOptions().timeZone
  tz_offset_min    int,
  tz_nombre        text,

  creado_en    timestamptz not null default now(),
  creado_por   text not null        -- email de la sesion de Supabase
);
create index if not exists ticket_creado_idx on ticket (creado_en desc);
create index if not exists ticket_autor_idx  on ticket (lower(creado_por), creado_en desc);
create index if not exists ticket_modulo_idx on ticket (modulo, creado_en desc);

comment on table ticket is
  'Un hallazgo reportado por cualquiera del equipo. Append-only: el ticket no se '
  'edita. Su estado vive en ticket_estado y su marca en ticket_marca.';

-- ⚠️ `build` SOLO NO ALCANZA, y esto es el corazon del asunto.
-- Hoy un sello como 'b61' puede significar DOS cosas: lo que hay en main y lo
-- que hay en una rama sin publicar. Cuando la rama se publique, el sello NO
-- cambia necesariamente. O sea que un ticket que diga `build = 'v 17 sep 2026
-- · b61'` reproduce exactamente la ambigüedad que costo la media mañana del
-- 8-sep.
-- `doc_modificado` es `document.lastModified`: la fecha del archivo QUE EL
-- APARATO TIENE CARGADO, no la que el servidor sirve ahora. Es lo unico que
-- distingue dos builds con el mismo sello, y contesta "¿que version corria el
-- iPad?" sin depender del sello.
-- `standalone` va por lo mismo: el icono de iOS es el que retiene la version
-- vieja horas o dias (medido el 8-sep con el pedido 46).
-- `vista` y `miga` van LOS DOS a proposito: `vista` dice `vReporte`, que a
-- Andrea no le dice nada; `miga` dice "Entregas · Sin factura", que no sirve
-- para buscar en el codigo. Cada uno contesta una pregunta distinta.

-- La firma no se elige: tiene que ser quien esta adentro. Mismo guardia que
-- ent_alisto_lote_correccion, y por el mismo motivo.
create or replace function ticket_firma_guard()
returns trigger language plpgsql as $guard$
declare quien text;
begin
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
$guard$;

drop trigger if exists ticket_firma_trg on ticket;
create trigger ticket_firma_trg before insert on ticket
  for each row execute function ticket_firma_guard();


-- ════════════════════════════════════════════════════════════════════════
-- 2 · EL CICLO DE VIDA · eventos, no una columna
-- ════════════════════════════════════════════════════════════════════════
-- ── EL MAPA DE NOMBRES · decidido por Andrea el 17-sep ──────────────────
--   adentro          en pantalla     quien lo pone
--   ───────────────  ──────────────  ───────────────────────────────────
--   (sin eventos)    "Abierto"       nadie: es la ausencia de eventos
--   en_analisis      "En curso"      una socia
--   resuelto         "Resuelto"      una socia
--   cerrado          "Visto"         una socia — es el gesto que VACIA la lista
--
-- Los nombres de ADENTRO no se tocan a proposito: la version del 10-sep ya los
-- usa, estan en la vista y en el guardia, y renombrarlos migraria datos para
-- ganar cero. El nombre de PANTALLA vive en index.html y puede cambiar sin
-- tocar la base. Si algun dia confunde, este mapa es la respuesta.
--
-- 'abierto' NO SE INSERTA NUNCA. Es la ausencia de eventos, y la vista lo
-- resuelve con un coalesce. Un estado inicial insertado seria una excepcion a
-- la regla escrita adentro de la regla misma.
create table if not exists ticket_estado (
  id          bigint generated always as identity primary key,
  ticket_id   bigint not null references ticket(id),
  estado      text   not null check (estado in ('en_analisis','resuelto','cerrado')),
  -- El ANALISIS de CC vive acá, no en un archivo del repo: Daniel no tiene el
  -- repo, y Andrea tiene que poder leer la propuesta al lado del ticket.
  nota        text,

  -- ── LOS DOS BUILDS, Y NO SON EL MISMO ────────────────────────────────
  -- ⚠️ AGREGADO EL 17-sep. Contestan preguntas distintas y confundirlos seria
  -- volver a la ambigüedad del 8-sep con otro nombre.
  --
  -- `build_al_marcar` · QUE ESTABA CORRIENDO LA SOCIA cuando toco el boton. Lo
  --   pone la app sola, de su propia constante BUILD. Sirve para cazar el caso
  --   feo: marcar "Resuelto" desde un aparato que todavia tiene la version
  --   vieja cargada — el icono de iOS retiene builds dias enteros (medido el
  --   8-sep con el pedido 46). NO es donde salio el arreglo.
  --
  -- `build_arreglo`   · DONDE SALIO EL ARREGLO DE VERDAD. Se escribe en el
  --   PUBLICAR, no en el marcar, y lo escribe el ritual de cierre (§11).
  --   Queda NULL hasta entonces, y NULL SE MUESTRA COMO "no consta", nunca se
  --   rellena con una suposicion. Es la misma regla que 'migrado · sin build'.
  build_al_marcar  text,
  build_arreglo    text,

  creado_en   timestamptz not null default now(),
  creado_por  text   not null,

  -- Pasar a "En curso" sin dejar escrito QUE se analizo es mover una ficha.
  constraint ticket_estado_nota_ok check (
    estado <> 'en_analisis'
    or length(btrim(coalesce(nota,''))) >= 20)
);
create index if not exists ticket_estado_idx
  on ticket_estado (ticket_id, creado_en desc);

-- ── EL GUARDIA ───────────────────────────────────────────────────────────
-- ⚠️ CAMBIO DEL 17-sep: ahora la regla es UNA SOLA — mover el estado es de las
--    socias. Desaparece la "REGLA 1 · quien abre no cambia estados" que tenia
--    la version del 10-sep, y conviene decir POR QUE y no borrarla en silencio:
--    esa regla existia para que nadie se autocontestara, en un mundo donde
--    cualquiera del equipo podia mover un ticket ajeno. Con "solo socias" ya no
--    hay a quien impedirselo: el equipo no mueve nada. Y la excepcion que
--    Andrea habia aprobado el 10-sep —que una socia SI pueda mover un ticket
--    que abrio ella, para no quedar trabada en el propio— se vuelve el caso
--    normal. La regla no se perdio: se disolvio adentro de la nueva.
--
-- ⚠️ Y LO MAS IMPORTANTE DE ESTE BLOQUE: la politica RLS del §7 dice
--    `acceso_es_socia()`, pero **la RLS no alcanza al SQL Editor**, que entra
--    como `postgres` y la pasa de largo. Ahi el unico que queda de pie es este
--    trigger. Por eso las dos capas no son adorno, y por eso el trigger repite
--    lo que la politica ya dice.
create or replace function ticket_estado_guard()
returns trigger language plpgsql as $guard$
declare
  autor text;
  quien text;
  socia boolean;
begin
  select t.creado_por into autor from ticket t where t.id = new.ticket_id;
  if autor is null then
    raise exception 'no existe el ticket %', new.ticket_id;
  end if;

  quien := nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email';

  if quien is null then
    -- SQL Editor: la base no puede saber quien escribe, y eso se dice.
    -- ✅ APROBADO 10-sep: es la via por la que entra el analisis de CC, y la
    -- UNICA. pg_lector.py sigue siendo SOLO LECTURA con sus dos candados: CC no
    -- escribe en Supabase, escribe el INSERT y Andrea lo pega. Un paste por
    -- sesion, con el analisis de todos los tickets trabajados.
    if new.creado_por not like 'cc-sql%' then
      raise exception 'un cambio de estado sin sesion de Supabase (SQL Editor) tiene que '
        'firmar creado_por empezando con "cc-sql". Vino: %', new.creado_por;
    end if;
    -- Ni siquiera por SQL se marca "Visto": ese gesto es de una socia concreta,
    -- y desde el SQL Editor no hay forma de saber cual.
    if new.estado = 'cerrado' then
      raise exception 'marcar "Visto" es de las socias y desde el SQL Editor no se sabe '
        'quien esta escribiendo. Se hace desde la pantalla, con sesion.';
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

  -- ── LA REGLA · mover el estado es de las socias ───────────────────────
  if not socia then
    raise exception 'mover el estado de un ticket es de un perfil socias, y % no lo es. '
      'Reportar es de todos; decidir que pasa con lo reportado, no.', quien;
  end if;

  return new;
end
$guard$;

drop trigger if exists ticket_estado_guard_trg on ticket_estado;
create trigger ticket_estado_guard_trg before insert on ticket_estado
  for each row execute function ticket_estado_guard();


-- ════════════════════════════════════════════════════════════════════════
-- 3 · LA MARCA · ¿toca numeros o escribe en la base?
-- ════════════════════════════════════════════════════════════════════════
-- ⚠️ NUEVO EL 17-sep. Es LO QUE VUELVE AUTOMATIZABLE AL MODULO, y es la razon
-- por la que el ticket sale hacia el repo (§6).
--
-- LA REGLA DE DONDE SALE (14-sep): §17, §18 y §19 los puede tomar un agente;
-- §20 no, aunque parezca del mismo tamaño. Lo que separa a los tres del cuarto
-- no es el tamaño: es si el trabajo TOCA NUMEROS o ESCRIBE EN LA BASE. Con esa
-- marca puesta, el agente sabe cuales puede agarrar sin preguntar.
--
-- ES UN EVENTO Y NO UNA COLUMNA DE `ticket`, por dos razones y las dos pesan:
--   1. Daniel NO PUEDE ponerla. No sabe si algo toca numeros — por eso lo esta
--      reportando. La marca nace cuando Andrea mira el ticket, despues.
--   2. Si fuera columna de `ticket`, ponerla seria un UPDATE y el ticket
--      dejaria de ser append-only. Toda la doctrina del proyecto se cae por
--      esa esquina.
--
-- SON DOS PREGUNTAS, NO UNA, y se guardan separadas a proposito. "No lo puede
-- tomar un agente" es una conclusion; `toca_numeros` y `escribe_en_base` son
-- los hechos de los que sale. Guardar solo la conclusion obliga a re-preguntar
-- el porque cada vez, y el porque es justo lo que se pierde primero.
create table if not exists ticket_marca (
  id               bigint generated always as identity primary key,
  ticket_id        bigint not null references ticket(id),

  toca_numeros     boolean not null,   -- ¿el arreglo cambia un calculo, un saldo, un costo?
  escribe_en_base  boolean not null,   -- ¿el arreglo escribe en Supabase o en Odoo?

  -- Una marca sin razon escrita es mover una ficha. Mismo criterio que la nota
  -- de "En curso", con un minimo mas bajo porque acá la razon suele ser corta
  -- y precisa ("solo cambia el texto del boton").
  razon            text not null,
  constraint ticket_marca_razon_ok
    check (length(btrim(coalesce(razon,''))) >= 12),

  creado_en        timestamptz not null default now(),
  creado_por       text not null
);
create index if not exists ticket_marca_idx
  on ticket_marca (ticket_id, creado_en desc);

comment on table ticket_marca is
  'Append-only. La ultima fila por ticket es la que vale. La pone una socia al '
  'mirar el ticket, nunca quien lo reporta.';

-- Mismo guardia, misma razon: marcar es decidir, y decidir es de las socias.
-- Y otra vez: la RLS del §7 no alcanza al SQL Editor. Este trigger si.
create or replace function ticket_marca_guard()
returns trigger language plpgsql as $guard$
declare quien text; socia boolean;
begin
  if not exists (select 1 from ticket t where t.id = new.ticket_id) then
    raise exception 'no existe el ticket %', new.ticket_id;
  end if;

  quien := nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email';

  if quien is null then
    if new.creado_por not like 'cc-sql%' then
      raise exception 'una marca sin sesion de Supabase (SQL Editor) tiene que firmar '
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
    raise exception 'marcar un ticket es de un perfil socias, y % no lo es.', quien;
  end if;
  return new;
end
$guard$;

drop trigger if exists ticket_marca_guard_trg on ticket_marca;
create trigger ticket_marca_guard_trg before insert on ticket_marca
  for each row execute function ticket_marca_guard();


-- ════════════════════════════════════════════════════════════════════════
-- 4 · LA FOTO · una fila por INTENTO, no una fila por archivo
-- ════════════════════════════════════════════════════════════════════════
-- ⚠️ CAMBIO DEL 17-sep, y sale de una leccion medida ESE MISMO DIA. En
-- Devoluciones (b61) un guardado fallaba EN SILENCIO: Andrea guardo, la lista
-- dijo "todavia no hay devoluciones", y en la base habia cero filas. Tres
-- silencios encadenados.
--
-- Aca el silencio tendria esta forma: Andrea abre un ticket, no ve foto, y NO
-- PUEDE SABER si Daniel no saco ninguna o si la subida se perdio. Son dos
-- cosas distintas y una de ellas es un bug.
--
-- Por eso la tabla guarda INTENTOS, no archivos:
--
--   filas del ticket            significa
--   ─────────────────────────   ────────────────────────────────────────────
--   ninguna                     no se adjunto foto. Es normal.
--   'intento' y nada mas        se empezo a subir y NO SE SUPO COMO TERMINO
--                               (el aparato se apago, se fue la señal). Es el
--                               unico estado honesto para ese caso.
--   'intento' + 'fallo'         se intento y fallo, con el error guardado.
--   'intento' + 'subida'        esta la foto.
--
-- ⚠️ EL ORDEN IMPORTA Y NO ES CAPRICHO: la fila 'intento' se escribe ANTES de
-- empezar a subir, mientras la red todavia funciona —lo sabemos porque el
-- ticket acaba de entrar—. Si se escribiera despues, el registro del fallo
-- necesitaria red para registrar que no habia red, que es un chiste. Escribir
-- primero es lo que hace que el caso "no se supo" exista en vez de parecer
-- "sin foto".
create table if not exists ticket_foto (
  id          bigint generated always as identity primary key,
  ticket_id   bigint not null references ticket(id),
  resultado   text   not null check (resultado in ('intento','subida','fallo')),

  ruta        text,               -- 'tickets/{ticket_id}/{uuid}.{ext}' — solo si subio
  mime        text,
  bytes       bigint,
  error       text,               -- el mensaje que devolvio Storage — solo si fallo

  creado_en   timestamptz not null default now(),
  creado_por  text   not null,

  -- Que cada resultado traiga lo suyo, o la fila no dice nada.
  constraint ticket_foto_subida_ok check (
    resultado <> 'subida' or (ruta is not null and length(btrim(coalesce(ruta,''))) > 0)),
  constraint ticket_foto_fallo_ok check (
    resultado <> 'fallo'  or length(btrim(coalesce(error,''))) >= 3)
);
create index if not exists ticket_foto_idx on ticket_foto (ticket_id, creado_en);
-- Una ruta no se repite. El indice es PARCIAL porque 'intento' y 'fallo' no
-- tienen ruta, y un unique comun dejaria pasar los NULL igual pero sin decir
-- que eso fue a proposito.
create unique index if not exists ticket_foto_ruta_uq
  on ticket_foto (ruta) where ruta is not null;


-- ════════════════════════════════════════════════════════════════════════
-- 5 · LAS VISTAS QUE LEE LA PANTALLA
-- ════════════════════════════════════════════════════════════════════════
-- security_invoker en TODAS: es la regla del modulo desde la fuga del 24-ago
-- (v_acceso_usuario le devolvia cinco correos a la anon key).

-- El estado de la foto, resumido a una palabra que Andrea pueda leer de un ojo.
create or replace view v_ticket_foto with (security_invoker = true) as
  select f.ticket_id,
         case
           when bool_or(f.resultado = 'subida') then 'ok'
           when bool_or(f.resultado = 'fallo')  then 'perdida'
           else 'sin_respuesta'                 -- quedo en 'intento' y nunca cerro
         end                                              as estado_foto,
         count(*) filter (where f.resultado = 'subida')   as fotos,
         max(f.error) filter (where f.resultado = 'fallo') as ultimo_error
    from ticket_foto f
   group by f.ticket_id;

create or replace view v_ticket with (security_invoker = true) as
  select t.id,
         t.descripcion, t.tipo,
         t.build, t.doc_modificado, t.vista, t.miga, t.modulo, t.sobre,
         t.agente, t.standalone, t.viewport,
         t.tz_offset_min, t.tz_nombre,
         t.creado_en, t.creado_por,
         coalesce(e.estado, 'abierto')          as estado,
         e.nota                                 as ultima_nota,
         e.creado_en                            as estado_en,
         e.creado_por                           as estado_por,
         -- La marca. `agente_puede` es DERIVADA, nunca guardada: guardar una
         -- conclusion al lado de sus premisas es pedir que se contradigan.
         m.toca_numeros,
         m.escribe_en_base,
         (m.toca_numeros is not null
            and not m.toca_numeros and not m.escribe_en_base) as agente_puede,
         m.razon                                as marca_razon,
         m.creado_por                           as marca_por,
         -- Sin fila en ticket_foto no hay nada que decir: es 'sin_foto'.
         coalesce(f.estado_foto, 'sin_foto')    as estado_foto,
         coalesce(f.fotos, 0)                   as fotos,
         f.ultimo_error                         as foto_error
    from ticket t
    left join lateral (
      select x.estado, x.nota, x.creado_en, x.creado_por
        from ticket_estado x
       where x.ticket_id = t.id
       order by x.creado_en desc
       limit 1) e on true
    left join lateral (
      select x.toca_numeros, x.escribe_en_base, x.razon, x.creado_por
        from ticket_marca x
       where x.ticket_id = t.id
       order by x.creado_en desc
       limit 1) m on true
    left join v_ticket_foto f on f.ticket_id = t.id;

-- Lo que CC trae al abrir sesion con /retomar: lo abierto y lo que ya analizo,
-- con su propuesta al lado. Lo marcado "Visto" no vuelve.
create or replace view v_ticket_pendiente with (security_invoker = true) as
  select * from v_ticket
   where estado in ('abierto','en_analisis','resuelto')
   order by (estado = 'abierto') desc, creado_en;

-- El contador de la tarjeta del lobby. Una fila por modulo.
create or replace view v_ticket_conteo with (security_invoker = true) as
  select coalesce(modulo, 'sin_modulo')              as modulo,
         count(*) filter (where estado = 'abierto')     as abiertos,
         count(*) filter (where estado = 'en_analisis') as en_curso,
         count(*) filter (where estado = 'resuelto')    as resueltos
    from v_ticket
   group by coalesce(modulo, 'sin_modulo');


-- ════════════════════════════════════════════════════════════════════════
-- 6 · LA SALIDA AL REPO · un archivo por ticket
-- ════════════════════════════════════════════════════════════════════════
-- ⚠️ NUEVO EL 17-sep. El circuito que Andrea pidio:
--     Daniel reporta → Andrea marca → CC lo toma de ahi. Sin que nadie lo
--     reescriba.
--
-- ⚠️ Y LO PRIMERO, PARA QUE NADIE SE CONFUNDA: **la base de datos no escribe
--    archivos.** Esta vista no "exporta" nada; arma el TEXTO, y alguien tiene
--    que venir a buscarlo y escribirlo en disco. Ese alguien es una
--    herramienta chica que todavia no existe (ver el pendiente), o un copiar y
--    pegar mientras tanto. Decirlo de otra forma seria prometer algo que este
--    archivo no hace.
--
-- POR QUE UNA VISTA Y NO UN CAMPO: el contenido del archivo se DERIVA del
-- ticket y de sus eventos. Guardarlo seria una copia que se desincroniza a la
-- primera nota nueva — y despues nadie sabe cual de las dos manda.
--
-- EL NOMBRE DEL ARCHIVO lleva el id con ceros a la izquierda para que ordene
-- solo en cualquier listado: tickets/T-0007.md
create or replace view v_ticket_export with (security_invoker = true) as
  select t.id,
         'tickets/T-' || lpad(t.id::text, 4, '0') || '.md'          as archivo,
         concat_ws(E'\n',
           '# T-' || lpad(t.id::text, 4, '0') || ' · ' ||
             case t.tipo when 'no_funciona' then 'Algo no funciona'
                         when 'duda'        then 'Tengo una duda'
                         else                    'Se me ocurrió algo' end,
           '',
           '> **Estado:** ' ||
             case t.estado when 'abierto'     then 'Abierto'
                           when 'en_analisis' then 'En curso'
                           when 'resuelto'    then 'Resuelto'
                           else                    'Visto' end ||
             '  ·  **Reportó:** ' || t.creado_por ||
             '  ·  **Cuándo:** ' || to_char(t.creado_en, 'YYYY-MM-DD HH24:MI') ||
             coalesce(' (' || t.tz_nombre || ')', ''),
           '',
           '## Qué pasa',
           '',
           t.descripcion,
           '',
           '## Dónde estaba parado',
           '',
           '| | |',
           '|---|---|',
           '| Pantalla | ' || coalesce(t.miga, '—') ||
             coalesce(' (`' || t.vista || '`)', '') || ' |',
           '| Módulo | ' || coalesce(t.modulo, '—') || ' |',
           '| Encima | ' || coalesce(t.sobre, '— nada') || ' |',
           '| Build | ' || t.build || ' |',
           '| Archivo cargado | ' || coalesce(t.doc_modificado, '— no capturado') || ' |',
           '| Desde el ícono | ' || coalesce(t.standalone::text, '—') || ' |',
           '| Pantalla física | ' || coalesce(t.viewport, '—') || ' |',
           '| Aparato | ' || coalesce(t.agente, '—') || ' |',
           '| Foto | ' ||
             case t.estado_foto
               when 'ok'            then t.fotos || ' adjunta(s)'
               when 'perdida'       then '⚠️ SE PERDIÓ LA SUBIDA — ' || coalesce(t.foto_error,'')
               when 'sin_respuesta' then '⚠️ se intentó subir y no se supo cómo terminó'
               else                      'sin foto' end || ' |',
           '',
           '## Marca',
           '',
           case when t.toca_numeros is null then
             '_Sin marcar. Hasta que una socia lo marque, **un agente no lo toma**._'
           else
             '- ¿Toca números? **' || case when t.toca_numeros then 'Sí' else 'No' end || '**' ||
             E'\n' ||
             '- ¿Escribe en la base? **' || case when t.escribe_en_base then 'Sí' else 'No' end || '**' ||
             E'\n' ||
             '- ➡️ **' || case when t.agente_puede
                                then 'Un agente puede tomarlo.'
                                else 'Un agente NO lo toma.' end || '**' ||
             E'\n\n' || '> ' || t.razon || '  — ' || coalesce(t.marca_por,'')
           end,
           '',
           case when t.ultima_nota is null then ''
                else '## Análisis' || E'\n\n' || t.ultima_nota ||
                     E'\n\n' || '— ' || coalesce(t.estado_por,'') ||
                     coalesce(', ' || to_char(t.estado_en,'YYYY-MM-DD'), '') end
         )                                                          as contenido
    from v_ticket t;

-- PENDIENTE, anotado y NO construido: la herramienta que lee esta vista y
-- escribe los archivos. Cuando exista, va a ser SOLO LECTURA contra Supabase
-- (pg_lector.py ya sirve tal como esta) y escribir en disco del lado de la Mac.
-- No hace falta ningun permiso nuevo en la base para eso.


-- ════════════════════════════════════════════════════════════════════════
-- 7 · RLS
-- ════════════════════════════════════════════════════════════════════════
alter table ticket        enable row level security;
alter table ticket_estado enable row level security;
alter table ticket_marca  enable row level security;
alter table ticket_foto   enable row level security;

drop policy if exists ticket_sel on ticket;
drop policy if exists ticket_ins on ticket;
drop policy if exists ticket_estado_sel on ticket_estado;
drop policy if exists ticket_estado_ins on ticket_estado;
drop policy if exists ticket_marca_sel on ticket_marca;
drop policy if exists ticket_marca_ins on ticket_marca;
drop policy if exists ticket_foto_sel on ticket_foto;
drop policy if exists ticket_foto_ins on ticket_foto;

-- ── VER · TODO EL EQUIPO VE TODOS LOS TICKETS ───────────────────────────
-- ⚠️ DECISION DE ANDREA, REVISADA Y RATIFICADA EL 17-sep. Llego a pedir "cada
-- uno ve los suyos" y lo revirtio ella misma, con esta razon: *un ticket no
-- tiene nada privado, y el duplicado si cuesta — si Daniel ve que alguien ya
-- reporto lo mismo, no lo reporta dos veces*. Queda escrito para que a nadie
-- le parezca un descuido y lo "arregle".
-- La FOTO es harina de otro costal y sigue siendo estricta: ver §8.
create policy ticket_sel on ticket
  for select to authenticated using (true);

-- REPORTAR ES DE TODOS. Daniel, el equipo y las socias, sin distincion.
-- El `true` no es flojera: el trigger del §1 ata la firma a la sesion, que es
-- la unica restriccion que tiene sentido acá.
create policy ticket_ins on ticket
  for insert to authenticated with check (true);

create policy ticket_estado_sel on ticket_estado
  for select to authenticated using (true);

-- ── MOVER EL ESTADO · SOLO SOCIAS, Y ACA ES DONDE CUENTA ────────────────
-- 🔴 ESTA LINEA ES LA LECCION DEL 17-sep. Ese dia se midio que
-- `ent_anulacion_ins` decia `with check (true)` mientras la pantalla decia
-- "solo socias": cualquiera con sesion pasaba la politica, y lo unico que
-- frenaba a Daniel era que no le mostraban el boton. Una garantia de pantalla
-- no es una garantia. Acá la condicion esta en la base.
create policy ticket_estado_ins on ticket_estado
  for insert to authenticated with check (acceso_es_socia());

create policy ticket_marca_sel on ticket_marca
  for select to authenticated using (true);

-- Marcar es decidir. Mismo criterio, misma linea.
create policy ticket_marca_ins on ticket_marca
  for insert to authenticated with check (acceso_es_socia());

-- La FILA de la foto (que existe, cuanto peso, si fallo) la ve todo el equipo:
-- es metadato y sirve para saber que una subida se perdio. El ARCHIVO en si
-- tiene su propia politica, mas estricta, en §8. No es una incoherencia: son
-- dos cosas con sensibilidad distinta.
create policy ticket_foto_sel on ticket_foto
  for select to authenticated using (true);

-- Adjuntar: a un ticket propio, o cualquiera si es socia (agregar la foto que
-- Daniel no pudo sacar). Espeja la politica de Storage del §8 — si las dos no
-- dicen lo mismo, una de las dos miente.
create policy ticket_foto_ins on ticket_foto
  for insert to authenticated with check (
    acceso_es_socia()
    or exists (select 1 from ticket t
                where t.id = ticket_id
                  and lower(t.creado_por) = lower(coalesce(auth.jwt() ->> 'email',''))));

-- Sin update ni delete en las cuatro: append-only se niega por AUSENCIA de
-- politica. No hay que escribir nada para prohibirlo.
-- ⚠️ Pero SI hay que revocar lo que Supabase regala: por privilegios por
-- defecto sobre `public`, `anon` y `authenticated` reciben update y delete
-- igual. Hoy la RLS los contiene (no hay politica que los deje tocar una fila),
-- pero el grant sobra y se mide como sobrante. Es el hallazgo V4=12 del 16-sep.
revoke all on ticket, ticket_estado, ticket_marca, ticket_foto from anon;
revoke update, delete, truncate on ticket, ticket_estado, ticket_marca, ticket_foto
  from authenticated;

grant select, insert on ticket        to authenticated;
grant select, insert on ticket_estado to authenticated;
grant select, insert on ticket_marca  to authenticated;
grant select, insert on ticket_foto   to authenticated;
grant select on v_ticket, v_ticket_pendiente, v_ticket_conteo,
                v_ticket_foto, v_ticket_export to authenticated;


-- ════════════════════════════════════════════════════════════════════════
-- 8 · EL BUCKET · privado, y la parte que hay que mirar dos veces
-- ════════════════════════════════════════════════════════════════════════
-- Un screenshot de Truefie puede tener clientes, facturas y cantidades. Y si
-- se saca desde una pantalla de Personal, puede tener un salario o una nota
-- medica. Eso ultimo es lo que decide la politica de LECTURA de abajo.
--
-- ── ⚠️ LA DECISION SOBRE HEIC · la pediste antes de construir ───────────
-- **Se convierte a JPEG en el navegador ANTES de subir. HEIC queda en la lista
--   de permitidos solo como red, no como camino normal.**
--
-- Las razones, en orden de peso:
--   1. Si la foto no se puede VER, no sirve de nada. HEIC no se muestra en un
--      <img> en Chrome ni en Firefox, y en Safari viejo tampoco. Andrea abre
--      el ticket desde donde este, no siempre desde un iPhone. Una foto que
--      solo se ve en la mitad de los aparatos es media foto.
--   2. La foto es para DIAGNOSTICAR, no para archivar. No hay nada que
--      preservar: la fidelidad no entra en la decision.
--   3. Pesa menos. Un screenshot de iPad en PNG son 2-4 MB; en JPEG de calidad
--      0,9 baja mucho. Menos peso es menos subida fallida con señal mala, que
--      es justo el caso de Daniel en la calle.
--   4. Convertir por canvas TIRA EL EXIF, y con el la ubicacion GPS si la
--      foto vino de la camara. Es un beneficio que no buscabamos.
--
-- Y un dato que achica el problema: **las capturas de pantalla de iOS son PNG,
-- no HEIC.** HEIC solo aparece si Daniel FOTOGRAFIA algo fisico con la camara.
-- O sea que es el caso raro, no el normal.
--
-- ⚠️ LO QUE NO MEDI, y conviene que este escrito: el comportamiento exacto de
-- iOS al elegir una foto con <input type="file" accept="image/*">. En la
-- practica iOS suele entregar JPEG ya convertido, pero eso es conocimiento
-- general, NO una medicion en el iPad de Andrea. Por eso HEIC se queda en la
-- lista: si la conversion falla, se sube el original y se guarda el mime real,
-- en vez de perder la foto por una suposicion mia.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'tickets', 'tickets',
  false,                                  -- PRIVADO. No cambiar. Es todo el asunto.
  10485760,                               -- 10 MB. Un screenshot de iPad pesa 2-4 MB
  array['image/jpeg','image/png','image/webp','image/heic','image/heif']
)
on conflict (id) do update
  set public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ── LA RUTA ─────────────────────────────────────────────────────────────
--     bucket 'tickets'  ·  objeto:  {ticket_id}/{uuid}.{ext}
--                                    └─ ESTA carpeta manda la seguridad
--
-- ⚠️ EL NOMBRE DEL BUCKET NO VA ADENTRO DE LA RUTA. En Supabase el bucket vive
-- en `storage.objects.bucket_id` y `name` guarda SOLO la ruta interna, asi que
-- para 'tickets' + '12/ab.png' el `name` es '12/ab.png' y foldername devuelve
-- {12}: el ticket_id es el [1], no el [2]. Es la misma convencion que
-- PERSONAL_STORAGE, donde el persona_id tambien es el [1] — ahi el
-- 'justificantes/' que aparece en los comentarios es el nombre del bucket, no
-- un segmento. Escribirlo mal NO DA ERROR: da una politica que compara contra
-- el segmento equivocado y deja de proteger EN SILENCIO.
--
-- Y el primer segmento es el ticket_id y NO el correo: un correo dentro de una
-- ruta es un dato personal viajando en un identificador, y las rutas terminan
-- en logs, en URLs firmadas y en mensajes de error.
create or replace function ticket_de_ruta(ruta text) returns bigint
language sql stable as $$
  select nullif((storage.foldername(ruta))[1], '')::bigint;
$$;

create or replace function ticket_es_mio(ruta text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from ticket t
                  where t.id = ticket_de_ruta(ruta)
                    and lower(t.creado_por) = lower(coalesce(auth.jwt() ->> 'email','')));
$$;

drop policy if exists tickets_ins on storage.objects;
drop policy if exists tickets_sel on storage.objects;
drop policy if exists tickets_upd on storage.objects;
drop policy if exists tickets_del on storage.objects;

-- SUBIR: a la carpeta de un ticket propio. Una socia puede subir a cualquiera.
create policy tickets_ins on storage.objects
  for insert to authenticated
  with check (bucket_id = 'tickets'
              and (acceso_es_socia() or ticket_es_mio(name)));

-- ⚠️ VER: LA FOTO PROPIA, O TODO SI ES SOCIA. Y NO "todo el equipo".
-- ✅ APROBADO POR ANDREA EL 10-sep, y RATIFICADO el 17-sep cuando se decidio
--    que el TEXTO si lo ve todo el equipo. Las dos cosas conviven a proposito:
--    el TEXTO de un ticket lo escribe una persona que sabe lo que esta
--    escribiendo; la FOTO se saca de la pantalla que estaba abierta, y esa
--    pantalla puede ser Personal — un salario, un aguinaldo, una nota medica.
--    Si la lectura del archivo fuera "todo el equipo", un ticket abierto desde
--    Personal le abriria a Daniel un dato que hoy no ve.
--    Reglas de acceso distintas no se mezclan porque el archivo "es del mismo
--    tipo". Es la leccion de PERSONAL_STORAGE.
create policy tickets_sel on storage.objects
  for select to authenticated
  using (bucket_id = 'tickets'
         and (acceso_es_socia() or ticket_es_mio(name)));

-- Sin update ni delete: append-only, igual que justificantes. Una foto que no
-- sirve se reemplaza subiendo otra, no borrando la primera.


-- ════════════════════════════════════════════════════════════════════════
-- 9 · LO QUE TIENE QUE HACER ANDREA, Y COMPROBAR DESPUES
-- ════════════════════════════════════════════════════════════════════════
-- ⚠️ EL CONTROL VA ADENTRO DE LA TRANSACCION SI SE PEGA TODO JUNTO. Este
--    archivo NO abre transaccion a proposito: son muchos objetos y conviene
--    pegarlo por secciones, mirando cada una. Pero entonces la verificacion de
--    abajo NO es opcional: sin ella, un "Success. No rows returned" no prueba
--    nada. Es la leccion del 16-sep, cuando el primer pegado de
--    CAMBIO_DEVOLUCIONES no aplico NADA y dijo exactamente eso.
--
-- 1) Storage → Buckets. Si despues de pegar falta `tickets`, el insert no tuvo
--    permisos: crealo a mano.
--        New bucket → nombre: tickets
--        Public bucket: DESMARCADO   ← lo mas importante de todo el archivo
--        File size limit: 10 MB
--        Allowed MIME types: image/jpeg, image/png, image/webp, image/heic, image/heif
--    Y volve a pegar el §8, para que queden las politicas.

-- V1 · Las tablas. ESPERADO: 5 (las cuatro del ticket + build_publicado).
select count(*) as tablas_debe_ser_5
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r'
   and c.relname in ('ticket','ticket_estado','ticket_marca','ticket_foto',
                     'build_publicado');

-- V2 · Las vistas, TODAS con security_invoker. ESPERADO: 6 filas, las seis
--      en `t`. Una vista sin la opcion es la fuga del 24-ago otra vez.
select c.relname,
       coalesce((select option_value from pg_options_to_table(c.reloptions)
                  where option_name = 'security_invoker'), 'NO LA TIENE') as invoker
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'v'
   and c.relname in ('v_ticket','v_ticket_pendiente','v_ticket_conteo',
                     'v_ticket_foto','v_ticket_export','v_ticket_historial')
 order by c.relname;

-- V3 · 🔴 LA QUE IMPORTA MAS. Que mover el estado y marcar sean de socias EN
--      LA BASE. ESPERADO: las dos filas con `acceso_es_socia()` en with_check.
--      Si alguna dice `true`, es `ent_anulacion_ins` otra vez: la pantalla
--      diria "solo socias" y la base dejaria pasar a cualquiera. PARAR.
select tablename, policyname, cmd, with_check
  from pg_policies
 where schemaname = 'public'
   and policyname in ('ticket_estado_ins','ticket_marca_ins')
 order by policyname;

-- V4 · Que no quede update ni delete concedido. ESPERADO: CERO filas.
select table_name, grantee, privilege_type
  from information_schema.role_table_grants
 where table_schema = 'public'
   and table_name in ('ticket','ticket_estado','ticket_marca','ticket_foto')
   and grantee in ('anon','authenticated')
   and privilege_type in ('UPDATE','DELETE','TRUNCATE')
 order by table_name, grantee;

-- V5 · El bucket. `public` TIENE que salir false. Si sale true, cada
--      screenshot queda legible para cualquiera con la URL, sin login.
select id, public, file_size_limit, allowed_mime_types
  from storage.buckets where id = 'tickets';

-- V6 · Las politicas de Storage. ESPERADO: DOS, tickets_ins y tickets_sel.
--      Si aparece una de update o delete, sobra.
select policyname, cmd from pg_policies
 where tablename = 'objects' and policyname like 'tickets%';

-- V7 · ⚠️ QUE LA POLITICA MIRE EL SEGMENTO CORRECTO. Una politica que compara
--      contra la carpeta equivocada no da error: deja de proteger y nadie se
--      entera. ESPERADO: 12.
select ticket_de_ruta('12/ab.png') as debe_dar_12;

-- V8 · Y la prueba de verdad, que no es un select: con un ticket ya subido, y
--      con la sesion de alguien que NO sea su autor ni socia, la foto tiene
--      que dar "not found". Si se ve, PARAR.
--      ⚠️ Esto NO se puede probar desde el SQL Editor: entra como `postgres` y
--         saltea la RLS. Va con el carril B de pg_pruebas.py (pendiente H3), o
--         con dos sesiones de verdad en la app.

-- 🟢 YA MEDIDO EL 17-sep, no hace falta repetirlo: `justificantes` y
--    `aguinaldos` existen y los dos tienen public = false. Era lo que pedia el
--    ticket T6 y quedo contestado. Lo que sigue abierto de T6 es lo otro: que
--    esquema_check.py NO MIRA STORAGE, asi que nadie se habria enterado.


-- ════════════════════════════════════════════════════════════════════════
-- 10 · DONDE VA EL BOTON · la propuesta, porque junto a "Salir" no entra
-- ════════════════════════════════════════════════════════════════════════
-- EL PROBLEMA, MEDIDO: `#btnSalir` es position:fixed arriba a la derecha, y el
-- encabezado de telefono le reserva 78px EXACTOS (`padding-right:78px` en la
-- regla de `#appHeader` a max-width:700px). Esos 78px son lo que deja a la
-- miga de pan sin cortarse — y el 17-sep Andrea verifico EN EL APARATO que hoy
-- se ve completa. Un segundo boton ahi se come la reserva y la miga empieza a
-- terminar en "…", que es exactamente lo que acabamos de arreglar.
--
-- ── LA PROPUESTA · boton flotante abajo a la derecha ────────────────────
-- Un circulo chico, position:fixed, abajo a la derecha, por encima del
-- safe-area de iOS. No toca el encabezado, no toca los 78px, y no toca la
-- miga. Y se alcanza con el pulgar sin cambiar la mano, que es como Daniel
-- tiene el telefono cuando encuentra el problema.
--
-- POR QUE NO LAS OTRAS QUE SE MIRARON:
--   · Adentro del "+" de Mas vistas → ese menu es POR MODULO. El boton tiene
--     que estar en TODA pantalla, incluidas las de Finanzas y Personal.
--   · Al final de la fila de pestañas → mismo problema, y ademas Entregas ya
--     mide 517/720 en iPad: no sobra lugar.
--   · Una fila al pie de cada pantalla → hay que bajar scrolleando para
--     llegar. Cuando Daniel encuentra el problema esta mirando el problema,
--     no el pie.
--
-- ⚠️ LO QUE HAY QUE CUIDAR, Y ES REAL:
--   1. El boton FLOTA ENCIMA del contenido. En las pantallas de Entregas hay
--      tablas, y la ultima fila puede quedar tapada. `.main` ya tiene
--      `padding-bottom: calc(28px + env(safe-area-inset-bottom))`; hay que
--      subirlo donde viva el boton, o la ultima fila se pierde.
--   2. `env(safe-area-inset-bottom)` NO es opcional en iPhone: sin el, el
--      boton queda debajo de la barra de gestos y se toca sin querer al
--      subir para cerrar la app.
--   3. ⚠️ Y esto hay que MIRARLO EN EL APARATO antes de darlo por bueno, no
--      deducirlo: es la misma regla que valio hoy para la miga.


-- ════════════════════════════════════════════════════════════════════════
-- 11 · EL HISTORIAL · y el build en el que salio el arreglo
-- ════════════════════════════════════════════════════════════════════════
-- ⚠️ NUEVO EL 17-sep, a pedido de Andrea. Un ticket cerrado tiene que poder
-- leerse ENTERO, de una, sin ruido: que se reporto, quien, cuando, la foto, lo
-- que capturo el sistema, cada cambio de estado con su nota — y en que build
-- salio el arreglo. Eso ultimo es lo que convierte "resuelto" en "resuelto
-- asi".
--
-- ── EL PROBLEMA, DICHO DERECHO ──────────────────────────────────────────
-- El build del arreglo NO se sabe cuando se marca "Resuelto". Se sabe cuando
-- se PUBLICA, que es despues y a veces bastante despues. Cualquier diseño que
-- dependa de que alguien vuelva al ticket a escribirlo ya perdio: nadie
-- vuelve.
--
-- ── LA SOLUCION · que lo escriba el ritual que YA CORRE ─────────────────
-- No hace falta que nadie se acuerde, porque hay un momento que ya existe y ya
-- mide exactamente estos datos: **el cierre de sesion que publica** (`/cierre`).
-- Ese ritual ya calcula el sha de `main`, ya lo compara contra `origin/main`,
-- ya verifica el sello contra Pages y ya lo escribe en la bitacora. Agregarle
-- una fila es sumar un dato que ya tiene en la mano, no pedirle uno nuevo.
--
-- Son dos piezas:
--
--   1. `build_publicado` (abajo) · UNA FILA POR PUBLICACION. Sello, sha de
--      main, cuando, y que ramas entraron. Resuelve de paso el problema viejo
--      de que "b56" signifique dos cosas: el sha desambigua siempre.
--
--   2. Al publicar, el ritual lee los commits que entraron, busca las
--      referencias `T-0007` en los mensajes —la misma costumbre con la que el
--      repo ya escribe `§12` y `b61`— y emite el INSERT en `ticket_estado`
--      con `build_arreglo` puesto. Andrea lo pega, como el analisis de CC.
--
-- ⚠️ Y CUANDO EL RITUAL NO PUEDA SABERLO, `build_arreglo` SE QUEDA EN NULL Y
--    LA PANTALLA DICE "no consta en qué build salió". No se infiere, no se
--    rellena con el build del dia. Un ticket puede resolverse sin tocar
--    codigo, o el arreglo puede haber entrado en un commit que no lo nombro.
--    Un dato con pinta de medido que en realidad es un supuesto es peor que
--    un hueco: el hueco se ve.
--
-- 🟠 SE PUEDE MOSTRAR UNA INFERENCIA, PERO ROTULADA. Con `build_publicado`
--    completa se puede decir "se marco Resuelto el 17-sep y el primer build
--    publicado despues fue b62". Eso es una PISTA, no el dato, y la pantalla
--    tiene que decirlo con esas palabras. Nunca en el mismo renglon ni con la
--    misma tipografia que el dato registrado.
create table if not exists build_publicado (
  id           bigint generated always as identity primary key,
  sello        text        not null,   -- la constante BUILD: 'v 17 sep 2026 · b61'
  sha_main     text        not null,   -- el commit de main que quedo publicado
  ramas        text,                   -- que se mergeo, en palabras
  publicado_en timestamptz not null default now(),
  creado_por   text        not null    -- 'cc-sql · cierre' o el correo de la socia
);
create unique index if not exists build_publicado_sha_uq on build_publicado (sha_main);
create index if not exists build_publicado_fecha_idx on build_publicado (publicado_en desc);

comment on table build_publicado is
  'Una fila por publicacion a main. La escribe el ritual de cierre, que ya mide '
  'estos datos. El sha desambigua los sellos repetidos.';

alter table build_publicado enable row level security;
drop policy if exists build_publicado_sel on build_publicado;
drop policy if exists build_publicado_ins on build_publicado;
create policy build_publicado_sel on build_publicado
  for select to authenticated using (true);
-- Publicar es de las socias. Y otra vez: el SQL Editor pasa la RLS de largo,
-- asi que esta politica cubre la app y no el pegado — que es el camino normal.
create policy build_publicado_ins on build_publicado
  for insert to authenticated with check (acceso_es_socia());
revoke all on build_publicado from anon;
revoke update, delete, truncate on build_publicado from authenticated;
grant select, insert on build_publicado to authenticated;

-- ── LA VISTA DEL HISTORIAL · una fila por cosa que paso ─────────────────
-- El orden es cronologico y el primero SIEMPRE es el reporte. La pantalla no
-- tiene que interpretar: pinta lo que viene.
-- ⚠️ El `order by` de una vista con UNION no esta garantizado si alguien la
--    envuelve en otra consulta. Quien la lea ordena igual por (orden, cuando).
create or replace view v_ticket_historial with (security_invoker = true) as
  select t.id                                as ticket_id,
         0                                   as orden,
         t.creado_en                         as cuando,
         'reporte'                           as que,
         t.creado_por                        as quien,
         t.descripcion                       as detalle,
         null::text                          as build_arreglo
    from ticket t
  union all
  select e.ticket_id, 1, e.creado_en,
         case e.estado when 'en_analisis' then 'En curso'
                       when 'resuelto'    then 'Resuelto'
                       else                    'Visto' end,
         e.creado_por, e.nota, e.build_arreglo
    from ticket_estado e
  union all
  select m.ticket_id, 1, m.creado_en, 'marca', m.creado_por,
         case when m.toca_numeros or m.escribe_en_base
              then 'Un agente NO lo toma. ' else 'Un agente puede tomarlo. ' end || m.razon,
         null
    from ticket_marca m
  union all
  select f.ticket_id, 1, f.creado_en,
         case f.resultado when 'subida' then 'foto'
                          when 'fallo'  then 'foto perdida'
                          else               'foto sin respuesta' end,
         f.creado_por, coalesce(f.error, f.ruta), null
    from ticket_foto f
   where f.resultado <> 'intento'      -- el 'intento' solo importa si nada lo cerro
  order by ticket_id, orden, cuando;

grant select on v_ticket_historial to authenticated;

-- ── LA PANTALLA ─────────────────────────────────────────────────────────
-- El estandar de tarjetas que se limpio estos dias: titulo, datos, y nada de
-- parrafos explicando el sistema. Nada grita.
--
--   · Arriba: el tipo y el estado. Nada mas.
--   · Despues: que se reporto, quien, cuando.
--   · La foto, si hay. Si se perdio, una linea que lo diga.
--   · Lo que capturo el sistema: en una tabla de dos columnas, plegada.
--     Son ocho campos tecnicos y no son la noticia.
--   · Abajo: la linea de tiempo, una fila por evento, con su nota.
--   · Y el build del arreglo al lado de "Resuelto" — o "no consta".
--
-- ⚠️ Sin subtitulos que expliquen que es un ticket. Es la misma regla que saco
--    el titulo de "Sin factura" el 17-sep: la pantalla arranca en el trabajo.


-- ════════════════════════════════════════════════════════════════════════
-- 12 · LOS ROJOS VIEJOS · la migracion, APROBADA y SIN PEGAR
-- ════════════════════════════════════════════════════════════════════════
-- Decision del 10-sep: se migran SOLO los 🔴. Los ambar se quedan en la
-- bitacora hasta que alguien los toque. La lista de siete la reviso y aprobo
-- Andrea el 10-sep.
--
-- QUE NO SE MIGRA, y por que (queda escrito para que nadie lo vuelva a proponer):
--   · "las cuatro mediciones del iPad, mañana temprano" — ese mañana era el
--     9-sep. Es una tarea vencida, no un hallazgo. Lo durable que habia debajo
--     es T1.
--   · "Bloque 4 + 3.2 + 3.3" — trabajo ya diseñado y en cola. Un ticket seria
--     una copia de la cola.
--   · DIAGNOSTICO_ESCRITURA_ODOO.md:98 — el 🔴 encabeza una CORRECCION
--     ("esto era falso"), no un pendiente abierto.
--   · reporte_cruce.md:7 — encabezado de un cruce de junio, anterior al modulo.
--     Antes de descartarlo del todo hay que confirmar que esos despachos ya
--     entraron. NO SE HIZO.
--
-- EL BUILD DE UN TICKET MIGRADO NO SE INVENTA. Va la cadena literal
-- 'migrado · sin build': un pendiente viejo no tiene version que capturar, y
-- ponerle la de hoy seria fabricar un dato con pinta de medido. Por la misma
-- razon van sin `vista`, sin `miga`, sin `doc_modificado`, sin `standalone` y
-- sin zona horaria: nadie los midio.
--
-- ⚠️ EL `tipo` LO ASIGNE YO, no salia de la bitacora — la columna es nueva del
--    17-sep y estos siete son de antes. Seis quedaron 'no_funciona' y T7 quedo
--    'duda' porque su primer trabajo es, literalmente, explicar que paso.
--    Andrea revisa y cambia el que no le cuadre; no es un dato medido.
--
-- La firma es 'ticket-sql · migracion 10-sep', que el guardia de §1 exige que
-- empiece con 'ticket-sql' cuando no hay sesion de Supabase.

/*  NO PEGAR — esperando el visto bueno final.

insert into ticket (descripcion, tipo, build, creado_por) values

-- ── T1 ──────────────────────────────────────────────────────────────────
('"b56" significa DOS cosas y el sello no lo dice. Entregas solo esta en main; '
 'Entregas mas el calendario de Personal de Lorena esta en dev. Cuando lo de '
 'Lorena se publique, el sello NO va a cambiar: los dos builds se llaman igual. '
 'Y el sello del pie del lobby es el mecanismo del que dependemos para saber que '
 'version corre el iPad de Daniel. Golpea justo ahi. Viene del bloque del 8-sep '
 'de la bitacora. '
 '⚠️ 17-sep: esto lo resuelve en parte `build_publicado` (§11), que guarda el '
 'sha de main junto al sello. El ticket no se cierra por eso: falta que el '
 'aparato pueda decir QUE version tiene cargada, que es `doc_modificado`.',
 'no_funciona', 'migrado · sin build', 'ticket-sql · migracion 10-sep'),

-- ── T2 ──────────────────────────────────────────────────────────────────
('stock.move.line sigue con write, create y unlink concedidos a TODO usuario '
 'interno de Odoo. Arrastra del 2-sep, cuando se arreglaron los otros cuatro '
 'modelos quitandole el grupo Inventory/User al usuario lector. En este modelo '
 'el unico freno que queda es LECTURA_OK, que es una lista de Python — o sea una '
 'sola capa en un proyecto cuya doctrina son dos. Va junto con los grants de '
 'Supabase, que tienen la misma forma.',
 'no_funciona', 'migrado · sin build', 'ticket-sql · migracion 10-sep'),

-- ── T3 ──────────────────────────────────────────────────────────────────
('Tres salidas sin registrar, cada una de un tipo distinto: (a) el summit, '
 'WH/INT/00137, validado en Odoo y ausente de Truefie; (b) el Pan Blanco de '
 'Automercado, que esta en Truefie pero sin lote; (c) BM/Bmquepos, WH/OUT/02350, '
 'cuyo albaran valido Andrea en Odoo el 7-sep 19:57 (6 paquetes, 1 caja) y del '
 'que solo falta que se registren los lotes. Andrea decidio registrarlas con el '
 'lote como NO DETERMINADO, con la razon y quien lo decidio. '
 '⚠️ BLOQUEADO: esa decision no se puede ejecutar todavia. El centinela existe '
 'en la base desde el 8-sep y NINGUNA pantalla lo ofrece. Este ticket no se '
 'puede trabajar hasta que salga el Bloque 3.2/3.3.',
 'no_funciona', 'migrado · sin build', 'ticket-sql · migracion 10-sep'),

-- ── T4 ──────────────────────────────────────────────────────────────────
('El BLOQUEO DURO de Despachos no existe: se aprobo como parte de la Entrega 2 y '
 'nunca se construyo. Hoy despachar de un lote sin saldo pasa en silencio. '
 'Verificado en el codigo el 10-sep, no citado: _despSaldo se lee en dos lugares '
 'de index.html y los dos son para armar el selector, nunca para frenar. '
 'Detalle completo en ENTREGAS_PENDIENTES.md §13. '
 '⚠️ NO LO ARREGLA EL BLOQUE 4, Y ESTE TICKET NO SE CIERRA CUANDO EL BLOQUE 4 '
 'SALGA. Son dos bloqueos distintos con el mismo apodo: el Bloque 4 es la LINEA '
 'SIN LOTE (falta el dato de que lote salio) y §13 es el LOTE SIN SALDO (el dato '
 'esta y dice que ese pan ya no existe). Arreglar el primero no toca al segundo. '
 'Si alguien cierra este ticket viendo salir el Bloque 4, lo cierra sin haberse '
 'resuelto — y seria la segunda vez que esta salvaguarda se da por hecha sin '
 'existir.',
 'no_funciona', 'migrado · sin build', 'ticket-sql · migracion 10-sep'),

-- ── T5 ──────────────────────────────────────────────────────────────────
('130 unidades salieron del lote Pan Blanco 208 / 1-27, que nunca se movio. El '
 'lote daba −4 en Inventario y Daniel conto 21 cajas = 126 unidades fisicas, '
 'cajas cerradas y todas de ese lote. Quedan dos hipotesis abiertas y el detalle '
 'entero, con lo ya descartado, esta en ENTREGAS_PENDIENTES.md §15.',
 'no_funciona', 'migrado · sin build', 'ticket-sql · migracion 10-sep'),

-- ── T6 ──────────────────────────────────────────────────────────────────
('PERSONAL_STORAGE.sql esta aprobado desde el 24-ago-2026 y nunca se estreno: '
 'grep de .upload( y de createSignedUrl sobre index.html → cero apariciones de '
 'cada uno, el 10-sep y otra vez el 17-sep sobre b61. Es el cuarto caso del '
 'patron "decision escrita y nunca implementada". Detalle en PENDIENTES.md P1. '
 '✅ 17-sep: LA PRIMERA PARTE YA SE MIDIO y salio bien. `justificantes` y '
 '`aguinaldos` EXISTEN y los dos tienen public = false. O sea que el pegado si '
 'se corrio; lo que nunca se estreno es el codigo. '
 '🔴 LO QUE SIGUE ABIERTO es lo otro, y es lo que importaba: esquema_check.py NO '
 'MIRA STORAGE. Que esta vez saliera bien no fue porque el porton avisara — '
 'nadie se habria enterado si hubiera salido mal. Es su unico punto ciego que '
 'puede callar sobre una exposicion de datos.',
 'no_funciona', 'migrado · sin build', 'ticket-sql · migracion 10-sep'),

-- ── T7 ──────────────────────────────────────────────────────────────────
('El paquete cruzado entre el lote 175 y el 191 (4 unidades). '
 'POR QUE ESTA EN ROJO, y esto es parte del ticket: se marco rojo porque NADIE '
 'EN LA SESION PUDO EXPLICAR BIEN QUE ES. No esta en rojo por gravedad medida '
 'sino por falta de entendimiento, y con BRC Start en proceso un paquete '
 'registrado contra el lote equivocado es un hueco de trazabilidad. '
 'PRIMER TRABAJO DEL TICKET: explicar en lenguaje claro y sin jerga que paso '
 'exactamente — que paquete, de que producto, que dice cada uno de los dos '
 'lotes, y que consecuencia real tiene. Andrea reevalua el color con eso en '
 'mano. '
 'Ojo al leerlo: el pendiente aparece 🟠 en su descripcion completa (bitacora '
 'del 7-sep) y 🔴 en el resumen del 8-sep. La contradiccion la resolvio Andrea '
 'el 10-sep a favor del rojo. '
 '⚠️ Y ojo con la unidad: si el paquete es de Frances, Buns o Pizza, "4 '
 'unidades" y "4 paquetes" no son lo mismo — leer eso mal ya desvio el caso del '
 'lote 191 durante horas.',
 'duda', 'migrado · sin build', 'ticket-sql · migracion 10-sep');

*/

-- Y despues, la comprobacion: tienen que salir SIETE, todos en 'abierto', seis
-- 'no_funciona' y uno 'duda'.
--   select id, tipo, estado, left(descripcion, 60) as arranque
--     from v_ticket where build = 'migrado · sin build' order by id;
