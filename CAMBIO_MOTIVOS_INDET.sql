-- ════════════════════════════════════════════════════════════════════════
-- CAMBIO_MOTIVOS_INDET.sql · 15-sep-2026
-- "No sé de qué lote salió": la pantalla pasa a ofrecer TRES motivos y uno de
-- ellos es 'otro' + nota. La BASE tiene que aceptar 'otro' — hoy no lo acepta y
-- la columna de la nota no existe.
--
-- ⚠️ NO SE PEGA POR PARTES. Cada seccion es una unidad — el orden importa:
-- la columna (§A) antes del CHECK que la nombra, y antes de las vistas (§D)
-- que la leen.
--
-- ⚠️ ESTA VERSION DE LA APP (b59) NO SE PUEDE PUBLICAR ANTES DE PEGAR ESTO.
-- La pantalla ya ofrece "Otro" — sin el CHECK nuevo, elegirlo hace que el INSERT
-- del despacho falle ENTERO — no la linea, el despacho. Es el incidente del
-- 17-ago (codigo publicado que dependia de un .sql sin pegar), y esta escrito
-- aca para que no haya que acordarse.
--
-- LO QUE **NO** CAMBIA, y es deliberado:
--   Los CUATRO valores viejos siguen siendo validos. 'chofer_no_reporto' ESTA EN
--   USO: la correccion #1 del 8-sep, sobre ent_alisto_lote 184 (la entrega de
--   Automercado). Sacarlo del CHECK dejaria esa fila invalida. Que la pantalla
--   deje de ofrecer un valor no es lo mismo que que la base deje de aceptarlo:
--   un dato ya escrito no se desescribe cambiando la regla.
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- ANTES · MEDIR. Solo lectura. Correr y GUARDAR la salida.
-- Los numeros entre [] son los medidos el 15-sep 19:2x — si no dan, PARAR.
-- ════════════════════════════════════════════════════════════════════════

-- A1 · filas centinela por motivo          [no_se_anoto: 2 (ids 235, 236)]
select coalesce(motivo_indeterminado,'(NULL)') as motivo, count(*) as filas,
       min(id) as id_min, max(id) as id_max
  from ent_alisto_lote where lote = 'NO DETERMINADO'
 group by 1 order by 2 desc, 1;

-- A2 · los motivos EN USO en las tres tablas que los nombran
--      [alisto_lote: no_se_anoto 2]
--      [correccion : no_se_anoto 4 · chofer_no_reporto 1 · sticker_caido 1]
--      [conteo_linea: ninguno]
select 'ent_alisto_lote' as tabla, motivo_indeterminado as motivo, count(*) as filas
  from ent_alisto_lote where motivo_indeterminado is not null group by 1,2
union all
select 'ent_conteo_linea', motivo_indeterminado, count(*)
  from ent_conteo_linea where motivo_indeterminado is not null group by 1,2
union all
select 'ent_alisto_lote_correccion', motivo, count(*)
  from ent_alisto_lote_correccion where motivo is not null group by 1,2
order by 1,2;

-- A3 · la fila que obliga a NO tocar la lista de valores          [1 fila]
--      184 lleva 'sin lote' en crudo — el motivo vive en su correccion.
select c.id as correccion, c.alisto_lote_id, l.lote as lote_crudo,
       c.lote as lote_corregido, c.motivo, left(c.nota, 60) as nota
  from ent_alisto_lote_correccion c
  join ent_alisto_lote l on l.id = c.alisto_lote_id
 where c.motivo = 'chofer_no_reporto';

-- A4 · 7e · salidas desde el ancla, por producto
--      [451:150/2 · 452:60/1 · 453:432/2 · 472:48/1 · 503:174/1 · 519:38/1]
select producto_id, sum(uds) as uds, count(*) as filas
  from ent_salido_del_congelador_desde_ancla group by 1 order by 1;

-- A5 · 7e · total                                       [902 uds · 8 filas]
select sum(uds) as uds_total, count(*) as filas_total
  from ent_salido_del_congelador_desde_ancla;

-- A6 · el CHECK de hoy, textual (para comparar con el de despues)
select pg_get_constraintdef(oid) as def_antes
  from pg_constraint where conname = 'ent_alisto_lote_motivo_ok';


-- ════════════════════════════════════════════════════════════════════════
-- P0 · LAS DOS QUE TIENEN QUE FALLAR **ANTES** DE APLICAR
-- Si alguna pasa, el diagnostico esta mal y NO se aplica nada.
-- Las dos CREAN su fila: una prueba que no encuentra a quien probar no prueba
-- nada y dice "Success" (la 7a del 14-sep).
-- ════════════════════════════════════════════════════════════════════════

-- P0-a · ESPERADO: ERROR de ent_alisto_lote_motivo_ok. 'otro' todavia no existe.
begin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden,
         motivo_indeterminado, indeterminado_por, indeterminado_en)
  select (select id from ent_alisto_linea order by id desc limit 1),
         'NO DETERMINADO', 1, 0, 'otro', 'prueba-p0a', now();
rollback;

-- P0-b · ⚠️ ESPERADO: **PASA**, y no deberia. Es el hueco del NULL: el CHECK
--        dice `lote <> '...' OR (motivo = ANY(...) AND ...)`, y con motivo NULL
--        el ANY da NULL, el OR da NULL, y un CHECK NULL se considera cumplido.
--        Es el MISMO hueco que el 15-sep se cerro en ent_alisto_linea. Si esta
--        PASA, queda demostrado que hoy se puede escribir un centinela mudo.
begin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden,
         motivo_indeterminado, indeterminado_por, indeterminado_en)
  select (select id from ent_alisto_linea order by id desc limit 1),
         'NO DETERMINADO', 1, 0, null, 'prueba-p0b', now();
  -- si llego aca sin error, el hueco esta abierto
  select 'HUECO ABIERTO: el centinela sin motivo entro' as resultado;
rollback;


-- ════════════════════════════════════════════════════════════════════════
-- §A · ent_alisto_lote — la columna de la nota y el CHECK nuevo
-- ════════════════════════════════════════════════════════════════════════
begin;

-- A.1 · la columna. Nullable: solo 'otro' la usa.
alter table ent_alisto_lote
  add column if not exists nota_indeterminado text;

comment on column ent_alisto_lote.nota_indeterminado is
  'Que paso, cuando motivo_indeterminado = ''otro''. Minimo 6 caracteres al '
  'recortar, lo exige ent_alisto_lote_motivo_ok. Null en los demas motivos.';

-- A.2 · el CHECK. Copiado de pg_get_constraintdef y cambiado en TRES cosas:
--   1. entra 'otro' a la lista. Los cuatro viejos NO se tocan (ver A3).
--   2. nota obligatoria, >= 6 al recortar, cuando el motivo es 'otro'.
--      Mismo numero y misma forma que ent_alisto_linea_no_entrega_ok: dos
--      minimos distintos para el mismo tipo de campo es una segunda regla que
--      se desincroniza. El 6 se calibro el 15-sep contra un caso real
--      ("consigna", 8 caracteres, que con el minimo de 10 no pasaba).
--   3. COALESCE(..., false) — se cierra el hueco de P0-b. Un CHECK se cumple
--      cuando la expresion es TRUE **o NULL**, asi que sin el coalesce un
--      motivo NULL entraba. Misma correccion que se aplico a
--      ent_alisto_linea_no_entrega_ok el 15-sep, por decision de Andrea.
alter table ent_alisto_lote drop constraint ent_alisto_lote_motivo_ok;

alter table ent_alisto_lote add constraint ent_alisto_lote_motivo_ok check (
  lote <> 'NO DETERMINADO'
  or (
        coalesce(motivo_indeterminado in (
          -- los dos que la pantalla ofrece
          'no_se_anoto', 'sticker_caido',
          -- el nuevo
          'otro',
          -- los dos que salieron de la pantalla y SIGUEN VALIDOS en la base
          'caja_sin_sticker', 'chofer_no_reporto'
        ), false)
    and ( motivo_indeterminado <> 'otro'
          or ( nota_indeterminado is not null
               and length(btrim(nota_indeterminado)) >= 6 ) )
    and indeterminado_por is not null
    and length(btrim(indeterminado_por)) > 0
    and indeterminado_en is not null
  )
);

commit;


-- ════════════════════════════════════════════════════════════════════════
-- §B · ent_alisto_lote_correccion — 'otro' tambien aca
--
-- POR QUE. Una correccion tiene que poder decir lo mismo que la fila que
-- corrige. Sin esto, una fila escrita hoy con motivo 'otro' no se va a poder
-- corregir manana: el CHECK de la correccion la rechaza. Es un candado que se
-- descubre el dia que hace falta abrirlo.
-- La tabla YA tiene columna `nota` (las seis correcciones del 8-sep la usan,
-- 179-192 caracteres cada una), asi que solo se le pide lo mismo que a §A.
-- ════════════════════════════════════════════════════════════════════════
begin;

alter table ent_alisto_lote_correccion drop constraint correccion_motivo_ok;

alter table ent_alisto_lote_correccion add constraint correccion_motivo_ok check (
  lote <> 'NO DETERMINADO'
  or (
        coalesce(motivo in (
          'no_se_anoto', 'sticker_caido', 'otro',
          'caja_sin_sticker', 'chofer_no_reporto'
        ), false)
    and ( motivo <> 'otro'
          or ( nota is not null and length(btrim(nota)) >= 6 ) )
  )
);

commit;


-- ════════════════════════════════════════════════════════════════════════
-- §C · ent_conteo_linea — NO SE TOCA, y se deja escrito por que
--
-- `ent_conteo_linea_motivo_ok` nombra la misma lista de cuatro, pero:
--   · tiene CERO filas con motivo (medido en A2), y
--   · la app NUNCA le escribe motivo_indeterminado: las dos unicas escrituras
--     del motivo en index.html van a ent_alisto_lote (despConfirmar y rpGuardar).
-- Agregarle 'otro' seria cambiar una regla que nadie ejerce, y quitarle los dos
-- que salen de la pantalla no tendria efecto ninguno. Queda como esta.
-- Si algun dia el Conteo ofrece el centinela con motivo, ESE es el momento de
-- alinear las tres listas — y entonces conviene una sola fuente, no tres copias.
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- §D · LAS DOS VISTAS — que la nota LLEGUE a la cola de las socias
--
-- POR QUE ENTRA EN EL MISMO PEGADO (decision de Andrea, 15-sep). Sin esto se
-- podria escribir "Otro — se mojo la caja" y la socia que tiene que resolverlo
-- veria 'otro' pelado. Publicar un campo que nadie puede leer no sirve de nada.
--
-- ES CHICO, Y ESTA MEDIDO: dos `create or replace`, y las dos SOLO AGREGAN UNA
-- COLUMNA AL FINAL. Postgres permite eso aunque la vista tenga dependientes —
-- lo que prohibe es quitar, renombrar o cambiar el tipo de una columna que ya
-- existe. `ent_alisto_lote_efectivo` tiene TRES dependientes
-- (ent_salido_del_congelador_desde_ancla, v_ent_excepcion_pendiente,
-- v_ent_indeterminado_pendiente) y ninguno se toca: ninguno se rompe.
-- No hay `drop view` en ninguna parte de esta seccion. Si hiciera falta uno,
-- seria otra conversacion.
--
-- EL CUERPO ES COPIA LITERAL de pg_get_viewdef. Lo unico agregado va marcado
-- con "NUEVO" al lado.
-- ════════════════════════════════════════════════════════════════════════
begin;

-- D.1 · ent_alisto_lote_efectivo
--   La nota sigue la MISMA regla que el lote, el motivo y el quien: si hay
--   correccion, manda la correccion. Es el `coalesce(c.X, al.X)` que la vista ya
--   usa tres veces — no se inventa una cuarta regla para el cuarto campo.
--
--   ⚠️ CONSECUENCIA MEDIBLE, dicha antes de pegar: las SEIS correcciones del
--   8-sep tienen nota (179-192 caracteres, "Migracion b56: ...") y motivos que
--   NO son 'otro'. Con este coalesce esas seis filas van a mostrar su nota de
--   migracion al lado de un motivo que no es 'otro'. Es correcto —es la nota
--   efectiva de esa fila— y es MAS de lo que se ve hoy, que es el motivo pelado.
--   D10 las lista para que se vea exactamente cuales son.
create or replace view ent_alisto_lote_efectivo as
 SELECT al.id,
    al.linea_id,
    al.cant_uds,
    al.orden,
    COALESCE(c.lote, al.lote) AS lote,
    al.lote AS lote_original,
    COALESCE(c.motivo, al.motivo_indeterminado) AS motivo_indeterminado,
    COALESCE(c.creado_por, al.indeterminado_por) AS excepcion_por,
    c.fuente AS resuelto_con,
    c.id IS NOT NULL AS corregido,
    COALESCE(c.nota, al.nota_indeterminado) AS nota_indeterminado   -- NUEVO, al final
   FROM ent_alisto_lote al
     LEFT JOIN LATERAL ( SELECT x.id,
            x.lote,
            x.motivo,
            x.fuente,
            x.creado_por,
            x.nota                                                  -- NUEVO
           FROM ent_alisto_lote_correccion x
          WHERE x.alisto_lote_id = al.id
          ORDER BY x.creado_en DESC
         LIMIT 1) c ON true;

-- D.2 · v_ent_indeterminado_pendiente — la cola que miran las socias
create or replace view v_ent_indeterminado_pendiente as
 SELECT p.id AS pedido_id,
    p.origen,
    p.cliente_nombre,
    COALESCE(fv.factura_nombre, p.factura_nombre) AS factura_nombre,
    ali.producto_id,
    ale.cant_uds,
    ale.motivo_indeterminado,
    ale.excepcion_por,
    av.preparado_en,
    ale.id AS alisto_lote_id,
    ale.nota_indeterminado                                          -- NUEVO, al final
   FROM ent_alisto_lote_efectivo ale
     JOIN ent_alisto_linea ali ON ali.id = ale.linea_id
     JOIN ent_alisto_vigente av ON av.alisto_id = ali.alisto_id
     JOIN ent_pedido p ON p.id = av.pedido_id
     LEFT JOIN ent_pedido_factura_vigente fv ON fv.pedido_id = p.id AND fv.anulado = false
  WHERE ale.lote = 'NO DETERMINADO'::text;

commit;


-- ════════════════════════════════════════════════════════════════════════
-- PRUEBAS · todas CREAN la fila que van a probar, y todas terminan en rollback.
-- Correr DESPUES de §A y §B. Cada una dice que tiene que pasar.
-- ════════════════════════════════════════════════════════════════════════

-- T1 · 'otro' con nota de 6 → ESPERADO: PASA (Success, 1 fila)
begin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden,
         motivo_indeterminado, nota_indeterminado, indeterminado_por, indeterminado_en)
  select (select id from ent_alisto_linea order by id desc limit 1),
         'NO DETERMINADO', 1, 0, 'otro', 'mojado', 'prueba-t1', now();
  select 'T1 OK: otro con nota de 6 entro' as resultado;
rollback;

-- T2 · 'otro' con nota de 5 → ESPERADO: ERROR
begin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden,
         motivo_indeterminado, nota_indeterminado, indeterminado_por, indeterminado_en)
  select (select id from ent_alisto_linea order by id desc limit 1),
         'NO DETERMINADO', 1, 0, 'otro', 'corta', 'prueba-t2', now();
rollback;

-- T3 · 'otro' SIN nota → ESPERADO: ERROR
begin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden,
         motivo_indeterminado, indeterminado_por, indeterminado_en)
  select (select id from ent_alisto_linea order by id desc limit 1),
         'NO DETERMINADO', 1, 0, 'otro', 'prueba-t3', now();
rollback;

-- T4 · 'otro' con nota de espacios y 6 letras → ESPERADO: PASA
--      El minimo se mide al RECORTAR: "  mojado  " son 6, no 10.
begin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden,
         motivo_indeterminado, nota_indeterminado, indeterminado_por, indeterminado_en)
  select (select id from ent_alisto_linea order by id desc limit 1),
         'NO DETERMINADO', 1, 0, 'otro', '  mojado  ', 'prueba-t4', now();
  select 'T4 OK: se mide al recortar' as resultado;
rollback;

-- T5 · nota de 6 espacios → ESPERADO: ERROR (btrim la deja en 0)
begin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden,
         motivo_indeterminado, nota_indeterminado, indeterminado_por, indeterminado_en)
  select (select id from ent_alisto_linea order by id desc limit 1),
         'NO DETERMINADO', 1, 0, 'otro', '      ', 'prueba-t5', now();
rollback;

-- T6 · EL HUECO CERRADO: motivo NULL → ESPERADO: ERROR
--      Esta es P0-b otra vez. Antes de §A pasaba — ahora tiene que reventar.
begin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden,
         motivo_indeterminado, indeterminado_por, indeterminado_en)
  select (select id from ent_alisto_linea order by id desc limit 1),
         'NO DETERMINADO', 1, 0, null, 'prueba-t6', now();
rollback;

-- T7 · LOS VIEJOS SIGUEN VALIDOS: 'chofer_no_reporto' → ESPERADO: PASA
--      Si esta falla, la fila 184 quedo huerfana y hay que revertir §A.
begin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden,
         motivo_indeterminado, indeterminado_por, indeterminado_en)
  select (select id from ent_alisto_linea order by id desc limit 1),
         'NO DETERMINADO', 1, 0, 'chofer_no_reporto', 'prueba-t7', now();
  select 'T7 OK: los cuatro viejos siguen entrando' as resultado;
rollback;

-- T8 · 'caja_sin_sticker' → ESPERADO: PASA (el otro que sale de la pantalla)
begin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden,
         motivo_indeterminado, indeterminado_por, indeterminado_en)
  select (select id from ent_alisto_linea order by id desc limit 1),
         'NO DETERMINADO', 1, 0, 'caja_sin_sticker', 'prueba-t8', now();
  select 'T8 OK' as resultado;
rollback;

-- T9 · un motivo inventado → ESPERADO: ERROR
begin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden,
         motivo_indeterminado, indeterminado_por, indeterminado_en)
  select (select id from ent_alisto_linea order by id desc limit 1),
         'NO DETERMINADO', 1, 0, 'se_perdio', 'prueba-t9', now();
rollback;

-- T10 · §B · una correccion con 'otro' y nota de 6 → ESPERADO: PASA
begin;
  insert into ent_alisto_lote_correccion (alisto_lote_id, lote, motivo, nota, creado_por)
  select (select id from ent_alisto_lote order by id desc limit 1),
         'NO DETERMINADO', 'otro', 'mojado', 'prueba-t10';
  select 'T10 OK' as resultado;
rollback;

-- T11 · §B · una correccion con 'otro' sin nota → ESPERADO: ERROR
begin;
  insert into ent_alisto_lote_correccion (alisto_lote_id, lote, motivo, creado_por)
  select (select id from ent_alisto_lote order by id desc limit 1),
         'NO DETERMINADO', 'otro', 'prueba-t11';
rollback;

-- T12 · §B · las seis correcciones del 8-sep siguen validas
--       ESPERADO: 0 filas. Revalida el CHECK nuevo contra los datos reales.
select c.id, c.motivo, length(btrim(coalesce(c.nota,''))) as largo_nota
  from ent_alisto_lote_correccion c
 where not (
   c.lote <> 'NO DETERMINADO'
   or ( coalesce(c.motivo in ('no_se_anoto','sticker_caido','otro',
                              'caja_sin_sticker','chofer_no_reporto'), false)
        and ( c.motivo <> 'otro'
              or (c.nota is not null and length(btrim(c.nota)) >= 6) ) ) );


-- ════════════════════════════════════════════════════════════════════════
-- DESPUES · VERIFICAR. Solo lectura. Comparar contra el ANTES.
-- ════════════════════════════════════════════════════════════════════════

-- D1 · la columna existe y es nullable            [nota_indeterminado · text · YES]
select column_name, data_type, is_nullable
  from information_schema.columns
 where table_name = 'ent_alisto_lote' and column_name = 'nota_indeterminado';

-- D2 · el CHECK nuevo, textual. Tiene que nombrar los CINCO valores,
--      el coalesce y el minimo de 6.
select pg_get_constraintdef(oid) as def_despues
  from pg_constraint where conname = 'ent_alisto_lote_motivo_ok';

-- D3 · los cinco valores, uno por uno, leidos del CHECK real
--      ESPERADO, exactamente 5 filas:
--        caja_sin_sticker · chofer_no_reporto · no_se_anoto · otro · sticker_caido
--      (Postgres reescribe el `in (...)` como `= ANY (ARRAY[...])`, asi que el
--       texto del CHECK no va a verse igual al que se pego. Eso es normal: lo
--       que importa son los valores, y por eso se leen asi y no a ojo.)
--      'NO DETERMINADO' no aparece porque lleva mayusculas y espacio.
--      ⚠️ Una primera version de esta consulta cortaba por parentesis y devolvia
--      "ARRAY['sticker_caido" y "no_se_anoto']". Ensayada el 15-sep contra el
--      CHECK viejo: esta devuelve los cuatro limpios.
with d as (select pg_get_constraintdef(oid) t
             from pg_constraint where conname = 'ent_alisto_lote_motivo_ok')
select distinct m[1] as valor
  from d, regexp_matches(t, '''([a-z_]+)''', 'g') m
 order by 1;

-- D4 · NADA SE MOVIO · filas centinela por motivo    [no_se_anoto: 2, ids 235-236]
select coalesce(motivo_indeterminado,'(NULL)') as motivo, count(*) as filas,
       min(id) as id_min, max(id) as id_max
  from ent_alisto_lote where lote = 'NO DETERMINADO'
 group by 1 order by 2 desc, 1;

-- D5 · NADA SE MOVIO · 7e por producto
--      [451:150/2 · 452:60/1 · 453:432/2 · 472:48/1 · 503:174/1 · 519:38/1]
select producto_id, sum(uds) as uds, count(*) as filas
  from ent_salido_del_congelador_desde_ancla group by 1 order by 1;

-- D6 · NADA SE MOVIO · 7e total                         [902 uds · 8 filas]
select sum(uds) as uds_total, count(*) as filas_total
  from ent_salido_del_congelador_desde_ancla;

-- D7 · la correccion #1 sigue entera                              [1 fila]
select c.id, c.alisto_lote_id, c.motivo, length(c.nota) as largo_nota
  from ent_alisto_lote_correccion c where c.motivo = 'chofer_no_reporto';

-- D8 · ninguna fila existente viola el CHECK nuevo        [ESPERADO: 0 filas]
--      ⚠️ Esta SOLO corre despues de §A: nombra nota_indeterminado, que hasta
--      entonces no existe. Si se corre antes da 42703 y eso no es una falla,
--      es la prueba de que la columna todavia no esta.
select id, lote, motivo_indeterminado, nota_indeterminado
  from ent_alisto_lote
 where not (
   lote <> 'NO DETERMINADO'
   or ( coalesce(motivo_indeterminado in ('no_se_anoto','sticker_caido','otro',
                                          'caja_sin_sticker','chofer_no_reporto'), false)
        and ( motivo_indeterminado <> 'otro'
              or (nota_indeterminado is not null
                  and length(btrim(nota_indeterminado)) >= 6) )
        and indeterminado_por is not null
        and length(btrim(indeterminado_por)) > 0
        and indeterminado_en is not null ) );


-- D9 · §D · las dos vistas exponen la nota, y AL FINAL
--      ESPERADO: ent_alisto_lote_efectivo -> posicion 11
--                v_ent_indeterminado_pendiente -> posicion 11
select table_name, column_name, ordinal_position
  from information_schema.columns
 where column_name = 'nota_indeterminado'
   and table_name in ('ent_alisto_lote_efectivo','v_ent_indeterminado_pendiente')
 order by 1;

-- D10 · §D · que ve la socia AHORA en la cola          [ESPERADO: 6 filas]
--       Las seis del 8-sep, cada una con su nota de migracion. Antes de §D esta
--       consulta no se podia ni escribir.
select alisto_lote_id, producto_id, cant_uds, motivo_indeterminado,
       left(coalesce(nota_indeterminado,'(sin nota)'), 50) as nota
  from v_ent_indeterminado_pendiente
 order by alisto_lote_id;

-- D11 · §D · los tres dependientes siguen vivos y contestando
--       ESPERADO: 7e = 902 uds / 8 filas (igual que A5 y D6), y las otras dos
--       sin error. Una vista que se rompe al recrear su base no avisa sola.
select (select count(*) from ent_salido_del_congelador_desde_ancla) as filas_7e,
       (select sum(uds) from ent_salido_del_congelador_desde_ancla) as uds_7e,
       (select count(*) from v_ent_excepcion_pendiente)             as filas_excepcion,
       (select count(*) from v_ent_indeterminado_pendiente)         as filas_cola;

-- ════════════════════════════════════════════════════════════════════════
-- ⚠️ NO SE PEGA · TRES COSAS QUE APARECIERON MIDIENDO, PARA DECIDIR APARTE
--
-- 1. UN LOTE NORMAL PUEDE LLEVAR COLUMNAS DE CENTINELA. El CHECK arranca con
--    `lote <> 'NO DETERMINADO' or (...)`: si el lote es normal, el OR ya es
--    verdadero y nadie mira las otras columnas. Hoy no hay ninguna fila asi
--    (medido: 0), y la app nunca las escribe, pero la puerta esta abierta.
--    El hermano ent_alisto_linea_no_entrega_ok NO la tiene abierta: usa un CASE
--    con ELSE que obliga a que todo sea NULL. Una linea lo cerraria:
--      and (lote = 'NO DETERMINADO' or (motivo_indeterminado is null
--           and nota_indeterminado is null and indeterminado_por is null
--           and indeterminado_en is null))
--
-- 2. LA NOTA NO ESTA PROHIBIDA EN LOS OTROS MOTIVOS. §A la EXIGE en 'otro' y no
--    dice nada de los demas, igual que el hermano. Prohibirla seria una linea:
--      and (motivo_indeterminado = 'otro' or nota_indeterminado is null)
--    No se incluyo para no divergir del hermano sin que Andrea lo decida.
--
-- (El tercer punto que estaba aca —la nota que no llegaba a la cola de las
--  socias— dejo de ser pendiente: se midio, resulto chico y entro como §D.)
-- ════════════════════════════════════════════════════════════════════════
