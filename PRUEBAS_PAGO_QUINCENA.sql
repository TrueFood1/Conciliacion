-- ════════════════════════════════════════════════════════════════════════
-- PRUEBAS · PAGO DE QUINCENA   (SOLO LECTURA · se corre en el SQL Editor)
-- 3-oct-2026. Va DESPUES de PERSONAL_PAGO_QUINCENA.sql, ya pegado.
--
-- POR QUE EXISTE. `esquema_check.py` y `sonda_columnas.py` prueban que los
-- objetos EXISTEN y que `anon` no los lee. Ninguno de los dos prueba que el
-- NUMERO este bien, y es el numero contra el que se transfiere.
--
-- NO ESCRIBE NADA: son cuatro `select`. No hace falta transaccion ni rollback.
--
-- ⚠️ NO IMPRIME NINGUN MONTO, a proposito. Todo sale como booleano o como
-- conteo. Es la unica forma de dejar el resultado pegado en un chat o en la
-- bitacora sin que viaje el salario de nadie.
--
-- ⚠️ LA PRUEBA 0 VA PRIMERA Y NO SE SALTEA. Dice QUE SE PUEDE PROBAR con los
-- datos que hay hoy. Un `true` sobre cero filas no prueba nada —`bool_and` de
-- un conjunto vacio da NULL, y un NULL leido con prisa parece un pase— asi que
-- si la prueba 0 dice que falta un caso, ese caso queda SIN PROBAR y hay que
-- decirlo, no inventar un permiso para que el chequeo se ponga verde.
-- ════════════════════════════════════════════════════════════════════════

-- ── PRUEBA 0 · QUE HAY PARA PROBAR ──────────────────────────────────────
-- Cuenta los permisos aprobados por forma. Cada cero de aca es una prueba de
-- abajo que no se puede correr todavia.
select
  count(*)                                                          as aprobados,
  count(*) filter (where modalidad_descuento = 'descuento')         as con_descuento,
  count(*) filter (where modalidad_descuento = 'reposicion')        as con_reposicion,
  count(*) filter (where modalidad_descuento is null)               as sin_modalidad,
  count(*) filter (where modalidad_descuento = 'descuento'
                     and horas is null)                             as descuento_por_dias,
  count(*) filter (where modalidad_descuento = 'descuento'
                     and horas is not null)                         as descuento_por_horas,
  -- El caso 4: un permiso de descuento cuyos dias son TODOS no habiles
  -- (fin de semana, feriado o cierre). Si da 0, la prueba 4 no se puede correr.
  count(*) filter (where modalidad_descuento = 'descuento'
    and not exists (
      select 1 from generate_series(0, (fecha_fin - fecha_inicio)) g(i)
       where extract(isodow from (fecha_inicio + g.i)) <= 5
         and not exists (select 1 from rrhh_feriado f
                          where daterange(f.fecha, coalesce(f.fecha_fin, f.fecha), '[]')
                                @> (fecha_inicio + g.i))))          as descuento_todo_no_habil
  from rrhh_permiso
 where estado = 'aprobado';


-- ── PRUEBAS 1, 2 y 4 · LA ARITMETICA ────────────────────────────────────
-- Los dias habiles se vuelven a contar ACA, directo de rrhh_permiso y
-- rrhh_feriado, SIN pasar por v_rrhh_permiso_dia. Si se contaran con la misma
-- vista que se esta probando, la prueba seria una tautologia: coincidiria
-- siempre, incluso con el bug adentro.
with recuento as (
  select pm.id as permiso_id, pm.persona_id, pm.horas,
         rrhh_quincena(pm.fecha_inicio + g.i) as quincena,
         count(*) filter (
           where extract(isodow from (pm.fecha_inicio + g.i)) <= 5
             and not exists (select 1 from rrhh_feriado f
                              where daterange(f.fecha, coalesce(f.fecha_fin, f.fecha), '[]')
                                    @> (pm.fecha_inicio + g.i))) as habiles_yo
    from rrhh_permiso pm
    cross join generate_series(0, (pm.fecha_fin - pm.fecha_inicio)) g(i)
   where pm.estado = 'aprobado' and pm.modalidad_descuento = 'descuento'
   group by pm.id, pm.persona_id, pm.horas, rrhh_quincena(pm.fecha_inicio + g.i)
),
vista as (
  select d.quincena, d.persona_id, d.ref_id as permiso_id,
         d.cantidad, d.unidad, d.tarifa, d.monto
    from v_rrhh_pago_detalle d
   where d.concepto = 'descuento_permiso'
),
sal as (
  select r.permiso_id, r.quincena, r.persona_id, r.horas, r.habiles_yo,
         q.fin as quincena_fin,
         (select sa.salario_mensual from rrhh_salario sa
           where sa.persona_id = r.persona_id and sa.vigente_desde <= q.fin
           order by sa.vigente_desde desc, sa.creado_en desc limit 1) as sm
    from recuento r
    join (select quincena, max(fin) as fin from v_rrhh_pago_detalle group by quincena) q
      on q.quincena = r.quincena
),
j as (
  select s.*, v.cantidad, v.unidad, v.tarifa, v.monto
    from sal s
    left join vista v on v.permiso_id = s.permiso_id and v.quincena = s.quincena
   where s.sm is not null
)
select
  count(*)                                                      as renglones_comparados,
  -- 1 · dias: la cantidad de la vista es mi recuento independiente de habiles
  bool_and(case when horas is null then cantidad = habiles_yo else true end)
                                                                as p1_dias_cuadran,
  -- 1 · dias: monto = -(dias x salario/30). Se compara la RAZON, no el monto.
  bool_and(case when horas is null and habiles_yo > 0
                then abs(monto + (habiles_yo * sm / rrhh_param('dias_mes_tarifa', quincena_fin))) < 0.01
                else true end)                                  as p1_monto_cuadra,
  -- 2 · horas: monto = -(horas x salario/30/8)
  bool_and(case when horas is not null and habiles_yo > 0
                then abs(monto + (horas * sm / rrhh_param('dias_mes_tarifa', quincena_fin)
                                              / rrhh_param('jornada_horas',   quincena_fin))) < 0.01
                else true end)                                  as p2_horas_cuadran,
  -- 4 · ningun dia habil -> cantidad 0 y monto 0
  bool_and(case when habiles_yo = 0 then coalesce(cantidad,0) = 0 and coalesce(monto,0) = 0
                else true end)                                  as p4_no_habil_da_cero,
  -- la unidad tiene que seguir a horas, y el descuento nunca puede SUMAR
  bool_and(unidad = case when horas is null then 'dias' else 'horas' end)
                                                                as unidad_correcta,
  bool_and(coalesce(monto,0) <= 0)                              as nunca_suma,
  count(*) filter (where habiles_yo = 0)                        as de_esos_no_habiles
  from j;


-- ── PRUEBA 3 · LA REPOSICION NO RESTA ───────────────────────────────────
-- Tiene que dar 0: ni un renglon de descuento para un permiso marcado
-- 'reposicion'. Y de paso, lo mismo para los que quedaron sin modalidad.
select
  (select count(*) from v_rrhh_pago_detalle d
    where d.concepto = 'descuento_permiso'
      and d.ref_id in (select id from rrhh_permiso
                        where modalidad_descuento = 'reposicion'))   as p3_reposicion_debe_ser_0,
  (select count(*) from v_rrhh_pago_detalle d
    where d.concepto = 'descuento_permiso'
      and d.ref_id in (select id from rrhh_permiso
                        where modalidad_descuento is null))          as sin_modalidad_debe_ser_0,
  -- Y que un permiso NO aprobado nunca descuente.
  (select count(*) from v_rrhh_pago_detalle d
    where d.concepto = 'descuento_permiso'
      and d.ref_id in (select id from rrhh_permiso
                        where estado <> 'aprobado'))                 as no_aprobado_debe_ser_0;


-- ── PRUEBA 5 · QUE LA COLUMNA SUME (el control de la pantalla) ──────────
-- La pantalla suma los renglones redondeados y compara contra `final`. Esto es
-- lo mismo del lado de la base: si aparta mas de un colon, falta un renglon.
select count(*) as filas,
       bool_and(abs(p.final - d.suma) <= 1) as p5_detalle_suma_al_total
  from v_rrhh_pago p
  join (select quincena, persona_id, sum(monto) as suma
          from v_rrhh_pago_detalle group by quincena, persona_id) d
    on d.quincena = p.quincena and d.persona_id = p.persona_id;
