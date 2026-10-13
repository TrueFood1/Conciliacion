-- ═══════════════════════════════════════════════════════════════════════════
-- COMPRA_INSUMO_ODOO.sql  ·  13-oct-2026  ·  Insumos de materia prima nuevos, creados desde Truefie
-- ⏳ SIN PEGAR. Antes: ENSAYO_COMPRA_INSUMO_ODOO.sql (todas las filas ok = true).
-- Para saber si está aplicado, mirar la base: `select to_regclass('public.compra_insumo_odoo')`.
--
-- QUÉ HACE
--   Dos tablas append-only (nadie edita ni borra: solo SELECT e INSERT):
--
--   compra_insumo_propuesta  lo que una socia propone crear en Odoo: nombre, unidad, IVA de compra,
--                            Cabys, proveedor, precio sin IVA por unidad de compra, código del
--                            proveedor y la factura electrónica que sirve de testigo. El quinto
--                            carril del servicio de escritura (POST /insumo) la lee, la revisa contra
--                            Odoo y arma el producto EXACTO; lo fijo (categoría Materia Prima, ruta
--                            Comprar, cuenta 5101030, …) no está acá porque no lo elige nadie.
--   compra_insumo_odoo       el RASTRO: qué producto se creó en Odoo por cuál propuesta, con la huella
--                            de la vista previa. Una propuesta crea UN producto (único), y un producto
--                            viene de UNA propuesta (único).
--
--   Los CHECK repiten las cercas del servidor (unidad kg/g/L/gal, IVA [15] 1 % o [21] 13 %, Cabys de
--   13 dígitos, precio > 0): si un error de código o de pantalla las saltara, la base no lo acepta.
--
--   Las insertan las socias CON SU TOKEN: la base exige socia y que `creado_por` sea el correo del
--   token. Las leen las socias, y el asistente (decisión de Andrea, 12-oct: sí ve precios de compra;
--   igual que compra_tarifa_odoo). El disparador `asistente_politicas` (ASISTENTE_ROL.sql §7) les
--   pone solo sus cuatro políticas restrictivas al crearlas.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$ begin
  if to_regclass('public.compra_insumo_propuesta') is not null or to_regclass('public.compra_insumo_odoo') is not null then
    raise exception 'compra_insumo_* ya existe: este archivo no se vuelve a pegar';
  end if;
end $$;

create table public.compra_insumo_propuesta (
  id               bigint generated always as identity primary key,
  nombre           text not null check (nombre = btrim(nombre) and length(nombre) between 1 and 60),
  uom_id           integer not null check (uom_id in (12, 13, 10, 24)),        -- kg · g · L · gal (EE. UU.)
  iva_compra_id    integer not null check (iva_compra_id in (15, 21)),         -- 1 % · 13 % (el de la factura)
  cabys            text not null check (cabys ~ '^[0-9]{13}$'),
  proveedor_id     integer not null check (proveedor_id > 0),                  -- res.partner en Odoo
  precio           numeric(14,4) not null check (precio > 0),                  -- sin IVA, CRC, por unidad de compra
  codigo_proveedor text check (codigo_proveedor is null or (codigo_proveedor = btrim(codigo_proveedor)
                                                             and length(codigo_proveedor) between 1 and 30)),
  factura_ref      text not null check (factura_ref ~ '^[0-9]{20}$'),          -- consecutivo de la FE testigo
  nota             text,
  creado_por       text not null,
  creado_en        timestamptz not null default now()
);

create table public.compra_insumo_odoo (
  id               bigint generated always as identity primary key,
  propuesta_id     bigint not null unique references public.compra_insumo_propuesta (id),
  producto_tmpl_id integer not null unique check (producto_tmpl_id > 0),       -- product.template en Odoo
  producto_id      integer check (producto_id is null or producto_id > 0),     -- su variante (product.product)
  supplierinfo_id  integer check (supplierinfo_id is null or supplierinfo_id > 0),   -- su tarifa
  nombre           text not null check (length(btrim(nombre)) > 0),
  huella           text not null check (length(huella) between 1 and 64),      -- la de la vista previa
  creado_por       text not null,
  creado_en        timestamptz not null default now()
);

alter table public.compra_insumo_propuesta enable row level security;
alter table public.compra_insumo_odoo enable row level security;
revoke all on public.compra_insumo_propuesta, public.compra_insumo_odoo from anon, authenticated;
grant select, insert on public.compra_insumo_propuesta, public.compra_insumo_odoo to authenticated;

create policy compra_insumo_propuesta_sel on public.compra_insumo_propuesta
  for select to authenticated using (acceso_es_socia());
create policy compra_insumo_propuesta_ins on public.compra_insumo_propuesta
  for insert to authenticated with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));
create policy compra_insumo_propuesta_sel_asistente on public.compra_insumo_propuesta
  for select to authenticated using ((select public.acceso_es_asistente()));

create policy compra_insumo_odoo_sel on public.compra_insumo_odoo
  for select to authenticated using (acceso_es_socia());
create policy compra_insumo_odoo_ins on public.compra_insumo_odoo
  for insert to authenticated with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));
create policy compra_insumo_odoo_sel_asistente on public.compra_insumo_odoo
  for select to authenticated using ((select public.acceso_es_asistente()));

-- CONTROL, adentro de la transacción y justo antes del commit. ESPERADO: una fila
--   2 · 6 · 8 · 0 · INSERT,SELECT · INSERT,SELECT · 1
--   (8 = las 4 restrictivas del asistente × 2 tablas, que pone el disparador; si sale 0, el disparador
--    no está y hay que avisar ANTES de seguir)
select (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname in ('compra_insumo_propuesta', 'compra_insumo_odoo')
           and c.relrowsecurity) as tablas_con_rls,
       (select count(*) from pg_policy where polrelid in ('public.compra_insumo_propuesta'::regclass,
         'public.compra_insumo_odoo'::regclass) and polpermissive) as politicas_propias,
       (select count(*) from pg_policy where polrelid in ('public.compra_insumo_propuesta'::regclass,
         'public.compra_insumo_odoo'::regclass) and not polpermissive) as restrictivas_asistente,
       (select count(*) from information_schema.role_table_grants
         where table_name in ('compra_insumo_propuesta', 'compra_insumo_odoo') and grantee = 'anon') as grants_anon,
       (select string_agg(distinct privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
         where table_name = 'compra_insumo_propuesta' and grantee = 'authenticated') as grants_propuesta,
       (select string_agg(distinct privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
         where table_name = 'compra_insumo_odoo' and grantee = 'authenticated') as grants_rastro,
       (select count(*) from pg_constraint where conrelid = 'public.compra_insumo_odoo'::regclass and contype = 'f') as fk_rastro;
commit;
