-- ════════════════════════════════════════════════════════════════════════
-- PRUEBAS · PAGO DE QUINCENA — UNA SOLA CONSULTA, UNA SOLA TABLA
-- 3-oct-2026. Va DESPUES de PERSONAL_PAGO_QUINCENA.sql, ya pegado.
-- Version de una tabla de PRUEBAS_PAGO_QUINCENA.sql (mismas pruebas).
--
-- POR QUE EN UNA SOLA. El SQL Editor de Supabase muestra SOLO el resultado de
-- la ULTIMA sentencia. Con cinco `select` sueltos hay que correrlos de a uno y
-- cuatro resultados se pierden de vista — que es justo como se saltea una
-- prueba sin querer. Aca sale todo junto o no sale nada.
--
-- SOLO LECTURA: una sentencia, un `select`. Sin insert/update/delete/DDL, sin
-- transaccion y sin rollback.
--
-- ⚠️ NINGUN MONTO. Todo sale como booleano, conteo o texto. El resultado se
-- puede pegar en un chat o en la bitacora sin que viaje el salario de nadie.
--
-- ⚠️ "SIN PROBAR" NO ES "OK", Y ES LO MAS IMPORTANTE DE ESTE ARCHIVO.
-- `bool_and` sobre cero filas devuelve NULL, y un NULL en una columna de
-- veredictos se lee como un pase. Peor en una tabla unificada, donde el ojo
-- busca la palabra "FALLA" y da por bueno todo lo demas. Por eso cada prueba
-- lleva su PROPIO contador de filas que la ejercitan (`filas`), y el veredicto
-- dice SIN PROBAR cuando ese contador es 0. Una prueba sin casos no se tapa:
-- se reporta, y se decide si hace falta un permiso real para cubrirla.
--
-- ⚠️ LOS DIAS HABILES SE RECUENTAN ACA, directo de rrhh_permiso y rrhh_feriado,
-- SIN pasar por v_rrhh_permiso_dia. Contarlos con la misma vista que se esta
-- probando daria `true` siempre, incluso con el bug adentro.
-- ════════════════════════════════════════════════════════════════════════

with
-- ── recuento independiente de dias habiles, por permiso y por quincena ──
recuento as (
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
-- El ultimo dia de la quincena se DERIVA de su nombre, no se saca de la vista:
-- si la vista no tiene filas para esa quincena, el join la perderia y la prueba
-- quedaria en silencio sin que nadie lo note.
fin_q as (
  select r.*,
         case when right(r.quincena,2) = 'Q1'
              then to_date(left(r.quincena,7) || '-01','YYYY-MM-DD') + 14
              else (date_trunc('month', to_date(left(r.quincena,7) || '-01','YYYY-MM-DD'))
                    + interval '1 month - 1 day')::date
         end as quincena_fin
    from recuento r
),
sal as (
  select f.*,
         (select sa.salario_mensual from rrhh_salario sa
           where sa.persona_id = f.persona_id and sa.vigente_desde <= f.quincena_fin
           order by sa.vigente_desde desc, sa.creado_en desc limit 1) as sm
    from fin_q f
),
j as (
  select s.*, v.cantidad, v.unidad, v.monto
    from sal s
    left join (select d.quincena, d.persona_id, d.ref_id as permiso_id,
                      d.cantidad, d.unidad, d.monto
                 from v_rrhh_pago_detalle d
                where d.concepto = 'descuento_permiso') v
      on v.permiso_id = s.permiso_id and v.quincena = s.quincena
   where s.sm is not null
),
-- ── inventario: que casos EXISTEN hoy ───────────────────────────────────
inv as (
  select
    count(*)                                                   as aprobados,
    count(*) filter (where modalidad_descuento = 'descuento')  as c_desc,
    count(*) filter (where modalidad_descuento = 'reposicion') as c_repo,
    count(*) filter (where modalidad_descuento is null)        as c_nula,
    count(*) filter (where modalidad_descuento = 'descuento'
                       and horas is null)                      as c_dias,
    count(*) filter (where modalidad_descuento = 'descuento'
                       and horas is not null)                  as c_horas,
    count(*) filter (where modalidad_descuento = 'descuento'
      and not exists (
        select 1 from generate_series(0, (fecha_fin - fecha_inicio)) g(i)
         where extract(isodow from (fecha_inicio + g.i)) <= 5
           and not exists (select 1 from rrhh_feriado f
                            where daterange(f.fecha, coalesce(f.fecha_fin, f.fecha), '[]')
                                  @> (fecha_inicio + g.i))))   as c_nohabil
    from rrhh_permiso where estado = 'aprobado'
),
-- ── las pruebas: cada una con su booleano Y su contador de filas ────────
t as (
  select
    count(*) filter (where horas is null)                               as n_dias,
    bool_and(cantidad = habiles_yo) filter (where horas is null)        as b_dias,

    count(*) filter (where horas is null and habiles_yo > 0)            as n_dmonto,
    bool_and(abs(monto + (habiles_yo * sm / rrhh_param('dias_mes_tarifa', quincena_fin))) < 0.01)
      filter (where horas is null and habiles_yo > 0)                   as b_dmonto,

    count(*) filter (where horas is not null and habiles_yo > 0)        as n_horas,
    bool_and(abs(monto + (horas * sm / rrhh_param('dias_mes_tarifa', quincena_fin)
                                    / rrhh_param('jornada_horas',   quincena_fin))) < 0.01)
      filter (where horas is not null and habiles_yo > 0)               as b_horas,

    count(*) filter (where habiles_yo = 0)                              as n_nohabil,
    bool_and(coalesce(cantidad,0) = 0 and coalesce(monto,0) = 0)
      filter (where habiles_yo = 0)                                     as b_nohabil,

    count(*)                                                            as n_todas,
    bool_and(unidad = case when horas is null then 'dias' else 'horas' end) as b_unidad,
    bool_and(coalesce(monto,0) <= 0)                                    as b_nosuma,
    bool_and(unidad is not null)                                        as b_hay_renglon
    from j
),
-- ── la reposicion y lo no aprobado no pueden dejar renglon ──────────────
r3 as (
  select
    (select count(*) from v_rrhh_pago_detalle d
      where d.concepto = 'descuento_permiso'
        and d.ref_id in (select id from rrhh_permiso where modalidad_descuento = 'reposicion')) as n_repo,
    (select count(*) from v_rrhh_pago_detalle d
      where d.concepto = 'descuento_permiso'
        and d.ref_id in (select id from rrhh_permiso where modalidad_descuento is null))        as n_nula,
    (select count(*) from v_rrhh_pago_detalle d
      where d.concepto = 'descuento_permiso'
        and d.ref_id in (select id from rrhh_permiso where estado <> 'aprobado'))               as n_noap
),
-- ── el control de la pantalla: la columna tiene que sumar al total ──────
r5 as (
  select count(*) as n, bool_and(abs(p.final - x.suma) <= 1) as b
    from v_rrhh_pago p
    join (select quincena, persona_id, sum(monto) as suma
            from v_rrhh_pago_detalle group by quincena, persona_id) x
      on x.quincena = p.quincena and x.persona_id = p.persona_id
)
-- ── LA TABLA ────────────────────────────────────────────────────────────
-- `orden` esta para ordenar y para citar una fila sin ambiguedad.
-- `veredicto`: OK · FALLA · SIN PROBAR (no hay casos) · INFO (no es una prueba).
select * from (
  select 0 as orden, 'permisos aprobados'::text as prueba,
         inv.aprobados::text as resultado,
         'INFO'::text as veredicto, inv.aprobados as filas from inv
  union all select 1, 'de esos, con descuento',   inv.c_desc::text,
         case when inv.c_desc  > 0 then 'INFO' else 'SIN CASOS' end, inv.c_desc  from inv
  union all select 2, 'de esos, con reposicion',  inv.c_repo::text,
         case when inv.c_repo  > 0 then 'INFO' else 'SIN CASOS' end, inv.c_repo  from inv
  union all select 3, 'de esos, sin modalidad',   inv.c_nula::text, 'INFO', inv.c_nula from inv
  union all select 4, 'descuento por dias completos', inv.c_dias::text,
         case when inv.c_dias  > 0 then 'INFO' else 'SIN CASOS' end, inv.c_dias  from inv
  union all select 5, 'descuento por horas',      inv.c_horas::text,
         case when inv.c_horas > 0 then 'INFO' else 'SIN CASOS' end, inv.c_horas from inv
  union all select 6, 'descuento con todos los dias NO habiles', inv.c_nohabil::text,
         case when inv.c_nohabil > 0 then 'INFO' else 'SIN CASOS' end, inv.c_nohabil from inv

  -- P1 · dias
  union all select 10, 'P1 dias: la cantidad es mi recuento de habiles',
         coalesce(t.b_dias::text,'—'),
         case when t.n_dias = 0 then 'SIN PROBAR' when t.b_dias then 'OK' else 'FALLA' end,
         t.n_dias from t
  union all select 11, 'P1 dias: monto = -(dias x salario/30)',
         coalesce(t.b_dmonto::text,'—'),
         case when t.n_dmonto = 0 then 'SIN PROBAR' when t.b_dmonto then 'OK' else 'FALLA' end,
         t.n_dmonto from t
  -- P2 · horas
  union all select 12, 'P2 horas: monto = -(horas x salario/30/8)',
         coalesce(t.b_horas::text,'—'),
         case when t.n_horas = 0 then 'SIN PROBAR' when t.b_horas then 'OK' else 'FALLA' end,
         t.n_horas from t
  -- P4 · dia cerrado
  union all select 13, 'P4 ningun dia habil: cantidad y monto en 0',
         coalesce(t.b_nohabil::text,'—'),
         case when t.n_nohabil = 0 then 'SIN PROBAR' when t.b_nohabil then 'OK' else 'FALLA' end,
         t.n_nohabil from t
  -- invariantes que valen para todo renglon de descuento
  union all select 14, 'la unidad sigue a horas (dias / horas)',
         coalesce(t.b_unidad::text,'—'),
         case when t.n_todas = 0 then 'SIN PROBAR' when t.b_unidad then 'OK' else 'FALLA' end,
         t.n_todas from t
  union all select 15, 'un descuento nunca SUMA (monto <= 0)',
         coalesce(t.b_nosuma::text,'—'),
         case when t.n_todas = 0 then 'SIN PROBAR' when t.b_nosuma then 'OK' else 'FALLA' end,
         t.n_todas from t
  union all select 16, 'la vista deja renglon para cada permiso de descuento',
         coalesce(t.b_hay_renglon::text,'—'),
         case when t.n_todas = 0 then 'SIN PROBAR' when t.b_hay_renglon then 'OK' else 'FALLA' end,
         t.n_todas from t

  -- P3 · lo que NO tiene que descontar (contadores: el esperado es 0)
  union all select 20, 'P3 reposicion no deja renglon (espera 0)', r3.n_repo::text,
         case when r3.n_repo = 0 then 'OK' else 'FALLA' end, r3.n_repo from r3
  union all select 21, 'sin modalidad no deja renglon (espera 0)', r3.n_nula::text,
         case when r3.n_nula = 0 then 'OK' else 'FALLA' end, r3.n_nula from r3
  union all select 22, 'un permiso NO aprobado no deja renglon (espera 0)', r3.n_noap::text,
         case when r3.n_noap = 0 then 'OK' else 'FALLA' end, r3.n_noap from r3

  -- P5 · el control de la pantalla
  union all select 30, 'P5 el desglose suma al total (± 1 colon)',
         coalesce(r5.b::text,'—'),
         case when r5.n = 0 then 'SIN PROBAR' when r5.b then 'OK' else 'FALLA' end,
         r5.n from r5
) z
order by z.orden;
