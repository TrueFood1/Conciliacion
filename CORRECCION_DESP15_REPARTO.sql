-- ════════════════════════════════════════════════════════════════════════
-- CORRECCIÓN · despacho 15 (Automercado, 25-ago) · reparto entre lotes
-- 28-ago-2026.  Pegar COMO UN SOLO BLOQUE en el editor SQL de Supabase.
--
-- ⚠️ EL REPARTO ES INFERIDO, NO RECORDADO. Daniel NO recuerda cuántas
-- unidades salieron de cada lote. Las 54/30 son la única repartición que la
-- aritmética señala como consistente con el conteo físico del 28-ago; nadie
-- las vio. Queda escrito acá y en el `creado_por` de las filas nuevas para
-- que dentro de un mes nadie lo lea como un dato medido.
--
-- QUÉ PASÓ. El despacho 15 tiene UNA línea de Pan Blanco de 84 uds (14 cajas)
-- cargada entera al lote `208 / 1-27`. El conteo físico del 28-ago dice que
-- parte de ese pan salió del `202 / 1-27`: al 202 le sobran unidades en el
-- sistema y al 208 le faltan, en la misma proporción y con signo opuesto.
--
-- QUÉ HACE ESTE BLOQUE. Parte esa única línea de lote en dos:
--     54 uds (9 cajas) → 202 / 1-27
--     30 uds (5 cajas) → 208 / 1-27
-- El total de la línea NO cambia: 54 + 30 = 84. No se mueve producto, no se
-- cambia la cantidad facturada ni la factura. Solo cambia DE QUÉ LOTE salió.
--
-- APPEND-ONLY, igual que `CORRECCION_DESP11_REVERTIR.sql`. No hay UPDATE ni
-- DELETE sobre `ent_alisto_lote`. El esquema no contempla revertir: se anula
-- el alisto vigente (y su salida) y se re-registra completo, con la misma
-- fecha, el mismo responsable y las mismas líneas. Las filas viejas SE QUEDAN,
-- con su reparto equivocado, que es la evidencia de que esto pasó.
--
-- LO QUE NO CIERRA, Y SE PUBLICA ASÍ A PROPÓSITO. Con 54/30 el 208 queda
-- exacto (teórico +2 contra 2 físicos disponibles) pero el 202 queda en −1
-- contra 1 físico: sobran 2 unidades sin explicar. Mover 52 en vez de 54
-- cerraría el 202 y dejaría el 208 descuadrado en 2 — el residuo existe en
-- las dos direcciones y no se sabe de cuál lado está. Se elige 54 porque son
-- 9 CAJAS ENTERAS, y una confusión al cargar un camión se hace en cajas, no
-- en unidades sueltas. Las 2 quedan abiertas, escritas, sin inventarles causa.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── 0 · CANDADOS ────────────────────────────────────────────────────────
-- Si algo no es exactamente como se describió arriba, no se inserta NADA.
do $$
declare
  v_alisto  bigint;
  v_n       int;
  v_uds     numeric;
  v_lotes   int;
  v_en208   numeric;
begin
  select av.alisto_id into v_alisto
    from ent_alisto_vigente av where av.pedido_id = 15;

  if v_alisto is null then
    raise exception 'El pedido 15 no tiene alisto vigente. No se insertó nada.';
  end if;

  if v_alisto <> 14 then
    raise exception 'El alisto vigente del pedido 15 es % y se esperaba 14. No se insertó nada.', v_alisto;
  end if;

  if exists (select 1 from ent_alisto a
              where a.id = v_alisto and a.creado_por like 'correccion-sql:28ago-desp15%') then
    raise exception 'YA CORREGIDO: el alisto vigente del pedido 15 ya es el re-registro. No se insertó nada.';
  end if;

  select count(*) into v_n
    from ent_alisto_linea l where l.alisto_id = v_alisto and l.producto_id = 451;
  if v_n <> 1 then
    raise exception 'Se esperaba UNA línea de Pan Blanco en el alisto %; hay %. No se insertó nada.', v_alisto, v_n;
  end if;

  -- La copia de las demás líneas se empareja por producto_id: si un producto
  -- estuviera repetido, el emparejamiento sería ambiguo y duplicaría lotes.
  select count(*) into v_n from (
    select l.producto_id from ent_alisto_linea l
     where l.alisto_id = v_alisto group by l.producto_id having count(*) > 1) x;
  if v_n > 0 then
    raise exception 'El alisto % tiene más de una línea del mismo producto: la copia sería ambigua. No se insertó nada.', v_alisto;
  end if;

  select coalesce(sum(alo.cant_uds),0), count(*),
         coalesce(sum(alo.cant_uds) filter (where alo.lote = '208 / 1-27'),0)
    into v_uds, v_lotes, v_en208
    from ent_alisto_lote  alo
    join ent_alisto_linea l on l.id = alo.linea_id
   where l.alisto_id = v_alisto and l.producto_id = 451;

  if v_lotes <> 1 or v_uds <> 84 or v_en208 <> 84 then
    raise exception 'Se esperaba UNA fila de lote con 84 uds en 208 / 1-27; hay % fila(s), % uds, % en el 208. No se insertó nada.',
      v_lotes, v_uds, v_en208;
  end if;
end $$;

-- ── 1 · ANULAR la salida vigente y el alisto vigente ────────────────────
-- La salida primero. Las dos filas quedan para siempre: son la evidencia.
insert into ent_anulacion (entidad, entidad_id, motivo, creado_por)
select 'salida', s.id,
       'Reparto entre lotes corregido (28-ago). La salida se re-registra junto con su '
       || 'alisto, con la MISMA fecha y hora: el pan salió, lo que estaba mal era de qué '
       || 'lote se descontó. Ver CORRECCION_DESP15_REPARTO.sql.',
       'correccion-sql:28ago-desp15-reparto-inferido'
  from ent_salida s
 where s.alisto_id = 14
   and not exists (select 1 from ent_anulacion x
                    where x.entidad = 'salida' and x.entidad_id = s.id);

insert into ent_anulacion (entidad, entidad_id, motivo, creado_por)
values ('alisto', 14,
        'Reparto entre lotes equivocado: las 84 uds de Pan Blanco estaban cargadas enteras '
        || 'al 208 / 1-27 y parte salió del 202 / 1-27. Se re-registra con 54 al 202 y 30 al '
        || '208. El reparto es INFERIDO de la aritmética del conteo del 28-ago, NO recordado '
        || 'por Daniel. Ver CORRECCION_DESP15_REPARTO.sql.',
        'correccion-sql:28ago-desp15-reparto-inferido');

-- ── 2 · RE-REGISTRO completo (alisto + líneas + lotes + salida) ─────────
-- Misma fecha, mismo responsable, mismas líneas. Lo único que cambia es el
-- reparto por lote de la línea de Pan Blanco.
with orig as (select * from ent_alisto where id = 14),
a as (
  insert into ent_alisto (pedido_id, responsable, creado_en, nota, creado_por)
  select o.pedido_id, o.responsable, o.creado_en,
         'RE-REGISTRO POR CORRECCIÓN DE REPARTO ENTRE LOTES. El alisto 14 de este mismo '
         || 'pedido se anuló el 28-ago porque cargaba las 84 uds de Pan Blanco enteras al '
         || 'lote 208 / 1-27, y el conteo físico del 28-ago muestra que parte salió del '
         || '202 / 1-27. Se re-registra con 54 uds (9 cajas) al 202 y 30 uds (5 cajas) al 208. '
         || '⚠️ EL REPARTO ES INFERIDO, NO RECORDADO: Daniel no recuerda cuántas de cada lote. '
         || '54/30 es la repartición que deja el 208 en cero contra el físico, y 54 son cajas '
         || 'enteras. Quedan 2 unidades sin explicar en el 202. La anulación NO se borra.',
         'correccion-sql:28ago-desp15-reparto-inferido'
    from orig o
  returning id
), li as (
  insert into ent_alisto_linea (alisto_id, producto_id, cant_uds, cant_uom)
  select a.id, l.producto_id, l.cant_uds, l.cant_uom
    from a, ent_alisto_linea l
   where l.alisto_id = 14
  returning id, producto_id
), lot as (
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden)
  -- (a) Pan Blanco: EL REPARTO NUEVO. 54 + 30 = 84, el total no cambia.
  select li.id, v.lote, v.cant_uds, v.orden
    from li
    join (values ('202 / 1-27', 54::numeric, 0),
                 ('208 / 1-27', 30::numeric, 1)) as v(lote, cant_uds, orden)
      on li.producto_id = 451
  union all
  -- (b) el resto de las líneas del alisto: copia fiel, lote por lote.
  select li.id, alo.lote, alo.cant_uds, alo.orden
    from li
    join ent_alisto_linea lo  on lo.alisto_id = 14 and lo.producto_id = li.producto_id
    join ent_alisto_lote  alo on alo.linea_id = lo.id
   where li.producto_id <> 451
)
-- La salida, con su hora original. Si el alisto 14 no tenía salida vigente,
-- este insert no produce ninguna fila y el pedido queda solo PREPARADO.
insert into ent_salida (alisto_id, salida_en, nota, creado_por)
select a.id, s.salida_en,
       'RE-REGISTRO junto con su alisto (28-ago). La fecha y la hora son las ORIGINALES: '
       || 'la salida ocurrió, lo que se corrigió es de qué lote se descontó.',
       'correccion-sql:28ago-desp15-reparto-inferido'
  from a
  join ent_salida s on s.alisto_id = 14
 where exists (select 1 from ent_anulacion x
                where x.entidad = 'salida' and x.entidad_id = s.id
                  and x.creado_por = 'correccion-sql:28ago-desp15-reparto-inferido');

-- ════════════════════════════════════════════════════════════════════════
-- VERIFICACIÓN.  Un solo resultado, columna `bloque`. Leer ANTES del commit.
-- ════════════════════════════════════════════════════════════════════════
with a as (select id, fecha, corte from ent_ancla),
mov as (
  select alo.lote as lote, -sum(alo.cant_uds) as delta
    from ent_alisto_lote    alo
    join ent_alisto_linea   ali on ali.id       = alo.linea_id
    join ent_alisto_vigente av  on av.alisto_id = ali.alisto_id
   where ali.producto_id = 451 and (alo.lote like '208%' or alo.lote like '202%')
   group by alo.lote
  union all
  select cl.lote, sum(cl.uds)
    from ent_conteo_linea cl
   where cl.conteo_id = (select id from a) and cl.producto_id = 451
     and (cl.lote like '208%' or cl.lote like '202%')
   group by cl.lote
  union all
  select dl.lote, sum(dl.cant_uds)
    from ent_devolucion_linea   dl
    join ent_devolucion_vigente dv on dv.devolucion_id = dl.devolucion_id
   where dl.producto_id = 451 and (dl.lote like '208%' or dl.lote like '202%')
   group by dl.lote),
teo as (select lote, sum(delta) as saldo from mov group by lote),
sinsalir as (
  select alo.lote as lote, sum(alo.cant_uds) as uds
    from ent_alisto_lote    alo
    join ent_alisto_linea   ali on ali.id       = alo.linea_id
    join ent_alisto_vigente av  on av.alisto_id = ali.alisto_id
   where ali.producto_id = 451 and (alo.lote like '208%' or alo.lote like '202%')
     and not exists (select 1 from ent_salida_vigente sv where sv.alisto_id = av.alisto_id)
   group by alo.lote)

select '1 · ALISTO VIGENTE DEL PEDIDO 15'::text as bloque,
       'debe ser el NUEVO, con preparado_en igual al original'::text as control,
       av.alisto_id::text as valor, al.creado_por as detalle
  from ent_alisto_vigente av join ent_alisto al on al.id = av.alisto_id
 where av.pedido_id = 15
union all
select '2 · REPARTO NUEVO', 'debe decir 202→54 y 208→30 (suman 84)',
       alo.lote || ' → ' || alo.cant_uds::text, 'orden ' || alo.orden::text
  from ent_alisto_lote  alo
  join ent_alisto_linea ali on ali.id = alo.linea_id
  join ent_alisto_vigente av on av.alisto_id = ali.alisto_id
 where av.pedido_id = 15 and ali.producto_id = 451
union all
select '3 · SALDO 202', 'teórico DEBE dar −1 · físico contado = 1 · difieren en 2',
       coalesce((select saldo from teo where lote like '202%'),0)::text,
       'apartado sin salir: ' || coalesce((select uds from sinsalir where lote like '202%'),0)::text
union all
select '4 · SALDO 208', 'teórico DEBE dar 2 · físico disponible = 50 − 48 (desp 33) = 2 · CUADRA',
       coalesce((select saldo from teo where lote like '208%'),0)::text,
       'apartado sin salir: ' || coalesce((select uds from sinsalir where lote like '208%'),0)::text
union all
select '5 · LA EVIDENCIA SE QUEDA', 'las anulaciones NO se borran',
       an.entidad || ' ' || an.entidad_id::text, left(an.motivo, 70)
  from ent_anulacion an
 where an.creado_por = 'correccion-sql:28ago-desp15-reparto-inferido'
 order by 1, 3;

-- ⚠️ SI EL BLOQUE 2 NO DICE 202→54 Y 208→30, O SI EL 4 NO DA 2: hacer
--    ROLLBACK en vez de COMMIT. Nada de lo de arriba queda escrito hasta el
--    commit, y las filas viejas siguen intactas de todos modos.
commit;
