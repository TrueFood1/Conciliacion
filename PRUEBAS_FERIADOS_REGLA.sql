-- SOLO ENSAYO · PRUEBAS_FERIADOS_REGLA.sql · termina en ROLLBACK, no deja nada
--
-- ESTADO: CORRIDO EN PRODUCCIÓN EL 20-OCT-2026: TODO VERDE, 14/14.
-- (con rollback; nada quedó guardado, y el trigger se confirmó en O antes de
-- empezar). Antes de eso corrió completo en la base local el mismo dia, dos
-- veces, tambien TODO VERDE 14 de 14.
-- Dos corridas seguidas, y despues del rollback no quedo ni una fila ni un objeto.
-- NO se corrio todavia en produccion con la version corregida.
--
-- ⚠️ EL 19-oct ABORTO EN PRODUCCION con 42725 «operator is not unique: unknown ||
-- "char"» en la prueba 4.5, y no guardo nada (la transaccion entera se deshizo).
-- Causa: `'texto' || t.tgenabled`. `pg_trigger.tgenabled` es de tipo "char", no
-- text, y contra un literal sin tipo el `||` tiene DOS candidatos (text||text y
-- text||anynonarray), asi que Postgres no elige. Es un error de ANALISIS, no de
-- ejecucion: revienta aunque la rama del `case` nunca se evalue. Arreglado con
-- `t.tgenabled::text`, y verificado en la base local de las dos maneras: el
-- archivo viejo reproduce el 42725 en la misma linea, el nuevo pasa.
-- El mismo barrido por todo el repo no encontro otro caso: `name` (relname,
-- proname, nspname) SI resuelve solo, medido, asi que los `r.relname ||` de
-- ENSAYO_ASISTENTE_ROL.sql no tienen este problema. "char" era el unico.
-- ════════════════════════════════════════════════════════════════════════
-- ENSAYO · LAS CUATRO REGLAS DE FERIADOS QUE CONFIRMO LORENA (19-oct-2026)
--
--   1. Feriado OBLIGATORIO en sabado o domingo: no cambia nada. No entra al
--      divisor y no suma pago extra.
--   2. Obligatorio en dia laboral y la persona NO trabaja: se paga normal, o sea
--      cuenta en el divisor y una ausencia ese dia no descuenta.
--   3. Obligatorio en dia laboral y la persona SI trabaja: se paga doble, por
--      `rrhh_feriado_trabajado`.
--   4. Feriado NO obligatorio: nunca paga doble, aunque se trabaje.
--
-- ⚠️ ESTE ENSAYO NO LLEVA NINGUN PEGADO ADENTRO, y es a proposito. Las cuatro
-- reglas viven en funciones y vistas que YA ESTAN APLICADAS (pegados 10, 11 y 12).
-- Asi que esto mide las definiciones VIVAS de la base, que es mas fuerte que
-- medir una copia: si alguien cambia una funcion manana, este ensayo lo ve.
--
-- ⚠️ TERMINA EN `rollback;`. Crea personas y cuentas ficticias, dos feriados
-- inventados y unas filas de prueba, y lo deshace TODO. No deja ni una fila.
--
-- ⚠️ TOCA UNA COSA QUE YA EXISTE, y conviene saberlo: el caso 4 APAGA por un
-- momento el trigger `rrhh_feriado_trabajado_valida_tg` para poder meter una fila
-- que el trigger rechazaria, y probar asi el SEGUNDO filtro —el de la vista—. Lo
-- vuelve a encender en la linea siguiente, y el rollback lo devuelve igual de
-- todos modos. Si la corrida se cortara en ese punto, hay una consulta al final
-- del archivo para confirmar que el trigger esta encendido.
--
-- ⚠️ MONTOS INVENTADOS Y REDONDOS. Neto ficticio 1100 para todas las personas de
-- prueba, elegido para que el valor del dia salga exacto:
--       1100 ÷ 11 (divisor de 1-15 oct y de 1-15 dic) = 100
--       valor de la hora = 100 ÷ 8 = 12,5
-- No se parecen a ningun sueldo de nadie, y cada esperado se verifica a mano.
--
-- ⚠️ PERSONAS Y CUENTAS FICTICIAS, con correos @example.invalid — un TLD que la
-- RFC 2606 reserva y que no puede existir. Los mismos nombres de prueba que usan
-- los otros ensayos del modulo (ZZ …). Ninguna persona real se toca.
--
-- LAS FECHAS DE PRUEBA, verificadas contra el calendario:
--       sabado  3-oct-2026   → feriado obligatorio INVENTADO (caso 1)
--       martes  6-oct-2026   → feriado obligatorio INVENTADO (casos 2 y 3)
--       martes  1-dic-2026   → feriado REAL, de pago NO obligatorio (caso 4)
-- Octubre no tiene ningun dia cerrado cargado, asi que los dos inventados no se
-- pisan con nada — y si se pisaran, la guardia de abajo aborta antes de insertar.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── 0 · LAS GUARDIAS · que el ensayo no mienta por una base distinta ────
do $guardias$
declare v_n int; v_tipo text; v_obl boolean;
begin
  -- 0.1 · las cuatro funciones de regla tienen que existir.
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('rrhh_es_dia_divisor','rrhh_es_dia_descontable',
                       'rrhh_dias_divisor','rrhh_feriado_paga_doble');
  if v_n <> 4 then
    raise exception 'ENSAYO ABORTADO: faltan funciones de regla (hay %, tenian que ser 4). '
      'El pegado 10 no esta aplicado en esta base.', v_n;
  end if;

  -- 0.2 · los dos dias inventados tienen que estar libres: rrhh_feriado tiene una
  -- exclusion por rangos solapados y el insert fallaria con un 23P01 confuso.
  select count(*) into v_n from rrhh_feriado f
   where daterange(f.fecha, coalesce(f.fecha_fin, f.fecha), '[]')
      && daterange(date '2026-10-03', date '2026-10-06', '[]');
  if v_n <> 0 then
    raise exception 'ENSAYO ABORTADO: ya hay % dia(s) cerrado(s) entre el 3 y el 6 de octubre '
      'de 2026, asi que los feriados inventados de los casos 1 a 3 no se pueden cargar. '
      'Mirar con: select fecha, fecha_fin, descripcion, tipo from rrhh_feriado order by fecha;', v_n;
  end if;

  -- 0.3 · y el 1-dic tiene que estar cargado y ser NO obligatorio: es el dato del
  -- caso 4, y si no fuera asi el caso probaria otra cosa sin avisar.
  select f.tipo, f.pago_obligatorio into v_tipo, v_obl from rrhh_feriado f
   where f.fecha = date '2026-12-01';
  if v_tipo is null then
    raise exception 'ENSAYO ABORTADO: el 1-dic-2026 no esta cargado en rrhh_feriado, y el caso '
      '4 necesita un feriado REAL de pago no obligatorio para probarse.';
  end if;
  if v_tipo <> 'feriado' or coalesce(v_obl, false) then
    raise exception 'ENSAYO ABORTADO: el 1-dic-2026 esta como tipo «%» con pago_obligatorio = %, '
      'y el caso 4 necesita tipo «feriado» con pago_obligatorio = false.', v_tipo, v_obl;
  end if;
end
$guardias$;


-- ── 1 · LA TABLA DE RESULTADOS ──────────────────────────────────────────
-- Tabla NORMAL y no `temporary`: en esta base hay un disparador (`ensure_rls`)
-- que le prende la seguridad por filas a toda tabla nueva de public, y una
-- temporal creada por postgres no le da INSERT a nadie mas. Creada dentro de la
-- transaccion, el `rollback;` la borra igual que si fuera temporal.
-- `n` es NUMERIC para poder numerar 1.1 … 4.3 y que ordenen solas.
create table zz_res (n numeric, escenario text, esperado text, obtenido text, veredicto text);
grant select, insert, update on zz_res to public;
alter table zz_res disable row level security;

-- Y se le apaga la seguridad por filas por la misma razon: es un papel borrador
-- con resultados de prueba, no tiene un dato de nadie y vive lo que dura la
-- transaccion.

create or replace function zz_n(p numeric) returns text language sql immutable as $zz$
  -- Los ceros se recortan SOLO despues de un punto decimal: un `'0+$'` a secas
  -- convertiria 1100 en 11, y nadie lo veria venir.
  select regexp_replace(regexp_replace(round(p, 10)::text, '(\.\d*?)0+$', '\1'), '\.$', '')
$zz$;


-- ── 2 · LAS PERSONAS Y LAS CUENTAS FICTICIAS ────────────────────────────
insert into acceso_usuario (email, nombre, perfil, activo, nota, creado_por) values
  ('zz-socia@example.invalid', 'ZZ Socia', 'socias', true, 'ensayo-feriados', 'ensayo');

with p as (
  insert into rrhh_persona (nombre, email, puesto, ingreso, creado_por) values
    ('ZZ Limpia',   null, 'ensayo', '2026-01-05', 'ensayo-feriados'),
    ('ZZ Ausente',  null, 'ensayo', '2026-01-05', 'ensayo-feriados'),
    ('ZZ Trabajo',  null, 'ensayo', '2026-01-05', 'ensayo-feriados'),
    ('ZZ Horas',    null, 'ensayo', '2026-01-05', 'ensayo-feriados'),
    ('ZZ Diciembre',null, 'ensayo', '2026-01-05', 'ensayo-feriados')
  returning id, nombre)
select set_config('cc.' ||
         case nombre when 'ZZ Limpia' then 'limpia' when 'ZZ Ausente' then 'ausente'
                     when 'ZZ Trabajo' then 'trabajo' when 'ZZ Horas' then 'horas'
                     else 'dic' end, id::text, true) from p;

-- Las cuatro de octubre, con el neto vigente desde el 1-oct.
insert into rrhh_neto_quincena (persona_id, neto, vigente_desde, nota, creado_por)
select current_setting('cc.'||k, true)::bigint, 1100, '2026-10-01', 'FICTICIO', 'ensayo-feriados'
  from (values ('limpia'),('ausente'),('trabajo'),('horas')) v(k);

-- Y la de diciembre con vigencia 1-dic, y NO es un detalle: el universo de
-- quincenas de la vista se mide con el maximo de `vigente_desde`, entre otros. Con
-- todos los netos en octubre, la quincena 1-15 de diciembre no existiria y el
-- caso 4 daria «sin dato» en vez de probar algo.
insert into rrhh_neto_quincena (persona_id, neto, vigente_desde, nota, creado_por)
values (current_setting('cc.dic', true)::bigint, 1100, '2026-12-01', 'FICTICIO', 'ensayo-feriados');

-- La ausencia del caso 2, cargada ANTES de que el 6-oct sea feriado: a
-- rrhh_permiso no le importa el calendario, y asi se prueba que lo que cambia el
-- descuento es la regla del feriado y no la forma de cargar el permiso.
insert into rrhh_permiso (persona_id, fecha_inicio, fecha_fin, motivo, estado,
                          resuelto_por, resuelto_en, modalidad_descuento, creado_por)
values (current_setting('cc.ausente', true)::bigint, '2026-10-06','2026-10-06','zz',
        'aprobado','zz-socia@example.invalid', now(), 'descuento', 'ensayo-feriados');

-- LA SESION. Las vistas del pago llevan `where acceso_es_socia()` adentro, y esa
-- funcion mira el CORREO DEL JWT, no el rol de Postgres. Sin esto todo daria cero
-- filas y el ensayo diria «0 = 0» en verde sin haber probado nada.
select set_config('request.jwt.claims',
  json_build_object('email','zz-socia@example.invalid','role','authenticated')::text, true);
do $$
begin
  if not coalesce(acceso_es_socia(), false) then
    raise exception 'ENSAYO ABORTADO: la socia ficticia no quedo reconocida por '
      'acceso_es_socia(). Sin eso las vistas del pago devuelven CERO filas.';
  end if;
end $$;

-- INFO · que hay cargado alrededor de las fechas de prueba, para que se vea el
-- calendario real contra el que corrio esto.
insert into zz_res
select 0, 'INFO · dias cerrados cargados en oct-nov-dic 2026',
       '(lo que diga, no es una falla)',
       coalesce((select string_agg(to_char(f.fecha,'DD-MM') || '→' ||
                         to_char(coalesce(f.fecha_fin,f.fecha),'DD-MM') || ' ' || f.tipo ||
                         case when f.pago_obligatorio then ' OBLIG' else '' end,
                         ' · ' order by f.fecha)
                  from rrhh_feriado f
                 where f.fecha between date '2026-10-01' and date '2026-12-31'), '(ninguno)'),
       'INFO';


-- ════════════════════════════════════════════════════════════════════════
-- CASO 1 · OBLIGATORIO EN SABADO: NO CAMBIA NADA
-- ════════════════════════════════════════════════════════════════════════
-- Se mide ANTES de cargar el feriado y DESPUES, y los dos valores tienen que ser
-- iguales. Comparar contra un numero escrito a mano no alcanzaria: probaria que
-- el divisor es 11, no que el feriado no lo movio.
select set_config('cc.div_antes',
  rrhh_dias_divisor(date '2026-10-01', date '2026-10-15')::text, true);
select set_config('cc.final_antes',
  (select zz_n(v.final) from v_rrhh_pago v
    where v.persona_id = current_setting('cc.limpia',true)::bigint
      and v.quincena = '2026-10-Q1'), true);

-- EL SABADO INVENTADO. En lo que queda de 2026 no hay ningun feriado obligatorio
-- real que caiga fin de semana, asi que sin inventarlo este caso no se puede
-- probar — y es justo el que nadie mira hasta que pasa.
insert into rrhh_feriado (fecha, descripcion, tipo, pago_obligatorio, creado_por)
values (date '2026-10-03', 'ZZ ensayo · obligatorio en sabado', 'feriado', true, 'ensayo-feriados');

insert into zz_res
select 1.1, 'CASO 1 · el sabado obligatorio NO entra al divisor · antes → despues',
       current_setting('cc.div_antes',true) || ' → ' || current_setting('cc.div_antes',true),
       current_setting('cc.div_antes',true) || ' → ' ||
       rrhh_dias_divisor(date '2026-10-01', date '2026-10-15')::text, null;

insert into zz_res
select 1.2, 'CASO 1 · y no cambia el pago de nadie · final antes → despues',
       current_setting('cc.final_antes',true) || ' → ' || current_setting('cc.final_antes',true),
       current_setting('cc.final_antes',true) || ' → ' || zz_n(v.final), null
  from v_rrhh_pago v
 where v.persona_id = current_setting('cc.limpia',true)::bigint
   and v.quincena = '2026-10-Q1';

insert into zz_res
select 1.3, 'CASO 1 · sab 3-oct · es dia del divisor? · paga doble? · descuenta?',
       'f · f · f',
       concat_ws(' · ', left(rrhh_es_dia_divisor(date '2026-10-03')::text,1),
                        left(rrhh_feriado_paga_doble(date '2026-10-03')::text,1),
                        left(rrhh_es_dia_descontable(date '2026-10-03')::text,1)), null;

do $$
begin
  insert into rrhh_feriado_trabajado (persona_id, fecha, nota, creado_por)
  values (current_setting('cc.limpia',true)::bigint, '2026-10-03', 'zz', 'ensayo-feriados');
  insert into zz_res values (1.4,
    'CASO 1 · cargar un feriado trabajado EN SABADO', 'rechazado 23514', 'ENTRO', null);
exception
  when check_violation then
    insert into zz_res values (1.4,
      'CASO 1 · cargar un feriado trabajado EN SABADO', 'rechazado 23514', 'rechazado 23514', null);
  when others then
    insert into zz_res values (1.4,
      'CASO 1 · cargar un feriado trabajado EN SABADO', 'rechazado 23514',
      'otro error: ' || sqlstate, null);
end $$;


-- ════════════════════════════════════════════════════════════════════════
-- CASO 2 · OBLIGATORIO EN DIA LABORAL, SIN TRABAJAR: SE PAGA NORMAL
-- ════════════════════════════════════════════════════════════════════════
insert into rrhh_feriado (fecha, descripcion, tipo, pago_obligatorio, creado_por)
values (date '2026-10-06', 'ZZ ensayo · obligatorio en martes', 'feriado', true, 'ensayo-feriados');

insert into zz_res
select 2.1, 'CASO 2 · mar 6-oct · es dia del divisor? · descuenta? · paga doble si se trabaja?',
       't · f · t',
       concat_ws(' · ', left(rrhh_es_dia_divisor(date '2026-10-06')::text,1),
                        left(rrhh_es_dia_descontable(date '2026-10-06')::text,1),
                        left(rrhh_feriado_paga_doble(date '2026-10-06')::text,1)), null;

-- EL DIA SE PAGA PORQUE ESTA DENTRO DEL NETO: cuenta en el divisor, asi que el
-- neto entero se cobra sin restarle nada. 11 dias de divisor, neto 1100.
insert into zz_res
select 2.2, 'CASO 2 · quien no trabajo ese dia cobra el neto exacto · final · divisor',
       '1100 · 11',
       zz_n(v.final) || ' · ' || zz_n(v.divisor), null
  from v_rrhh_pago v
 where v.persona_id = current_setting('cc.limpia',true)::bigint
   and v.quincena = '2026-10-Q1';

-- Y UNA AUSENCIA ESE DIA NO DESCUENTA. Si descontara, el final seria 1000.
insert into zz_res
select 2.3, 'CASO 2 · una ausencia aprobada ese dia · final · descuento',
       '1100 · 0',
       zz_n(v.final) || ' · ' || zz_n(v.descuentos), null
  from v_rrhh_pago v
 where v.persona_id = current_setting('cc.ausente',true)::bigint
   and v.quincena = '2026-10-Q1';


-- ════════════════════════════════════════════════════════════════════════
-- CASO 3 · OBLIGATORIO EN DIA LABORAL Y SE TRABAJA: SE PAGA DOBLE
-- ════════════════════════════════════════════════════════════════════════
insert into rrhh_feriado_trabajado (persona_id, fecha, horas, nota, creado_por) values
  (current_setting('cc.trabajo',true)::bigint, '2026-10-06', null, 'dia completo', 'ensayo-feriados'),
  (current_setting('cc.horas',true)::bigint,   '2026-10-06', 4,    '4 horas',      'ensayo-feriados');

-- DIA COMPLETO: el dia ya venia pagado dentro del neto, asi que el adicional lo
-- deja al doble. 1100 + 100 = 1200, y UN solo renglon.
insert into zz_res
select 3.1, 'CASO 3 · dia completo trabajado · final · suma · cuantos renglones',
       '1200 · 100 · 1',
       zz_n(v.final) || ' · ' || zz_n(v.feriados_trab) || ' · ' || v.feriados_trab_n, null
  from v_rrhh_pago v
 where v.persona_id = current_setting('cc.trabajo',true)::bigint
   and v.quincena = '2026-10-Q1';

-- POR HORAS: 4 h × (100 ÷ 8) = 4 × 12,5 = 50. No es el dia entero.
insert into zz_res
select 3.2, 'CASO 3 · 4 horas trabajadas · final · suma',
       '1150 · 50',
       zz_n(v.final) || ' · ' || zz_n(v.feriados_trab), null
  from v_rrhh_pago v
 where v.persona_id = current_setting('cc.horas',true)::bigint
   and v.quincena = '2026-10-Q1';


-- ════════════════════════════════════════════════════════════════════════
-- CASO 4 · FERIADO NO OBLIGATORIO: NUNCA PAGA DOBLE
-- ════════════════════════════════════════════════════════════════════════
-- El 1-dic-2026 es un feriado REAL, martes, de pago NO obligatorio. La guardia 0.3
-- ya verifico que siga asi en esta base.
insert into zz_res
select 4.1, 'CASO 4 · mar 1-dic · tipo · pago_obligatorio · paga doble?',
       'feriado · f · f',
       f.tipo || ' · ' || left(f.pago_obligatorio::text,1) || ' · ' ||
       left(rrhh_feriado_paga_doble(date '2026-12-01')::text,1), null
  from rrhh_feriado f where f.fecha = date '2026-12-01';

select set_config('cc.dic_antes',
  (select zz_n(v.final) from v_rrhh_pago v
    where v.persona_id = current_setting('cc.dic',true)::bigint
      and v.quincena = '2026-12-Q1'), true);

do $$
begin
  insert into rrhh_feriado_trabajado (persona_id, fecha, nota, creado_por)
  values (current_setting('cc.dic',true)::bigint, '2026-12-01', 'zz', 'ensayo-feriados');
  insert into zz_res values (4.2,
    'CASO 4 · cargar un feriado trabajado en uno NO obligatorio',
    'rechazado 23514', 'ENTRO', null);
exception
  when check_violation then
    insert into zz_res values (4.2,
      'CASO 4 · cargar un feriado trabajado en uno NO obligatorio',
      'rechazado 23514', 'rechazado 23514', null);
  when others then
    insert into zz_res values (4.2,
      'CASO 4 · cargar un feriado trabajado en uno NO obligatorio',
      'rechazado 23514', 'otro error: ' || sqlstate, null);
end $$;

-- ── EL SEGUNDO FILTRO, QUE ES EL QUE DE VERDAD PROTEGE ──────────────────
-- El trigger frena la CARGA. Pero si alguien desmarcara `pago_obligatorio`
-- DESPUES de haber cargado un feriado trabajado, el trigger ya no vuelve a
-- correr: lo que tiene que dejar de pagar es la VISTA. Para probar eso hay que
-- meter una fila que el trigger rechazaria, asi que se lo apaga un momento.
-- Se enciende de nuevo en la linea siguiente, y el rollback lo devuelve igual.
alter table rrhh_feriado_trabajado disable trigger rrhh_feriado_trabajado_valida_tg;
insert into rrhh_feriado_trabajado (persona_id, fecha, nota, creado_por)
values (current_setting('cc.dic',true)::bigint, '2026-12-01',
        'zz forzado con el trigger apagado', 'ensayo-feriados');
alter table rrhh_feriado_trabajado enable trigger rrhh_feriado_trabajado_valida_tg;

insert into zz_res
select 4.3, 'CASO 4 · con la fila forzada · renglones de feriado trabajado · final antes → despues',
       '0 · ' || current_setting('cc.dic_antes',true) || ' → ' || current_setting('cc.dic_antes',true),
       v.feriados_trab_n || ' · ' || current_setting('cc.dic_antes',true) || ' → ' || zz_n(v.final), null
  from v_rrhh_pago v
 where v.persona_id = current_setting('cc.dic',true)::bigint
   and v.quincena = '2026-12-Q1';

-- Y que la fila forzada SI exista: si no existiera, la 4.3 pasaria sin haber
-- probado el filtro de la vista.
insert into zz_res
select 4.4, 'CASO 4 · la fila forzada quedo en la tabla (si no, la 4.3 no prueba nada)',
       '1 fila',
       (select count(*)::text || ' fila' ||
               case when count(*) = 1 then '' else 's' end
          from rrhh_feriado_trabajado ft
         where ft.persona_id = current_setting('cc.dic',true)::bigint
           and ft.fecha = date '2026-12-01'), null;

-- Y que el trigger quedo ENCENDIDO.
insert into zz_res
select 4.5, 'CASO 4 · el trigger quedo encendido despues de la prueba',
       'encendido',
       case when t.tgenabled = 'O' then 'encendido' else 'APAGADO · tgenabled=' || t.tgenabled::text end,
       null
  from pg_trigger t
 where t.tgname = 'rrhh_feriado_trabajado_valida_tg' and not t.tgisinternal;


-- ── EL VEREDICTO ────────────────────────────────────────────────────────
-- Se compara el texto que se MUESTRA, no otra cuenta por el costado: en un ensayo
-- anterior el veredicto salia de una comparacion distinta a la impresa y decia OK
-- con los numeros a la vista distintos.
update zz_res set veredicto =
  case when obtenido is null                  then 'SIN DATO'
       when btrim(obtenido) = btrim(esperado) then 'OK'
       else 'FALLA' end
 where n in (1.1,1.2,1.3,1.4,2.1,2.2,2.3,3.1,3.2,4.1,4.2,4.3,4.4,4.5);

-- Y las que tenian que correr y podrian no existir: si un `select … from` no
-- devuelve filas, el insert no inserta nada y la prueba DESAPARECE en silencio.
insert into zz_res
select v.n, 'ESTA PRUEBA NO CORRIO · la consulta no devolvio ninguna fila',
       'la fila existe', 'NO EXISTE', 'FALLA'
  from (values (1.1),(1.2),(1.3),(1.4),(2.1),(2.2),(2.3),
               (3.1),(3.2),(4.1),(4.2),(4.3),(4.4),(4.5)) v(n)
 where v.n not in (select r.n from zz_res r);

-- EL VEREDICTO PRIMERO Y EL TOTAL ARRIBA: asi se confirma con una sola foto y sin
-- arrastrar la tabla a la derecha. Y es UN SOLO resultado, porque el editor de
-- Supabase muestra nada mas el ultimo.
select t.veredicto as "veredicto", t.n as "#", t.escenario as "escenario",
       t.esperado as "esperado", t.obtenido as "obtenido"
  from (
    select r.veredicto, r.n, r.escenario, r.esperado,
           coalesce(r.obtenido,'(nada)') as obtenido,
           case when r.veredicto in ('FALLA','SIN DATO') then 1
                when r.veredicto = 'INFO'                then 2
                else 3 end as grupo
      from zz_res r
    union all
    select (select case when count(*) < 14 then 'FALTAN PRUEBAS · NO CONFIAR'
                        when count(*) filter (where veredicto <> 'OK') = 0 then 'TODO VERDE'
                        else 'HAY ROJO' end
              from zz_res where veredicto in ('OK','FALLA','SIN DATO')),
           99, '── TOTAL ──',
           (select count(*)::text || ' pruebas' from zz_res
             where veredicto in ('OK','FALLA','SIN DATO')),
           (select count(*) filter (where veredicto='OK')::text || ' OK · ' ||
                   count(*) filter (where veredicto='FALLA')::text || ' FALLA · ' ||
                   count(*) filter (where veredicto='SIN DATO')::text || ' SIN DATO'
              from zz_res where veredicto in ('OK','FALLA','SIN DATO')),
           0
  ) t
 order by t.grupo, t.n;

rollback;


-- ── DESPUES DEL ROLLBACK ────────────────────────────────────────────────
-- No tiene que quedar NADA, y el trigger tiene que estar encendido. Todo en una
-- sola corrida:
--   select (select count(*) from acceso_usuario where nota = 'ensayo-feriados')      as cuentas,
--          (select count(*) from rrhh_persona  where creado_por = 'ensayo-feriados') as personas,
--          (select count(*) from rrhh_feriado  where creado_por = 'ensayo-feriados') as feriados,
--          (select count(*) from rrhh_feriado_trabajado
--            where creado_por = 'ensayo-feriados')                                   as trabajados,
--          (select count(*) from information_schema.tables where table_schema='public'
--            and table_name = 'zz_res')                                             as sobras,
--          (select t.tgenabled from pg_trigger t
--            where t.tgname = 'rrhh_feriado_trabajado_valida_tg' and not t.tgisinternal) as trigger_O;
--   -- ESPERADO: 0 · 0 · 0 · 0 · 0 · O
--
-- ⚠️ Si `trigger_O` no dice «O», el trigger quedo APAGADO y hay que encenderlo:
--     alter table rrhh_feriado_trabajado enable trigger rrhh_feriado_trabajado_valida_tg;
-- No deberia pasar —el rollback lo devuelve—, pero si la corrida se corto justo
-- en el caso 4, conviene mirarlo antes de seguir.
