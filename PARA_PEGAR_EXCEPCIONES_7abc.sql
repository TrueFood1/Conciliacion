-- ════════════════════════════════════════════════════════════════════════
-- PARA PEGAR · 7a / 7b / 7c · UNA POR UNA, Y LAS SEIS TIENEN QUE DAR ERROR
-- ════════════════════════════════════════════════════════════════════════
-- Preparado el 13-sep-2026. CORRIDO Y CORREGIDO el 14-sep-2026.
--
-- ⚠️ UNA POR UNA. Estas pruebas terminan en error A PROPOSITO, y en el SQL editor
-- un error aborta el resto del lote. Pegadas juntas, la primera mata a las demas
-- y parece que "paso todo". Van de a una, se lee el error, y se pasa a la siguiente.
--
-- ⚠️ EL ERROR ES EL RESULTADO BUENO. Si alguna PASA en vez de fallar, el candado
-- que esa prueba mide NO esta puesto: PARAR y avisar.
--
-- Las seis van envueltas en begin/rollback: no dejan nada escrito.
--
-- ════════════════════════════════════════════════════════════════════════
-- POR QUE ESTE ARCHIVO CAMBIO EL 14-SEP — LEER ANTES DE "MEJORARLO" DE VUELTA
-- ════════════════════════════════════════════════════════════════════════
-- La version del 13-sep tenia CINCO pruebas que no probaban nada, y una que si.
-- El defecto no se veia: las cinco devolvian "Success. No rows returned", que es
-- indistinguible de un candado ausente Y de un candado presente. Un test que da
-- lo mismo en los dos mundos no mide: tranquiliza.
--
-- LA CAUSA, MEDIDA EL 14-SEP CON pg_lector:
--   ent_alisto_linea            199 filas
--   lineas SIN lotes colgando     0   <-- de aca salia todo
--   ent_alisto_lote             231 filas
--
-- 7a y las cuatro esquinas de 7c buscaban "una linea sin lotes" con
--   where not exists (select 1 from ent_alisto_lote al where al.linea_id = l.id)
-- y esa subconsulta devuelve NULL. `where id = NULL` no matchea nunca, asi que el
-- update tocaba 0 filas, el insert seleccionaba 0 filas, y el trigger —que es
-- BEFORE INSERT FOR EACH ROW— nunca se disparaba. Sin fila, no hay trigger.
--
-- Y no es una casualidad de este martes: la app inserta la linea y sus lotes en el
-- mismo acto, asi que una linea sin lotes no existe en la operacion normal. Las
-- cinco pruebas no podian ejercer nunca.
--
-- 7c-1 tenia ademas un defecto peor: era
--   begin; update ent_alisto_linea set no_se_entrega = true where id = <una sin lotes>; rollback;
-- con `<una sin lotes>` literal, sin rellenar. No es SQL: pegada da error de
-- sintaxis, no la violacion del CHECK. Y venia asi del original
-- (ENTREGAS_EXCEPCIONES_LINEA.sql linea 529), que ya era una plantilla en prosa.
--
-- EL ARREGLO: las cinco CREAN la fila de prueba en vez de buscarla, dentro del
-- mismo begin/rollback. No hay trigger de INSERT sobre ent_alisto_linea
-- (ent_alisto_linea_marca_trg es BEFORE UPDATE), asi que en las de 7c el CHECK
-- queda aislado y el error que sale es del CHECK y de nada mas.
--
-- 7b NO SE TOCO: era la unica sana. Apunta a la linea del lote mas reciente, que
-- por definicion tiene lotes. Medido el 14-sep: resolvia a la linea 199 y el
-- update tocaba 1 fila, o sea que el trigger si se disparaba.
--
-- ════════════════════════════════════════════════════════════════════════
-- CORRIDAS EL 14-SEP-2026 · LAS SEIS DIERON EL ERROR ESPERADO
-- ════════════════════════════════════════════════════════════════════════
--   7a-bis    · ERROR 'la linea N esta marcada "no se entrega": no puede llevar lote'
--   7b        · ERROR 'la linea N ya tiene lotes registrados'
--   7c-1-bis  · ERROR violates check constraint "ent_alisto_linea_no_entrega_ok"
--   7c-2-bis  · idem
--   7c-3-bis  · idem
--   7c-4-bis  · idem
--
-- Verificado despues de las seis (solo lectura, 18:09 CR = 00:09 UTC del 15-sep):
--   ent_alisto_linea            199 filas · 0 marcadas · 0 firmas 'prueba%'
--   ent_alisto_lote             231 filas · 0 con lote '001 / 1-27'
--   ent_alisto_linea_autorizacion 0 filas
--   ent_conteo_linea            132 filas · huella 217ac7e8da95ca930c95274fe26acb46
--   7e                          8 filas · suma 423.500 · md5 44dc89ae9bf7bd996291f518062ae990
--                               (identico al 7e-ANTES de las 17:30 CR)
-- Los seis rollback deshicieron todo.
--
-- ════════════════════════════════════════════════════════════════════════
-- 🔴 PENDIENTE SIN RESOLVER · UN HUECO EN ent_alisto_linea_no_entrega_ok
-- ════════════════════════════════════════════════════════════════════════
-- En Postgres un CHECK se satisface si la expresion da TRUE *o NULL*. Con
--   no_se_entrega = true, motivo_no_entrega = NULL, pero firma y hora PUESTAS
-- el termino `motivo_no_entrega in ('agotado','otro')` da NULL, el resto da TRUE,
-- y la conjuncion entera queda en NULL — o sea que la fila ENTRA.
--
-- Medido el 14-sep evaluando la expresion exacta del CHECK con un select (sin
-- escribir nada). Los seis casos:
--   marcada y pelada .................... false  -> rechaza ✓
--   marcada SIN motivo, con firma y hora .. NULL  -> ACEPTA  ⚠
--   motivo 'otro' sin nota .............. false  -> rechaza ✓
--   marcada con cant_uds = 1 ............ false  -> rechaza ✓
--   sin marcar pero con motivo .......... false  -> rechaza ✓
--   control · marcada bien formada ...... true   -> pasa, como debe
--
-- 7c-1-bis NO lo cubre a proposito: su fila va pelada, y ahi
-- `no_entrega_por is not null` da FALSE y hunde la expresion. El hueco aparece
-- solo cuando firma y hora vienen puestas y el motivo no.
--
-- Esto contradice el comentario del §1 —«Sin motivo no se guarda» es candado del
-- motor, no validacion de pantalla— para ese caso puntual.
--
-- NO ES URGENTE: la app manda el motivo siempre, y al 14-sep hay 0 filas marcadas
-- en toda la tabla. Arreglarlo es cambiar el CHECK (p.ej. envolver el termino en
-- `coalesce(motivo_no_entrega in ('agotado','otro'), false)`), o sea otro pegado,
-- y lo decide Andrea. NO se agrega como septima prueba porque hoy PASARIA: seria
-- un test en rojo sobre algo que todavia no esta arreglado.
--
-- ════════════════════════════════════════════════════════════════════════
-- PROCEDENCIA, para que la proxima sesion sepa que es literal y que no:
--   7b es COPIA LITERAL de ENTREGAS_EXCEPCIONES_LINEA.sql (lineas 517-521),
--   solo descomentada. Es lo unico que sobrevive textual del original.
--   7a-bis y las cuatro 7c-*-bis se escribieron el 14-sep y se CORRIERON; su
--   esperado esta medido, no supuesto.
--
-- ANTES DE ESTO: haber corrido 7e-ANTES, pegado PARA_PEGAR_EXCEPCIONES_1a6.sql,
-- y 7e-DESPUES (identico al ANTES).
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- 7a-bis · EL EXCLUYENTE, SENTIDO (a) · CREA la linea de prueba, no la busca
-- ESPERADO: ERROR 'la linea N esta marcada "no se entrega": no puede llevar lote'
-- Si el segundo INSERT pasa, el trigger no ejerce: PARAR.
-- El primer INSERT SI tiene que pasar: es el que arma la trampa.
-- ════════════════════════════════════════════════════════════════════════
   begin;
     -- 1) una linea de prueba, YA marcada y sin lotes. Nace marcada en vez de
     --    marcarse despues: ent_alisto_linea_marca_trg es BEFORE UPDATE y no
     --    aplica a un insert. cant_uds = 0 y cant_uom = 0 los exige el CHECK.
     insert into ent_alisto_linea
            (alisto_id, producto_id, cant_uds, cant_uom,
             no_se_entrega, motivo_no_entrega, no_entrega_por, no_entrega_en)
     values ((select id from ent_alisto where not anulado order by id desc limit 1),
             451, 0, 0,
             true, 'agotado', 'prueba-7a', now());

     -- 2) y se le intenta colgar un lote. ACA TIENE QUE REVENTAR.
     --    Filtra por la firma de prueba y no por `where l.no_se_entrega`, para
     --    no agarrar una marca real el dia que exista alguna.
     insert into ent_alisto_lote (linea_id, lote, cant_uds, orden)
     select l.id, '001 / 1-27', 1, 0
       from ent_alisto_linea l
      where l.no_entrega_por = 'prueba-7a'
      order by l.id desc limit 1;
   rollback;


-- ════════════════════════════════════════════════════════════════════════
-- 7b · EL EXCLUYENTE, SENTIDO (b) · una linea con lotes no se puede marcar
-- ESPERADO: ERROR 'la linea N ya tiene lotes registrados'
-- ════════════════════════════════════════════════════════════════════════
   begin;
     update ent_alisto_linea set no_se_entrega = true, motivo_no_entrega = 'agotado',
            no_entrega_por = 'prueba', no_entrega_en = now(), cant_uds = 0, cant_uom = 0
      where id = (select al.linea_id from ent_alisto_lote al order by al.id desc limit 1);
   rollback;


-- ════════════════════════════════════════════════════════════════════════
-- 7c · EL CHECK DE §1, LAS CUATRO ESQUINAS · las cuatro CREAN la fila
-- Las cuatro ESPERAN: ERROR 'violates check constraint "ent_alisto_linea_no_entrega_ok"'
-- Cada una sola, cada una en su begin/rollback.
-- ════════════════════════════════════════════════════════════════════════

-- ── 7c-1-bis · marcada y PELADA (sin motivo, sin firma, sin hora) ───────
   begin;
     insert into ent_alisto_linea (alisto_id, producto_id, cant_uds, cant_uom, no_se_entrega)
     values ((select id from ent_alisto where not anulado order by id desc limit 1),
             451, 0, 0, true);
   rollback;


-- ── 7c-2-bis · motivo 'otro' SIN nota ──────────────────────────────────
-- El CHECK exige: motivo <> 'otro'  OR  (nota is not null and length(btrim(nota)) >= 10)
   begin;
     insert into ent_alisto_linea
            (alisto_id, producto_id, cant_uds, cant_uom,
             no_se_entrega, motivo_no_entrega, nota_no_entrega, no_entrega_por, no_entrega_en)
     values ((select id from ent_alisto where not anulado order by id desc limit 1),
             451, 0, 0, true, 'otro', null, 'prueba-7c2', now());
   rollback;


-- ── 7c-3-bis · marcada pero con cant_uds > 0 ───────────────────────────
-- Es la condicion que hace VERDAD "no mueve ningun saldo": cant_uds = 0 and coalesce(cant_uom,0) = 0
   begin;
     insert into ent_alisto_linea
            (alisto_id, producto_id, cant_uds, cant_uom,
             no_se_entrega, motivo_no_entrega, no_entrega_por, no_entrega_en)
     values ((select id from ent_alisto where not anulado order by id desc limit 1),
             451, 1, 0, true, 'agotado', 'prueba-7c3', now());
   rollback;


-- ── 7c-4-bis · SIN marcar pero con motivo puesto ───────────────────────
-- La rama `else` exige que los cinco campos de la excepcion queden en NULL.
   begin;
     insert into ent_alisto_linea
            (alisto_id, producto_id, cant_uds, no_se_entrega, motivo_no_entrega)
     values ((select id from ent_alisto where not anulado order by id desc limit 1),
             451, 1, false, 'agotado');
   rollback;


-- ════════════════════════════════════════════════════════════════════════
-- 7f · EL CONTROL QUE VALE · por IDS, no por cantidad
-- ════════════════════════════════════════════════════════════════════════
-- El archivo original trae `select tipo, count(*) ... group by tipo`, que cuenta.
-- Contar no alcanza: si la vista nueva cambia de semantica y devuelve SEIS filas
-- DISTINTAS, el count pasa igual y el cambio se cuela.
--
-- Medido el 13-sep-2026 con pg_lector sobre la vista VIEJA
-- (v_ent_indeterminado_pendiente), que son las seis de referencia:
--
--   alisto_lote_id | pedido | producto          | cantidad     | motivo
--   ---------------+--------+-------------------+--------------+-------------------
--   164            | 48     | Pan Blanco        | 1 unidad     | sticker_caido
--   184            | 55     | Pan Blanco        | 102 unidades | chofer_no_reporto
--   192            | 56     | Buns              | 2 paquetes   | no_se_anoto
--   193            | 56     | Pan Blanco        | 2 unidades   | no_se_anoto
--   194            | 56     | Pan de Semillas   | 2 unidades   | no_se_anoto
--   195            | 56     | Pan Frances       | 2 paquetes   | no_se_anoto
--
--   Las seis son del 8-sep-2026 (09:16:57 a 14:28:11 CR), TODAS anteriores al
--   corte del ancla, asi que ninguna mueve el saldo de hoy.
--
-- TIENE QUE DEVOLVER EXACTAMENTE ESOS SEIS IDS. Seis distintas = PARAR.
select alisto_lote_id, pedido_id, producto_id, cant_uds, motivo
  from v_ent_excepcion_pendiente
 where tipo = 'lote_no_determinado'
 order by alisto_lote_id;

-- Y esta tiene que dar CERO filas: la marca 'no se entrega' no existia hasta hoy.
select count(*) as no_se_entrega_pendientes
  from v_ent_excepcion_pendiente where tipo = 'no_se_entrega';
