-- ════════════════════════════════════════════════════════════════════════
-- MÓDULO DE ENTREGAS · ESQUEMA SUPABASE — PROPUESTA, NO CREADO TODAVÍA
-- Fecha: 11-ago-2026 · Requiere OK de Andrea antes de correrse.
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
create table ent_conteo (
  id           bigint generated always as identity primary key,
  fecha        date        not null,              -- el día que se contó (no el de captura)
  responsable  text        not null,              -- quién contó (Daniel)
  nota         text,
  creado_en    timestamptz not null default now(),
  creado_por   text        not null               -- email del usuario de Supabase
);

create table ent_conteo_linea (
  id           bigint generated always as identity primary key,
  conteo_id    bigint  not null references ent_conteo(id),
  producto_id  integer not null,                  -- product.product de Odoo (451/452/453/472/503/519)
  lote         text    not null,                  -- forma canónica "154 / 12-26"
  cajas        numeric not null default 0,        -- Daniel cuenta cajas y sueltas POR SEPARADO
  sueltas      numeric not null default 0,        -- en unidades de venta
  uds          numeric not null,                  -- total en unidades individuales (derivado, se guarda)
  creado_en    timestamptz not null default now()
);
create index on ent_conteo_linea (producto_id, lote);


-- ── 2 · PEDIDOS MANDADOS A ENTREGAS ─────────────────────────────────────
-- Nace de una factura de Odoo (camino normal) o a mano (red de seguridad, para
-- cuando el pedido llega por texto y se factura después).
create table ent_pedido (
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
create unique index on ent_pedido (factura_id) where factura_id is not null;
create index on ent_pedido (fecha_despacho);

create table ent_pedido_linea (
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
create table ent_alisto (
  id          bigint generated always as identity primary key,
  pedido_id   bigint  not null references ent_pedido(id),
  responsable text    not null,                   -- quién alistó
  anulado     boolean not null default false,     -- "me equivoqué de pedido": se anula, no se borra
  nota        text,
  creado_en   timestamptz not null default now(),
  creado_por  text    not null
);
create index on ent_alisto (pedido_id, creado_en desc);

create table ent_alisto_linea (
  id          bigint generated always as identity primary key,
  alisto_id   bigint  not null references ent_alisto(id),
  producto_id integer not null,
  cant_uds    numeric not null                    -- lo REALMENTE entregado (puede diferir de lo pedido)
);

-- ── EL CORAZÓN: una línea puede repartirse entre VARIOS lotes ───────────
-- 16 uds = 12 del lote 318 + 4 del 326 → dos filas acá.
create table ent_alisto_lote (
  id        bigint generated always as identity primary key,
  linea_id  bigint  not null references ent_alisto_linea(id),
  lote      text    not null,                     -- "154 / 12-26"; el producto sale de la línea
  cant_uds  numeric not null,
  orden     smallint not null default 0           -- en qué orden los tocó (del más viejo al más nuevo)
);
create index on ent_alisto_lote (lote);


-- ── 4 · SALDO POR LOTE ──────────────────────────────────────────────────
-- No es una tabla: es una resta que se hace al vuelo, y se deja escrita acá
-- para que haya UNA sola definición.
--   saldo(producto,lote) = conteo del ancla más reciente
--                        + fabricado en Odoo DESPUÉS de la fecha del ancla
--                        − entregado registrado en este módulo (alistos vigentes)
-- Lo fabricado sale del extractor de lote (chatter de mrp.production), no de
-- una tabla: Odoo no lleva lote en producto terminado (tracking = none en los
-- seis, y 1.604 movimientos de 2026 con cero lot_id — verificado 11-ago).
create view ent_entregado_por_lote as
  select al.lote, ali.producto_id, sum(al.cant_uds) as uds
    from ent_alisto_lote al
    join ent_alisto_linea ali on ali.id = al.linea_id
    join ent_alisto a         on a.id  = ali.alisto_id
   where a.anulado = false
     -- solo el alisto vigente de cada pedido (el más reciente no anulado)
     and a.creado_en = (select max(a2.creado_en) from ent_alisto a2
                         where a2.pedido_id = a.pedido_id and a2.anulado = false)
   group by al.lote, ali.producto_id;


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
-- append-only se hace cumplir acá, no solo por convención.
create policy ent_sel on ent_conteo       for select to authenticated using (true);
create policy ent_ins on ent_conteo       for insert to authenticated with check (true);
-- (mismo par de políticas para las otras seis tablas)


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
