-- PRUEBA I2 · CARRIL B · el EQUIPO no puede. La RLS es lo que protege; la
-- pantalla solo evita ofrecer un boton que la base va a rechazar.
-- ESPERADO: 42501 "new row violates row-level security policy".
-- ⚠️ Si esto ENTRA, `bsPuedeDeshacer` seria el unico freno — que es exactamente
--    el mundo del `with check (true)` que se cerro el 18-sep.
select acceso_perfil() as perfil, acceso_es_socia() as es_socia;
insert into ent_anulacion (entidad, entidad_id, motivo, creado_por)
values ('salida', 77, 'prueba-i2 NO DEBERIA ENTRAR',
        nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email');
select 'I2: EL INSERT ENTRO — la RLS no protege' as resultado;
