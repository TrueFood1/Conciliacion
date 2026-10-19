-- SOLO LECTURA · DIAGNOSTICO_CANCELAR_APLICADO.sql
-- ════════════════════════════════════════════════════════════════════════
-- ¿ESTA APLICADO PERSONAL_CANCELAR_SOLICITUD.sql (pegado 9) EN PRODUCCION?
-- Una sola consulta, solo lectura: lee pg_proc, pg_constraint y pg_trigger.
-- No toca nada.
--
-- Es la PUERTA del botón «Cancelar» de «Mis solicitudes»: sin esa función en la
-- base, el botón no tiene a qué llamar.
--
-- COMO LEER EL RESULTADO:
--   funcion · check_nuevo · triggers · definer · guardia · anon_no_ejecuta
--
--   1 · 1 · 2 · t · t · f   => APLICADO Y COMPLETO. Se puede construir el botón.
--   0 · 0 · 0 · f · f · f   => NO aplicado. PARAR: primero hay que pegar el 9.
--   cualquier otra mezcla   => quedó A MEDIAS. Avisar antes de tocar nada.
-- ════════════════════════════════════════════════════════════════════════

select
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'rrhh_cancelar_solicitud')      as funcion,
  (select count(*) from pg_constraint
    where conname = 'rrhh_permiso_estado_ok'
      and pg_get_constraintdef(oid) like '%cancelado%')                        as check_nuevo,
  (select count(*) from pg_trigger where not tgisinternal
    and tgname in ('rrhh_evento_no_repetida_tg','rrhh_permiso_no_repetida_tg')) as triggers,
  -- Y las tres propiedades que hacen que la función sea segura, no solo que exista:
  coalesce((select p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'rrhh_cancelar_solicitud'), false)
                                                                               as definer,
  coalesce((select position('rrhh_mi_persona' in p.prosrc) > 0 from pg_proc p
             join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'rrhh_cancelar_solicitud'), false)
                                                                               as guardia,
  coalesce((select has_function_privilege('anon',
             'public.rrhh_cancelar_solicitud(text, bigint, text)', 'EXECUTE')), false)
                                                                               as anon_no_ejecuta;
