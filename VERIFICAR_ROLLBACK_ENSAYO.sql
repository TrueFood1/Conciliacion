-- ════════════════════════════════════════════════════════════════════════
-- ¿EL ROLLBACK DE PRUEBAS_INCAPACIDAD.sql DEJO ALGO? · SOLO LECTURA
-- 3-oct-2026. Una sola consulta, sin transaccion, sin escrituras.
--
-- POR QUE EXISTE Y NO ALCANZA CON RAZONARLO. El razonamiento dice que no puede
-- haber quedado nada: el script no tiene ni un `commit`, y si hubiera fallado a
-- mitad de camino Postgres aborta la transaccion igual. Es un argumento solido
-- y NO ES UNA MEDICION. La regla del repo es que una salvaguarda citada no es
-- una salvaguarda verificada, asi que se corre.
--
-- ESPERADO: 0 · 0 · 0 · 0 · t
-- Si alguno sale distinto de 0, se borra a mano con:
--     delete from rrhh_permiso where creado_por = 'ensayo-incap';
--     delete from rrhh_salario where creado_por = 'ensayo-incap';
--     delete from rrhh_persona where creado_por = 'ensayo-incap';
--   (en ESE orden: rrhh_salario y rrhh_permiso referencian rrhh_persona)
-- ════════════════════════════════════════════════════════════════════════
select
  (select count(*) from rrhh_persona where creado_por = 'ensayo-incap') as personas,
  (select count(*) from rrhh_salario where creado_por = 'ensayo-incap') as salarios,
  (select count(*) from rrhh_permiso where creado_por = 'ensayo-incap') as permisos,
  -- Y por el nombre, por si alguien corrio una version del ensayo con otro
  -- `creado_por`: las cuatro personas del ensayo empiezan con 'ZZ Ensayo'.
  (select count(*) from rrhh_persona where nombre like 'ZZ Ensayo%')    as por_nombre,
  -- El semaforo sigue donde tiene que estar: el ensayo no lo toca, pero si
  -- alguien corrio algo a medias conviene verlo en la misma fila.
  ((select valor from rrhh_param where clave = 'incapacidad_reglas_confirmadas'
     order by vigente_desde desc, creado_en desc limit 1) = 0)          as reglas_siguen_sin_confirmar;
