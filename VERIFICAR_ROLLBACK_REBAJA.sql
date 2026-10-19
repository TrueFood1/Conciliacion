-- ════════════════════════════════════════════════════════════════════════
-- ¿EL ROLLBACK DE PRUEBAS_REBAJA.sql DEJO ALGO? · SOLO LECTURA
-- 3-oct-2026. Una sola consulta. Sin transaccion, sin escrituras, sin montos:
-- solo conteos y un porcentaje.
--
-- POR QUE NO ALCANZA CON esquema_check NI CON LA SONDA. Esos dos miran si los
-- objetos EXISTEN y si `anon` los puede leer. Ninguno mira el CONTENIDO, asi que
-- los dos darian verde con la fila de ensayo todavia adentro.
--
-- ⚠️ Y LA FILA PELIGROSA ES UNA SOLA: la prueba 6 inserta
-- `rebaja_trabajador_pct = 10` con vigente_desde 2026-10-01 para demostrar que
-- cambiar el parametro cambia el neto. Esa fila GANA sobre la semilla (misma
-- clave, vigencia mas nueva). Si el rollback no la deshizo, la rebaja real pasa
-- del 6,49% al 10% EN SILENCIO: la pantalla no avisa nada —el semaforo sigue en
-- 0 igual— y el neto de las tres personas queda unos 37.000 mas bajo por cabeza
-- sin que nada lo explique. De ahi que `filas_pct` tenga que dar 1 y no 2.
--
-- EL 6.49 SE ESCRIBE ACA A PROPOSITO. En las vistas no va nunca (sale de
-- rrhh_param, para poder cambiarlo sin tocar codigo); aca el valor literal ES
-- la pregunta, no una regla de calculo.
--
-- ESPERADO:  0 · 0 · 0 · 0 · 0 · 0 · 1 · 6.49 · t · 0 · 0
-- Si `params_ensayo` o `filas_pct` salen distintos, se limpia con:
--     delete from rrhh_param where creado_por = 'ensayo-rebaja';
-- y las demas, en este orden (las tres primeras referencian rrhh_persona):
--     delete from rrhh_permiso       where creado_por = 'ensayo-rebaja';
--     delete from rrhh_salario       where creado_por = 'ensayo-rebaja';
--     delete from rrhh_ajuste_manual where creado_por = 'ensayo-rebaja';
--     delete from rrhh_persona       where creado_por = 'ensayo-rebaja';
--
-- (Las sobras del ensayo de incapacidades, `creado_por = 'ensayo-incap'`, ya se
--  verificaron aparte el 3-oct y dieron 0.)
-- ════════════════════════════════════════════════════════════════════════
select
  (select count(*) from rrhh_persona       where creado_por = 'ensayo-rebaja') as personas,
  (select count(*) from rrhh_salario       where creado_por = 'ensayo-rebaja') as salarios,
  (select count(*) from rrhh_permiso       where creado_por = 'ensayo-rebaja') as permisos,
  (select count(*) from rrhh_ajuste_manual where creado_por = 'ensayo-rebaja') as ajustes,
  (select count(*) from rrhh_param         where creado_por = 'ensayo-rebaja') as params_ensayo,
  -- Por el nombre tambien, por si alguna vez se corre una variante con otra firma.
  (select count(*) from rrhh_persona       where nombre like 'ZZ Rebaja%')     as por_nombre,
  -- LA MAS IMPORTANTE: una sola fila para esa clave. Dos = la del ensayo quedo.
  (select count(*) from rrhh_param
    where clave = 'rebaja_trabajador_pct')                                     as filas_pct,
  -- El valor que la vista va a usar de verdad hoy.
  rrhh_param('rebaja_trabajador_pct', current_date)                            as pct_vigente,
  (rrhh_param('rebaja_trabajador_pct', current_date) = 6.49)                   as pct_es_6_49,
  -- Y que los otros dos semaforos sigan donde los dejo el pegado 7.
  (rrhh_param('rebaja_trabajador_confirmada', current_date))::int              as confirmada_0,
  (rrhh_param('incap_sujeta_a_rebaja', current_date))::int                     as incap_rebaja_0;
