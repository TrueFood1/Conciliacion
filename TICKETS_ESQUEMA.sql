-- ════════════════════════════════════════════════════════════════════════
-- TICKETS · el canal de Daniel, y el lugar donde deja de perderse un hallazgo
-- PROPUESTA. NO PEGAR. Andrea aprueba antes, y no antes de que cierre el
-- conteo fisico y este hecha el ancla nueva.
--
-- ── LO QUE RESUELVE ─────────────────────────────────────────────────────
--   1. los hallazgos quedan enterrados en prosa dentro de los ESTADO_ACTUAL;
--   2. Daniel encuentra los problemas y su unico canal es Andrea. El 8-sep se
--      fue media mañana reconstruyendo que paso en una pantalla que nadie
--      fotografio a tiempo.
--
-- ── NO ES LA PRIMERA VEZ QUE TRUEFIE GUARDA UN ARCHIVO ──────────────────
-- ⚠️ Corregir el supuesto de partida: PERSONAL_STORAGE.sql (aprobado por Andrea
-- el 24-ago) ya diseña DOS buckets privados con sus politicas, y usa
-- acceso_es_socia() y storage.foldername() exactamente como hace falta acá. Lo
-- que NO existe es el CODIGO: `index.html` no tiene un solo `.upload(` ni un
-- `createSignedUrl` — grepeado el 10-sep, cero apariciones. O sea que el esquema
-- de archivos ya fue pensado y aprobado, y nunca se estreno.
-- Consecuencia practica: este archivo NO inventa una convencion nueva, copia la
-- que ya se decidio. Y queda una pregunta que hay que MEDIR, no citar: si esos
-- dos buckets estan creados de verdad en el proyecto (esquema_check no mira
-- Storage, asi que nadie lo sabria).
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- 1 · EL TICKET · lo que se escribe una vez y no se toca mas
-- ════════════════════════════════════════════════════════════════════════
-- Append-only como todo el sistema: el ticket no cambia nunca. Lo que cambia es
-- su ESTADO, y eso son eventos aparte (§2). Un `estado` como columna de esta
-- tabla obligaria a un UPDATE, y este proyecto no tiene grant de update en
-- ninguna tabla de datos.
create table if not exists ticket (
  id           bigint generated always as identity primary key,

  -- ── LO QUE ESCRIBE LA PERSONA ────────────────────────────────────────
  descripcion  text not null,
  constraint ticket_descripcion_ok check (length(btrim(descripcion)) >= 15),

  -- ── LO QUE CAPTURA EL SISTEMA, SIN QUE NADIE ESCRIBA ─────────────────
  build            text not null,   -- la constante BUILD del index.html que corria
  doc_modificado   text,            -- document.lastModified — ver el comentario de abajo
  vista            text,            -- id del <div> visible (vDespachos, vConteoLote, …)
  modulo           text,            -- body[data-mod]: entregas | finanzas | …
  sobre            text,            -- el modal encima, si habia (rpSheet, vHistorial, …)
  agente           text,            -- navigator.userAgent
  standalone       boolean,         -- abierto desde el icono de iOS, o desde Safari
  viewport         text,            -- '820x1180 @2' — para leer un reporte de layout

  creado_en    timestamptz not null default now(),
  creado_por   text not null        -- email de la sesion de Supabase
);
create index if not exists ticket_creado_idx on ticket (creado_en desc);
create index if not exists ticket_autor_idx  on ticket (lower(creado_por), creado_en desc);

comment on table ticket is
  'Un hallazgo reportado por cualquiera del equipo desde el boton flotante. Append-only: '
  'el ticket no se edita. Su estado vive en ticket_estado.';

-- ⚠️ `build` SOLO NO ALCANZA, y esto es el corazon del asunto.
-- Hoy "b56" significa DOS cosas: Entregas en main y Entregas + el calendario de
-- Lorena en dev. Y cuando lo de Lorena se publique, el sello NO va a cambiar.
-- O sea que un ticket que diga `build = 'v 8 sep 2026 · b56'` reproduce
-- exactamente la ambigüedad que costo la media mañana del 8-sep.
-- `doc_modificado` es `document.lastModified`: la fecha del archivo QUE EL
-- APARATO TIENE CARGADO, no la que el servidor sirve ahora. Es lo unico que
-- distingue dos builds con el mismo sello, y es lo que contesta "¿que version
-- corria el iPad?" sin depender del sello.
-- `standalone` va por lo mismo: el icono de iOS es el que retiene la version
-- vieja horas o dias (medido el 8-sep con el pedido 46).

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
-- Abierto → En analisis → Resuelto → Cerrado.
--
-- 'abierto' NO SE INSERTA NUNCA. Es la ausencia de eventos, y la vista lo
-- resuelve con un coalesce. Asi "quien abre no cambia estados" es literal: la
-- persona que reporta no escribe ni una fila en esta tabla, ni siquiera la
-- primera. Un estado inicial insertado seria una excepcion a la regla escrita
-- adentro de la regla misma.
create table if not exists ticket_estado (
  id          bigint generated always as identity primary key,
  ticket_id   bigint not null references ticket(id),
  estado      text   not null check (estado in ('en_analisis','resuelto','cerrado')),
  -- El ANALISIS de CC vive acá, no en un archivo del repo: Daniel no tiene el
  -- repo, y Andrea tiene que poder leer la propuesta al lado del ticket.
  nota        text,
  creado_en   timestamptz not null default now(),
  creado_por  text   not null,

  -- Pasar a "en analisis" sin dejar escrito QUE se analizo es mover una ficha.
  constraint ticket_estado_nota_ok check (
    estado <> 'en_analisis' or (nota is not null and length(btrim(nota)) >= 20))
);
create index if not exists ticket_estado_idx
  on ticket_estado (ticket_id, creado_en desc);

-- ── EL GUARDIA · las dos reglas duras ────────────────────────────────────
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
    -- Es la via por la que entra el analisis de CC (ver §5).
    -- ✅ APROBADO 10-sep: es la via por la que entra el analisis de CC, y la
    -- UNICA. pg_lector.py sigue siendo SOLO LECTURA con sus dos candados: CC no
    -- escribe en Supabase, escribe el INSERT y Andrea lo pega. Un paste por
    -- sesion, con el analisis de todos los tickets trabajados.
    if new.creado_por not like 'cc-sql%' then
      raise exception 'un cambio de estado sin sesion de Supabase (SQL Editor) tiene que '
        'firmar creado_por empezando con "cc-sql". Vino: %', new.creado_por;
    end if;
    -- Ni siquiera por SQL se cierra un ticket: cerrar es de las socias, y desde
    -- el SQL Editor no hay forma de saber cual socia es.
    if new.estado = 'cerrado' then
      raise exception 'cerrar un ticket es de las socias y desde el SQL Editor no se sabe '
        'quien esta escribiendo. Se cierra desde la pantalla, con sesion.';
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

  -- ── REGLA 1 · QUIEN ABRE NO CAMBIA ESTADOS ────────────────────────────
  -- Con una excepcion deliberada, ✅ APROBADA POR ANDREA EL 10-sep: una socia SI
  -- puede mover un ticket que abrio ella. La regla existe para que nadie se
  -- autoconteste, no para dejar a Andrea trabada en su propio ticket.
  if lower(btrim(autor)) = lower(btrim(quien)) and not socia then
    raise exception 'vos abriste este ticket: el estado lo mueve otra persona. '
      'Es lo que hace que "resuelto" signifique algo.';
  end if;

  -- ── REGLA 2 · SOLO LAS SOCIAS CIERRAN ─────────────────────────────────
  if new.estado = 'cerrado' and not socia then
    raise exception 'cerrar un ticket es de un perfil socias, y % no lo es.', quien;
  end if;

  return new;
end
$guard$;

drop trigger if exists ticket_estado_guard_trg on ticket_estado;
create trigger ticket_estado_guard_trg before insert on ticket_estado
  for each row execute function ticket_estado_guard();


-- ════════════════════════════════════════════════════════════════════════
-- 3 · LA FOTO · una fila por archivo, y el archivo aparte
-- ════════════════════════════════════════════════════════════════════════
-- La foto es OPCIONAL y por eso es una tabla aparte y no una columna: un ticket
-- sin foto entra igual, y una subida que falla no puede tumbar el ticket. El
-- orden en la pantalla es: primero se inserta el ticket, despues se sube. Si la
-- subida falla, queda el ticket con su texto — que es lo que se queria.
create table if not exists ticket_foto (
  id          bigint generated always as identity primary key,
  ticket_id   bigint not null references ticket(id),
  ruta        text   not null unique,   -- 'tickets/{ticket_id}/{uuid}.{ext}'
  mime        text,
  bytes       bigint,
  creado_en   timestamptz not null default now(),
  creado_por  text   not null
);
create index if not exists ticket_foto_idx on ticket_foto (ticket_id, creado_en);


-- ════════════════════════════════════════════════════════════════════════
-- 4 · LA VISTA QUE LEE LA PANTALLA
-- ════════════════════════════════════════════════════════════════════════
-- security_invoker en TODAS las vistas: es la regla del modulo desde la fuga
-- del 24-ago (v_acceso_usuario le devolvia cinco correos a la anon key).
create or replace view v_ticket with (security_invoker = true) as
  select t.id,
         t.descripcion,
         t.build, t.doc_modificado, t.vista, t.modulo, t.sobre,
         t.agente, t.standalone, t.viewport,
         t.creado_en, t.creado_por,
         coalesce(e.estado, 'abierto')          as estado,
         e.nota                                 as ultima_nota,
         e.creado_en                            as estado_en,
         e.creado_por                           as estado_por,
         (select count(*) from ticket_foto f where f.ticket_id = t.id) as fotos
    from ticket t
    left join lateral (
      select x.estado, x.nota, x.creado_en, x.creado_por
        from ticket_estado x
       where x.ticket_id = t.id
       order by x.creado_en desc
       limit 1) e on true;

-- Lo que CC trae al abrir sesion con /retomar: lo abierto y lo que ya analizo,
-- con su propuesta al lado. Lo cerrado no vuelve.
create or replace view v_ticket_pendiente with (security_invoker = true) as
  select * from v_ticket
   where estado in ('abierto','en_analisis','resuelto')
   order by (estado = 'abierto') desc, creado_en;


-- ════════════════════════════════════════════════════════════════════════
-- 5 · RLS
-- ════════════════════════════════════════════════════════════════════════
alter table ticket        enable row level security;
alter table ticket_estado enable row level security;
alter table ticket_foto   enable row level security;

drop policy if exists ticket_sel on ticket;
drop policy if exists ticket_ins on ticket;
drop policy if exists ticket_estado_sel on ticket_estado;
drop policy if exists ticket_estado_ins on ticket_estado;
drop policy if exists ticket_foto_sel on ticket_foto;
drop policy if exists ticket_foto_ins on ticket_foto;

-- VER: todo el equipo ve todos los tickets. Es una decision, no un descuido —
-- ver la nota de arriba del reporte. Lo que sostiene "si reporta y nunca sabe
-- que paso, deja de reportar" es justamente que Daniel vea el suyo cerrado, y
-- esconderle los de los demas no protege nada que el no vea ya en Truefie.
create policy ticket_sel on ticket
  for select to authenticated using (true);

create policy ticket_ins on ticket
  for insert to authenticated with check (true);   -- el trigger ata la firma

create policy ticket_estado_sel on ticket_estado
  for select to authenticated using (true);

-- La capa 1. El trigger dice lo mismo y ata ademas al SQL Editor, que entra
-- como `postgres` y pasa la RLS de largo. Dos capas, doctrina del proyecto.
create policy ticket_estado_ins on ticket_estado
  for insert to authenticated with check (
    (estado <> 'cerrado' or acceso_es_socia())
    and (acceso_es_socia()
         or not exists (select 1 from ticket t
                         where t.id = ticket_id
                           and lower(t.creado_por) = lower(
                               nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email'))));

create policy ticket_foto_sel on ticket_foto
  for select to authenticated using (true);
create policy ticket_foto_ins on ticket_foto
  for insert to authenticated with check (true);

-- Sin update ni delete en las tres: append-only se niega por AUSENCIA de
-- politica. No hay que escribir nada para prohibirlo.
grant select, insert on ticket        to authenticated;
grant select, insert on ticket_estado to authenticated;
grant select, insert on ticket_foto   to authenticated;
grant select on v_ticket            to authenticated;
grant select on v_ticket_pendiente  to authenticated;


-- ════════════════════════════════════════════════════════════════════════
-- 6 · EL BUCKET · privado, y la parte que hay que mirar dos veces
-- ════════════════════════════════════════════════════════════════════════
-- Un screenshot de Truefie puede tener clientes, facturas y cantidades. Y si
-- se saca desde una pantalla de Personal, puede tener un salario o una nota
-- medica. Eso ultimo es lo que decide la politica de LECTURA de abajo.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'tickets', 'tickets',
  false,                                  -- PRIVADO. No cambiar. Es todo el asunto.
  10485760,                               -- 10 MB. Un screenshot de iPad pesa 2-4 MB
  array['image/jpeg','image/png','image/heic','image/heif','image/webp']
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
-- un segmento. Escribirlo mal no da error: da una politica que compara contra
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

-- SUBIR: a la carpeta de un ticket propio. Una socia puede subir a cualquiera
-- (agregar la foto que Daniel no pudo sacar).
create policy tickets_ins on storage.objects
  for insert to authenticated
  with check (bucket_id = 'tickets'
              and (acceso_es_socia() or ticket_es_mio(name)));

-- ⚠️ VER: LA FOTO PROPIA, O TODO SI ES SOCIA. Y NO "todo el equipo".
-- ✅ APROBADO POR ANDREA EL 10-sep, con este argumento.
-- Acá se separa a proposito de la politica de la TABLA (§5), que si deja ver
-- todos los tickets. El motivo es concreto: el TEXTO de un ticket lo escribe
-- una persona que sabe lo que esta escribiendo; la FOTO se saca de la pantalla
-- que estaba abierta, y esa pantalla puede ser Personal — un salario, un
-- aguinaldo, una nota medica. Si la lectura fuera "todo el equipo", un ticket
-- abierto desde Personal le abriria a Daniel un dato que hoy no ve.
-- Es la misma leccion de PERSONAL_STORAGE: reglas de acceso distintas no se
-- mezclan porque el archivo "es del mismo tipo".
create policy tickets_sel on storage.objects
  for select to authenticated
  using (bucket_id = 'tickets'
         and (acceso_es_socia() or ticket_es_mio(name)));

-- Sin update ni delete: append-only, igual que justificantes. Una foto que no
-- sirve se reemplaza subiendo otra, no borrando la primera.


-- ════════════════════════════════════════════════════════════════════════
-- 7 · LO QUE TIENE QUE HACER ANDREA EN EL PANEL, Y COMPROBAR
-- ════════════════════════════════════════════════════════════════════════
-- 1) Storage → Buckets. Si despues de pegar esto falta `tickets`, el insert no
--    tuvo permisos: crealo a mano.
--        New bucket → nombre: tickets
--        Public bucket: DESMARCADO   ← lo mas importante de todo el archivo
--        File size limit: 10 MB
--        Allowed MIME types: image/jpeg, image/png, image/heic, image/heif, image/webp
--    Y volve a pegar el archivo, para que queden las politicas.
--
-- 2) select id, public, file_size_limit from storage.buckets where id = 'tickets';
--    `public` tiene que salir FALSE. Si sale true, cada screenshot queda
--    legible para cualquiera que tenga la URL, sin login.
--
-- 3) select policyname, cmd from pg_policies
--     where tablename = 'objects' and policyname like 'tickets%';
--    Tienen que salir DOS: tickets_ins y tickets_sel. Si aparece una de update
--    o delete, sobra.
--
-- 3b) ⚠️ QUE LA POLITICA MIRE EL SEGMENTO CORRECTO. Una politica que compara
--     contra la carpeta equivocada no da error: deja de proteger y nadie se
--     entera. Con un ticket ya subido, y con la sesion de alguien que NO sea su
--     autor ni socia, la foto tiene que dar "not found". Si se ve, PARAR.
--         select ticket_de_ruta('12/ab.png');   -- tiene que devolver 12
--
-- 4) ⚠️ DE PASO, Y NO ES DE ESTE ARCHIVO: comprobar si `justificantes` y
--    `aguinaldos` existen de verdad. Se aprobaron el 24-ago y nunca se
--    estrenaron desde el codigo, asi que nadie sabria si el pegado quedo a
--    medias. esquema_check NO mira Storage.
--        select id, public from storage.buckets order by id;


-- ════════════════════════════════════════════════════════════════════════
-- 8 · LOS ROJOS VIEJOS · la migracion, APROBADA y SIN PEGAR
-- ════════════════════════════════════════════════════════════════════════
-- Decision del 10-sep: se migran SOLO los 🔴. Los ambar se quedan en la bitacora
-- hasta que alguien los toque. La lista de siete la reviso y aprobo Andrea el
-- 10-sep. Va escrita y NO PEGADA, como todo en este archivo.
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
-- ponerle la de hoy seria fabricar un dato con pinta de medido.
-- Por la misma razon van sin `vista`, sin `doc_modificado` y sin `standalone`:
-- nadie los midio.
--
-- La firma es 'ticket-sql · migracion 10-sep', que el guardia de §1 exige que
-- empiece con 'ticket-sql' cuando no hay sesion de Supabase.

/*  NO PEGAR — esperando que cierre el conteo y el visto bueno final.

insert into ticket (descripcion, build, creado_por) values

-- ── T1 ──────────────────────────────────────────────────────────────────
('"b56" significa DOS cosas y el sello no lo dice. Entregas solo esta en main; '
 'Entregas mas el calendario de Personal de Lorena esta en dev. Cuando lo de '
 'Lorena se publique, el sello NO va a cambiar: los dos builds se llaman igual. '
 'Y el sello del pie del lobby es el mecanismo del que dependemos para saber que '
 'version corre el iPad de Daniel. Golpea justo ahi. Viene del bloque del 8-sep '
 'de la bitacora.',
 'migrado · sin build', 'ticket-sql · migracion 10-sep'),

-- ── T2 ──────────────────────────────────────────────────────────────────
('stock.move.line sigue con write, create y unlink concedidos a TODO usuario '
 'interno de Odoo. Arrastra del 2-sep, cuando se arreglaron los otros cuatro '
 'modelos quitandole el grupo Inventory/User al usuario lector. En este modelo '
 'el unico freno que queda es LECTURA_OK, que es una lista de Python — o sea una '
 'sola capa en un proyecto cuya doctrina son dos. Va junto con los grants de '
 'Supabase, que tienen la misma forma.',
 'migrado · sin build', 'ticket-sql · migracion 10-sep'),

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
 'migrado · sin build', 'ticket-sql · migracion 10-sep'),

-- ── T4 ──────────────────────────────────────────────────────────────────
('El BLOQUEO DURO de Despachos no existe: se aprobo como parte de la Entrega 2 y '
 'nunca se construyo. Hoy despachar de un lote sin saldo pasa en silencio. '
 'Verificado en el codigo el 10-sep, no citado: _despSaldo se lee en dos lugares '
 'de index.html (10815 y 11052) y los dos son para armar el selector, nunca para '
 'frenar. Detalle completo en ENTREGAS_PENDIENTES.md §13. '
 '⚠️ NO LO ARREGLA EL BLOQUE 4, Y ESTE TICKET NO SE CIERRA CUANDO EL BLOQUE 4 '
 'SALGA. Son dos bloqueos distintos con el mismo apodo: el Bloque 4 es la LINEA '
 'SIN LOTE (falta el dato de que lote salio) y §13 es el LOTE SIN SALDO (el dato '
 'esta y dice que ese pan ya no existe). Arreglar el primero no toca al segundo. '
 'Si alguien cierra este ticket viendo salir el Bloque 4, lo cierra sin haberse '
 'resuelto — y seria la segunda vez que esta salvaguarda se da por hecha sin '
 'existir.',
 'migrado · sin build', 'ticket-sql · migracion 10-sep'),

-- ── T5 ──────────────────────────────────────────────────────────────────
('130 unidades salieron del lote Pan Blanco 208 / 1-27, que nunca se movio. El '
 'lote daba −4 en Inventario y Daniel conto 21 cajas = 126 unidades fisicas, '
 'cajas cerradas y todas de ese lote. Quedan dos hipotesis abiertas y el detalle '
 'entero, con lo ya descartado, esta en ENTREGAS_PENDIENTES.md §15.',
 'migrado · sin build', 'ticket-sql · migracion 10-sep'),

-- ── T6 ──────────────────────────────────────────────────────────────────
('PERSONAL_STORAGE.sql esta aprobado desde el 24-ago-2026 y nunca se estreno: '
 'grep de .upload( y de createSignedUrl sobre index.html el 10-sep → cero '
 'apariciones de cada uno. Es el cuarto caso del patron "decision escrita y '
 'nunca implementada". Detalle en PENDIENTES.md P1. '
 'PRIMER TRABAJO: medir si los dos buckets existen de verdad y si son privados '
 '(select id, public from storage.buckets). Va por pg_lector.py con contraseña: '
 'la anon key contestaria vacio en vez de "no tenes permiso". Si alguno sale con '
 'public = true, esto deja de ser 🟠 y pasa a urgente. '
 'Y no se habria detectado solo: ver PENDIENTES.md H1 — esquema_check.py NO MIRA '
 'STORAGE, y es su unico punto ciego que puede callar sobre una exposicion de '
 'datos.',
 'migrado · sin build', 'ticket-sql · migracion 10-sep'),

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
 'migrado · sin build', 'ticket-sql · migracion 10-sep');

*/

-- Y despues, la comprobacion: tienen que salir SIETE, todos en 'abierto'.
--   select id, estado, left(descripcion, 60) as arranque
--     from v_ticket where build = 'migrado · sin build' order by id;
