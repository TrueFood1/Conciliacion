-- SOLO DIAGNOSTICO · DIAGNOSTICO_POLITICAS_ENSAYO.sql · termina en ROLLBACK
-- ════════════════════════════════════════════════════════════════════════
-- ⚠️ ESTE ARCHIVO NO ES UNA PRUEBA, Y NO SIRVE PARA DECIDIR SI PEGAR.
-- Le SACARON EL CANDADO a proposito: el candado aborta antes de poder mostrar la
-- lista de politicas, que es justamente lo que hay que ver. Que esto corra «bien»
-- no dice nada sobre si el pegado 10 se puede aplicar. Para eso esta
-- PRUEBAS_NETO_QUINCENA.sql, que lo lleva entero.
--
-- QUE HACE. Dentro de UNA transaccion: saca una foto de las politicas que hay
-- hoy en las dos tablas nuevas, corre el cuerpo del pegado 10 (sin el candado y
-- sin su fila de control), vuelve a sacar la foto, muestra las dos juntas y
-- DESHACE TODO con un rollback. No deja ni una tabla, ni una politica, ni una fila.
--
-- GENERADO por herramientas/ensayos/armar_diagnostico_politicas.py — no editar a
-- mano. El cuerpo del pegado va byte a byte: el generador reconstruye el original
-- juntando lo que saco con lo que dejo y compara md5, asi que lo unico que falta
-- es el candado y nada mas.
--
-- COMO LEER LA TABLA QUE SALE:
--   · `momento` = «1 · ANTES» son las politicas que YA ESTABAN en la base. Si no
--     sale ninguna fila de ANTES, las tablas no existian y todo lo que aparezca
--     en DESPUES lo creo el pegado.
--   · `cuantas_en_este_momento` repite el total de ese momento. El numero de
--     DESPUES es el que el candado compara contra 4.
--   · `la_declara_el_pegado` dice si esa politica es una de las cuatro que el
--     pegado escribe. Un «NO» en DESPUES es una regla de seguridad que salio de
--     otro lado.
--   · ⚠️ `permisiva_o_restrictiva`: las PERMISIVAS del mismo comando se SUMAN
--     (basta que una diga si), las RESTRICTIVAS se exigen todas. Una permisiva de
--     mas ABRE la puerta.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- LA FOTO DE ANTES. Tabla normal y no temporal: las mediciones de abajo no
-- cambian de rol, pero una tabla creada dentro de la transaccion se borra con el
-- rollback igual que una temporal, y sin depender del esquema temporal.
create table zz_antes as
select p.tablename::text as tabla, p.policyname::text as politica,
       p.cmd::text as comando, p.permissive::text as permisiva,
       array_to_string(p.roles, ', ') as roles,
       coalesce(p.qual, '—') as cond_leer,
       coalesce(p.with_check, '—') as cond_escribir
  from pg_policies p
 where p.schemaname = 'public' and p.tablename in ('rrhh_neto_quincena','rrhh_feriado_trabajado');

-- Y si las tablas existian o no, que es distinto de «no tenian politicas».
create table zz_antes_tablas as
select t.tabla::text as tabla,
       (select count(*) from pg_class k join pg_namespace n on n.oid = k.relnamespace
         where k.relname = t.tabla and n.nspname = 'public' and k.relkind = 'r') as existia
  from (values ('rrhh_neto_quincena'), ('rrhh_feriado_trabajado')) as t(tabla);


-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  CUERPO DE PERSONAL_NETO_QUINCENA.sql, SIN EL CANDADO                ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- ── 1 · rrhh_feriado SABE SI ES DE PAGO OBLIGATORIO ─────────────────────
-- `default false` es lo que no rompe nada: las filas que ya existen pasan a «no
-- obligatorio», que es el caso que NO suma plata. Un default true habria vuelto
-- obligatorios todos los feriados y cierres cargados, en silencio.
alter table rrhh_feriado add column if not exists pago_obligatorio boolean not null default false;

comment on column rrhh_feriado.pago_obligatorio is
  'true = feriado de pago obligatorio del art. 148 del Codigo de Trabajo. Solo estos '
  'pagan doble si se trabajan, y solo si caen de lunes a viernes. Verificado el '
  '15-oct-2026 contra el art. 148 y comunicados del MTSS: de lo que queda de 2026 el '
  'UNICO obligatorio es el 25-dic. El 1-dic es de pago NO obligatorio. (El 12-oct '
  'tampoco lo es, pero ademas NO esta cargado en esta tabla: ver PENDIENTES.md P3.) '
  'Se corrige desde la pantalla «Dias cerrados».';

-- ⚠️ HALLAZGO, Y NO SE ARREGLA DESDE ACA.
-- El 25-dic-2026 NO esta cargado en rrhh_feriado, y hoy NO SE PUEDE cargar: el
-- cierre de planta del 18-dic-2026 al 11-ene-2027 (PERSONAL_CALENDARIO.sql, fila
-- semilla) lo CONTIENE, y rrhh_feriado tiene una exclusion por rangos solapados
-- que impide que un feriado viva adentro de un cierre. La semilla ni lo intento:
-- su `where not exists` se salta en silencio cualquier fila que se pise.
--
-- Operativamente hoy da igual —si la planta esta cerrada nadie trabaja el 25 y
-- nadie cobra doble— pero deja una regla que NO PUEDE DISPARARSE NUNCA, y eso es
-- peor que no tenerla: la pantalla ofreceria cargar un feriado trabajado que el
-- trigger va a rechazar siempre.
--
-- Partir o no el cierre de planta es DECISION DE LORENA, no un efecto secundario
-- de este pegado: ese rango se ve en la pantalla «Dias cerrados» y lo usa el
-- calendario. Este update queda igual, idempotente, para el dia en que se
-- decida: en cuanto el 25-dic exista como feriado propio, marcarlo es correr
-- esta linea.
update rrhh_feriado set pago_obligatorio = true
 where fecha = date '2026-12-25' and tipo = 'feriado' and not pago_obligatorio;


-- ── 2 · EL NETO DE QUINCENA, COMO DATO ──────────────────────────────────
-- Espejo de `rrhh_salario`: historia, no valor actual. El neto de una quincena
-- vieja tiene que poder reconstruirse tal como se pago.
create table if not exists rrhh_neto_quincena (
  id            bigint generated always as identity primary key,
  persona_id    bigint  not null references rrhh_persona(id),
  neto          numeric not null check (neto > 0),
  vigente_desde date    not null,
  nota          text,
  creado_en     timestamptz not null default now(),
  creado_por    text    not null
);
create index if not exists rrhh_neto_quincena_persona_idx
  on rrhh_neto_quincena (persona_id, vigente_desde desc);

comment on table rrhh_neto_quincena is
  'El NETO que se transfiere por quincena, por persona, con vigencia. Append-only: '
  'un neto nuevo es una fila nueva, nunca un update. Desde el 15-oct-2026 ES LA BASE '
  'del calculo del pago, en lugar de salario_mensual/2 con rebaja porcentual. '
  'rrhh_salario NO se reemplaza: sigue siendo la historia del bruto.';

alter table rrhh_neto_quincena enable row level security;
-- SOLO SOCIAS, de los dos lados. Es dato salarial, con el mismo criterio que
-- rrhh_salario y rrhh_aguinaldo: el equipo no lo necesita para usar el modulo.
drop policy if exists rrhh_neto_quincena_sel on rrhh_neto_quincena;
create policy rrhh_neto_quincena_sel on rrhh_neto_quincena for select to authenticated
  using (acceso_es_socia());
drop policy if exists rrhh_neto_quincena_ins on rrhh_neto_quincena;
create policy rrhh_neto_quincena_ins on rrhh_neto_quincena for insert to authenticated
  with check (acceso_es_socia());
-- Sin politica de update ni delete: sin politica la operacion no pasa aunque
-- alguien le diera el grant por error. Dos candados para el append-only.


-- ── 3 · FERIADO TRABAJADO, TIPO DE MOVIMIENTO PROPIO ────────────────────
-- Tabla aparte y no un tipo mas de `rrhh_ajuste_manual`, por dos razones: lleva
-- dias u horas (el ajuste lleva un monto suelto), y Lorena lo quiere VER separado
-- de las horas extra normales en el desglose.
create table if not exists rrhh_feriado_trabajado (
  id          bigint generated always as identity primary key,
  persona_id  bigint  not null references rrhh_persona(id),
  fecha       date    not null,
  horas       numeric check (horas > 0 and horas <= 24),  -- null = dia completo
  nota        text,
  creado_por  text    not null,
  creado_en   timestamptz not null default now(),
  constraint rrhh_feriado_trabajado_unico unique (persona_id, fecha)
);
comment on table rrhh_feriado_trabajado is
  'Dias (o horas) trabajados en un feriado de PAGO OBLIGATORIO que cae de lunes a '
  'viernes. SUMA una vez al neto: el feriado ya viene pagado, asi que el dia queda al '
  'doble. Append-only. El unique (persona_id, fecha) impide cargar dos veces el mismo '
  'feriado a la misma persona, que seria pagarlo triple.';

alter table rrhh_feriado_trabajado enable row level security;
drop policy if exists rrhh_feriado_trabajado_sel on rrhh_feriado_trabajado;
create policy rrhh_feriado_trabajado_sel on rrhh_feriado_trabajado for select to authenticated
  using (acceso_es_socia() or persona_id = rrhh_mi_persona());
drop policy if exists rrhh_feriado_trabajado_ins on rrhh_feriado_trabajado;
create policy rrhh_feriado_trabajado_ins on rrhh_feriado_trabajado for insert to authenticated
  with check (acceso_es_socia());


-- ── 4 · LAS CUATRO REGLAS, CADA UNA EN UN SOLO LUGAR ────────────────────
-- Si manana el sabado pasa a ser habil, o los feriados pasan a descontar, se
-- cambia UNA de estas funciones y todo el modulo lo sigue.

-- 4.1 · DIA DEL DIVISOR: lunes a viernes, feriados INCLUIDOS.
create or replace function rrhh_es_dia_divisor(p_dia date) returns boolean
language sql immutable set search_path = public as $$
  select extract(isodow from p_dia) <= 5;
$$;
comment on function rrhh_es_dia_divisor(date) is
  'Dia que CUENTA EN EL DIVISOR: lunes a viernes, feriados incluidos. Decision de '
  'Lorena, 15-oct-2026: el feriado se paga, asi que esta en el divisor. 1-15 oct = 11.';

-- 4.2 · DIA DESCONTABLE: lunes a viernes y NO feriado.
-- SECURITY DEFINER a proposito. Si fuera invoker y quien llama no pudiera leer
-- rrhh_feriado, el `not exists` daria true y la funcion diria que el dia SI
-- descuenta: un error silencioso, y en la direccion que le cuesta plata a una
-- persona. Los feriados no son dato sensible («no son de nadie», pegado 4).
create or replace function rrhh_es_dia_descontable(p_dia date) returns boolean
language sql stable security definer set search_path = public as $$
  select extract(isodow from p_dia) <= 5
     and not exists (select 1 from rrhh_feriado f
                      where daterange(f.fecha, coalesce(f.fecha_fin, f.fecha), '[]') @> p_dia);
$$;
comment on function rrhh_es_dia_descontable(date) is
  'Dia que DESCUENTA si hay ausencia, permiso sin goce o incapacidad: lunes a viernes '
  'y que NO sea feriado ni cierre de planta. ⚠️ Que el feriado no descuente es una '
  'SUPOSICION de Andrea (el feriado se paga igual), SIN CONFIRMAR por la contadora. '
  'Si se confirma al revés, se cambia SOLO esta funcion.';

-- 4.3 · EL DIVISOR DE UNA QUINCENA.
create or replace function rrhh_dias_divisor(p_ini date, p_fin date) returns integer
language sql immutable set search_path = public as $$
  select count(*)::int from generate_series(0, (p_fin - p_ini)) g(i)
   where rrhh_es_dia_divisor(p_ini + g.i);
$$;
comment on function rrhh_dias_divisor(date, date) is
  'Cuantos dias del divisor tiene el rango. Serie de ENTEROS y no de fechas: '
  'generate_series(date,date,interval) vuelve como timestamptz y el ::date dependeria '
  'del timezone de la sesion. Oct Q1 = 11 · Nov Q1 = 10 · Dic Q2 (16-31) = 12.';

-- 4.4 · ¿ESTE FERIADO PAGA DOBLE SI SE TRABAJA?
create or replace function rrhh_feriado_paga_doble(p_dia date) returns boolean
language sql stable security definer set search_path = public as $$
  select extract(isodow from p_dia) <= 5
     and exists (select 1 from rrhh_feriado f
                  where f.tipo = 'feriado' and f.pago_obligatorio
                    and daterange(f.fecha, coalesce(f.fecha_fin, f.fecha), '[]') @> p_dia);
$$;
comment on function rrhh_feriado_paga_doble(date) is
  'true solo si el dia es feriado de PAGO OBLIGATORIO y cae de lunes a viernes. '
  '⚠️ PENDIENTE: un feriado obligatorio en sabado o domingo devuelve false y NO suma '
  'nada. La ley podria exigir el dia sencillo igual — pendiente de la contadora. En '
  'lo que queda de 2026 el caso no se presenta.';

-- Y el guardia: no se puede cargar un feriado trabajado sobre un dia que no
-- califica. Sin esto, un error de dedo paga doble un martes cualquiera.
create or replace function rrhh_feriado_trabajado_valida() returns trigger
language plpgsql set search_path = public as $$
begin
  if not rrhh_feriado_paga_doble(new.fecha) then
    raise exception 'El % no es un feriado de pago obligatorio de lunes a viernes, asi que '
      'no paga doble. Si es un dia extra o una hora extra comun, va por otro camino.',
      to_char(new.fecha,'DD-MM-YYYY') using errcode = '23514';
  end if;
  return new;
end $$;
drop trigger if exists rrhh_feriado_trabajado_valida_tg on rrhh_feriado_trabajado;
create trigger rrhh_feriado_trabajado_valida_tg before insert on rrhh_feriado_trabajado
  for each row execute function rrhh_feriado_trabajado_valida();


-- ── 5 · LOS PARAMETROS · FILAS NUEVAS, NADA BORRADO ─────────────────────
-- Vigencia 2026-10-01 para los dos, que es desde cuando rige el neto fijo. Las
-- filas viejas QUEDAN: asi el calculo de una quincena anterior sigue siendo
-- reconstruible con los valores que regian entonces.
insert into rrhh_param (clave, valor, vigente_desde, nota, creado_por) values
  ('rebaja_trabajador_pct', 0.0, '2026-10-01',
   'APAGADA desde el 15-oct-2026. El neto ya no se deriva del bruto con un porcentaje: '
   'sale de rrhh_neto_quincena. La fila anterior (6,49) NO se borra — sin ella no se '
   'podria reconstruir como se calculo antes de este cambio.', 'pegado-10'),
  ('incap_dias_naturales', 0.0, '2026-10-01',
   'Decision de Lorena, 15-oct-2026: la incapacidad descuenta solo en dias HABILES '
   '(lunes a viernes y no feriado), igual que un permiso. Antes era 1 (dias naturales). '
   'La fila anterior NO se borra.', 'pegado-10');


-- ── 6 · LAS VISTAS ──────────────────────────────────────────────────────
-- `habil` de v_rrhh_permiso_dia pasa a calcularse con rrhh_es_dia_descontable().
-- Significa lo MISMO que antes (L-V y no feriado), pero ahora la regla vive en la
-- funcion y no repetida en la vista. No se agregan ni se quitan columnas.
create or replace view v_rrhh_permiso_dia with (security_invoker = true) as
select pm.id                                     as permiso_id,
       pm.persona_id,
       p.nombre,
       pm.modalidad_descuento,
       pm.horas,
       (pm.fecha_inicio + g.i)                   as dia,
       rrhh_quincena(pm.fecha_inicio + g.i)      as quincena,
       rrhh_es_dia_descontable(pm.fecha_inicio + g.i) as habil,
       -- `dia_n` sigue contando DIAS NATURALES desde el inicio: el plazo del
       -- art. 79 («los primeros 3 dias») corre en calendario. Un fin de semana
       -- no descuenta pero igual consume plazo.
       (g.i + 1)                                 as dia_n,
       pm.incapacidad_origen
  from rrhh_permiso pm
  join rrhh_persona p on p.id = pm.persona_id
  cross join lateral generate_series(0, (pm.fecha_fin - pm.fecha_inicio)) as g(i)
 where pm.estado = 'aprobado'
   and acceso_es_socia();


-- EL DESGLOSE. Seis conceptos: base · incapacidad · descuento_permiso ·
-- feriado_trabajado · rebaja · ajuste.
create or replace view v_rrhh_pago_detalle with (security_invoker = true) as
with rango as (
  -- Los dos extremos en su propio CTE: una subconsulta agregada como ARGUMENTO
  -- de generate_series dentro del FROM es sintaxis discutible segun la version,
  -- y esto no deja lugar a duda.
  --
  -- ⚠️ EL UNIVERSO TIENE QUE CUBRIR TAMBIEN AJUSTES Y PERMISOS, no solo salarios.
  -- La rama de ajustes de abajo hace `join q`, asi que un ajuste fuera del rango
  -- NO SALE EN NINGUNA PANTALLA — se guarda y desaparece. Y el rango se puede
  -- quedar corto de los dos lados: un ajuste con fecha anterior al primer salario
  -- cargado, o uno adelantado al mes que viene. Plata que existe y no se ve es
  -- peor que plata mal calculada, porque nada avisa.
  -- `least`/`greatest` de Postgres IGNORAN los nulls, asi que una tabla vacia no
  -- arrastra todo a null; si las tres estan vacias, d0 queda null, generate_series
  -- no devuelve filas y la vista sale vacia — la respuesta correcta.
  --
  -- ⚠️ AGREGADO EN EL PEGADO 10, y no es cosmetico: desde ahora la BASE del pago
  -- sale de rrhh_neto_quincena. Si el universo siguiera midiendose solo con
  -- rrhh_salario, una persona con neto cargado y sin salario quedaria fuera del
  -- rango y su pago no apareceria en ninguna pantalla — guardado y mudo. Lo
  -- mismo con un feriado trabajado adelantado a diciembre.
  select date_trunc('month', least(
           (select min(vigente_desde) from rrhh_salario),
           (select min(vigente_desde) from rrhh_neto_quincena),
           (select min(fecha)         from rrhh_feriado_trabajado),
           (select min(fecha)         from rrhh_ajuste_manual),
           (select min(fecha_inicio)  from rrhh_permiso)))::date            as desde,
         (date_trunc('month', greatest(
           current_date,
           (select max(vigente_desde) from rrhh_salario),
           (select max(vigente_desde) from rrhh_neto_quincena),
           (select max(fecha)      from rrhh_feriado_trabajado),
           (select max(fecha)      from rrhh_ajuste_manual),
           (select max(fecha_fin)  from rrhh_permiso)))
          + interval '1 month - 1 day')::date                              as hasta
),
q as (
  -- Serie de ENTEROS por la misma razon que en v_rrhh_permiso_dia: una serie de
  -- fechas con `interval` vuelve como timestamptz y el `::date` dependeria del
  -- timezone de la sesion. `date + integer` no toca ningun huso.
  select rrhh_quincena(r.desde + g.i) as quincena,
         min(r.desde + g.i)           as ini,
         max(r.desde + g.i)           as fin
    from rango r
    cross join lateral generate_series(0, (r.hasta - r.desde)) as g(i)
   group by 1
),
-- QUIÉN ENTRA EN CADA QUINCENA. Se excluye a quien todavía no había ingresado y
-- a quien ya estaba de baja antes de que la quincena empezara. La quincena en
-- la que alguien se va SÍ aparece, completa: prorratearla es una decisión de
-- plata que le toca a la socia, y la hace con un ajuste manual a la vista.
persona_q as (
  select p.id as persona_id, p.nombre, q.quincena, q.ini, q.fin
    from rrhh_persona p
    cross join q
    left join lateral (select b.anulada, b.fecha from rrhh_persona_baja b
                        where b.persona_id = p.id
                        order by b.creado_en desc limit 1) ba on true
   where (p.ingreso is null or p.ingreso <= q.fin)
     and (ba.fecha is null or ba.anulada or ba.fecha >= q.ini)
),
-- EL SALARIO VIGENTE EL ÚLTIMO DÍA DE LA QUINCENA, y de ahí las dos tarifas.
-- Mismo patrón que `v_rrhh_evento` (lateral + order by vigente_desde desc,
-- creado_en desc limit 1), para que dos filas con la misma vigencia desempaten
-- igual en los dos lados del módulo.,
-- EL NETO FIJO, vigente el ULTIMO dia de la quincena. Reemplaza al CTE `sal`,
-- que derivaba todo de salario_mensual. Mismo patron de desempate que
-- rrhh_salario (vigente_desde desc, creado_en desc) para que los dos lados del
-- modulo resuelvan igual una vigencia repetida.
neto as (
  select pq.persona_id, pq.nombre, pq.quincena, pq.ini, pq.fin,
         n.neto, n.vigente_desde,
         rrhh_dias_divisor(pq.ini, pq.fin)                          as divisor,
         n.neto / nullif(rrhh_dias_divisor(pq.ini, pq.fin), 0)      as valor_dia,
         n.neto / nullif(rrhh_dias_divisor(pq.ini, pq.fin), 0)
                / rrhh_param('jornada_horas', pq.fin)               as valor_hora
    from persona_q pq
    left join lateral (select nq.neto, nq.vigente_desde from rrhh_neto_quincena nq
                        where nq.persona_id = pq.persona_id and nq.vigente_desde <= pq.fin
                        order by nq.vigente_desde desc, nq.creado_en desc limit 1) n on true
),
-- PERMISOS CON DESCUENTO. `pd.habil` ya es «descontable», asi que un dia sobre un
-- feriado no entra en la cuenta.
perm as (
  select n.quincena, n.ini, n.fin, n.persona_id, n.nombre,
         n.valor_dia, n.valor_hora, pd.permiso_id,
         min(pd.dia) as dia_ini, max(pd.dia) as dia_fin,
         count(*) filter (where pd.habil) as dias,
         max(pd.horas)                    as horas
    from neto n
    join v_rrhh_permiso_dia pd
      on pd.persona_id = n.persona_id and pd.dia between n.ini and n.fin
   where pd.modalidad_descuento = 'descuento'
     and n.neto is not null
   group by n.quincena, n.ini, n.fin, n.persona_id, n.nombre,
            n.valor_dia, n.valor_hora, pd.permiso_id
),
-- INCAPACIDADES. Que cuenten solo los dias descontables o todos los naturales lo
-- decide `incap_dias_naturales`, que el pegado puso en 0 (= solo habiles). El
-- parametro SE SIGUE LEYENDO a proposito: si dejara de consultarse, volverlo a 1
-- no haria nada y nadie se enteraria. La regla vive ahi, en un solo lugar.
-- El porcentaje del patrono depende del numero de dia DENTRO de la incapacidad
-- (dia_n, dias NATURALES: el plazo del art. 79 corre en calendario), no del dia
-- de la quincena.
incap as (
  select n.quincena, n.ini, n.fin, n.persona_id, n.nombre, n.valor_dia,
         pd.permiso_id, max(pd.incapacidad_origen) as origen,
         min(pd.dia) as dia_ini, max(pd.dia) as dia_fin,
         count(*) filter (where rrhh_param('incap_dias_naturales', n.fin) = 1
                             or pd.habil)                   as dias,
         sum(case when rrhh_param('incap_dias_naturales', n.fin) = 1 or pd.habil
                  then n.valor_dia * (1 -
                         (case when pd.dia_n <= rrhh_param('incap_dias_patrono', n.fin)
                               then rrhh_param('incap_patrono_pct_dias_1_3',        n.fin)
                               else rrhh_param('incap_patrono_pct_dia_4_en_adelante', n.fin)
                          end) / 100.0)
                  else 0 end)             as descuento
    from neto n
    join v_rrhh_permiso_dia pd
      on pd.persona_id = n.persona_id and pd.dia between n.ini and n.fin
   where pd.modalidad_descuento = 'incapacidad'
     and n.neto is not null
   group by n.quincena, n.ini, n.fin, n.persona_id, n.nombre, n.valor_dia, pd.permiso_id
),
-- FERIADO TRABAJADO. Suma. La vista vuelve a preguntar si el dia califica aunque
-- el trigger ya lo valido al insertar: si alguien desmarca `pago_obligatorio`
-- despues, el adicional tiene que dejar de pagarse.
fert as (
  select n.quincena, n.ini, n.fin, n.persona_id, n.nombre,
         n.valor_dia, n.valor_hora, ft.id as ft_id, ft.fecha, ft.horas, ft.nota
    from neto n
    join rrhh_feriado_trabajado ft
      on ft.persona_id = n.persona_id and ft.fecha between n.ini and n.fin
   where n.neto is not null
     and rrhh_feriado_paga_doble(ft.fecha)
),
renglones as (
-- LA BASE: el neto fijo. El divisor va a la vista en `cantidad`, que es lo que
-- vuelve auditable el valor del dia sin abrir la base.
select n.quincena, n.ini, n.fin, n.persona_id, n.nombre,
       'base'::text                          as concepto,
       null::bigint                          as ref_id,
       n.ini                                 as dia,
       n.divisor::numeric                    as cantidad,
       'dias habiles'::text                  as unidad,
       n.valor_dia                           as tarifa,
       n.neto                                as monto,
       ('Neto de quincena vigente desde ' || to_char(n.vigente_desde,'DD-MM-YYYY')
        || ' · divisor ' || n.divisor)        as nota
  from neto n
 where n.neto is not null
   and acceso_es_socia()

union all

select p.quincena, p.ini, p.fin, p.persona_id, p.nombre,
       'descuento_permiso'::text             as concepto,
       p.permiso_id                          as ref_id,
       p.dia_ini                             as dia,
       case when p.horas is not null
            then case when p.dias > 0 then p.horas else 0 end
            else p.dias::numeric end         as cantidad,
       case when p.horas is not null then 'horas' else 'dias' end as unidad,
       case when p.horas is not null then p.valor_hora else p.valor_dia end as tarifa,
       - (case when p.horas is not null
               then case when p.dias > 0 then p.horas else 0 end * p.valor_hora
               else p.dias * p.valor_dia end) as monto,
       ('Permiso ' || to_char(p.dia_ini,'DD-MM')
          || case when p.dia_fin > p.dia_ini then ' al ' || to_char(p.dia_fin,'DD-MM') else '' end
          || case when p.dias = 0 then ' · sin dias descontables' else '' end) as nota
  from perm p
 where acceso_es_socia()

union all

select i.quincena, i.ini, i.fin, i.persona_id, i.nombre,
       'incapacidad'::text                   as concepto,
       i.permiso_id                          as ref_id,
       i.dia_ini                             as dia,
       i.dias::numeric                       as cantidad,
       'dias'::text                          as unidad,
       i.valor_dia                           as tarifa,
       - i.descuento                         as monto,
       ('Incapacidad'
        || case when i.origen = 'accidente_trabajo' then ' (accidente de trabajo)'
                when i.origen = 'enfermedad_comun'  then ' (enfermedad comun)' else '' end
        || ': ' || i.dias::text || case when i.dias = 1 then ' dia habil' else ' dias habiles' end
        || ' · ' || to_char(i.dia_ini,'DD-MM')
        || case when i.dia_fin > i.dia_ini then ' al ' || to_char(i.dia_fin,'DD-MM') else '' end
        || case when rrhh_param('incapacidad_reglas_confirmadas', i.fin) = 1 then ''
                else ' · REGLAS SIN CONFIRMAR' end) as nota
  from incap i
 where acceso_es_socia()

union all

-- FERIADO TRABAJADO · suma, y sale como su propio concepto para que Lorena lo vea
-- separado de cualquier otra cosa.
select f.quincena, f.ini, f.fin, f.persona_id, f.nombre,
       'feriado_trabajado'::text             as concepto,
       f.ft_id                               as ref_id,
       f.fecha                               as dia,
       coalesce(f.horas, 1)                  as cantidad,
       case when f.horas is not null then 'horas' else 'dias' end as unidad,
       case when f.horas is not null then f.valor_hora else f.valor_dia end as tarifa,
       case when f.horas is not null then f.horas * f.valor_hora else f.valor_dia end as monto,
       ('Feriado trabajado ' || to_char(f.fecha,'DD-MM')
        || case when f.horas is not null then ' · ' || f.horas::text || ' h' else ' · dia completo' end
        || ' · el dia queda al doble'
        || case when coalesce(f.nota,'') <> '' then ' · ' || f.nota else '' end) as nota
  from fert f
 where acceso_es_socia()

union all

select rrhh_quincena(a.fecha)                as quincena,
       q.ini, q.fin,
       a.persona_id, p.nombre,
       'ajuste'::text                        as concepto,
       a.id                                  as ref_id,
       a.fecha                               as dia,
       1::numeric                            as cantidad,
       null::text                            as unidad,
       null::numeric                         as tarifa,
       a.monto                               as monto,
       a.nota                                as nota
  from rrhh_ajuste_manual a
  join rrhh_persona p on p.id = a.persona_id
  join q on q.quincena = rrhh_quincena(a.fecha)
 where acceso_es_socia()
),
-- LA REBAJA sigue existiendo, apagada. Con el pct en 0 el renglon NO se emite:
-- un «-₡0» es ruido en la unica pantalla que tiene que leerse entera. El concepto
-- queda para poder reconstruir una quincena vieja.
reb as (
  select r.quincena, r.persona_id, r.nombre,
         min(r.ini) as ini, max(r.fin) as fin,
         sum(case when r.concepto in ('base','descuento_permiso','incapacidad')
                  then r.monto else 0 end) as sujeto
    from renglones r
   group by r.quincena, r.persona_id, r.nombre
)
select * from renglones

union all

select b.quincena, b.ini, b.fin, b.persona_id, b.nombre,
       'rebaja'::text, null::bigint, b.ini,
       rrhh_param('rebaja_trabajador_pct', b.fin),
       'pct'::text, null::numeric,
       - (b.sujeto * rrhh_param('rebaja_trabajador_pct', b.fin) / 100.0),
       ('Rebajas del trabajador ('
        || trim(to_char(rrhh_param('rebaja_trabajador_pct', b.fin), 'FM999990.00')) || '%)')
  from reb b
 where acceso_es_socia()
   and coalesce(rrhh_param('rebaja_trabajador_pct', b.fin), 0) <> 0
   and b.sujeto <> 0;


-- EL NUMERO A TRANSFERIR. Las columnas nuevas van AL FINAL: `create or replace
-- view` solo permite agregar.
create or replace view v_rrhh_pago with (security_invoker = true) as
select quincena, persona_id, nombre,
       min(ini) as ini, max(fin) as fin,
       coalesce(sum(monto) filter (where concepto = 'base'), 0)              as base,
       coalesce(sum(monto) filter (where concepto = 'descuento_permiso'), 0) as descuentos,
       coalesce(sum(monto) filter (where concepto = 'ajuste'), 0)            as ajustes,
       coalesce(sum(monto), 0)                                               as final,
       count(*) filter (where concepto = 'descuento_permiso')                as permisos,
       count(*) filter (where concepto = 'ajuste')                           as ajustes_n,
       coalesce(sum(monto) filter (where concepto = 'incapacidad'), 0)       as incapacidades,
       count(*) filter (where concepto = 'incapacidad')                      as incap_n,
       coalesce(sum(monto) filter (where concepto = 'rebaja'), 0)            as rebaja,
       coalesce(sum(monto) filter (where concepto <> 'rebaja'), 0)           as subtotal,
       coalesce(sum(monto) filter (where concepto = 'feriado_trabajado'), 0) as feriados_trab,
       count(*) filter (where concepto = 'feriado_trabajado')                as feriados_trab_n,
       max(cantidad) filter (where concepto = 'base')                        as divisor,
       max(tarifa)   filter (where concepto = 'base')                        as valor_dia
  from v_rrhh_pago_detalle
 where acceso_es_socia()
 group by quincena, persona_id, nombre;


-- ── 7 · GRANTS ──────────────────────────────────────────────────────────
-- Aca hay NETO: la anon key es publica y va dentro de index.html.
revoke all on rrhh_neto_quincena, rrhh_feriado_trabajado from anon;
revoke all on v_rrhh_permiso_dia, v_rrhh_pago_detalle, v_rrhh_pago from anon;
grant select on rrhh_neto_quincena, rrhh_feriado_trabajado to authenticated;
grant insert on rrhh_neto_quincena, rrhh_feriado_trabajado to authenticated;
grant select on v_rrhh_permiso_dia, v_rrhh_pago_detalle, v_rrhh_pago to authenticated;
-- Las funciones de regla: ejecutarlas no revela nada, pero `execute` se le da a
-- PUBLIC por defecto y las dos definer correrian como su dueño. No se depende de
-- una sola capa.
revoke all on function rrhh_es_dia_divisor(date)      from anon, public;
revoke all on function rrhh_es_dia_descontable(date)  from anon, public;
revoke all on function rrhh_dias_divisor(date, date)  from anon, public;
revoke all on function rrhh_feriado_paga_doble(date)  from anon, public;
grant execute on function rrhh_es_dia_divisor(date)     to authenticated;
grant execute on function rrhh_es_dia_descontable(date) to authenticated;
grant execute on function rrhh_dias_divisor(date, date) to authenticated;
grant execute on function rrhh_feriado_paga_doble(date) to authenticated;


-- ── 8 · EL CANDADO ──────────────────────────────────────────────────────



-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  FIN DEL CUERPO · desde aca, la lista                                 ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- Un solo resultado, porque el editor de Supabase muestra nada mas el ultimo.
select 0                                         as orden,
       '0 · existia la tabla?'                   as momento,
       t.tabla                                   as tabla,
       case when t.existia > 0 then 'LA TABLA YA EXISTIA en public'
            else 'la tabla NO existia' end       as politica,
       '—'::text as comando, '—'::text as permisiva_o_restrictiva,
       '—'::text as roles, '—'::text as condicion_para_leer,
       '—'::text as condicion_para_escribir,
       '—'::text as la_declara_el_pegado,
       null::bigint                              as cuantas_en_este_momento
  from zz_antes_tablas t

union all

select 1, '1 · ANTES del pegado', a.tabla, a.politica, a.comando, a.permisiva,
       a.roles, a.cond_leer, a.cond_escribir,
       case when a.politica in ('rrhh_neto_quincena_sel','rrhh_neto_quincena_ins','rrhh_feriado_trabajado_sel','rrhh_feriado_trabajado_ins') then 'si' else 'NO' end,
       count(*) over (partition by 1)
  from zz_antes a

union all

select 2, '2 · DESPUES del pegado', p.tablename::text, p.policyname::text,
       p.cmd::text, p.permissive::text,
       array_to_string(p.roles, ', '),
       coalesce(p.qual, '—'), coalesce(p.with_check, '—'),
       case when p.policyname in ('rrhh_neto_quincena_sel','rrhh_neto_quincena_ins','rrhh_feriado_trabajado_sel','rrhh_feriado_trabajado_ins') then 'si' else 'NO' end,
       count(*) over (partition by 2)
  from pg_policies p
 where p.schemaname = 'public' and p.tablename in ('rrhh_neto_quincena','rrhh_feriado_trabajado')

 order by 1, 3, 5, 4;

rollback;

-- ── DESPUES DEL ROLLBACK ────────────────────────────────────────────────
-- No tiene que quedar nada. En una sola corrida:
--   select (select count(*) from information_schema.tables where table_schema='public'
--            and table_name in ('rrhh_neto_quincena','rrhh_feriado_trabajado',
--                               'zz_antes','zz_antes_tablas'))                as tablas,
--          (select count(*) from information_schema.columns where table_schema='public'
--            and table_name='rrhh_feriado' and column_name='pago_obligatorio') as columna;
--   -- ESPERADO: 0 · 0
