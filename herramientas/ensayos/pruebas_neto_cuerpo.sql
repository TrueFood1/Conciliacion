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
--   1200 ÷ 12 (divisor 16-31 dic) = 100   (personas 4, 6, 7, 8 y 9)
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
       case when k in (4,6,7,8,9) then 1200 else 1100 end,
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
  -- 4 · ausencia justo sobre un feriado de PAGO OBLIGATORIO: el 25-dic-2026,
  --     que cae VIERNES. Esta prueba ya se mudo dos veces, y cada mudanza fue
  --     porque la premisa estaba mal, no el numero:
  --       · empezo en el 12-oct-2026, que NO esta cargado en rrhh_feriado;
  --       · paso al 1-dic-2026, que si esta cargado — pero con la regla del
  --         16-oct un feriado NO obligatorio descuenta como un dia normal, asi
  --         que ya no sirve para probar «el feriado no descuenta»;
  --       · ahora el 25-dic, que es el unico obligatorio del año.
  (current_setting('cc.p4',true)::bigint,'2026-12-25','2026-12-25','zz',
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
select 2, 'quincena con feriado NO obligatorio (1-15 dic) y sin feriados (16-31 oct): mismo divisor',
       'si · 11 = 11',
       case when rrhh_dias_divisor('2026-12-01','2026-12-15')
               = rrhh_dias_divisor('2026-10-16','2026-10-31') then 'si · ' else 'NO · ' end
       || rrhh_dias_divisor('2026-12-01','2026-12-15') || ' = '
       || rrhh_dias_divisor('2026-10-16','2026-10-31'), null;

-- 3 · Los dos conceptos NO son el mismo. 1-15 oct tiene 11 dias de divisor pero
--     solo 10 descontables, porque el 12-oct es feriado.
-- Las dos quincenas de diciembre, una al lado de la otra, porque juntas dicen la
-- regla entera:
--   1-15 dic  · divisor 11 · descontables 11 → el feriado del 1-dic NO es
--               obligatorio, asi que descuenta como cualquier dia: los dos
--               numeros coinciden y el feriado no se nota.
--   16-31 dic · divisor 12 · descontables 11 → el 25-dic SI es obligatorio: esta
--               en el divisor pero no descuenta. Ahi se separan los conceptos.
insert into zz_res
select 3, 'los dos conceptos · 1-15 dic (sin obligatorios) y 16-31 dic (con el 25-dic)',
       '11 · 11 · 12 · 11',
       rrhh_dias_divisor('2026-12-01','2026-12-15') || ' · ' ||
       (select count(*) from generate_series(0,14) g(i)
         where rrhh_es_dia_descontable(date '2026-12-01' + g.i)) || ' · ' ||
       rrhh_dias_divisor('2026-12-16','2026-12-31') || ' · ' ||
       (select count(*) from generate_series(0,15) g(i)
         where rrhh_es_dia_descontable(date '2026-12-16' + g.i)), null;

-- 4 · Dia por dia, los casos de borde del divisor: sabado, domingo, feriado.
-- El divisor NO MIRA los feriados, ni los obligatorios ni los otros: los dos
-- ultimos dan `t`. Es lo que sostiene que el divisor no cambie con la regla nueva.
insert into zz_res
select 4, 'es_dia_divisor: jue 1 oct · sab 3 · dom 4 · no oblig mar 1 dic · OBLIG vie 25 dic',
       't · f · f · t · t',
       concat_ws(' · ', left(rrhh_es_dia_divisor('2026-10-01')::text,1),
                        left(rrhh_es_dia_divisor('2026-10-03')::text,1),
                        left(rrhh_es_dia_divisor('2026-10-04')::text,1),
                        left(rrhh_es_dia_divisor('2026-12-01')::text,1),
                        left(rrhh_es_dia_divisor('2026-12-25')::text,1)), null;

-- 5 · Y del descontable: el feriado NO descuenta (suposicion de Andrea).
-- LA REGLA NUEVA, EN UNA FILA. El feriado no obligatorio del 1-dic pasa a dar
-- `t` (descuenta, como un dia normal) y el obligatorio del 25-dic da `f`.
insert into zz_res
select 5, 'es_dia_descontable: jue 1 oct · sab 3 · dom 4 · no oblig mar 1 dic · OBLIG vie 25 dic',
       't · f · f · t · f',
       concat_ws(' · ', left(rrhh_es_dia_descontable('2026-10-01')::text,1),
                        left(rrhh_es_dia_descontable('2026-10-03')::text,1),
                        left(rrhh_es_dia_descontable('2026-10-04')::text,1),
                        left(rrhh_es_dia_descontable('2026-12-01')::text,1),
                        left(rrhh_es_dia_descontable('2026-12-25')::text,1)), null;


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
-- Neto 1200, divisor de 16-31 dic = 12, valor del dia 100. El permiso es de un
-- solo dia y ese dia no descuenta, asi que el final es el neto entero.
insert into zz_res
select 10, 'ausencia el 25-dic (feriado OBLIGATORIO, viernes) · final · descuento · SIN CONFIRMAR',
       '1200 · 0',
       concat_ws(' · ', zz_n(final), zz_n(descuentos))
  from zz_pago('4','2026-12-Q2');

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

-- 11b · EL DIA DE LA SEMANA, COMPROBADO Y NO SUPUESTO. La fila 10 y las 20 y 21
--       dependen de que el 25-dic-2026 caiga de lunes a viernes; si cayera fin de
--       semana no serian las pruebas que dicen ser.
-- ⚠️ POR NUMERO DE DIA, NO POR NOMBRE. La primera version usaba
-- `to_char(fecha,'TMDy')` y esperaba «vie · sab»: eso depende del idioma del
-- SERVIDOR (lc_time), no del dato. En la base local dio «Fri · Sat» y la prueba
-- fallo sin que nada estuviera mal. isodow es un numero y no habla ningun idioma:
-- 1 = lunes ... 5 = viernes, 6 = sabado, 7 = domingo.
insert into zz_res
select 35, 'el dia de la semana · 25-dic-2026 (5 = viernes) · 26-dic-2026 (6 = sabado)',
       '5 · 6',
       extract(isodow from date '2026-12-25')::text || ' · ' ||
       extract(isodow from date '2026-12-26')::text, null;


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
 where n between 1 and 35 or n = -1;

-- Y las filas que el ensayo tenia que producir y podrian no existir: si un
-- `select ... from zz_pago(...)` no devuelve filas, el insert no inserta nada y
-- la prueba DESAPARECE en silencio en vez de fallar.
insert into zz_res
select n, 'ESTA PRUEBA NO CORRIO · la consulta no devolvio ninguna fila',
       'la fila existe', 'NO EXISTE', 'FALLA'
  from generate_series(1,35) n
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
    select (select case when count(*) < 35                    then 'FALTAN PRUEBAS · NO PEGAR'
                        when count(*) filter (where veredicto <> 'OK') = 0
                                                              then 'TODO VERDE'
                        else 'HAY ROJO · NO PEGAR' end
              from zz_res where n between 1 and 35),
           99, '── TOTAL ──',
           (select count(*)::text || ' pruebas' from zz_res where n between 1 and 35),
           (select count(*) filter (where veredicto='OK')::text || ' OK · ' ||
                   count(*) filter (where veredicto='FALLA')::text || ' FALLA · ' ||
                   count(*) filter (where veredicto='SIN DATO')::text || ' SIN DATO'
              from zz_res where n between 1 and 35),
           0
  ) t
 order by t.grupo, t.n;
