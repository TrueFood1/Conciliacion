-- SOLO LECTURA · DIAGNOSTICO_DANIELA.sql · no escribe nada · SIN MONTOS
-- ════════════════════════════════════════════════════════════════════════
-- ¿QUE TIENE DANIELA QUE DANIEL Y NEY NO TENGAN?
-- 15-oct-2026. Una sola sentencia, una sola tabla, una fila por persona.
--
-- ⚠️ NO MUESTRA NI UN MONTO. Ni salarios, ni el monto de los ajustes. De los
-- ajustes sale la FECHA y si suma o resta, nunca cuanto. Se puede pegar la tabla
-- en un chat sin pensarlo dos veces, con una excepcion: la columna `ajustes_det`
-- trae la NOTA del ajuste, que es texto libre que escribio una socia («adelanto»,
-- «prestamo»…). Si alguna nota dice algo que no corresponda compartir, recortar
-- esa celda antes de reenviar.
--
-- ⚠️ Se corre como `postgres` desde el SQL Editor: la RLS no recorta y se ve al
-- equipo entero sin impersonar a nadie.
--
-- LA HIPOTESIS QUE VIENE A CONFIRMAR O DESCARTAR. El pegado 5 toma el salario
-- vigente el ULTIMO dia de la quincena, para la base y para la tarifa, y NO
-- prorratea. Esta escrito ahi como simplificacion consciente: un aumento con
-- vigencia el dia 20 paga TODA la Q2 al valor nuevo. Si Daniela tiene un
-- `vigente_desde` que cae ADENTRO de una quincena —no el dia 1 ni el 16— esa es
-- la explicacion mas probable de que su neto no calce, y Daniel y Ney no la
-- tendrian. La columna `ojo` marca exactamente eso.
-- ════════════════════════════════════════════════════════════════════════
with
-- Las dos quincenas que interesan: la actual y la anterior. La serie va de
-- ENTEROS y no de fechas: `generate_series(date, date, interval)` vuelve como
-- timestamptz y el `::date` dependeria del timezone de la sesion.
rango as (
  select date_trunc('month', current_date - interval '1 month')::date        as desde,
         (date_trunc('month', current_date) + interval '1 month - 1 day')::date as hasta
),
q as (
  select rrhh_quincena(r.desde + g.i) as quincena,
         min(r.desde + g.i)           as ini,
         max(r.desde + g.i)           as fin
    from rango r cross join generate_series(0, (r.hasta - r.desde)) g(i)
   group by 1
),
dos as (
  select q.*,
         case when q.quincena = rrhh_quincena(current_date) then 'actual' else 'anterior' end as cual
    from q
   where q.quincena in (
          rrhh_quincena(current_date),
          rrhh_quincena(case when extract(day from current_date) <= 15
                             then (date_trunc('month', current_date) - interval '1 day')::date
                             else  date_trunc('month', current_date)::date end))
),
gente as (
  select p.id, p.nombre, p.ingreso from rrhh_persona p
),
-- 1 · SALARIOS: cuantas filas y con que vigencias. Sin el monto.
sal as (
  select g.id,
         count(s.id)                                               as n,
         coalesce(string_agg(to_char(s.vigente_desde,'DD-MM-YYYY'), ' · '
                             order by s.vigente_desde), '—')       as vigencias,
         -- EL DIAGNOSTICO: una vigencia que cae ADENTRO de una de las dos
         -- quincenas y no en su primer dia. Eso es el cambio a mitad de quincena.
         coalesce(string_agg(distinct to_char(s.vigente_desde,'DD-MM') || ' (' || d.cual || ')', ', ')
                  filter (where s.vigente_desde > d.ini and s.vigente_desde <= d.fin), '') as adentro
    from gente g
    left join rrhh_salario s on s.persona_id = g.id
    left join dos d on s.vigente_desde between d.ini and d.fin
   group by g.id
),
-- 2 · AJUSTES MANUALES en esas dos quincenas. Fecha y signo, nunca el monto.
aj as (
  select g.id,
         count(*) filter (where d.cual = 'actual')   as n_actual,
         count(*) filter (where d.cual = 'anterior') as n_anterior,
         -- ⚠️ EL FILTRO VA EN EL `filter`, NO EN UN `where`. Con un LEFT JOIN un
         -- `where d.cual is not null or a.id is null` descarta las filas de quien
         -- tiene ajustes SOLO FUERA de la ventana, y si esos eran sus unicos
         -- ajustes la persona se queda sin filas y el join del final LA SACA DEL
         -- REPORTE. En un diagnostico que compara tres personas, que una se caiga
         -- sin aviso se leeria como «no tiene nada raro» cuando no se la midio.
         -- Sin `where`, el left join garantiza al menos una fila por persona y
         -- los `filter` hacen el recorte sin perder a nadie.
         coalesce(string_agg(to_char(a.fecha,'DD-MM') || ' '
                             || case when a.monto < 0 then 'resta' else 'suma' end
                             || ' · ' || left(coalesce(a.nota,''), 22),
                             ' | ' order by a.fecha)
                  filter (where d.cual is not null), '—')           as det
    from gente g
    left join rrhh_ajuste_manual a on a.persona_id = g.id
    left join dos d on a.fecha between d.ini and d.fin
   group by g.id
),
-- 3 · PERMISOS E INCAPACIDADES que CUENTAN en esas quincenas: aprobados, y por
-- su modalidad. Un permiso sin modalidad no descuenta, asi que va aparte.
pm as (
  select g.id,
         count(*) filter (where p.modalidad_descuento = 'descuento')   as desc_n,
         count(*) filter (where p.modalidad_descuento = 'reposicion')  as repo_n,
         count(*) filter (where p.modalidad_descuento = 'incapacidad') as incap_n,
         count(*) filter (where p.modalidad_descuento is null)         as sin_mod_n
    from gente g
    left join rrhh_permiso p
           on p.persona_id = g.id and p.estado = 'aprobado'
          and exists (select 1 from dos d
                       where daterange(p.fecha_inicio, p.fecha_fin, '[]')
                             && daterange(d.ini, d.fin, '[]'))
   group by g.id
)
select g.nombre                                            as persona,
       to_char(g.ingreso,'DD-MM-YYYY')                      as ingreso,
       sal.n                                                as salarios,
       sal.vigencias                                        as vigencias,
       case when sal.adentro <> '' then '⚠ ' || sal.adentro
            else 'no' end                                   as ojo_cambio_en_quincena,
       aj.n_actual                                          as aj_actual,
       aj.n_anterior                                        as aj_anterior,
       aj.det                                               as ajustes_det,
       pm.desc_n                                            as perm_descuento,
       pm.repo_n                                            as perm_reposicion,
       pm.incap_n                                           as incapacidades,
       pm.sin_mod_n                                         as perm_sin_modalidad
  from gente g
  join sal on sal.id = g.id
  join aj  on aj.id  = g.id
  join pm  on pm.id  = g.id
 order by g.nombre;
