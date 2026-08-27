-- ════════════════════════════════════════════════════════════════════════
-- CORRECCIÓN · el despacho 11 registra una salida que NUNCA OCURRIÓ
-- 26-ago-2026.  Pegar COMO UN SOLO BLOQUE en el editor SQL de Supabase.
--
-- QUÉ PASÓ. El despacho 11 (Mentha y limón, 19-ago, factura ...3484) entró en el
-- cargue retroactivo del 19-ago desde la hoja de Daniel. La hoja tenía el bloque
-- anotado y la factura existía en Odoo, así que el cargue lo dio por salido. Pero
-- el pan NO salió el 19: la entrega no se hizo, la 3484 se anuló por eso (NC
-- id 40822) y su traslado `WH/OUT/02319` está `cancel` en Odoo. El producto salió
-- HOY, 26-ago, con la factura ...3499 (pedido de venta S02360, traslado
-- `WH/OUT/02333` validado).
--
-- CONSECUENCIA. El lote se descontó DOS VECES: una por el despacho 11, que es
-- falso, y otra por la salida real de hoy. El saldo de esos dos lotes está 6
-- unidades más bajo que el congelador físico, cada uno.
--
-- QUÉ DEVUELVE ESTE BLOQUE AL SALDO:
--     Pan Blanco       [451]   6 u   ·   lote  202 / 1-27
--     Pan de Semillas  [452]   6 u   ·   lote  209 / 1-27
--
-- POR QUÉ SE ANULA EL **ALISTO** Y NO SOLO LA SALIDA. El saldo se descuenta al
-- PREPARAR, no al entregar: `ent_salido_del_congelador_desde_ancla` suma desde
-- `ent_alisto_lote` pasando por `ent_alisto_vigente`. Anular solo la salida
-- devolvería el pedido a "Preparado" y dejaría el saldo igual de mal. Se anulan
-- las dos cosas, porque las dos son falsas: no se preparó y no salió.
--
-- APPEND-ONLY. No se borra ni se actualiza nada. Anular = INSERTAR en
-- `ent_anulacion`, que es la única forma que el esquema permite (ent_alisto.anulado
-- existe pero NO tiene grant de UPDATE — ver ENTREGAS_ETAPAS.sql §2). La fila del
-- despacho 11 se queda donde está, con su historia entera y su motivo escrito.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── 0 · CANDADO ANTI-DUPLICADO ──────────────────────────────────────────
do $$
begin
  if not exists (select 1 from ent_pedido where id = 11) then
    raise exception 'No existe el pedido 11. No se insertó nada.';
  end if;
  if exists (select 1 from ent_anulacion x
              join ent_alisto a on a.id = x.entidad_id
             where x.entidad = 'alisto' and a.pedido_id = 11) then
    raise exception 'YA ANULADO: el alisto del pedido 11 ya tiene anulación. No se insertó nada.';
  end if;
end $$;

-- ── 1 · LO QUE SE VA A DEVOLVER AL SALDO (mirar antes de confirmar) ─────
select 'ANTES' as momento, ali.producto_id, al.lote, sum(al.cant_uds) as uds_que_vuelven
  from ent_alisto_lote  al
  join ent_alisto_linea ali on ali.id = al.linea_id
  join ent_alisto        a  on a.id   = ali.alisto_id
 where a.pedido_id = 11
 group by ali.producto_id, al.lote
 order by ali.producto_id;

-- ── 2 · ANULAR EL ALISTO · esto es lo que devuelve el saldo ─────────────
insert into ent_anulacion (entidad, entidad_id, motivo, creado_por)
select 'alisto', a.id,
       'La preparación NUNCA OCURRIÓ. El despacho 11 entró en el cargue retroactivo '
       || 'del 19-ago desde la hoja de Daniel; la hoja lo tenía anotado y la factura '
       || '...3484 existía, pero el pan no salió ese día. Andrea lo confirma el 26-ago. '
       || 'Evidencia en Odoo: la 3484 está anulada por NC (id 40822) y su traslado '
       || 'WH/OUT/02319 quedó en estado cancel. El producto salió el 26-ago con la '
       || 'factura ...3499 (pedido de venta S02360, traslado WH/OUT/02333 validado), '
       || 'que está registrada aparte. Sin esta anulación el lote queda descontado dos veces.',
       'correccion-sql:26ago-desp11'
  from ent_alisto a
 where a.pedido_id = 11;

-- ── 3 · ANULAR LA SALIDA · las dos son falsas, no solo una ─────────────
insert into ent_anulacion (entidad, entidad_id, motivo, creado_por)
select 'salida', s.id,
       'La salida NUNCA OCURRIÓ. Se anula junto con su alisto — ver el motivo de la '
       || 'anulación del alisto del pedido 11. La salida real de este producto es la '
       || 'del 26-ago contra la factura ...3499.',
       'correccion-sql:26ago-desp11'
  from ent_salida s
  join ent_alisto a on a.id = s.alisto_id
 where a.pedido_id = 11;

-- ── 4 · COMPROBACIÓN · el alisto ya no es vigente ──────────────────────
-- Tiene que devolver CERO filas. Si devuelve alguna, algo no se anuló.
select 'NO DEBERIA SALIR NADA' as control, av.*
  from ent_alisto_vigente av
 where av.pedido_id = 11;

-- ── 5 · COMPROBACIÓN · el saldo ya no lo cuenta ────────────────────────
-- Los lotes 202 / 1-27 y 209 / 1-27 no deben traer las 6 u del despacho 11.
select 'DESPUES' as momento, producto_id, lote, uds as uds_que_siguen_descontadas
  from ent_salido_del_congelador_desde_ancla
 where lote in ('202 / 1-27','209 / 1-27')
 order by producto_id, lote;

commit;


-- ════════════════════════════════════════════════════════════════════════
-- APARTE · VERIFICAR LA SALIDA REAL DE HOY (...3499). NO MODIFICA NADA.
-- Correr DESPUÉS del bloque de arriba. Lo que hay que ver: que exista UN solo
-- despacho para la 3499, con Blanco 6 y Semillas 6, y con sus lotes.
-- ════════════════════════════════════════════════════════════════════════
select p.id as despacho, p.fecha_despacho, p.cliente_nombre, p.factura_nombre,
       p.motivo, p.origen, p.creado_por, p.creado_en,
       ali.producto_id, ali.cant_uds, al.lote, al.cant_uds as uds_del_lote,
       (av.alisto_id is not null) as alisto_vigente,
       sv.salida_en
  from ent_pedido p
  left join ent_alisto_vigente av  on av.pedido_id = p.id
  left join ent_alisto_linea   ali on ali.alisto_id = av.alisto_id
  left join ent_alisto_lote    al  on al.linea_id  = ali.id
  left join ent_salida_vigente sv  on sv.alisto_id = av.alisto_id
 where p.cliente_id = 887                          -- Mentha y limón
   and p.fecha_despacho >= date '2026-08-19'
 order by p.fecha_despacho, p.id, ali.producto_id;
