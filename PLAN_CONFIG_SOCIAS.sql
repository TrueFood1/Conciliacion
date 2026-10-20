-- ═══════════════════════════════════════════════════════════════════════════
-- PLAN_CONFIG_SOCIAS.sql  ·  2-oct-2026  ·  Compras › Proveedores: «solo socias» EN LA BASE
-- ✅ APLICADO el 3-oct-2026 por Andrea. Ensayo 7/7 ok; fila de control del pegado:
--    ins_exige_socia 1 · sel_intacta 1 · politicas 2. Verificado después con pg_lector:
--    pg_policy de plan_config = plan_config_ins (insert, con el check nuevo) + plan_config_sel.
--    NO volver a pegar: el guarda de arriba lo rechaza («ya no es with check (true)»).
--
-- POR QUÉ: la pantalla Proveedores (b82) solo deja editar a las socias, pero la política
-- `plan_config_ins` acepta el insert de CUALQUIER usuario con sesión (`with check (true)`,
-- medido el 2-oct). Una clave de configuración que decide cuánto se le pide a un proveedor
-- no puede depender de que la pantalla esconda un botón.
--
-- QUÉ CAMBIA: solo la clave `compras_dia_fijo`. Para esa clave, el insert exige socia
-- (`acceso_es_socia()`) y que `usuario` sea el correo del token (quién la cambió queda dicho
-- por la base, no por el navegador). Las demás claves siguen como están: hoy las escriben
-- pantallas de Operaciones (cierre_*) y no se tocan acá.
-- `plan_config` sigue append-only (sin update ni delete): esto no cambia.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$ begin
  if not exists (select 1 from pg_policy where polrelid = 'public.plan_config'::regclass
                  and polname = 'plan_config_ins' and pg_get_expr(polwithcheck, polrelid) = 'true') then
    raise exception 'plan_config_ins ya no es «with check (true)»: este archivo ya se pegó o alguien la cambió. Mirar antes de seguir.';
  end if;
end $$;

drop policy plan_config_ins on public.plan_config;
create policy plan_config_ins on public.plan_config
  for insert to authenticated
  with check (clave <> 'compras_dia_fijo'
              or (acceso_es_socia() and usuario = (auth.jwt() ->> 'email')));

-- Prueba de que la transacción llegó hasta acá (ESPERADO: 1 · 1 · 2).
select (select count(*) from pg_policy where polrelid = 'public.plan_config'::regclass and polname = 'plan_config_ins'
         and pg_get_expr(polwithcheck, polrelid) like '%acceso_es_socia()%') as ins_exige_socia,
       (select count(*) from pg_policy where polrelid = 'public.plan_config'::regclass and polname = 'plan_config_sel') as sel_intacta,
       (select count(*) from pg_policy where polrelid = 'public.plan_config'::regclass) as politicas;
commit;
