-- ════════════════════════════════════════════════════════════════════════
-- CERRAR `ent_anulacion_ins` · de `with check (true)` a `acceso_es_socia()`
-- PROPUESTA 17-sep-2026 · ✅ **APLICADO EN PRODUCCION EL 18-sep-2026.**
--
-- Este encabezado se escribe DESPUES de correrlo y de haber mirado la
-- verificacion, no antes. Regla del 16-sep: sobre un "Success" sin verificar se
-- escribio que algo estaba aplicado, y durante unos minutos el archivo y la
-- bitacora afirmaban las dos algo falso.
--
-- ── LA EVIDENCIA, MEDIDA EL 18-sep ──────────────────────────────────
-- §0 · los seis valores del antes, IDENTICOS a los del 17-sep: con_check
--      `true` · 6 filas (alisto 3 · salida 2 · devolucion 1) · 5 de 6 por pegado
--      a mano y la unica de la app firmada por una socia · 7e 8 filas/1049 uds
--      · devoluciones 1 total / 0 vigentes.
-- P0 · corrio ANTES del cambio y el insert ENTRO (`INSERT 0 1`), con su
--      control mirado aparte: `equipo` · `f` · claims puestos. O sea que P0
--      midio la POLITICA y no a `postgres` salteando la RLS.
-- §1 · el control de adentro de la transaccion, antes del commit:
--      **politicas_insert 1 · con_check `acceso_es_socia()` · sigue_en_true 0.**
--
-- ── Y DESPUES, POR EL CARRIL B (`pg_pruebas.py`, no el editor) ────────
-- B0 · 1 fila · `equipo` · `f` → el carril B apaga el bypass de la RLS, asi que
--      lo que sigue significa algo. Va aparte porque `--solo` se lo saltea.
-- D9 · identidad de perfil 'equipo' → **ERROR 42501**, "new row violates
--      row-level security policy for table ent_anulacion". Es el agujero
--      cerrado, medido: el 17-sep ese mismo insert ENTRABA.
-- D9 · identidad de SOCIA → **`INSERT 0 1`**. El control del otro lado: una
--      politica que no deja pasar a nadie tambien "protege" y rompe la
--      pantalla. ⚠️ La linea que imprime D9 dice "D9 MAL: el insert ENTRO",
--      pero ese texto esta escrito para la identidad 'equipo'; con una socia
--      que entre es el resultado CORRECTO.
-- 7e · **8 filas · 1049 uds**, identico al 0d: ningun saldo se movio.
-- V1 · leido aparte: `ent_anulacion_ins` · INSERT · {authenticated} ·
--      con_check `acceso_es_socia()`, y ninguna otra politica de INSERT.
-- V5/V6 · **0 filas `prueba-%`** y **6 filas en total**: las pruebas no
--      dejaron nada escrito.
--
-- ── DE DONDE SALE ───────────────────────────────────────────────────────
-- La pantalla de Devoluciones (b61) dice que anular es SOLO SOCIAS. La base
-- decia otra cosa. No es una lectura del catalogo: el 17-sep se MIDIO EN VIVO
-- con `pg_pruebas.py` carril B —como usuaria de perfil 'equipo', con la RLS
-- aplicando de verdad— y el insert ENTRO:
--
--     PRUEBA D9_ANULACION · CARRIL B
--       corre como: authenticated · la RLS SI aplica
--       INSERT 0 1
--       D9: el insert ENTRO — hoy la politica NO protege
--
-- El propio codigo ya lo decia (`index.html`, `dvPuedeAnular`):
--     "EL PERMISO NO IMPIDE NADA. (…) Que nadie lea este `if` y crea que
--      protege."
-- Este cambio convierte ese `if` en lo que ya aparentaba ser.
--
-- ── 🔴 LO QUE ESTE CAMBIO **NO** HACE, Y HAY QUE LEERLO DERECHO ─────────
-- **Cierra la puerta de la APP, no la del editor.** El SQL Editor entra como
-- `postgres`, que saltea la RLS: despues de esto, un pegado a mano sigue
-- pudiendo escribir una anulacion igual que hoy. Y esta bien que asi sea —
-- quien tiene el editor ya puede hacer cualquier cosa con la base, y agregarle
-- un candado ahi seria teatro.
-- Pero que **nadie lo lea como "ahora solo las socias pueden anular, punto"**.
-- Lo correcto es: por la aplicacion, anular exige perfil de socias, y eso
-- ahora lo garantiza la base y no la pantalla.
--
-- ── POR QUE PLANO Y NO POR ENTIDAD ──────────────────────────────────────
-- `ent_anulacion` acepta 'alisto', 'salida' y 'devolucion', y NO son lo mismo.
-- Pero medido el 17-sep: **la app escribe UNA sola clase, 'devolucion'** — hay
-- exactamente un insert a esta tabla en todo `index.html` (linea 13929), y
-- buscar `entidad:'alisto'` y `entidad:'salida'` en el archivo da **cero**.
-- Las de alisto y salida existen solo porque se pegaron a mano, o sea por el
-- camino que igual saltea la RLS.
-- Entonces una politica por entidad **no cambiaria nada hoy** y seria construir
-- una puerta para una pantalla que no existe. Asi llego el `with check (true)`:
-- permisos escritos antes que el caso.
-- ⚠️ CUANDO SE CONSTRUYA §7 (anular un despacho desde la pantalla), esta
--    politica se revisa CON LA PANTALLA EN LA MANO. Ese es el momento de
--    decidir si Daniel puede anular algo suyo — hoy no hay donde.
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- §0 · LAS MEDICIONES DE ANTES · solo lectura, correr y GUARDAR la salida
-- ════════════════════════════════════════════════════════════════════════
-- Sin esto, el "despues" no se puede comparar con nada.

-- 0a · LA POLITICA ACTUAL, TEXTUAL.
--      MEDIDO el 17-sep:  ent_anulacion_ins · INSERT · PERMISSIVE
--                         roles {authenticated} · using (sin using)
--                         with_check **true**
select policyname, cmd, permissive, roles::text as roles,
       coalesce(qual,'(sin using)')       as usando,
       coalesce(with_check,'(sin check)') as con_check
  from pg_policies
 where schemaname = 'public' and tablename = 'ent_anulacion'
 order by policyname;

-- 0b · CUANTAS FILAS TIENE HOY, y de que clase.
--      MEDIDO el 17-sep:  6 en total — alisto 3 · salida 2 · devolucion 1
select count(*) as filas_total from ent_anulacion;

select entidad, count(*) as cuantas,
       min(creado_en)::date as primera, max(creado_en)::date as ultima
  from ent_anulacion group by entidad order by entidad;

-- 0c · QUIEN LAS ESCRIBIO. Es lo que decide si el cambio rompe algo.
--      MEDIDO el 17-sep: CINCO de las seis las escribio un pegado a mano
--      (`correccion-sql…`, que no es una sesion y entra como postgres); la
--      unica que entro por la app la firmo una SOCIA (el correo no se escribe
--      aca: el repo es publico; sale del 0c cuando se corre). O sea: **nadie sin perfil de socia escribio nunca una
--      anulacion por la aplicacion**, y este cambio no rompe nada existente.
select a.creado_por, count(*) as cuantas,
       coalesce(v.perfil, '— no esta en acceso_usuario') as perfil
  from ent_anulacion a
  left join v_acceso_usuario v on lower(v.email) = lower(a.creado_por)
 group by a.creado_por, v.perfil
 order by count(*) desc;

-- 0d · 7e · EL CANARIO. Ningun saldo se puede mover con este cambio: solo se
--      toca una politica de INSERT. Si 7e cambia, paso algo que no era esto.
--      MEDIDO el 17-sep:  8 filas · 1049 uds
select count(*) as filas_7e, sum(uds) as uds_7e
  from ent_salido_del_congelador_desde_ancla;

-- 0e · De paso, el estado de las devoluciones.
--      MEDIDO el 17-sep:  1 en total · 0 vigentes (Andrea anulo la unica).
select (select count(*) from ent_devolucion)         as devoluciones_total,
       (select count(*) from ent_devolucion_vigente) as devoluciones_vigentes;


-- ════════════════════════════════════════════════════════════════════════
-- P0 · LA PRUEBA QUE HOY TIENE QUE **PASAR** · el espejo del despues
-- ════════════════════════════════════════════════════════════════════════
-- Es el insert de D9 tal cual: como alguien de perfil 'equipo', anular una
-- devolucion. HOY ENTRA. Despues del cambio tiene que dar 42501.
--
-- 🔴 EL DETALLE QUE HACE QUE ESTO SIRVA, Y SIN EL NO PRUEBA NADA:
--    el SQL Editor entra como `postgres` y **saltea la RLS**. Un insert pelado
--    acá pasaria con la politica vieja Y con la nueva, o sea que no mediria la
--    politica: mediria que postgres puede escribir, que ya lo sabemos.
--    Por eso el bloque se pone encima la identidad de prueba ANTES de insertar.
--    Es exactamente lo que hace `pg_pruebas.py` en su carril B, traido acá para
--    que el pegado se sostenga solo.
--
-- ⚠️ El correo NO se escribe en este archivo: el repo es PUBLICO. Se lee de la
--    base con `set_config`, que a diferencia de `SET` acepta una expresion.
--    Y va ANTES del `set local role`, porque despues de cambiar de rol la
--    lectura de `v_acceso_usuario` queda filtrada por la RLS.
--
-- ESPERADO HOY:  `INSERT 0 1` y la fila 'P0 …: el insert ENTRO'.
--                Si ya diera 42501, el cambio YA se aplico: no lo pegues dos
--                veces, anda derecho a la verificacion final.
begin;
  select set_config('request.jwt.claims',
           (select json_build_object('email', v.email, 'role', 'authenticated')::text
              from v_acceso_usuario v
             where v.nombre = 'PRUEBAS-H3' and v.activo),
           true) is not null as claims_puestos;

  set local role authenticated;

  -- Control de que la identidad agarro: TIENE que decir 'equipo' y `f`.
  -- Si dijera 'socias', este P0 no probaria nada — una socia pasa en los dos
  -- mundos. Y si `acceso_perfil()` diera null, el claim no llego.
  select acceso_perfil() as debe_decir_equipo, acceso_es_socia() as debe_ser_f;

  insert into ent_anulacion (entidad, entidad_id, motivo, creado_por)
  values ('devolucion', 999999, 'P0 antes de cerrar la politica', 'prueba-p0');

  select 'P0: el insert ENTRO — la politica vieja no protege' as resultado;
rollback;


-- ════════════════════════════════════════════════════════════════════════
-- §1 · EL CAMBIO · una sola transaccion, con su control adentro
-- ════════════════════════════════════════════════════════════════════════
-- ⚠️ SELECCIONA DESDE `begin;` HASTA `commit;` Y NADA MAS. El archivo arranca
--    con ~130 lineas de comentario, y un tramo de puro comentario devuelve
--    exactamente "Success. No rows returned" — que el 16-sep hizo creer que
--    algo se habia aplicado cuando no se aplico nada.
begin;

  -- Se reemplaza, no se agrega: dos politicas PERMISSIVE de INSERT se SUMAN
  -- con OR, asi que dejar la vieja al lado de la nueva no cerraria nada.
  drop policy if exists ent_anulacion_ins on ent_anulacion;

  create policy ent_anulacion_ins on ent_anulacion
    for insert to authenticated
    with check (acceso_es_socia());

  -- ── EL CONTROL, ADENTRO Y ANTES DEL COMMIT ──────────────────────────
  -- O se ven estos valores, o esto no llego. No alcanza con "Success".
  -- ESPERADO, exactamente:
  --     politicas_insert 1 · con_check acceso_es_socia() · sigue_en_true 0
  select
    (select count(*) from pg_policies
      where schemaname='public' and tablename='ent_anulacion' and cmd='INSERT')
                                                            as politicas_insert,
    (select with_check from pg_policies
      where schemaname='public' and tablename='ent_anulacion'
        and policyname='ent_anulacion_ins')                 as con_check,
    (select count(*) from pg_policies
      where schemaname='public' and tablename='ent_anulacion'
        and cmd='INSERT' and with_check = 'true')           as sigue_en_true;

commit;


-- ════════════════════════════════════════════════════════════════════════
-- §2 · DESPUES · VERIFICAR. Solo lectura salvo V3, que hace rollback.
-- ════════════════════════════════════════════════════════════════════════

-- V1 · La politica nueva, textual. ESPERADO: `acceso_es_socia()` en con_check,
--      y NINGUNA politica de INSERT que diga `true`.
select policyname, cmd, roles::text as roles,
       coalesce(with_check,'(sin check)') as con_check
  from pg_policies
 where schemaname = 'public' and tablename = 'ent_anulacion'
 order by policyname;

-- V2 · 7e otra vez. ESPERADO: IDENTICO al 0d — 8 filas · 1049 uds.
--      Si cambio, paso algo que no era este cambio.
select count(*) as filas_7e, sum(uds) as uds_7e
  from ent_salido_del_congelador_desde_ancla;

-- V3 · 🔴 LA QUE IMPORTA: EL P0 INVERTIDO.
--      El mismo bloque de arriba, palabra por palabra, y ahora
--      ESPERADO: **ERROR 42501** ·
--                "new row violates row-level security policy for table
--                 ent_anulacion"
--      ⚠️ Si esto PASA en vez de fallar, la politica no quedo: puede que el
--         §1 no se haya seleccionado entero. Volve al §1.
begin;
  select set_config('request.jwt.claims',
           (select json_build_object('email', v.email, 'role', 'authenticated')::text
              from v_acceso_usuario v
             where v.nombre = 'PRUEBAS-H3' and v.activo),
           true) is not null as claims_puestos;

  set local role authenticated;

  select acceso_perfil() as debe_decir_equipo, acceso_es_socia() as debe_ser_f;

  insert into ent_anulacion (entidad, entidad_id, motivo, creado_por)
  values ('devolucion', 999999, 'V3 despues de cerrar la politica', 'prueba-v3');

  select 'V3 MAL: el insert ENTRO — la politica NO quedo' as resultado;
rollback;

-- V4 · Y el CONTROL del otro lado, que es tan importante como V3: que a una
--      SOCIA la siga dejando. Una politica que no deja pasar a nadie tambien
--      "protege", y rompe la pantalla.
--      ESPERADO: `INSERT 0 1` y la fila 'V4 OK'.
begin;
  select set_config('request.jwt.claims',
           (select json_build_object('email', v.email, 'role', 'authenticated')::text
              from v_acceso_usuario v
             where v.perfil = 'socias' and v.activo
             order by v.email limit 1),
           true) is not null as claims_puestos;

  set local role authenticated;

  select acceso_perfil() as debe_decir_socias, acceso_es_socia() as debe_ser_t;

  insert into ent_anulacion (entidad, entidad_id, motivo, creado_por)
  values ('devolucion', 999999, 'V4 control de socia', 'prueba-v4');

  select 'V4 OK: la socia sigue pudiendo anular' as resultado;
rollback;

-- V5 · Que no quedo nada escrito por las pruebas. ESPERADO: 0.
select count(*) as debe_ser_0
  from ent_anulacion where creado_por like 'prueba-%';

-- V6 · Y las seis de siempre, intactas. ESPERADO: 6.
select count(*) as debe_ser_6 from ent_anulacion;

-- ⚠️ V7 · LO QUE ESTE ARCHIVO NO PUEDE PROBAR SOLO. V3 y V4 se ponen la
--      identidad a mano con `set_config`: eso ejercita la RLS y la cadena
--      `auth.jwt() → acceso_perfil() → acceso_es_socia()`, que es lo que
--      importa, pero NO prueba la firma del JWT ni la capa de PostgREST.
--      El camino de verdad es la app. Cuando se pueda, abrir Devoluciones con
--      una sesion que no sea de socia y comprobar que el boton no esta — y que
--      si alguien lo forzara por REST, rebota.
