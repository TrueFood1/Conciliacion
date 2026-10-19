-- SOLO SE PEGA DESPUES DEL ENSAYO · PERSONAL_CIERRE_TRAMOS.sql
-- ════════════════════════════════════════════════════════════════════════
-- MODULO PERSONAL · EL CIERRE DE PLANTA SE PARTE EN CINCO TRAMOS (PEGADO 11)
-- Preparado el 16-oct-2026. NO SE CORRIO.
--
-- ⚠️ VA DESPUES DE PERSONAL_NETO_QUINCENA.sql (pegado 10), y no es opcional:
-- necesita la columna `pago_obligatorio`, que la crea ese pegado. Si se pega
-- antes, falla con «column pago_obligatorio does not exist» y no deja nada a
-- medias. El orden completo es: ensayo de la formula → pegado 10 → carga de los
-- netos → ensayo de este → este.
--
-- ════════════════════════════════════════════════════════════════════════
-- QUE DECIDIO LORENA, Y CONTRA QUE
-- ════════════════════════════════════════════════════════════════════════
-- El 25-dic-2026 y el 1-ene-2027 son los dos feriados de PAGO OBLIGATORIO que
-- caen dentro del cierre de planta de fin de año (18-dic-2026 al 11-ene-2027).
-- Ninguno de los dos estaba cargado, y no se podian cargar: `rrhh_feriado` tiene
-- una exclusion por rangos solapados que impide que un feriado viva adentro de un
-- cierre. Mientras eso siguiera asi, la regla del pago doble NO PODIA DISPARARSE
-- NUNCA — y peor, una ausencia en esos dias descontaba, siendo dias pagados.
--
-- Habia dos salidas y Lorena eligio la primera el 16-oct (PENDIENTES.md P3):
--   A · partir el cierre para que los dos feriados existan como filas propias;
--   B · dejarlo entero y que la regla no pudiera dispararse.
--
-- LOS CINCO TRAMOS, y suman los mismos 25 dias que el cierre entero:
--     18 al 24 de dic 2026  ·  7 dias  ·  cierre
--     25 de dic 2026        ·  1 dia   ·  FERIADO, pago_obligatorio = true
--     26 al 31 de dic 2026  ·  6 dias  ·  cierre
--     1 de ene 2027         ·  1 dia   ·  FERIADO, pago_obligatorio = true
--     2 al 11 de ene 2027   · 10 dias  ·  cierre
--                                       ─────────
--                                         25 dias
-- Los tres tramos de cierre conservan EXACTAMENTE el tratamiento de hoy: no
-- descuentan y no pagan doble. Lo unico que cambia son esos dos dias.
--
-- ════════════════════════════════════════════════════════════════════════
-- EL MECANISMO, Y POR QUE ESTE Y NO OTRO
-- ════════════════════════════════════════════════════════════════════════
-- PRIMERO LA PREGUNTA QUE HABIA QUE HACER: ¿`rrhh_feriado` es append-only como el
-- resto del modulo? Si lo fuera, partir el cierre seria anular una fila y cargar
-- cinco, y habria que inventar una columna `anulada` que no existe.
--
-- NO LO ES, y es la UNICA tabla mutable de Personal. Verificado en el codigo, no
-- supuesto:
--   · no tiene columna `anulada` ni nada parecido (PERSONAL_CALENDARIO.sql:121);
--   · tiene politica de UPDATE y de DELETE —`rrhh_feriado_upd` y
--     `rrhh_feriado_del`— y son las unicas del modulo (lineas 353 y 356);
--   · tiene `grant update, delete on rrhh_feriado to authenticated` (linea 386),
--     que tampoco tiene ninguna otra tabla;
--   · y la pantalla «Dias cerrados» la edita y la borra de verdad:
--     index.html:7254 hace `.update()` y 7275 hace `.delete()`.
-- Es un calendario operativo, no un libro de plata: se corrige en el lugar y por
-- eso se puede. Un neto o un salario no; un dia cerrado si.
--
-- ENTONCES: UN UPDATE Y CUATRO INSERT. No cinco DELETE + INSERT, por dos razones:
--   1. EL ORDEN IMPORTA POR LA EXCLUSION. No se puede insertar el 25-dic mientras
--      la fila grande todavia lo cubra: el constraint lo rechaza. Encogiendo
--      PRIMERO la fila original a su tramo (18 al 24), los otros cuatro entran sin
--      pisar nada. Borrar y reinsertar tambien funcionaria, pero deja la ventana
--      abierta a que un error entre los dos pasos pierda el cierre entero.
--   2. SE CONSERVA LA FILA ORIGINAL. El primer tramo sigue siendo la MISMA fila,
--      con su `id`, su `creado_en` y su `creado_por = 'semilla'`. En el calendario
--      se sigue viendo quien cargo el cierre y cuando. Un delete + insert pondria
--      'pegado-11' en los cinco tramos y borraria ese rastro.
--
-- ⚠️ Y EL CANDADO COMPARA EL CONJUNTO DE DIAS CERRADOS, dia por dia, antes y
-- despues. Es la unica comprobacion que importa de verdad: el calendario de
-- Lorena no puede cambiar ni un dia. Si entra un hueco o se corre un borde, no se
-- aplica nada.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── 1 · LA FOTO DE ANTES ────────────────────────────────────────────────
-- Dia por dia, no por rangos: dos rangos distintos pueden cubrir los mismos dias
-- y dos iguales pueden estar en filas distintas. Lo que no puede cambiar es el
-- CONJUNTO DE DIAS, y eso es lo que se guarda.
create temporary table zz_cerrados_antes on commit drop as
select d::date as dia
  from rrhh_feriado f
  cross join lateral generate_series(0, (coalesce(f.fecha_fin, f.fecha) - f.fecha)) g(i)
  cross join lateral (select f.fecha + g.i) x(d);


-- ── 2 · EL TRAMO QUE YA EXISTE SE ENCOGE ────────────────────────────────
-- ⚠️ ESTO PRIMERO, SIEMPRE. Mientras la fila cubra del 18-dic al 11-ene, ninguno
-- de los cuatro insert de abajo entra: la exclusion por rangos los rechaza.
-- Se busca por su RANGO EXACTO y no por su descripcion ni por su id: una
-- descripcion se edita desde la pantalla y un id no se puede escribir a mano en
-- un pegado que todavia no se corrio.
do $tramo1$
declare v_n int;
begin
  update rrhh_feriado
     set fecha_fin   = date '2026-12-24',
         descripcion = 'Cierre de planta de fin de año (18 al 24 de dic)'
   where fecha = date '2026-12-18' and fecha_fin = date '2027-01-11' and tipo = 'cierre';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'ABORTADO: esperaba UNA fila de cierre del 18-dic-2026 al 11-ene-2027 y '
      'encontre %. O ya se partio, o alguien le movio las fechas desde la pantalla «Dias '
      'cerrados». Mirar que hay con: select id, fecha, fecha_fin, descripcion, tipo from '
      'rrhh_feriado order by fecha. NO SE APLICO NADA.', v_n;
  end if;
end
$tramo1$;


-- ── 3 · LOS OTROS CUATRO TRAMOS ─────────────────────────────────────────
-- Los dos feriados van con pago_obligatorio = true; los dos cierres, con el
-- default false, que es el tratamiento que ya tenian.
insert into rrhh_feriado (fecha, fecha_fin, descripcion, tipo, pago_obligatorio, creado_por) values
  (date '2026-12-25', null,               'Navidad',
   'feriado', true,  'pegado-11'),
  (date '2026-12-26', date '2026-12-31',  'Cierre de planta de fin de año (26 al 31 de dic)',
   'cierre',  false, 'pegado-11'),
  (date '2027-01-01', null,               'Año Nuevo',
   'feriado', true,  'pegado-11'),
  (date '2027-01-02', date '2027-01-11',  'Cierre de planta de fin de año (2 al 11 de ene)',
   'cierre',  false, 'pegado-11');


-- ── 4 · EL CANDADO ──────────────────────────────────────────────────────
do $candado$
declare
  v_falta int; v_sobra int; v_tramos int; v_dias int;
  v_doble_25 boolean; v_doble_1 boolean;
  v_doble_cierre int; v_desc_25 boolean; v_desc_1 boolean; v_desc_cierre int;
begin
  -- 4.1 · EL CALENDARIO NO CAMBIO NI UN DIA. Es lo unico que no se negocia.
  select count(*) into v_falta from (
    select dia from zz_cerrados_antes
    except
    select (f.fecha + g.i)::date from rrhh_feriado f
     cross join lateral generate_series(0, (coalesce(f.fecha_fin, f.fecha) - f.fecha)) g(i)) a;
  select count(*) into v_sobra from (
    select (f.fecha + g.i)::date from rrhh_feriado f
     cross join lateral generate_series(0, (coalesce(f.fecha_fin, f.fecha) - f.fecha)) g(i)
    except
    select dia from zz_cerrados_antes) b;
  if v_falta <> 0 or v_sobra <> 0 then
    raise exception 'CANDADO: el calendario cambio. Quedaron % dia(s) sin cubrir y aparecieron '
      '% dia(s) nuevos. Partir el cierre no puede agregar ni quitar un solo dia cerrado. '
      'NO SE APLICO NADA.', v_falta, v_sobra;
  end if;

  -- 4.2 · LOS CINCO TRAMOS, Y LOS 25 DIAS.
  select count(*) into v_tramos from rrhh_feriado
   where fecha between date '2026-12-18' and date '2027-01-11';
  select count(*) into v_dias from (
    select (f.fecha + g.i)::date as dia from rrhh_feriado f
     cross join lateral generate_series(0, (coalesce(f.fecha_fin, f.fecha) - f.fecha)) g(i)
     where f.fecha >= date '2026-12-18') c
   where dia between date '2026-12-18' and date '2027-01-11';
  if v_tramos <> 5 or v_dias <> 25 then
    raise exception 'CANDADO: quedaron % tramos y % dias cerrados entre el 18-dic y el 11-ene; '
      'tenian que ser 5 tramos y 25 dias. NO SE APLICO NADA.', v_tramos, v_dias;
  end if;

  -- 4.3 · LA REGLA DEL PAGO DOBLE, EN LOS DOS SENTIDOS. Los dos feriados si; los
  -- tres tramos de cierre no, y se preguntan en un LUNES de cada uno para que el
  -- «no» no venga de que el dia caiga fin de semana.
  v_doble_25 := rrhh_feriado_paga_doble(date '2026-12-25');  -- viernes, obligatorio
  v_doble_1  := rrhh_feriado_paga_doble(date '2027-01-01');  -- viernes, obligatorio
  select count(*) into v_doble_cierre
    from (values (date '2026-12-21'), (date '2026-12-28'), (date '2027-01-04')) t(d)
   where rrhh_feriado_paga_doble(t.d);                       -- los tres son lunes
  if not v_doble_25 or not v_doble_1 then
    raise exception 'CANDADO: el 25-dic-2026 o el 1-ene-2027 no califican para pago doble, y los '
      'dos son viernes y de pago obligatorio. NO SE APLICO NADA.';
  end if;
  if v_doble_cierre <> 0 then
    raise exception 'CANDADO: % de los tramos de CIERRE califican para pago doble, y ninguno '
      'tiene que calificar: son dias cerrados, no feriados. NO SE APLICO NADA.', v_doble_cierre;
  end if;

  -- 4.4 · Y EL DESCUENTO. Ni los dos feriados ni los cierres descuentan.
  v_desc_25 := rrhh_es_dia_descontable(date '2026-12-25');
  v_desc_1  := rrhh_es_dia_descontable(date '2027-01-01');
  select count(*) into v_desc_cierre
    from (values (date '2026-12-21'), (date '2026-12-28'), (date '2027-01-04')) t(d)
   where rrhh_es_dia_descontable(t.d);
  if v_desc_25 or v_desc_1 then
    raise exception 'CANDADO: el 25-dic o el 1-ene DESCUENTAN si alguien falta, y son feriados '
      'de pago obligatorio: ese dia se paga igual. NO SE APLICO NADA.';
  end if;
  if v_desc_cierre <> 0 then
    raise exception 'CANDADO: % dia(s) de los tramos de cierre pasaron a DESCONTAR. El cierre '
      'tenia que quedar como estaba. NO SE APLICO NADA.', v_desc_cierre;
  end if;

  raise notice 'CANDADO OK: el calendario no cambio ni un dia · 5 tramos · 25 dias · el 25-dic y '
    'el 1-ene pagan doble y no descuentan · los tres tramos de cierre siguen igual';
end
$candado$;


-- ── 5 · LA FILA DE CONTROL ──────────────────────────────────────────────
-- Regla 🔴 de CLAUDE.md: un "Success" del editor no es evidencia de nada.
-- ESPERADO, las cinco filas en este orden:
--   18-12-2026 · 24-12-2026 · cierre  · f · 7
--   25-12-2026 · 25-12-2026 · feriado · t · 1
--   26-12-2026 · 31-12-2026 · cierre  · f · 6
--   01-01-2027 · 01-01-2027 · feriado · t · 1
--   02-01-2027 · 11-01-2027 · cierre  · f · 10
select to_char(f.fecha, 'DD-MM-YYYY')                        as desde,
       to_char(coalesce(f.fecha_fin, f.fecha), 'DD-MM-YYYY') as hasta,
       f.tipo                                                as tipo,
       f.pago_obligatorio                                    as paga_doble_si_se_trabaja,
       (coalesce(f.fecha_fin, f.fecha) - f.fecha) + 1         as dias,
       f.creado_por                                          as cargado_por
  from rrhh_feriado f
 where f.fecha between date '2026-12-18' and date '2027-01-11'
 order by f.fecha;

commit;


-- ════════════════════════════════════════════════════════════════════════
-- DESPUES DEL COMMIT
-- ════════════════════════════════════════════════════════════════════════
-- En la pantalla «Dias cerrados» el periodo se va a ver en CINCO filas en vez de
-- una, y dos de ellas van a decir «Navidad» y «Año Nuevo». Los dias pintados en el
-- calendario son exactamente los mismos: el candado no deja aplicarlo si no.
--
-- Y queda una cosa SIN HACER a proposito: el cierre de fin de año 2027-2028, y
-- los feriados obligatorios de 2027, siguen sin cargar. Ver PENDIENTES.md P3.
