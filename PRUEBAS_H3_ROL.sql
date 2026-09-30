-- ════════════════════════════════════════════════════════════════════════
-- H3 · EL ROL QUE CORRE LAS PRUEBAS, Y EL USUARIO DE PRUEBA
-- PROPUESTA 17-sep-2026.
--
-- ✅ APLICADO Y VERIFICADO EL 17-sep-2026. Este encabezado se toca DESPUES de
--    mirar los numeros, no antes — la regla del 16-sep, cuando sobre un
--    "Success" sin verificar se escribio que algo estaba aplicado y durante
--    unos minutos el archivo y la bitacora afirmaban las dos algo falso.
--
--    LA EVIDENCIA. Andrea reporto cinco de los siete valores del control; los
--    SIETE se volvieron a medir aparte con `pg_lector.py` —solo lectura— para
--    no escribir "verificado" sobre un dato que nadie miro:
--
--      rol 1 · miembro_de_authenticated 1 · tablas (INSERT) 10
--      vistas_y_tablas_select 14 · acceso_total 6
--      puede_entrar t · saltea_rls t
--
--    Y los atributos, medidos: rolsuper f · rolcreatedb f · rolcreaterole f ·
--    rolconfig {statement_timeout=15s, idle_in_transaction_session_timeout=30s,
--    search_path=public,extensions}.
--    Sobrantes (UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER): **0**.
--    Usuario de prueba: nombre PRUEBAS-H3 · perfil **equipo** · activo t ·
--    sin `CAMBIAR-` suelto.
--
--    ⚠️ `miembro_de_authenticated 1` y `vistas_y_tablas_select 14` son los dos
--       que no venian en el reporte. El primero NO es cosmetico: sin esa
--       membresia el carril B daria "permission denied to set role" y ninguna
--       prueba de permiso existiria.
--
--    LA CLAVE quedo en `herramientas/conexion_db.env` (gitignored) como
--    `PRUEBAS_ROL_PASSWORD`. El archivo tiene 2 lineas: esa y la de la base.
--
-- QUE ES ESTO
--   El piso de `pg_pruebas.py` (pendiente H3). Crea UN rol de base de datos y
--   UNA fila en acceso_usuario. Nada mas. No toca ninguna tabla de datos, no
--   crea ni modifica ninguna politica, y no cambia nada de lo que la app usa.
--
-- LOS DOS CARRILES QUE ESTO HABILITA
--   A · llave maestra — saltea la RLS. Prueba reglas de CONTENIDO (candados,
--       constraints, triggers). Es D0-D7.
--   B · como usuario real — NO saltea nada. Prueba reglas de PERMISO. Es 7d,
--       D8 y la prueba nueva de ent_anulacion.
--   Los dos corren por la MISMA conexion: el carril B es el carril A que, ya
--   adentro del sobre, hace `set local role authenticated` y se pone encima
--   los claims del usuario de prueba. Eso lo emite la herramienta, nunca la
--   prueba: `set`, `set_config` y `reset` estan PROHIBIDOS en el SQL de entrada.
--
-- POR QUE ALCANZA CON UNA FILA Y NO HACE FALTA UN USUARIO DE AUTH
--   Medido: `auth.jwt()` es exactamente
--     coalesce( nullif(current_setting('request.jwt.claim' , true), ''),
--               nullif(current_setting('request.jwt.claims', true), '') )::jsonb
--   o sea que lee un GUC de sesion. Y de ese GUC cuelga toda la cadena:
--   auth.jwt() -> acceso_perfil() -> acceso_es_socia() -> las politicas.
--   Poniendo el GUC alcanza para manejar la cadena entera desde el sobre.
--   CONSECUENCIA BUENA, y es la razon por la que se eligio este camino:
--     · NO existe una cuenta nueva que pueda entrar a Truefie de verdad;
--     · NO hay una contrasena de Auth en ningun archivo;
--     · y una prueba que FALLA no deja nada escrito, porque todo vive adentro
--       de una transaccion que termina en rollback. Por REST eso es imposible:
--       PostgREST no tiene transaccion entre pedidos, cada pedido commitea, y
--       una politica mal escrita dejaria la fila puesta en produccion.
--   LO QUE ESTE CAMINO NO PRUEBA, y queda anotado aparte (B-rest):
--     · que el JWT venga firmado y valido (aca el claim se pone a mano);
--     · la capa de PostgREST;
--     · el `statement_timeout = 8s` que `authenticated` trae por rol, que se
--       aplica en el LOGIN y no en un `set role`.
--
-- ⚠️ CONSTRAINTS DIFERIDOS: hoy no hay NINGUNO (medido 17-sep-2026:
--    `select count(*) from pg_constraint where condeferrable` = 0). Queda
--    escrito porque si alguna vez aparece uno, una prueba que espera ERROR va
--    a pasar EN VERDE sin evaluarse: el diferido se chequea en el commit, y
--    aca nunca hay commit. Ese dia hay que volver a leer esta linea.
--
-- QUE NECESITA ANDREA ANTES DE PEGAR — DOS COSAS, ninguna va en este archivo
--   porque el repo es PUBLICO:
--     1. La CLAVE del rol                         -> §4
--     2. El CORREO del usuario de prueba          -> §6
--   ⚠️ La clave va a quedar escrita en el editor de SQL. NO guardes el snippet
--      con la clave adentro: borra el texto despues de correrlo. Y la clave va
--      despues a `herramientas/conexion_db.env` (gitignored), nunca al repo,
--      nunca por chat, nunca como argumento en la linea de comandos.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── §1 · EL ROL ─────────────────────────────────────────────────────────
-- Nace SIN LOGIN a proposito. Si el §4 no se corre, este rol no puede
-- conectarse y `pg_pruebas.py` falla con "authentication failed" — que es la
-- forma correcta de fallar. Lo que NO puede pasar es que quede con una clave
-- que este escrita en un repo publico.
--
-- `bypassrls` NO es decorativo y no se puede reemplazar con grants: medido, las
-- 7 tablas tienen `relforcerowsecurity = false`, o sea que el DUENO
-- (`postgres`) saltea la RLS por ser dueno. Este rol NO va a ser dueno de nada,
-- asi que sin el atributo la RLS se le aplicaria y el carril A no existiria.
--
-- Y lo que NO lleva es tan importante como lo que lleva. `nocreatedb`,
-- `nocreaterole`, y no es dueno de ninguna tabla — o sea que NO puede hacer
-- `alter table`, `drop`, ni crear nada. Los cambios de esquema siguen pasando
-- por Andrea, y eso es un REVOKE, no una promesa.
create role truefie_pruebas with
  nologin          -- el §4 le da login; ver el comentario de arriba
  nosuperuser
  nocreatedb
  nocreaterole
  noreplication
  bypassrls;       -- el carril A. El carril B lo apaga con `set local role`.

-- ── §2 · LA MEMBRESIA QUE HABILITA EL CARRIL B ──────────────────────────
-- `set role authenticated` solo lo puede hacer un rol que sea MIEMBRO de
-- `authenticated`. Sin esto, el carril B da "permission denied to set role".
-- No agrega poder: `authenticated` es estrictamente mas debil que este rol.
grant authenticated to truefie_pruebas;

-- ── §3 · LOS GRANTS · SOLO select E insert ──────────────────────────────
-- Deliberadamente SIN update y SIN delete. Las nueve pruebas solo insertan y
-- leen, y el rollback es el que limpia. Asi, aunque el sobre se rompiera, este
-- rol NO PUEDE modificar ni borrar una sola fila de produccion.
-- ⚠️ Si alguna vez se hace B-rest, ahi si va a hacer falta delete para limpiar
--    lo que quede escrito. No se agrega antes de que esa decision se tome.
grant usage on schema public to truefie_pruebas;

grant select, insert on
  ent_pedido,
  ent_devolucion,
  ent_devolucion_linea,
  ent_alisto,
  ent_alisto_linea,
  ent_alisto_lote,
  ent_odoo_pendiente,
  ent_odoo_pendiente_linea,
  ent_odoo_hecho,
  ent_anulacion
to truefie_pruebas;

-- Las columnas `id` son todas `generated always as identity` (medido), asi que
-- el insert alcanza: no hace falta grant sobre ninguna secuencia.

grant select on
  v_ent_devolucion_exceso,
  v_ent_odoo_pendiente,
  acceso_usuario,
  v_acceso_usuario
to truefie_pruebas;

-- ── §4 · LA CLAVE Y EL LOGIN · ⚠️ ANDREA: CAMBIAR ANTES DE CORRER ───────
-- Si te salteas esta linea, el rol queda NOLOGIN y nada puede conectarse.
-- Eso es seguro, no es un error: la verificacion del §7 te lo va a decir.
alter role truefie_pruebas login password 'CAMBIAR-por-una-clave-larga-y-nueva';

-- ── §5 · TIMEOUTS Y search_path ─────────────────────────────────────────
-- Por rol, no por sesion: asi no dependen de que la herramienta se acuerde.
-- ⚠️ Ojo con el modo de falla del segundo: cuando salta, MATA la conexion y la
--    transaccion se va en rollback — la direccion segura. Pero la herramienta
--    tiene que reportar "se corto la conexion" DISTINTO de "la prueba fallo",
--    o vuelve el problema de fallar por el motivo de al lado.
alter role truefie_pruebas set statement_timeout = '15s';
alter role truefie_pruebas set idle_in_transaction_session_timeout = '30s';
alter role truefie_pruebas set search_path = public, extensions;

-- ── §6 · EL USUARIO DE PRUEBA · ⚠️ ANDREA: CAMBIAR EL CORREO ────────────
-- Es una fila en acceso_usuario y NADA MAS. No hay usuario en Supabase Auth,
-- asi que este correo NO PUEDE entrar a Truefie: sin cuenta de Auth no hay
-- login posible. La fila existe unicamente para que `acceso_perfil()` tenga
-- que contestar 'equipo' cuando el sobre forje ese correo en los claims.
--
-- perfil 'equipo' a proposito: el carril B prueba que a quien NO es socia lo
-- rechacen. El caso contrario (que a una socia SI la dejen) sale gratis
-- forjando el correo de Andrea, que ya esta en la tabla — por eso alcanza con
-- UN usuario de prueba y no dos.
--
-- El nombre grita lo que es porque esta tabla dibuja el lobby: si alguna vez
-- alguien la mira, tiene que ser obvio de una que no es una persona.
insert into acceso_usuario (email, nombre, perfil, nota, creado_por) values
  ('CAMBIAR-pruebas@ejemplo.com', 'PRUEBAS-H3', 'equipo',
   'usuario de prueba de pg_pruebas.py (H3). NO es una persona. Sin cuenta en Auth: no puede entrar.',
   'H3-17sep2026');

-- ── §7 · CONTROL ADENTRO DE LA TRANSACCION, ANTES DEL COMMIT ────────────
-- La leccion del 16-sep: un pegado que devuelve "Success. No rows returned"
-- puede no haber aplicado NADA — basta con que el editor haya mandado solo un
-- tramo de comentario. O se ven los numeros de abajo, o esto no llego.
--
-- ESPERADO, exactamente:
--   rol 1 · miembro_de_authenticated 1 · tablas (con INSERT) 10
--   vistas_y_tablas_select 14  (las 10 tablas + las 4 vistas del §3)
--   usuario_prueba 1 · acceso_total 6 · puede_entrar t · saltea_rls t
-- ⚠️ `acceso_total` era 5 antes de este pegado (medido el 17-sep: 5 filas,
--    5 correos vigentes, 5 activos — 3 equipo y 2 socias). Si ves 5, la fila
--    del §6 no entro. Si ves 7 o mas, alguien la inserto dos veces.
-- ⚠️ Y si `puede_entrar` sale `f`, el §4 no se corrio: el rol existe pero no
--    puede conectarse. Es recuperable con un `alter role ... login password`.
select
  (select count(*) from pg_roles where rolname = 'truefie_pruebas')                      as rol,
  (select count(*) from pg_auth_members m
     join pg_roles r on r.oid = m.roleid join pg_roles g on g.oid = m.member
    where g.rolname = 'truefie_pruebas' and r.rolname = 'authenticated')                 as miembro_de_authenticated,
  (select count(*) from information_schema.role_table_grants
    where grantee = 'truefie_pruebas' and privilege_type = 'INSERT')                     as tablas,
  (select count(*) from information_schema.role_table_grants
    where grantee = 'truefie_pruebas' and privilege_type = 'SELECT')                     as vistas_y_tablas_select,
  (select count(*) from acceso_usuario where creado_por = 'H3-17sep2026')                as usuario_prueba,
  (select count(*) from acceso_usuario)                                                  as acceso_total,
  (select rolcanlogin from pg_roles where rolname = 'truefie_pruebas')                    as puede_entrar,
  (select rolbypassrls from pg_roles where rolname = 'truefie_pruebas')                   as saltea_rls;

commit;


-- ════════════════════════════════════════════════════════════════════════
-- §8 · DESPUES · VERIFICAR. Solo lectura, se puede correr cuantas veces sea.
-- ════════════════════════════════════════════════════════════════════════

-- V1 · Los atributos del rol. ESPERADO: super f · createdb f · createrole f
--      · bypassrls t · canlogin t
select rolname, rolsuper, rolcreatedb, rolcreaterole, rolbypassrls, rolcanlogin, rolconfig
  from pg_roles where rolname = 'truefie_pruebas';

-- V2 · Que NO pueda escribir de mas. ESPERADO: CERO filas.
--      Si aparece algun UPDATE, DELETE o TRUNCATE, el §3 se escribio mal.
select table_name, privilege_type
  from information_schema.role_table_grants
 where grantee = 'truefie_pruebas'
   and privilege_type in ('UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')
 order by table_name, privilege_type;

-- V3 · Que no pueda crear nada. ESPERADO: las dos columnas en `f`.
--      (`public` ya no le da CREATE a PUBLIC desde PG15 — medido: f. Esto lo
--       confirma para este rol en particular, que es lo que importa.)
select has_schema_privilege('truefie_pruebas','public','CREATE') as puede_crear_en_public,
       has_database_privilege('truefie_pruebas','postgres','CREATE') as puede_crear_esquemas;

-- V4 · El usuario de prueba, y que no quedo ningun CAMBIAR- suelto.
--      ESPERADO: 1 fila, perfil 'equipo', y `placeholder` en `f`.
select email, nombre, perfil, activo,
       (email like 'CAMBIAR-%') as placeholder
  from v_acceso_usuario where nombre = 'PRUEBAS-H3';

-- V5 · ⚠️ LA QUE IMPORTA DE VERDAD: que el usuario de prueba NO sea socia.
--      ESPERADO: 'equipo'. Si dijera 'socias', el carril B probaria al reves y
--      todas las pruebas de permiso pasarian en verde sin probar nada.
select perfil as debe_decir_equipo
  from v_acceso_usuario where nombre = 'PRUEBAS-H3' and activo;
