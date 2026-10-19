-- ════════════════════════════════════════════════════════════════════════
-- ENSAYO · CARGA HISTORICA DE VACACIONES DE DANIEL · termina en ROLLBACK
-- 7-oct-2026. Va DESPUES de PERSONAL_ARREGLO_RESOLVER.sql (pegado 8), que ya
-- esta aplicado: la aprobacion pasa por rrhh_resolver_evento(), y antes de ese
-- arreglo la funcion no podia escribir.
--
-- ⚠️ TERMINA EN `rollback;`. No deja ni una fila. Es el ENSAYO del archivo real
-- (CARGA_VACACIONES_DANIEL.sql) y corre sobre los datos de verdad, asi que mide
-- exactamente lo que va a pasar — y despues lo deshace.
--
-- ⚠️ NO TOCA las dos solicitudes del 19-20 de noviembre. Solo las LEE, para
-- comprobar que lo pendiente no cuenta como tomado.
--
-- ⚠️ NO IMPRIME NINGUN CORREO. Las cuentas salen de acceso_usuario por el nombre
-- de pila y viajan por un set_config; a la salida solo van dias y conteos.
--
-- QUE SE CARGA (7 dias, todos completos, todos de 2026):
--     20 de marzo ....... 1 dia   (viernes)
--     24 de abril ....... 1 dia   (viernes)
--     22 al 26 de junio . 5 dias  (lunes a viernes)
--
-- LOS DIAS DE SEMANA YA SE VERIFICARON FUERA (los 7 son lunes-viernes). Lo que
-- NO se pudo verificar desde afuera —y por eso va como GUARDIA que aborta— es
-- si alguno cae en un feriado o cierre de `rrhh_feriado`, y si todos son
-- posteriores al ingreso de Daniel: las dos tablas estan cerradas a la anon key.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── 0 · QUIEN ES QUIEN ──────────────────────────────────────────────────
-- ⚠️ ACA FALLO LA PRIMERA VERSION, Y EL ERROR SALVO LA CARGA.
-- Decia `where p.nombre ilike 'daniel%'`. ILIKE con % es un PREFIJO, y el equipo
-- es Daniel, Daniela y Neybel: 'daniel%' matchea a Daniel **y a Daniela**. Dos
-- filas en una subconsulta usada como expresion -> ERROR 21000.
--
-- Lo importante no es el error, es lo que habria pasado sin el: con un `limit 1`
-- puesto para "arreglarlo", la subconsulta habria devuelto UNA de las dos sin
-- decir cual, y los 7 dias historicos de Daniel podrian haber quedado cargados
-- a nombre de DANIELA. Un limit 1 sobre un conjunto ambiguo no arregla la
-- ambiguedad: la esconde y elige al azar.
--
-- EL MATCHER ES LA PRIMERA PALABRA EXACTA, no un prefijo:
--     split_part(btrim(nombre),' ',1) = 'daniel'
-- matchea 'Daniel' y 'Daniel Ramirez', y NO matchea 'Daniela' ni 'Daniela Mora'.
--
-- Y EL ORDEN CAMBIO: los CONTEOS van PRIMERO. `count(*)` nunca puede dar 21000,
-- asi que el guardia alcanza a hablar. En la version anterior el guardia existia
-- —contaba bien— pero corria DESPUES del escalar que reventaba, asi que nunca
-- llegaba a decir nada. Un guardia que se ejecuta tarde no es un guardia.
--
-- Nunca se imprime un correo.

-- OVERRIDE, por si el nombre guardado no alcanza para identificarlo solo (por
-- ejemplo si hubiera dos personas cuya primera palabra es 'Daniel'). Se pone el
-- id a mano y el guardia igual lo valida contra la base.
select set_config('cv.id_manual', '', true);

-- PRIMERO LOS CONTEOS. Son count(*): no pueden reventar.
select set_config('cv.daniel_n',
  (select count(*)::text from rrhh_persona p
    where lower(split_part(btrim(p.nombre), ' ', 1)) = 'daniel'), true);
select set_config('cv.socia_n',
  (select count(*)::text from acceso_usuario a
    where lower(split_part(btrim(a.nombre), ' ', 1)) = 'lorena'
      and a.perfil = 'socias' and a.activo), true);

do $$
declare v_n int;
begin
  -- DANIEL
  if coalesce(current_setting('cv.id_manual', true),'') <> '' then
    select count(*) into v_n from rrhh_persona p
     where p.id = current_setting('cv.id_manual', true)::bigint;
    if v_n <> 1 then
      raise exception 'ENSAYO ABORTADO: el id puesto a mano en cv.id_manual (%) no existe '
        'en rrhh_persona.', current_setting('cv.id_manual', true);
    end if;
    perform set_config('cv.daniel', current_setting('cv.id_manual', true), true);
  elsif coalesce(nullif(current_setting('cv.daniel_n', true),'')::numeric, -1) <> 1 then
    raise exception 'ENSAYO ABORTADO: % personas de rrhh_persona tienen "Daniel" como '
      'primera palabra del nombre. Tiene que ser exactamente 1 para no cargarle los '
      'dias a quien no es. Mira quienes son y pone el id a mano arriba, en '
      'cv.id_manual:  select id, nombre from rrhh_persona order by id;',
      current_setting('cv.daniel_n', true);
  else
    perform set_config('cv.daniel',
      (select p.id::text from rrhh_persona p
        where lower(split_part(btrim(p.nombre), ' ', 1)) = 'daniel'), true);
  end if;

  -- LORENA. Mismo criterio: la carga la firma ELLA, asi que no sirve "cualquier
  -- socia". Con el `limit 1` de antes, una segunda socia llamada Lorena —o el
  -- orden de los ids— podia firmar la carga a nombre de la otra.
  if coalesce(nullif(current_setting('cv.socia_n', true),'')::numeric, -1) <> 1 then
    raise exception 'ENSAYO ABORTADO: % socias activas tienen "Lorena" como primera '
      'palabra del nombre en acceso_usuario; tiene que ser exactamente 1. Sin eso no '
      'se puede impersonar y la vista (que filtra por acceso_es_socia()) devolveria '
      'CERO FILAS: el ensayo saldria en verde sin medir nada.',
      current_setting('cv.socia_n', true);
  end if;
  perform set_config('cv.socia',
    (select a.email from acceso_usuario a
      where lower(split_part(btrim(a.nombre), ' ', 1)) = 'lorena'
        and a.perfil = 'socias' and a.activo), true);
end $$;


-- ── 1 · LAS 7 FECHAS, EN UNA TABLA TEMPORAL ─────────────────────────────
-- Una fila por DIA, para poder revisar feriado por feriado. La tabla temporal se
-- va con el rollback.
create temp table cv_dias (dia date primary key) on commit drop;
insert into cv_dias (dia) values
  ('2026-03-20'), ('2026-04-24'),
  ('2026-06-22'), ('2026-06-23'), ('2026-06-24'), ('2026-06-25'), ('2026-06-26');


-- ── 2 · LOS TRES GUARDIAS, CONTRA LA BASE REAL ──────────────────────────
do $$
declare
  v_ing    date;
  v_fer    int;
  v_finde  int;
  v_antes  int;
begin
  select p.ingreso into v_ing from rrhh_persona p
   where p.id = current_setting('cv.daniel', true)::bigint;

  if v_ing is null then
    raise exception 'ENSAYO ABORTADO: Daniel no tiene fecha de ingreso en rrhh_persona. '
      'Sin ingreso, v_rrhh_vacacion_saldo lo EXCLUYE (where p.ingreso is not null) y el '
      'saldo no existiria.';
  end if;

  -- (a) ninguno puede ser feriado ni cierre de planta
  select count(*) into v_fer
    from cv_dias d
   where exists (select 1 from rrhh_feriado f
                  where daterange(f.fecha, coalesce(f.fecha_fin, f.fecha), '[]') @> d.dia);
  -- (b) ninguno puede caer en fin de semana (ya verificado afuera; se repite acá
  --     contra la base para que el archivo no dependa de una cuenta hecha aparte)
  select count(*) into v_finde from cv_dias d where extract(isodow from d.dia) > 5;
  -- (c) todos tienen que ser posteriores al ingreso
  select count(*) into v_antes from cv_dias d where d.dia <= v_ing;

  perform set_config('cv.ingreso', v_ing::text, true);
  perform set_config('cv.feriados', v_fer::text, true);
  perform set_config('cv.findes',   v_finde::text, true);
  perform set_config('cv.antes',    v_antes::text, true);

  if v_fer > 0 then
    raise exception 'ENSAYO ABORTADO: % de los 7 dias cae en un feriado o cierre de '
      'rrhh_feriado. Cargarlo como vacacion le descontaria a Daniel un dia que la '
      'fabrica no abria. Revisar cuales con el select del pie.', v_fer;
  end if;
  if v_finde > 0 then
    raise exception 'ENSAYO ABORTADO: % de los 7 dias cae en fin de semana.', v_finde;
  end if;
  if v_antes > 0 then
    raise exception 'ENSAYO ABORTADO: % de los 7 dias es anterior o igual al ingreso (%). '
      'No se pueden tomar vacaciones antes de entrar.', v_antes, v_ing;
  end if;
end $$;


-- ── 3 · EL ESTADO DE ANTES, para poder comparar ─────────────────────────
-- Se mide como socia, porque la vista filtra por acceso_es_socia().
select set_config('request.jwt.claims',
  json_build_object('email', current_setting('cv.socia', true),
                    'role','authenticated')::text, true);
select set_config('role','authenticated', true);

do $$
declare r record;
begin
  if not coalesce(acceso_es_socia(), false) then
    perform set_config('role','postgres', true);
    raise exception 'ENSAYO ABORTADO: impersonar a la socia no funciono. La vista habria '
      'devuelto cero filas y todo "pasaria" sin medir nada.';
  end if;
  select dias_ganados, dias_tomados, dias_disponibles, meses_completos into r
    from v_rrhh_vacacion_saldo
   where persona_id = current_setting('cv.daniel', true)::bigint;
  perform set_config('cv.a_ganados',  coalesce(r.dias_ganados::text,''),     true);
  perform set_config('cv.a_tomados',  coalesce(r.dias_tomados::text,''),     true);
  perform set_config('cv.a_disp',     coalesce(r.dias_disponibles::text,''), true);
  perform set_config('cv.a_meses',    coalesce(r.meses_completos::text,''),  true);
  -- Las dos solicitudes de noviembre, ANTES: cuantas y en que estado.
  perform set_config('cv.a_nov',
    (select count(*)::text from v_rrhh_evento_estado
      where persona_id = current_setting('cv.daniel', true)::bigint
        and tipo = 'vacaciones' and fecha = date '2026-11-19'), true);
  perform set_config('cv.a_nov_pend',
    (select count(*)::text from v_rrhh_evento_estado
      where persona_id = current_setting('cv.daniel', true)::bigint
        and tipo = 'vacaciones' and fecha = date '2026-11-19'
        and estado = 'solicitado'), true);
  perform set_config('role','postgres', true);
end $$;


-- ── 4 · LA CARGA, POR EL CAMINO REAL ────────────────────────────────────
-- Se inserta y se aprueba COMO SOCIA, no como postgres: asi pasa por la politica
-- rrhh_evento_ins y por el guardia de rrhh_resolver_evento(), que es exactamente
-- lo que va a hacer el archivo real.
select set_config('request.jwt.claims',
  json_build_object('email', current_setting('cv.socia', true),
                    'role','authenticated')::text, true);
select set_config('role','authenticated', true);

do $$
declare
  v_id   bigint;
  v_n    int;
  v_tot  int := 0;
  r      record;
begin
  for r in
    select * from (values (date '2026-03-20', 1),
                          (date '2026-04-24', 1),
                          (date '2026-06-22', 5)) as v(f, d)
  loop
    insert into rrhh_evento (persona_id, fecha, tipo, dias, motivo, creado_por)
    values (current_setting('cv.daniel', true)::bigint, r.f, 'vacaciones', r.d,
            'Carga histórica: vacaciones tomadas antes de usar Truefie',
            current_setting('cv.socia', true))
    returning id into v_id;

    -- La aprobacion por el camino real. Devuelve 1 fila si escribio.
    select count(*) into v_n from rrhh_resolver_evento(v_id, true, null, null,
      'Carga histórica: vacaciones tomadas antes de usar Truefie');
    v_tot := v_tot + v_n;
  end loop;
  perform set_config('cv.aprobadas', v_tot::text, true);

  -- El estado de DESPUES.
  select dias_ganados, dias_tomados, dias_disponibles into r
    from v_rrhh_vacacion_saldo
   where persona_id = current_setting('cv.daniel', true)::bigint;
  perform set_config('cv.d_ganados', coalesce(r.dias_ganados::text,''),     true);
  perform set_config('cv.d_tomados', coalesce(r.dias_tomados::text,''),     true);
  perform set_config('cv.d_disp',    coalesce(r.dias_disponibles::text,''), true);

  -- Y las de noviembre, DESPUES: tienen que seguir igual y seguir pendientes.
  perform set_config('cv.d_nov',
    (select count(*)::text from v_rrhh_evento_estado
      where persona_id = current_setting('cv.daniel', true)::bigint
        and tipo = 'vacaciones' and fecha = date '2026-11-19'), true);
  perform set_config('cv.d_nov_pend',
    (select count(*)::text from v_rrhh_evento_estado
      where persona_id = current_setting('cv.daniel', true)::bigint
        and tipo = 'vacaciones' and fecha = date '2026-11-19'
        and estado = 'solicitado'), true);

  perform set_config('role','postgres', true);
end $$;


-- ── 5 · LA TABLA ────────────────────────────────────────────────────────
-- Cada fila compara un escalar capturado contra un valor concreto. No hay ni un
-- bool_and, asi que un dato que falte da NULL y un NULL nunca entra al `then`:
-- la falta de medicion sale FALLA, nunca OK.
--
-- ⚠️ TODO LO QUE VIENE DE UNA COLUMNA NUMERICA SE COMPARA COMO NUMERIC, nunca
-- como texto. Aca fallo la segunda version (ERROR 22P02) y de paso habia un
-- segundo bug que todavia no se habia visto:
--   · `dias_ganados`     = sum(rrhh_param(...))        -> NUMERIC -> '9.0'
--   · `dias_disponibles` = ganados - tomados           -> NUMERIC -> '2.0'
--   · `dias_tomados`     = coalesce(sum(dias),0)       -> bigint  -> '7'
-- `'2.0'::int` revienta con 22P02 (eso es lo que se vio), y `'2.0' = '2'` como
-- TEXTO da false sin reventar — la fila 10 habria dicho FALLA para siempre y
-- nadie habria sabido por que. El mismo error, una vez ruidoso y una vez
-- silencioso; el silencioso es el peor.
-- `'2.0'::numeric = 2` da true, EXACTO, sin redondear nada.
select t.orden, t.prueba, t.esperado, t.obtenido,
       -- ⚠️ TRES ESTADOS, Y EL TERCERO ES NUEVO (7-oct-2026).
       -- La fila 12 decia esperado '2 / 2', obtenia '2 / 1' y daba OK: el
       -- veredicto comparaba DESPUES contra ANTES y nunca mira el esperado que
       -- muestra. El veredicto era correcto en sustancia pero la fila mentia, y
       -- una fila que muestra un esperado que no se cumple y dice OK es peor que
       -- una que falla: entrena a no leer la columna.
       -- Lo mismo pasaba en la fila 5, con el veredicto fijo en `true`.
       -- Ahora: lo informativo dice INFO —nunca OK—, y donde el predicado compara
       -- contra un valor CAPTURADO, el esperado se DERIVA de ese mismo valor, asi
       -- que esperado y obtenido no pueden divergir sin que se vea.
       case when t.prueba like 'INFO%' then 'INFO'
            when t.obtenido like 'SIN PROBAR%' then 'SIN PROBAR'
            when t.ok then 'OK' else 'FALLA' end as veredicto
  from (
  select 0 as orden, 'INFO · ingreso de Daniel (lo lee de la base)'::text as prueba,
         'informativo · lo que mide es la fila 3'::text as esperado,
         coalesce(nullif(current_setting('cv.ingreso', true),''),'SIN DATO') as obtenido,
         true as ok
  union all
  select 1, 'guardia · dias en feriado o cierre', '0',
         coalesce(current_setting('cv.feriados', true),'SIN DATO'),
         nullif(current_setting('cv.feriados', true),'')::numeric = 0
  union all
  select 2, 'guardia · dias en fin de semana', '0',
         coalesce(current_setting('cv.findes', true),'SIN DATO'),
         nullif(current_setting('cv.findes', true),'')::numeric = 0
  union all
  select 3, 'guardia · dias anteriores o iguales al ingreso', '0',
         coalesce(current_setting('cv.antes', true),'SIN DATO'),
         nullif(current_setting('cv.antes', true),'')::numeric = 0
  union all
  select 4, 'ANTES · tomados', '0',
         coalesce(nullif(current_setting('cv.a_tomados', true),''),'SIN FILA'),
         nullif(current_setting('cv.a_tomados', true),'')::numeric = 0
  union all
  -- INFO, no prueba: los ganados dependen de la fecha en que se corra (hoy 9, en
  -- noviembre 10). Lo que SI se mide es la fila 8.
  select 5, 'INFO · ganados / meses cumplidos (dependen de la fecha)',
         'informativo · lo que mide es la fila 8',
         coalesce(nullif(current_setting('cv.a_ganados', true),''),'SIN FILA') || ' / '
           || coalesce(nullif(current_setting('cv.a_meses', true),''),'?'),
         true
  union all
  select 6, 'las 3 aprobaciones escribieron (1 fila cada una)', '3',
         coalesce(current_setting('cv.aprobadas', true),'SIN DATO'),
         nullif(current_setting('cv.aprobadas', true),'')::numeric = 3
  union all
  select 7, 'DESPUES · tomados = 7', '7',
         coalesce(nullif(current_setting('cv.d_tomados', true),''),'SIN FILA'),
         nullif(current_setting('cv.d_tomados', true),'')::numeric = 7
  union all
  -- ESPERADO DERIVADO: se calcula de los ganados capturados, no se escribe a
  -- mano. Asi la fila sigue valiendo en noviembre (10 - 7 = 3) sin tocarla, y el
  -- esperado nunca puede decir una cosa mientras el predicado compara otra.
  select 8, 'DESPUES · disponibles = ganados - 7',
         coalesce((nullif(current_setting('cv.d_ganados', true),'')::numeric - 7)::text,'?'),
         coalesce(nullif(current_setting('cv.d_disp', true),''),'SIN FILA'),
         nullif(current_setting('cv.d_disp', true),'')::numeric
           = nullif(current_setting('cv.d_ganados', true),'')::numeric - 7
  union all
  -- ESPERADO DERIVADO del estado de ANTES, capturado en esta misma transaccion.
  select 9, 'DESPUES · ganados NO cambiaron (la carga no inventa antiguedad)',
         coalesce(nullif(current_setting('cv.a_ganados', true),''),'?'),
         coalesce(nullif(current_setting('cv.d_ganados', true),''),'SIN FILA'),
         nullif(current_setting('cv.d_ganados', true),'')::numeric
           = nullif(current_setting('cv.a_ganados', true),'')::numeric
  union all
  -- Esta fila SOLO vale si hoy los ganados son 9. Si no, no se puede probar el
  -- "2" y lo dice, en vez de fallar por una razon que no es un bug.
  select 10, 'hoy, con 9 ganados: disponibles = 2', '2',
         case when coalesce(nullif(current_setting('cv.d_ganados', true),'')::numeric, -1) <> 9
              then 'SIN PROBAR · los ganados de hoy son '
                   || coalesce(nullif(current_setting('cv.d_ganados', true),''),'?') || ', no 9'
              else coalesce(nullif(current_setting('cv.d_disp', true),''),'SIN FILA') end,
         nullif(current_setting('cv.d_disp', true),'')::numeric = 2
  union all
  -- LO PENDIENTE NO CUENTA COMO TOMADO. Si las solicitudes de noviembre se
  -- sumaran, tomados daria 9 y no 7.
  select 11, 'lo PENDIENTE de noviembre NO cuenta como tomado (si contara, daria 9)',
         '7, con al menos 1 pendiente',
         case when coalesce(nullif(current_setting('cv.d_nov_pend', true),''),'0')::numeric = 0
              then 'SIN PROBAR · ya no hay solicitudes pendientes de noviembre'
              else coalesce(nullif(current_setting('cv.d_tomados', true),''),'SIN FILA')
                   || ', pendientes: ' || coalesce(current_setting('cv.d_nov_pend', true),'?') end,
         nullif(current_setting('cv.d_tomados', true),'')::numeric = 7
           and coalesce(nullif(current_setting('cv.d_nov_pend', true),''),'0')::numeric <> 0
  union all
  -- ⚠️ LA FILA QUE SE CORRIGIO. El esperado AHORA SE DERIVA del estado de antes
  -- de la carga, capturado dentro de esta misma transaccion: hoy son 2
  -- solicitudes y 1 pendiente (Lorena ya rechazo la otra), y eso es exactamente
  -- lo que tiene que seguir siendo despues. Si la carga tocara cualquiera de los
  -- dos numeros, esperado y obtenido se separan y la fila FALLA.
  select 12, 'las solicitudes de noviembre quedaron INTACTAS (total / pendientes)',
         coalesce(nullif(current_setting('cv.a_nov', true),''),'?') || ' / '
           || coalesce(nullif(current_setting('cv.a_nov_pend', true),''),'?'),
         coalesce(nullif(current_setting('cv.d_nov', true),''),'?') || ' / '
           || coalesce(nullif(current_setting('cv.d_nov_pend', true),''),'?'),
         nullif(current_setting('cv.d_nov', true),'')::numeric
             = nullif(current_setting('cv.a_nov', true),'')::numeric
           and nullif(current_setting('cv.d_nov_pend', true),'')::numeric
             = nullif(current_setting('cv.a_nov_pend', true),'')::numeric
  ) t
 order by t.orden;

rollback;

-- ── DESPUES DEL ROLLBACK ────────────────────────────────────────────────
-- No tiene que quedar nada:
--   select count(*) from rrhh_evento
--    where motivo = 'Carga histórica: vacaciones tomadas antes de usar Truefie';  -- 0
--
-- Si el guardia 1 aborto, estos son los dias que chocan con un feriado:
--   select d.dia, f.descripcion, f.tipo from (values ('2026-03-20'::date),
--     ('2026-04-24'),('2026-06-22'),('2026-06-23'),('2026-06-24'),('2026-06-25'),
--     ('2026-06-26')) d(dia)
--   join rrhh_feriado f
--     on daterange(f.fecha, coalesce(f.fecha_fin, f.fecha), '[]') @> d.dia;
