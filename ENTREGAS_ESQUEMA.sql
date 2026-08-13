-- ════════════════════════════════════════════════════════════════════════
-- MÓDULO DE ENTREGAS · ESQUEMA SUPABASE
-- Aprobado 12-ago-2026. LISTO PARA PEGAR UNA SOLA VEZ en el SQL Editor.
--
-- Se puede correr más de una vez sin romper nada (todo es "if not exists" /
-- "or replace" / "drop policy if exists"). Si algo sale mal a mitad, se
-- corrige y se vuelve a pegar completo.
--
-- Principios (los mismos del resto de Truefie):
--  · APPEND-ONLY. Nada se actualiza ni se borra: corregir = insertar una fila
--    nueva y que gane la más reciente. Es lo que ya hacen plan_overrides y
--    semana_capacidad, y es lo que permite reconstruir qué se sabía y cuándo.
--  · La CLAVE de un lote es siempre PRODUCTO + LOTE. El número solo se repite:
--    "168 / 12-26" existe hoy en Pan de Semillas Y en Buns (verificado 11-ago).
--  · Odoo es SOLO LECTURA. Acá se guarda lo que Odoo no sabe: qué lote salió.
--  · El pedido guarda el ID de la factura de Odoo. Sin ese vínculo no hay
--    Fase C (que la confirmación de Daniel valide la entrega) ni control cruzado.
-- ════════════════════════════════════════════════════════════════════════


-- ── 1 · ANCLA DE INVENTARIO (el conteo del viernes) ─────────────────────
-- Un conteo = una foto del congelador. El del viernes 14-ago reemplaza al del
-- 17-jul. Se guardan varios a lo largo del tiempo; manda el más reciente.
-- El ancla SE REPITE: habrá otro conteo en unos meses, y ese pasa a ser el nuevo
-- punto de partida. No hay restricción de unicidad por fecha a propósito.
-- `corte` es el instante en que la foto fue verdad, y es LA línea divisoria:
-- todo lo fabricado y todo lo entregado se cuenta DESPUÉS de ese instante.
-- Se usa un timestamp y no la fecha porque el viernes 14 hay conteo Y puede
-- haber entregas el mismo día: con fecha suelta no se sabe cuál va primero.
create table if not exists ent_conteo (
  id           bigint generated always as identity primary key,
  fecha        date        not null,              -- el día que se contó, para leerlo
  corte        timestamptz not null default now(),-- el instante exacto: la línea divisoria
  responsable  text        not null,              -- quién contó (Daniel)
  nota         text,
  creado_en    timestamptz not null default now(),
  creado_por   text        not null               -- email del usuario de Supabase
);

create table if not exists ent_conteo_linea (
  id           bigint generated always as identity primary key,
  conteo_id    bigint  not null references ent_conteo(id),
  producto_id  integer not null,                  -- product.product de Odoo (451/452/453/472/503/519)
  lote         text    not null,                  -- forma canónica "154 / 12-26"
  cajas        numeric not null default 0,        -- Daniel cuenta cajas y sueltas POR SEPARADO
  sueltas      numeric not null default 0,        -- en unidades de venta
  uds          numeric not null,                  -- total en unidades individuales (derivado, se guarda)
  creado_en    timestamptz not null default now()
);
create index if not exists ent_conteo_linea_prod_lote_idx
  on ent_conteo_linea (producto_id, lote);


-- ── 2 · PEDIDOS MANDADOS A ENTREGAS ─────────────────────────────────────
-- Nace de una factura de Odoo (camino normal) o a mano (red de seguridad, para
-- cuando el pedido llega por texto y se factura después).
create table if not exists ent_pedido (
  id              bigint generated always as identity primary key,
  fecha_despacho  date        not null,
  origen          text        not null check (origen in ('factura','manual')),
  factura_id      integer,                        -- account.move.id de Odoo; null si es manual
  factura_nombre  text,                           -- consecutivo legible, para leerlo sin ir a Odoo
  cliente_id      integer     not null,           -- res.partner.id
  cliente_nombre  text        not null,           -- copia del nombre al momento (el alias cambia)
  canal           text,                           -- crm.team del cliente, informativo
  motivo          text check (motivo in ('venta','influencer','regalia','reposicion','consumo_interno','otro')),
  nota            text,
  creado_en       timestamptz not null default now(),
  creado_por      text        not null
);
-- Una factura no se manda dos veces. Los pedidos manuales quedan fuera del
-- índice (factura_id null) porque justamente todavía no tienen factura.
create unique index if not exists ent_pedido_factura_uidx
  on ent_pedido (factura_id) where factura_id is not null;
create index if not exists ent_pedido_despacho_idx
  on ent_pedido (fecha_despacho);

create table if not exists ent_pedido_linea (
  id            bigint generated always as identity primary key,
  pedido_id     bigint  not null references ent_pedido(id),
  producto_id   integer not null,
  cant_uds      numeric not null,                 -- lo pedido, en unidades individuales
  presentacion  text    not null check (presentacion in ('cj','uds')),
  cant_present  numeric not null                  -- el mismo número en la presentación que ve Daniel
);


-- ── 3 · EL ALISTO (lo que Daniel confirma) ──────────────────────────────
-- Evento append-only: si Daniel corrige, se inserta otro alisto del mismo
-- pedido y manda el de creado_en más reciente. No se edita el anterior.
create table if not exists ent_alisto (
  id          bigint generated always as identity primary key,
  pedido_id   bigint  not null references ent_pedido(id),
  responsable text    not null,                   -- quién alistó
  anulado     boolean not null default false,     -- "me equivoqué de pedido": se anula, no se borra
  nota        text,
  creado_en   timestamptz not null default now(),
  creado_por  text    not null
);
create index if not exists ent_alisto_pedido_idx
  on ent_alisto (pedido_id, creado_en desc);

create table if not exists ent_alisto_linea (
  id          bigint generated always as identity primary key,
  alisto_id   bigint  not null references ent_alisto(id),
  producto_id integer not null,
  cant_uds    numeric not null                    -- lo REALMENTE entregado (puede diferir de lo pedido)
);

-- ── EL CORAZÓN: una línea puede repartirse entre VARIOS lotes ───────────
-- 16 uds = 12 del lote 318 + 4 del 326 → dos filas acá.
create table if not exists ent_alisto_lote (
  id        bigint generated always as identity primary key,
  linea_id  bigint  not null references ent_alisto_linea(id),
  lote      text    not null,                     -- "154 / 12-26"; el producto sale de la línea
  cant_uds  numeric not null,
  orden     smallint not null default 0           -- en qué orden los tocó (del más viejo al más nuevo)
);
create index if not exists ent_alisto_lote_lote_idx
  on ent_alisto_lote (lote);


-- ── 4 · SALDO POR LOTE ──────────────────────────────────────────────────
-- No es una tabla: es una resta que se hace al vuelo, y se deja escrita acá
-- para que haya UNA sola definición.
--   saldo(producto,lote) = conteo del ANCLA VIGENTE
--                        + fabricado en Odoo   DESPUÉS del corte del ancla
--                        − entregado en este módulo DESPUÉS del corte del ancla
-- Lo fabricado sale del extractor de lote (chatter de mrp.production), no de
-- una tabla: Odoo no lleva lote en producto terminado (tracking = none en los
-- seis, y 1.604 movimientos de 2026 con cero lot_id — verificado 11-ago).
-- OJO al convertir date_finished a día CR (UTC−6) antes de comparar.

-- security_invoker = true es OBLIGATORIO en Supabase: sin eso la vista corre con
-- los permisos de quien la creó y se saltaría el RLS de las tablas de abajo.
--
-- El ancla vigente: el conteo más reciente. Si se corrige el mismo día, gana
-- el capturado después. Cuando entre el conteo de dentro de unos meses, esta
-- vista empieza a devolverlo sola y el saldo arranca de cero desde ahí.
create or replace view ent_ancla with (security_invoker = true) as
  select id, fecha, corte
    from ent_conteo
   order by fecha desc, creado_en desc
   limit 1;

-- Lo entregado DESDE EL ANCLA. El filtro por corte es lo que hace que el ancla
-- nuevo sea un punto de partida y no una suma más: sin él, las entregas
-- anteriores al conteo se restarían dos veces (ya están descontadas en la foto).
-- Antes del primer conteo esta vista devuelve CERO filas (no hay corte contra
-- el cual comparar). Es lo correcto: sin ancla no hay saldo que calcular.
create or replace view ent_entregado_desde_ancla with (security_invoker = true) as
  select al.lote, ali.producto_id, sum(al.cant_uds) as uds
    from ent_alisto_lote al
    join ent_alisto_linea ali on ali.id = al.linea_id
    join ent_alisto a         on a.id  = ali.alisto_id
   where a.anulado = false
     and a.creado_en > (select corte from ent_ancla)
     -- solo el alisto vigente de cada pedido (el más reciente no anulado)
     and a.creado_en = (select max(a2.creado_en) from ent_alisto a2
                         where a2.pedido_id = a.pedido_id and a2.anulado = false)
   group by al.lote, ali.producto_id;

-- Un lote que existía en el ancla anterior y NO aparece en el nuevo conteo
-- queda en cero, que es lo correcto: si no se contó, no está. Si igual sale
-- en una entrega, la pantalla lo acepta (regla e: propone, nunca bloquea) y
-- el saldo negativo es la señal de que hay que ajustar.


-- ── 5 · RLS ─────────────────────────────────────────────────────────────
-- Igual que la tabla de conteos que ya existe: entra quien tiene sesión.
-- Los roles finos (Daniel solo alista, Andrea manda pedidos) vienen después;
-- la primera semana Andrea opera la pantalla con Daniel al lado.
alter table ent_conteo        enable row level security;
alter table ent_conteo_linea  enable row level security;
alter table ent_pedido        enable row level security;
alter table ent_pedido_linea  enable row level security;
alter table ent_alisto        enable row level security;
alter table ent_alisto_linea  enable row level security;
alter table ent_alisto_lote   enable row level security;

-- Lectura y alta para cualquier usuario autenticado. NO hay update ni delete:
-- append-only se hace cumplir ACÁ, no solo por convención. Sin política de
-- update/delete, Postgres las niega — que es exactamente lo que queremos.

drop policy if exists ent_conteo_sel on ent_conteo;
drop policy if exists ent_conteo_ins on ent_conteo;
create policy ent_conteo_sel on ent_conteo
  for select to authenticated using (true);
create policy ent_conteo_ins on ent_conteo
  for insert to authenticated with check (true);

drop policy if exists ent_conteo_linea_sel on ent_conteo_linea;
drop policy if exists ent_conteo_linea_ins on ent_conteo_linea;
create policy ent_conteo_linea_sel on ent_conteo_linea
  for select to authenticated using (true);
create policy ent_conteo_linea_ins on ent_conteo_linea
  for insert to authenticated with check (true);

drop policy if exists ent_pedido_sel on ent_pedido;
drop policy if exists ent_pedido_ins on ent_pedido;
create policy ent_pedido_sel on ent_pedido
  for select to authenticated using (true);
create policy ent_pedido_ins on ent_pedido
  for insert to authenticated with check (true);

drop policy if exists ent_pedido_linea_sel on ent_pedido_linea;
drop policy if exists ent_pedido_linea_ins on ent_pedido_linea;
create policy ent_pedido_linea_sel on ent_pedido_linea
  for select to authenticated using (true);
create policy ent_pedido_linea_ins on ent_pedido_linea
  for insert to authenticated with check (true);

drop policy if exists ent_alisto_sel on ent_alisto;
drop policy if exists ent_alisto_ins on ent_alisto;
create policy ent_alisto_sel on ent_alisto
  for select to authenticated using (true);
create policy ent_alisto_ins on ent_alisto
  for insert to authenticated with check (true);

drop policy if exists ent_alisto_linea_sel on ent_alisto_linea;
drop policy if exists ent_alisto_linea_ins on ent_alisto_linea;
create policy ent_alisto_linea_sel on ent_alisto_linea
  for select to authenticated using (true);
create policy ent_alisto_linea_ins on ent_alisto_linea
  for insert to authenticated with check (true);

drop policy if exists ent_alisto_lote_sel on ent_alisto_lote;
drop policy if exists ent_alisto_lote_ins on ent_alisto_lote;
create policy ent_alisto_lote_sel on ent_alisto_lote
  for select to authenticated using (true);
create policy ent_alisto_lote_ins on ent_alisto_lote
  for insert to authenticated with check (true);


-- ── 5b · PERMISOS DE ROL ────────────────────────────────────────────────
-- Supabase normalmente ya concede esto por privilegios por defecto, pero se
-- deja explícito para que el pegado funcione sí o sí. Ojo: select+insert y
-- nada más. Sin update ni delete a nivel de permiso TAMBIÉN — doble candado
-- sobre el append-only (el RLS de arriba y el grant de acá).
grant usage on schema public to authenticated;
grant select, insert on ent_conteo        to authenticated;
grant select, insert on ent_conteo_linea  to authenticated;
grant select, insert on ent_pedido        to authenticated;
grant select, insert on ent_pedido_linea  to authenticated;
grant select, insert on ent_alisto        to authenticated;
grant select, insert on ent_alisto_linea  to authenticated;
grant select, insert on ent_alisto_lote   to authenticated;
grant select on ent_ancla                 to authenticated;
grant select on ent_entregado_desde_ancla to authenticated;
-- Las tablas usan "generated always as identity", que no crea secuencias con
-- permiso aparte, así que no hace falta grant usage on sequences.


-- ── 6 · EL REGISTRO AB-RE-04 SALE DE ACÁ ────────────────────────────────
-- Columnas del documento controlado de Daniel, y de dónde sale cada una:
--   Fecha de despacho  → ent_pedido.fecha_despacho
--   Cliente            → ent_pedido.cliente_nombre
--   Producto           → ent_alisto_linea.producto_id → nombre de las constantes
--   Cantidad Total     → ent_alisto_linea.cant_uds
--   Caja/Unid          → ent_pedido_linea.presentacion
--   Cantidad x Lote    → ent_alisto_lote.cant_uds
--   Lotes              → ent_alisto_lote.lote
--   Responsable        → ent_alisto.responsable


-- ── 7 · VERIFICACIÓN (opcional: devuelve una tabla con el resultado) ────
-- Si querés confirmar sin ir al Table Editor, corré esto después:
--   select table_name, 'tabla' as tipo from information_schema.tables
--    where table_schema='public' and table_name like 'ent\_%'
--   union all
--   select table_name, 'vista' from information_schema.views
--    where table_schema='public' and table_name like 'ent\_%'
--   order by tipo, table_name;
-- Tienen que salir 7 tablas y 2 vistas.
