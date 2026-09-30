-- ════════════════════════════════════════════════════════════════════════
-- ANULAR UNA DEVOLUCION A MANO · 17-sep-2026
-- Preparado. NO SE CORRIO.
--
-- PARA QUE. Hasta que exista el boton en la lista de Devoluciones, esta es la
-- unica forma de deshacer una devolucion registrada. Andrea lo pidio "por si lo
-- necesito antes de que el boton exista".
--
-- ⚠️ NO BORRA NADA, Y NO TIENE QUE BORRAR. Escribe UNA fila en `ent_anulacion`.
-- La devolucion sigue existiendo con todas sus lineas; lo que cambia es que
-- `ent_devolucion_vigente` deja de mostrarla, y por eso todo lo que cuelga de
-- esa vista deja de contarla. El rastro de las dos versiones queda entero, que
-- es la unica forma de corregir en este modulo.
--
-- LA CADENA, VERIFICADA EL 17-sep CONTRA PRODUCCION (no supuesta):
--   ent_devolucion_vigente   filtra `where not exists (ent_anulacion x where
--                            x.entidad='devolucion' and x.entidad_id = d.id)`
--   ent_devuelto_desde_ancla hace JOIN a ent_devolucion_vigente  <- LA 4a PUNTA
--   v_ent_devolucion_exceso  tambien sale de ent_devolucion_vigente
-- O sea: al anular, el saldo por lote vuelve SOLO y la marca de exceso
-- desaparece SOLA. No hay nada mas que tocar.
--
-- ⚠️ LA NOTA DE CREDITO **NO** SE ANULA CON ESTO. `ent_odoo_pendiente` no cuelga
-- de `ent_devolucion_vigente`: su fila `nota_credito` va a seguir en la cola de
-- las socias. Si la devolucion se anula porque NO habia que hacer ninguna NC,
-- hay que marcarla hecha aparte (ver el bloque opcional al final). Esto es una
-- consecuencia del diseño, no un olvido: la NC puede haberse emitido ya en Odoo.
--
-- ⚠️ `ent_anulacion` acepta solo tres entidades, medido:
--    'alisto' · 'salida' · 'devolucion'
-- Y su RLS es `insert to authenticated with check (true)`: NO comprueba que
-- seas socia. El filtro "solo socias" del boton va a ser de pantalla, o sea
-- cosmetico, igual que el de descartar borradores.
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- §0 · ANTES · MEDIR. Solo lectura. Correr y GUARDAR la salida.
-- ════════════════════════════════════════════════════════════════════════

-- 0a · las devoluciones vigentes, para elegir cual. ANOTAR EL id.
select d.devolucion_id, d.fecha, d.cliente_nombre, d.pedido_id, d.causa,
       left(coalesce(d.nota,''),40) as nota, d.creado_por,
       d.recibido_en at time zone 'America/Costa_Rica' as recibido_cr
  from ent_devolucion_vigente d order by d.recibido_en desc;

-- 0b · QUE SUMA HOY esa devolucion, lote por lote. Es lo que va a dejar de
--      sumar. ⚠️ Reemplazar :ID por el id de 0a en las cuatro consultas.
select dl.producto_id, dl.lote, dl.cant_uom, dl.uom_nombre, dl.cant_uds
  from ent_devolucion_linea dl where dl.devolucion_id = :ID order by dl.id;

-- 0c · LA FOTO DE LA 4a PUNTA, para comparar despues. Estos son los numeros
--      que tienen que BAJAR exactamente en lo que dice 0b.
select producto_id, lote, uds from ent_devuelto_desde_ancla order by 1,2;

-- 0d · ¿ya estaba anulada? Si devuelve algo, PARAR: no se anula dos veces.
select * from ent_anulacion where entidad='devolucion' and entidad_id = :ID;

-- 0e · la NC que nacio de ella, para saber que va a quedar colgando.
select p.id, p.tipo, p.factura_nombre, p.creado_en
  from ent_odoo_pendiente p where p.devolucion_id = :ID;


-- ════════════════════════════════════════════════════════════════════════
-- P0 · LO QUE TIENE QUE PASAR ANTES DE APLICAR NADA
-- Cada prueba construye su propio caso. Todo en begin/rollback: no escribe.
-- ════════════════════════════════════════════════════════════════════════

-- P0-0 · CONTROL · ESPERADO: PASA. La escalera anda: se puede anular una
--        devolucion de prueba y desaparece de la vista vigente.
--        SIN ESTA NO SE PUEDE LEER P0-a.
begin;
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por)
  values (current_date, 'manual', 'regalia', 'prueba-an0');
  insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, causa, creado_por)
  select current_date, 999999, 'PRUEBA an0', id, 'producto_equivocado', 'prueba-an0'
    from ent_pedido where creado_por = 'prueba-an0';
  -- antes: 1 fila en la vista vigente
  select 'antes_debe_ser_1' as q, count(*) from ent_devolucion_vigente where creado_por='prueba-an0';
  insert into ent_anulacion (entidad, entidad_id, motivo, creado_por)
  select 'devolucion', id, 'prueba', 'prueba-an0'
    from ent_devolucion where creado_por = 'prueba-an0';
  -- despues: 0. Si no da 0, la vista NO filtra y todo este archivo no sirve.
  select 'despues_debe_ser_0' as q, count(*) from ent_devolucion_vigente where creado_por='prueba-an0';
rollback;

-- P0-a · ESPERADO: **ERROR** de `ent_anulacion_entidad_chk`.
--        Verifica que la lista de entidades es cerrada de verdad. Si esto NO da
--        error, el CHECK no es lo que este archivo supone: PARAR.
begin;
  insert into ent_anulacion (entidad, entidad_id, motivo, creado_por)
  values ('devolucion_inventada', 1, 'prueba', 'prueba-ana');
  select 'P0-a MAL: entro una entidad inventada' as resultado;
rollback;

-- P0-b · ESPERADO: PASA, y las dos consultas muestran que la 4a PUNTA baja.
--        Es la prueba de que anular devuelve el saldo, medida y no supuesta.
--        Construye su propio caso completo: pedido -> devolucion -> linea.
begin;
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por)
  values (current_date, 'manual', 'regalia', 'prueba-anb');
  insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, causa, creado_por)
  select current_date, 999999, 'PRUEBA anb', id, 'producto_equivocado', 'prueba-anb'
    from ent_pedido where creado_por = 'prueba-anb';
  insert into ent_devolucion_linea
    (devolucion_id, producto_id, lote, cant_uds, uom_id, uom_nombre, cant_uom, uom_factor)
  select id, 451, '100 / 1-27', 6, 0, 'Unidades', 6, 1
    from ent_devolucion where creado_por = 'prueba-anb';
  -- ⚠️ La vista filtra por `recibido_en > corte del ancla`. Una devolucion
  -- recien insertada SIEMPRE lo cumple, asi que aca tiene que aparecer.
  select 'con la devolucion' as q, coalesce(sum(uds),0) as uds
    from ent_devuelto_desde_ancla where producto_id=451 and lote='100 / 1-27';
  insert into ent_anulacion (entidad, entidad_id, motivo, creado_por)
  select 'devolucion', id, 'prueba', 'prueba-anb'
    from ent_devolucion where creado_por = 'prueba-anb';
  -- ESPERADO: SEIS UNIDADES MENOS que la consulta de arriba.
  select 'anulada' as q, coalesce(sum(uds),0) as uds
    from ent_devuelto_desde_ancla where producto_id=451 and lote='100 / 1-27';
rollback;


-- ════════════════════════════════════════════════════════════════════════
-- EL PEGADO · UNA SOLA FILA, EN UNA SOLA TRANSACCION
-- ⚠️ Reemplazar :ID por el id de 0a, y escribir el MOTIVO de verdad — no
-- "prueba". Ese texto es lo unico que va a explicar por que se anulo.
-- ════════════════════════════════════════════════════════════════════════

begin;

insert into ent_anulacion (entidad, entidad_id, motivo, creado_por)
values ('devolucion', :ID, 'ESCRIBIR EL MOTIVO ACA', 'andrea@truefoodcr.com');

-- ⚠️ LA PRUEBA DE QUE ESTO CORRIO, ADENTRO DE LA TRANSACCION Y ANTES DEL COMMIT.
-- ESPERADO: **1 · 0** — una anulacion escrita, y cero filas de esa devolucion en
-- la vista vigente.
-- Si el editor dice "Success. No rows returned" en vez de mostrar esta fila, NO
-- LLEGO HASTA ACA y no se aplico nada: es la leccion del 17-sep, cuando un
-- "Success" tapo un pegado que no habia entrado.
-- Y si los numeros no son 1 · 0, `rollback;` a mano — todavia no commiteo.
select (select count(*) from ent_anulacion
         where entidad='devolucion' and entidad_id = :ID)              as anulacion_escrita,
       (select count(*) from ent_devolucion_vigente
         where devolucion_id = :ID)                                    as sigue_vigente;

commit;


-- ════════════════════════════════════════════════════════════════════════
-- DESPUES · VERIFICAR. Solo lectura.
-- ════════════════════════════════════════════════════════════════════════

-- V1 · la devolucion ya no esta vigente        [0 filas]
select * from ent_devolucion_vigente where devolucion_id = :ID;

-- V2 · ⚠️ LA 4a PUNTA BAJO EXACTAMENTE EN LO QUE DECIA 0b.
--      Comparar contra la salida de 0c, lote por lote.
select producto_id, lote, uds from ent_devuelto_desde_ancla order by 1,2;

-- V3 · las lineas SIGUEN ahi: no se borro nada, solo dejo de contar.
select count(*) as lineas_intactas from ent_devolucion_linea where devolucion_id = :ID;

-- V4 · la marca de exceso, si la habia, tambien desaparecio.
select * from v_ent_devolucion_exceso order by pedido_id, producto_id, lote;

-- V5 · la anulacion quedo escrita, con su motivo y su firma.
select * from ent_anulacion where entidad='devolucion' and entidad_id = :ID;


-- ════════════════════════════════════════════════════════════════════════
-- OPCIONAL · SI ADEMAS NO HAY QUE HACER LA NOTA DE CREDITO
-- ⚠️ Correr esto SOLO si la NC no se emitio y no se va a emitir. Si ya se emitio
-- en Odoo, la fila de la cola tiene que quedarse hasta que alguien la marque
-- hecha con su referencia real.
-- `ent_odoo_hecho` es de SOCIAS (`acceso_es_socia()`), pero el SQL Editor entra
-- como postgres y saltea la RLS — o sea que esto funciona y NO prueba el permiso.
-- ════════════════════════════════════════════════════════════════════════

-- begin;
-- insert into ent_odoo_hecho (pendiente_id, referencia, creado_por)
-- select p.id, 'sin NC: la devolucion se anulo', 'andrea@truefoodcr.com'
--   from ent_odoo_pendiente p where p.devolucion_id = :ID;
-- select (select count(*) from v_ent_odoo_pendiente
--          where devolucion_id = :ID) as debe_ser_0;
-- commit;
