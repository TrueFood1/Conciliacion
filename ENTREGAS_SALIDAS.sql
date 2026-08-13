-- ════════════════════════════════════════════════════════════════════════
-- SALIDAS SIN FACTURA: tipo obligatorio + vínculo a factura que llega después
-- 12-ago-2026. TERCER pegado, después de ENTREGAS_ESQUEMA.sql y ENTREGAS_ANCLA.sql.
-- Re-ejecutable.
--
-- POR QUÉ. Hay salidas de inventario que no son ventas —reposiciones, regalías,
-- consumo de las socias—. Si Truefie solo captura lo facturado, esos lotes quedan
-- mal contados y el descuadre aparece después sin explicación.
-- ════════════════════════════════════════════════════════════════════════


-- ── 1 · El TIPO DE SALIDA pasa a obligatorio ────────────────────────────
-- La columna `motivo` y su lista de valores YA existían en ent_pedido. Lo único
-- que falta es que no se pueda dejar en blanco: si es opcional, el apuro lo deja
-- vacío y después nadie sabe qué fue esa salida.
-- El DO block lo hace idempotente y no revienta si quedara alguna fila vieja sin
-- motivo (avisa en vez de fallar).
do $$
begin
  if exists (select 1 from ent_pedido where motivo is null) then
    raise notice 'Hay pedidos con motivo NULL: se dejan como están y NO se aplica el NOT NULL. Revisarlos primero.';
  else
    begin
      alter table ent_pedido alter column motivo set not null;
    exception when others then
      raise notice 'No se pudo aplicar NOT NULL a motivo: %', sqlerrm;
    end;
  end if;
end $$;


-- ── 2 · EL VÍNCULO A LA FACTURA, EN SU PROPIA TABLA ─────────────────────
-- El pedido se puede crear sin factura y vincularla DESPUÉS. Pero "después"
-- significaría UPDATE sobre ent_pedido.factura_id, y este módulo no permite
-- update (no hay política ni grant, a propósito). Así que el vínculo se INSERTA,
-- igual que la confirmación del ancla: manda la fila más reciente de cada pedido.
--
-- ent_pedido.factura_id queda OBSOLETA a partir de acá: no se borra (borrar es
-- destructivo y no hace falta), pero el vínculo vive SOLO en esta tabla, para que
-- haya una sola fuente de verdad. Cuando la fase 2 cree pedidos desde una factura,
-- inserta el pedido y su vínculo en la misma operación.
create table if not exists ent_pedido_factura (
  id              bigint generated always as identity primary key,
  pedido_id       bigint  not null references ent_pedido(id),
  factura_id      integer not null,                -- account.move.id de Odoo
  factura_nombre  text,                            -- consecutivo legible, para no ir a Odoo
  anulado         boolean not null default false,  -- ¿me equivoqué de factura? se INSERTA otra con true
  nota            text,
  creado_en       timestamptz not null default now(),
  creado_por      text    not null
);
create index if not exists ent_pedido_factura_pedido_idx
  on ent_pedido_factura (pedido_id, creado_en desc);
create index if not exists ent_pedido_factura_factura_idx
  on ent_pedido_factura (factura_id);

alter table ent_pedido_factura enable row level security;

drop policy if exists ent_pedido_factura_sel on ent_pedido_factura;
drop policy if exists ent_pedido_factura_ins on ent_pedido_factura;
create policy ent_pedido_factura_sel on ent_pedido_factura
  for select to authenticated using (true);
create policy ent_pedido_factura_ins on ent_pedido_factura
  for insert to authenticated with check (true);

grant select, insert on ent_pedido_factura to authenticated;

-- NOTA sobre unicidad: no hay índice único que impida vincular la misma factura a
-- dos pedidos. Con append-only no se puede expresar "único entre los vínculos
-- vigentes" con un índice parcial (la fila anulada sigue ahí). Se valida en la app
-- antes de insertar, y un duplicado se ve en la vista de control. Preferimos eso a
-- meter un trigger, que es más maquinaria de la que este problema pide.


-- ── 3 · EL VÍNCULO VIGENTE DE CADA PEDIDO ───────────────────────────────
create or replace view ent_pedido_factura_vigente with (security_invoker = true) as
  select distinct on (pedido_id)
         pedido_id, factura_id, factura_nombre, anulado,
         creado_en as vinculado_en, creado_por as vinculado_por
    from ent_pedido_factura
   order by pedido_id, creado_en desc;


-- ── 4 · LA LISTA DE PENDIENTES ──────────────────────────────────────────
-- Solo las salidas de tipo VENTA sin vínculo vigente. Una regalía o un consumo
-- interno sin factura NO es un pendiente: es lo correcto. Si se listaran todas,
-- la lista se llena de ruido y se deja de mirar — que es la forma más común de
-- matar una vista de control.
create or replace view ent_salida_sin_factura with (security_invoker = true) as
  select p.id, p.fecha_despacho, p.cliente_id, p.cliente_nombre,
         p.motivo, p.creado_en, p.creado_por
    from ent_pedido p
    left join ent_pedido_factura_vigente v
           on v.pedido_id = p.id and v.anulado = false
   where p.motivo = 'venta'
     and v.pedido_id is null
   order by p.fecha_despacho, p.id;

grant select on ent_pedido_factura_vigente to authenticated;
grant select on ent_salida_sin_factura     to authenticated;


-- ── VERIFICACIÓN (opcional) ─────────────────────────────────────────────
-- 1) Dos políticas, SELECT e INSERT, ninguna UPDATE ni DELETE:
--      select policyname, cmd from pg_policies
--       where schemaname='public' and tablename='ent_pedido_factura' order by cmd;
-- 2) motivo tiene que aparecer como NOT NULL:
--      select column_name, is_nullable from information_schema.columns
--       where table_name='ent_pedido' and column_name='motivo';
-- 3) Y esto tiene que devolver 0 filas mientras no haya ninguna salida cargada:
--      select * from ent_salida_sin_factura;
