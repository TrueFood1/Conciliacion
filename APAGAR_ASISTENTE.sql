-- ═══════════════════════════════════════════════════════════════════════════
-- APAGAR_ASISTENTE.sql  ·  13-oct-2026  ·  Apaga a Instinct en un minuto
-- Se puede pegar cada vez que se quiera apagar. El proxy de lectura tarda hasta 60 s en enterarse.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

insert into public.asistente_interruptor (encendido, motivo, creado_por)
values (false, 'Apagado por Andrea.', 'andrea@truefoodcr.com');

-- CONTROL. ESPERADO: una fila  false · false
select (select encendido from public.asistente_interruptor order by creado_en desc, id desc limit 1) as ultima_fila,
       public.asistente_encendido() as asistente_encendido;
commit;
