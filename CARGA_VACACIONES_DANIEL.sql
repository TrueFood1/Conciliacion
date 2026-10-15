-- ════════════════════════════════════════════════════════════════════════
-- CARGA HISTORICA · 7 dias de vacaciones de Daniel, tomados antes de Truefie
-- 7-oct-2026. NO SE CORRIO.
-- Va DESPUES de PERSONAL_ARREGLO_RESOLVER.sql (pegado 8), que ya esta aplicado:
-- la aprobacion pasa por rrhh_resolver_evento(), y antes de ese arreglo esa
-- funcion no podia escribir.
--
-- ENSAYADO PRIMERO. PRUEBAS_CARGA_VACACIONES.sql corrio el 7-oct con estos
-- mismos datos y termino en ROLLBACK: 13 filas, saldo 9 ganados / 7 tomados /
-- 2 disponibles, y las solicitudes de noviembre intactas.
--
-- QUE CARGA (7 dias, todos completos, todos de 2026):
--     20 de marzo ....... 1 dia   (viernes)
--     24 de abril ....... 1 dia   (viernes)
--     22 al 26 de junio . 5 dias  (lunes a viernes)
--
-- ⚠️ NO TOCA las dos solicitudes del 19-20 de noviembre. El candado de la
-- seccion 5 ABORTA si alguna cambia.
--
-- ⚠️ SEGURO CONTRA UNA SEGUNDA CORRIDA. La seccion 1 aborta si ya existe
-- cualquier evento de Daniel con este motivo. Correrlo dos veces NO puede
-- dejar 14 dias tomados: la transaccion se cae antes de insertar nada.
--
-- POR QUE ESTA OPCION Y NO UNA TABLA DE AJUSTE DE SALDO. Se conocen las fechas
-- reales, asi que lo que se guarda es el HECHO —estuvo fuera estos dias— y no
-- una correccion de saldo. El calendario pasa a reflejar algo que ocurrio. Si
-- las fechas no se supieran, lo correcto seria lo otro: una nota que diga "7
-- dias antes de Truefie" es mas honesta que siete fechas inventadas.
--
-- EL `creado_por` ES EL CORREO DE LORENA, no el de Daniel, porque esto es una
-- carga que hace una socia. Por eso el motivo lo dice con todas las letras: en
-- seis meses, una fila de 7 dias a nombre de Daniel sin esa nota se lee como una
-- solicitud que el hizo un dia, y nadie se va a acordar.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── 0 · QUIEN ES QUIEN ──────────────────────────────────────────────────
-- LOS CONTEOS PRIMERO. `count(*)` nunca puede dar 21000, asi que el guardia
-- alcanza a hablar. El ensayo fallo con 21000 porque el escalar corria antes del
-- guardia, y porque `ilike 'daniel%'` matchea tambien a DANIELA: el matcher es
-- la primera palabra EXACTA. Con un `limit 1` los 7 dias podian haber quedado
-- cargados a la persona equivocada.
select set_config('cv.id_manual', '', true);   -- override, si el nombre no alcanza

select set_config('cv.daniel_n',
  (select count(*)::text from rrhh_persona p
    where lower(split_part(btrim(p.nombre), ' ', 1)) = 'daniel'), true);
select set_config('cv.socia_n',
  (select count(*)::text from acceso_usuario a
    where lower(split_part(btrim(a.nombre), ' ', 1)) = 'lorena'
      and a.perfil = 'socias' and a.activo), true);

do $$
declare v_n int;
begin
  if coalesce(current_setting('cv.id_manual', true),'') <> '' then
    select count(*) into v_n from rrhh_persona p
     where p.id = current_setting('cv.id_manual', true)::bigint;
    if v_n <> 1 then
      raise exception 'ABORTADO: el id de cv.id_manual (%) no existe en rrhh_persona.',
        current_setting('cv.id_manual', true);
    end if;
    perform set_config('cv.daniel', current_setting('cv.id_manual', true), true);
  elsif coalesce(nullif(current_setting('cv.daniel_n', true),'')::numeric, -1) <> 1 then
    raise exception 'ABORTADO: % personas tienen "Daniel" como primera palabra del nombre. '
      'Tiene que ser exactamente 1 para no cargarle los dias a quien no es. Mira quienes '
      'son y pone el id a mano arriba:  select id, nombre from rrhh_persona order by id;',
      current_setting('cv.daniel_n', true);
  else
    perform set_config('cv.daniel',
      (select p.id::text from rrhh_persona p
        where lower(split_part(btrim(p.nombre), ' ', 1)) = 'daniel'), true);
  end if;

  if coalesce(nullif(current_setting('cv.socia_n', true),'')::numeric, -1) <> 1 then
    raise exception 'ABORTADO: % socias activas tienen "Lorena" como primera palabra del '
      'nombre; tiene que ser exactamente 1. La carga la firma ella, asi que no sirve '
      '"cualquier socia".', current_setting('cv.socia_n', true);
  end if;
  perform set_config('cv.socia',
    (select a.email from acceso_usuario a
      where lower(split_part(btrim(a.nombre), ' ', 1)) = 'lorena'
        and a.perfil = 'socias' and a.activo), true);
end $$;


-- ── 1 · EL CANDADO ANTI-DOBLE-CORRIDA ───────────────────────────────────
-- Va ANTES de cualquier insert. El motivo es la firma de esta carga: si ya hay
-- uno, esto ya se corrio y volver a correrlo dejaria 14 dias tomados en vez de 7.
do $$
declare v_ya int;
begin
  select count(*) into v_ya from rrhh_evento e
   where e.persona_id = current_setting('cv.daniel', true)::bigint
     and e.tipo = 'vacaciones'
     and e.motivo = 'Carga histórica: vacaciones tomadas antes de usar Truefie';
  if v_ya > 0 then
    raise exception 'ABORTADO: ya existen % evento(s) de carga historica para Daniel. '
      'Esto YA SE CORRIO. Volver a correrlo dejaria 14 dias tomados en vez de 7. '
      'Si hay que corregir algo, se anula lo viejo con rrhh_evento_anulado — no se '
      'carga de nuevo.', v_ya;
  end if;
end $$;


-- ── 2 · LOS GUARDIAS DE FECHAS, CONTRA LA BASE ──────────────────────────
create temp table cv_dias (dia date primary key) on commit drop;
insert into cv_dias (dia) values
  ('2026-03-20'), ('2026-04-24'),
  ('2026-06-22'), ('2026-06-23'), ('2026-06-24'), ('2026-06-25'), ('2026-06-26');

do $$
declare v_ing date; v_fer int; v_finde int; v_antes int;
begin
  select p.ingreso into v_ing from rrhh_persona p
   where p.id = current_setting('cv.daniel', true)::bigint;
  if v_ing is null then
    raise exception 'ABORTADO: Daniel no tiene fecha de ingreso. Sin ingreso, '
      'v_rrhh_vacacion_saldo lo EXCLUYE y el saldo no existiria.';
  end if;

  select count(*) into v_fer from cv_dias d
   where exists (select 1 from rrhh_feriado f
                  where daterange(f.fecha, coalesce(f.fecha_fin, f.fecha), '[]') @> d.dia);
  select count(*) into v_finde from cv_dias d where extract(isodow from d.dia) > 5;
  select count(*) into v_antes from cv_dias d where d.dia <= v_ing;

  if v_fer > 0 then
    raise exception 'ABORTADO: % de los 7 dias cae en un feriado o cierre de planta. '
      'Cargarlo como vacacion le descontaria a Daniel un dia que la fabrica no abria.', v_fer;
  end if;
  if v_finde > 0 then
    raise exception 'ABORTADO: % de los 7 dias cae en fin de semana.', v_finde;
  end if;
  if v_antes > 0 then
    raise exception 'ABORTADO: % de los 7 dias es anterior o igual al ingreso (%).',
      v_antes, v_ing;
  end if;
end $$;


-- ── 3 · COMO SOCIA, por el camino real ──────────────────────────────────
select set_config('request.jwt.claims',
  json_build_object('email', current_setting('cv.socia', true),
                    'role','authenticated')::text, true);
select set_config('role','authenticated', true);

do $$
begin
  if not coalesce(acceso_es_socia(), false) then
    raise exception 'ABORTADO: impersonar a la socia no funciono (acceso_es_socia() dio '
      'false). Sin eso ni el insert ni la aprobacion pasarian las politicas.';
  end if;
  -- El estado de NOVIEMBRE antes de tocar nada, para que el candado compare.
  perform set_config('cv.a_nov',
    (select count(*)::text from rrhh_evento
      where persona_id = current_setting('cv.daniel', true)::bigint
        and tipo = 'vacaciones' and fecha = date '2026-11-19'), true);
  perform set_config('cv.a_nov_pend',
    (select count(*)::text from v_rrhh_evento_estado
      where persona_id = current_setting('cv.daniel', true)::bigint
        and tipo = 'vacaciones' and fecha = date '2026-11-19'
        and estado = 'solicitado'), true);
end $$;


-- ── 4 · LA CARGA ────────────────────────────────────────────────────────
do $$
declare v_id bigint; v_n int; v_tot int := 0; r record;
begin
  for r in select * from (values (date '2026-03-20', 1),
                                 (date '2026-04-24', 1),
                                 (date '2026-06-22', 5)) as v(f, d)
  loop
    insert into rrhh_evento (persona_id, fecha, tipo, dias, motivo, creado_por)
    values (current_setting('cv.daniel', true)::bigint, r.f, 'vacaciones', r.d,
            'Carga histórica: vacaciones tomadas antes de usar Truefie',
            current_setting('cv.socia', true))
    returning id into v_id;

    select count(*) into v_n from rrhh_resolver_evento(v_id, true, null, null,
      'Carga histórica: vacaciones tomadas antes de usar Truefie');
    if v_n <> 1 then
      raise exception 'ABORTADO: la aprobacion del evento del % devolvio % filas en vez '
        'de 1. Cero filas significa que ya tenia resolucion; cualquier otra cosa es un '
        'problema. No se deja un evento cargado sin aprobar.', r.f, v_n;
    end if;
    v_tot := v_tot + v_n;
  end loop;
  perform set_config('cv.aprobadas', v_tot::text, true);
end $$;


-- ── 5 · EL CANDADO ──────────────────────────────────────────────────────
-- Las tres cosas que no se pueden dejar pasar: que los dias tomados no den 7,
-- que falte una aprobacion, o que las solicitudes de noviembre hayan cambiado.
do $$
declare
  v_ev int; v_ap int; v_tom numeric; v_gan numeric; v_disp numeric;
  v_nov int; v_nov_p int;
begin
  select count(*) into v_ev from rrhh_evento e
   where e.persona_id = current_setting('cv.daniel', true)::bigint
     and e.motivo = 'Carga histórica: vacaciones tomadas antes de usar Truefie';
  select count(*) into v_ap from rrhh_evento_aprob a
   where a.evento_id in (select id from rrhh_evento
                          where persona_id = current_setting('cv.daniel', true)::bigint
                            and motivo = 'Carga histórica: vacaciones tomadas antes de usar Truefie');
  select dias_tomados, dias_ganados, dias_disponibles into v_tom, v_gan, v_disp
    from v_rrhh_vacacion_saldo
   where persona_id = current_setting('cv.daniel', true)::bigint;
  select count(*) into v_nov from rrhh_evento
   where persona_id = current_setting('cv.daniel', true)::bigint
     and tipo = 'vacaciones' and fecha = date '2026-11-19';
  select count(*) into v_nov_p from v_rrhh_evento_estado
   where persona_id = current_setting('cv.daniel', true)::bigint
     and tipo = 'vacaciones' and fecha = date '2026-11-19' and estado = 'solicitado';

  if v_ev <> 3 then
    raise exception 'CANDADO: quedaron % eventos de carga historica en vez de 3. NO SE APLICO NADA.', v_ev;
  end if;
  if v_ap <> 3 then
    raise exception 'CANDADO: % aprobaciones en vez de 3 — hay un evento cargado sin '
      'aprobar, y un evento sin aprobar NO cuenta en el saldo. NO SE APLICO NADA.', v_ap;
  end if;
  if v_tom <> 7 then
    raise exception 'CANDADO: los dias tomados dan % en vez de 7. NO SE APLICO NADA.', v_tom;
  end if;
  if v_disp <> v_gan - 7 then
    raise exception 'CANDADO: disponibles (%) no es ganados (%) menos 7. NO SE APLICO NADA.',
      v_disp, v_gan;
  end if;
  -- LAS DE NOVIEMBRE, CONTRA EL ESTADO CAPTURADO ANTES de la carga.
  if v_nov::text <> current_setting('cv.a_nov', true)
     or v_nov_p::text <> current_setting('cv.a_nov_pend', true) then
    raise exception 'CANDADO: las solicitudes de noviembre cambiaron: eran % / % y quedaron '
      '% / %. Esta carga no tiene que tocarlas. NO SE APLICO NADA.',
      current_setting('cv.a_nov', true), current_setting('cv.a_nov_pend', true), v_nov, v_nov_p;
  end if;

  raise notice 'CANDADO OK: 3 eventos · 3 aprobaciones · 7 tomados · disponibles = % · noviembre intacto', v_disp;
end $$;


-- ── 6 · LA FILA DE CONTROL ──────────────────────────────────────────────
-- Regla 🔴 de CLAUDE.md: un "Success" del editor no es evidencia de nada.
-- ESPERADO:  3 · 3 · 7 · 2 · t     (el 2 es con 9 ganados; en noviembre seria 3)
select
  (select count(*) from rrhh_evento e
    where e.persona_id = current_setting('cv.daniel', true)::bigint
      and e.motivo = 'Carga histórica: vacaciones tomadas antes de usar Truefie')
                                                                  as eventos_cargados,
  (select count(*) from rrhh_evento_aprob a
    where a.evento_id in (select id from rrhh_evento
                           where persona_id = current_setting('cv.daniel', true)::bigint
                             and motivo = 'Carga histórica: vacaciones tomadas antes de usar Truefie'))
                                                                  as aprobaciones,
  (select dias_tomados from v_rrhh_vacacion_saldo
    where persona_id = current_setting('cv.daniel', true)::bigint) as dias_tomados,
  (select dias_disponibles from v_rrhh_vacacion_saldo
    where persona_id = current_setting('cv.daniel', true)::bigint) as dias_disponibles,
  ((select count(*)::text from rrhh_evento
     where persona_id = current_setting('cv.daniel', true)::bigint
       and tipo = 'vacaciones' and fecha = date '2026-11-19')
   = current_setting('cv.a_nov', true))                            as noviembre_intacto;

commit;


-- ════════════════════════════════════════════════════════════════════════
-- DESPUES DEL COMMIT
-- ════════════════════════════════════════════════════════════════════════
--   1. En la app: Daniel entra a «Mis vacaciones» y tiene que ver 2 disponibles,
--      con el detalle 9 ganados / 7 tomados. Y en el Calendario tienen que
--      aparecer marcados el 20-mar, el 24-abr y la semana del 22 al 26-jun.
--   2. Recien AHORA se puede aprobar la solicitud del 19-20 de noviembre: 2 dias
--      contra 2 disponibles, y el saldo queda en 0.
--      ⚠️ Nada en la base impide pasarse del saldo: ni el formulario ni
--      rrhh_resolver_evento() lo validan. Eso sigue pendiente y es otra decision.
--   3. Correrlo DOS VECES aborta en la seccion 1. Comprobado que es lo que hace:
--      el guardia va antes de cualquier insert.
