-- ════════════════════════════════════════════════════════════════════════
-- ¿El bug del lote repetido dejó daño en los conteos ya guardados?
-- 2-sep-2026 · SOLO LECTURA (tres SELECT, nada que escriba)
--
-- QUÉ PASABA (medido sobre las funciones reales, no supuesto):
-- `_clAgregar` dejaba agregar a mano un lote que YA estaba en la lista. Quedaban
-- DOS filas en pantalla apuntando a la MISMA clave de `_clVal` ('producto|lote').
-- Las dos se dibujan con el mismo valor, y escribir en cualquiera de las dos
-- REEMPLAZA el valor de la otra — no suma. Peor: vaciar la fila agregada BORRA la
-- clave entera (`_clSet` hace `delete _clVal[k]` cuando cajas y sueltas quedan en
-- blanco), y el lote desaparece de `_clLeer()`, que es lo que se inserta.
--
-- ⚠️ LO QUE ESTO SIGNIFICA PARA ESTAS CONSULTAS, DICHO ANTES DE CORRERLAS:
--   · Un lote REPETIDO en un mismo conteo NO puede venir de este bug. `_clLeer()`
--     recorre las CLAVES de `_clVal`, y dos filas de pantalla comparten una sola
--     clave → una sola línea insertada. Si la consulta 1 devuelve algo, es OTRO
--     problema, no éste, y hay que mirarlo aparte.
--   · Una línea en CERO tampoco: `_clLeer()` salta las filas sin cajas ni sueltas.
--     Si la 2 devuelve algo, la línea no salió de esta pantalla.
--   · EL DAÑO REAL DE ESTE BUG NO DEJA RASTRO EN LA TABLA. Un lote que se contó y
--     se borró no está: no hay fila que buscar, y un valor pisado (7 donde iban 10)
--     es un número plausible. Las consultas 1 y 2 descartan las dos formas
--     detectables; la 3 da el material para revisar a ojo contra el congelador.
--     Si las tres salen limpias, lo honesto es decir "no encontré daño", no
--     "no hubo daño".
-- ════════════════════════════════════════════════════════════════════════

-- ── 1 · ¿Algún conteo con el MISMO lote repetido para el mismo producto? ──
-- Esperado: 0 filas.
select
  l.conteo_id                                  as conteo,
  c.fecha,
  c.responsable,
  l.producto_id                                as producto,
  l.lote,
  count(*)                                     as veces,
  string_agg(l.cajas || ' cj + ' || l.sueltas || ' su = ' || l.uds || ' u',
             '  |  ' order by l.id)            as valores
from ent_conteo_linea l
join ent_conteo c on c.id = l.conteo_id
group by l.conteo_id, c.fecha, c.responsable, l.producto_id, l.lote
having count(*) > 1
order by c.fecha desc, l.producto_id, l.lote;


-- ── 2 · ¿Alguna línea en blanco/cero donde debería haber dato? ──
-- Esperado: 0 filas. `_clLeer()` no inserta líneas sin nada anotado, así que una
-- fila en cero significa que entró por otro camino (pegado a mano, corrección SQL).
select
  l.conteo_id   as conteo,
  c.fecha,
  c.responsable,
  l.producto_id as producto,
  l.lote,
  l.cajas,
  l.sueltas,
  l.uds,
  l.creado_en
from ent_conteo_linea l
join ent_conteo c on c.id = l.conteo_id
where (coalesce(l.cajas,0) = 0 and coalesce(l.sueltas,0) = 0)
   or coalesce(l.uds,0) = 0
order by c.fecha desc, l.producto_id, l.lote;


-- ── 3 · Material para revisar a ojo: lotes que aparecen y desaparecen ──
-- Un lote contado en un conteo y AUSENTE en el siguiente del mismo producto.
-- ⚠️ Esto NO es una alarma: lo normal es que un lote se agote y deje de contarse.
-- Sirve para mirar los casos raros — un lote que desaparece y VUELVE a aparecer
-- después es el patrón que dejaría un borrado accidental.
with conteos as (
  select id, fecha,
         row_number() over (order by fecha, id) as n
  from ent_conteo
),
lineas as (
  select c.n, c.id as conteo_id, c.fecha, l.producto_id, l.lote, l.uds
  from ent_conteo_linea l
  join conteos c on c.id = l.conteo_id
)
select
  a.conteo_id      as conteo,
  a.fecha,
  a.producto_id    as producto,
  a.lote,
  a.uds            as uds_en_ese_conteo,
  'ausente en el conteo siguiente, presente en uno posterior' as patron
from lineas a
where not exists (                      -- no está en el conteo inmediatamente siguiente
        select 1 from lineas b
        where b.n = a.n + 1
          and b.producto_id = a.producto_id
          and b.lote = a.lote)
  and exists (                          -- pero reaparece más adelante
        select 1 from lineas d
        where d.n > a.n + 1
          and d.producto_id = a.producto_id
          and d.lote = a.lote)
order by a.fecha desc, a.producto_id, a.lote;
