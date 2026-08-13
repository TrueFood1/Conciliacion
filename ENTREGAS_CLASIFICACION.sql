-- ════════════════════════════════════════════════════════════════════════
-- DANIEL NO CLASIFICA: sin_clasificar + reclasificación + validación manual
-- 12-ago-2026. CUARTO pegado, después de ENTREGAS_SALIDAS.sql. Re-ejecutable.
--
-- POR QUÉ. Daniel ve una caja saliendo, pero si es reposición, regalía o consumo
-- interno lo saben las socias, no él. Pedirle que clasifique es pedirle que
-- adivine. Entonces: Daniel marca "sin factura" y nada más; la salida queda en
-- un estado CON NOMBRE (`sin_clasificar`, no un NULL) y Andrea o Lorena la
-- clasifican después desde Truefie.
--
-- Como el módulo es append-only, clasificar después NO es un UPDATE sobre
-- ent_pedido.motivo: se INSERTA en ent_pedido_motivo y manda la fila más
-- reciente. Mismo patrón que el ancla y el vínculo de factura.
-- ════════════════════════════════════════════════════════════════════════


-- ── 1 · `sin_clasificar` entra a la lista de motivos ────────────────────
-- El pendiente es un estado con nombre, no un hueco: el NOT NULL del pegado
-- anterior se queda, y el check gana el valor nuevo.
do $$
declare cname text;
begin
  select conname into cname
    from pg_constraint
   where conrelid = 'ent_pedido'::regclass
     and contype  = 'c'
     and pg_get_constraintdef(oid) like '%motivo%';
  if cname is not null then
    execute format('alter table ent_pedido drop constraint %I', cname);
  end if;
  alter table ent_pedido add constraint ent_pedido_motivo_chk
    check (motivo in ('venta','influencer','regalia','reposicion',
                      'consumo_interno','otro','sin_clasificar'));
end $$;


-- ── 2 · LA RECLASIFICACIÓN (quién dijo qué era, y cuándo) ───────────────
create table if not exists ent_pedido_motivo (
  id          bigint generated always as identity primary key,
  pedido_id   bigint not null references ent_pedido(id),
  motivo      text   not null check (motivo in ('venta','influencer','regalia',
                                                'reposicion','consumo_interno','otro')),
  nota        text,
  creado_en   timestamptz not null default now(),
  creado_por  text   not null
);
create index if not exists ent_pedido_motivo_pedido_idx
  on ent_pedido_motivo (pedido_id, creado_en desc);

alter table ent_pedido_motivo enable row level security;
drop policy if exists ent_pedido_motivo_sel on ent_pedido_motivo;
drop policy if exists ent_pedido_motivo_ins on ent_pedido_motivo;
create policy ent_pedido_motivo_sel on ent_pedido_motivo
  for select to authenticated using (true);
create policy ent_pedido_motivo_ins on ent_pedido_motivo
  for insert to authenticated with check (true);
grant select, insert on ent_pedido_motivo to authenticated;

-- El motivo VIGENTE: la reclasificación más reciente, o el motivo original.
create or replace view ent_pedido_motivo_vigente with (security_invoker = true) as
  select p.id as pedido_id,
         coalesce(m.motivo, p.motivo) as motivo,
         m.creado_en  as clasificado_en,
         m.creado_por as clasificado_por
    from ent_pedido p
    left join lateral (
      select motivo, creado_en, creado_por
        from ent_pedido_motivo
       where pedido_id = p.id
       order by creado_en desc
       limit 1
    ) m on true;


-- ── 3 · VALIDACIÓN MANUAL EN ODOO (fase 1: Andrea valida a mano y lo marca) ──
-- Truefie no puede saber solo si la entrega ya se validó en Odoo (eso sería la
-- fase 4). Mientras tanto, Andrea lo marca acá al terminar. Append-only:
-- desmarcar = insertar otra fila con anulado=true.
create table if not exists ent_pedido_valida (
  id          bigint  generated always as identity primary key,
  pedido_id   bigint  not null references ent_pedido(id),
  anulado     boolean not null default false,
  nota        text,
  creado_en   timestamptz not null default now(),
  creado_por  text    not null
);
create index if not exists ent_pedido_valida_pedido_idx
  on ent_pedido_valida (pedido_id, creado_en desc);

alter table ent_pedido_valida enable row level security;
drop policy if exists ent_pedido_valida_sel on ent_pedido_valida;
drop policy if exists ent_pedido_valida_ins on ent_pedido_valida;
create policy ent_pedido_valida_sel on ent_pedido_valida
  for select to authenticated using (true);
create policy ent_pedido_valida_ins on ent_pedido_valida
  for insert to authenticated with check (true);
grant select, insert on ent_pedido_valida to authenticated;

create or replace view ent_pedido_valida_vigente with (security_invoker = true) as
  select distinct on (pedido_id)
         pedido_id, anulado, creado_en as validado_en, creado_por as validado_por
    from ent_pedido_valida
   order by pedido_id, creado_en desc;


-- ── 4 · LAS LISTAS DE PENDIENTES, con el motivo VIGENTE ─────────────────
-- ent_salida_sin_factura se redefine: ahora respeta la reclasificación (una
-- salida reclasificada a venta ENTRA a la lista; una venta reclasificada a
-- regalía SALE).
create or replace view ent_salida_sin_factura with (security_invoker = true) as
  select p.id, p.fecha_despacho, p.cliente_id, p.cliente_nombre,
         mv.motivo, p.creado_en, p.creado_por
    from ent_pedido p
    join ent_pedido_motivo_vigente mv on mv.pedido_id = p.id
    left join ent_pedido_factura_vigente v
           on v.pedido_id = p.id and v.anulado = false
   where mv.motivo = 'venta'
     and v.pedido_id is null
   order by p.fecha_despacho, p.id;

create or replace view ent_salida_sin_clasificar with (security_invoker = true) as
  select p.id, p.fecha_despacho, p.cliente_id, p.cliente_nombre,
         p.creado_en, p.creado_por
    from ent_pedido p
    join ent_pedido_motivo_vigente mv on mv.pedido_id = p.id
   where mv.motivo = 'sin_clasificar'
   order by p.fecha_despacho, p.id;

grant select on ent_pedido_motivo_vigente to authenticated;
grant select on ent_pedido_valida_vigente to authenticated;
grant select on ent_salida_sin_factura    to authenticated;
grant select on ent_salida_sin_clasificar to authenticated;


-- ── VERIFICACIÓN (opcional) ─────────────────────────────────────────────
-- 1) El check tiene que incluir sin_clasificar:
--      select pg_get_constraintdef(oid) from pg_constraint
--       where conname='ent_pedido_motivo_chk';
-- 2) Cuatro políticas nuevas, todas SELECT o INSERT:
--      select tablename, policyname, cmd from pg_policies
--       where tablename in ('ent_pedido_motivo','ent_pedido_valida') order by tablename, cmd;
-- 3) Las dos listas devuelven 0 filas mientras no haya salidas cargadas:
--      select * from ent_salida_sin_clasificar;
