-- SOLO ENSAYO · PRUEBAS_NETO_QUINCENA.sql · termina en ROLLBACK, no deja nada
-- ════════════════════════════════════════════════════════════════════════
-- ENSAYO · neto fijo de quincena · CON EL PEGADO 10 ADENTRO
-- GENERADO por herramientas/ensayos/armar_ensayo_neto.py — NO editar a mano:
-- se regenera y se pierde. Para cambiar las pruebas, editar
-- herramientas/ensayos/pruebas_neto_cuerpo.sql y volver a correrlo.
--
-- ⚠️ ADENTRO VA EL CUERPO REAL DE PERSONAL_NETO_QUINCENA.sql, extraido del
-- archivo por estructura (el unico begin; y el unico commit;, sin incluirlos).
-- md5 del cuerpo extraido: c64630bb3638a362ad50a854932530e8
-- O sea que esto NO prueba una copia: prueba byte a byte lo que se va a pegar.
-- Un ensayo que valida una copia se desincroniza en silencio — se arregla el
-- pegado, el ensayo sigue validando lo viejo, y da verde.
--
-- ⚠️ TERMINA EN `rollback;`. Crea y deshace TODO: las dos tablas nuevas, la
-- columna pago_obligatorio, las cuatro funciones, las tres vistas reescritas,
-- los parametros nuevos y los datos ficticios. No deja ni una fila ni un objeto.
--
-- ⚠️ LOS MONTOS SON INVENTADOS. Netos ficticios 1100 y 1200, elegidos redondos
-- para que el valor del dia salga exacto (1100÷11 = 100, 1200÷12 = 100,
-- 1100÷10 = 110) y cada esperado se verifique a mano. No se parecen a ningun
-- sueldo de nadie. El cuadre contra lo que Lorena transfiere de verdad va en
-- PEGADO_NETO_QUINCENA.sql, que no entra al repo porque el repo es PUBLICO.
--
-- ⚠️ CUENTAS Y PERSONAS FICTICIAS, con correos @example.invalid (un TLD que la
-- RFC 2606 reserva y que no puede existir). No depende de ninguna cuenta real y
-- no escribe nada a nombre de ninguna persona de verdad.
--
-- ⚠️ TRES FILAS DEPENDEN DE REGLAS SIN CONFIRMAR y pueden cambiar de esperado
-- cuando contesten: la 10 (una ausencia sobre un feriado no descuenta — es una
-- suposicion de Andrea), las 13/16/19 (el patrono paga el 50% los primeros 3
-- dias de incapacidad) y la 23 (un feriado obligatorio en sabado no suma). Van
-- marcadas «SIN CONFIRMAR» o «PENDIENTE» en el texto de cada escenario.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── 0 · ¿QUEDO ALGO DE UNA CORRIDA ANTERIOR? ────────────────────────────
-- Se mide ANTES que todo lo demas, porque es el unico momento en que la
-- pregunta tiene sentido: tres lineas mas abajo el pegado crea las dos tablas y
-- las dos funciones, y entonces ya no se sabe si estaban de antes.
-- Sale como la PRIMERA FILA de la tabla de resultados (la -1), porque el editor
-- de Supabase muestra solo el ultimo resultado y una consulta suelta aca arriba
-- se perderia de vista.
select set_config('cc.residuo', concat_ws(' · ',
  (select count(*) from information_schema.tables where table_schema = 'public'
    and table_name = 'rrhh_neto_quincena'),
  (select count(*) from information_schema.tables where table_schema = 'public'
    and table_name = 'rrhh_feriado_trabajado'),
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'rrhh_es_dia_divisor'),
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'rrhh_es_dia_descontable')), true);

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  PROLOGO · la precondicion de datos que el pegado NO puede arreglar   ║
-- ╚══════════════════════════════════════════════════════════════════════╝
-- Va ANTES del cuerpo del pegado, y no es parte de el: el pegado se aplica tal
-- cual, byte a byte, mas abajo.
--
-- POR QUE EXISTE. El 25-dic-2026 no esta cargado en rrhh_feriado: el cierre de
-- planta del 18-dic al 11-ene lo contiene, y la exclusion de rangos solapados no
-- deja que un feriado viva adentro de un cierre. Sin esto, el ensayo NO LLEGA A
-- CORRER: los dos insert de feriado trabajado chocan con el trigger (23514) y la
-- transaccion muere en el armado, sin devolver ni una fila de resultados.
--
-- Entonces el ensayo se ARMA la precondicion: quita los dias cerrados que se
-- pisan con el 24-27 de diciembre y carga el 25 como feriado propio. Todo
-- adentro de la transaccion — el `rollback;` del final devuelve el cierre de
-- planta exactamente como estaba. Lo que se quito queda reportado en la fila 0.
--
-- ⚠️ ESTO NO ES LA SOLUCION, ES EL ANDAMIO. Que el 25-dic exista como feriado de
-- pago obligatorio en produccion lo decide Lorena, porque implica partir el
-- cierre de planta y eso se ve en la pantalla «Dias cerrados».
do $prologo$
declare v_quitados int; v_que text; v_navidad int;
begin
  select count(*), coalesce(string_agg(descripcion, ' · '), '(ninguno)')
    into v_quitados, v_que
    from rrhh_feriado
   where daterange(fecha, coalesce(fecha_fin, fecha), '[]')
      && daterange(date '2026-12-24', date '2026-12-27', '[]');
  delete from rrhh_feriado
   where daterange(fecha, coalesce(fecha_fin, fecha), '[]')
      && daterange(date '2026-12-24', date '2026-12-27', '[]');
  insert into rrhh_feriado (fecha, descripcion, tipo, creado_por)
  values (date '2026-12-25', 'Navidad', 'feriado', 'ensayo-neto');
  select count(*) into v_navidad from rrhh_feriado
   where fecha = date '2026-12-25' and tipo = 'feriado';
  if v_navidad <> 1 then
    raise exception 'ENSAYO ABORTADO: el prologo no pudo dejar el 25-dic-2026 como un '
      'feriado propio (quedaron % filas). Sin eso las pruebas 20, 21, 24 y 26 no '
      'probarian nada y darian FALLA por una causa que no es la que se esta midiendo.', v_navidad;
  end if;
  perform set_config('cc.prologo', v_quitados || ' quitado(s): ' || v_que, true);
end
$prologo$;

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  CUERPO DE PERSONAL_NETO_QUINCENA.sql — pegado tal cual              ║
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

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  FIN DEL CUERPO DEL PEGADO · desde aca, las PRUEBAS                   ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- ════════════════════════════════════════════════════════════════════════
-- LOS NUMEROS DE ESTE ENSAYO SON INVENTADOS, Y A PROPOSITO REDONDOS
-- ════════════════════════════════════════════════════════════════════════
-- Neto ficticio 1100 para las personas de octubre y noviembre, 1200 para las de
-- diciembre. No se parecen a ningun sueldo de nadie: son placeholders elegidos
-- para que el valor del dia salga EXACTO y cada esperado se pueda verificar a
-- mano sin calculadora y sin abrir la base.
--
--   1100 ÷ 11 (divisor 1-15 oct)  = 100   -> valor hora 100 ÷ 8 = 12.5
--   1100 ÷ 11 (divisor 16-31 oct) = 100
--   1100 ÷ 10 (divisor 1-15 nov)  = 110
--   1200 ÷ 12 (divisor 16-31 dic) = 100
--
-- Ninguno de los esperados sale de correr la funcion que se esta probando: estan
-- escritos a mano abajo, derivados del calendario. Si el ensayo da rojo, el
-- esperado NO se cambia para forzar verde: se revisa el pegado o se le pregunta
-- a Lorena.
-- ════════════════════════════════════════════════════════════════════════

-- ── 1 · LAS CUENTAS Y LAS PERSONAS FICTICIAS ────────────────────────────
-- Correos @example.invalid: un TLD reservado por la RFC 2606 que no existe ni
-- puede existir. No depende de ninguna cuenta real y no escribe nada a nombre
-- de ninguna persona de verdad.
insert into acceso_usuario (email, nombre, perfil, activo, nota, creado_por) values
  ('zz-socia@example.invalid', 'ZZ Socia',  'socias', true, 'ensayo-neto', 'ensayo'),
  ('zz-equipo@example.invalid','ZZ Equipo', 'equipo', true, 'ensayo-neto', 'ensayo');

with p as (
  insert into rrhh_persona (nombre, email, puesto, ingreso, creado_por)
  select 'ZZ N' || k, 'zz-n' || k || '@example.invalid', 'ensayo', '2026-01-05', 'ensayo-neto'
    from generate_series(1,15) k
  returning id, nombre
)
select set_config('cc.p' || replace(nombre,'ZZ N',''), id::text, true) from p;

-- El equipo ficticio apunta a la persona 15, para probar que NO ve el neto.
update rrhh_persona set email = 'zz-equipo@example.invalid'
 where id = current_setting('cc.p15',true)::bigint;

-- EL NETO. Vigencia 2026-10-01, igual que en produccion.
insert into rrhh_neto_quincena (persona_id, neto, vigente_desde, nota, creado_por)
select current_setting('cc.p'||k,true)::bigint,
       case when k in (6,7,8,9) then 1200 else 1100 end,
       '2026-10-01', 'FICTICIO · ensayo', 'ensayo-neto'
  from generate_series(1,15) k
 where k <> 14;   -- la 14 queda SIN neto a proposito (escenario 14)

-- Un feriado OBLIGATORIO en SABADO, inventado, para poder probar la regla del
-- fin de semana: en lo que queda de 2026 no hay ninguno real que caiga sabado.
-- El 26-dic-2026 es sabado y no se pisa con el 25 (la exclusion es por rango).
insert into rrhh_feriado (fecha, descripcion, tipo, pago_obligatorio, creado_por)
values ('2026-12-26', 'ZZ ensayo · obligatorio en sabado', 'feriado', true, 'ensayo-neto');

-- ── LOS PERMISOS. Todos ya aprobados: v_rrhh_permiso_dia solo mira aprobados.
-- resuelto_por y resuelto_en van a mano porque el trigger que los sella es
-- BEFORE UPDATE, y aca se insertan ya resueltos.
insert into rrhh_permiso (persona_id, fecha_inicio, fecha_fin, motivo, estado,
                          resuelto_por, resuelto_en, modalidad_descuento, horas,
                          incapacidad_origen, creado_por) values
  -- 2 · un dia habil de ausencia (martes 6 oct)
  (current_setting('cc.p2',true)::bigint,'2026-10-06','2026-10-06','zz',
   'aprobado','zz-socia@example.invalid',now(),'descuento',null,null,'ensayo-neto'),
  -- 3 · ausencia en sabado y domingo (3 y 4 oct)
  (current_setting('cc.p3',true)::bigint,'2026-10-03','2026-10-04','zz',
   'aprobado','zz-socia@example.invalid',now(),'descuento',null,null,'ensayo-neto'),
  -- 4 · ausencia justo sobre un feriado DE VERDAD: el 1-dic-2026 (martes).
  --     ⚠️ Antes esta prueba usaba el 12-oct-2026, y el 12-oct NO ESTA CARGADO
  --     en rrhh_feriado: la semilla de PERSONAL_CALENDARIO.sql trae 31-ago,
  --     15-sep, 1-dic y el cierre de planta, y nada mas. La prueba medía contra
  --     un feriado inexistente y daba FALLA con razon.
  (current_setting('cc.p4',true)::bigint,'2026-12-01','2026-12-01','zz',
   'aprobado','zz-socia@example.invalid',now(),'descuento',null,null,'ensayo-neto'),
  -- 5 · la quincena 16-31 oct ENTERA ausente (esa quincena no tiene feriados)
  (current_setting('cc.p5',true)::bigint,'2026-10-16','2026-10-31','zz',
   'aprobado','zz-socia@example.invalid',now(),'descuento',null,null,'ensayo-neto'),
  -- 10 · incapacidad de UN dia habil (martes 6 oct)
  (current_setting('cc.p10',true)::bigint,'2026-10-06','2026-10-06','zz',
   'aprobado','zz-socia@example.invalid',now(),'incapacidad',null,'enfermedad_comun','ensayo-neto'),
  -- 11 · incapacidad de todo octubre: cubre las DOS quincenas completas
  (current_setting('cc.p11',true)::bigint,'2026-10-01','2026-10-31','zz',
   'aprobado','zz-socia@example.invalid',now(),'incapacidad',null,'enfermedad_comun','ensayo-neto'),
  -- 12 · incapacidad viernes 2 a lunes 5: cruza un fin de semana
  (current_setting('cc.p12',true)::bigint,'2026-10-02','2026-10-05','zz',
   'aprobado','zz-socia@example.invalid',now(),'incapacidad',null,'enfermedad_comun','ensayo-neto'),
  -- 13 · incapacidad 28 oct a 3 nov: cruza dos quincenas CON DIVISORES DISTINTOS
  (current_setting('cc.p13',true)::bigint,'2026-10-28','2026-11-03','zz',
   'aprobado','zz-socia@example.invalid',now(),'incapacidad',null,'enfermedad_comun','ensayo-neto');

-- ── EL FERIADO TRABAJADO. El 25-dic-2026 es viernes y es el unico de pago
-- obligatorio que queda en el año.
insert into rrhh_feriado_trabajado (persona_id, fecha, horas, nota, creado_por) values
  (current_setting('cc.p6',true)::bigint,'2026-12-25', null, 'dia completo','ensayo-neto'),
  (current_setting('cc.p7',true)::bigint,'2026-12-25', 4,    '4 horas',     'ensayo-neto');


-- ── 2 · LA TABLA DE RESULTADOS ──────────────────────────────────────────
-- Tabla NORMAL, no `temporary`, y no es un descuido. Las mediciones de abajo
-- corren como `authenticated` (las vistas son security_invoker y exigen
-- acceso_es_socia()), y una tabla temporal creada por postgres no le da INSERT a
-- `authenticated`: los 33 inserts fallarian — o peor, si alguien los envolviera en
-- un exception handler, el ensayo saldria con la tabla vacia y el total diria
-- «0 pruebas · TODO VERDE». Creada dentro de la transaccion, el `rollback;` del
-- final la borra igual que si fuera temporal.
create table zz_res (
  n int, escenario text, esperado text, obtenido text, veredicto text
);
grant select, insert, update on zz_res to public;
-- ⚠️ Y SE LE APAGA LA SEGURIDAD POR FILAS. Sin esta linea el ensayo MUERE en la
-- primera prueba, y el motivo no se ve leyendo el archivo.
--
-- En esta base hay un disparador de eventos, `ensure_rls`, que le PRENDE la
-- seguridad por filas a toda tabla nueva de public — y otro,
-- `asistente_politicas`, que le pone las cinco politicas del asistente. O sea
-- que `zz_res` nace protegida, igual que una tabla de sueldos. Y protegida
-- significa: sin ninguna politica PERMISIVA de insercion, nadie inserta. Las
-- mediciones de abajo corren como `authenticated` (las vistas son
-- security_invoker y exigen acceso_es_socia()), asi que cada `insert into
-- zz_res` se caia con 42501 «new row violates row-level security policy».
--
-- De las tres salidas posibles —tabla temporal, apagar la seguridad, o escribir
-- desde una funcion `security definer`— esta es la mas simple y la mas facil de
-- defender: zz_res es un papel borrador con los resultados de una prueba, no
-- tiene un solo dato de nadie, y vive lo que dura la transaccion.
alter table zz_res disable row level security;

-- DOS AYUDANTES, creados todavia como postgres: `authenticated` no puede crear
-- funciones en el esquema public.
--
-- zz_n() es el que importa. La division numerica de Postgres devuelve ~20
-- decimales: 1100/11 no es «100», es 100.00000000000000000000. Comparar eso
-- contra un esperado escrito a mano daria FALLA siempre, y la tentacion seria
-- comparar por un lado y mostrar por otro — que es exactamente como un ensayo
-- anterior dijo OK con los numeros distintos a la vista. Aca el esperado se
-- compara contra el MISMO texto que se imprime.
--
-- ¿Y el `round` no tapa una diferencia? Tapa hasta la decima cifra decimal, y
-- ninguna de las cuentas de este ensayo puede errar por tan poco: todas las
-- divisiones son exactas (1100÷11, 1200÷12, 1100÷10, 100÷8) y cualquier error de
-- verdad —un dia de mas, un divisor equivocado, un porcentaje mal aplicado— mueve
-- el numero en decenas, no en milmillonesimas. Esta ahi para que un artefacto de
-- escala no haga fallar una fila que esta bien, no para suavizar un desvio.
-- Se recortan los ceros SOLO despues de un punto decimal. Un `'0+$'` a secas
-- convertiria 100 en 1, y nadie lo veria venir.
create or replace function zz_n(p numeric) returns text
language sql immutable as $zz$
  select regexp_replace(regexp_replace(round(p, 10)::text, '(\.\d*?)0+$', '\1'), '\.$', '')
$zz$;

create or replace function zz_pago(p_k text, p_q text)
  returns table (final numeric, base numeric, divisor numeric, valor_dia numeric,
                 descuentos numeric, incapacidades numeric, feriados numeric, fert_n bigint)
language sql set search_path = public as $zz$
  select v.final, v.base, v.divisor, v.valor_dia,
         v.descuentos, v.incapacidades, v.feriados_trab, v.feriados_trab_n
    from v_rrhh_pago v
   where v.persona_id = current_setting('cc.p'||p_k,true)::bigint and v.quincena = p_q;
$zz$;


-- Todo lo que sigue se mide COMO LA SOCIA: las tres vistas son security_invoker
-- y exigen acceso_es_socia(). Medir como postgres probaria otra cosa.
select set_config('request.jwt.claims',
  json_build_object('email','zz-socia@example.invalid','role','authenticated')::text, true);
select set_config('role','authenticated', true);
do $$
begin
  if not coalesce(acceso_es_socia(), false) then
    perform set_config('role','postgres', true);
    raise exception 'ENSAYO ABORTADO: la socia ficticia no quedo reconocida por '
      'acceso_es_socia(). Sin eso las vistas devuelven CERO filas y todo el ensayo '
      'daria «0 = 0» en verde sin haber probado nada.';
  end if;
end $$;


-- -1 · ¿QUEDO RESIDUO DE UNA CORRIDA ANTERIOR? Medido ANTES de que el pegado
--      cree nada, que es el unico momento en que la pregunta tiene sentido. Si
--      da algo distinto de cuatro ceros, un ensayo anterior NO se deshizo y hay
--      que avisar antes de seguir: el pegado 10 todavia no se aplico nunca.
insert into zz_res values (-1,
  'residuo antes de empezar · tabla neto · tabla feriado trabajado · funcion divisor · funcion descontable',
  '0 · 0 · 0 · 0',
  coalesce(nullif(current_setting('cc.residuo', true),''), '(no se midio)'),
  null);


-- 0 · QUE TUVO QUE TOCAR EL PROLOGO. No es una prueba: es informacion, y la
--     parte que Lorena tiene que decidir. Si dice «1 quitado(s): Cierre de planta
--     de fin de año», significa que el 25-dic no existe como feriado en
--     produccion y que el pago doble no puede dispararse hasta que eso se arregle.
--     El rollback devuelve el cierre como estaba.
insert into zz_res values (0,
  'INFO · dias cerrados que el prologo tuvo que quitar para poder probar el 25-dic',
  '(lo que diga, no es una falla)',
  coalesce(nullif(current_setting('cc.prologo', true),''), '(el prologo no corrio)'),
  'INFO');


-- ════════════════════════════════════════════════════════════════════════
-- BLOQUE A · EL DIVISOR Y EL VALOR DEL DIA
-- ════════════════════════════════════════════════════════════════════════

-- 1 · El divisor de cada quincena, contado contra el calendario a mano.
--     1-15 oct: jue 1, vie 2, lun 5 a vie 9, lun 12 a jue 15 = 11.
insert into zz_res
select 1, 'divisor · 1-15 oct · 16-31 oct · 1-15 nov · 16-31 dic',
       '11 · 11 · 10 · 12',
       concat_ws(' · ', rrhh_dias_divisor('2026-10-01','2026-10-15'),
                        rrhh_dias_divisor('2026-10-16','2026-10-31'),
                        rrhh_dias_divisor('2026-11-01','2026-11-15'),
                        rrhh_dias_divisor('2026-12-16','2026-12-31')), null;

-- 2 · EL FERIADO ESTA EN EL DIVISOR. 1-15 oct TIENE feriado (12-oct) y 16-31 oct
--     NO, y las dos dan 11: el feriado no se resta. Es la decision de Lorena.
-- 1-15 dic TIENE feriado (el 1-dic) y 16-31 oct no, y las dos dan 11.
-- ⚠️ Antes comparaba 1-15 oct contra 16-31 oct: NINGUNA de las dos tiene feriado
-- cargado, asi que la prueba pasaba sin probar nada.
insert into zz_res
select 2, 'quincena CON feriado (1-15 dic) y quincena SIN feriado (16-31 oct): mismo divisor',
       'si · 11 = 11',
       case when rrhh_dias_divisor('2026-12-01','2026-12-15')
               = rrhh_dias_divisor('2026-10-16','2026-10-31') then 'si · ' else 'NO · ' end
       || rrhh_dias_divisor('2026-12-01','2026-12-15') || ' = '
       || rrhh_dias_divisor('2026-10-16','2026-10-31'), null;

-- 3 · Los dos conceptos NO son el mismo. 1-15 oct tiene 11 dias de divisor pero
--     solo 10 descontables, porque el 12-oct es feriado.
insert into zz_res
select 3, 'divisor (11) y dias descontables (10) de 1-15 DIC · el feriado separa los dos',
       '11 · 10',
       rrhh_dias_divisor('2026-12-01','2026-12-15') || ' · ' ||
       (select count(*) from generate_series(0,14) g(i)
         where rrhh_es_dia_descontable(date '2026-12-01' + g.i)), null;

-- 4 · Dia por dia, los casos de borde del divisor: sabado, domingo, feriado.
insert into zz_res
select 4, 'es_dia_divisor: jue 1 oct · sab 3 · dom 4 · feriado mar 1 dic',
       't · f · f · t',
       concat_ws(' · ', left(rrhh_es_dia_divisor('2026-10-01')::text,1),
                        left(rrhh_es_dia_divisor('2026-10-03')::text,1),
                        left(rrhh_es_dia_divisor('2026-10-04')::text,1),
                        left(rrhh_es_dia_divisor('2026-12-01')::text,1)), null;

-- 5 · Y del descontable: el feriado NO descuenta (suposicion de Andrea).
insert into zz_res
select 5, 'es_dia_descontable: jue 1 oct · sab 3 · dom 4 · feriado mar 1 dic',
       't · f · f · f',
       concat_ws(' · ', left(rrhh_es_dia_descontable('2026-10-01')::text,1),
                        left(rrhh_es_dia_descontable('2026-10-03')::text,1),
                        left(rrhh_es_dia_descontable('2026-10-04')::text,1),
                        left(rrhh_es_dia_descontable('2026-12-01')::text,1)), null;


-- ════════════════════════════════════════════════════════════════════════
-- BLOQUE B · EL NETO FIJO COMO BASE
-- ════════════════════════════════════════════════════════════════════════

-- 6 · QUINCENA LIMPIA. Sin ausencias, sin extras: el neto, redondo, sin restas.
--     Es la prueba que cierra el tema: antes esto daba el bruto÷2 menos un 6,49%
--     y no calzaba. Ahora el neto ES el dato.
insert into zz_res
select 6, 'quincena limpia 1-15 oct · neto ficticio 1100 · final · base · divisor · valor dia',
       '1100 · 1100 · 11 · 100',
       concat_ws(' · ', zz_n(final), zz_n(base), zz_n(divisor), zz_n(valor_dia))
  from zz_pago('1','2026-10-Q1');

-- 7 · El valor de la HORA sale del valor del dia, no del mes: 100 ÷ 8 = 12.5.
insert into zz_res
select 7, 'valor de la hora en 1-15 oct · valor dia 100 ÷ jornada 8',
       '12.5',
       zz_n(valor_dia / rrhh_param('jornada_horas','2026-10-15'))
  from zz_pago('1','2026-10-Q1');

-- 14 · SIN NETO CARGADO, NINGUN RENGLON. Ni una base en cero, ni un numero
--      inventado: la persona no sale. Un cero en la pantalla de pago se lee como
--      «no le toca nada» y alguien transfiere cero.
insert into zz_res
select 14, 'persona SIN neto cargado · filas en v_rrhh_pago · renglones en el desglose',
       '0 · 0',
       (select count(*) from v_rrhh_pago v
         where v.persona_id = current_setting('cc.p14',true)::bigint) || ' · ' ||
       (select count(*) from v_rrhh_pago_detalle d
         where d.persona_id = current_setting('cc.p14',true)::bigint), null;


-- ════════════════════════════════════════════════════════════════════════
-- BLOQUE C · AUSENCIAS
-- ════════════════════════════════════════════════════════════════════════

-- 8 · UN DIA HABIL DE AUSENCIA = neto − neto÷11.  1100 − 100 = 1000.
insert into zz_res
select 8, 'ausencia de 1 dia habil (mar 6 oct) · final · descuento',
       '1000 · -100',
       concat_ws(' · ', zz_n(final), zz_n(descuentos))
  from zz_pago('2','2026-10-Q1');

-- 9 · SABADO Y DOMINGO NO DESCUENTAN. Dos dias de ausencia, cero colones.
insert into zz_res
select 9, 'ausencia en sab 3 y dom 4 oct · final · descuento',
       '1100 · 0',
       concat_ws(' · ', zz_n(final), zz_n(descuentos))
  from zz_pago('3','2026-10-Q1');

-- 10 · AUSENCIA SOBRE UN FERIADO = cero descuento.
--      ⚠️ Esto es la SUPOSICION de Andrea (el feriado se paga igual), SIN
--      CONFIRMAR por la contadora. Si se confirma al revés el esperado de esta
--      fila cambia a 1000 · -100, y se arregla rrhh_es_dia_descontable().
insert into zz_res
select 10, 'ausencia justo el feriado del 1 dic · final · descuento · SIN CONFIRMAR',
       '1100 · 0',
       concat_ws(' · ', zz_n(final), zz_n(descuentos))
  from zz_pago('4','2026-12-Q1');

-- 11 · LA QUINCENA ENTERA AUSENTE = cero, exacto. 16-31 oct no tiene feriados,
--      asi que los 11 dias del divisor son los 11 descontables: 11 × 100 = 1100.
--      Y el piso: el final no puede quedar NEGATIVO.
insert into zz_res
select 11, 'quincena 16-31 oct entera ausente · final · descuento · final >= 0',
       '0 · -1100 · si',
       concat_ws(' · ', zz_n(final), zz_n(descuentos),
                 case when final >= 0 then 'si' else 'NEGATIVO' end)
  from zz_pago('5','2026-10-Q2');


-- ════════════════════════════════════════════════════════════════════════
-- BLOQUE D · INCAPACIDADES
-- ════════════════════════════════════════════════════════════════════════
-- ⚠️ EL PORCENTAJE NO ESTA CONFIRMADO. Hoy rrhh_param dice que el patrono paga
-- el 50% los primeros 3 dias y 0% desde el 4. Eso sigue SIN confirmar por la
-- contadora, y esta anotado en PREGUNTAS_contadora_feriados.md. Lo que este
-- bloque prueba y SI esta confirmado es otra cosa: QUE DIAS SE CUENTAN (solo
-- habiles) y CUANTO VALE CADA UNO (neto ÷ divisor, igual que un permiso).
-- Las filas marcadas «SIN CONFIRMAR» pueden cambiar de esperado cuando conteste;
-- las otras no.

-- 12 · UN DIA HABIL DE INCAPACIDAD. El VALOR DEL DIA aplicado tiene que ser
--      exactamente neto ÷ divisor = 100. Eso es lo confirmado, y se mide solo.
insert into zz_res
select 12, 'incapacidad de 1 dia habil · valor del dia aplicado = neto ÷ divisor',
       '100',
       zz_n(max(d.tarifa))
  from v_rrhh_pago_detalle d
 where d.persona_id = current_setting('cc.p10',true)::bigint
   and d.concepto = 'incapacidad';

-- 13 · Y el monto, que SI depende del porcentaje sin confirmar: un dia, dia_n=1,
--      el patrono paga 50% -> descuenta la mitad de 100.
insert into zz_res
select 13, 'incapacidad de 1 dia habil · final · descuento · SIN CONFIRMAR (patrono 50%)',
       '1050 · -50',
       concat_ws(' · ', zz_n(final), zz_n(incapacidades))
  from zz_pago('10','2026-10-Q1');

-- 15 · CUBRE TODA LA QUINCENA 16-31 OCT, y descuenta EXACTAMENTE EL NETO, NI UN
--      COLON MAS. La incapacidad arranca el 1 de octubre, asi que para esta
--      quincena los 3 dias del patrono YA PASARON (dia_n >= 16) y el porcentaje
--      no se mete: 11 dias × 100 = 1100. Final 0, no negativo.
insert into zz_res
select 15, 'incapacidad que cubre toda la quincena 16-31 oct · descuento · final · <= neto',
       '-1100 · 0 · si',
       concat_ws(' · ', zz_n(incapacidades), zz_n(final),
                 case when -incapacidades <= base then 'si' else 'MAS QUE EL NETO' end)
  from zz_pago('11','2026-10-Q2');

-- 16 · La MISMA incapacidad en la otra quincena, 1-15 oct. Los 11 dias del
--      divisor son los 11 descontables: 1-15 oct NO tiene ningun feriado cargado.
--      Los dias naturales 1 y 2 (jue 1 y vie 2) caen dentro de los 3 del patrono.
--      2 dias × 50 + 9 dias × 100 = 1000.  Final 1100 − 1000 = 100.
insert into zz_res
select 16, 'la misma incapacidad en 1-15 oct · descuento · final · SIN CONFIRMAR',
       '-1000 · 100',
       concat_ws(' · ', zz_n(incapacidades), zz_n(final))
  from zz_pago('11','2026-10-Q1');

-- 17 · CRUZA UN FIN DE SEMANA Y NO LO COBRA. Viernes 2 a lunes 5: cuatro dias
--      naturales, DOS descontables. El sabado y el domingo no cuentan.
--      El plazo de 3 dias del patrono SI corre en calendario: el lunes es dia 4.
--      1 dia × 50 (vie, dia_n 1) + 1 dia × 100 (lun, dia_n 4) = 150.
insert into zz_res
select 17, 'incapacidad vie 2 a lun 5 oct · dias cobrados · descuento · final',
       '2 · -150 · 950',
       (select zz_n(max(d.cantidad)) from v_rrhh_pago_detalle d
         where d.persona_id = current_setting('cc.p12',true)::bigint
           and d.concepto = 'incapacidad' and d.quincena = '2026-10-Q1')
       || ' · ' || zz_n(incapacidades) || ' · ' || zz_n(final)
  from zz_pago('12','2026-10-Q1');

-- 18 · CRUZA DOS QUINCENAS CON DIVISORES DISTINTOS, y cada mitad usa el SUYO.
--      Esta es la fila que prueba que el divisor no esta congelado en 11.
--        16-31 oct: 28, 29 y 30 (mie, jue, vie) = 3 dias, divisor 11, dia 100.
--                   dia_n 1, 2 y 3 -> los 3 del patrono -> 3 × 50 = 150.
--        1-15 nov : lun 2 y mar 3 = 2 dias, divisor 10, dia 110.
--                   dia_n 6 y 7 -> fuera del plazo -> 2 × 110 = 220.
insert into zz_res
select 18, 'incapacidad 28 oct a 3 nov · valor dia de cada quincena (100 y 110)',
       '100 · 110',
       (select zz_n(valor_dia) from zz_pago('13','2026-10-Q2'))
       || ' · ' ||
       (select zz_n(valor_dia) from zz_pago('13','2026-11-Q1')), null;

insert into zz_res
select 19, 'incapacidad 28 oct a 3 nov · descuento de cada mitad · SIN CONFIRMAR',
       '-150 · -220',
       (select zz_n(incapacidades) from zz_pago('13','2026-10-Q2'))
       || ' · ' ||
       (select zz_n(incapacidades) from zz_pago('13','2026-11-Q1')), null;


-- ════════════════════════════════════════════════════════════════════════
-- BLOQUE E · FERIADO TRABAJADO
-- ════════════════════════════════════════════════════════════════════════

-- 20 · DIA COMPLETO EN EL 25-DIC. Suma UN valor de dia: 1200 ÷ 12 = 100.
--      Con el feriado ya pagado dentro del neto, el dia queda al doble.
insert into zz_res
select 20, 'feriado trabajado 25-dic dia completo · neto ficticio 1200 · final · suma · cuantos',
       '1300 · 100 · 1',
       concat_ws(' · ', zz_n(final), zz_n(feriados), fert_n)
  from zz_pago('6','2026-12-Q2');

-- 21 · POR HORAS. 4 h × (100 ÷ 8) = 4 × 12.5 = 50.
insert into zz_res
select 21, 'feriado trabajado 25-dic · 4 horas · final · suma',
       '1250 · 50',
       concat_ws(' · ', zz_n(final), zz_n(feriados))
  from zz_pago('7','2026-12-Q2');

-- 22 · UN FERIADO QUE NO ES DE PAGO OBLIGATORIO NO SUMA NADA, y el intento NO
--      queda guardado en cero: se RECHAZA. El 1-dic-2026 es martes y de pago no
--      obligatorio. Guardarlo en cero seria peor: la fila existiria, Lorena la
--      veria en la lista y pensaria que algo se pago.
do $$
begin
  begin
    insert into rrhh_feriado_trabajado (persona_id, fecha, nota, creado_por)
    values (current_setting('cc.p8',true)::bigint,'2026-12-01','no obligatorio','ensayo-neto');
    insert into zz_res values (22,'feriado NO obligatorio (1-dic, martes) se rechaza',
      'rechazado 23514','SE GUARDO',null);
  exception
    when check_violation then
      insert into zz_res values (22,'feriado NO obligatorio (1-dic, martes) se rechaza',
        'rechazado 23514','rechazado 23514',null);
    when others then
      insert into zz_res values (22,'feriado NO obligatorio (1-dic, martes) se rechaza',
        'rechazado 23514','otro error: '||sqlstate,null);
  end;
end $$;

-- 23 · UN FERIADO OBLIGATORIO QUE CAE SABADO TAMPOCO SUMA. El 26-dic-2026 que
--      este ensayo cargo como obligatorio es sabado.
--      ⚠️ PENDIENTE DE LA CONTADORA: podria corresponder el dia sencillo igual.
--      Si contesta que si, cambia rrhh_feriado_paga_doble() y esta fila.
insert into zz_res
select 23, 'feriado obligatorio en SABADO (26-dic) · paga doble? · PENDIENTE',
       'f',
       left(rrhh_feriado_paga_doble('2026-12-26')::text,1), null;

do $$
begin
  begin
    insert into rrhh_feriado_trabajado (persona_id, fecha, nota, creado_por)
    values (current_setting('cc.p9',true)::bigint,'2026-12-26','sabado','ensayo-neto');
    insert into zz_res values (24,'cargar un feriado obligatorio en sabado se rechaza',
      'rechazado 23514','SE GUARDO',null);
  exception
    when check_violation then
      insert into zz_res values (24,'cargar un feriado obligatorio en sabado se rechaza',
        'rechazado 23514','rechazado 23514',null);
    when others then
      insert into zz_res values (24,'cargar un feriado obligatorio en sabado se rechaza',
        'rechazado 23514','otro error: '||sqlstate,null);
  end;
end $$;

-- 25 · EL MISMO FERIADO DOS VECES A LA MISMA PERSONA SE RECHAZA. Sin esto el
--      dia se pagaria triple y nada avisaria.
do $$
begin
  begin
    insert into rrhh_feriado_trabajado (persona_id, fecha, nota, creado_por)
    values (current_setting('cc.p6',true)::bigint,'2026-12-25','repetido','ensayo-neto');
    insert into zz_res values (25,'el mismo feriado dos veces a la misma persona',
      'rechazado 23505','SE GUARDO · se pagaria doble de mas',null);
  exception
    when unique_violation then
      insert into zz_res values (25,'el mismo feriado dos veces a la misma persona',
        'rechazado 23505','rechazado 23505',null);
    when others then
      insert into zz_res values (25,'el mismo feriado dos veces a la misma persona',
        'rechazado 23505','otro error: '||sqlstate,null);
  end;
end $$;

-- 26 · Y si alguien DESMARCA el pago obligatorio despues de cargarlo, el
--      adicional deja de pagarse. La vista vuelve a preguntar, no confia en que
--      el trigger ya valido al insertar.
do $$
declare v_antes numeric; v_despues numeric;
begin
  select feriados into v_antes from zz_pago('6','2026-12-Q2');
  perform set_config('role','postgres', true);
  update rrhh_feriado set pago_obligatorio = false where fecha = date '2026-12-25';
  perform set_config('role','authenticated', true);
  select feriados into v_despues from zz_pago('6','2026-12-Q2');
  insert into zz_res values (26,
    'si se desmarca pago_obligatorio del 25-dic, el adicional deja de pagarse',
    '100 -> 0', coalesce(zz_n(v_antes),'?') || ' -> ' || coalesce(zz_n(v_despues),'0'), null);
  -- Se deja como estaba, que las filas de abajo no midan sobre un 25-dic roto.
  perform set_config('role','postgres', true);
  update rrhh_feriado set pago_obligatorio = true where fecha = date '2026-12-25';
  perform set_config('role','authenticated', true);
end $$;


-- ════════════════════════════════════════════════════════════════════════
-- BLOQUE F · LA REBAJA APAGADA, Y EL DESGLOSE COMPLETO
-- ════════════════════════════════════════════════════════════════════════

-- 27 · LA REBAJA NO APARECE. Con el parametro en 0 el renglon no se emite: un
--      «−₡0» en la unica pantalla que hay que leer entera es ruido. El concepto
--      queda en el codigo para poder reconstruir una quincena vieja.
insert into zz_res
select 27, 'rebaja del trabajador · parametro vigente · renglones de rebaja · monto',
       '0 · 0 · 0',
       zz_n(rrhh_param('rebaja_trabajador_pct','2026-10-15'))
       || ' · ' ||
       (select count(*) from v_rrhh_pago_detalle d where d.concepto = 'rebaja'
         and d.quincena = '2026-10-Q1')
       || ' · ' || (select zz_n(coalesce(rebaja,0)) from v_rrhh_pago v
                     where v.persona_id = current_setting('cc.p1',true)::bigint
                       and v.quincena = '2026-10-Q1'), null;

-- 28 · `incap_dias_naturales` quedo en 0 Y SE SIGUE LEYENDO. Si el codigo dejara
--      de consultarlo, volverlo a 1 no haria nada y nadie se enteraria.
insert into zz_res
select 28, 'incap_dias_naturales vigente · y el SQL de la vista lo lee',
       '0 · si',
       zz_n(rrhh_param('incap_dias_naturales','2026-10-15')) || ' · ' ||
       case when (select pg_get_viewdef('v_rrhh_pago_detalle'::regclass)::text)
                 like '%incap_dias_naturales%' then 'si' else 'NO · quedo de adorno' end, null;

-- 29 · EL DESGLOSE SE VE ENTERO, y suma exactamente el final. Si los renglones
--      no suman el total, la pantalla miente en alguno de los dos lados.
insert into zz_res
select 29, 'el desglose de la quincena entera ausente suma el final · renglones · suma = final',
       '2 · si',
       (select count(*)::text from v_rrhh_pago_detalle d
         where d.persona_id = current_setting('cc.p5',true)::bigint
           and d.quincena = '2026-10-Q2')
       || ' · ' ||
       case when (select sum(d.monto) from v_rrhh_pago_detalle d
                   where d.persona_id = current_setting('cc.p5',true)::bigint
                     and d.quincena = '2026-10-Q2')
               = (select final from zz_pago('5','2026-10-Q2'))
            then 'si' else 'NO SUMA' end, null;

-- 30 · Y LA BASE MUESTRA EL DIVISOR. Sin esto el valor del dia es una caja
--      negra: Lorena ve «−₡100» y no tiene de donde sacar que son 1100 ÷ 11.
insert into zz_res
select 30, 'el renglon de base dice el divisor y el valor del dia · cantidad · unidad · tarifa',
       '11 · dias habiles · 100',
       concat_ws(' · ', zz_n(d.cantidad), d.unidad, zz_n(d.tarifa))
  from v_rrhh_pago_detalle d
 where d.persona_id = current_setting('cc.p1',true)::bigint
   and d.quincena = '2026-10-Q1' and d.concepto = 'base';


-- ════════════════════════════════════════════════════════════════════════
-- BLOQUE G · QUIEN VE EL NETO, Y QUE NO SE PUEDE EDITAR
-- ════════════════════════════════════════════════════════════════════════

-- 31 · EL EQUIPO NO VE EL NETO DE NADIE. El grant de select es a
--      `authenticated`, o sea todo el equipo: lo unico que frena es la RLS.
--      Se mide con una cuenta de perfil 'equipo' de verdad, no suponiendo.
do $$
declare v_neto bigint; v_pago bigint; v_mio bigint;
begin
  perform set_config('request.jwt.claims',
    json_build_object('email','zz-equipo@example.invalid','role','authenticated')::text, true);
  if coalesce(acceso_es_socia(), false) then
    perform set_config('role','postgres', true);
    raise exception 'ENSAYO ABORTADO: la cuenta de perfil «equipo» salio reconocida como '
      'socia. Entonces la fila 31 no probaria nada.';
  end if;
  select count(*) into v_neto from rrhh_neto_quincena;
  select count(*) into v_pago from v_rrhh_pago;
  -- Su propio feriado trabajado SI lo puede ver: la politica lo permite y no es
  -- plata de otra persona. La 15 no tiene ninguno, asi que esto da 0 igual; lo
  -- que se mide es que la consulta no explote.
  select count(*) into v_mio from rrhh_feriado_trabajado;
  insert into zz_res values (31,
    'cuenta de perfil «equipo» · filas de neto que ve · filas de v_rrhh_pago que ve',
    '0 · 0', v_neto || ' · ' || v_pago, null);
exception when insufficient_privilege then
  insert into zz_res values (31,
    'cuenta de perfil «equipo» · filas de neto que ve · filas de v_rrhh_pago que ve',
    '0 · 0', 'permission denied (tambien sirve)', null);
end $$;

select set_config('request.jwt.claims',
  json_build_object('email','zz-socia@example.invalid','role','authenticated')::text, true);

-- 32 · APPEND-ONLY, LAS DOS CERRADURAS. Ni grant de update ni politica de
--      update: un neto corregido es una fila nueva, no un numero sobreescrito.
--      De estos montos cuelga una transferencia que ya se hizo.
-- ⚠️ ESTA PRUEBA SE REESCRIBIO DOS VECES, Y LAS DOS POR LA MISMA RAZON: medía
-- permisos en vez de medir lo que pasa.
--   v1 contaba `pg_policies` con cmd in ('UPDATE','DELETE') y esperaba 0. Daba
--      FALLA: hay 2, pero son las RESTRICTIVAS del asistente, que no habilitan
--      nada. Estaba contando candados a favor.
--   v2 contaba solo las permisivas y preguntaba `has_table_privilege`. Pasaba,
--      pero seguia sin probar lo unico que importa: que el dato no se pueda
--      cambiar. Un permiso ausente es un indicio; una fila intacta es la prueba.
--   v3, esta: INTENTA el update y el delete de verdad y mira FILAS AFECTADAS y
--      CONTENIDO. Y los intenta DOS veces: tal como queda el pegado, y despues
--      con el grant puesto a mano — que es el escenario que de verdad preocupa,
--      el dia que alguien corra un `grant all` sobre el esquema.
--
-- Medido contra PostgreSQL 17 el 16-oct-2026: sin grant las dos operaciones dan
-- 42501; con el grant puesto dan 0 FILAS AFECTADAS y ningun error. O sea que hay
-- DOS cerraduras independientes, y la de abajo (las politicas) aguanta sola.
-- ⚠️ Pero aguanta EN SILENCIO: 0 filas no es un error, y quien corra ese update
-- creeria que funciono. Queda dicho; no se cambia el mecanismo, porque es el
-- mismo que usan las otras nueve tablas del modulo y la consistencia vale mas
-- que un candado suelto.
do $$
declare v_n int; v_antes numeric; v_despues numeric; v_filas int; v_res text := '';
begin
  select nq.neto into v_antes from rrhh_neto_quincena nq
   where nq.persona_id = current_setting('cc.p1',true)::bigint;

  -- 1 · TAL COMO QUEDA EL PEGADO: sin grant de update ni de delete.
  begin
    update rrhh_neto_quincena set neto = 1
     where persona_id = current_setting('cc.p1',true)::bigint;
    get diagnostics v_n = row_count;
    v_res := v_res || v_n || ' filas';
  exception when insufficient_privilege then v_res := v_res || 'denegado';
           when others then v_res := v_res || 'error ' || sqlstate;
  end;
  begin
    delete from rrhh_neto_quincena
     where persona_id = current_setting('cc.p1',true)::bigint;
    get diagnostics v_n = row_count;
    v_res := v_res || ' · ' || v_n || ' filas';
  exception when insufficient_privilege then v_res := v_res || ' · denegado';
           when others then v_res := v_res || ' · error ' || sqlstate;
  end;

  -- 2 · Y AHORA CON EL GRANT, para ver si queda algo frenando.
  perform set_config('role','postgres', true);
  execute 'grant update, delete on rrhh_neto_quincena to authenticated';
  perform set_config('role','authenticated', true);
  begin
    update rrhh_neto_quincena set neto = 1
     where persona_id = current_setting('cc.p1',true)::bigint;
    get diagnostics v_n = row_count;
    v_res := v_res || ' · ' || v_n || ' filas';
  exception when others then v_res := v_res || ' · error ' || sqlstate;
  end;
  begin
    delete from rrhh_neto_quincena
     where persona_id = current_setting('cc.p1',true)::bigint;
    get diagnostics v_n = row_count;
    v_res := v_res || ' · ' || v_n || ' filas';
  exception when others then v_res := v_res || ' · error ' || sqlstate;
  end;
  -- 3 · Y EL TRUNCATE, que es el que no frena ninguna politica: no borra filas
  --     una por una, vacia la tabla, y la seguridad por filas no lo ve pasar. Lo
  --     unico que lo detiene es NO TENER EL PRIVILEGIO. Por eso el pegado revoca
  --     de `authenticated` y no solo de `anon`.
  begin
    execute 'truncate rrhh_neto_quincena';
    v_res := v_res || ' · truncate PASO';
  exception when insufficient_privilege then v_res := v_res || ' · truncate denegado';
           when others then v_res := v_res || ' · truncate error ' || sqlstate;
  end;
  perform set_config('role','postgres', true);
  execute 'revoke update, delete on rrhh_neto_quincena from authenticated';
  perform set_config('role','authenticated', true);

  -- 4 · Y EL DATO. Cuatro intentos de escritura y el neto tiene que estar igual.
  select nq.neto into v_despues from rrhh_neto_quincena nq
   where nq.persona_id = current_setting('cc.p1',true)::bigint;
  select count(*) into v_filas from rrhh_neto_quincena nq
   where nq.persona_id = current_setting('cc.p1',true)::bigint;
  insert into zz_res values (32,
    'append-only CON FILAS · update y delete sin grant · con grant · truncate · el dato',
    'denegado · denegado · 0 filas · 0 filas · truncate denegado · igual',
    v_res || ' · ' || case when v_despues = v_antes and v_filas = 1 then 'igual'
                           when v_filas <> 1 then 'LO BORRO'
                           else 'LO CAMBIO' end,
    null);
end $$;

-- Y el permiso, aparte y como lo que es: un indicio, no la prueba.
insert into zz_res
-- ⚠️ ESTA FILA ES LA QUE DESTAPO EL HUECO. Antes del 16-oct decia `f · f` en mi
-- base local y `t · t` en Supabase, y la diferencia era que mi base no tenia
-- configurado el `alter default privileges ... grant all` que Supabase si trae:
-- toda tabla nueva nace con TODOS los privilegios para authenticated. Ahora el
-- pegado los revoca, asi que tiene que dar f en los tres lados — y el TRUNCATE es
-- el que importa, porque es el unico que la seguridad por filas no frena.
select 34, 'privilegios de escritura · authenticated upd · del · truncate · anon truncate',
       'f · f · f · f',
       left(has_table_privilege('authenticated','rrhh_neto_quincena','UPDATE')::text,1) || ' · ' ||
       left(has_table_privilege('authenticated','rrhh_neto_quincena','DELETE')::text,1) || ' · ' ||
       left(has_table_privilege('authenticated','rrhh_neto_quincena','TRUNCATE')::text,1) || ' · ' ||
       left(has_table_privilege('anon','rrhh_neto_quincena','TRUNCATE')::text,1), null;

-- 33 · ANON NO LLEGA A NADA. La anon key viaja dentro de index.html, que esta en
--      un repo PUBLICO. Se mide llamando de verdad como anon, no leyendo grants.
do $$
declare v text := '';
begin
  perform set_config('role','anon', true);
  begin
    perform (select count(*) from rrhh_neto_quincena);  v := v || 'LEYO neto';
  exception when insufficient_privilege then v := v || 'denegado';
            when others then                 v := v || 'denegado('||sqlstate||')';
  end;
  begin
    perform (select count(*) from v_rrhh_pago);         v := v || ' · LEYO pago';
  exception when insufficient_privilege then v := v || ' · denegado';
            when others then                 v := v || ' · denegado('||sqlstate||')';
  end;
  begin
    perform rrhh_dias_divisor('2026-10-01','2026-10-15'); v := v || ' · CORRIO divisor';
  exception when insufficient_privilege then v := v || ' · denegado';
            when others then                 v := v || ' · denegado('||sqlstate||')';
  end;
  perform set_config('role','postgres', true);
  insert into zz_res values (33,
    'como anon de verdad: leer el neto · leer v_rrhh_pago · correr rrhh_dias_divisor',
    'denegado · denegado · denegado', v, null);
end $$;

select set_config('role','postgres', true);


-- ════════════════════════════════════════════════════════════════════════
-- EL VEREDICTO
-- ════════════════════════════════════════════════════════════════════════
-- El veredicto se calcula comparando las dos columnas que se MUESTRAN. En un
-- ensayo anterior el veredicto salia de otra cuenta que la impresa y decia OK
-- con los numeros distintos a la vista.
update zz_res set veredicto =
  case when obtenido is null                              then 'SIN DATO'
       when btrim(obtenido) = btrim(esperado)             then 'OK'
       else 'FALLA' end
 where n between 1 and 34 or n = -1;

-- Y las filas que el ensayo tenia que producir y podrian no existir: si un
-- `select ... from zz_pago(...)` no devuelve filas, el insert no inserta nada y
-- la prueba DESAPARECE en silencio en vez de fallar.
insert into zz_res
select n, 'ESTA PRUEBA NO CORRIO · la consulta no devolvio ninguna fila',
       'la fila existe', 'NO EXISTE', 'FALLA'
  from generate_series(1,34) n
 where n not in (select r.n from zz_res r);

-- EL VEREDICTO VA PRIMERO, y las filas que no estan en OK van arriba.
-- Pedido de Lorena el 16-oct: con el veredicto en la ultima columna hay que
-- arrastrar la tabla a la derecha para saber si algo fallo, y con 36 filas hacen
-- falta cuatro fotos. Asi se confirma con una.
--
-- El orden es: el TOTAL arriba de todo, despues lo que FALLA o quedo SIN DATO,
-- despues las INFO, y al final las OK en su numero. Si todo esta bien, la primera
-- fila dice TODO VERDE y lo que sigue son las dos informativas y las 34 en orden.
--
-- Va envuelto en una subconsulta porque el `order by` de un UNION solo entiende
-- posiciones, y `grupo` no se muestra: ordenar por algo que no se ve, mostrando
-- otra cosa, es como se arma una tabla que miente.
select t.veredicto                                   as "veredicto",
       t.n                                           as "#",
       t.escenario                                   as "escenario",
       t.esperado                                    as "esperado",
       t.obtenido                                    as "obtenido"
  from (
    select r.veredicto, r.n, r.escenario, r.esperado,
           coalesce(r.obtenido,'(nada)')             as obtenido,
           case when r.veredicto in ('FALLA','SIN DATO') then 1
                when r.veredicto = 'INFO'                then 2
                else 3 end                           as grupo
      from zz_res r
    union all
    select (select case when count(*) < 34                    then 'FALTAN PRUEBAS · NO PEGAR'
                        when count(*) filter (where veredicto <> 'OK') = 0
                                                              then 'TODO VERDE'
                        else 'HAY ROJO · NO PEGAR' end
              from zz_res where n between 1 and 34),
           99, '── TOTAL ──',
           (select count(*)::text || ' pruebas' from zz_res where n between 1 and 34),
           (select count(*) filter (where veredicto='OK')::text || ' OK · ' ||
                   count(*) filter (where veredicto='FALLA')::text || ' FALLA · ' ||
                   count(*) filter (where veredicto='SIN DATO')::text || ' SIN DATO'
              from zz_res where n between 1 and 34),
           0
  ) t
 order by t.grupo, t.n;

rollback;

-- ── DESPUES DEL ROLLBACK ────────────────────────────────────────────────
-- No tiene que quedar NADA, ni datos ni esquema. Las siete en una sola corrida:
--   select (select count(*) from acceso_usuario where nota = 'ensayo-neto')        as cuentas,
--          (select count(*) from rrhh_persona  where creado_por = 'ensayo-neto')   as personas,
--          (select count(*) from rrhh_permiso  where creado_por = 'ensayo-neto')   as permisos,
--          (select count(*) from rrhh_feriado  where creado_por = 'ensayo-neto')   as feriados,
--          (select count(*) from information_schema.tables where table_schema='public'
--            and table_name in ('rrhh_neto_quincena','rrhh_feriado_trabajado'))    as tablas,
--          (select count(*) from pg_proc where proname like 'rrhh_es_dia%'
--            or proname in ('rrhh_dias_divisor','rrhh_feriado_paga_doble','zz_n','zz_pago')) as funciones,
--          (select count(*) from information_schema.columns where table_schema='public'
--            and table_name='rrhh_feriado' and column_name='pago_obligatorio')     as columna;
--   -- ESPERADO: 0 · 0 · 0 · 0 · 0 · 0 · 0
--
-- ⚠️ Si `columna` o `tablas` dan distinto de 0, el rollback NO corrio y el
-- esquema quedo a medias. En ese caso NO pegar nada mas y avisar.
