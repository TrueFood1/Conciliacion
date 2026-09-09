-- ════════════════════════════════════════════════════════════════════════
-- b56 · ¿Aparecen en el selector los lotes viejos con saldo?  (SOLO LECTURA)
--
-- QUÉ PRUEBA. El selector de Entregas salía solo de entLotesActivos(3), o sea
-- los últimos 3 meses de PRODUCCIÓN. Un lote más viejo con producto en el
-- congelador no se podía elegir. b56 lo cambia por la unión de las dos fuentes
-- (lotes activos + claves del saldo), la misma que ya usaba Inventario.
--
-- POR QUÉ ESTE SELECT ALCANZA. Para un lote FUERA de la ventana de 3 meses, el
-- término "producción" del motor vale 0 por definición (solo suma órdenes que
-- están en g.lotes) y su merma cae en `mermaSinLote`, que no baja de ningún
-- lote. Así que para estos cinco:
--        saldo = ancla − salido del congelador + devuelto
-- ...que es exactamente lo que calcula esta consulta, sin tocar Odoo.
--
-- CÓMO SE CORRE (la clave nunca toca el disco ni el historial):
--     copiá la contraseña de Postgres al portapapeles, y después
--     python3 herramientas/pg_lector.py --clave --archivo VERIFICACION_B56_SELECTOR.sql
-- ════════════════════════════════════════════════════════════════════════

-- 1 · El ancla vigente. Todo lo de abajo se cuenta DESPUÉS de este corte.
select id as conteo_id, fecha, corte from ent_ancla;

-- 2 · Saldo por (producto, lote), de las tres fuentes de Supabase.
--     `en_selector_b56` es la regla nueva: un lote viejo entra si le queda algo.
with anc as (select id from ent_ancla limit 1),
     a as (select l.producto_id, l.lote, sum(l.uds) uds
             from ent_conteo_linea l join anc on l.conteo_id = anc.id
            group by 1,2),
     s as (select producto_id, lote, sum(uds) uds
             from ent_salido_del_congelador_desde_ancla group by 1,2),
     d as (select producto_id, lote, sum(uds) uds
             from ent_devuelto_desde_ancla group by 1,2),
     k as (select producto_id, lote from a
           union select producto_id, lote from s
           union select producto_id, lote from d)
select k.producto_id,
       case k.producto_id when 451 then 'Pan Blanco'  when 452 then 'Pan de Semillas'
                          when 453 then 'Pan Frances' when 472 then 'Pizza Crust'
                          when 503 then 'Buns'        when 519 then 'Galletas'
                          else '?' end as producto,
       k.lote,
       coalesce(a.uds,0) as ancla,
       coalesce(s.uds,0) as salido,
       coalesce(d.uds,0) as devuelto,
       coalesce(a.uds,0) - coalesce(s.uds,0) + coalesce(d.uds,0) as saldo_uds,
       case when coalesce(a.uds,0) - coalesce(s.uds,0) + coalesce(d.uds,0) > 0
            then 'SI' else 'no' end as en_selector_b56
  from k
  left join a on a.producto_id = k.producto_id and a.lote = k.lote
  left join s on s.producto_id = k.producto_id and s.lote = k.lote
  left join d on d.producto_id = k.producto_id and d.lote = k.lote
 order by k.producto_id, k.lote;

-- 3 · Los CINCO del caso, aislados. Es la fila que hay que leer.
--     Pizza 120/10-26 (el de hoy, 4 paquetes), Pizza 82/9-26 y 107/10-26,
--     Semillas 126/11-26 y Frances 182/12-26 (documentados el 25-ago).
--     El match va por prefijo numerico + vencimiento para no depender de como
--     esten escritos los espacios alrededor de la barra.
with anc as (select id from ent_ancla limit 1),
     a as (select l.producto_id, l.lote, sum(l.uds) uds
             from ent_conteo_linea l join anc on l.conteo_id = anc.id
            group by 1,2),
     s as (select producto_id, lote, sum(uds) uds
             from ent_salido_del_congelador_desde_ancla group by 1,2),
     d as (select producto_id, lote, sum(uds) uds
             from ent_devuelto_desde_ancla group by 1,2),
     k as (select producto_id, lote from a
           union select producto_id, lote from s
           union select producto_id, lote from d),
     objetivo(producto_id, ddd, venc) as (values
       (472,'120','10-26'), (472,'82','9-26'), (472,'107','10-26'),
       (452,'126','11-26'), (453,'182','12-26'))
select o.producto_id, o.ddd || ' / ' || o.venc as lote_buscado,
       k.lote as lote_en_base,
       coalesce(a.uds,0) as ancla,
       coalesce(s.uds,0) as salido,
       coalesce(d.uds,0) as devuelto,
       coalesce(a.uds,0) - coalesce(s.uds,0) + coalesce(d.uds,0) as saldo_uds,
       case when k.lote is null then 'NO ESTA EN LA BASE'
            when coalesce(a.uds,0) - coalesce(s.uds,0) + coalesce(d.uds,0) > 0
            then 'SI aparece en el selector'
            else 'no aparece (saldo <= 0)' end as veredicto
  from objetivo o
  left join k on k.producto_id = o.producto_id
             and regexp_replace(k.lote, '\s', '', 'g') = o.ddd || '/' || o.venc
  left join a on a.producto_id = k.producto_id and a.lote = k.lote
  left join s on s.producto_id = k.producto_id and s.lote = k.lote
  left join d on d.producto_id = k.producto_id and d.lote = k.lote
 order by o.producto_id, o.ddd::int;
