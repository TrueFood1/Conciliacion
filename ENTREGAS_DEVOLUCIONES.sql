-- ════════════════════════════════════════════════════════════════════════
-- ENTREGAS · DEVOLUCIONES — 20-ago-2026. Re-ejecutable.
-- NO TOCA ODOO: todo es Supabase/Postgres.
--
-- POR QUE. El motor de saldos solo resta: ancla + produccion - salidas. Una
-- devolucion es una ENTRADA y no existe en ninguna parte, asi que el saldo por
-- lote queda subestimado cuando un cliente devuelve producto que vuelve al
-- congelador. Con el bloqueo duro de Despachos eso deja de ser cosmetico: un
-- saldo subestimado ahora IMPIDE despachar producto que si esta.
--
-- ALCANCE: solo lo que vuelve al congelador. Lo que se bota no se registra
-- (decision de Andrea). No hay ruta de desecho y no se construye una.
-- ════════════════════════════════════════════════════════════════════════


-- ── 1 · LA CABECERA ─────────────────────────────────────────────────────
-- Suelta: NO se liga a factura. Una devolucion llega por telefono o en el camion
-- de vuelta, y esperar a saber contra que factura fue es esperar a nunca.
--
-- DOS TIEMPOS, A PROPOSITO, igual que ent_conteo (fecha + corte):
--   `fecha`       el dia en que volvio el producto — lo que elige quien registra.
--   `recibido_en` el INSTANTE, para comparar contra el corte del ancla.
-- Con solo la fecha no se puede decidir una devolucion del mismo dia del conteo:
-- si volvio a las 17:00 y Daniel conto a las 16:00, cuenta; si volvio a las 10:00,
-- ya esta dentro de la foto. Una fecha suelta no distingue esos dos casos y el
-- saldo sale mal en silencio — que es justo el error que se pago caro el 19-ago.
create table if not exists ent_devolucion (
  id             bigint generated always as identity primary key,
  fecha          date        not null,
  recibido_en    timestamptz not null default now(),
  cliente_id     integer     not null,          -- res.partner.id de Odoo
  cliente_nombre text        not null,          -- copia del nombre al momento
  nota           text,
  creado_en      timestamptz not null default now(),
  creado_por     text        not null
);
create index if not exists ent_devolucion_fecha_idx on ent_devolucion (fecha desc);
create index if not exists ent_devolucion_cli_idx   on ent_devolucion (cliente_id, fecha desc);

comment on table  ent_devolucion             is 'Producto que volvio al congelador. Suelta: no se liga a factura. Lo que se bota NO se registra.';
comment on column ent_devolucion.recibido_en is 'El instante. Es lo que se compara contra el corte del ancla, no `fecha`.';


-- ── 2 · LA LINEA ────────────────────────────────────────────────────────
-- LA UNIDAD ES INDEPENDIENTE DE COMO SALIO. Caso real de Andrea: se vendio 1 caja
-- y devuelven 1 unidad. Por eso la linea guarda su propia unidad y su propio
-- factor congelado, y NO hereda nada de ent_pedido_linea ni de ent_alisto_linea.
--
-- El lote entra en FORMA CANONICA: la app le pasa _entCanon() al escribir, nunca
-- al leer. El check de abajo es la red — el saldo se lleva por la clave
-- `producto|lote` COMO TEXTO, asi que "183 - 12/26" seria un lote aparte y su
-- devolucion no sumaria al lote real. Paso el 18-ago con un alisto.
-- Es una tabla NUEVA: no hay filas viejas que el check pueda romper.
create table if not exists ent_devolucion_linea (
  id            bigint  generated always as identity primary key,
  devolucion_id bigint  not null references ent_devolucion(id),
  producto_id   integer not null,               -- product.product de Odoo, por ID
  lote          text    not null check (lote ~ '^\d{1,3} / \d{1,2}-\d{2}$'),
  cant_uds      numeric not null,               -- unidades individuales (la que resta/suma)
  uom_id        integer not null,               -- uom.uom.id — LA VERDAD
  uom_nombre    text    not null,               -- nombre es_CR al momento, para leerlo
  cant_uom      numeric not null,               -- cantidad EN esa unidad
  uom_factor    numeric not null                -- congelado: 1 unidad de esa UoM = 1/factor base
);
create index if not exists ent_devolucion_linea_dev_idx  on ent_devolucion_linea (devolucion_id);
create index if not exists ent_devolucion_linea_lote_idx on ent_devolucion_linea (producto_id, lote);

comment on column ent_devolucion_linea.uom_id is 'NUNCA leer la unidad por nombre: Paquete de 4 [37] y Docenas [2] se muestran los dos como "Dozens".';


-- ── 3 · RLS Y GRANTS ────────────────────────────────────────────────────
-- select + insert y nada mas, a nivel de politica Y de grant. Sin update ni
-- delete: corregir es anular e insertar de nuevo, con rastro.
alter table ent_devolucion       enable row level security;
alter table ent_devolucion_linea enable row level security;

drop policy if exists ent_devolucion_sel on ent_devolucion;
drop policy if exists ent_devolucion_ins on ent_devolucion;
create policy ent_devolucion_sel on ent_devolucion for select to authenticated using (true);
create policy ent_devolucion_ins on ent_devolucion for insert to authenticated with check (true);

drop policy if exists ent_devolucion_linea_sel on ent_devolucion_linea;
drop policy if exists ent_devolucion_linea_ins on ent_devolucion_linea;
create policy ent_devolucion_linea_sel on ent_devolucion_linea for select to authenticated using (true);
create policy ent_devolucion_linea_ins on ent_devolucion_linea for insert to authenticated with check (true);

grant select, insert on ent_devolucion       to authenticated;
grant select, insert on ent_devolucion_linea to authenticated;


-- ── 4 · ANULAR UNA DEVOLUCION ───────────────────────────────────────────
-- Se reusa ent_anulacion, que ya es el mecanismo del modulo. Solo hay que
-- ensanchar su check para que acepte la entidad nueva. Idempotente.
do $$
declare cname text;
begin
  select conname into cname
    from pg_constraint
   where conrelid = 'ent_anulacion'::regclass
     and contype  = 'c'
     and pg_get_constraintdef(oid) like '%entidad%';
  if cname is not null then
    execute format('alter table ent_anulacion drop constraint %I', cname);
  end if;
  alter table ent_anulacion add constraint ent_anulacion_entidad_chk
    check (entidad in ('alisto','salida','devolucion'));
end $$;

create or replace view ent_devolucion_vigente with (security_invoker = true) as
  select d.id as devolucion_id, d.fecha, d.recibido_en, d.cliente_id,
         d.cliente_nombre, d.nota, d.creado_en, d.creado_por
    from ent_devolucion d
   where not exists (select 1 from ent_anulacion x
                      where x.entidad = 'devolucion' and x.entidad_id = d.id);

grant select on ent_devolucion_vigente to authenticated;


-- ── 5 · LO DEVUELTO DESDE EL ANCLA ──────────────────────────────────────
-- Mismo criterio que las salidas: solo lo posterior al corte. Una devolucion
-- anterior al conteo ya esta contada en el fisico — sumarla la contaria dos veces.
-- Se compara `recibido_en` (instante) contra `corte` (instante), nunca fechas
-- sueltas. Agrupa por (producto, lote), igual que las otras tres puntas.
create or replace view ent_devuelto_desde_ancla with (security_invoker = true) as
  select dl.lote, dl.producto_id, sum(dl.cant_uds) as uds
    from ent_devolucion_linea   dl
    join ent_devolucion_vigente dv on dv.devolucion_id = dl.devolucion_id
   where dv.recibido_en > (select corte from ent_ancla)
   group by dl.lote, dl.producto_id;

grant select on ent_devuelto_desde_ancla to authenticated;

comment on view ent_devuelto_desde_ancla is
  'La cuarta punta del saldo: disponible = ancla + produccion - salidas + devoluciones.';
