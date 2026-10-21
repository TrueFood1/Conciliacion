-- ═══════════════════════════════════════════════════════════════════════════
-- DESHACER_COMPRA_TARIFA_HISTORIAL.sql  ·  21-oct-2026  ·  deshace COMPRA_TARIFA_HISTORIAL.sql
-- ⛔ NO APLICADO. Probado en Postgres local (espejo del respaldo del 21-oct), de ida y vuelta.
--
-- Borra la tabla compra_tarifa_historial y el rol truefie_tarifa_auto. Se FRENA si la tabla ya
-- tiene filas: eso es historial de cambios hechos en Odoo, y Odoo no lo guarda en ningún otro lado.
-- Para deshacer con filas, primero se exportan (y lo decide una socia); este archivo no lo hace.
-- Antes de correrlo, apagar la revisión diaria: sin la tabla, cada cambio quedaría sin anotar y
-- la revisión lo avisaría como «SIN anotar».
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$
declare v_n bigint;
begin
  if to_regclass('public.compra_tarifa_historial') is null then
    raise exception 'compra_tarifa_historial no existe: no hay nada que deshacer';
  end if;
  execute 'select count(*) from public.compra_tarifa_historial' into v_n;
  if v_n > 0 then
    raise exception 'compra_tarifa_historial tiene % fila(s) de historial: exportarlas antes, no se borran desde acá', v_n;
  end if;
end $$;

drop table public.compra_tarifa_historial;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'truefie_tarifa_auto') then
    revoke usage on schema public from truefie_tarifa_auto;
    drop role truefie_tarifa_auto;
  end if;
end $$;

-- Control: t · f  (la tabla ya no existe · el rol tampoco)
select to_regclass('public.compra_tarifa_historial') is null as tabla_borrada,
       exists (select 1 from pg_roles where rolname = 'truefie_tarifa_auto') as rol_sigue;
commit;
