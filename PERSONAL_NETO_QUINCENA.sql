-- SOLO SE PEGA DESPUES DEL ENSAYO · PERSONAL_NETO_QUINCENA.sql
-- ════════════════════════════════════════════════════════════════════════
-- MODULO PERSONAL · NETO FIJO DE QUINCENA + VALOR DEL DIA  (PEGADO 10)
-- Preparado el 15-oct-2026. NO SE CORRIO.
-- Va DESPUES de los pegados 5, 6 y 7, todos aplicados. NO toca ninguno.
--
-- ════════════════════════════════════════════════════════════════════════
-- EL CAMBIO DE FONDO, Y POR QUE
-- ════════════════════════════════════════════════════════════════════════
-- Hasta hoy el pago se derivaba del salario mensual: base = salario/2 y la
-- tarifa = salario/30/8, con una rebaja porcentual encima para llegar al neto.
-- Ese porcentaje (6,49%) salia de una observacion, no de una tasa, y nunca calzo
-- para las tres personas: el neto de Daniela no daba.
--
-- Decision de Lorena (15-oct): EL NETO DE LA QUINCENA PASA A SER UN DATO, no un
-- calculo. Se guarda por persona, con vigencia, y de ahi sale todo:
--     valor del dia  = neto de la quincena ÷ dias habiles de ESA quincena
--     valor de la hora = valor del dia ÷ jornada (8 h)
-- Ya no se usa ÷15, ni ÷30, ni la rebaja %.
--
-- LO QUE NO SE TOCA, Y ES A PROPOSITO:
--   · `rrhh_salario` queda intacta. No se borra, no se reemplaza, no se migra.
--     Sigue siendo la historia del salario bruto y la usa `v_rrhh_evento` para
--     las horas extra del aparato viejo. Que el pago ya no la lea no la vuelve
--     basura: es el unico registro de cuanto gana cada persona.
--   · La rebaja % NO se borra. Se APAGA poniendo el parametro en 0 con una fila
--     nueva. Asi el renglon desaparece del desglose y el historico de como se
--     calculo en octubre sigue siendo reconstruible. Borrar la fila vieja
--     romperia eso.
--
-- ⚠️ TODO APPEND-ONLY. `rrhh_neto_quincena` no se edita ni se borra: un neto
-- nuevo es una fila nueva con otra vigencia. Es la misma razon que en
-- `rrhh_salario` — de estos numeros cuelga una transferencia que ya se hizo.
--
-- ════════════════════════════════════════════════════════════════════════
-- DOS CONCEPTOS QUE ANTES ERAN UNO
-- ════════════════════════════════════════════════════════════════════════
--   DIA DEL DIVISOR   lunes a viernes, FERIADOS INCLUIDOS.  1-15 oct = 11
--   DIA DESCONTABLE   lunes a viernes y NO feriado.
--
-- Hasta hoy habia UNA sola bandera `habil` (L-V y no feriado) y alcanzaba,
-- porque el divisor era 30 y nunca la usaba. Con el divisor nuevo los dos
-- conceptos se cruzan y hacen falta dos. Cada uno vive en UNA funcion:
--     rrhh_es_dia_divisor()      ·  rrhh_es_dia_descontable()
-- Si manana el sabado pasa a ser habil, se cambia UNA linea.
--
-- ⚠️ SUPOSICION DE ANDREA, SIN CONFIRMAR POR LA CONTADORA: una ausencia, un
-- permiso sin goce o un dia de incapacidad que caigan en un FERIADO no
-- descuentan nada ese dia, porque el feriado se paga igual. De ahi que
-- `descontable` excluya los feriados. Si la contadora dice lo contrario, se
-- cambia esa funcion y nada mas. Ver PREGUNTAS_contadora_feriados.md.
--
-- ════════════════════════════════════════════════════════════════════════
-- FERIADO TRABAJADO
-- ════════════════════════════════════════════════════════════════════════
-- Suma UNA vez (un dia, o las horas × valor de hora), porque el feriado ya viene
-- pagado dentro del neto: con el adicional el dia queda al doble.
-- Califica SOLO si el feriado es de PAGO OBLIGATORIO y cae de lunes a viernes.
-- Esa condicion vive en `rrhh_feriado_paga_doble()`, en un solo lugar.
--
-- ⚠️ PENDIENTE, NO IMPLEMENTADO: un feriado obligatorio que cae en sabado o
-- domingo NO suma nada hoy. La ley podria exigir el dia sencillo igual. En lo que
-- queda de 2026 el caso no se presenta (los tres feriados caen L-V). Pendiente de
-- la contadora.
-- ⚠️ PENDIENTE, NO IMPLEMENTADO: si un feriado OBLIGATORIO no trabajado suma un
-- dia sencillo de todos modos. Hay dos fuentes que no coinciden; esta en el
-- documento de preguntas.
-- ════════════════════════════════════════════════════════════════════════

begin;

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
-- ⚠️ Y TAMBIEN DE `authenticated`, QUE ES EL ARREGLO DE FONDO DE ESTA SECCION.
-- Supabase trae configurado `alter default privileges in schema public grant all
-- on tables to anon, authenticated, service_role`, asi que TODA TABLA NUEVA NACE
-- CON TODOS LOS PRIVILEGIOS para los tres roles. Un `grant select, insert` no
-- quita nada: agrega sobre lo que ya estaba.
--
-- Las otras nueve tablas de Personal revocan solo de `anon` (PERSONAL_ESQUEMA.sql
-- linea 663), asi que `authenticated` conserva UPDATE, DELETE y TRUNCATE sobre
-- ellas. Para el update y el delete da igual: sin politica permisiva afectan 0
-- filas. Pero EL TRUNCATE NO LO FRENA LA SEGURIDAD POR FILAS — no borra filas una
-- por una, vacia la tabla, y las politicas no lo ven pasar. Medido contra
-- PostgreSQL 17 el 16-oct-2026: cualquier cuenta del equipo con sesion abierta
-- podia vaciar la tabla del neto de un solo comando.
--
-- Esta tabla nace cerrada. Las otras nueve quedan como estan: arreglarlas es otro
-- pegado y toca otros modulos — ver PENDIENTES.md P4.
revoke all on rrhh_neto_quincena, rrhh_feriado_trabajado from anon, authenticated;
revoke all on v_rrhh_permiso_dia, v_rrhh_pago_detalle, v_rrhh_pago from anon, authenticated;
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
do $candado$
declare
  v_anon int; v_inv int; v_rls boolean; v_pol int;
  v_pol_dif text; v_esc int;
  v_div int; v_fer boolean; v_desc boolean;
  v_doble boolean; v_doble_sab boolean; v_doble_no boolean; v_oblig int;
  v_pct numeric; v_nat numeric; v_dx_pct text; v_dx_nat text;
begin
  -- Ninguna de las tablas ni vistas nuevas puede quedar legible por anon.
  select count(*) into v_anon from (
    select unnest(array['rrhh_neto_quincena','rrhh_feriado_trabajado',
                        'v_rrhh_permiso_dia','v_rrhh_pago_detalle','v_rrhh_pago']) as t) x
   where has_table_privilege('anon','public.'||x.t,'SELECT')
      or has_table_privilege('anon','public.'||x.t,'INSERT');

  select count(*) into v_inv from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public'
     and c.relname in ('v_rrhh_permiso_dia','v_rrhh_pago_detalle','v_rrhh_pago')
     and c.reloptions::text like '%security_invoker=true%';

  select c.relrowsecurity into v_rls from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='rrhh_neto_quincena';
  -- LAS POLITICAS, POR NOMBRE Y COMANDO, NO POR CANTIDAD.
  -- ⚠️ Contar no alcanzaba, y el agujero era grande: «4 politicas» se cumple
  -- igual con un SELECT y un INSERT en una tabla y un UPDATE y un DELETE en la
  -- otra — o sea exactamente lo contrario del append-only que este pegado dice
  -- garantizar. Un numero te dice que algo esta mal; el conjunto te dice QUE.
  select count(*) into v_pol from pg_policies
   where schemaname='public' and tablename in ('rrhh_neto_quincena','rrhh_feriado_trabajado');
  --
  -- ⚠️ SON CATORCE, NO CUATRO, Y NO ES UN ERROR. Este pegado escribe 2 politicas
  -- por tabla. Las otras 5 por tabla las pone SOLO el disparador de eventos
  -- `asistente_politicas` (ASISTENTE_ROL.sql §7), que corre en cada `create
  -- table` de public y llama a `asistente_crear_politicas()`. O sea que aparecen
  -- en el mismo instante en que este pegado crea las tablas, sin que este pegado
  -- las pida. 2 + 5 = 7 por tabla, 14 en total.
  --
  -- El candado viejo esperaba 4 y abortaba. Contaba las politicas de otro, y
  -- encima contar no distingue: 14 se cumple igual con cinco de UPDATE y DELETE
  -- donde no tiene que haber ninguna. Asi que ahora se compara el CONJUNTO exacto
  -- de tabla + politica + comando, y el mensaje dice que FALTA y que SOBRA.
  v_pol_dif := (
    with asis(politica, comando) as (values
      ('asistente_lee','SELECT'), ('asistente_ve_todo','SELECT'),
      ('asistente_no_inserta','INSERT'), ('asistente_no_actualiza','UPDATE'),
      ('asistente_no_borra','DELETE')),
    tab(tabla) as (values ('rrhh_neto_quincena'), ('rrhh_feriado_trabajado')),
    esperado(tabla, politica, comando) as (
      select t.tabla, a.politica, a.comando from tab t cross join asis a
      union all
      values ('rrhh_neto_quincena',    'rrhh_neto_quincena_sel',     'SELECT'),
             ('rrhh_neto_quincena',    'rrhh_neto_quincena_ins',     'INSERT'),
             ('rrhh_feriado_trabajado','rrhh_feriado_trabajado_sel', 'SELECT'),
             ('rrhh_feriado_trabajado','rrhh_feriado_trabajado_ins', 'INSERT')),
    hay(tabla, politica, comando) as (
      select tablename::text, policyname::text, cmd::text from pg_policies
       where schemaname = 'public'
         and tablename in ('rrhh_neto_quincena','rrhh_feriado_trabajado')),
    dif(que, tabla, politica, comando) as (
      select 'FALTA', e.* from (select * from esperado except select * from hay) e
      union all
      select 'SOBRA', h.* from (select * from hay except select * from esperado) h)
    select string_agg(que || ' ' || tabla || '.' || politica || ' (' || comando || ')',
                      ' · ' order by que, tabla, politica)
      from dif);

  -- NADIE MAS QUE EL DUEÑO PUEDE ESCRIBIR ENCIMA NI VACIAR. Se pregunta por los
  -- TRES privilegios, y TRUNCATE es el que importa: es el unico que la seguridad
  -- por filas no frena. Sin esta comprobacion, un `grant all` futuro —o el
  -- default de Supabase, que es justo eso— deja la tabla del neto a merced de
  -- cualquier cuenta con sesion.
  select count(*) into v_esc
    from (select unnest(array['rrhh_neto_quincena','rrhh_feriado_trabajado']) as t) x
   cross join unnest(array['UPDATE','DELETE','TRUNCATE']) as p(priv)
   where has_table_privilege('authenticated','public.'||x.t, p.priv)
      or has_table_privilege('anon','public.'||x.t, p.priv);

  -- LAS REGLAS, MEDIDAS CONTRA EL CALENDARIO REAL. No se confia en el texto de
  -- la funcion: se la llama.
  v_div   := rrhh_dias_divisor(date '2026-10-01', date '2026-10-15');
  -- ⚠️ CON UN FERIADO QUE EXISTE DE VERDAD. Antes esto preguntaba por el
  -- 12-oct-2026, que NO esta cargado en rrhh_feriado (la semilla trae 31-ago,
  -- 15-sep, 1-dic y el cierre de planta, nada mas): la comprobacion pasaba
  -- porque el 12-oct es lunes, no porque fuera feriado. Una salvaguarda que pasa
  -- por el motivo equivocado no esta probando lo que dice probar.
  -- El 1-dic-2026 es martes Y esta cargado como feriado.
  v_fer   := rrhh_es_dia_divisor(date '2026-12-01');
  v_desc  := rrhh_es_dia_descontable(date '2026-10-03'); -- sabado -> no descuenta
  -- LA REGLA DEL PAGO DOBLE, LAS DOS RAMAS, con una fila que se crea y se borra
  -- aca mismo. La version anterior de este candado preguntaba por el 25-dic-2026
  -- y habria abortado el pegado entero: ese dia NO esta cargado ni puede estarlo
  -- (ver el hallazgo de la seccion 1). Un candado que exige un dato imposible no
  -- es un candado, es una puerta tapiada.
  -- Y se prueban LAS DOS ramas: una funcion que siempre dijera «no» pasaria un
  -- candado que solo mire el «no». El 3-jul-2099 es viernes y el 4 es sabado.
  insert into rrhh_feriado (fecha, fecha_fin, descripcion, tipo, pago_obligatorio, creado_por)
  values (date '2099-07-03', date '2099-07-04',
          'CANDADO del pegado 10 · se borra cuatro lineas mas abajo', 'feriado', true, 'pegado-10');
  v_doble     := rrhh_feriado_paga_doble(date '2099-07-03');  -- viernes obligatorio -> si
  v_doble_sab := rrhh_feriado_paga_doble(date '2099-07-04');  -- sabado  obligatorio -> no
  delete from rrhh_feriado where fecha = date '2099-07-03' and creado_por = 'pegado-10';
  if exists (select 1 from rrhh_feriado where creado_por = 'pegado-10') then
    raise exception 'CANDADO: la fila de prueba de 2099 no se borro. NO SE APLICO NADA.';
  end if;
  -- Y la rama del «no obligatorio», contra un dia que SI esta cargado: el
  -- 1-dic-2026 es feriado de pago no obligatorio y cae martes.
  v_doble_no  := rrhh_feriado_paga_doble(date '2026-12-01');
  select count(*) into v_oblig from rrhh_feriado where pago_obligatorio;

  -- ⚠️ POR rrhh_param(), NO POR UN SELECT PROPIO. La version anterior de este
  -- candado hacia `order by vigente_desde desc limit 1`, que toma la ultima fila
  -- de CUALQUIER fecha — incluso una con vigencia FUTURA. rrhh_param() toma la
  -- ultima fila con vigencia <= la fecha que se le pide, y es lo que usan las
  -- vistas. Medir por otro camino que el codigo no es medir: el candado podia
  -- gritar con las vistas bien, o callarse con las vistas mal.
  --
  -- Y se pregunta en VARIAS fechas, no en una: un parametro apagado el 15 de
  -- octubre y encendido el 1 de noviembre pasaria un candado de una sola fecha.
  select coalesce(max(rrhh_param('rebaja_trabajador_pct', t.d)), -1) into v_pct
    from (values (date '2026-10-15'), (date '2026-10-31'),
                 (date '2026-11-30'), (date '2026-12-31')) t(d);
  select coalesce(max(rrhh_param('incap_dias_naturales', t.d)), -1) into v_nat
    from (values (date '2026-10-15'), (date '2026-10-31'),
                 (date '2026-11-30'), (date '2026-12-31')) t(d);
  -- Y si algo no cuadra, el mensaje tiene que decir QUE filas hay, no solo que
  -- esta mal. Son porcentajes y banderas, no montos: se pueden imprimir.
  select string_agg(format('%s = %s', to_char(vigente_desde,'DD-MM-YYYY'), valor),
                    ' · ' order by vigente_desde)
    into v_dx_pct from rrhh_param where clave = 'rebaja_trabajador_pct';
  select string_agg(format('%s = %s', to_char(vigente_desde,'DD-MM-YYYY'), valor),
                    ' · ' order by vigente_desde)
    into v_dx_nat from rrhh_param where clave = 'incap_dias_naturales';

  if v_anon <> 0 then
    raise exception 'CANDADO: `anon` llega a % de las tablas/vistas nuevas. Aca hay NETO y '
      'la anon key es PUBLICA. NO SE APLICO NADA.', v_anon;
  end if;
  if v_inv <> 3 then
    raise exception 'CANDADO: solo % de 3 vistas con security_invoker. NO SE APLICO NADA.', v_inv;
  end if;
  if not coalesce(v_rls,false) then
    raise exception 'CANDADO: rrhh_neto_quincena quedo SIN RLS. El grant de select es para '
      '`authenticated`, o sea todo el equipo: sin RLS cualquiera leeria el neto de todos. '
      'NO SE APLICO NADA.';
  end if;
  if v_esc <> 0 then
    raise exception 'CANDADO: `authenticated` o `anon` conservan % privilegio(s) de UPDATE, '
      'DELETE o TRUNCATE sobre las dos tablas nuevas. El TRUNCATE no lo frena la seguridad '
      'por filas: vacia la tabla y las politicas no lo ven pasar. Aca hay NETO. '
      'NO SE APLICO NADA.', v_esc;
  end if;
  if v_pol_dif is not null then
    raise exception E'CANDADO: las politicas de las dos tablas nuevas no son las 14 esperadas '
      '(2 de este pegado y 5 del disparador del asistente, por tabla). Aca hay NETO, y las '
      'politicas PERMISIVAS del mismo comando se SUMAN: una de mas ABRE la puerta, no la '
      'cierra. NO SE APLICO NADA.\n  HAY % en total.\n  DIFERENCIAS: %', v_pol, v_pol_dif;
  end if;
  -- EL DIVISOR, CONTRA EL DATO QUE CONFIRMO LORENA.
  if v_div <> 11 then
    raise exception 'CANDADO: el divisor del 1-15 de octubre da % y tiene que dar 11. '
      'Lorena lo confirmo con «neto - neto/11». NO SE APLICO NADA.', v_div;
  end if;
  if not v_fer then
    raise exception 'CANDADO: el 1-dic-2026 (feriado cargado, martes) NO cuenta en el divisor, '
      'y tiene que contar: la decision de Lorena es que el feriado se paga. NO SE APLICO NADA.';
  end if;
  if v_desc then
    raise exception 'CANDADO: el sabado 3-oct cuenta como descontable, y no tiene que '
      'contar. NO SE APLICO NADA.';
  end if;
  if not v_doble then
    raise exception 'CANDADO: un feriado de pago obligatorio en VIERNES no califica para pago '
      'doble, y tendria que calificar. La regla esta al reves. NO SE APLICO NADA.';
  end if;
  if v_doble_sab then
    raise exception 'CANDADO: un feriado de pago obligatorio en SABADO califica para pago doble, '
      'y hoy no tendria que calificar. NO SE APLICO NADA.';
  end if;
  if v_doble_no then
    raise exception 'CANDADO: el 1-dic-2026 (feriado de pago NO obligatorio, martes) califica '
      'para pago doble. La columna pago_obligatorio no esta frenando nada. NO SE APLICO NADA.';
  end if;
  -- ⚠️ NINGUN `%%` EN ESTOS MENSAJES, Y ES A PROPOSITO. En el formato de RAISE
  -- `%%` es un porcentaje LITERAL, no un hueco: `raise ... 'quedo en %%', v_pct`
  -- tiene cero huecos y un argumento, y Postgres contesta «too many parameters
  -- specified for RAISE» en vez del mensaje. Y pasa solo cuando la rama se
  -- dispara, o sea justo cuando el mensaje hacia falta. Se escribe «por ciento».
  if v_pct <> 0 then
    raise exception 'CANDADO: la rebaja del trabajador NO quedo apagada: en alguna quincena '
      'de 2026 todavia vale % por ciento. Las filas de rrhh_param para esa clave son: %. '
      'La fila que agrega este pegado tiene vigencia 01-10-2026, asi que una fila POSTERIOR '
      'con valor distinto de 0 la tapa. Eso se arregla a mano, decidiendo que vigencia '
      'corresponde — no desde aca. NO SE APLICO NADA.', v_pct, coalesce(v_dx_pct,'(ninguna)');
  end if;
  if v_nat <> 0 then
    raise exception 'CANDADO: incap_dias_naturales NO quedo en 0: en alguna quincena de 2026 '
      'todavia vale %, o sea que la incapacidad seguiria descontando dias naturales. Las '
      'filas de rrhh_param para esa clave son: %. NO SE APLICO NADA.',
      v_nat, coalesce(v_dx_nat,'(ninguna)');
  end if;

  raise notice 'CANDADO OK: anon en 0 · 3 vistas invoker · RLS con 4 politicas · divisor 11 · '
    'feriado en el divisor · sabado no descuenta · la regla del pago doble funciona en las dos '
    'ramas · rebaja 0 · incap habiles';

  -- AVISO, NO EXCEPCION. Que no haya ningun feriado obligatorio cargado no es un
  -- error del pegado: es el hallazgo de la seccion 1 esperando decision. Se
  -- aplica igual, y queda dicho en voz alta.
  if v_oblig = 0 then
    raise notice '⚠️ PENDIENTE: no hay NINGUN feriado de pago obligatorio cargado, asi que el '
      'pago doble no puede dispararse todavia. El unico de 2026 es el 25-dic y esta adentro del '
      'cierre de planta del 18-dic al 11-ene, que la exclusion de rangos no deja partir. Lo '
      'decide Lorena.';
  end if;
end
$candado$;


-- ── 9 · LA FILA DE CONTROL ──────────────────────────────────────────────
-- Regla 🔴 de CLAUDE.md: un "Success" del editor no es evidencia de nada.
-- ESPERADO:  1 · 1 · 1 · 11 · t · f · f · 0 · 0 · 0 · 14 · 0 · 0
-- ⚠️ `politicas_14` son 14 y no 4: 2 por tabla las escribe este pegado y 5 por
-- tabla las agrega el disparador `asistente_politicas` al crear cada tabla. El
-- conjunto exacto lo verifica el candado; este numero es solo la señal de humo.
-- ⚠️ `feriados_obligatorios` en 0 es lo esperado HOY, y es el pendiente de la
-- seccion 1, no una falla. Las dos ramas de la regla del pago doble las prueba el
-- candado de arriba, que para eso crea y borra una fila de 2099.
select
  (select count(*) from information_schema.columns where table_schema='public'
    and table_name='rrhh_feriado' and column_name='pago_obligatorio')        as col_feriado,
  (select count(*) from information_schema.tables where table_schema='public'
    and table_name='rrhh_neto_quincena')                                     as tabla_neto,
  (select count(*) from information_schema.tables where table_schema='public'
    and table_name='rrhh_feriado_trabajado')                                 as tabla_fer_trab,
  rrhh_dias_divisor(date '2026-10-01', date '2026-10-15')                    as divisor_oct_q1,
  rrhh_es_dia_divisor(date '2026-12-01')                                     as feriado_en_divisor,
  rrhh_es_dia_descontable(date '2026-10-03')                                 as sabado_descuenta,
  rrhh_feriado_paga_doble(date '2026-12-01')                                 as no_oblig_doble,
  (select count(*) from rrhh_feriado where pago_obligatorio)                 as feriados_obligatorios,
  -- Por rrhh_param() y en la ultima fecha de 2026, igual que el candado y que
  -- las vistas. Un select propio aca mediria otra cosa que el codigo.
  rrhh_param('rebaja_trabajador_pct', date '2026-12-31')                     as rebaja_apagada,
  rrhh_param('incap_dias_naturales',  date '2026-12-31')                     as incap_habiles,
  (select count(*) from pg_policies where schemaname='public'
    and tablename in ('rrhh_neto_quincena','rrhh_feriado_trabajado'))        as politicas_14,
  (select count(*) from (select unnest(array['rrhh_neto_quincena','rrhh_feriado_trabajado',
      'v_rrhh_pago_detalle','v_rrhh_pago']) as t) x
    where has_table_privilege('anon','public.'||x.t,'SELECT'))               as anon_debe_ser_0,
  -- Y el que de verdad protege el dato: nadie escribe encima ni vacia.
  (select count(*)
     from (select unnest(array['rrhh_neto_quincena','rrhh_feriado_trabajado']) as t) x
    cross join unnest(array['UPDATE','DELETE','TRUNCATE']) as p(priv)
    where has_table_privilege('authenticated','public.'||x.t, p.priv)
       or has_table_privilege('anon','public.'||x.t, p.priv))                as escritura_debe_ser_0;

commit;


-- ════════════════════════════════════════════════════════════════════════
-- DESPUES DEL COMMIT
-- ════════════════════════════════════════════════════════════════════════
--   1. PRUEBAS_NETO_QUINCENA.sql — el ensayo, con el cuerpo de ESTE archivo
--      adentro y ROLLBACK.
--   2. Cargar los netos reales con PEGADO_NETO_QUINCENA.sql, que NO va al repo
--      (PEGADO_*.sql esta en .gitignore porque el repo es PUBLICO).
--   3. esquema_check.py y sonda_columnas.py --nuevas.
--   4. Y el cuadre que ningun script da: la quincena 1-15 de octubre, limpia,
--      tiene que dar exactamente el neto cargado de cada persona.
