-- ════════════════════════════════════════════════════════════════════════
-- BLOQUE 4 + 3.2 + 3.3 · LA LINEA QUE NO LLEVA LOTE
-- PROPUESTA. NO PEGAR. Andrea aprueba antes, y no antes de que cierre el
-- conteo fisico del viernes 11-sep y este hecha el ancla nueva.
--
-- Va sin numero de build en el nombre a proposito: hoy "b56" ya significa dos
-- cosas (Entregas en main, Entregas + el calendario de Lorena en dev) y ese
-- pendiente esta abierto. Ponerle un numero ahora seria inventar el tercero.
--
-- ── LOS DOS HECHOS, Y EN QUE SE PARECEN DE VERDAD ───────────────────────
-- Son el mismo hecho para el BLOQUEO DURO: "esta linea del alisto se cerro sin
-- lote y aun asi esta resuelta". Por eso el contador se unifica y `_despEst`,
-- `_despLineaOK` y `_despPendientes` se tocan UNA sola vez.
--
-- ⚠️ NO son el mismo hecho para el SALDO, y esta distincion es la que sostiene
-- todo el archivo:
--
--   NO DETERMINADO (3.3)  el pan SALIO del congelador y no se sabe de que lote.
--                         El saldo del producto BAJA. Cae en el balde
--                         'NO DETERMINADO', que es un valor de `lote`.
--   NO SE ENTREGA  (3.2)  el pan NO SALIO. No baja ningun saldo, de ningun lote,
--                         ni del producto. No es un lote: es la AUSENCIA de lote.
--
-- Consecuencia directa: 'NO SE ENTREGA' NO puede ser un centinela de `lote`. Si
-- lo fuera, el motor —que indexa por `producto|lote`— abriria un balde nuevo por
-- producto que solo resta, o sea un lote fantasma con saldo negativo. Es
-- exactamente la enfermedad que se acaba de curar el 8-sep retirando los seis
-- 'sin lote' / 'Sin lote'. La marca va en `ent_alisto_linea` y la linea no
-- escribe NINGUNA fila en `ent_alisto_lote`.
--
-- ── EL CHOQUE DE NOMBRES QUE HAY QUE DECIDIR PRIMERO ────────────────────
-- `ent_pedido_valida` YA EXISTE desde el 19-ago y significa otra cosa: "Andrea
-- ya valido esta entrega EN ODOO" (ENTREGAS_CLASIFICACION.sql §3). Si 3.2 usa
-- "esperando validacion", la palabra pasa a significar dos cosas sobre el MISMO
-- pedido — el mismo problema que ya esta abierto con "b56".
-- Este archivo usa AUTORIZACION, que ademas es el verbo que uso Andrea al
-- describirlo ("lo autoriza Andrea o Lorena"). DECIDIDO el 10-sep: autorizacion,
-- no validacion, justamente por el choque con ent_pedido_valida.
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- 0 · LO QUE HAY QUE MEDIR ANTES DE PEGAR NADA
-- ════════════════════════════════════════════════════════════════════════
-- ⚠️ NINGUN NUMERO DE ESTE ARCHIVO ESTA MEDIDO. Lo de abajo son CONDICIONES,
-- no resultados. La diferencia entre un numero medido y un objetivo escrito a
-- mano ya costo una sesion entera (bitacora 9-ago) y por eso no se anota
-- ningun "esperado" que no venga de una corrida.
--
-- Las trece consultas viven en MEDICION_EXCEPCIONES.sql, en UN solo lugar, y se
-- corren con el lector de solo lectura:
--
--     python3 herramientas/pg_lector.py --clave --archivo MEDICION_EXCEPCIONES.sql
--
-- ⚠️ NO SE MIDE CON LA ANON KEY. `ent_alisto_linea` y `ent_conteo_linea` tienen
-- RLS con politica `to authenticated`, asi que la anon key no recibe un error:
-- recibe CERO FILAS. Un `count(*)` daria 0 y ese 0 no significa "no hay", 
-- significa "no veo". Es la misma trampa que el grep vacio, y es exactamente la
-- razon por la que existe pg_lector (lo dice su propio encabezado).
--
-- LO QUE TIENE QUE DAR PARA SEGUIR:
--   M1  · los objetos del 8-sep existen de verdad (ent_alisto_lote_correccion,
--         ent_alisto_lote_efectivo, v_ent_indeterminado_pendiente). Este archivo
--         se apoya entero en ellos y la bitacora los da por aplicados: eso es una
--         cita, no una medicion.
--   M2  · ent_alisto_lote_lote_forma convalidated = f  ·  motivo_ok = t
--   M3  · acceso_es_socia() existe. La politica RLS de §6 la llama, y si no esta,
--         el CREATE POLICY falla.
--   M4  · hay al menos 2 personas activas con perfil socias. Si no, nadie puede
--         autorizar y la lista de §5 no se vacia nunca.
--   M5  · ent_alisto_linea tiene la columna `cant_uom`. El CHECK de §1 la nombra.
--   M6  · contexto: cuantas lineas de alisto hay y cuantas tienen cant_uom nula.
--   M7  · TIENE QUE DAR 0. Es lo unico que permite que el CHECK de §4 entre VALID.
--         Si no da 0, PARAR: alguien escribio el centinela a mano en un conteo y
--         hay que decidir que motivo lleva antes de que el check lo exija.
--   M8/M9 · el censo de formas invalidas en ent_conteo_linea. NO bloquea este
--         archivo: es el insumo del candado de forma, que va DESPUES y aparte
--         (CANDADO_B56_FORMA_LOTE.sql §4). Se mide ahora porque entre el 8-sep y
--         hoy hay un conteo fisico entero de por medio.
--   M10 · el ancla vigente. Sirve para saber si se esta midiendo antes o despues
--         del reancle del viernes, que cambia M11 y M12 por completo.
--   M11 · el ANTES de la verificacion 7f. La vista nueva tiene que devolver este
--         MISMO numero para el tipo lote_no_determinado.
--   M12 · el balde del alisto hoy, en unidad de venta. Es el ANTES de 7e.
--   M13 · que el candado NOT VALID del 8-sep no haya dejado entrar filas nuevas
--         de forma invalida.
--
-- El candado de forma de ent_conteo_linea NO esta en este archivo. Va aparte,
-- DESPUES de que la pantalla de Conteo ofrezca 'NO DETERMINADO' y despues de que
-- M8 de cero. Ese orden ya esta escrito y razonado en CANDADO_B56_FORMA_LOTE.sql
-- §4 y no se adelanta acá.


-- ════════════════════════════════════════════════════════════════════════
-- 1 · 3.2 · LA MARCA VIVE EN LA LINEA, Y EN EL MISMO INSERT
-- ════════════════════════════════════════════════════════════════════════
-- Mismo criterio que 'NO DETERMINADO' el 8-sep: el motivo va en la MISMA fila y
-- el MISMO insert que la marca, asi no existe el estado intermedio "linea
-- marcada y sin motivo". "Sin motivo no se guarda" es candado del motor, no
-- validacion de pantalla.
alter table ent_alisto_linea
  add column if not exists no_se_entrega     boolean not null default false,
  add column if not exists motivo_no_entrega text,
  add column if not exists nota_no_entrega   text,
  add column if not exists no_entrega_por    text,
  add column if not exists no_entrega_en     timestamptz,
  add column if not exists cant_no_entregada numeric;

comment on column ent_alisto_linea.no_se_entrega is
  'Esta linea del pedido NO salio del congelador. No descuenta ningun lote ni el saldo del producto.';
comment on column ent_alisto_linea.motivo_no_entrega is
  'Lista cerrada: agotado | otro. Obligatorio cuando no_se_entrega. Es DATO, no texto.';
comment on column ent_alisto_linea.nota_no_entrega is
  'Obligatoria SOLO cuando el motivo es "otro". Es lo unico libre de todo el bloque.';
comment on column ent_alisto_linea.cant_no_entregada is
  'Cuanto se iba a entregar y no se entrego, en unidades individuales. cant_uds queda en 0 '
  'porque nada salio; este campo guarda el tamaño del hueco para poder sumarlo por motivo.';

-- `cant_no_entregada` no venia en el enunciado: la propuse yo y Andrea la
-- APROBO el 10-sep. El motivo: sin ella, "Agotado" dice que paso pero no cuanto, y el bloque entero
-- existe para que la excepcion se pueda SUMAR. Es la misma razon por la que el
-- motivo de una salida sin factura es el dato y el destinatario es contexto.
-- Se puede derivar de ent_pedido_linea por producto, pero solo si el pedido no
-- repite producto; guardarla cuesta una columna y no depende de esa suerte.

-- El CHECK va VALID: hoy ninguna fila tiene la marca puesta (§0a).
alter table ent_alisto_linea
  drop constraint if exists ent_alisto_linea_no_entrega_ok;
alter table ent_alisto_linea
  add constraint ent_alisto_linea_no_entrega_ok check (
    case when no_se_entrega then
           motivo_no_entrega in ('agotado','otro')
           -- "otro" SIN nota es un motivo que no dice nada: queda prohibido en la base.
           and (motivo_no_entrega <> 'otro'
                or (nota_no_entrega is not null and length(btrim(nota_no_entrega)) >= 10))
           and no_entrega_por is not null and length(btrim(no_entrega_por)) > 0
           and no_entrega_en  is not null
           -- LO QUE HACE VERDAD "no mueve ningun saldo", en el motor y no en la pantalla.
           and cant_uds = 0
           and coalesce(cant_uom, 0) = 0
         else
           motivo_no_entrega is null and nota_no_entrega is null
           and no_entrega_por is null and no_entrega_en is null
           and cant_no_entregada is null
    end);

comment on constraint ent_alisto_linea_no_entrega_ok on ent_alisto_linea is
  'La marca "no se entrega" viaja con su motivo, su firma y su hora, y con las cantidades '
  'en cero. Sin marca, los seis campos van nulos: no hay marca a medias en ninguna direccion.';

-- El minimo de 10 caracteres de la nota es la misma regla que `fuente` en
-- ent_alisto_lote_correccion: no alcanza para "ok" ni "no", si alcanza para
-- "no llego el camion". Es una perilla: si a Daniel con guantes le resulta
-- larga, se baja acá y en ningun otro lado.


-- ════════════════════════════════════════════════════════════════════════
-- 2 · EL CANDADO EXCLUYENTE · o lleva lote, o va marcada. Nunca las dos
-- ════════════════════════════════════════════════════════════════════════
-- POR QUE UN TRIGGER Y NO UN CHECK: el candado tiene que mirar la OTRA tabla
-- (`ent_alisto_lote` desde `ent_alisto_linea` y al reves), y Postgres no admite
-- subconsultas en un CHECK. Es palabra por palabra el motivo de §3 de
-- ENTREGAS_INDETERMINADO.sql.
--
-- Van los DOS sentidos, y no solo el obvio:
--   a) insertar un lote colgando de una linea ya marcada  → se rechaza;
--   b) marcar una linea que YA tiene lotes colgando       → se rechaza.
-- El (b) parece imposible porque la app inserta la linea antes que los lotes, y
-- porque la tabla es append-only. Pero append-only lo sostiene SOLO la RLS —hoy
-- toda tabla le da UPDATE a `authenticated` por el default de Supabase, que es
-- un pendiente abierto— y el SQL Editor entra como `postgres`, que pasa la RLS
-- de largo. El trigger ata a los dos.
create or replace function ent_alisto_linea_excluyente_guard()
returns trigger language plpgsql as $guard$
declare
  marcada boolean;
begin
  select l.no_se_entrega into marcada
    from ent_alisto_linea l where l.id = new.linea_id;
  if marcada is null then
    raise exception 'no existe la linea % de ent_alisto_linea', new.linea_id;
  end if;
  if marcada then
    raise exception
      'la linea % esta marcada "no se entrega": no puede llevar lote. Una linea o salio del '
      'congelador (y dice de que lote, o dice NO DETERMINADO) o no salio. Las dos cosas a la '
      'vez no describen nada fisico.', new.linea_id;
  end if;
  return new;
end
$guard$;

drop trigger if exists ent_alisto_lote_excluyente_trg on ent_alisto_lote;
create trigger ent_alisto_lote_excluyente_trg
  before insert on ent_alisto_lote
  for each row execute function ent_alisto_linea_excluyente_guard();

-- El otro sentido: no se le puede poner la marca a una linea que ya tiene lotes.
create or replace function ent_alisto_linea_marca_guard()
returns trigger language plpgsql as $guard$
begin
  if new.no_se_entrega and not coalesce(old.no_se_entrega, false)
     and exists (select 1 from ent_alisto_lote al where al.linea_id = new.id) then
    raise exception
      'la linea % ya tiene lotes registrados: no se puede marcar "no se entrega" encima. Para '
      'deshacer una salida que si ocurrio se anula el alisto y se registra de nuevo, que deja '
      'rastro de las dos versiones.', new.id;
  end if;
  return new;
end
$guard$;

drop trigger if exists ent_alisto_linea_marca_trg on ent_alisto_linea;
create trigger ent_alisto_linea_marca_trg
  before update on ent_alisto_linea
  for each row execute function ent_alisto_linea_marca_guard();


-- ════════════════════════════════════════════════════════════════════════
-- 3 · 3.2 · LA AUTORIZACION · el permiso de socias, sin frenar el camion
-- ════════════════════════════════════════════════════════════════════════
-- LA DECISION DE FONDO, APROBADA POR ANDREA EL 10-SEP:
-- la MARCA la puede escribir cualquiera que este alistando (Daniel incluido), y
-- la AUTORIZACION solo una socia. Son dos hechos distintos en dos momentos
-- distintos, no dos permisos sobre el mismo campo.
--
-- Por que asi y no "solo socias escriben la marca":
--   · el alisto de Daniel CIERRA NORMAL y el pedido SALE. El camion se va antes
--     de que las socias validen — lo pidio Andrea explicitamente. Si la marca
--     necesitara permiso de socia para escribirse, el alisto no podria cerrar;
--   · una marca sin autorizar ya es un dato completo y honesto: tiene motivo,
--     firma y hora, y el candado del §1 lo garantiza. Lo que le falta es el
--     visto bueno, que es justo lo que esta tabla registra;
--   · es la MISMA forma que 'NO DETERMINADO': Daniel registra la excepcion
--     frente a la caja, las socias la resuelven despues
--     (ent_alisto_lote_correccion). Un segundo mecanismo para el mismo tipo de
--     acto seria un segundo camino que se desincroniza.
--
-- ⚠️ LA ALTERNATIVA QUE SE DESCARTO (10-sep): que la marca fuera literalmente
-- socias-only y lo de Daniel una fila aparte ("señalado"). Queda escrita porque
-- el motivo de descartarla sigue valiendo si alguien la vuelve a proponer: parte
-- el estado de la linea en dos tablas, y entonces el bloqueo duro —que es lo que
-- este bloque viene a unificar— tendria que leer las dos, y el candado
-- excluyente tambien.
create table if not exists ent_alisto_linea_autorizacion (
  id               bigint generated always as identity primary key,
  alisto_linea_id  bigint not null references ent_alisto_linea(id),
  decision         text   not null check (decision in ('autorizada','rechazada')),
  nota             text,
  creado_en        timestamptz not null default now(),
  creado_por       text   not null,
  -- Rechazar sin decir por que no es una decision, es un boton. La nota
  -- obligatoria la confirmo Andrea el 10-sep.
  constraint autorizacion_nota_ok check (
    decision <> 'rechazada' or (nota is not null and length(btrim(nota)) >= 10))
);
create index if not exists ent_alisto_linea_autorizacion_idx
  on ent_alisto_linea_autorizacion (alisto_linea_id, creado_en desc);

comment on table ent_alisto_linea_autorizacion is
  'El visto bueno de una socia sobre una linea marcada "no se entrega". Append-only: manda la '
  'fila mas reciente por alisto_linea_id. NINGUNA de las dos decisiones mueve un saldo: el pan '
  'ya salio o ya no salio, y eso es un hecho fisico cerrado. "rechazada" dice "esto no debio '
  'marcarse" y deja el caso a la vista; deshacerlo de verdad es anular el alisto y registrarlo '
  'de nuevo, que es el unico camino que deja rastro de las dos versiones.';

-- ── EL GUARDIA · mismo patron que ent_alisto_lote_correccion_guard ──────
create or replace function ent_alisto_linea_autorizacion_guard()
returns trigger language plpgsql as $guard$
declare
  marcada boolean;
  quien   text;
begin
  select l.no_se_entrega into marcada
    from ent_alisto_linea l where l.id = new.alisto_linea_id;
  if marcada is null then
    raise exception 'no existe la linea % de ent_alisto_linea', new.alisto_linea_id;
  end if;
  if not marcada then
    raise exception
      'la linea % no esta marcada "no se entrega": no hay nada que autorizar.', new.alisto_linea_id;
  end if;

  quien := nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email';

  if quien is not null then
    -- Sesion de la app. La firma no se elige: tiene que ser quien esta adentro.
    if lower(btrim(new.creado_por)) <> lower(btrim(quien)) then
      raise exception 'creado_por dice % y la sesion es de %. La firma no se elige.',
        new.creado_por, quien;
    end if;
    if not exists (select 1 from acceso_usuario a
                    where lower(a.email) = lower(quien)
                      and a.perfil = 'socias' and a.activo) then
      raise exception 'solo un perfil socias autoriza que una linea no se entregue, y % no lo es. '
        'Marcarla SI puede cualquiera que este alistando (es el que esta frente al congelador); '
        'autorizarla despues es de las socias.', quien;
    end if;
  else
    -- Sin JWT: SQL Editor, o sea `postgres`. La base no puede saber quien
    -- escribe, y eso se dice en vez de fingir que si.
    if new.creado_por not like 'autorizacion-sql%' then
      raise exception 'una autorizacion sin sesion de Supabase (SQL Editor) tiene que firmar '
        'creado_por empezando con "autorizacion-sql", para que se distinga de una hecha desde '
        'la app. Vino: %', new.creado_por;
    end if;
  end if;

  return new;
end
$guard$;

drop trigger if exists ent_alisto_linea_autorizacion_guard_trg on ent_alisto_linea_autorizacion;
create trigger ent_alisto_linea_autorizacion_guard_trg
  before insert on ent_alisto_linea_autorizacion
  for each row execute function ent_alisto_linea_autorizacion_guard();

-- Andrea y Lorena tienen el MISMO poder: no hay jerarquia dentro de 'socias', y
-- ningun correo aparece escrito adentro de una politica ni de un trigger. El
-- quien sale siempre de acceso_usuario.perfil.


-- ════════════════════════════════════════════════════════════════════════
-- 4 · 3.3 · 'NO DETERMINADO' TAMBIEN EN EL CONTEO, con su motivo
-- ════════════════════════════════════════════════════════════════════════
-- El alisto ya tiene el centinela y su motivo desde el 8-sep. El Conteo no, y
-- por eso `_clAgregar` sigue siendo la unica salida cuando no se puede leer un
-- lote — una salida que escribe texto libre y que es justo la razon por la que
-- el candado de forma de ent_conteo_linea quedo sin poner.
--
-- ⚠️ EL CENTINELA SIGNIFICA COSAS DISTINTAS EN CADA TABLA, y conviene decirlo:
--   en el ALISTO   'NO DETERMINADO' es producto que SALIO y no se sabe de donde
--                  → resta, y aparece como "Salidas sin lote imputado";
--   en el CONTEO   es una caja que ESTA en el congelador y no se le puede leer
--                  el lote → suma al producto, sin poder asignarse a ningun lote.
-- Es la misma cadena y la misma disciplina (lista cerrada, motivo obligatorio),
-- pero NO son la misma fila ni se cancelan entre si. Que el ancla nueva vacie el
-- balde del alisto (medido en la verificacion 8c del 8-sep) no dice nada sobre
-- este; este NACE con el ancla.
alter table ent_conteo_linea
  add column if not exists motivo_indeterminado text,
  add column if not exists indeterminado_por    text,
  add column if not exists indeterminado_en     timestamptz;

comment on column ent_conteo_linea.motivo_indeterminado is
  'Por que esta caja se conto sin poder identificar su lote. Obligatorio cuando lote = NO DETERMINADO.';

-- Misma lista cerrada de cuatro, sin "otro" y sin texto libre, que la del
-- alisto: el motivo es EL DATO y un campo libre no se puede sumar.
alter table ent_conteo_linea
  drop constraint if exists ent_conteo_linea_motivo_ok;
alter table ent_conteo_linea
  add constraint ent_conteo_linea_motivo_ok check (
    lote <> 'NO DETERMINADO' or (
      motivo_indeterminado in ('sticker_caido','caja_sin_sticker',
                               'chofer_no_reporto','no_se_anoto')
      and indeterminado_por is not null
      and length(btrim(indeterminado_por)) > 0
      and indeterminado_en is not null));
-- VALID, y §0b es la medicion que lo permite. Si 0b no da cero, este ALTER falla
-- y hay que decidir antes que motivo llevan esas filas.


-- ════════════════════════════════════════════════════════════════════════
-- 5 · LA LISTA DE LAS SOCIAS · UNA sola, con las dos excepciones
-- ════════════════════════════════════════════════════════════════════════
-- `v_ent_indeterminado_pendiente` se creo el 8-sep y NO LA LEE NADIE: grepeada
-- hoy, sus dos apariciones fuera de su propio archivo son
-- MIGRACION_B56_FANTASMAS.sql y VERIFICACION_B56_MIGRACION.sql, los dos scripts
-- sueltos. Es exactamente el punto ciego 2 de esquema_check documentado en
-- CLAUDE.md: un esquema que nadie consulta no puede faltarle a nadie, y el ✓ no
-- se mueve. Esta vista la reemplaza y le da su primer lector vivo.
--
-- UNA sola vista y no dos porque la pregunta de la socia es UNA: "¿que quedo
-- pendiente de resolver?". Dos listas obligan a mirar dos lugares para contestar
-- una pregunta, y la segunda es la que nadie abre.
create or replace view v_ent_excepcion_pendiente
  with (security_invoker = true) as
  -- (a) salio sin lote imputado y todavia no se le asigno el real
  select 'lote_no_determinado'::text        as tipo,
         p.id                               as pedido_id,
         p.origen,
         p.cliente_nombre,
         coalesce(fv.factura_nombre, p.factura_nombre) as factura_nombre,
         ali.producto_id,
         ale.cant_uds                       as cant_uds,
         ale.motivo_indeterminado           as motivo,
         null::text                         as nota,
         ale.excepcion_por                  as registrada_por,
         av.preparado_en,
         ale.id                             as alisto_lote_id,
         null::bigint                       as alisto_linea_id
    from ent_alisto_lote_efectivo ale
    join ent_alisto_linea  ali on ali.id       = ale.linea_id
    join ent_alisto_vigente av on av.alisto_id = ali.alisto_id
    join ent_pedido        p   on p.id         = av.pedido_id
    left join ent_pedido_factura_vigente fv
           on fv.pedido_id = p.id and fv.anulado = false
   where ale.lote = 'NO DETERMINADO'

  union all

  -- (b) no salio, y ninguna socia lo autorizo todavia
  select 'no_se_entrega'::text,
         p.id,
         p.origen,
         p.cliente_nombre,
         coalesce(fv.factura_nombre, p.factura_nombre),
         ali.producto_id,
         ali.cant_no_entregada,
         ali.motivo_no_entrega,
         ali.nota_no_entrega,
         ali.no_entrega_por,
         av.preparado_en,
         null::bigint,
         ali.id
    from ent_alisto_linea  ali
    join ent_alisto_vigente av on av.alisto_id = ali.alisto_id
    join ent_pedido        p   on p.id         = av.pedido_id
    left join ent_pedido_factura_vigente fv
           on fv.pedido_id = p.id and fv.anulado = false
    left join lateral (
      select x.decision
        from ent_alisto_linea_autorizacion x
       where x.alisto_linea_id = ali.id
       order by x.creado_en desc
       limit 1) au on true
   where ali.no_se_entrega
     and au.decision is null;   -- autorizada Y rechazada salen de la lista: las dos son
                                -- una decision tomada. Lo pendiente es lo NO decidido.

-- ⚠️ SOLO MIRA EL ALISTO VIGENTE, las dos mitades. Una excepcion que colgaba de
-- un alisto anulado y reemplazado no es un pendiente: se fue con el alisto.

-- El contador para el lobby. Sale de la MISMA vista —una sola definicion de
-- "pendiente"— y por pedido, que es la unidad en la que se mira.
create or replace view v_ent_excepcion_pendiente_pedido
  with (security_invoker = true) as
  select pedido_id,
         min(preparado_en)                                          as desde,
         count(*)                                                   as n,
         count(*) filter (where tipo = 'no_se_entrega')             as n_no_entrega,
         count(*) filter (where tipo = 'lote_no_determinado')       as n_sin_lote,
         max(cliente_nombre)                                        as cliente_nombre,
         max(factura_nombre)                                        as factura_nombre
    from v_ent_excepcion_pendiente
   group by pedido_id;


-- ════════════════════════════════════════════════════════════════════════
-- 6 · RLS Y GRANTS
-- ════════════════════════════════════════════════════════════════════════
-- Sin politica de update ni de delete: append-only se niega por ausencia, igual
-- que en todas las tablas del modulo.
alter table ent_alisto_linea_autorizacion enable row level security;

drop policy if exists ent_alisto_linea_autorizacion_sel on ent_alisto_linea_autorizacion;
drop policy if exists ent_alisto_linea_autorizacion_ins on ent_alisto_linea_autorizacion;

create policy ent_alisto_linea_autorizacion_sel on ent_alisto_linea_autorizacion
  for select to authenticated using (true);

-- Capa 1 del permiso: la RLS niega el insert a quien no sea socias. El trigger
-- dice lo mismo y ata tambien al SQL Editor. Dos capas, como pg_lector y odoo_read.
--
-- USA `acceso_es_socia()`, que ya existe desde el 24-ago (ACCESOS_ESQUEMA.sql) y
-- es la definicion unica de "es socia" del sistema. La politica del 8-sep en
-- ent_alisto_lote_correccion re-escribio la condicion a mano en vez de llamarla.
-- ⚠️ DEUDA ANOTADA, NO SE TOCA HOY (decision de Andrea, 10-sep): va con la sesion
-- de GRANTS, junto con el DELETE/UPDATE/TRUNCATE que el default de Supabase le da
-- a `anon` y `authenticated`. Son dos redacciones de la misma regla, que es como
-- empiezan a desincronizarse — pero abrirlo hoy es tocar permisos el dia del
-- conteo.
create policy ent_alisto_linea_autorizacion_ins on ent_alisto_linea_autorizacion
  for insert to authenticated with check (acceso_es_socia());

grant select, insert on ent_alisto_linea_autorizacion to authenticated;
grant select on v_ent_excepcion_pendiente         to authenticated;
grant select on v_ent_excepcion_pendiente_pedido  to authenticated;


-- ── EL NOMBRE VIEJO: se propone borrarlo, y va APARTE ───────────────────
-- Unica linea destructiva del archivo, y la decide Andrea. Redefinir
-- v_ent_indeterminado_pendiente apuntando a la nueva seria gratis e inutil:
-- dejaria vivo un segundo nombre para el mismo dato justo cuando se acaba de
-- unificar — el mismo error que ent_entregado_desde_ancla, que lleva tres
-- semanas de mas. Nadie la lee (grepeado el 10-sep).
--
--   drop view if exists v_ent_indeterminado_pendiente;


-- ════════════════════════════════════════════════════════════════════════
-- 7 · LAS VERIFICACIONES · pegar DESPUES, UNA POR UNA
-- ════════════════════════════════════════════════════════════════════════
-- Varias terminan a proposito en error, y un error aborta el resto del lote si
-- se pegan todas juntas.

-- ── 7a · EL EXCLUYENTE, SENTIDO (a). TIENE QUE DAR ERROR ─────────────────
-- El error ES el resultado bueno. Envuelto en transaccion: no deja nada.
--
--   begin;
--     -- se marca una linea cualquiera SIN lotes y se le intenta colgar uno
--     update ent_alisto_linea set no_se_entrega = true, motivo_no_entrega = 'agotado',
--            no_entrega_por = 'prueba', no_entrega_en = now(), cant_uds = 0, cant_uom = 0
--      where id = (select l.id from ent_alisto_linea l
--                   where not exists (select 1 from ent_alisto_lote al where al.linea_id = l.id)
--                   order by l.id desc limit 1);
--     insert into ent_alisto_lote (linea_id, lote, cant_uds, orden)
--     select l.id, '001 / 1-27', 1, 0 from ent_alisto_linea l
--      where l.no_se_entrega order by l.id desc limit 1;
--   rollback;
--
-- ESPERADO: 'la linea N esta marcada "no se entrega": no puede llevar lote'.
-- Si el insert PASA, el trigger no esta puesto: PARAR.

-- ── 7b · EL EXCLUYENTE, SENTIDO (b). TIENE QUE DAR ERROR ─────────────────
--   begin;
--     update ent_alisto_linea set no_se_entrega = true, motivo_no_entrega = 'agotado',
--            no_entrega_por = 'prueba', no_entrega_en = now(), cant_uds = 0, cant_uom = 0
--      where id = (select al.linea_id from ent_alisto_lote al order by al.id desc limit 1);
--   rollback;
--
-- ESPERADO: 'la linea N ya tiene lotes registrados'.

-- ── 7c · EL CHECK DE §1, LAS CUATRO ESQUINAS. TIENEN QUE DAR ERROR ───────
-- Marcada sin motivo · motivo 'otro' sin nota · marcada con cant_uds > 0 ·
-- sin marcar pero con motivo puesto. Cada una sola, cada una en su begin/rollback.
--
--   begin; update ent_alisto_linea set no_se_entrega = true where id = <una sin lotes>; rollback;
--   ESPERADO: 'violates check constraint "ent_alisto_linea_no_entrega_ok"'.

-- ── 7d · EL PERMISO. Con sesion de Daniel, desde la app ──────────────────
-- No se puede probar desde el SQL Editor: ahi no hay JWT y el guardia toma la
-- otra rama a proposito. Se prueba EN LA PANTALLA, con Daniel adentro:
--   · marcar una linea "no se entrega"  → tiene que GUARDAR;
--   · intentar autorizarla              → tiene que decir que lo autoriza una socia.
-- Y despues con Andrea o Lorena adentro: autorizar tiene que guardar.
-- ⚠️ Esto no se cita: se corre. Es la regla mas cara del repo (el candado de
-- produccion se dio por real durante meses sin que nadie lo midiera).

-- ── 7e · NINGUN SALDO SE MOVIO ───────────────────────────────────────────
-- ⚠️ DIFERENCIAL, no contra numeros medidos otro dia. Comparar la misma consulta
-- ANTES y DESPUES de pegar, en la misma sesion. Un "esperado" copiado de una
-- medicion de ayer ya fallo una vez (bitacora 8-sep): con doce pedidos de por
-- medio parecio que la correccion habia roto los seis saldos.
--
-- LA SALIDA VA EN UNIDAD DE VENTA, no en unidades sueltas.
with pres(producto_id, nombre, div, rotulo) as (values
  (451,'Pan Blanco',      1, 'unidades'),
  (452,'Pan de Semillas', 1, 'unidades'),
  (453,'Pan Frances',     4, 'paquetes'),
  (472,'Pizza Crust',     2, 'paquetes'),
  (503,'Buns',            4, 'paquetes'),
  (519,'Galletas',        1, 'unidades'))
select pres.nombre as producto, s.lote,
       round(sum(s.uds) / pres.div, 3) as cantidad, pres.rotulo as unidad
  from ent_salido_del_congelador_desde_ancla s
  join pres on pres.producto_id = s.producto_id
 group by pres.nombre, pres.rotulo, pres.div, s.lote
 order by pres.nombre, s.lote;
-- ESPERADO: identico antes y despues. Este archivo no toca ninguna fila de
-- ent_alisto_lote; si algo cambia acá, algo esta mal.

-- ── 7f · LA VISTA NUEVA ARRANCA VACIA (o casi) ──────────────────────────
select tipo, count(*) from v_ent_excepcion_pendiente group by tipo;
-- ESPERADO: cero filas de 'no_se_entrega' (la marca no existia hasta hoy), y las
-- de 'lote_no_determinado' que haya. Medir cuantas son ANTES, con la vista vieja:
--   select count(*) from v_ent_indeterminado_pendiente;
-- Los dos numeros tienen que dar IGUAL. Si no, la mitad (a) cambio de semantica
-- sin querer: PARAR.
