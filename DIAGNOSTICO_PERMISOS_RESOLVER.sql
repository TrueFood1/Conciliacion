-- ════════════════════════════════════════════════════════════════════════
-- DIAGNOSTICO · POR QUE FALLA EL RECHAZO DE UNA VACACION
-- 7-oct-2026. UNA sola consulta, SOLO LECTURA, UNA sola tabla.
--
-- POR QUE EXISTE ESTE ARCHIVO. El diagnostico original traia dos `select` y el
-- SQL Editor muestra SOLO el resultado del ultimo, asi que las banderas —que
-- son la causa— quedaron tapadas por el detalle de las solicitudes. Aca van
-- solas y en una tabla, con una fila por bandera.
--
-- ⚠️ NO LLEVA NINGUN DATO PERSONAL: ni nombres, ni correos, ni montos. Solo
-- banderas de privilegios y conteos. Esta tabla se puede pegar entera en un
-- chat sin pensarlo dos veces.
--
-- YA SABEMOS (medido el 7-oct con el segundo select del diagnostico anterior):
-- las dos solicitudes del 19-20 de nov existen y NINGUNA tiene resolucion. O
-- sea que los dos rechazos de Lorena NO se guardaron. Esto explica por que.
--
-- ESPERADO SI LA HIPOTESIS ES CORRECTA: las filas 1 y 2 en «f», la 3 en «t».
-- ════════════════════════════════════════════════════════════════════════
select * from (

  -- 1 · LA CAUSA. rrhh_resolver_evento() inserta en rrhh_evento_aprob. Si
  -- `authenticated` no tiene INSERT ahi, el insert muere con 42501 — y los
  -- grants se revisan ANTES de la RLS, asi que da igual si quien aprieta es
  -- socia: falla para todo el mundo, Andrea incluida.
  select 1 as orden,
         'authenticated puede INSERT en rrhh_evento_aprob'::text as bandera,
         has_table_privilege('authenticated','public.rrhh_evento_aprob','INSERT')::text as valor,
         'f'::text as esperado,
         'si es f, ESTA es la causa: el pegado 4 revoco ese privilegio'::text as lectura

  union all
  -- 2 · POR QUE ESO IMPORTA. Si la funcion fuera `security definer` correria con
  -- los permisos de su dueño y el revoke no la afectaria. Es la UNICA funcion del
  -- modulo que no lo es (acceso_perfil, acceso_es_socia, rrhh_mi_persona y
  -- rrhh_calendario si lo son).
  select 2, 'rrhh_resolver_evento es security definer',
         coalesce((select p.prosecdef::text from pg_proc p
                    join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname='public' and p.proname='rrhh_resolver_evento'),
                  'LA FUNCION NO EXISTE'),
         'f',
         'si es f, la funcion entra por la misma puerta que le cerraron'

  union all
  -- 3 · EL CONTRASTE, y es lo que vuelve la hipotesis verificable en vez de
  -- plausible: rechazar un PERMISO si funciona, porque es un UPDATE directo
  -- sobre rrhh_permiso y ese grant por columna si esta puesto. Mismo boton,
  -- mismo rol, resultado distinto. Si esta fila diera «f» tambien, el problema
  -- seria otro y mas grande.
  select 3, 'authenticated puede UPDATE en rrhh_permiso',
         has_table_privilege('authenticated','public.rrhh_permiso','UPDATE')::text,
         't',
         'por eso rechazar un PERMISO si funciona y una VACACION no'

  union all
  -- 4 · La politica sigue existiendo, pero es inalcanzable: el grant la tapa.
  -- Sirve para no salir a buscar una politica que falta cuando no falta.
  select 4, 'politica INSERT en rrhh_evento_aprob (existe)',
         (select count(*)::text from pg_policies
           where schemaname='public' and tablename='rrhh_evento_aprob' and cmd='INSERT'),
         '1',
         'existe y exige acceso_es_socia(), pero nunca se llega a evaluar'

  union all
  -- 5 · Que pedir vacaciones si funciona (el empleado inserta en rrhh_evento).
  -- Confirma que lo roto es SOLO resolver, no todo el flujo.
  select 5, 'authenticated puede INSERT en rrhh_evento',
         has_table_privilege('authenticated','public.rrhh_evento','INSERT')::text,
         't',
         'por eso Daniel pudo pedir (y pedir dos veces) sin problema'

  union all
  -- 6 · Cuantas socias activas hay. SIN correos: solo el conteo.
  select 6, 'socias activas en acceso_usuario (solo el conteo)',
         (select count(*)::text from acceso_usuario where perfil='socias' and activo),
         '>= 1',
         'si es >= 1, el perfil de Lorena NO es el problema'

  union all
  -- 7 · Y la vuelta de tuerca: tampoco puede nadie ANULAR una solicitud ya
  -- resuelta ni borrar una duplicada. Explica por que las dos van a seguir ahi
  -- aunque se arregle lo de arriba.
  select 7, 'authenticated puede INSERT en rrhh_evento_anulado',
         has_table_privilege('authenticated','public.rrhh_evento_anulado','INSERT')::text,
         't',
         'el grant esta, pero NINGUNA pantalla lo usa: hoy no hay como anular'

  union all
  select 8, 'authenticated puede DELETE en rrhh_evento',
         has_table_privilege('authenticated','public.rrhh_evento','DELETE')::text,
         'f',
         'a proposito: el modulo es append-only, una duplicada no se borra'

) t order by t.orden;
