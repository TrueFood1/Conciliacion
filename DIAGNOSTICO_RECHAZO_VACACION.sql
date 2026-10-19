-- ════════════════════════════════════════════════════════════════════════
-- DIAGNOSTICO · por que no se registra el rechazo de una vacacion
-- 7-oct-2026. SOLO LECTURA: un select, sin escrituras, sin transaccion.
-- No imprime ningun salario. Si, nombres del equipo (hace falta para ubicar
-- la solicitud); no lo peguen en un chat publico.
--
-- ESPERADO SI LA HIPOTESIS ES CORRECTA:
--   aprob_insert_authenticated .... f   <- ACA ESTA LA CAUSA
--   resolver_es_security_definer .. f   <- y aca por que importa
--   solicitudes_19_20_nov .......... 2
--   resoluciones_guardadas ......... 0
-- ════════════════════════════════════════════════════════════════════════
select
  -- 1 · LA CAUSA. `rrhh_resolver_evento()` inserta en rrhh_evento_aprob, y como
  -- NO es security definer, ese insert corre con los permisos de quien llama
  -- (authenticated). PERSONAL_CALENDARIO.sql le quito ese privilegio. Los grants
  -- se revisan ANTES de la RLS, asi que no importa si quien aprieta es socia:
  -- falla para todo el mundo, Andrea incluida.
  has_table_privilege('authenticated','public.rrhh_evento_aprob','INSERT')
                                                        as aprob_insert_authenticated,
  (select p.prosecdef from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='rrhh_resolver_evento')
                                                        as resolver_es_security_definer,

  -- 2 · CONTRASTE: el rechazo de un PERMISO si funciona, porque es un UPDATE
  -- directo sobre rrhh_permiso y ese grant por columna si esta puesto.
  has_table_privilege('authenticated','public.rrhh_permiso','UPDATE')
                                                        as permiso_update_authenticated,

  -- 3 · LAS SOLICITUDES DOBLES. Tienen que ser 2 y seguir sin resolucion.
  (select count(*) from rrhh_evento e
    where e.tipo = 'vacaciones'
      and e.fecha = date '2026-11-19')                   as solicitudes_19_20_nov,
  (select count(*) from rrhh_evento_aprob a
    where a.evento_id in (select id from rrhh_evento
                           where tipo='vacaciones' and fecha = date '2026-11-19'))
                                                        as resoluciones_guardadas,

  -- 4 · Y que la politica siga ahi, inalcanzable: existe, pero el grant la tapa.
  (select count(*) from pg_policies
    where schemaname='public' and tablename='rrhh_evento_aprob'
      and cmd = 'INSERT')                                as politica_insert_existe,

  -- 5 · Cuantas socias hay (sin imprimir correos).
  (select count(*) from acceso_usuario
    where perfil = 'socias' and activo)                  as socias_activas;


-- ── Y EL DETALLE DE LAS DOS SOLICITUDES, para saber cual es cual ─────────
-- Sin montos. `creado_por` es un correo: no pegar esto en un chat publico.
select e.id, p.nombre, e.fecha, e.dias, e.motivo, e.creado_en, e.creado_por,
       (select count(*) from rrhh_evento_aprob a where a.evento_id = e.id) as tiene_resolucion
  from rrhh_evento e
  join rrhh_persona p on p.id = e.persona_id
 where e.tipo = 'vacaciones'
   and e.fecha between date '2026-11-18' and date '2026-11-21'
 order by e.creado_en;
