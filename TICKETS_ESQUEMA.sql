-- ════════════════════════════════════════════════════════════════════════
-- TICKETS · la ENTRADA de Daniel y la SALIDA de trabajo, en la misma tabla
-- PROPUESTA. NO PEGAR. Andrea aprueba antes.
--
-- ⚠️ REESCRITO ENTERO EL 17-sep-2026, por tercera vez en el dia. Las dos
--    versiones anteriores (10-sep y la de esta misma tarde) siguen vivas en
--    git. Este encabezado NO dice "aplicado" hasta DESPUES de pegar y de haber
--    mirado la verificacion del §10 — la regla del 16-sep.
--
-- ── LAS DOS MITADES, Y POR QUE SON LA MISMA TABLA ───────────────────────
--   ENTRADA · Daniel encuentra algo y lo reporta desde la pantalla. Escribe
--             tres cosas; el resto lo captura el sistema solo.
--   SALIDA  · el mismo hallazgo, triado, priorizado y con criterio de
--             terminado, es de donde CC toma trabajo y donde lo deja.
--
--   El backlog que Andrea vio (concasa-cc-backlog) resuelve la mitad de
--   SALIDA y no tiene entrada de usuarios. Truefie tiene las dos, y son la
--   misma fila: un reporte de Daniel triado ES un item de backlog. Duplicarlo
--   en dos tablas obligaria a copiar a mano, y lo que se copia a mano se
--   desincroniza.
--   ⚠️ EL COSTO, dicho de frente: un reporte de Daniel y un item de backlog no
--   tienen la misma forma. El de Daniel trae foto y contexto y una descripcion
--   de cinco caracteres; el de backlog trae criterio de terminado y prioridad.
--   O sea que la mitad de las columnas van en null para cada clase. Se acepta
--   a conciencia: ya pasa con los migrados, que llevan 'migrado · sin build'.
--
-- ── LOS OCHO ESTADOS ────────────────────────────────────────────────────
--   Sin triar      · nadie lo miro todavia. Es la AUSENCIA de eventos.
--   Disponible     · se puede agarrar YA.
--   Bloqueado      · espera otra cosa, y esa cosa esta escrita.
--   En curso       · alguien lo esta haciendo.
--   En validacion  · terminado, esperando que Andrea apruebe.
--   Cerrado        · listo.
--   Pospuesto      · no ahora, pero vuelve.
--   Descartado     · no se hace. No vuelve.
--
--   🔴 LO QUE MAS IMPORTA ES LA PRIMERA SEPARACION: **Bloqueado aparte de
--   Disponible**. Hoy los arrastrados mezclan lo que se puede hacer con lo que
--   espera otra cosa, y por eso la lista pesa. Separados, la lista real es la
--   de lo que se puede agarrar — y esa es corta.
--   🔴 Y LA SEGUNDA: **En validacion**. Es el rato entre que CC termina y
--   Andrea aprueba. Hoy no existe en ningun lado, y por eso las ramas se
--   acumulan sin que nadie sepa cuales esperan.
--   ⚠️ 'Pospuesto' y 'Descartado' van SEPARADOS a proposito. Pospuesto vuelve,
--   descartado no. Juntos, la lista de "lo que algun dia vuelve" no se puede
--   sacar, que es justo para lo que sirve.
--
-- ── QUIEN MUEVE QUE ─────────────────────────────────────────────────────
--   CC     · en_curso, en_validacion.      (toma trabajo y lo deja)
--   Andrea · disponible, bloqueado, cerrado, pospuesto, descartado.
--            O sea: el triaje y el cierre.
--
--   🔴 Y ESTO HAY QUE LEERLO DERECHO, PORQUE NO ES UNA PROTECCION:
--   CC escribe por el SQL Editor, que entra como `postgres` y **pasa la RLS de
--   largo**. Ahi el unico control es el trigger, y **el trigger NO PUEDE
--   VERIFICAR QUIEN ES CC**: solo comprueba que `creado_por` empiece con
--   `cc-sql`. Cualquiera con acceso al SQL Editor puede escribir esa cadena.
--   Es una CONVENCION para que la fila diga de donde vino, **no un candado**.
--   Quien tenga el SQL Editor ya puede hacer cualquier cosa con la base; esto
--   no agrega ni quita nada a eso. Que nadie lo lea como proteccion.
--   La proteccion de verdad es la RLS del §8, y esa cubre la APP: por ahi,
--   mover un estado exige `acceso_es_socia()` en la base y no en la pantalla.
--   Es la leccion del 17-sep con `ent_anulacion_ins`, que decia
--   `with check (true)` mientras la pantalla decia "solo socias".
--
-- ── EL TERRENO, MEDIDO EL 17-sep (no citado) ────────────────────────────
--   · `index.html` sigue en CERO `.upload(` y CERO `createSignedUrl` en b61.
--   · Los buckets `justificantes` y `aguinaldos` EXISTEN y son PRIVADOS.
--   · Cero tablas `ticket*` en la base: esto nunca se pego.
--   · `const BUILD = 'v 17 sep 2026 · b61'` (index.html:4028).
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- 1 · EL TICKET · lo que se escribe una vez y no se toca mas
-- ════════════════════════════════════════════════════════════════════════
-- Append-only. El ticket no cambia NUNCA. Lo que cambia son sus eventos:
-- estado (§2), triaje (§3), detalle (§4) y foto (§5). Cualquier cosa que
-- alguien pueda querer corregir despues va en un evento, no acá.
create table if not exists ticket (
  id           bigint generated always as identity primary key,

  -- ── LO QUE ESCRIBE LA PERSONA · tres cosas y nada mas ────────────────
  descripcion  text not null,
  tipo         text not null,

  -- ⚠️ MINIMO DE 5 CARACTERES. El reporte se hace con el problema en la mano
  -- y puede ser dictado: "no va" son 5 y es un reporte legitimo. El minimo NO
  -- esta para exigir calidad —la calidad la pone el contexto que el sistema
  -- captura solo— sino para frenar el toque accidental.
  -- El `coalesce` no es decorativo aunque la columna sea NOT NULL: es la misma
  -- forma que D3-bis caza en `ent_devolucion`, donde sin el la conjuncion
  -- queda NULL y Postgres DEJA PASAR la fila. Medido el 17-sep: el DETAIL
  -- mostro `nota = null` y el CHECK igual rebato. Se escribe asi siempre.
  constraint ticket_descripcion_ok
    check (length(btrim(coalesce(descripcion,''))) >= 5),

  --   no_funciona → "Algo no funciona"
  --   duda        → "Tengo una duda"
  --   idea        → "Se me ocurrió algo"
  --   encargo     → trabajo pedido, no un hallazgo
  --
  -- ⚠️ 'encargo' ES UN TIPO Y NO UN ESTADO, por decision de Andrea el 17-sep.
  -- El backlog de referencia lo tenia como estado, y ahi se pierde: un encargo
  -- EN CURSO dejaria de ser un encargo. El tipo dice QUE es; el estado dice
  -- DONDE esta. Son ejes distintos y no se mezclan.
  constraint ticket_tipo_ok
    check (tipo in ('no_funciona','duda','idea','encargo')),

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
  -- `creado_en` es timestamptz: guarda el INSTANTE, en UTC, y PIERDE la zona
  -- de quien reporto. Hoy casi no muerde porque Costa Rica es UTC−6 fijo. Pero
  -- el dia que el iPad tenga la zona mal —que es la clase de bug que un ticket
  -- vendria a reportar— el dato que lo probaria no estaria.
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
  'Un hallazgo o un encargo. Append-only: no se edita. Estado, triaje, detalle '
  'y fotos viven en tablas de eventos.';

-- ⚠️ `build` SOLO NO ALCANZA. Un sello como 'b61' puede significar dos cosas:
-- lo que hay en main y lo que hay en una rama sin publicar. `doc_modificado`
-- es `document.lastModified`: la fecha del archivo QUE EL APARATO TIENE
-- CARGADO, no la que el servidor sirve ahora. Es lo unico que distingue dos
-- builds con el mismo sello. `standalone` va por lo mismo: el icono de iOS
-- retiene la version vieja dias (medido el 8-sep con el pedido 46).
-- `vista` y `miga` van LOS DOS: `vista` dice `vReporte`, que a Andrea no le
-- dice nada; `miga` dice "Entregas · Sin factura", que no sirve para buscar en
-- el codigo. Cada uno contesta una pregunta distinta.

-- La firma no se elige: tiene que ser quien esta adentro.
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
-- ── EL MAPA · adentro / en pantalla / quien lo pone ─────────────────────
--   (sin eventos)   "Sin triar"      nadie: es la AUSENCIA de eventos
--   disponible      "Disponible"     Andrea
--   bloqueado       "Bloqueado"      Andrea
--   en_curso        "En curso"       CC   (toma el trabajo)
--   en_validacion   "En validación"  CC   (lo deja terminado)
--   cerrado         "Cerrado"        Andrea
--   pospuesto       "Pospuesto"      Andrea
--   descartado      "Descartado"     Andrea
--
-- 🔴 'Sin triar' NO SE INSERTA NUNCA. Es la ausencia de eventos, y la vista lo
-- resuelve con un coalesce. Eso hace LITERAL la regla de que **quien reporta
-- no escribe una sola fila de estado**: Daniel manda su ticket y no toca esta
-- tabla ni para abrirlo. Un estado inicial insertado seria una excepcion a la
-- regla escrita adentro de la regla misma.
-- Y de paso, el contador de "Sin triar" ES la cola de Andrea: lo que llego y
-- nadie miro todavia.
create table if not exists ticket_estado (
  id          bigint generated always as identity primary key,
  ticket_id   bigint not null references ticket(id),
  estado      text   not null,
  constraint ticket_estado_ok check (estado in
    ('disponible','bloqueado','en_curso','en_validacion',
     'cerrado','pospuesto','descartado')),

  nota        text,

  -- ── LAS DEPENDENCIAS · que lo bloquea ────────────────────────────────
  -- ⚠️ "Bloqueado" sin decir QUE lo bloquea no sirve para nada: la lista de
  -- bloqueados se vuelve un cajon y nadie sabe que destrabar. Y sin esto,
  -- "Recien desbloqueado" no se puede calcular.
  -- Casos reales esperando: el ticket de las tres salidas sin registrar
  -- ("no se puede trabajar hasta que salga el Bloque 3.2/3.3") y §25, aplazado
  -- con su razon escrita.
  --
  -- DOS FORMAS, y al menos una es obligatoria cuando el estado es 'bloqueado':
  --   · `bloquea_ticket_id` — lo bloquea OTRO TICKET. Es la buena: cuando ese
  --     se cierra, se sabe a quien destrabar.
  --   · `espera` — lo bloquea algo de afuera, en palabras. Una decision de
  --     Andrea, un dato de Odoo, una respuesta de alguien.
  bloquea_ticket_id bigint references ticket(id),
  espera            text,

  -- ⚠️ LIMITE ESCRITO A PROPOSITO: un evento guarda UN bloqueo, no varios. Si
  -- un ticket espera dos cosas, se anota la que de verdad lo frena, y cuando
  -- esa se levanta se vuelve a bloquear con la otra. Modelar N bloqueos
  -- complicaria "cual es el estado de hoy" para un caso que todavia no
  -- aparecio. Si aparece, esto se relee.
  constraint ticket_estado_bloqueo_ok check (
    estado <> 'bloqueado'
    or bloquea_ticket_id is not null
    or length(btrim(coalesce(espera,''))) >= 8),
  -- Un ticket no se bloquea a si mismo. Ciclos mas largos (A espera a B, B
  -- espera a A) NO se detectan acá: seria un trigger recursivo por una vuelta
  -- que nunca paso. Queda escrito para que nadie crea que esta cubierto.
  constraint ticket_estado_no_autobloqueo check (
    bloquea_ticket_id is null or bloquea_ticket_id <> ticket_id),
  -- Y lo que bloquea solo tiene sentido si esta bloqueado.
  constraint ticket_estado_bloqueo_limpio check (
    estado = 'bloqueado' or (bloquea_ticket_id is null and espera is null)),

  -- ── LOS DOS BUILDS, Y NO SON EL MISMO ────────────────────────────────
  -- `build_al_marcar` · QUE ESTABA CORRIENDO quien toco el boton. Lo pone la
  --   app sola. Caza el caso feo: mover un ticket desde un aparato que todavia
  --   tiene la version vieja cargada. NO es donde salio el arreglo.
  -- `build_arreglo`   · DONDE SALIO EL ARREGLO. Se escribe al PUBLICAR, no al
  --   marcar, y lo escribe el ritual de cierre (§12). Queda NULL hasta
  --   entonces, y NULL se muestra como "no consta" — nunca se rellena con una
  --   suposicion. Misma regla que 'migrado · sin build'.
  build_al_marcar  text,
  build_arreglo    text,

  creado_en   timestamptz not null default now(),
  creado_por  text   not null,

  -- Dejar algo "En validación" sin decir QUE se hizo es tirarle el trabajo a
  -- Andrea para que lo adivine. Mismo criterio para "Descartado": descartar
  -- sin razon escrita es lo que hace que seis meses despues nadie sepa por que.
  constraint ticket_estado_nota_ok check (
    estado not in ('en_validacion','descartado','pospuesto')
    or length(btrim(coalesce(nota,''))) >= 20)
);
create index if not exists ticket_estado_idx
  on ticket_estado (ticket_id, creado_en desc);
create index if not exists ticket_estado_bloquea_idx
  on ticket_estado (bloquea_ticket_id) where bloquea_ticket_id is not null;

-- ── EL GUARDIA ───────────────────────────────────────────────────────────
-- 🔴 LEER EL ENCABEZADO DEL ARCHIVO ANTES DE TOCAR ESTO. Resumen: el camino
--    del SQL Editor NO ESTA PROTEGIDO por este trigger, porque el trigger no
--    puede saber quien escribe — solo comprueba que la firma empiece con
--    `cc-sql`. Eso es una CONVENCION para que la fila diga de donde vino. La
--    proteccion real es la RLS del §8, y cubre la app.
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
    -- CC toma trabajo y lo deja. No tria y no cierra: eso es de Andrea.
    if new.estado not in ('en_curso','en_validacion') then
      raise exception 'desde el SQL Editor solo se puede poner en_curso o en_validacion. '
        'Triar (disponible/bloqueado) y cerrar (cerrado/pospuesto/descartado) es de las '
        'socias, y desde acá no se sabe cuál socia es. Vino: %', new.estado;
    end if;
    return new;
  end if;

  -- ── EL CAMINO DE LA APP · con sesion ──────────────────────────────────
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

drop trigger if exists ticket_estado_guard_trg on ticket_estado;
create trigger ticket_estado_guard_trg before insert on ticket_estado
  for each row execute function ticket_estado_guard();


-- ════════════════════════════════════════════════════════════════════════
-- 3 · EL TRIAJE · lo que Andrea decide cuando lo mira
-- ════════════════════════════════════════════════════════════════════════
-- Append-only: la ultima fila por ticket es la que vale. Es UN evento y no
-- columnas del ticket, por dos razones y las dos pesan:
--   1. Daniel NO PUEDE poner nada de esto. No sabe si algo toca numeros — por
--      eso lo esta reportando. Nace cuando Andrea lo mira, despues.
--   2. Si fueran columnas de `ticket`, ponerlas seria un UPDATE y el ticket
--      dejaria de ser append-only.
-- Van las cuatro decisiones juntas porque se toman en el mismo momento: Andrea
-- abre el ticket, lo entiende, y decide las cuatro de una sentada.
create table if not exists ticket_marca (
  id               bigint generated always as identity primary key,
  ticket_id        bigint not null references ticket(id),

  -- ── LA MARCA QUE VUELVE AUTOMATIZABLE AL MODULO ──────────────────────
  -- LA REGLA DE DONDE SALE (14-sep): §17, §18 y §19 los puede tomar un
  -- agente; §20 no, aunque parezca del mismo tamaño. Y medido el 17-sep
  -- contra `ENTREGAS_PENDIENTES.md`, la regla se explica sola: §17 es una
  -- columna en unidades individuales, §18 una columna que se sale de pantalla
  -- en iPhone, §19 un encabezado que dice "solo lectura" — los tres de
  -- PANTALLA. §20 es "el factor caja→unidad vive DOS VECES": toca numeros.
  --
  -- SON DOS PREGUNTAS Y SE GUARDAN SEPARADAS. "No lo puede tomar un agente" es
  -- una conclusion; estos dos son los hechos de los que sale. Guardar solo la
  -- conclusion obliga a re-preguntar el porque cada vez, y el porque es lo
  -- primero que se pierde.
  toca_numeros     boolean not null,   -- ¿el arreglo cambia un calculo, un saldo, un costo?
  escribe_en_base  boolean not null,   -- ¿el arreglo escribe en Supabase o en Odoo?

  -- ── LAS ETIQUETAS ────────────────────────────────────────────────────
  -- prioridad: alta ≈ 🔴 · media ≈ 🟠 · baja. Se usan los mismos tres niveles
  -- que el repo ya usa en prosa, para no inventar una escala nueva.
  prioridad        text not null,
  constraint ticket_marca_prioridad_ok check (prioridad in ('alta','media','baja')),

  -- La etiqueta que marca lo que frena una ENTREGA. Es distinta de la
  -- prioridad a proposito: algo puede ser de prioridad media y aun asi estar
  -- trabando una entrega concreta de esta semana.
  bloquea_entrega  boolean not null default false,

  -- Un triaje sin razon escrita es mover una ficha.
  razon            text not null,
  constraint ticket_marca_razon_ok
    check (length(btrim(coalesce(razon,''))) >= 12),

  creado_en        timestamptz not null default now(),
  creado_por       text not null
);
create index if not exists ticket_marca_idx
  on ticket_marca (ticket_id, creado_en desc);

comment on table ticket_marca is
  'El triaje: si un agente puede tomarlo, con que prioridad, y si frena una '
  'entrega. Append-only, la ultima fila manda. La pone una socia.';

-- Triar es decidir, y decidir es de las socias. Ni siquiera por SQL Editor:
-- ahi no se sabe quien escribe, y el triaje es justamente un juicio.
create or replace function ticket_marca_guard()
returns trigger language plpgsql as $guard$
declare quien text; socia boolean;
begin
  if not exists (select 1 from ticket t where t.id = new.ticket_id) then
    raise exception 'no existe el ticket %', new.ticket_id;
  end if;
  quien := nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email';
  if quien is null then
    raise exception 'triar un ticket es de las socias y desde el SQL Editor no se sabe '
      'quien esta escribiendo. Se hace desde la pantalla, con sesion.';
  end if;
  if lower(btrim(new.creado_por)) <> lower(btrim(quien)) then
    raise exception 'creado_por dice % y la sesion es de %. La firma no se elige.',
      new.creado_por, quien;
  end if;
  socia := exists (select 1 from acceso_usuario a
                    where lower(a.email) = lower(quien)
                      and a.perfil = 'socias' and a.activo);
  if not socia then
    raise exception 'triar un ticket es de un perfil socias, y % no lo es.', quien;
  end if;
  return new;
end
$guard$;

drop trigger if exists ticket_marca_guard_trg on ticket_marca;
create trigger ticket_marca_guard_trg before insert on ticket_marca
  for each row execute function ticket_marca_guard();


-- ════════════════════════════════════════════════════════════════════════
-- 4 · LA ESTRUCTURA · qué se espera, criterio de terminado, cierres, anuncios
-- ════════════════════════════════════════════════════════════════════════
-- Las cuatro piezas que el backlog de referencia resuelve y acá faltaban.
-- Van como FILAS HIJAS y no como columnas de `ticket`, por el mismo argumento
-- que el triaje: **Daniel no escribe el criterio de terminado**. Lo escribe
-- quien tria, despues, y se puede revisar. Una columna obligaria a un UPDATE.
--
-- ── LAS CUATRO CLASES, y no se comportan igual ──────────────────────────
--   espera    "Qué se espera"          DEFINICION · la ultima fila manda
--   criterio  "Criterio de terminado"  DEFINICION · la ultima fila manda
--   cierre    "Cierres"                BITACORA   · se muestran todas
--   anuncio   "Anuncios de sesión"     BITACORA   · se muestran todas
--
-- 🔴 `criterio` ES LA PIEZA QUE MAS FALTABA. Hoy no esta escrito cuando algo
-- esta listo, y por eso se discute AL FINAL, que es el peor momento: el
-- trabajo ya se hizo y discutir el criterio se siente como mover el arco.
-- Escrito antes, "En validación" deja de ser una opinion.
create table if not exists ticket_detalle (
  id          bigint generated always as identity primary key,
  ticket_id   bigint not null references ticket(id),
  clase       text   not null,
  constraint ticket_detalle_clase_ok
    check (clase in ('espera','criterio','cierre','anuncio')),

  texto       text   not null,
  constraint ticket_detalle_texto_ok
    check (length(btrim(coalesce(texto,''))) >= 10),

  creado_en   timestamptz not null default now(),
  creado_por  text   not null
);
create index if not exists ticket_detalle_idx
  on ticket_detalle (ticket_id, clase, creado_en desc);

-- ── QUIEN ESCRIBE QUE ───────────────────────────────────────────────────
-- socias  · espera, criterio      (la definicion del trabajo)
-- CC      · cierre, anuncio       (lo que hizo y lo que encontro)
--
-- ⚠️ POR QUE CC NO ESCRIBE EL CRITERIO, aunque seria comodo: el criterio de
--    terminado es el CONTRATO. Si el mismo lado que lo escribe es el que lo
--    cumple, deja de ser un control y pasa a ser una descripcion de lo que se
--    hizo. Es exactamente lo que el criterio viene a impedir.
--    Si Andrea prefiere que CC lo redacte y ella lo apruebe, es agregar
--    'criterio' a la lista de abajo — una linea. Queda escrito que se eligio
--    al reves a proposito, y no por olvido.
create or replace function ticket_detalle_guard()
returns trigger language plpgsql as $guard$
declare quien text; socia boolean;
begin
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
$guard$;

drop trigger if exists ticket_detalle_guard_trg on ticket_detalle;
create trigger ticket_detalle_guard_trg before insert on ticket_detalle
  for each row execute function ticket_detalle_guard();


-- ════════════════════════════════════════════════════════════════════════
-- 5 · LA FOTO · una fila por INTENTO, no una fila por archivo
-- ════════════════════════════════════════════════════════════════════════
-- Sale de una leccion medida el 17-sep: en Devoluciones un guardado fallaba EN
-- SILENCIO. Acá el silencio tendria esta forma: Andrea abre un ticket, no ve
-- foto, y no puede saber si Daniel no saco ninguna o si la subida se perdio.
--
--   filas del ticket            significa
--   ─────────────────────────   ────────────────────────────────────────────
--   ninguna                     no se adjunto foto. Es normal.
--   'intento' y nada mas        se empezo a subir y NO SE SUPO COMO TERMINO.
--   'intento' + 'fallo'         se intento y fallo, con el error guardado.
--   'intento' + 'subida'        esta la foto.
--
-- ⚠️ EL ORDEN NO ES CAPRICHO: la fila 'intento' se escribe ANTES de empezar a
-- subir, mientras la red todavia funciona —lo sabemos porque el ticket acaba
-- de entrar—. Si se escribiera despues, registrar el fallo necesitaria red
-- para registrar que no habia red.
create table if not exists ticket_foto (
  id          bigint generated always as identity primary key,
  ticket_id   bigint not null references ticket(id),
  resultado   text   not null check (resultado in ('intento','subida','fallo')),

  ruta        text,               -- '{ticket_id}/{uuid}.{ext}' — solo si subio
  mime        text,
  bytes       bigint,
  error       text,               -- lo que devolvio Storage — solo si fallo

  creado_en   timestamptz not null default now(),
  creado_por  text   not null,

  constraint ticket_foto_subida_ok check (
    resultado <> 'subida' or length(btrim(coalesce(ruta,''))) > 0),
  constraint ticket_foto_fallo_ok check (
    resultado <> 'fallo'  or length(btrim(coalesce(error,''))) >= 3)
);
create index if not exists ticket_foto_idx on ticket_foto (ticket_id, creado_en);
-- Indice PARCIAL: 'intento' y 'fallo' no tienen ruta. Un unique comun dejaria
-- pasar los NULL igual, pero sin decir que eso fue a proposito.
create unique index if not exists ticket_foto_ruta_uq
  on ticket_foto (ruta) where ruta is not null;


-- ════════════════════════════════════════════════════════════════════════
-- 6 · LAS VISTAS
-- ════════════════════════════════════════════════════════════════════════
-- security_invoker en TODAS: es la regla del modulo desde la fuga del 24-ago,
-- cuando `v_acceso_usuario` le devolvia cinco correos a la anon key.

create or replace view v_ticket_foto with (security_invoker = true) as
  select f.ticket_id,
         case
           when bool_or(f.resultado = 'subida') then 'ok'
           when bool_or(f.resultado = 'fallo')  then 'perdida'
           else 'sin_respuesta'                 -- quedo en 'intento' y nunca cerro
         end                                               as estado_foto,
         count(*) filter (where f.resultado = 'subida')    as fotos,
         max(f.error) filter (where f.resultado = 'fallo') as ultimo_error
    from ticket_foto f
   group by f.ticket_id;

-- ── "RECIEN DESBLOQUEADO" · DERIVADO, NUNCA GUARDADO ────────────────────
-- Es "el estado de hoy es Disponible, el anterior era Bloqueado, y paso hace
-- poco". Guardarlo como bandera obligaria a que alguien la apague, y nadie
-- apaga banderas: a la semana media lista estaria "recien" desbloqueada.
--
-- ⚠️ Y VA EN SU PROPIA VISTA POR UNA RAZON QUE CUESTA VER: para saber el
-- estado ANTERIOR hacen falta DOS filas. Un `lag(...) over (...)` adentro de
-- un lateral con `limit 1` **devuelve NULL siempre** — la ventana corre sobre
-- una sola fila. Parece que anda y no anda nunca. Por eso se numeran todas las
-- filas del ticket y despues se toma la ultima, en vez de recortar primero.
create or replace view v_ticket_desbloqueo with (security_invoker = true) as
  select z.ticket_id,
         (z.estado = 'disponible' and z.previo = 'bloqueado'
          and z.creado_en > now() - interval '7 days')  as recien_desbloqueado,
         z.previo                                       as estado_anterior,
         z.creado_en                                    as ultimo_cambio_en
    from (
      select x.ticket_id, x.estado, x.creado_en,
             lag(x.estado) over (partition by x.ticket_id order by x.creado_en) as previo,
             row_number() over (partition by x.ticket_id order by x.creado_en desc) as rn
        from ticket_estado x) z
   where z.rn = 1;

create or replace view v_ticket with (security_invoker = true) as
  select t.id,
         t.descripcion, t.tipo,
         t.build, t.doc_modificado, t.vista, t.miga, t.modulo, t.sobre,
         t.agente, t.standalone, t.viewport,
         t.tz_offset_min, t.tz_nombre,
         t.creado_en, t.creado_por,

         -- Sin eventos, "Sin triar". Es la cola de Andrea.
         coalesce(e.estado, 'sin_triar')        as estado,
         e.nota                                 as ultima_nota,
         e.creado_en                            as estado_en,
         e.creado_por                           as estado_por,
         e.build_arreglo,
         e.bloquea_ticket_id,
         e.espera,

         coalesce(des.recien_desbloqueado, false) as recien_desbloqueado,
         des.estado_anterior,

         -- El triaje. `agente_puede` es DERIVADA: guardar una conclusion al
         -- lado de sus premisas es pedir que algun dia se contradigan.
         m.toca_numeros,
         m.escribe_en_base,
         (m.toca_numeros is not null
            and not m.toca_numeros and not m.escribe_en_base) as agente_puede,
         m.prioridad,
         m.bloquea_entrega,
         m.razon                                as marca_razon,
         m.creado_por                           as marca_por,

         -- Las dos definiciones: la ultima fila de cada clase manda.
         d_esp.texto                            as que_se_espera,
         d_cri.texto                            as criterio_terminado,

         coalesce(f.estado_foto, 'sin_foto')    as estado_foto,
         coalesce(f.fotos, 0)                   as fotos,
         f.ultimo_error                         as foto_error
    from ticket t
    left join lateral (
      select x.estado, x.nota, x.creado_en, x.creado_por, x.build_arreglo,
             x.bloquea_ticket_id, x.espera
        from ticket_estado x
       where x.ticket_id = t.id
       order by x.creado_en desc
       limit 1) e on true
    left join v_ticket_desbloqueo des on des.ticket_id = t.id
    left join lateral (
      select x.toca_numeros, x.escribe_en_base, x.prioridad, x.bloquea_entrega,
             x.razon, x.creado_por
        from ticket_marca x
       where x.ticket_id = t.id
       order by x.creado_en desc
       limit 1) m on true
    left join lateral (
      select x.texto from ticket_detalle x
       where x.ticket_id = t.id and x.clase = 'espera'
       order by x.creado_en desc limit 1) d_esp on true
    left join lateral (
      select x.texto from ticket_detalle x
       where x.ticket_id = t.id and x.clase = 'criterio'
       order by x.creado_en desc limit 1) d_cri on true
    left join v_ticket_foto f on f.ticket_id = t.id;

-- ── LO QUE CC PUEDE TOMAR ───────────────────────────────────────────────
-- Es la lista CORTA, y es el punto entero de separar Bloqueado de Disponible:
-- acá solo esta lo que se puede agarrar hoy. La marca es el porton.
create or replace view v_ticket_disponible with (security_invoker = true) as
  select * from v_ticket
   where estado = 'disponible'
     and agente_puede
   order by (prioridad = 'alta') desc, bloquea_entrega desc, creado_en;

-- Lo que espera a ANDREA: lo que llego y nadie miro, y lo que CC dejo listo.
create or replace view v_ticket_para_andrea with (security_invoker = true) as
  select * from v_ticket
   where estado in ('sin_triar','en_validacion')
   order by (estado = 'en_validacion') desc, creado_en;

-- El contador de la tarjeta del lobby: una fila por modulo, una columna por
-- estado. "Sin triar" incluido, que es la cola de Andrea.
create or replace view v_ticket_conteo with (security_invoker = true) as
  select coalesce(modulo, 'sin_modulo')                   as modulo,
         count(*) filter (where estado = 'sin_triar')     as sin_triar,
         count(*) filter (where estado = 'disponible')    as disponible,
         count(*) filter (where estado = 'bloqueado')     as bloqueado,
         count(*) filter (where estado = 'en_curso')      as en_curso,
         count(*) filter (where estado = 'en_validacion') as en_validacion,
         count(*) filter (where estado = 'cerrado')       as cerrado,
         count(*) filter (where estado = 'pospuesto')     as pospuesto,
         count(*) filter (where estado = 'descartado')    as descartado
    from v_ticket
   group by coalesce(modulo, 'sin_modulo');

-- Quien bloquea a quien. Cuando un ticket se cierra, esta vista dice a quien
-- hay que destrabar — que es lo que hace util al modelo de dependencias en vez
-- de un cajon de bloqueados que nadie revisa.
create or replace view v_ticket_bloqueos with (security_invoker = true) as
  select v.id                as ticket_id,
         v.bloquea_ticket_id as lo_bloquea,
         b.estado            as estado_del_que_bloquea,
         v.espera
    from v_ticket v
    left join v_ticket b on b.id = v.bloquea_ticket_id
   where v.estado = 'bloqueado';


-- ════════════════════════════════════════════════════════════════════════
-- 7 · LA SALIDA AL REPO · un archivo por ticket
-- ════════════════════════════════════════════════════════════════════════
-- El circuito: Daniel reporta → Andrea tria → CC lo toma de acá. Sin que nadie
-- lo reescriba.
--
-- ⚠️ LA BASE DE DATOS NO ESCRIBE ARCHIVOS. Esta vista arma el TEXTO; alguien
-- tiene que venir a buscarlo y escribirlo en disco. Ese alguien es una
-- herramienta chica que todavia no existe — y cuando exista va a ser SOLO
-- LECTURA contra Supabase (`pg_lector.py` sirve tal como esta). Decirlo de
-- otra forma seria prometer algo que este archivo no hace.
--
-- POR QUE UNA VISTA Y NO UN CAMPO: el contenido se DERIVA del ticket y sus
-- eventos. Guardarlo seria una copia que se desincroniza al primer cierre
-- nuevo, y despues nadie sabe cual de las dos manda.
create or replace view v_ticket_export with (security_invoker = true) as
  select t.id,
         'tickets/T-' || lpad(t.id::text, 4, '0') || '.md'          as archivo,
         concat_ws(E'\n',
           '# T-' || lpad(t.id::text, 4, '0') || ' · ' ||
             case t.tipo when 'no_funciona' then 'Algo no funciona'
                         when 'duda'        then 'Tengo una duda'
                         when 'encargo'     then 'Encargo'
                         else                    'Se me ocurrió algo' end,
           '',
           '> **Estado:** ' ||
             case t.estado when 'sin_triar'     then 'Sin triar'
                           when 'disponible'    then 'Disponible'
                           when 'bloqueado'     then 'Bloqueado'
                           when 'en_curso'      then 'En curso'
                           when 'en_validacion' then 'En validación'
                           when 'cerrado'       then 'Cerrado'
                           when 'pospuesto'     then 'Pospuesto'
                           else                      'Descartado' end ||
             coalesce('  ·  **Prioridad:** ' || t.prioridad, '') ||
             case when t.bloquea_entrega then '  ·  ⚠️ **bloquea una entrega**' else '' end ||
             case when t.recien_desbloqueado then '  ·  🆕 **recién desbloqueado**' else '' end,
           '> **Reportó:** ' || t.creado_por ||
             '  ·  **Cuándo:** ' || to_char(t.creado_en, 'YYYY-MM-DD HH24:MI') ||
             coalesce(' (' || t.tz_nombre || ')', ''),
           '',
           '## Qué pasa',
           '',
           t.descripcion,
           '',
           case when t.que_se_espera is null then ''
                else '## Qué se espera' || E'\n\n' || t.que_se_espera || E'\n' end,
           case when t.criterio_terminado is null
                then '## Criterio de terminado' || E'\n\n' ||
                     '_Sin escribir. **Hasta que exista, esto no se toma**: sin criterio, '
                     '"terminado" se discute al final._' || E'\n'
                else '## Criterio de terminado' || E'\n\n' || t.criterio_terminado || E'\n' end,
           case when t.estado <> 'bloqueado' then ''
                else '## Bloqueado por' || E'\n\n' ||
                     coalesce('T-' || lpad(t.bloquea_ticket_id::text, 4, '0'), t.espera, '—')
                     || E'\n' end,
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
             '_Sin triar. Hasta que una socia lo mire, **un agente no lo toma**._'
           else
             '- ¿Toca números? **' || case when t.toca_numeros then 'Sí' else 'No' end || '**' ||
             E'\n' ||
             '- ¿Escribe en la base? **' || case when t.escribe_en_base then 'Sí' else 'No' end || '**' ||
             E'\n' ||
             '- ➡️ **' || case when t.agente_puede
                                then 'Un agente puede tomarlo.'
                                else 'Un agente NO lo toma.' end || '**' ||
             E'\n\n' || '> ' || t.marca_razon || '  — ' || coalesce(t.marca_por,'')
           end,
           '',
           coalesce((select E'## Cierres\n\n' || string_agg(
                       '- ' || to_char(d.creado_en,'YYYY-MM-DD') || ' · ' || d.texto,
                       E'\n' order by d.creado_en)
                       from ticket_detalle d
                      where d.ticket_id = t.id and d.clase = 'cierre'), ''),
           '',
           coalesce((select E'## Anuncios de sesión\n\n' || string_agg(
                       '- ' || to_char(d.creado_en,'YYYY-MM-DD') || ' · ' || d.texto,
                       E'\n' order by d.creado_en)
                       from ticket_detalle d
                      where d.ticket_id = t.id and d.clase = 'anuncio'), '')
         )                                                          as contenido
    from v_ticket t;


-- ════════════════════════════════════════════════════════════════════════
-- 8 · RLS · acá es donde las garantias son garantias
-- ════════════════════════════════════════════════════════════════════════
alter table ticket         enable row level security;
alter table ticket_estado  enable row level security;
alter table ticket_marca   enable row level security;
alter table ticket_detalle enable row level security;
alter table ticket_foto    enable row level security;

drop policy if exists ticket_sel on ticket;
drop policy if exists ticket_ins on ticket;
drop policy if exists ticket_estado_sel on ticket_estado;
drop policy if exists ticket_estado_ins on ticket_estado;
drop policy if exists ticket_marca_sel on ticket_marca;
drop policy if exists ticket_marca_ins on ticket_marca;
drop policy if exists ticket_detalle_sel on ticket_detalle;
drop policy if exists ticket_detalle_ins on ticket_detalle;
drop policy if exists ticket_foto_sel on ticket_foto;
drop policy if exists ticket_foto_ins on ticket_foto;

-- ── VER · TODO EL EQUIPO VE TODOS LOS TICKETS ───────────────────────────
-- ⚠️ DECISION DE ANDREA, REVISADA Y RATIFICADA EL 17-sep. Llego a pedir "cada
-- uno ve los suyos" y lo revirtio ella misma: *un ticket no tiene nada
-- privado, y el duplicado si cuesta — si Daniel ve que alguien ya reporto lo
-- mismo, no lo reporta dos veces*. Queda escrito para que a nadie le parezca
-- un descuido y lo "arregle". La FOTO es otra cosa: ver §9.
create policy ticket_sel on ticket
  for select to authenticated using (true);

-- REPORTAR ES DE TODOS: Daniel, el equipo y las socias, sin distincion.
-- El `true` no es flojera: el trigger del §1 ata la firma a la sesion, que es
-- la unica restriccion con sentido acá.
create policy ticket_ins on ticket
  for insert to authenticated with check (true);

create policy ticket_estado_sel on ticket_estado
  for select to authenticated using (true);

-- 🔴 MOVER EL ESTADO · SOLO SOCIAS, EN LA BASE.
-- Es la leccion del 17-sep: ese dia se midio que `ent_anulacion_ins` decia
-- `with check (true)` mientras la pantalla decia "solo socias" — y se
-- comprobo EN VIVO que una usuaria sin perfil de socia podia insertar. Una
-- garantia de pantalla no es una garantia.
-- ⚠️ Y otra vez: esto cubre la APP. El SQL Editor entra como `postgres` y pasa
--    la RLS de largo; ahi manda el trigger, que NO puede verificar quien es CC.
create policy ticket_estado_ins on ticket_estado
  for insert to authenticated with check (acceso_es_socia());

create policy ticket_marca_sel on ticket_marca
  for select to authenticated using (true);

-- Triar es decidir. Mismo criterio, misma linea.
create policy ticket_marca_ins on ticket_marca
  for insert to authenticated with check (acceso_es_socia());

create policy ticket_detalle_sel on ticket_detalle
  for select to authenticated using (true);

-- Desde la app, escribir detalle es de socias. El trigger del §4 afina cual
-- clase puede escribir cada camino.
create policy ticket_detalle_ins on ticket_detalle
  for insert to authenticated with check (acceso_es_socia());

-- La FILA de la foto (que existe, cuanto peso, si fallo) la ve todo el equipo:
-- es metadato y sirve para saber que una subida se perdio. El ARCHIVO tiene su
-- propia politica, mas estricta, en §9. No es incoherencia: son dos cosas con
-- sensibilidad distinta.
create policy ticket_foto_sel on ticket_foto
  for select to authenticated using (true);

-- Adjuntar: a un ticket propio, o cualquiera si es socia. Espeja la politica
-- de Storage del §9 — si las dos no dicen lo mismo, una de las dos miente.
create policy ticket_foto_ins on ticket_foto
  for insert to authenticated with check (
    acceso_es_socia()
    or exists (select 1 from ticket t
                where t.id = ticket_id
                  and lower(t.creado_por) = lower(coalesce(auth.jwt() ->> 'email',''))));

-- Sin update ni delete en las cinco: append-only se niega por AUSENCIA de
-- politica. No hay que escribir nada para prohibirlo.
-- ⚠️ Pero SI hay que revocar lo que Supabase regala: por privilegios por
-- defecto sobre `public`, `anon` y `authenticated` reciben update y delete
-- igual. Hoy la RLS los contiene, pero el grant sobra y se mide como sobrante.
-- Es el hallazgo V4=12 del 16-sep.
revoke all on ticket, ticket_estado, ticket_marca, ticket_detalle, ticket_foto from anon;
revoke update, delete, truncate
  on ticket, ticket_estado, ticket_marca, ticket_detalle, ticket_foto
  from authenticated;

grant select, insert on ticket         to authenticated;
grant select, insert on ticket_estado  to authenticated;
grant select, insert on ticket_marca   to authenticated;
grant select, insert on ticket_detalle to authenticated;
grant select, insert on ticket_foto    to authenticated;
grant select on v_ticket, v_ticket_foto, v_ticket_desbloqueo, v_ticket_disponible,
                v_ticket_para_andrea, v_ticket_conteo, v_ticket_bloqueos,
                v_ticket_export to authenticated;


-- ════════════════════════════════════════════════════════════════════════
-- 9 · EL BUCKET · privado, y la parte que hay que mirar dos veces
-- ════════════════════════════════════════════════════════════════════════
-- Un screenshot de Truefie puede tener clientes, facturas y cantidades. Y si
-- se saca desde Personal, puede tener un salario o una nota medica. Eso ultimo
-- decide la politica de LECTURA de abajo.
--
-- ── LA DECISION SOBRE HEIC ──────────────────────────────────────────────
-- **Se convierte a JPEG en el navegador ANTES de subir. HEIC queda permitido
--   solo como red, no como camino normal.**
--   1. Si la foto no se puede VER, no sirve. HEIC no se muestra en un <img> en
--      Chrome ni en Firefox, y Andrea abre el ticket desde donde este.
--   2. La foto es para DIAGNOSTICAR, no para archivar: la fidelidad no entra.
--   3. Pesa menos, y menos peso es menos subida fallida con señal mala.
--   4. Convertir por canvas TIRA EL EXIF, y con el la ubicacion GPS.
-- Dato que achica el problema: **las capturas de iOS son PNG**, no HEIC. HEIC
-- solo aparece si Daniel FOTOGRAFIA algo fisico.
-- ⚠️ NO MEDIDO: que entrega iOS exactamente al elegir una foto con
--    <input type="file" accept="image/*">. Es conocimiento general, no una
--    medicion en el iPad. Por eso HEIC se queda permitido: si la conversion
--    falla, se sube el original y se guarda el mime real, en vez de perder la
--    foto por una suposicion.
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
-- en `storage.objects.bucket_id` y `name` guarda SOLO la ruta interna: para
-- 'tickets' + '12/ab.png' el `name` es '12/ab.png' y foldername devuelve {12}.
-- El ticket_id es el [1], no el [2]. Escribirlo mal NO DA ERROR: da una
-- politica que compara contra el segmento equivocado y deja de proteger EN
-- SILENCIO.
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

create policy tickets_ins on storage.objects
  for insert to authenticated
  with check (bucket_id = 'tickets'
              and (acceso_es_socia() or ticket_es_mio(name)));

-- ⚠️ VER: LA FOTO PROPIA, O TODO SI ES SOCIA. Y NO "todo el equipo".
-- Se separa a proposito de la politica de la TABLA: el TEXTO de un ticket lo
-- escribe alguien que sabe lo que esta escribiendo; la FOTO se saca de la
-- pantalla que estaba abierta, y esa pantalla puede ser Personal. Si la
-- lectura del archivo fuera "todo el equipo", un ticket abierto desde Personal
-- le abriria a Daniel un dato que hoy no ve.
create policy tickets_sel on storage.objects
  for select to authenticated
  using (bucket_id = 'tickets'
         and (acceso_es_socia() or ticket_es_mio(name)));

-- Sin update ni delete: append-only. Una foto que no sirve se reemplaza
-- subiendo otra, no borrando la primera.


-- ════════════════════════════════════════════════════════════════════════
-- 10 · LO QUE TIENE QUE HACER ANDREA, Y COMPROBAR DESPUES
-- ════════════════════════════════════════════════════════════════════════
-- ⚠️ Este archivo NO abre una transaccion unica a proposito: son muchos
--    objetos y conviene pegarlo por secciones, mirando cada una. Pero entonces
--    la verificacion de abajo NO ES OPCIONAL: sin ella, un "Success. No rows
--    returned" no prueba nada. Es la leccion del 16-sep, cuando el primer
--    pegado de CAMBIO_DEVOLUCIONES no aplico NADA y dijo exactamente eso.
--
-- 1) Storage → Buckets. Si despues de pegar falta `tickets`, el insert no tuvo
--    permisos: crealo a mano. Public bucket DESMARCADO, 10 MB, los cinco MIME.
--    Y volve a pegar el §9 para que queden las politicas.

-- V1 · Las tablas. ESPERADO: 6 (las cinco del ticket + build_publicado).
select count(*) as tablas_debe_ser_6
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r'
   and c.relname in ('ticket','ticket_estado','ticket_marca','ticket_detalle',
                     'ticket_foto','build_publicado');

-- V2 · Las vistas, TODAS con security_invoker. ESPERADO: 9 filas, las nueve
--      en `t`. Una vista sin la opcion es la fuga del 24-ago otra vez.
select c.relname,
       coalesce((select option_value from pg_options_to_table(c.reloptions)
                  where option_name = 'security_invoker'), 'NO LA TIENE') as invoker
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'v'
   and c.relname like 'v_ticket%'
 order by c.relname;

-- V3 · 🔴 LA QUE MAS IMPORTA. Que mover el estado, triar y definir sean de
--      socias EN LA BASE. ESPERADO: las tres con `acceso_es_socia()`.
--      Si alguna dice `true`, es `ent_anulacion_ins` otra vez. PARAR.
select tablename, policyname, cmd, with_check
  from pg_policies
 where schemaname = 'public'
   and policyname in ('ticket_estado_ins','ticket_marca_ins','ticket_detalle_ins')
 order by policyname;

-- V4 · Que no quede update ni delete concedido. ESPERADO: CERO filas.
select table_name, grantee, privilege_type
  from information_schema.role_table_grants
 where table_schema = 'public'
   and table_name in ('ticket','ticket_estado','ticket_marca','ticket_detalle',
                      'ticket_foto','build_publicado')
   and grantee in ('anon','authenticated')
   and privilege_type in ('UPDATE','DELETE','TRUNCATE')
 order by table_name, grantee;

-- V5 · El bucket. `public` TIENE que salir false.
select id, public, file_size_limit, allowed_mime_types
  from storage.buckets where id = 'tickets';

-- V6 · Las politicas de Storage. ESPERADO: DOS, tickets_ins y tickets_sel.
select policyname, cmd from pg_policies
 where tablename = 'objects' and policyname like 'tickets%';

-- V7 · Que la politica mire el segmento correcto. ESPERADO: 12.
select ticket_de_ruta('12/ab.png') as debe_dar_12;

-- V8 · 🔴 LO QUE NO SE PUEDE PROBAR DESDE ACA. El SQL Editor entra como
--      `postgres` y saltea la RLS: desde el editor, V3 dice que la politica
--      EXISTE, no que FUNCIONE. Para eso esta `pg_pruebas.py` con su carril B,
--      que el 17-sep midio exactamente este caso en otra tabla: como usuaria
--      sin perfil de socia, el insert en `ent_odoo_hecho` rebato con 42501.
--      Las tres politicas del V3 hay que ejercitarlas igual.

-- 🟢 YA MEDIDO EL 17-sep: `justificantes` y `aguinaldos` existen y los dos
--    tienen public = false. Lo que sigue abierto es que `esquema_check.py` NO
--    MIRA STORAGE, asi que nadie se habria enterado si hubiera salido mal.


-- ════════════════════════════════════════════════════════════════════════
-- 11 · DONDE VA EL BOTON · junto a "Salir" NO entra
-- ════════════════════════════════════════════════════════════════════════
-- MEDIDO: `#btnSalir` es position:fixed arriba a la derecha, y el encabezado
-- de telefono le reserva 78px EXACTOS (`padding-right:78px`). Esos 78px son lo
-- que deja a la miga de pan sin cortarse, y el 17-sep Andrea verifico EN EL
-- APARATO que hoy se ve completa. Un segundo boton ahi se come la reserva y la
-- miga empieza a terminar en "…", que es lo que acabamos de arreglar.
--
-- LA PROPUESTA: un circulo chico, position:fixed, ABAJO A LA DERECHA, por
-- encima del safe-area de iOS. No toca el encabezado, no toca los 78px, no
-- toca la miga, y se alcanza con el pulgar sin cambiar la mano — que es como
-- Daniel tiene el telefono cuando encuentra el problema.
--
-- POR QUE NO LAS OTRAS:
--   · adentro del "+" de Mas vistas → ese menu es POR MODULO, y el boton tiene
--     que estar en TODA pantalla;
--   · al final de la fila de pestañas → mismo problema, y Entregas ya mide
--     517/720 en iPad: no sobra lugar;
--   · una fila al pie → hay que bajar scrolleando. Cuando Daniel encuentra el
--     problema esta mirando el problema, no el pie.
--
-- ⚠️ LO QUE HAY QUE CUIDAR:
--   1. FLOTA ENCIMA del contenido. `.main` ya tiene
--      `padding-bottom: calc(28px + env(safe-area-inset-bottom))`; hay que
--      subirlo donde viva el boton, o la ultima fila de las tablas queda tapada.
--   2. `env(safe-area-inset-bottom)` no es opcional en iPhone: sin el, el boton
--      queda bajo la barra de gestos y se toca sin querer.
--   3. Y hay que MIRARLO EN EL APARATO, no deducirlo. Misma regla que valio
--      hoy para la miga.


-- ════════════════════════════════════════════════════════════════════════
-- 12 · EL HISTORIAL · y el build en el que salio el arreglo
-- ════════════════════════════════════════════════════════════════════════
-- Un ticket cerrado tiene que poder leerse ENTERO, de una, sin ruido: que se
-- reporto, quien, cuando, la foto, lo que capturo el sistema, cada cambio de
-- estado con su nota — y en que build salio el arreglo. Eso ultimo es lo que
-- convierte "Cerrado" en "cerrado así".
--
-- ── EL PROBLEMA ─────────────────────────────────────────────────────────
-- El build del arreglo NO se sabe cuando se marca. Se sabe cuando se PUBLICA,
-- que es despues y a veces bastante despues. Cualquier diseño que dependa de
-- que alguien vuelva al ticket a escribirlo ya perdio: nadie vuelve.
--
-- ── LA SOLUCION · que lo escriba el ritual que YA CORRE ─────────────────
-- El cierre de sesion que publica (`/cierre`) ya calcula el sha de `main`, ya
-- lo compara contra `origin/main`, ya verifica el sello contra Pages y ya lo
-- escribe en la bitacora. Agregarle una fila es sumar un dato que ya tiene en
-- la mano, no pedirle uno nuevo. Dos piezas:
--   1. `build_publicado` · una fila por publicacion. Sello, sha de main,
--      cuando, que ramas entraron. Resuelve de paso que "b56" signifique dos
--      cosas: el sha desambigua siempre.
--   2. Al publicar, el ritual lee los commits que entraron, busca las
--      referencias `T-0007` en los mensajes —la misma costumbre con la que el
--      repo ya escribe `§12` y `b61`— y emite el INSERT con `build_arreglo`.
--
-- ⚠️ CUANDO EL RITUAL NO PUEDA SABERLO, `build_arreglo` QUEDA EN NULL Y LA
--    PANTALLA DICE "no consta en qué build salió". No se infiere. Un ticket
--    puede cerrarse sin tocar codigo, o el arreglo puede haber entrado en un
--    commit que no lo nombro. Un dato con pinta de medido que es un supuesto
--    es peor que un hueco: el hueco se ve.
-- 🟠 SE PUEDE MOSTRAR UNA INFERENCIA, PERO ROTULADA: "se cerró el 17-sep y el
--    primer build publicado después fue b62". Eso es una PISTA, y la pantalla
--    tiene que decirlo con esas palabras — nunca en el mismo renglon ni con la
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
create policy build_publicado_ins on build_publicado
  for insert to authenticated with check (acceso_es_socia());
revoke all on build_publicado from anon;
revoke update, delete, truncate on build_publicado from authenticated;
grant select, insert on build_publicado to authenticated;

-- ── LA VISTA DEL HISTORIAL · una fila por cosa que paso ─────────────────
-- El primero SIEMPRE es el reporte (orden 0). La pantalla pinta lo que viene.
-- ⚠️ El `order by` de una vista con UNION no esta garantizado si alguien la
--    envuelve en otra consulta: quien la lea ordena igual por (orden, cuando).
create or replace view v_ticket_historial with (security_invoker = true) as
  select t.id as ticket_id, 0 as orden, t.creado_en as cuando,
         'reporte' as que, t.creado_por as quien, t.descripcion as detalle,
         null::text as build_arreglo
    from ticket t
  union all
  select e.ticket_id, 1, e.creado_en,
         case e.estado when 'disponible'    then 'Disponible'
                       when 'bloqueado'     then 'Bloqueado'
                       when 'en_curso'      then 'En curso'
                       when 'en_validacion' then 'En validación'
                       when 'cerrado'       then 'Cerrado'
                       when 'pospuesto'     then 'Pospuesto'
                       else                      'Descartado' end,
         e.creado_por,
         coalesce(e.nota, '') ||
           coalesce('  · espera: ' || e.espera, '') ||
           coalesce('  · bloqueado por T-' || lpad(e.bloquea_ticket_id::text,4,'0'), ''),
         e.build_arreglo
    from ticket_estado e
  union all
  select m.ticket_id, 1, m.creado_en, 'triaje', m.creado_por,
         (case when m.toca_numeros or m.escribe_en_base
               then 'Un agente NO lo toma. ' else 'Un agente puede tomarlo. ' end)
         || 'Prioridad ' || m.prioridad
         || (case when m.bloquea_entrega then ' · bloquea una entrega' else '' end)
         || '. ' || m.razon,
         null
    from ticket_marca m
  union all
  select d.ticket_id, 1, d.creado_en,
         case d.clase when 'espera'   then 'Qué se espera'
                      when 'criterio' then 'Criterio de terminado'
                      when 'cierre'   then 'Cierre'
                      else                 'Anuncio' end,
         d.creado_por, d.texto, null
    from ticket_detalle d
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
--   · Arriba: el tipo y el estado. Nada mas.
--   · Qué se reportó, quién, cuándo.
--   · La foto, si hay. Si se perdió, una línea que lo diga.
--   · Qué se espera · Criterio de terminado.
--   · Lo que capturó el sistema: tabla de dos columnas, plegada. Son ocho
--     campos técnicos y no son la noticia.
--   · Abajo: la línea de tiempo, una fila por evento, con su nota.
--   · Y el build del arreglo al lado de "Cerrado" — o "no consta".
-- ⚠️ Sin subtitulos que expliquen que es un ticket. Misma regla que saco el
--    titulo de "Sin factura" el 17-sep: la pantalla arranca en el trabajo.


-- ════════════════════════════════════════════════════════════════════════
-- 13 · LA MIGRACION · UNA sola, desde los dos archivos
-- ════════════════════════════════════════════════════════════════════════
-- ⚠️ DECISION DEL 17-sep: **LA MIGRACION T1–T7 DEL 10-sep SE TIRA.** No se
--    perdio nada; esta en git. Se tira porque se SUPERPONIA con los archivos:
--      · T4 decia "Detalle completo en ENTREGAS_PENDIENTES.md §13";
--      · T5 decia "el detalle entero esta en ENTREGAS_PENDIENTES.md §15";
--      · T6 decia "Detalle en PENDIENTES.md P1" y arrastraba H1.
--    Pegar las dos migraciones habria creado esos tickets DOS VECES.
--
--    ⚠️ Y una correccion de metodo que vale anotar: al buscar la superposicion
--    se grepeo `"§15"` y dio cero — pero §15 SI existe: las secciones se
--    escriben `## 15 ·`, no `§15`. El cero probaba que esa grafia no estaba,
--    no que el tema no estuviera. Un grep vacio prueba lo que se busco, nada
--    mas.
--
-- SE CONSERVAN TRES, porque no tienen § propio en ninguno de los dos archivos
-- (buscado el 17-sep: "stock.move.line", "WH/INT/00137" y "175" → cero
-- apariciones en los dos):
--   · el de `stock.move.line` con write/create/unlink para todo usuario interno
--     de Odoo (era T2);
--   · el de las tres salidas sin registrar, BLOQUEADO por el Bloque 3.2/3.3
--     (era T3) — es el primer caso real del modelo de dependencias del §2;
--   · el del paquete cruzado entre los lotes 175 y 191 (era T7).
--
-- LO QUE HAY QUE MIGRAR, CONTADO EL 17-sep:
--
--   ENTREGAS_PENDIENTES.md · 25 secciones (§1–§25)
--       18 ABIERTO + §1 PRIORITARIO + §9 EN CURSO + §10 APARCADO  = 21 vivas
--        3 CERRADO (§2, §4, §11)
--        1 sin estado (§5) — no es un pendiente, es prosa de contexto
--   PENDIENTES.md · 7 pendientes: F1, O1, P1, H1, H2, O2, S1       =  7 vivas
--                                                                   ────────
--                                                            28 tickets
--
-- 🟢 Y UN HALLAZGO QUE SOSTIENE EL DISEÑO: los dos archivos YA TRAEN SU ESTADO
--    EN EL ENCABEZADO —ABIERTO, CERRADO, EN CURSO, APARCADO, PRIORITARIO— y
--    eso mapea casi uno a uno contra los ocho. Los estados no son una
--    taxonomia inventada: son la que estos archivos ya usaban sin nombrarla.
--      ABIERTO → disponible o bloqueado, segun tenga o no algo esperando
--      EN CURSO → en_curso · APARCADO → pospuesto · CERRADO → cerrado
--      PRIORITARIO → disponible con prioridad 'alta'
--
-- 🔴 LOS 28 NO ESTAN ESCRITOS EN ESTE ARCHIVO, Y ES A PROPOSITO.
--    Escribir 28 cuerpos de ticket fieles exige leer §1 a §25 y los siete de
--    PENDIENTES.md uno por uno, con su contexto. Resumirlos de memoria seria
--    fabricar 28 datos con pinta de medidos — exactamente lo que este repo
--    pasa el dia entero evitando. Es un trabajo aparte, y se hace en una
--    pasada propia, con las secciones abiertas al lado.
--    Cuando se haga, cada ticket migrado lleva:
--      · `build`  = 'migrado · sin build' — un pendiente viejo no tiene version
--        que capturar, y ponerle la de hoy seria inventar un dato;
--      · `vista`, `miga`, `doc_modificado`, `standalone`, zona horaria = NULL,
--        porque nadie los midio;
--      · `creado_por` = 'ticket-sql · migracion …', que el guardia del §1 exige;
--      · y su fila de `ticket_detalle` clase 'espera' con el § de donde salio,
--        para poder volver al original sin buscarlo.
--
-- ⚠️ EL ORDEN OBLIGADO, cuando se haga: PRIMERO los tres que bloquean a otros
--    (el del Bloque 3.2/3.3 bloquea al de las tres salidas), porque
--    `bloquea_ticket_id` es una FK: el ticket que bloquea tiene que existir
--    antes que el bloqueado. Migrar por numero de § lo rompe.
