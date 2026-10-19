-- ═══════════════════════════════════════════════════════════════════════════
-- ENCENDER_ASISTENTE.sql  ·  13-oct-2026  ·  Enciende el interruptor de Instinct (solo lectura)
-- Se puede pegar cada vez que se quiera encender. Para APAGAR: APAGAR_ASISTENTE.sql.
--
-- QUÉ HACE: una fila en asistente_interruptor con encendido = true (append-only; manda la última).
--   Con eso Instinct LEE Truefie y Odoo (menos Personal y archivos) y sigue SIN escribir nada:
--   las cuatro políticas restrictivas y las guardias no dependen del interruptor (ensayo 37/37).
--   No da ningún permiso de escritura: eso es asistente_permiso, de a una, más adelante.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

insert into public.asistente_interruptor (encendido, motivo, creado_por)
values (true, 'Fase 1: Instinct consulta (solo lectura). Decisión de Andrea, 13-oct-2026.', 'andrea@truefoodcr.com');

-- CONTROL, justo antes del commit. ESPERADO: una fila  true · true · 0
--   (la última fila dice encendido · asistente_encendido() · permisos de escritura dados)
select (select encendido from public.asistente_interruptor order by creado_en desc, id desc limit 1) as ultima_fila,
       public.asistente_encendido() as asistente_encendido,
       (select count(*) from public.asistente_permiso where encendido) as permisos_escritura;
commit;
