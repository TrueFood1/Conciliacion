-- ═══════════════════════════════════════════════════════════════════════════
-- CAMBIO_RECUENTO_PENDIENTE.sql  ·  30-oct-2026  ·  b151
-- ⛔ NO PEGADO EN PRODUCCION. Este header se cambia DESPUES de verificarlo desde afuera.
-- ✅ Probado SOLO en local (Postgres 17, espejo del respaldo del 23-oct): ENSAYO_RECUENTO_PENDIENTE.sql
--    30/30 con rollback verificado, y este archivo (con rollback en vez de commit) dio la fila
--    de control 1 · 1 · 3 · 1 · 4 · INSERT,SELECT · 0 · t. Falta el ensayo y el pegado en produccion.
--
-- QUE ES
--   Despachos deja sacar de un lote que en Truefie figura en 0 (o menos), con un
--   aviso y la confirmacion de Daniel de que hay producto fisico. La salida se
--   registra normal y el lote puede quedar NEGATIVO: no se ajusta ni se reparte
--   nada en otros lotes. Lo que queda es el RASTRO: cada lote que queda negativo
--   por esa via abre una fila aca, «pendiente de recuento», que las socias ven
--   en Entregas › Pendientes y que se cierra con OTRA fila despues de contar.
--
--   El caso que lo abrio: Pan Blanco 250 (saldo 0) con 2 panes fisicos que
--   salieron a Intimo el 30-oct (factura 3613) y Daniel no pudo registrar.
--
-- QUE TRAE
--   · `ent_recuento_pendiente` ............ solo de insercion. Una fila con
--       cierra_id NULL ABRE un pendiente; una fila con cierra_id = <id> lo CIERRA.
--   · `ent_recuento_pendiente_abierto` .... los abiertos (security_invoker).
--   · `ent_recuento_pendiente_guard` ...... BEFORE INSERT: la firma sale de la
--       sesion, el pendiente apunta a una linea de lote real del mismo lote y
--       producto, y solo una socia cierra.
--   · `ent_recuento_pendiente_inmutable` .. BEFORE UPDATE/DELETE/TRUNCATE: rechaza.
--
-- LAS GUARDAS
--   · Abrir: cualquier perfil con sesion menos la asistente (Daniel lo hace desde
--     Despachos; no necesita firma de socia: el control es el rastro), y solo
--     sobre una preparacion VIGENTE de un pedido que hizo quien firma.
--   · Cerrar: solo socias (RLS + guardia), con nota de al menos 3 caracteres.
--   · Un pendiente por linea de lote (`alisto_lote_id`) y un cierre por pendiente.
--   · saldo_resultante < 0, en UNIDAD DE VENTA (unidad o paquete), con su unidad.
--   · UPDATE, DELETE y TRUNCATE: rechazados por trigger (tambien al dueño) y sin
--     permiso para anon/authenticated.
--
-- NO TOCA el ancla, ent_conteo_correccion ni su candado, ni Odoo.
--
-- FILA DE CONTROL ESPERADA (adentro de la transaccion, justo antes del commit):
--   1 · 1 · 3 · 1 · 4 · INSERT,SELECT · 0 · t
--   (tabla · vista · triggers · politica de insert · indices (pkey + 3) ·
--    permisos de authenticated · permisos de anon · vista con security_invoker)
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ▼▼▼ BLOQUE DDL ▼▼▼
do $$ begin
  if to_regclass('public.ent_recuento_pendiente') is not null then
    raise exception 'ent_recuento_pendiente ya existe: este pegado ya corrio. No se vuelve a pegar.';
  end if;
end $$;

create table public.ent_recuento_pendiente (
  id                bigint generated always as identity primary key,
  cierra_id         bigint references public.ent_recuento_pendiente(id),
  producto_id       integer,
  lote              text,
  saldo_resultante  numeric,
  unidad_venta      text,
  alisto_lote_id    bigint references public.ent_alisto_lote(id),
  pedido_id         bigint references public.ent_pedido(id),
  motivo            text not null,
  nota              text,
  creado_por        text not null,
  creado_en         timestamptz not null default now(),
  constraint ent_recuento_pendiente_forma_ok check (
    (cierra_id is null
       and producto_id is not null and lote is not null and btrim(lote) <> ''
       and saldo_resultante is not null and saldo_resultante < 0
       and unidad_venta in ('unidad','paquete')
       and alisto_lote_id is not null and pedido_id is not null
       and motivo = 'despacho con lote en 0')
    or
    (cierra_id is not null
       and producto_id is null and lote is null and saldo_resultante is null
       and unidad_venta is null and alisto_lote_id is null and pedido_id is null
       and motivo = 'recuento'
       and nota is not null and length(btrim(nota)) >= 3)
  )
);
comment on table public.ent_recuento_pendiente is
  'Lotes que quedaron negativos al despachar con el lote en 0 en Truefie. Solo de insercion: '
  'cierra_id NULL abre, cierra_id = id cierra (solo socias). saldo_resultante en unidad de venta.';

create unique index ent_recuento_pendiente_un_cierre
  on public.ent_recuento_pendiente(cierra_id) where cierra_id is not null;
create unique index ent_recuento_pendiente_una_por_linea
  on public.ent_recuento_pendiente(alisto_lote_id) where cierra_id is null;
create index ent_recuento_pendiente_lote
  on public.ent_recuento_pendiente(producto_id, lote) where cierra_id is null;

create or replace function public.ent_recuento_pendiente_guard()
returns trigger language plpgsql security invoker set search_path = public as $$
declare
  v_quien text;
  v_abre  record;
begin
  -- La firma sale de la sesion, nunca de la fila.
  v_quien := lower(btrim(nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email'));
  if v_quien is null or v_quien = '' then
    raise exception 'un pendiente de recuento se registra desde la pantalla, con sesion iniciada: '
      'sin sesion no se sabe quien lo hizo';
  end if;
  if new.creado_por is not null and lower(btrim(new.creado_por)) <> v_quien then
    raise exception 'creado_por dice % y la sesion es de %. La firma no se elige.',
      new.creado_por, v_quien;
  end if;
  new.creado_por := v_quien;
  new.creado_en  := now();

  if new.cierra_id is null then
    -- ABRIR: la linea de lote tiene que existir y ser de ESTE lote y producto,
    -- y del pedido que dice.
    if not exists (
      select 1 from ent_alisto_lote al
        join ent_alisto_linea ln on ln.id = al.linea_id
        join ent_alisto a        on a.id  = ln.alisto_id
        join ent_alisto_vigente av on av.alisto_id = a.id
        join ent_pedido p        on p.id  = a.pedido_id
       where al.id = new.alisto_lote_id and al.lote = new.lote
         and ln.producto_id = new.producto_id and a.pedido_id = new.pedido_id
         and lower(btrim(p.creado_por)) = v_quien) then
      raise exception 'el pendiente no calza con la salida: la linea de lote % no es del lote % '
        'del producto % en una preparacion vigente del pedido %, hecha por %',
        new.alisto_lote_id, new.lote, new.producto_id, new.pedido_id, v_quien;
    end if;
  else
    -- CERRAR: solo socias, y solo un pendiente abierto (no un cierre).
    if not acceso_es_socia() then
      raise exception 'cerrar un pendiente de recuento es de un perfil socias, y % no lo es.', v_quien;
    end if;
    select * into v_abre from ent_recuento_pendiente where id = new.cierra_id;
    if v_abre.id is null or v_abre.cierra_id is not null then
      raise exception 'cierra_id % no es un pendiente abierto', new.cierra_id;
    end if;
  end if;
  return new;
end $$;

create trigger ent_recuento_pendiente_guard_trg
  before insert on public.ent_recuento_pendiente
  for each row execute function public.ent_recuento_pendiente_guard();

create or replace function public.ent_recuento_pendiente_inmutable()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'ent_recuento_pendiente es solo de insercion: un pendiente se cierra con otra '
    'fila (cierra_id), nunca con % ', tg_op using errcode = '42501';
end $$;

create trigger ent_recuento_pendiente_inmutable_trg
  before update or delete on public.ent_recuento_pendiente
  for each row execute function public.ent_recuento_pendiente_inmutable();
create trigger ent_recuento_pendiente_sin_truncate_trg
  before truncate on public.ent_recuento_pendiente
  for each statement execute function public.ent_recuento_pendiente_inmutable();

alter table public.ent_recuento_pendiente enable row level security;
create policy ent_recuento_pendiente_sel on public.ent_recuento_pendiente
  for select to authenticated using (true);
create policy ent_recuento_pendiente_ins on public.ent_recuento_pendiente
  for insert to authenticated with check (cierra_id is null or acceso_es_socia());

revoke all on public.ent_recuento_pendiente from anon, authenticated;
grant select, insert on public.ent_recuento_pendiente to authenticated;
revoke all on function public.ent_recuento_pendiente_guard() from public, anon;
revoke all on function public.ent_recuento_pendiente_inmutable() from public, anon;

create view public.ent_recuento_pendiente_abierto with (security_invoker = true) as
  select p.id, p.producto_id, p.lote, p.saldo_resultante, p.unidad_venta,
         p.alisto_lote_id, p.pedido_id, p.motivo, p.creado_por, p.creado_en
    from public.ent_recuento_pendiente p
   where p.cierra_id is null
     and not exists (select 1 from public.ent_recuento_pendiente c where c.cierra_id = p.id);
revoke all on public.ent_recuento_pendiente_abierto from anon, authenticated;
grant select on public.ent_recuento_pendiente_abierto to authenticated;
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

-- 🔴 FILA DE CONTROL. Si no aparece, no corrio hasta aca.
select (select count(*) from pg_class where oid = 'public.ent_recuento_pendiente'::regclass) as tabla,
       (select count(*) from pg_class where oid = 'public.ent_recuento_pendiente_abierto'::regclass) as vista,
       (select count(*) from pg_trigger where tgrelid = 'public.ent_recuento_pendiente'::regclass
          and not tgisinternal and tgname in ('ent_recuento_pendiente_guard_trg','ent_recuento_pendiente_inmutable_trg',
                         'ent_recuento_pendiente_sin_truncate_trg')) as triggers,
       (select count(*) from pg_policies where tablename = 'ent_recuento_pendiente'
          and policyname = 'ent_recuento_pendiente_ins') as pol_ins,
       (select count(*) from pg_indexes where tablename = 'ent_recuento_pendiente'
          and indexname like 'ent_recuento_pendiente_%') as indices,
       (select string_agg(privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
         where table_name = 'ent_recuento_pendiente' and grantee = 'authenticated') as permisos_auth,
       (select count(*) from information_schema.role_table_grants
         where table_name = 'ent_recuento_pendiente' and grantee = 'anon') as permisos_anon,
       (select coalesce('security_invoker=true' = any(reloptions), false) from pg_class
         where oid = 'public.ent_recuento_pendiente_abierto'::regclass) as invoker;
-- ESPERADO: 1 · 1 · 3 · 1 · 4 · INSERT,SELECT · 0 · t

commit;
