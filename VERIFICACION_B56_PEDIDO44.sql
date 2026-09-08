-- ════════════════════════════════════════════════════════════════════════
-- b56 · VERIFICACION de la correccion del pedido 44. SOLO LECTURA.
--   1 · la salida vigente dice 7-sep y el 43 sigue intacto
--   2 · la historia quedo (dos filas), no se borro nada
--   3 · ningun saldo por lote se movio
--   4 · el vinculo a la factura, leido de la tabla del vinculo
--   5 · el reseteo del balde por ancla nueva, MEDIDO antes del viernes
--   6 · existe la tabla de accesos (para el freno del Bloque 3)
--
--     python3 herramientas/pg_lector.py --clave --archivo VERIFICACION_B56_PEDIDO44.sql
-- ════════════════════════════════════════════════════════════════════════

-- ══ 1 · el 44 ya dice 7-sep, el 43 sigue en 3-sep. Y la semana ISO de cada uno.
select e.pedido_id, e.origen, e.cliente_nombre, e.estado,
       (e.preparado_en at time zone 'America/Costa_Rica') as preparado_cr,
       (e.salida_en    at time zone 'America/Costa_Rica') as salida_cr,
       extract(week from e.salida_en at time zone 'America/Costa_Rica') as semana_iso,
       (e.salida_en at time zone 'America/Costa_Rica')::date
         = (e.salida_registrada_en at time zone 'America/Costa_Rica')::date as hora_medida
  from v_ent_pedido_estado e
 where e.pedido_id in (43, 44)
 order by e.pedido_id;

-- ══ 2 · la historia del alisto del 44: la fila vieja tiene que seguir ahi.
select s.id, s.alisto_id,
       (s.salida_en at time zone 'America/Costa_Rica') as salida_cr,
       (s.creado_en at time zone 'America/Costa_Rica') as registrado_cr,
       s.creado_por,
       (s.id = sv.salida_id) as es_la_vigente
  from ent_salida s
  join ent_alisto a on a.id = s.alisto_id
  left join ent_salida_vigente sv on sv.alisto_id = s.alisto_id
 where a.pedido_id = 44
 order by s.creado_en;

-- ══ 3 · NINGUN SALDO SE MOVIO, y la prueba es DIFERENCIAL, no absoluta.
--
-- ⚠️ LA PRIMERA VERSION DE ESTA CONSULTA ESTUVO MAL, y vale dejar escrito por que.
-- Comparaba el saldo absoluto contra 713 / 121 / 1636 / 424 / 1444 / 101, que son
-- los numeros MEDIDOS el 7-sep. Dieron 693 / 24 / 1264 / 328 / 1216 / 97 y por un
-- momento parecio que la correccion habia movido los seis saldos. No: entre esa
-- medicion y esta pasaron doce pedidos del 8-sep (45 a 56). Era un numero de una
-- medicion vieja usado como objetivo de hoy — exactamente la confusion que la
-- bitacora del 9-ago manda evitar.
--
-- La prueba correcta calcula el saldo DOS VECES: como esta ahora (manda la salida
-- corregida) y como estaria si la correccion no existiera (ignorandola, o sea con
-- la salida vieja de vuelta). Si la diferencia es cero, la correccion no movio
-- nada — y eso es cierto sin importar cuantas entregas se registren despues.
--
-- El id de la salida a ignorar se busca por creado_por, no se escribe a mano.
with correccion as (
       select s.id from ent_salida s
        where s.creado_por like 'correccion-sql · b56%'),
     sv_sin as (
       select distinct on (s.alisto_id) s.alisto_id, s.salida_en
         from ent_salida s
        where s.id not in (select id from correccion)
          and not exists (select 1 from ent_anulacion x
                           where x.entidad='salida' and x.entidad_id = s.id)
        order by s.alisto_id, s.creado_en desc),
     salido_sin as (
       select al.lote, ali.producto_id, sum(al.cant_uds) as uds
         from ent_alisto_lote  al
         join ent_alisto_linea ali on ali.id        = al.linea_id
         join ent_alisto_vigente av on av.alisto_id = ali.alisto_id
         left join sv_sin sv on sv.alisto_id = av.alisto_id
        where coalesce(sv.salida_en, av.preparado_en) > (select corte from ent_ancla)
        group by al.lote, ali.producto_id),
     anc as (select producto_id, lote, sum(uds) u from ent_conteo_linea
              where conteo_id = (select id from ent_ancla) group by 1,2),
     con as (select a.producto_id, sum(a.u) - coalesce(sum(s.uds),0) as saldo
               from anc a
               left join ent_salido_del_congelador_desde_ancla s
                      on s.lote = a.lote and s.producto_id = a.producto_id
              group by a.producto_id),
     sin as (select a.producto_id, sum(a.u) - coalesce(sum(s.uds),0) as saldo
               from anc a
               left join salido_sin s
                      on s.lote = a.lote and s.producto_id = a.producto_id
              group by a.producto_id)
select pres.nombre                              as producto,
       round(sin.saldo / pres.div, 3)            as sin_la_correccion,
       round(c.saldo   / pres.div, 3)            as con_la_correccion,
       pres.rotulo                               as unidad,
       round((c.saldo - sin.saldo) / pres.div, 3) as dif
  from con c
  join sin  on sin.producto_id = c.producto_id
  join (values (451,'Pan Blanco',1,'unidades'), (452,'Pan de Semillas',1,'unidades'),
               (453,'Pan Frances',4,'paquetes'), (472,'Pizza Crust',2,'paquetes'),
               (503,'Buns',4,'paquetes'),        (519,'Galletas',1,'unidades'))
         as pres(producto_id, nombre, div, rotulo) on pres.producto_id = c.producto_id
 order by pres.nombre;
-- El saldo sale en UNIDAD DE VENTA, no en unidades sueltas: `cant_uds` guarda
-- individuales y eso es asunto de la columna, no del reporte.
-- Esperado: dif = 0 en los seis. MEDIDO el 8-sep: 0 / 0 / 0 / 0 / 0 / 0.

-- ══ 4 · el vinculo a la factura, de la tabla del vinculo y de la columna vieja,
--    lado a lado. El null de la columna NO significa que el vinculo falte.
-- OJO con los nombres: en `ent_pedido_factura_vigente` las columnas son
-- `vinculado_por` y `vinculado_en`, NO `creado_por` / `creado_en`. La primera
-- version de esta consulta uso los de la tabla base y revento.
select p.id as pedido, p.origen,
       fv.factura_nombre as del_vinculo,
       p.factura_nombre  as columna_obsoleta,
       fv.vinculado_por,
       (fv.vinculado_en at time zone 'America/Costa_Rica') as vinculado_cr
  from ent_pedido p
  left join ent_pedido_factura_vigente fv
         on fv.pedido_id = p.id and fv.anulado = false
 where p.id in (43, 44)
 order by p.id;

-- ══ 5 · EL RESETEO DEL BALDE, MEDIDO ANTES DEL VIERNES. Es la verificacion 2 de
--    las tres del Bloque 3, y se puede hacer HOY: los lotes fantasma ('sin lote'
--    y 'Sin lote') ya se comportan como el centinela va a comportarse. Se simula
--    el corte de un ancla nueva de mañana y se mira si siguen apareciendo.
--    Esperado: CERO filas invalidas con el corte simulado.
with corte_simulado(corte) as (values (timestamptz '2026-09-11 18:00:00-06:00')),
     salido as (
       select al.lote, ali.producto_id, sum(al.cant_uds) as uds
         from ent_alisto_lote  al
         join ent_alisto_linea ali on ali.id        = al.linea_id
         join ent_alisto_vigente av on av.alisto_id = ali.alisto_id
         left join ent_salida_vigente sv on sv.alisto_id = av.alisto_id
        where coalesce(sv.salida_en, av.preparado_en) > (select corte from corte_simulado)
        group by al.lote, ali.producto_id)
select 'con el corte de HOY'  as escenario, count(*) as claves_invalidas
  from ent_salido_del_congelador_desde_ancla
 where lote !~ '^\d{1,3} / \d{1,2}-\d{2}$'
union all
select 'con el corte SIMULADO del viernes', count(*)
  from salido
 where lote !~ '^\d{1,3} / \d{1,2}-\d{2}$';

-- ══ 5b · el detalle, para poder decir cual sobrevive si alguna sobrevive.
with corte_simulado(corte) as (values (timestamptz '2026-09-11 18:00:00-06:00'))
select al.lote, ali.producto_id, sum(al.cant_uds) as uds,
       max(coalesce(sv.salida_en, av.preparado_en)) as ultimo_movimiento
  from ent_alisto_lote  al
  join ent_alisto_linea ali on ali.id        = al.linea_id
  join ent_alisto_vigente av on av.alisto_id = ali.alisto_id
  left join ent_salida_vigente sv on sv.alisto_id = av.alisto_id
 where al.lote !~ '^\d{1,3} / \d{1,2}-\d{2}$'
   and coalesce(sv.salida_en, av.preparado_en) > (select corte from corte_simulado)
 group by al.lote, ali.producto_id
 order by ali.producto_id, al.lote;

-- ══ 6 · BLOQUE 3, condicion 2 · existe la tabla de accesos que ACCESOS_ESQUEMA.sql
--    declara. Si existe, el freno de "solo Andrea resuelve" se puede expresar
--    contra ella en vez de con un correo escrito adentro de una politica.
select t.nombre,
       (select count(*) from information_schema.tables i
         where i.table_schema='public' and i.table_name = t.nombre) as existe
  from (values ('acceso_usuario'), ('v_acceso_usuario')) as t(nombre)
 order by t.nombre;
