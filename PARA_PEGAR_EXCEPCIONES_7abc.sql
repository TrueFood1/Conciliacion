-- ════════════════════════════════════════════════════════════════════════
-- PARA PEGAR · 7a / 7b / 7c · UNA POR UNA, Y LAS TRES TIENEN QUE DAR ERROR
-- ════════════════════════════════════════════════════════════════════════
-- Preparado el 13-sep-2026. NO SE CORRIO.
--
-- ⚠️ UNA POR UNA. Estas pruebas terminan en error A PROPOSITO, y en el SQL editor
-- un error aborta el resto del lote. Pegadas juntas, la primera mata a las demas
-- y parece que "paso todo". Van de a una, se lee el error, y se pasa a la siguiente.
--
-- ⚠️ EL ERROR ES EL RESULTADO BUENO. Si alguna PASA en vez de fallar, el candado
-- que esa prueba mide NO esta puesto: PARAR y avisar.
--
-- Las tres van envueltas en begin/rollback: no dejan nada escrito.
--
-- PROCEDENCIA, para que la proxima sesion sepa que es literal y que no:
--   7a, 7b y la PRIMERA esquina de 7c son COPIA LITERAL de
--   ENTREGAS_EXCEPCIONES_LINEA.sql (lineas 501-511, 517-521 y 529), solo
--   descomentadas.
--   Las otras TRES esquinas de 7c el archivo original las describe en prosa pero
--   no las escribe. Las derive del CHECK `ent_alisto_linea_no_entrega_ok` tal como
--   esta en el §1 (lineas 130-145). Estan marcadas [DERIVADA] una por una.
--   Reviselas antes de correrlas: no vienen medidas de ningun lado.
--
-- ANTES DE ESTO: haber corrido 7e-ANTES, pegado PARA_PEGAR_EXCEPCIONES_1a6.sql,
-- y 7e-DESPUES (identico al ANTES).
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- 7a · EL EXCLUYENTE, SENTIDO (a) · una linea marcada no puede llevar lote
-- ESPERADO: ERROR 'la linea N esta marcada "no se entrega": no puede llevar lote'
-- Si el INSERT pasa, el trigger no esta puesto: PARAR.
-- ════════════════════════════════════════════════════════════════════════
   begin;
     -- se marca una linea cualquiera SIN lotes y se le intenta colgar uno
     update ent_alisto_linea set no_se_entrega = true, motivo_no_entrega = 'agotado',
            no_entrega_por = 'prueba', no_entrega_en = now(), cant_uds = 0, cant_uom = 0
      where id = (select l.id from ent_alisto_linea l
                   where not exists (select 1 from ent_alisto_lote al where al.linea_id = l.id)
                   order by l.id desc limit 1);
     insert into ent_alisto_lote (linea_id, lote, cant_uds, orden)
     select l.id, '001 / 1-27', 1, 0 from ent_alisto_linea l
      where l.no_se_entrega order by l.id desc limit 1;
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
-- 7c · EL CHECK DE §1, LAS CUATRO ESQUINAS
-- Las cuatro ESPERAN: ERROR 'violates check constraint "ent_alisto_linea_no_entrega_ok"'
-- Cada una sola, cada una en su begin/rollback.
-- ════════════════════════════════════════════════════════════════════════

-- ── 7c-1 · marcada SIN motivo ── (literal del archivo original, linea 529)
   begin; update ent_alisto_linea set no_se_entrega = true where id = <una sin lotes>; rollback;

-- ── 7c-2 · motivo 'otro' SIN nota ── [DERIVADA del CHECK, no del archivo]
-- El CHECK exige: motivo <> 'otro'  OR  (nota is not null and length(btrim(nota)) >= 10)
begin;
  update ent_alisto_linea
     set no_se_entrega = true, motivo_no_entrega = 'otro', nota_no_entrega = null,
         no_entrega_por = 'prueba', no_entrega_en = now(), cant_uds = 0, cant_uom = 0
   where id = (select l.id from ent_alisto_linea l
                where not exists (select 1 from ent_alisto_lote al where al.linea_id = l.id)
                order by l.id desc limit 1);
rollback;

-- ── 7c-3 · marcada pero con cant_uds > 0 ── [DERIVADA del CHECK, no del archivo]
-- Es la condicion que hace VERDAD "no mueve ningun saldo": cant_uds = 0 and coalesce(cant_uom,0) = 0
begin;
  update ent_alisto_linea
     set no_se_entrega = true, motivo_no_entrega = 'agotado',
         no_entrega_por = 'prueba', no_entrega_en = now(), cant_uds = 1, cant_uom = 0
   where id = (select l.id from ent_alisto_linea l
                where not exists (select 1 from ent_alisto_lote al where al.linea_id = l.id)
                order by l.id desc limit 1);
rollback;

-- ── 7c-4 · SIN marcar pero con motivo puesto ── [DERIVADA del CHECK, no del archivo]
-- La rama `else` exige que los cinco campos de la excepcion queden en NULL.
begin;
  update ent_alisto_linea
     set no_se_entrega = false, motivo_no_entrega = 'agotado'
   where id = (select l.id from ent_alisto_linea l
                where not exists (select 1 from ent_alisto_lote al where al.linea_id = l.id)
                order by l.id desc limit 1);
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
