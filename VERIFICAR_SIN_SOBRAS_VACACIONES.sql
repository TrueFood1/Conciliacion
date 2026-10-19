-- ════════════════════════════════════════════════════════════════════════
-- ¿QUEDO ALGO DEL ENSAYO QUE FALLO? · SOLO LECTURA · una sola consulta
-- 7-oct-2026.
--
-- CONTEXTO. El ensayo de la carga historica murio con ERROR 21000 en la seccion
-- 0, ANTES de llegar a cualquier insert. Y como todo estaba dentro de un
-- `begin`, Postgres aborta la transaccion igual. Por las dos razones no deberia
-- haber quedado nada — pero eso es un razonamiento, no una medicion, y en este
-- repo la regla es que una salvaguarda citada no es una salvaguarda verificada.
--
-- ⚠️ TAMBIEN sirve para el caso contrario: si alguien llego a correr el archivo
-- real (que todavia no existe) o una version con commit, aca se ve.
--
-- Sin montos. `creado_por` es un correo: no pegar esta tabla en un chat publico
-- si alguna fila sale distinta de 0.
--
-- ESPERADO:  0 · 0 · 0 · 0 · 2 · (lo que tenga hoy) · 0
-- ════════════════════════════════════════════════════════════════════════
select
  -- 1 · LA CARGA HISTORICA. El motivo es la firma: si existe, entro.
  (select count(*) from rrhh_evento
    where motivo = 'Carga histórica: vacaciones tomadas antes de usar Truefie')
                                                              as carga_historica,
  -- 2 · Y sus aprobaciones, por si quedo el evento sin aprobacion o al reves.
  (select count(*) from rrhh_evento_aprob
    where motivo = 'Carga histórica: vacaciones tomadas antes de usar Truefie')
                                                              as aprob_historica,
  -- 3 · Las personas de los ensayos anteriores, por si acaso.
  (select count(*) from rrhh_persona where nombre like 'ZZ %') as personas_ensayo,
  -- 4 · Y los eventos de los otros dos ensayos.
  (select count(*) from rrhh_evento
    where creado_por in ('ensayo-resolver','ensayo-incap','ensayo-rebaja'))
                                                              as eventos_ensayo,

  -- 5 · LAS DOS SOLICITUDES DEL 19-20 DE NOVIEMBRE: tienen que seguir ahi.
  -- El ensayo NO las toca, asi que esto confirma que no se perdio nada.
  (select count(*) from rrhh_evento
    where tipo = 'vacaciones' and fecha = date '2026-11-19')   as solicitudes_nov,
  -- 6 · Cuantas de esas estan ya resueltas (informativo: depende de si Lorena
  -- alcanzo a rechazar alguna despues del arreglo del pegado 8).
  (select count(*) from rrhh_evento_aprob a
    where a.evento_id in (select id from rrhh_evento
                           where tipo='vacaciones' and fecha = date '2026-11-19'))
                                                              as nov_ya_resueltas,

  -- 7 · Y el total de vacaciones aprobadas de TODO el equipo. Si el ensayo no
  -- dejo nada, tiene que ser lo mismo que antes de correrlo (hoy: 0, porque
  -- hasta el pegado 8 no se podia aprobar ninguna).
  (select count(*) from v_rrhh_evento where tipo = 'vacaciones')
                                                              as vacaciones_aprobadas_total;
