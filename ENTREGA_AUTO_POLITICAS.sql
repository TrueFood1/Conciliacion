-- ═══════════════════════════════════════════════════════════════════════════
-- ENTREGA_AUTO_POLITICAS.sql  ·  26-oct-2026  ·  NO SE CORRIÓ
-- Validar en Odoo AL ENTREGAR (b132, decisión de Andrea del 26-oct): el servicio
-- truefie-escritura (POST /auto) escribe el rastro CON EL TOKEN DE QUIEN ENTREGÓ, y
-- quien entrega es Daniel (perfil «equipo»). Hoy las tres tablas del rastro solo
-- aceptan socias, así que Odoo quedaría validado y Truefie sin enterarse.
--
-- ⚠️ Este encabezado se cambia a "APLICADO" SOLO después de ver la fila de
--    control del final con los números esperados. Un "Success" no vale.
--
-- QUÉ ABRE, EXACTAMENTE (y nada más): tres políticas de INSERT nuevas, para el
-- perfil «equipo» (acceso_perfil() = 'equipo', o sea usuario ACTIVO; el asistente
-- no es «equipo» y además lo frenan sus restrictivas):
--   · ent_odoo_validacion — con SU correo en validado_por, y solo si la salida
--     VIGENTE de ese pedido la registró ÉL hace menos de 30 minutos;
--   · ent_odoo_traslado   — igual, con SU correo en creado_por;
--   · ent_odoo_hecho      — con SU correo, solo para el pendiente de traslado
--     interno de un pedido cuyo traslado registró ÉL (misma referencia) hace menos
--     de 30 minutos.
-- NO cambia grants (siguen INSERT,SELECT en las dos de rastro; ent_odoo_hecho no se
-- toca), NO toca las políticas de socias, NO abre update ni delete.
-- Los 30 minutos son la red de la base; el servicio exige 15 (AUTO_VENTANA_MIN).
--
-- ANTES: correr ENSAYO_ENTREGA_AUTO_POLITICAS.sql. Tiene que dar las 19 filas ok.
-- DESPUÉS, por fuera de esta transacción (pg_lector):
--   select polname from pg_policy where polname like '%_ins_auto';   -- 3 filas
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$ begin
  if exists (select 1 from pg_policy where polname in
             ('ent_odoo_validacion_ins_auto','ent_odoo_traslado_ins_auto','ent_odoo_hecho_ins_auto')) then
    raise exception 'las políticas _ins_auto ya existen: este archivo no se vuelve a pegar';
  end if;
end $$;

-- ▼▼▼ BLOQUE DDL (el ensayo lo repite byte a byte) ▼▼▼
-- Las tres son PERMISSIVE y se SUMAN a las de socias (que no se tocan): un insert entra si
-- calza con cualquiera de las dos. Las restrictivas del asistente siguen mandando encima.
create policy ent_odoo_validacion_ins_auto on public.ent_odoo_validacion
  for insert to authenticated
  with check (
    acceso_perfil() = 'equipo'
    and validado_por = (auth.jwt() ->> 'email')
    and exists (select 1
                  from public.ent_salida_vigente s
                  join public.ent_alisto_vigente a on a.alisto_id = s.alisto_id
                 where a.pedido_id = ent_odoo_validacion.pedido_id
                   and lower(s.creado_por) = lower(auth.jwt() ->> 'email')
                   and s.registrado_en > now() - interval '30 minutes'));

create policy ent_odoo_traslado_ins_auto on public.ent_odoo_traslado
  for insert to authenticated
  with check (
    acceso_perfil() = 'equipo'
    and creado_por = (auth.jwt() ->> 'email')
    and exists (select 1
                  from public.ent_salida_vigente s
                  join public.ent_alisto_vigente a on a.alisto_id = s.alisto_id
                 where a.pedido_id = ent_odoo_traslado.pedido_id
                   and lower(s.creado_por) = lower(auth.jwt() ->> 'email')
                   and s.registrado_en > now() - interval '30 minutes'));

create policy ent_odoo_hecho_ins_auto on public.ent_odoo_hecho
  for insert to authenticated
  with check (
    acceso_perfil() = 'equipo'
    and creado_por = (auth.jwt() ->> 'email')
    and exists (select 1
                  from public.ent_odoo_pendiente p
                  join public.ent_odoo_traslado t on t.pedido_id = p.pedido_id
                 where p.id = ent_odoo_hecho.pendiente_id
                   and p.tipo = 'traslado_interno'
                   and t.picking_nombre = ent_odoo_hecho.referencia
                   and t.creado_por = (auth.jwt() ->> 'email')
                   and t.creado_en > now() - interval '30 minutes'));
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

-- CONTROL, adentro de la transacción y antes del commit.
select (select count(*) from pg_policy where polname in
         ('ent_odoo_validacion_ins_auto','ent_odoo_traslado_ins_auto','ent_odoo_hecho_ins_auto')
           and polpermissive and polcmd = 'a') as nuevas,
       (select count(*) from pg_policy where polname in
         ('ent_odoo_validacion_ins','ent_odoo_traslado_ins','ent_odoo_hecho_ins')) as de_socias_intactas,
       (select count(*) from pg_policy where polrelid = 'public.ent_odoo_validacion'::regclass) as pol_validacion,
       (select count(*) from pg_policy where polrelid = 'public.ent_odoo_traslado'::regclass) as pol_traslado,
       (select count(*) from pg_policy where polrelid = 'public.ent_odoo_hecho'::regclass) as pol_hecho,
       (select count(*) from information_schema.role_table_grants
         where table_name in ('ent_odoo_validacion','ent_odoo_traslado') and grantee = 'anon') as grants_anon,
       (select string_agg(privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
         where table_name = 'ent_odoo_validacion' and grantee = 'authenticated') as grants_validacion;
-- ESPERADO: 3 · 3 · 8 · 8 · 8 · 0 · INSERT,SELECT

commit;
