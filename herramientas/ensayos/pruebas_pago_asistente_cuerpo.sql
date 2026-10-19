-- ════════════════════════════════════════════════════════════════════════
-- NETOS FICTICIOS Y REDONDOS: 1100, para que el valor del dia salga exacto
-- (1100 ÷ 11 = 100 en la quincena 1-15 oct). No se parecen a ningun sueldo.
-- Los esperados estan escritos a mano, derivados del calendario.
-- ════════════════════════════════════════════════════════════════════════

-- `n` es NUMERIC y no int: la prueba 12 se parte en 12.1 … 12.6 para que cada
-- intento de escritura se lea en su propia fila, y asi ordenan entre la 12 y la 13.
create table zz_res (n numeric, escenario text, esperado text, obtenido text, veredicto text);
grant select, insert, update on zz_res to public;
-- Igual que en los otros ensayos: `ensure_rls` le prende la seguridad por filas
-- a toda tabla nueva, y sin politica permisiva de insercion nadie inserta. Es un
-- papel borrador con resultados de prueba.
alter table zz_res disable row level security;

create or replace function zz_n(p numeric) returns text language sql immutable as $zz$
  select regexp_replace(regexp_replace(round(p, 10)::text, '(\.\d*?)0+$', '\1'), '\.$', '')
$zz$;

-- ── LAS CUENTAS Y LAS PERSONAS FICTICIAS ────────────────────────────────
-- @example.invalid: TLD reservado por la RFC 2606. No depende de ninguna cuenta
-- real y no escribe nada a nombre de nadie.
-- ⚠️ El CHECK de `perfil` se amplia a 'asistente' si hace falta: ACCESOS_ESQUEMA
-- lo creo con ('socias','equipo') y ASISTENTE_ROL lo amplio. Si el ensayo corre
-- contra una base donde eso ya paso, el `do` no hace nada.
do $$
begin
  if exists (select 1 from pg_constraint c join pg_class t on t.oid=c.conrelid
              where t.relname='acceso_usuario' and c.contype='c'
                and pg_get_constraintdef(c.oid) like '%perfil%'
                and pg_get_constraintdef(c.oid) not like '%asistente%') then
    raise exception 'ENSAYO ABORTADO: el CHECK de acceso_usuario.perfil no acepta '
      '«asistente», asi que ASISTENTE_ROL.sql no esta aplicado en esta base y este '
      'ensayo no puede probar nada del asistente.';
  end if;
end $$;

insert into acceso_usuario (email, nombre, perfil, activo, nota, creado_por) values
  ('zz-socia@example.invalid',    'ZZ Socia',    'socias',    true, 'ensayo-asis', 'ensayo'),
  ('zz-instinct@example.invalid', 'ZZ Instinct', 'asistente', true, 'ensayo-asis', 'ensayo'),
  ('zz-equipo@example.invalid',   'ZZ Equipo',   'equipo',    true, 'ensayo-asis', 'ensayo');

with p as (
  insert into rrhh_persona (nombre, email, puesto, ingreso, creado_por) values
    ('ZZ Con Permiso', 'zz-equipo@example.invalid', 'ensayo', '2026-01-05', 'ensayo-asis'),
    ('ZZ Limpia',      null,                        'ensayo', '2026-01-05', 'ensayo-asis')
  returning id, nombre)
select set_config('cc.'||case when nombre='ZZ Limpia' then 'limpia' else 'perm' end,
                  id::text, true) from p;

insert into rrhh_neto_quincena (persona_id, neto, vigente_desde, nota, creado_por)
select current_setting('cc.'||k,true)::bigint, 1100, '2026-10-01', 'FICTICIO', 'ensayo-asis'
  from (values ('perm'),('limpia')) v(k);

-- EL CASO QUE IMPORTA: un permiso con descuento, el mismo que se midio el 19-oct.
-- Sin el, el total del asistente podria salir igual por casualidad.
insert into rrhh_permiso (persona_id, fecha_inicio, fecha_fin, motivo, estado,
                          resuelto_por, resuelto_en, modalidad_descuento, creado_por)
values (current_setting('cc.perm',true)::bigint, '2026-10-06','2026-10-06','zz',
        'aprobado','zz-socia@example.invalid',now(),'descuento','ensayo-asis');

-- Y un ajuste manual con una nota, para probar que el asistente no la ve por
-- ninguna via (hoy ni siquiera llega al detalle, pero se prueba igual).
insert into rrhh_ajuste_manual (persona_id, fecha, monto, nota, creado_por)
values (current_setting('cc.limpia',true)::bigint, '2026-10-10', 50,
        'ZZ nota privada de la socia', 'ensayo-asis');

-- Y una incapacidad, para que exista un origen que el asistente no debe ver.
insert into rrhh_permiso (persona_id, fecha_inicio, fecha_fin, motivo, estado,
                          resuelto_por, resuelto_en, modalidad_descuento,
                          incapacidad_origen, creado_por)
values (current_setting('cc.limpia',true)::bigint, '2026-10-13','2026-10-13','zz',
        'aprobado','zz-socia@example.invalid',now(),'incapacidad','enfermedad_comun','ensayo-asis');


-- ── LO QUE VE LA SOCIA, PRIMERO: es la referencia de todo lo demas ──────
-- ⚠️ DE ACA EN ADELANTE SE MIDE COMO `authenticated`, NO COMO postgres.
-- postgres es SUPERUSUARIO: ignora los grants. Y el `revoke` de las dos vistas
-- _calc es lo UNICO que las cierra —no tienen guardia de identidad adentro—, asi
-- que midiendo como postgres esa prueba no prueba nada. La primera corrida de
-- este ensayo dio «7 filas» y «2 filas» donde esperaba «denegado», y el error
-- era este. Es el mismo error que la fila 32 del ensayo de la formula, al revés:
-- ahi medía permisos en vez de hechos, aca medía los hechos con el rol que no es.
select set_config('request.jwt.claims',
  json_build_object('email','zz-socia@example.invalid','role','authenticated')::text, true);
set local role authenticated;
do $$
begin
  if not coalesce(acceso_es_socia(), false) then
    raise exception 'ENSAYO ABORTADO: la socia ficticia no quedo reconocida por '
      'acceso_es_socia(). Sin eso todo daria «0 = 0» en verde sin probar nada.';
  end if;
  perform set_config('cc.socia_total_perm',
    (select zz_n(final) from v_rrhh_pago
      where persona_id = current_setting('cc.perm',true)::bigint and quincena='2026-10-Q1'), true);
  perform set_config('cc.socia_total_limpia',
    (select zz_n(final) from v_rrhh_pago
      where persona_id = current_setting('cc.limpia',true)::bigint and quincena='2026-10-Q1'), true);
  perform set_config('cc.socia_renglones',
    (select count(*)::text from v_rrhh_pago_detalle where quincena='2026-10-Q1'), true);
end $$;


-- ════════════════════════════════════════════════════════════════════════
-- 1 · LA SOCIA SIGUE VIENDO LO MISMO QUE ANTES
-- ════════════════════════════════════════════════════════════════════════
-- 1100 − 100 (un dia habil de permiso) = 1000 para la de permiso.
-- La limpia: 1100 + 50 (el ajuste) − 50 (incapacidad, 1 dia al 50% del patrono) = 1100.
insert into zz_res
select 1, 'SOCIA · total de la persona con permiso (1100 − 100) · y de la limpia',
       '1000 · 1100',
       current_setting('cc.socia_total_perm',true) || ' · ' ||
       current_setting('cc.socia_total_limpia',true), null;

insert into zz_res
select 2, 'SOCIA · sigue viendo el desglose y el dia por dia',
       'si · si',
       case when (select count(*) from v_rrhh_pago_detalle) > 0 then 'si' else 'NO' end || ' · ' ||
       case when (select count(*) from v_rrhh_permiso_dia)  > 0 then 'si' else 'NO' end, null;

insert into zz_res
select 3, 'SOCIA · ve el origen de la incapacidad y la nota del ajuste',
       'enfermedad_comun · si',
       coalesce((select max(incapacidad_origen) from v_rrhh_permiso_dia
                  where incapacidad_origen is not null),'(ninguno)') || ' · ' ||
       case when exists (select 1 from v_rrhh_pago_detalle
                          where nota like '%nota privada%') then 'si' else 'NO' end, null;

insert into zz_res
select 4, 'SOCIA · la puerta nueva le da el MISMO total que v_rrhh_pago',
       '1000 · igual',
       zz_n(t.total) || ' · ' ||
       case when zz_n(t.total) = current_setting('cc.socia_total_perm',true)
            then 'igual' else 'DISTINTO' end, null
  from v_rrhh_pago_total t
 where t.persona_id = current_setting('cc.perm',true)::bigint and t.quincena='2026-10-Q1';


-- ════════════════════════════════════════════════════════════════════════
-- 2 · EL ASISTENTE · UNA FILA POR PERSONA, EL MISMO TOTAL, Y NADA MAS
-- ════════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claims',
  json_build_object('email','zz-instinct@example.invalid','role','authenticated')::text, true);
set local role authenticated;   -- explicito: mover esta seccion no debe romperla
do $$
begin
  if not coalesce(acceso_es_asistente(), false) then
    raise exception 'ENSAYO ABORTADO: la cuenta ficticia de asistente no quedo reconocida '
      'por acceso_es_asistente(). Sin eso las pruebas del asistente no prueban nada.';
  end if;
  if coalesce(acceso_es_socia(), false) then
    raise exception 'ENSAYO ABORTADO: el asistente salio reconocido ADEMAS como socia.';
  end if;
end $$;

-- 5 · EL TOTAL, IGUAL AL DE LA SOCIA. Es la prueba que pidio Lorena, y el caso
--     con descuento es el que la hace valer: sin el, un total calculado sin los
--     permisos daria 1100 y pasaria igual.
insert into zz_res
select 5, 'ASISTENTE · total de la persona con permiso · igual al de la socia?',
       current_setting('cc.socia_total_perm',true) || ' · igual',
       zz_n(t.total) || ' · ' ||
       case when zz_n(t.total) = current_setting('cc.socia_total_perm',true)
            then 'igual' else 'DISTINTO' end, null
  from v_rrhh_pago_total t
 where t.persona_id = current_setting('cc.perm',true)::bigint and t.quincena='2026-10-Q1';

insert into zz_res
select 6, 'ASISTENTE · y el de la persona limpia tambien',
       current_setting('cc.socia_total_limpia',true) || ' · igual',
       zz_n(t.total) || ' · ' ||
       case when zz_n(t.total) = current_setting('cc.socia_total_limpia',true)
            then 'igual' else 'DISTINTO' end, null
  from v_rrhh_pago_total t
 where t.persona_id = current_setting('cc.limpia',true)::bigint and t.quincena='2026-10-Q1';

-- 7 · UNA FILA POR PERSONA Y POR QUINCENA, ni mas ni menos.
insert into zz_res
select 7, 'ASISTENTE · filas de la quincena 1-15 oct (2 personas ficticias)',
       '2',
       (select count(*)::text from v_rrhh_pago_total
         where quincena='2026-10-Q1'
           and persona_id in (current_setting('cc.perm',true)::bigint,
                              current_setting('cc.limpia',true)::bigint)), null;

-- 8 · CUATRO COLUMNAS, NI UNA MAS. Se mide el catalogo, no lo que devuelve un
--     select: una columna de mas existe aunque nadie la pida hoy.
insert into zz_res
select 8, 'ASISTENTE · las columnas que existen en la puerta',
       'quincena,persona_id,nombre,total',
       (select string_agg(a.attname, ',' order by a.attnum) from pg_attribute a
         where a.attrelid='v_rrhh_pago_total'::regclass and a.attnum>0 and not a.attisdropped), null;

-- 9 · LAS TRES VISTAS DE SIEMPRE LE DAN CERO O LE NIEGAN EL PERMISO.
do $$
declare v text:='';
begin
  begin v:=v||(select count(*) from v_rrhh_pago)||' filas';
  exception when insufficient_privilege then v:=v||'denegado'; when others then v:=v||sqlstate; end;
  begin v:=v||' · '||(select count(*) from v_rrhh_pago_detalle)||' filas';
  exception when insufficient_privilege then v:=v||' · denegado'; when others then v:=v||' · '||sqlstate; end;
  begin v:=v||' · '||(select count(*) from v_rrhh_permiso_dia)||' filas';
  exception when insufficient_privilege then v:=v||' · denegado'; when others then v:=v||' · '||sqlstate; end;
  insert into zz_res values (9,
    'ASISTENTE · v_rrhh_pago · v_rrhh_pago_detalle · v_rrhh_permiso_dia',
    '0 filas · 0 filas · 0 filas', v, null);
end $$;

-- 10 · Y LAS DOS INTERNAS, QUE SON LAS QUE TIENEN TODO, LE NIEGAN EL PERMISO.
--      Es el unico candado de esas dos: no tienen guardia de identidad adentro.
do $$
declare v text:='';
begin
  begin v:=v||(select count(*) from v_rrhh_pago_detalle_calc)||' filas ❌';
  exception when insufficient_privilege then v:=v||'denegado';
           when others then v:=v||'error '||sqlstate; end;
  begin v:=v||' · '||(select count(*) from v_rrhh_permiso_dia_calc)||' filas ❌';
  exception when insufficient_privilege then v:=v||' · denegado';
           when others then v:=v||' · error '||sqlstate; end;
  insert into zz_res values (10,
    'ASISTENTE · las dos vistas _calc, que tienen el desglose entero',
    'denegado · denegado', v, null);
end $$;

-- 11 · NI EL ORIGEN DE LA INCAPACIDAD NI LA NOTA DEL AJUSTE, POR NINGUNA VIA.
--      Se busca el texto en TODO lo que el asistente puede leer del pago.
insert into zz_res
select 11, 'ASISTENTE · aparece «enfermedad» o la nota privada en lo que puede leer?',
       'no · no',
       case when exists (select 1 from v_rrhh_pago_total t
                          where t.nombre ilike '%enfermedad%'
                             or t.quincena ilike '%enfermedad%') then 'SI ❌' else 'no' end
       || ' · ' ||
       case when exists (select 1 from v_rrhh_pago_total t
                          where t.nombre ilike '%nota privada%') then 'SI ❌' else 'no' end, null;

-- 12 · EL ASISTENTE NO ESCRIBE NADA. Se intenta de verdad en las tres tablas del
--      pago, y CADA INTENTO SALE EN SU PROPIA FILA: una sola linea larga con seis
--      partes se corta en la pantalla de Supabase y hay que deslizar para saber
--      si fallo el update o el delete. Paso el 19-oct.
do $$
declare v_n int; v_antes numeric; v_despues numeric; v_rastro int;
begin
  -- ⚠️ EL ANTES Y EL DESPUES SE LEEN COMO postgres, NO COMO EL ASISTENTE.
  -- El asistente no puede leer rrhh_neto_quincena (su politica pide socia), asi
  -- que leyendolo como el las dos lecturas dan NULL — y `null = null` es NULL,
  -- que no es verdadero: la prueba decia «CAMBIO» con el dato intacto.
  perform set_config('role','postgres', true);
  select neto into v_antes from rrhh_neto_quincena
   where persona_id = current_setting('cc.perm',true)::bigint;
  perform set_config('role','authenticated', true);

  begin
    insert into rrhh_ajuste_manual (persona_id,fecha,monto,nota,creado_por)
    values (current_setting('cc.perm',true)::bigint,'2026-10-14',999,'zz','asis');
    insert into zz_res values (12.1,'ASISTENTE no escribe · insert de un AJUSTE manual',
      '42501','ENTRO', null);
  exception when others then
    insert into zz_res values (12.1,'ASISTENTE no escribe · insert de un AJUSTE manual',
      '42501', sqlstate, null);
  end;

  begin
    insert into rrhh_neto_quincena (persona_id,neto,vigente_desde,nota,creado_por)
    values (current_setting('cc.perm',true)::bigint,1,'2026-11-01','zz','asis');
    insert into zz_res values (12.2,'ASISTENTE no escribe · insert de un NETO',
      '42501','ENTRO', null);
  exception when others then
    insert into zz_res values (12.2,'ASISTENTE no escribe · insert de un NETO',
      '42501', sqlstate, null);
  end;

  -- ⚠️ ESTA ACEPTA DOS CODIGOS, y la razon importa.
  -- `rrhh_feriado_trabajado` tiene un trigger BEFORE INSERT que rechaza una fecha
  -- que no sea feriado de pago obligatorio de lunes a viernes, y un BEFORE corre
  -- ANTES de que se evalue el `with check` de la politica. Asi que cual de las dos
  -- capas frena depende de si ESA fecha es obligatoria, que a su vez depende de si
  -- el pegado 11 esta aplicado:
  --     sin el pegado 11 (mi base local) → el 25-dic no es obligatorio → 23514
  --     con el pegado 11 (produccion)    → si lo es → pasa el trigger → 42501
  -- Las dos son un bloqueo. Lo que NO se acepta es que entre.
  -- El esperado decia 23514 a secas y fallo en produccion el 19-oct: habia
  -- codificado una suposicion sobre el estado de OTRO pegado.
  begin
    insert into rrhh_feriado_trabajado (persona_id,fecha,nota,creado_por)
    values (current_setting('cc.perm',true)::bigint,'2026-12-25','zz','asis');
    insert into zz_res values (12.3,'ASISTENTE no escribe · insert de un FERIADO TRABAJADO',
      'bloqueado','ENTRO', null);
    insert into zz_res values (12.31,'INFO · y con que codigo lo frenaron',
      '(lo que diga)','ninguno: ENTRO', 'INFO');
  exception when others then
    -- LA PRUEBA mide el HECHO —bloqueado o no— y el codigo va en una fila INFO
    -- aparte. Si el veredicto saliera de comparar «42501 o 23514» contra un
    -- codigo concreto, no coincidiria nunca: el esperado y el obtenido serian
    -- dos textos distintos aunque todo estuviera bien. Paso en la primera
    -- version de esta fila.
    insert into zz_res values (12.3,'ASISTENTE no escribe · insert de un FERIADO TRABAJADO',
      'bloqueado',
      case when sqlstate in ('42501','23514') then 'bloqueado' else 'otro error' end, null);
    insert into zz_res values (12.31,'INFO · y con que codigo lo frenaron',
      '(lo que diga)',
      sqlstate || case when sqlstate='42501' then ' · la POLITICA (with check pide socia)'
                       when sqlstate='23514' then ' · el TRIGGER (esa fecha no es feriado obligatorio)'
                       else ' · inesperado' end, 'INFO');
  end;

  begin
    update rrhh_neto_quincena set neto = 1
     where persona_id = current_setting('cc.perm',true)::bigint;
    get diagnostics v_n = row_count;
    insert into zz_res values (12.4,'ASISTENTE no escribe · UPDATE del neto · filas afectadas',
      '42501', v_n || ' filas', null);
  exception when others then
    insert into zz_res values (12.4,'ASISTENTE no escribe · UPDATE del neto · filas afectadas',
      '42501', sqlstate, null);
  end;

  begin
    delete from rrhh_neto_quincena
     where persona_id = current_setting('cc.perm',true)::bigint;
    get diagnostics v_n = row_count;
    insert into zz_res values (12.5,'ASISTENTE no escribe · DELETE del neto · filas afectadas',
      '42501', v_n || ' filas', null);
  exception when others then
    insert into zz_res values (12.5,'ASISTENTE no escribe · DELETE del neto · filas afectadas',
      '42501', sqlstate, null);
  end;

  -- 12.6 · LOS HECHOS, que no dependen de ningun codigo de error: el dato esta
  --        igual y no quedo ni una fila a nombre del asistente.
  perform set_config('role','postgres', true);
  select neto into v_despues from rrhh_neto_quincena
   where persona_id = current_setting('cc.perm',true)::bigint;
  select (select count(*) from rrhh_ajuste_manual     where creado_por='asis')
       + (select count(*) from rrhh_neto_quincena     where creado_por='asis')
       + (select count(*) from rrhh_feriado_trabajado where creado_por='asis')
    into v_rastro;
  insert into zz_res values (12.6,
    'ASISTENTE no escribe · el neto quedo igual · y sin rastro en las tres tablas',
    'igual · 0 filas',
    (case when v_despues is not distinct from v_antes then 'igual' else 'CAMBIO' end)
      || ' · ' || v_rastro || ' filas', null);
  perform set_config('role','authenticated', true);
end $$;


-- ════════════════════════════════════════════════════════════════════════
-- 3 · EL EMPLEADO SIN ROL Y anon · NADA
-- ════════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claims',
  json_build_object('email','zz-equipo@example.invalid','role','authenticated')::text, true);
set local role authenticated;
insert into zz_res
select 13, 'EMPLEADO (ni socia ni asistente) · filas en la puerta · en v_rrhh_pago',
       '0 · 0',
       (select count(*)::text from v_rrhh_pago_total) || ' · ' ||
       (select count(*)::text from v_rrhh_pago), null;

do $$
declare v text:='';
begin
  perform set_config('role','anon', true);
  begin v:=v||(select count(*) from v_rrhh_pago_total)||' filas ❌';
  exception when insufficient_privilege then v:=v||'denegado'; when others then v:=v||'denegado('||sqlstate||')'; end;
  begin perform rrhh_pago_total(); v:=v||' · ejecuto la funcion ❌';
  exception when insufficient_privilege then v:=v||' · denegado'; when others then v:=v||' · denegado('||sqlstate||')'; end;
  begin perform rrhh_pago_puede_ver(); v:=v||' · ejecuto puede_ver ❌';
  exception when insufficient_privilege then v:=v||' · denegado'; when others then v:=v||' · denegado('||sqlstate||')'; end;
  perform set_config('role','postgres', true);
  insert into zz_res values (14,
    'anon · leer la puerta · ejecutar rrhh_pago_total() · ejecutar puede_ver()',
    'denegado · denegado · denegado', v, null);
end $$;
select set_config('role','postgres', true);


-- ════════════════════════════════════════════════════════════════════════
-- 4 · LOS DATOS REALES, INTACTOS
-- ════════════════════════════════════════════════════════════════════════
-- Esta y el veredicto vuelven a postgres: cuentan filas de las TABLAS, no de las
-- vistas, y la pregunta es cuantas hay — no cuantas ve tal perfil.
set local role postgres;
insert into zz_res
select 15, 'los datos reales · filas que NO son del ensayo en las tres tablas del pago',
       'las mismas que antes',
       'netos ' || (select count(*)::text from rrhh_neto_quincena where creado_por <> 'ensayo-asis')
       || ' · permisos ' || (select count(*)::text from rrhh_permiso where creado_por <> 'ensayo-asis')
       || ' · ajustes ' || (select count(*)::text from rrhh_ajuste_manual where creado_por <> 'ensayo-asis'),
       'INFO';


-- 16 · INFO · QUE PRIVILEGIOS HAY DE VERDAD EN ESTA BASE.
--      No es una prueba y no puede fallar: esta para SABER por que una fila dio
--      un codigo y no otro, sin tener que adivinar.
--      ⚠️ SE MIDE `authenticated`, NO «el asistente». No existe un rol de base de
--      datos llamado asistente: el perfil es una fila en acceso_usuario, y en
--      Postgres tanto la socia como el equipo como Instinct son `authenticated`.
--      Por eso los privilegios NO distinguen perfiles — lo que distingue son las
--      POLITICAS, que miran el correo del JWT. Confundir las dos cosas fue lo que
--      hizo que el esperado de la 12.3 estuviera mal.
insert into zz_res
select 16, 'INFO · privilegios de `authenticated` (= cualquier sesion) · ins/upd/del',
       '(lo que diga, no es una falla)',
       string_agg(x.t || ': ' ||
         case when has_table_privilege('authenticated','public.'||x.t,'INSERT') then 'ins' else '—' end || '/' ||
         case when has_table_privilege('authenticated','public.'||x.t,'UPDATE') then 'upd' else '—' end || '/' ||
         case when has_table_privilege('authenticated','public.'||x.t,'DELETE') then 'del' else '—' end,
         ' · ' order by x.t),
       'INFO'
  from (select unnest(array['rrhh_ajuste_manual','rrhh_neto_quincena',
                            'rrhh_feriado_trabajado']) as t) x;

insert into zz_res
select 17, 'INFO · y lo mismo para `anon`, que es la clave publica',
       '(tiene que ser todo —)',
       string_agg(x.t || ': ' ||
         case when has_table_privilege('anon','public.'||x.t,'INSERT') then 'ins' else '—' end || '/' ||
         case when has_table_privilege('anon','public.'||x.t,'UPDATE') then 'upd' else '—' end || '/' ||
         case when has_table_privilege('anon','public.'||x.t,'DELETE') then 'del' else '—' end,
         ' · ' order by x.t),
       'INFO'
  from (select unnest(array['rrhh_ajuste_manual','rrhh_neto_quincena',
                            'rrhh_feriado_trabajado']) as t) x;


-- ── EL VEREDICTO ────────────────────────────────────────────────────────
update zz_res set veredicto =
  case when obtenido is null                  then 'SIN DATO'
       when btrim(obtenido) = btrim(esperado) then 'OK'
       else 'FALLA' end
 where n in (1,2,3,4,5,6,7,8,9,10,11,12.1,12.2,12.3,12.4,12.5,12.6,13,14);

-- Y las que tenian que correr y podrian no existir: si un `select ... from`
-- no devuelve filas, el insert no inserta y la prueba DESAPARECE en silencio.
insert into zz_res
select v.n, 'ESTA PRUEBA NO CORRIO · la consulta no devolvio ninguna fila',
       'la fila existe', 'NO EXISTE', 'FALLA'
  from (values (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),
               (12.1),(12.2),(12.3),(12.4),(12.5),(12.6),(13),(14)) v(n)
 where v.n not in (select r.n from zz_res r);

-- El veredicto primero y el TOTAL arriba: una sola foto alcanza.
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
    select (select case when count(*) < 19 then 'FALTAN PRUEBAS · NO PEGAR'
                        when count(*) filter (where veredicto <> 'OK') = 0 then 'TODO VERDE'
                        else 'HAY ROJO · NO PEGAR' end from zz_res where veredicto in ('OK','FALLA','SIN DATO')),
           99, '── TOTAL ──',
           (select count(*)::text || ' pruebas' from zz_res where veredicto in ('OK','FALLA','SIN DATO')),
           (select count(*) filter (where veredicto='OK')::text || ' OK · ' ||
                   count(*) filter (where veredicto='FALLA')::text || ' FALLA · ' ||
                   count(*) filter (where veredicto='SIN DATO')::text || ' SIN DATO'
              from zz_res where veredicto in ('OK','FALLA','SIN DATO')),
           0
  ) t
 order by t.grupo, t.n;
