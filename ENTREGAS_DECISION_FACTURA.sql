-- ════════════════════════════════════════════════════════════════════════
-- ESQUEMA NUEVO · la decisión sobre una factura apartada
-- 26-ago-2026.  Pegar COMO UN SOLO BLOQUE en el editor SQL de Supabase.
--
-- ⚠️ NO HAY CÓDIGO TODAVÍA. Este bloque solo crea la tabla y su vista; la
-- pantalla se construye DESPUÉS de que esto esté pegado. Pegarlo no cambia nada
-- de lo que se ve hoy.
--
-- QUÉ RESUELVE. "Facturas sin despacho pendiente" (b39) aparta las facturas que
-- ya tienen su entrega hecha en Odoo, o que no tienen pedido de venta. Hoy esa
-- lista SOLO CRECE: el único botón es "Despachar igual", que hace lo contrario
-- de marcarla como vista, y encima vive en memoria — se pierde al recargar. Con
-- ~41 reversiones administrativas al año, en un año son 41 filas que nadie puede
-- sacar de la pantalla.
--
-- DOS DECISIONES, UNA TABLA. Son de la misma naturaleza —un humano miró una
-- factura apartada y dijo qué hacer con ella— y merecen el mismo registro:
--   'revisado'   → la miré, está bien apartada. Sale de la lista.
--   'despachar'  → el filtro se equivocó, esta SÍ lleva despacho. Va a la
--                  bandeja. Es el "Despachar igual" de b39, ahora persistido
--                  (cierra ENTREGAS_PENDIENTES.md §9).
--
-- ⚠️ EL NOMBRE ES "REVISADO", NO "VALIDADO". En este módulo "validar" ya
-- significa otra cosa —validar la entrega en Odoo, el botón "Ya validé" de
-- Pendientes— y las dos cosas conviven en la MISMA pantalla. Dos palabras
-- distintas para dos cosas distintas.
--
-- APPEND-ONLY, como todo el módulo: no hay update ni delete, ni por política ni
-- por grant. Cambiar de opinión es INSERTAR otra fila; gana la más reciente.
-- Es el mismo patrón de ent_pedido_factura, y a propósito NO el de
-- ent_anulacion, que es de una sola dirección y ya nos costó una corrección
-- (ver §8).
-- ════════════════════════════════════════════════════════════════════════

begin;

create table if not exists ent_factura_decision (
  id              bigint generated always as identity primary key,
  factura_id      integer not null,              -- account.move.id de Odoo
  factura_nombre  text,                          -- consecutivo legible, para no ir a Odoo
  decision        text    not null check (decision in ('revisado','despachar')),
  -- El motivo POR EL QUE SE APARTÓ, copiado del filtro en el momento de decidir
  -- ("ya entregado el 2026-07-08 según Odoo, 48 días antes de esta factura").
  -- Se congela acá a propósito: dentro de seis meses el filtro puede haber
  -- cambiado y esta fila tiene que seguir explicando qué se estaba mirando.
  motivo_filtro   text,
  -- Qué escribió el humano, si escribió algo. Opcional: "revisado" casi siempre
  -- no necesita explicación, y obligar a escribirla haría que nadie lo use.
  nota            text,
  creado_en       timestamptz not null default now(),
  creado_por      text    not null
);

create index if not exists ent_factura_decision_fac_idx
  on ent_factura_decision (factura_id, creado_en desc);

comment on table ent_factura_decision is
  'Qué decidió un humano sobre una factura apartada por el filtro de "sin despacho pendiente". Append-only: gana la fila más reciente por factura_id.';

-- ── LA DECISIÓN VIGENTE DE CADA FACTURA ────────────────────────────────
-- "Gana la más reciente", el mismo criterio del ancla, del motivo y del vínculo
-- a la factura. Cambiar de opinión es insertar, nunca actualizar.
create or replace view ent_factura_decision_vigente with (security_invoker = true) as
  select distinct on (factura_id)
         factura_id, factura_nombre, decision, motivo_filtro, nota,
         creado_en as decidido_en, creado_por as decidido_por
    from ent_factura_decision
   order by factura_id, creado_en desc;

-- ── RLS Y GRANTS · select + insert, y nada más ─────────────────────────
alter table ent_factura_decision enable row level security;
drop policy if exists ent_factura_decision_sel on ent_factura_decision;
drop policy if exists ent_factura_decision_ins on ent_factura_decision;
create policy ent_factura_decision_sel on ent_factura_decision
  for select to authenticated using (true);
create policy ent_factura_decision_ins on ent_factura_decision
  for insert to authenticated with check (true);

grant select, insert on ent_factura_decision to authenticated;
grant select on ent_factura_decision_vigente to authenticated;

-- ── COMPROBACIONES ─────────────────────────────────────────────────────
select 'la tabla existe' as control, count(*) as filas from ent_factura_decision;
select 'la vista existe' as control, count(*) as filas from ent_factura_decision_vigente;
-- Doble candado del append-only: NO tiene que aparecer ni UPDATE ni DELETE.
select cmd, count(*) as politicas
  from pg_policies
 where tablename = 'ent_factura_decision'
 group by cmd order by cmd;

commit;
