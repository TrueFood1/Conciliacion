-- ════════════════════════════════════════════════════════════════════════
-- DIAGNOSTICO DEL ANCLA · 19-ago-2026 · SOLO LECTURA
-- Ningun statement escribe nada: son cinco SELECT. Se puede pegar entero.
-- NO TOCA ODOO.
--
-- Por que existe: la anon key no puede leer NINGUNA fila de estas tablas (el RLS
-- es `to authenticated`, y con la anon todas devuelven 0 filas). Lo unico que se
-- puede medir desde afuera es SI EL OBJETO EXISTE, nunca que tiene adentro.
-- Estas cinco consultas son lo que hace falta para decidir si los bloques 3 y 4
-- van o se sacan.
-- ════════════════════════════════════════════════════════════════════════

-- ── 1 · TODOS LOS CONTEOS, con su corte y cuantas lineas trae cada uno ──
-- Lo que hay que mirar: `corte` (NO `creado_en`) — el corte es la linea divisoria
-- de los saldos. Y `creado_por`: 'carga-sql' significa que entro por el .sql;
-- un email significa que se capturo desde la pantalla.
select c.id,
       c.fecha,
       c.corte,
       c.responsable,
       c.creado_en,
       c.creado_por,
       (select count(*) from ent_conteo_linea l where l.conteo_id = c.id) as lineas
  from ent_conteo c
 order by c.id;

-- ── 2 · TODAS LAS FILAS DE ANCLA, en orden ─────────────────────────────
select a.id, a.conteo_id, a.anulada, a.creado_en, a.creado_por, a.nota
  from ent_conteo_ancla a
 order by a.id;

-- ── 3 · QUIEN GANA HOY ─────────────────────────────────────────────────
-- ent_conteo_estado = la fila mas reciente de cada conteo (si anulada=false, esta
-- confirmado). ent_ancla = el conteo confirmado mas reciente por fecha.
select * from ent_conteo_estado order by conteo_id;
select * from ent_ancla;

-- ── 4 · LA PIZZA DEL CONTEO ANCLADO ────────────────────────────────────
-- La pregunta decisiva: ¿el 183 quedo en '183 / 1-27' o en '183 / 12-26'?
-- La correccion del 183 se hizo en el ARCHIVO el 18-ago. Si el conteo se guardo
-- el 16-ago, entro con la version vieja.
select producto_id, lote, cajas, sueltas, uds
  from ent_conteo_linea
 where conteo_id = (select id from ent_ancla)
   and producto_id = 472
 order by lote;

-- ── 5 · EL DIFF COMPLETO contra CONTEO_14AGO.sql ───────────────────────
-- Compara las 33 lineas del conteo ANCLADO contra las 33 del archivo corregido.
-- `origen` dice de que lado esta la diferencia.
-- ⚠️ TIENE QUE DAR 0 FILAS si son equivalentes. Cualquier fila que salga es una
-- diferencia real de lote o de cantidad.
with archivo(producto_id, lote, cajas, sueltas, uds) as (
  values
      (451, '223 / 2-27', 20, 1, 121),
      (451, '195 / 1-27', 10, 4, 64),
      (451, '224 / 2-27', 21, 0, 126),
      (451, '215 / 2-27', 24, 0, 144),
      (451, '217 / 2-27', 21, 0, 126),
      (451, '208 / 1-27', 21, 0, 126),
      (451, '202 / 1-27', 21, 0, 126),
      (451, '201 / 1-27', 9, 0, 54),
      (452, '225 / 2-27', 28, 0, 168),
      (452, '209 / 1-27', 34, 1, 205),
      (452, '176 / 12-26', 6, 2, 38),
      (452, '218 / 2-27', 27, 3, 165),
      (452, '126 / 11-26', 2, 0, 12),
      (453, '216 / 2-27', 15, 0, 360),
      (453, '197 / 1-27', 15, 0, 360),
      (453, '221 / 2-27', 15, 0, 360),
      (453, '203 / 1-27', 15, 0, 360),
      (453, '204 / 1-27', 15, 0, 360),
      (453, '182 / 12-26', 0, 2, 8),
      (503, '212 / 1-27', 28, 0, 672),
      (503, '175 / 12-26', 24, 0, 576),
      (503, '191 / 1-27', 24, 0, 576),
      (503, '168 / 12-26', 0, 6, 24),
      (472, '211 / 1-27', 19, 4, 236),
      (472, '190 / 1-27', 16, 0, 192),
      (472, '183 / 1-27', 4, 0, 48),
      (472, '120 / 10-26', 0, 4, 8),
      (472, '146 / 11-26', 0, 3, 6),
      (472, '163 / 12-26', 0, 3, 6),
      (472, '82 / 9-26', 0, 2, 4),
      (472, '107 / 10-26', 0, 1, 2),
      (519, '205 / 1-27', 6, 0, 72),
      (519, '226 / 2-27', 13, 2, 158)
), guardado as (
  select producto_id, lote, cajas, sueltas, uds
    from ent_conteo_linea
   where conteo_id = (select id from ent_ancla)
)
select 'solo en el ANCLA (Supabase)' as origen, * from (
  select producto_id, lote, cajas, sueltas, uds from guardado
  except
  select producto_id, lote, cajas, sueltas, uds from archivo) a
union all
select 'solo en el ARCHIVO corregido', * from (
  select producto_id, lote, cajas, sueltas, uds from archivo
  except
  select producto_id, lote, cajas, sueltas, uds from guardado) b
order by 1, 2, 3;
