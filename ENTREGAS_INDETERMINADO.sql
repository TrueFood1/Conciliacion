-- ════════════════════════════════════════════════════════════════════════
-- b56 · "NO DETERMINADO": la excepcion con nombre, motivo y dueño
-- PROPUESTA. NO PEGAR todavia — Andrea aprueba antes.
--
-- ── QUE PROBLEMA RESUELVE ───────────────────────────────────────────────
-- El campo de texto libre del alisto acepta cualquier cadena y la trata como
-- lote. El bloqueo duro cuenta CANTIDADES, no lotes identificados, asi que se
-- cumple igual con "SIN LOTE", con "asdf" o con un numero mal tecleado. El
-- modulo nacio para hacer imposibles los typos de lote de la hoja de Daniel y
-- esa puerta quedo abierta.
--
-- El caso legitimo existe: se cae el sticker de la caja y nadie sabe el lote.
-- Pasa poco pero pasa, y si la pantalla no lo permite, Daniel inventa un lote o
-- no registra. Que exista no es el problema. Que salga GRATIS y DISFRAZADO de
-- lote, si.
--
-- ── LO QUE YA ESTA PASANDO, MEDIDO EL 8-SEP ─────────────────────────────
-- El balde ya existe, en la peor forma posible: seis filas escritas a mano en
-- DOS ortografias distintas, que la base trata como dos lotes separados y que
-- aparecen en el saldo como lotes fantasma con saldo negativo:
--     451 Pan Blanco  'sin lote' → −104      451 Pan Blanco  'Sin lote' → −1
--     452 Semillas    'sin lote' →   −2      453 Pan Frances 'sin lote' → −8
--     503 Buns        'sin lote' →   −8
-- Total, en unidad de VENTA: Blanco 105 unidades · Semillas 2 unidades ·
-- Frances 2 paquetes · Buns 2 paquetes.
-- Hay una septima cadena invalida, '183 - 12/26' (pedido 2, 18-ago, Pizza): es un
-- lote REAL mal transcrito, su alisto fue reemplazado por el 12 y se verifico que
-- NO aparece en el saldo. Queda quieta. No se migra.
--
-- ── LA DECISION DE FONDO: UN CENTINELA, NO UNA COLUMNA NUEVA ────────────
-- 'NO DETERMINADO' es un VALOR de `lote`, no un booleano aparte. El motor indexa
-- por `producto|lote` como texto en todas partes, asi que con centinela el balde
-- es UNA clave conocida por producto y la maquinaria de saldos sigue igual. Con
-- una columna nueva habria que cambiar las tres vistas y el render, y quedaria un
-- segundo camino para la misma pregunta.
--
-- ── LAS CUATRO OPCIONES DE MOTIVO ───────────────────────────────────────
--   sticker_caido        se cayo el sticker
--   caja_sin_sticker     la caja vino sin sticker
--   chofer_no_reporto    el chofer no reporto los lotes
--   no_se_anoto          no se anoto al momento
-- Lista cerrada, sin "otro" y sin texto libre: el motivo es EL DATO y un campo
-- libre no se puede sumar.
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- 1 · EL MOTIVO VIVE EN LA MISMA FILA, Y EL CANDADO ES DEL MOTOR
-- ════════════════════════════════════════════════════════════════════════
-- Va en `ent_alisto_lote` y no en una tabla aparte a proposito: asi el motivo
-- entra en el MISMO insert que el lote, y no existe el estado intermedio "linea
-- sin lote y sin motivo". "Sin motivo no se puede guardar" pasa a ser un candado
-- de la base, no una validacion de pantalla.
alter table ent_alisto_lote
  add column if not exists motivo_indeterminado text,
  add column if not exists indeterminado_por    text,
  add column if not exists indeterminado_en     timestamptz;

comment on column ent_alisto_lote.motivo_indeterminado is
  'Por que esta linea salio sin lote identificado. Obligatorio cuando lote = NO DETERMINADO.';
comment on column ent_alisto_lote.indeterminado_por is
  'Quien registro la excepcion (email de la sesion de Supabase).';

-- VA VALID, NO "not valid". Se verifico contra las cadenas exactas del censo: las
-- siete filas invalidas de hoy dicen 'sin lote', 'Sin lote' y '183 - 12/26', que
-- son todas <> 'NO DETERMINADO', asi que pasan el check sin excepcion.
alter table ent_alisto_lote
  drop constraint if exists ent_alisto_lote_motivo_ok;
alter table ent_alisto_lote
  add constraint ent_alisto_lote_motivo_ok check (
    lote <> 'NO DETERMINADO' or (
      motivo_indeterminado in ('sticker_caido','caja_sin_sticker',
                               'chofer_no_reporto','no_se_anoto')
      and indeterminado_por is not null
      and length(btrim(indeterminado_por)) > 0
      and indeterminado_en is not null));


-- ════════════════════════════════════════════════════════════════════════
-- 2 · LA TABLA UNICA: retirar los fantasmas Y resolver la excepcion despues
-- ════════════════════════════════════════════════════════════════════════
-- Una sola tabla hace los dos trabajos porque son EL MISMO HECHO: "el lote
-- efectivo de esta fila no es el que dice la fila".
--   · retirar un fantasma  = una fila con lote = 'NO DETERMINADO' y su motivo
--   · resolver la excepcion = una fila con el lote real y su fuente
-- Append-only: la vigente es la mas reciente por alisto_lote_id. El original no
-- se borra ni se edita nunca.
create table if not exists ent_alisto_lote_correccion (
  id             bigint generated always as identity primary key,
  alisto_lote_id bigint not null references ent_alisto_lote(id),
  lote           text   not null,
  motivo         text,
  fuente         text,
  nota           text,
  creado_en      timestamptz not null default now(),
  creado_por     text   not null,

  -- forma canonica DDD / M-AA, o el centinela. Nada mas.
  constraint correccion_lote_forma check (
    lote ~ '^\d{1,3} / \d{1,2}-\d{2}$' or lote = 'NO DETERMINADO'),

  -- si es el centinela, el motivo es obligatorio y de la lista cerrada.
  constraint correccion_motivo_ok check (
    lote <> 'NO DETERMINADO' or motivo in ('sticker_caido','caja_sin_sticker',
                                           'chofer_no_reporto','no_se_anoto')),

  -- SI ES UN LOTE REAL, LA FUENTE ES OBLIGATORIA. Una resolucion sin decir de
  -- donde salio el dato es un lote inventado con papeles. El minimo de 10
  -- caracteres es a proposito: no alcanza para escribir "ok" ni "si", y si alcanza
  -- para nombrar un documento ("comprobante CEDI 7-sep").
  constraint correccion_fuente_ok check (
    lote = 'NO DETERMINADO' or (fuente is not null and length(btrim(fuente)) >= 10))
);
create index if not exists ent_alisto_lote_correccion_idx
  on ent_alisto_lote_correccion (alisto_lote_id, creado_en desc);

comment on table ent_alisto_lote_correccion is
  'El lote EFECTIVO de una fila de ent_alisto_lote cuando el guardado es una excepcion. '
  'Retira los fantasmas historicos y resuelve un NO DETERMINADO cuando aparece el dato. '
  'Append-only: manda la fila mas reciente por alisto_lote_id.';


-- ════════════════════════════════════════════════════════════════════════
-- 3 · EL FRENO. Dos capas, como pg_lector y odoo_read
-- ════════════════════════════════════════════════════════════════════════
-- EL RIESGO QUE FRENA (lo dijo Andrea, y tiene razon): tal como quedaria sin esto,
-- la tabla aceptaria un lote real ENCIMA de otro lote real. Hasta hoy, cambiar el
-- lote de una entrega cerrada era imposible por diseño, y esa imposibilidad es lo
-- que hace confiable el registro. Sin freno, cualquiera con acceso al SQL
-- reescribe a que lote se cargo una salida y el saldo se mueve sin aviso.
--
-- POR QUE UN TRIGGER Y NO UN CHECK: un CHECK solo ve las columnas de su propia
-- fila — Postgres no admite subconsultas en un CHECK — y el freno necesita mirar
-- la fila ORIGINAL, que esta en otra tabla.
-- POR QUE UN TRIGGER Y NO SOLO RLS: el SQL Editor de Supabase entra como
-- `postgres`, y un superusuario pasa la RLS de largo. El trigger ata a TODOS.
-- Se ponen los dos igual, que es la doctrina del proyecto: pg_lector lleva la
-- allowlist de Python Y el BEGIN TRANSACTION READ ONLY del servidor, y odoo_read
-- lleva el permiso de Odoo Y su lista. Uno es la red, el otro es el que manda.
create or replace function ent_alisto_lote_correccion_guard()
returns trigger language plpgsql as $guard$
declare
  original text;
  quien    text;
begin
  select al.lote into original from ent_alisto_lote al where al.id = new.alisto_lote_id;
  if original is null then
    raise exception 'no existe la fila % de ent_alisto_lote', new.alisto_lote_id;
  end if;

  -- ── FRENO 1 · SOLO SE CORRIGE UNA EXCEPCION ──────────────────────────
  -- Si el original ya tiene un lote bien formado, no se toca: ni para ponerle
  -- otro lote real ni para marcarlo como excepcion.
  if original ~ '^\d{1,3} / \d{1,2}-\d{2}$' then
    raise exception
      'la fila % de ent_alisto_lote ya tiene un lote real (%). Esta tabla solo resuelve '
      'EXCEPCIONES: filas con NO DETERMINADO, o con una cadena que no tiene forma de lote. '
      'Cambiar a que lote se cargo una salida ya cerrada no entra por aca: para eso se '
      'anula el alisto y se registra de nuevo, que deja rastro de las dos versiones.',
      new.alisto_lote_id, original;
  end if;

  -- ── FRENO 2 · QUIEN ──────────────────────────────────────────────────
  -- La regla ya estaba decidida: la excepcion la resuelve Andrea, no Daniel. Vive
  -- en `acceso_usuario.perfil`, que existe y esta sembrada desde el 24-ago, asi
  -- que no hay ningun correo escrito adentro de una politica.
  quien := nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email';

  if quien is not null then
    -- Sesion de la app. `creado_por` no se elige: tiene que ser quien esta adentro.
    if lower(btrim(new.creado_por)) <> lower(btrim(quien)) then
      raise exception 'creado_por dice % y la sesion es de %. La firma no se elige.',
        new.creado_por, quien;
    end if;
    if not exists (select 1 from acceso_usuario a
                    where lower(a.email) = lower(quien)
                      and a.perfil = 'socias' and a.activo) then
      raise exception 'solo un perfil socias resuelve una excepcion de lote, y % no lo es. '
        'Daniel SI puede registrar la excepcion en el alisto (es el que esta frente a la '
        'caja); resolverla despues es de las socias.', quien;
    end if;
  else
    -- Sin JWT: es una sesion de SQL Editor, o sea `postgres`. La base NO puede
    -- saber quien la escribe, y eso hay que decirlo en vez de fingir que si.
    -- Lo unico que se puede exigir es que la firma lo declare.
    if new.creado_por not like 'correccion-sql%' then
      raise exception 'una correccion sin sesion de Supabase (SQL Editor) tiene que firmar '
        'creado_por empezando con "correccion-sql", para que se distinga de una hecha desde '
        'la app. Vino: %', new.creado_por;
    end if;
  end if;

  return new;
end
$guard$;

drop trigger if exists ent_alisto_lote_correccion_guard_trg on ent_alisto_lote_correccion;
create trigger ent_alisto_lote_correccion_guard_trg
  before insert on ent_alisto_lote_correccion
  for each row execute function ent_alisto_lote_correccion_guard();


-- ════════════════════════════════════════════════════════════════════════
-- 4 · EL LOTE EFECTIVO, EN UNA SOLA VISTA
-- ════════════════════════════════════════════════════════════════════════
create or replace view ent_alisto_lote_efectivo with (security_invoker = true) as
  select al.id, al.linea_id, al.cant_uds, al.orden,
         coalesce(c.lote, al.lote)                              as lote,
         al.lote                                                as lote_original,
         coalesce(c.motivo, al.motivo_indeterminado)            as motivo_indeterminado,
         coalesce(c.creado_por, al.indeterminado_por)           as excepcion_por,
         c.fuente                                               as resuelto_con,
         (c.id is not null)                                     as corregido
    from ent_alisto_lote al
    left join lateral (
      select x.id, x.lote, x.motivo, x.fuente, x.creado_por
        from ent_alisto_lote_correccion x
       where x.alisto_lote_id = al.id
       order by x.creado_en desc
       limit 1) c on true;


-- ════════════════════════════════════════════════════════════════════════
-- 5 · LOS DOS LECTORES VIVOS PASAN A LA VISTA
-- ════════════════════════════════════════════════════════════════════════
-- Se grepeo quien lee `ent_alisto_lote` de verdad. Objetos vivos: estas dos vistas
-- y nada mas. El resto de los ~40 hits del repo son scripts sueltos
-- (DIAGNOSTICO_*, CORRECCION_*, PEGADO_*, FOTO_*), que NO son objetos vivos:
-- quedan anotados y van a dar respuestas viejas si alguien los corre.
create or replace view ent_salido_del_congelador_desde_ancla
  with (security_invoker = true) as
  select al.lote, ali.producto_id, sum(al.cant_uds) as uds
    from ent_alisto_lote_efectivo al
    join ent_alisto_linea ali on ali.id        = al.linea_id
    join ent_alisto_vigente av on av.alisto_id = ali.alisto_id
    left join ent_salida_vigente sv on sv.alisto_id = av.alisto_id
   where coalesce(sv.salida_en, av.preparado_en) > (select corte from ent_ancla)
   group by al.lote, ali.producto_id;

-- ── EL ALIAS VIEJO: NO SE REDEFINE, SE PROPONE BORRARLO ─────────────────
-- `ent_entregado_desde_ancla` es el nombre de antes del 19-ago. ENTREGAS_ETAPAS.sql
-- lo declaro "vivo UN SOLO BUILD" y dejo escrito su `drop view if exists`; ya van
-- tres semanas. Grepeado el 8-sep: NO lo lee el index.html (solo lo menciona un
-- comentario) ni ningun otro objeto — las seis apariciones del repo son comentarios.
--
-- Redefinirlo apuntando a la vista nueva seria gratis pero inutil, y peor: dejaria
-- vivo un segundo nombre para el mismo dato justo cuando se acaba de unificar. Lo
-- correcto es borrarlo. Va APARTE y comentado, porque es la unica linea destructiva
-- de este archivo y la decide Andrea.
--
-- Primero, la prueba de que nada depende de el (tiene que dar 0 filas):
--   select dependent_ns.nspname, dependent_view.relname
--     from pg_depend d
--     join pg_rewrite r          on r.oid = d.objid
--     join pg_class dependent_view on dependent_view.oid = r.ev_class
--     join pg_namespace dependent_ns on dependent_ns.oid = dependent_view.relnamespace
--     join pg_class source_table on source_table.oid = d.refobjid
--    where source_table.relname = 'ent_entregado_desde_ancla'
--      and dependent_view.relname <> 'ent_entregado_desde_ancla';
--
-- Y despues, si da 0:
--   drop view if exists ent_entregado_desde_ancla;


-- ════════════════════════════════════════════════════════════════════════
-- 6 · LA LISTA DE REVISION DE ANDREA (punto 3.3)
-- ════════════════════════════════════════════════════════════════════════
-- Un pedido con una excepcion SIN resolver. El que ya se resolvio sale solo de la
-- lista, porque su lote efectivo deja de ser el centinela.
create or replace view v_ent_indeterminado_pendiente
  with (security_invoker = true) as
  select p.id                       as pedido_id,
         p.origen,
         p.cliente_nombre,
         coalesce(fv.factura_nombre, p.factura_nombre) as factura_nombre,
         ali.producto_id,
         ale.cant_uds,
         ale.motivo_indeterminado,
         ale.excepcion_por,
         av.preparado_en,
         ale.id                     as alisto_lote_id
    from ent_alisto_lote_efectivo ale
    join ent_alisto_linea  ali on ali.id        = ale.linea_id
    join ent_alisto_vigente av on av.alisto_id  = ali.alisto_id
    join ent_pedido        p   on p.id          = av.pedido_id
    left join ent_pedido_factura_vigente fv
           on fv.pedido_id = p.id and fv.anulado = false
   where ale.lote = 'NO DETERMINADO';


-- ════════════════════════════════════════════════════════════════════════
-- 7 · RLS Y GRANTS
-- ════════════════════════════════════════════════════════════════════════
-- Sin politica de update ni de delete: append-only se niega por ausencia, igual
-- que en todas las tablas del modulo.
alter table ent_alisto_lote_correccion enable row level security;

drop policy if exists ent_alisto_lote_correccion_sel on ent_alisto_lote_correccion;
drop policy if exists ent_alisto_lote_correccion_ins on ent_alisto_lote_correccion;

create policy ent_alisto_lote_correccion_sel on ent_alisto_lote_correccion
  for select to authenticated using (true);

-- La capa 1 del freno 2: la RLS niega el insert a quien no sea socias. El trigger
-- dice lo mismo y ata tambien al SQL Editor.
create policy ent_alisto_lote_correccion_ins on ent_alisto_lote_correccion
  for insert to authenticated with check (
    exists (select 1 from acceso_usuario a
             where lower(a.email) = lower(nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email')
               and a.perfil = 'socias' and a.activo));

grant select, insert on ent_alisto_lote_correccion to authenticated;
grant select on ent_alisto_lote_efectivo      to authenticated;
grant select on v_ent_indeterminado_pendiente to authenticated;


-- ════════════════════════════════════════════════════════════════════════
-- 8 · LAS VERIFICACIONES · pegar DESPUES, UNA POR UNA
-- ════════════════════════════════════════════════════════════════════════
-- Cada una va SOLA. Dos de ellas terminan a proposito en un error, y un error
-- aborta el resto del lote si se pegan todas juntas.

-- ── 8a · EL FRENO 1, PROBADO. TIENE QUE DAR ERROR ────────────────────────
-- El error ES el resultado bueno: significa que la tabla no acepta reescribir a
-- que lote se cargo una salida cerrada. Va envuelto en una transaccion que se
-- deshace, asi que no deja nada.
--
--   begin;
--     insert into ent_alisto_lote_correccion (alisto_lote_id, lote, fuente, creado_por)
--     select al.id, '999 / 12-27', 'prueba del freno, se deshace', 'correccion-sql · prueba'
--       from ent_alisto_lote al
--      where al.lote ~ '^\d{1,3} / \d{1,2}-\d{2}$'
--      order by al.id limit 1;
--   rollback;
--
-- ESPERADO: 'la fila N de ent_alisto_lote ya tiene un lote real (...)'.
-- Si el insert PASA, el trigger no esta puesto: PARAR y avisar.

-- ── 8b · EL "NOT VALID", MEDIDO EN VEZ DE CITADO ─────────────────────────
-- La pregunta de Andrea: ¿un CHECK agregado NOT VALID bloquea igual los INSERT y
-- UPDATE nuevos? Lo documentado dice que si (NOT VALID solo se saltea las filas
-- que YA estaban), pero no se cita: se mide. Esto es el ensayo del candado de
-- forma de 3.6b, que se aplica DESPUES de la migracion.
-- Las dos partes van en la MISMA transaccion y se deshace todo.
--
--   begin;
--     alter table ent_alisto_lote
--       add constraint prueba_forma check (
--         lote ~ '^\d{1,3} / \d{1,2}-\d{2}$' or lote = 'NO DETERMINADO') not valid;
--     -- si NOT VALID bloqueara solo lo viejo, este insert pasaria. Tiene que fallar:
--     insert into ent_alisto_lote (linea_id, lote, cant_uds, orden)
--     select al.linea_id, 'PRUEBA INVALIDA', 0, 99
--       from ent_alisto_lote al order by al.id limit 1;
--   rollback;
--
-- ESPERADO: 'new row for relation "ent_alisto_lote" violates check constraint
-- "prueba_forma"'. Si el insert PASA, NOT VALID no alcanza y el candado de 3.6b
-- hay que hacerlo de otra forma: PARAR y avisar.

-- ── 8c · EL RESETEO DEL BALDE ────────────────────────────────────────────
-- ✅ YA MEDIDO el 8-sep, ANTES de aplicar nada, y se pudo porque los lotes
-- fantasma se comportan igual que el centinela: 5 claves de lote invalidas con el
-- corte de hoy, CERO con el corte simulado del viernes 11-sep. El ancla nueva
-- vacia el balde sola. Se repite despues de migrar, cambiando el filtro de
-- "invalidas" por "= NO DETERMINADO":
select 'con el corte de HOY' as escenario,
       count(*) as claves_no_determinado
  from ent_salido_del_congelador_desde_ancla
 where lote = 'NO DETERMINADO'
union all
select 'con el corte SIMULADO del viernes', count(*)
  from (select al.lote
          from ent_alisto_lote_efectivo al
          join ent_alisto_linea ali on ali.id        = al.linea_id
          join ent_alisto_vigente av on av.alisto_id = ali.alisto_id
          left join ent_salida_vigente sv on sv.alisto_id = av.alisto_id
         where coalesce(sv.salida_en, av.preparado_en)
               > timestamptz '2026-09-11 18:00:00-06:00'
         group by al.lote) x
 where x.lote = 'NO DETERMINADO';

-- ── 8d · EL PEDIDO 48 NO SE MUEVE ────────────────────────────────────────
-- Esta PREPARADO y sin salida (factura 3520, Carne M D L, 8-sep). La migracion le
-- cambia el lote efectivo y NADA MAS: no le inventa salida, no le mueve el estado,
-- no lo saca de "Por entregar".
-- ESPERADO: estado 'preparado', salida_en nulo, y 3 lineas.
select pedido_id, cliente_nombre, factura_nombre, estado, n_lineas,
       (preparado_en at time zone 'America/Costa_Rica') as preparado_cr,
       salida_en
  from v_ent_pedido_estado
 where pedido_id = 48;

-- ── 8e · LOS SEIS FANTASMAS DESAPARECIERON, Y NINGUN LOTE REAL SE MOVIO ──
-- Despues de migrar: no queda ninguna cadena invalida tratada como lote, y el
-- balde por producto da lo esperado en unidad de VENTA — Blanco 105 unidades,
-- Semillas 2 unidades, Frances 2 paquetes, Buns 2 paquetes (o sea 105, 2, 8 y 8
-- unidades individuales, que es la escala de la columna).
select ali.producto_id, al.lote, sum(al.cant_uds) as uds_individuales
  from ent_alisto_lote_efectivo al
  join ent_alisto_linea ali on ali.id = al.linea_id
 where al.lote !~ '^\d{1,3} / \d{1,2}-\d{2}$'
 group by ali.producto_id, al.lote
 order by ali.producto_id, al.lote;
-- ESPERADO: solo filas con lote = 'NO DETERMINADO' — 451 → 105 · 452 → 2 ·
-- 453 → 8 · 503 → 8 — mas la unica fila que se deja quieta a proposito,
-- 472 con '183 - 12/26' → 84, del alisto reemplazado del 18-ago.
