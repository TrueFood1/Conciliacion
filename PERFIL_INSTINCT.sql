-- ═══════════════════════════════════════════════════════════════════════════
-- PERFIL_INSTINCT.sql  ·  13-oct-2026  ·  El perfil «asistente» de Instinct (fase 1)
-- ✅ APLICADO el 13-oct-2026 por Andrea (ensayo 37/37). Control 1 · 2 · 4 · 7 · 0. Verificado desde afuera (pg_lector). NO VOLVER A CORRER.
--
-- ORDEN (importa): este pegado VA ANTES de invitar a instinct@truefoodcr.com en Supabase Auth.
--   Una cuenta autenticada SIN fila en acceso_usuario no es asistente para la base: hoy podría
--   insertar en las 23 tablas con INSERT abierto. Con la fila puesta primero, la cuenta nace
--   asistente y, con el interruptor apagado (asistente_interruptor sin filas), no lee ni escribe nada.
--
-- QUÉ HACE: una fila en acceso_usuario (perfil 'asistente'). Nada más: no enciende el interruptor
--   (eso es ENCENDER_ASISTENTE.sql, aparte, cuando Andrea lo decida) ni da ningún permiso.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$ begin
  if exists (select 1 from public.acceso_usuario where lower(email) = 'instinct@truefoodcr.com') then
    raise exception 'instinct@truefoodcr.com ya tiene fila en acceso_usuario: este archivo no se vuelve a pegar';
  end if;
  if to_regprocedure('public.acceso_es_asistente()') is null or to_regclass('public.asistente_interruptor') is null then
    raise exception 'falta ASISTENTE_ROL.sql: sin el candado, esta cuenta no sería asistente';
  end if;
end $$;

insert into public.acceso_usuario (email, nombre, perfil, activo, nota, creado_por)
values ('instinct@truefoodcr.com', 'Instinct', 'asistente', true,
        'Asistente de Andrea por voz/WhatsApp (decisión del 12/13-oct). Solo lectura con su interruptor; cada escritura se habilita aparte (asistente_permiso + interruptor del carril).',
        'andrea@truefoodcr.com');

-- CONTROL, justo antes del commit. ESPERADO: una fila  1 · 2 · 4 · 7 · 0
--   (asistentes · socias · equipo · filas en total · filas del interruptor = APAGADO)
select (select count(*) from public.acceso_usuario where perfil = 'asistente') as asistentes,
       (select count(*) from public.acceso_usuario where perfil = 'socias') as socias,
       (select count(*) from public.acceso_usuario where perfil = 'equipo') as equipo,
       (select count(*) from public.acceso_usuario) as filas,
       (select count(*) from public.asistente_interruptor) as interruptor_filas;
commit;
