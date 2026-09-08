-- ════════════════════════════════════════════════════════════════════════
-- b56 · DIAGNOSTICO, SOLO LECTURA. No cambia nada.
--   A) BLOQUE 6   · la fecha pegada de los pedidos 43 y 44 (Walmart / CSU)
--   B) BLOQUE 3.7 · toda cadena guardada como lote que NO tiene forma de lote
--   C) BLOQUE 7   · cuales tablas del Planificador existen de verdad
--
--     python3 herramientas/pg_lector.py --clave --archivo DIAGNOSTICO_B56.sql
--
-- DOS TRAMPAS DEL LECTOR, aprendidas rompiendolo. Parte el archivo por punto y
-- coma y despues envuelve cada pedazo en una transaccion de solo lectura.
--   1. Un pedazo que TERMINA en linea de comentario deja el punto y coma final
--      comentado, y revienta en "commit". Los comentarios van SIEMPRE arriba de
--      la sentencia que describen, nunca abajo.
--   2. Un punto y coma DENTRO de un comentario tambien parte el archivo. En los
--      comentarios de este archivo no hay ni uno.
-- ════════════════════════════════════════════════════════════════════════

-- ══ A1 · BLOQUE 6 · los pedidos 43 y 44 con sus tres marcas de tiempo.
--    preparado_en es cuando se cerro el alisto. salida_en es cuando se dice que
--    salio del congelador. creado_en es cuando se tecleo la fila.
select p.id as pedido, p.origen, p.fecha_despacho, p.cliente_nombre,
       p.factura_nombre, p.creado_por, p.creado_en as pedido_creado_en,
       a.id as alisto_id, a.creado_en as preparado_en,
       s.id as salida_id, s.salida_en, s.nota as salida_nota,
       s.creado_por as salida_creado_por, s.creado_en as salida_creado_en
  from ent_pedido p
  left join ent_alisto a on a.pedido_id = p.id
  left join ent_salida s on s.alisto_id = a.id
 where p.id in (43, 44)
 order by p.id, a.id, s.id;

-- ══ A2 · lo mismo, pero como lo ve la vista que alimenta el Historial.
--    Si aca salida_en sale distinto que en A1, el problema esta en la vista.
select pedido_id, cliente_nombre, factura_id, factura_nombre, estado,
       preparado_en, salida_en, salida_registrada_en, n_lineas
  from v_ent_pedido_estado
 where pedido_id in (43, 44)
 order by pedido_id;

-- ══ A3 · el vinculo a la factura de esos pedidos. La 3515 es CSU, del 7-sep.
select pedido_id, factura_id, factura_nombre, anulado, creado_por, creado_en
  from ent_pedido_factura
 where pedido_id in (43, 44)
 order by pedido_id, creado_en;

-- ══ A4 · que salio en esos dos pedidos, por lote. Es lo que hay que mirar
--    para el punto 5: no mover ninguna fila de semana en el AB-RE-04.
select p.id as pedido, al.producto_id, alt.lote, alt.cant_uds
  from ent_pedido p
  join ent_alisto a on a.pedido_id = p.id
  join ent_alisto_linea al on al.alisto_id = a.id
  join ent_alisto_lote alt on alt.linea_id = al.id
 where p.id in (43, 44)
 order by p.id, al.producto_id, alt.orden;

-- ══ B1 · BLOQUE 3.7 · toda fila de ent_alisto_lote cuyo lote no tenga forma
--    canonica DDD / M-AA. Es la tabla donde cae lo que se escribe a mano en el
--    alisto de una factura y en el reporte sin factura.
select 'ent_alisto_lote' as tabla, alt.id as fila,
       p.id as pedido, p.origen, p.fecha_despacho, p.cliente_nombre,
       p.factura_nombre, al.producto_id, alt.cant_uds,
       '[' || alt.lote || ']' as cadena_exacta, a.creado_en as fecha
  from ent_alisto_lote alt
  join ent_alisto_linea al on al.id = alt.linea_id
  join ent_alisto a on a.id = al.alisto_id
  join ent_pedido p on p.id = a.pedido_id
 where alt.lote !~ '^\d{1,3} / \d{1,2}-\d{2}$'
 order by a.creado_en;

-- ══ B2 · lo mismo en ent_conteo_linea, que es el ancla. Si aparece algo aca NO
--    se migra sin preguntar: es texto de otra pantalla, no de una entrega.
select 'ent_conteo_linea' as tabla, l.id as fila, l.conteo_id,
       l.producto_id, l.uds, '[' || l.lote || ']' as cadena_exacta,
       l.creado_en as fecha
  from ent_conteo_linea l
 where l.lote !~ '^\d{1,3} / \d{1,2}-\d{2}$'
 order by l.creado_en;

-- ══ B3 · y en devoluciones. Se espera CERO: la columna tiene un check en la
--    base desde que existe la tabla. Se consulta igual, para no citarlo.
select 'ent_devolucion' as tabla, d.id as fila, d.producto_id,
       '[' || d.lote || ']' as cadena_exacta, d.creado_en as fecha
  from ent_devolucion d
 where d.lote !~ '^\d{1,3} / \d{1,2}-\d{2}$'
 order by d.creado_en;

-- ══ B4 · toda columna llamada lote que exista en la base, para probar que la
--    busqueda de arriba cubrio TODAS y no solo las tres que yo conozco.
select table_name, column_name, data_type
  from information_schema.columns
 where table_schema = 'public' and column_name ilike '%lote%'
 order by table_name, column_name;

-- ══ C1 · BLOQUE 7 · cuales tablas del Planificador existen. plan_metas no
--    aparece en ninguna linea de index.html: se consulta para cerrar el punto.
select t.nombre,
       (select count(*) from information_schema.tables i
         where i.table_schema='public' and i.table_name = t.nombre) as existe
  from (values ('plan_config'), ('plan_metas'), ('plan_overrides'),
               ('semana_capacidad')) as t(nombre)
 order by t.nombre;

-- ══ C2 · cuantas filas tiene cada una. Una tabla vacia y una que no existe se
--    ven igual en pantalla y NO son lo mismo.
select 'plan_config' as tabla, count(*) as filas from plan_config;

select 'plan_overrides' as tabla, count(*) as filas from plan_overrides;

select 'semana_capacidad' as tabla, count(*) as filas from semana_capacidad;

-- ══ C3 · los overrides mas recientes. Si hay filas, las ediciones del
--    Planificador SI estan sobreviviendo al recargar.
select fecha, producto_id, batches, tipo, personas, creado_en
  from plan_overrides
 order by creado_en desc
 limit 15;
