-- ═══════════════════════════════════════════════════════════════════════════
-- COMPRA_V3_E1.sql  ·  13-oct-2026  ·  Compras v3, etapa 1: «Ya llegó», nota libre
-- ⏳ SIN PEGAR. Antes: ENSAYO_COMPRA_V3_E1.sql (todas las filas ok = true).
--
-- QUÉ HACE (decisiones de Andrea del 13-oct; plan https://claude.ai/artifact/RjmgAQgXEM9zeiHMJQsd2V)
--   compra_propuesta:  modo 'llego' (una compra que YA llegó, con su fecha real: pedido = entrega) ·
--                      factura_ref (consecutivo de la FE, 20 dígitos; obligatorio en 'llego') ·
--                      nota libre (1 a 500 letras).
--   compra_pedido_odoo: factura_ref en el rastro, y una FE por proveedor se registra UNA sola vez.
--   Los 30 días hacia atrás y el tope que avisa los vigila el servidor (/pedir): un CHECK con la
--   fecha de hoy no sirve (no se vuelve a evaluar).
--   No cambia políticas ni grants: siguen insertando solo socias con su nombre. Filas viejas intactas.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'public'
              and table_name = 'compra_propuesta' and column_name = 'factura_ref') then
    raise exception 'COMPRA_V3_E1 ya está aplicado: este archivo no se vuelve a pegar';
  end if;
end $$;

alter table public.compra_propuesta drop constraint compra_propuesta_modo_check;
alter table public.compra_propuesta add constraint compra_propuesta_modo_check
  check (modo in ('pedir', 'registrar', 'llego'));
alter table public.compra_propuesta add column factura_ref text, add column nota text;
alter table public.compra_propuesta add constraint compra_propuesta_factura_ref
  check (factura_ref is null or factura_ref ~ '^[0-9]{20}$');
alter table public.compra_propuesta add constraint compra_propuesta_llego_fe
  check (modo <> 'llego' or factura_ref is not null);
alter table public.compra_propuesta add constraint compra_propuesta_llego_dia
  check (modo <> 'llego' or pedido_dia = entrega_dia);
alter table public.compra_propuesta add constraint compra_propuesta_nota
  check (nota is null or length(btrim(nota)) between 1 and 500);

alter table public.compra_pedido_odoo add column factura_ref text;
alter table public.compra_pedido_odoo add constraint compra_pedido_odoo_factura_ref
  check (factura_ref is null or factura_ref ~ '^[0-9]{20}$');
-- Una FE de un proveedor se registra UNA vez desde Truefie.
create unique index compra_pedido_odoo_fe_un on public.compra_pedido_odoo (proveedor_id, factura_ref)
  where factura_ref is not null;

-- CONTROL, justo antes del commit. ESPERADO: una fila  true · 2 · 4 · 2 · 1 · N · M
--   (llego en el CHECK · columnas nuevas en la propuesta · CHECKs nuevos en la propuesta · factura_ref
--    del rastro + su CHECK · índice de FE única · propuestas y rastros que ya había: 14 y 5 el 13-oct
--    a las 16 h, más los que se hayan creado después; este archivo no agrega ni borra ninguno)
select (select pg_get_constraintdef(oid) like '%llego%' from pg_constraint where conname = 'compra_propuesta_modo_check') as llego,
       (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'compra_propuesta'
         and column_name in ('factura_ref', 'nota')) as columnas_propuesta,
       (select count(*) from pg_constraint where conrelid = 'public.compra_propuesta'::regclass
         and conname in ('compra_propuesta_factura_ref', 'compra_propuesta_llego_fe', 'compra_propuesta_llego_dia',
                         'compra_propuesta_nota')) as checks_propuesta,
       (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'compra_pedido_odoo'
         and column_name = 'factura_ref')
       + (select count(*) from pg_constraint where conname = 'compra_pedido_odoo_factura_ref') as rastro,
       (select count(*) from pg_indexes where indexname = 'compra_pedido_odoo_fe_un') as indice_fe,
       (select count(*) from public.compra_propuesta) as propuestas,
       (select count(*) from public.compra_pedido_odoo) as rastros;
commit;
