-- ════════════════════════════════════════════════════════════════════════
-- ARREGLO · `v_ent_factura_despachada` lee la columna obsoleta
-- 26-ago-2026.  Pegar COMO UN SOLO BLOQUE en el editor SQL de Supabase.
--
-- 🔴 CORRER **DESPUÉS** DE `VINCULOS_BACKFILL.sql`. NO ANTES.
--    La vista pasa a leer `ent_pedido_factura_vigente`. Si los 23 vínculos no
--    están escritos todavía, esas 23 facturas dejan de contar como despachadas y
--    VUELVEN A "Por preparar" — con el producto ya fuera del congelador. El
--    bloque tiene un candado que lo impide, pero el orden importa igual.
--
-- QUÉ PASA. `v_ent_factura_despachada` es la vista que saca de "Por preparar" las
-- facturas que ya tienen despacho. Lee `ent_pedido.factura_id`, la columna que
-- `ENTREGAS_SALIDAS.sql` §2 declara OBSOLETA: el vínculo vive en
-- `ent_pedido_factura` y `ent_pedido.factura_id` NO tiene grant de UPDATE, así
-- que es un valor congelado en el momento en que se creó el pedido.
--
-- ES EL MISMO BUG DE b38, EN OTRA VISTA. Allá `pdLeer` leía `ent_alisto.anulado`
-- —columna sin UPDATE— en vez de `ent_alisto_vigente`; acá la vista lee
-- `ent_pedido.factura_id` en vez de `ent_pedido_factura_vigente`. Las dos veces:
-- una columna declarada muerta de la que todavía cuelga algo vivo.
--
-- POR QUÉ URGE. Sin esto, cambiar el vínculo de un despacho NO saca la factura
-- nueva de la bandeja: queda ahí con pinta de pendiente legítima y el primero que
-- la prepare descuenta los lotes por segunda vez. Es el riesgo que se abre en
-- cuanto se emita la factura nueva de Mentha por las 12 unidades del 19-ago, y es
-- el piso sobre el que se apoya el pendiente §10.
--
-- QUÉ **NO** HACE ESTE BLOQUE. No es §10. No agrega la pantalla para cambiar la
-- factura ni toca `ent_pedido`. Solo cambia de dónde LEE la vista.
--
-- AUDITORÍA · los otros lugares que tocan `ent_pedido.factura_id` (26-ago):
--   1. `v_ent_factura_despachada`  → LO LEE SOLO A ÉL. Es el bug. Se arregla acá.
--   2. `v_ent_pedido_estado`       → ya hace `coalesce(fv.factura_id, p.factura_id)`:
--      prefiere el vínculo vigente y cae a la columna solo si no hay. Es el patrón
--      correcto y NO se toca; después del backfill el fallback queda de adorno.
--   3. `ent_salida_a_reverificar`  → su `factura_id` sale de la verificación
--      (congelado a propósito, es lo que se verificó), pero muestra
--      `p.factura_nombre` como etiqueta, que quedaría vieja si el vínculo cambia.
--      Se le pone el mismo coalesce, abajo. Es cosmético; si preferís no tocarla,
--      borrá ese segundo `create or replace` y el bloque sigue siendo válido.
--   4. `ent_pedido_factura_unico`  → índice único sobre `ent_pedido(factura_id)`.
--      NO se toca: sigue siendo la red que impide dos pedidos para la misma
--      factura de origen. ⚠️ Pero solo cubre la columna vieja — `ent_pedido_factura`
--      no tiene índice único (el esquema lo dice y lo valida la app). Anotado en §10.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── 0 · CANDADO · el backfill tiene que estar corrido ───────────────────
do $$
declare n int;
begin
  select count(*) into n
    from ent_pedido p
    join ent_alisto_vigente av on av.pedido_id = p.id
    left join ent_pedido_factura_vigente fv
           on fv.pedido_id = p.id and fv.anulado = false
   where p.origen = 'factura' and p.factura_id is not null
     and fv.pedido_id is null;
  if n > 0 then
    raise exception 'FALTA EL BACKFILL: hay % despacho(s) con alisto vigente y sin vínculo. Si cambio la vista ahora, esas facturas vuelven a "Por preparar" con el producto ya despachado. Corré VINCULOS_BACKFILL.sql primero. No se cambió nada.', n;
  end if;
end $$;

-- ── 1 · FOTO DE ANTES · cuántas facturas cuenta hoy la vista ───────────
select 'ANTES' as momento, count(*) as facturas_despachadas
  from v_ent_factura_despachada;

-- ── 2 · LA VISTA, LEYENDO LA FUENTE BUENA ──────────────────────────────
-- `factura_id` sale ahora de ent_pedido_factura_vigente. Se mantiene el
-- `anulado = false`: un vínculo anulado no despacha nada.
-- Se deja de exigir `p.origen = 'factura'`: con el vínculo en su propia tabla, lo
-- que hace que una factura esté despachada es TENER un vínculo vigente y un
-- alisto vigente, no cómo nació el pedido. Un despacho cargado a mano que después
-- se vincula a su factura también tiene que sacarla de la bandeja.
create or replace view v_ent_factura_despachada with (security_invoker = true) as
  select fv.factura_id,
         p.id            as pedido_id,
         av.preparado_en as confirmado_en,
         av.creado_por
    from ent_pedido p
    join ent_alisto_vigente        av on av.pedido_id = p.id
    join ent_pedido_factura_vigente fv on fv.pedido_id = p.id and fv.anulado = false;

grant select on v_ent_factura_despachada to authenticated;

-- ── 3 · La etiqueta de la lista de re-verificación (cosmético) ─────────
create or replace view ent_salida_a_reverificar with (security_invoker = true) as
  select s.id            as salida_id,
         s.salida_en,
         v.factura_id,
         v.verificado_en,
         av.pedido_id,
         p.cliente_nombre,
         coalesce(fv.factura_nombre, p.factura_nombre) as factura_nombre
    from ent_salida_verif_vigente v
    join ent_salida         s  on s.id = v.salida_id
    join ent_alisto_vigente av on av.alisto_id = s.alisto_id
    join ent_pedido         p  on p.id = av.pedido_id
    left join ent_pedido_factura_vigente fv
           on fv.pedido_id = p.id and fv.anulado = false
   where v.estado = 'vigente'
     and v.factura_id is not null
     and not exists (select 1 from ent_anulacion x
                      where x.entidad = 'salida' and x.entidad_id = s.id)
   order by s.salida_en desc;

grant select on ent_salida_a_reverificar to authenticated;

-- ── 4 · FOTO DE DESPUÉS · tiene que dar el MISMO número que el paso 1 ──
-- Si baja, alguna factura volvió a "Por preparar": hacer rollback y avisar.
select 'DESPUES' as momento, count(*) as facturas_despachadas
  from v_ent_factura_despachada;

-- ── 5 · CONTROL · ¿alguna factura aparece dos veces en la vista? ───────
-- Cero filas. `ent_pedido_factura` no tiene índice único, así que acá se ve.
select factura_id, count(*) as veces, array_agg(pedido_id order by pedido_id) as pedidos
  from v_ent_factura_despachada
 group by factura_id
having count(*) > 1;

commit;
