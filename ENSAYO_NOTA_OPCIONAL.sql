-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_NOTA_OPCIONAL.sql  ·  24-sep-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Tickets: la nota al descartar o posponer pasa a ser OPCIONAL.
--
-- QUE ES
--   El ensayo completo de `PEGADO_NOTA_OPCIONAL.sql`: aplica el cambio, prueba
--   con una sesion simulada de socia (y de equipo, y sin sesion) y termina en
--   `rollback`. Se pega ENTERO en el editor de SQL. No deja nada.
--
-- COMO SE LEE EL RESULTADO
--   El editor muestra UNA tabla: una fila por prueba, con lo esperado, lo que
--   paso y `ok`. Si el editor dice "Success. No rows returned", el ensayo NO
--   llego al final y no vale nada.
--   Las identidades salen de `v_acceso_usuario` (la primera socia activa y la
--   primera persona de equipo activa); los correos no se escriben en este
--   archivo porque el repo es publico.
--
-- POR QUE CADA PRUEBA VA EN SU PROPIO `begin ... exception`
--   Cada sub-bloque es un savepoint: si una prueba falla —y cuatro TIENEN que
--   fallar— se deshace sola y no envenena a las que siguen (el 25P02 del
--   ensayo del vigia, 23-sep).
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ── 1 · EL CAMBIO, IGUAL QUE EN EL PEGADO ─────────────────────────────────
do $$
declare v_def text;
begin
  select pg_get_constraintdef(oid) into v_def
    from pg_constraint
   where conname = 'ticket_estado_nota_ok' and conrelid = 'public.ticket_estado'::regclass;
  if v_def is distinct from
     'CHECK (((estado <> ALL (ARRAY[''en_validacion''::text, ''descartado''::text, ''pospuesto''::text])) OR (length(btrim(COALESCE(nota, ''''::text))) >= 20)))'
  then
    raise exception 'el CHECK no es el medido el 24-sep. Vino: %', v_def;
  end if;
end $$;

alter table public.ticket_estado drop constraint ticket_estado_nota_ok;
alter table public.ticket_estado add constraint ticket_estado_nota_ok
  check (estado <> 'en_validacion' or length(btrim(coalesce(nota, ''))) >= 20);


-- ── 2 · LAS PRUEBAS ───────────────────────────────────────────────────────
do $$
declare
  v_socia  text;
  v_equipo text;
  v_t      bigint;   -- el ticket de las pruebas A, B y C
  v_t2     bigint;   -- OTRO ticket, que recibe UNA sola fila: la del B1
  v_res    jsonb := '[]'::jsonb;
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by email limit 1;
  select email into v_equipo from v_acceso_usuario where perfil = 'equipo' and activo order by email limit 1;
  select max(id) into v_t  from ticket where ambito = 'truefie';
  select max(id) into v_t2 from ticket where ambito = 'truefie' and id < v_t;
  -- ⚠️ POR QUE DOS TICKETS: `creado_en` es `now()`, que dentro de una
  -- transaccion es el MISMO instante para todas las filas. Si el B1 cayera
  -- en el mismo ticket que las otras siete, "la ultima" seria un empate y
  -- la prueba D leeria cualquiera. En v_t2 la fila del B1 es la unica.
  if v_socia is null or v_equipo is null or v_t is null or v_t2 is null then
    raise exception 'falta una identidad o un ticket para ensayar (socia %, equipo %, ticket %)',
      v_socia is not null, v_equipo is not null, v_t;
  end if;

  -- ── A · SIN SESION (como cc-sql). Todavia como postgres. ──────────────
  -- A1 · en_validacion SIN nota -> el CHECK lo tiene que seguir frenando
  begin
    insert into ticket_estado (ticket_id, estado, creado_por)
    values (v_t, 'en_validacion', 'cc-sql · ensayo');
    v_res := v_res || jsonb_build_object('p','A1 cc-sql · en_validacion sin nota','esperado','RECHAZA','obtenido','ENTRO');
  exception when others then
    v_res := v_res || jsonb_build_object('p','A1 cc-sql · en_validacion sin nota','esperado','RECHAZA','obtenido','RECHAZA: '||sqlerrm);
  end;
  -- A2 · en_validacion con nota de 20+ -> entra (control: el CHECK no quedo cerrado del todo)
  begin
    insert into ticket_estado (ticket_id, estado, creado_por, nota)
    values (v_t, 'en_validacion', 'cc-sql · ensayo', 'nota de ensayo de mas de veinte');
    v_res := v_res || jsonb_build_object('p','A2 cc-sql · en_validacion con nota 20+','esperado','ENTRA','obtenido','ENTRA');
  exception when others then
    v_res := v_res || jsonb_build_object('p','A2 cc-sql · en_validacion con nota 20+','esperado','ENTRA','obtenido','RECHAZA: '||sqlerrm);
  end;

  -- ── B · COMO SOCIA. De aca en adelante la RLS aplica. ─────────────────
  perform set_config('request.jwt.claims',
    json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);

  -- B1 · descartado SIN nota -> ENTRA (el cambio). En v_t2, ver arriba.
  begin
    insert into ticket_estado (ticket_id, estado, creado_por) values (v_t2, 'descartado', v_socia);
    v_res := v_res || jsonb_build_object('p','B1 socia · descartado sin nota','esperado','ENTRA','obtenido','ENTRA');
  exception when others then
    v_res := v_res || jsonb_build_object('p','B1 socia · descartado sin nota','esperado','ENTRA','obtenido','RECHAZA: '||sqlerrm);
  end;
  -- B2 · pospuesto SIN nota -> ENTRA (el cambio)
  begin
    insert into ticket_estado (ticket_id, estado, creado_por) values (v_t, 'pospuesto', v_socia);
    v_res := v_res || jsonb_build_object('p','B2 socia · pospuesto sin nota','esperado','ENTRA','obtenido','ENTRA');
  exception when others then
    v_res := v_res || jsonb_build_object('p','B2 socia · pospuesto sin nota','esperado','ENTRA','obtenido','RECHAZA: '||sqlerrm);
  end;
  -- B3 · descartado con nota CORTA (3 caracteres) -> ENTRA (sin minimo)
  begin
    insert into ticket_estado (ticket_id, estado, creado_por, nota) values (v_t, 'descartado', v_socia, 'no.');
    v_res := v_res || jsonb_build_object('p','B3 socia · descartado nota de 3','esperado','ENTRA','obtenido','ENTRA');
  exception when others then
    v_res := v_res || jsonb_build_object('p','B3 socia · descartado nota de 3','esperado','ENTRA','obtenido','RECHAZA: '||sqlerrm);
  end;
  -- B4 · pospuesto con nota LARGA (2000 caracteres) -> ENTRA (sin maximo)
  begin
    insert into ticket_estado (ticket_id, estado, creado_por, nota) values (v_t, 'pospuesto', v_socia, repeat('x', 2000));
    v_res := v_res || jsonb_build_object('p','B4 socia · pospuesto nota de 2000','esperado','ENTRA','obtenido','ENTRA');
  exception when others then
    v_res := v_res || jsonb_build_object('p','B4 socia · pospuesto nota de 2000','esperado','ENTRA','obtenido','RECHAZA: '||sqlerrm);
  end;
  -- B5 · cerrado SIN nota -> ENTRA (ya era asi; control)
  begin
    insert into ticket_estado (ticket_id, estado, creado_por) values (v_t, 'cerrado', v_socia);
    v_res := v_res || jsonb_build_object('p','B5 socia · cerrado sin nota','esperado','ENTRA','obtenido','ENTRA');
  exception when others then
    v_res := v_res || jsonb_build_object('p','B5 socia · cerrado sin nota','esperado','ENTRA','obtenido','RECHAZA: '||sqlerrm);
  end;
  -- B6 · bloqueado SIN espera ni ticket -> RECHAZA (bloqueado NO cambia)
  begin
    insert into ticket_estado (ticket_id, estado, creado_por) values (v_t, 'bloqueado', v_socia);
    v_res := v_res || jsonb_build_object('p','B6 socia · bloqueado sin espera','esperado','RECHAZA','obtenido','ENTRO');
  exception when others then
    v_res := v_res || jsonb_build_object('p','B6 socia · bloqueado sin espera','esperado','RECHAZA','obtenido','RECHAZA: '||sqlerrm);
  end;
  -- B7 · bloqueado CON espera de 8+ -> ENTRA (control del B6)
  begin
    insert into ticket_estado (ticket_id, estado, creado_por, espera)
    values (v_t, 'bloqueado', v_socia, 'que Daniel cuente');
    v_res := v_res || jsonb_build_object('p','B7 socia · bloqueado con espera','esperado','ENTRA','obtenido','ENTRA');
  exception when others then
    v_res := v_res || jsonb_build_object('p','B7 socia · bloqueado con espera','esperado','ENTRA','obtenido','RECHAZA: '||sqlerrm);
  end;
  -- B8 · en_validacion SIN nota, con sesion de socia -> RECHAZA (el CHECK no mira quien)
  begin
    insert into ticket_estado (ticket_id, estado, creado_por) values (v_t, 'en_validacion', v_socia);
    v_res := v_res || jsonb_build_object('p','B8 socia · en_validacion sin nota','esperado','RECHAZA','obtenido','ENTRO');
  exception when others then
    v_res := v_res || jsonb_build_object('p','B8 socia · en_validacion sin nota','esperado','RECHAZA','obtenido','RECHAZA: '||sqlerrm);
  end;

  -- ── C · COMO EQUIPO. Afloja la nota, NO el permiso. ───────────────────
  perform set_config('request.jwt.claims',
    json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  -- C1 · descartado sin nota, desde equipo -> RECHAZA (sigue siendo de socias)
  begin
    insert into ticket_estado (ticket_id, estado, creado_por) values (v_t, 'descartado', v_equipo);
    v_res := v_res || jsonb_build_object('p','C1 equipo · descartado sin nota','esperado','RECHAZA','obtenido','ENTRO');
  exception when others then
    v_res := v_res || jsonb_build_object('p','C1 equipo · descartado sin nota','esperado','RECHAZA','obtenido','RECHAZA: '||sqlerrm);
  end;

  -- ── D · COMO SE VE. La fila del B1, leida por las dos vistas. ─────────
  -- Vuelve la socia, para leer como la pantalla.
  perform set_config('request.jwt.claims',
    json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  -- D1 · v_ticket: el estado que dibuja la lista. La lista NO pide
  --      `ultima_nota`, pero se mide igual: tiene que ser NULL, no ''.
  -- ⚠️ `jsonb || NULL` es NULL: si el select no encuentra la fila, se
  -- perderian TODOS los resultados de arriba. Por eso el coalesce.
  v_res := v_res || coalesce((
    select jsonb_build_object('p','D1 v_ticket · estado y ultima_nota',
             'esperado','descartado · null',
             'obtenido', estado || ' · ' || coalesce('«'||ultima_nota||'»','null'))
      from v_ticket where id = v_t2),
    jsonb_build_object('p','D1 v_ticket · estado y ultima_nota','esperado','descartado · null',
                       'obtenido','NO APARECIO la fila'));
  -- D2 · v_ticket_historial: el renglon del descartado sin nota. `detalle`
  --      no puede decir "null" ni traer basura: vacio y nada mas.
  v_res := v_res || coalesce((
    select jsonb_build_object('p','D2 v_ticket_historial · descartado sin nota',
             'esperado','detalle vacio',
             'obtenido', 'detalle «' || coalesce(h.detalle,'<NULL>') || '»')
      from v_ticket_historial h
     where h.ticket_id = v_t2 and h.que = 'Descartado'
       and h.quien = v_socia and h.cuando = now()),
    jsonb_build_object('p','D2 v_ticket_historial · descartado sin nota','esperado','detalle vacio',
                       'obtenido','NO APARECIO la fila'));

  perform set_config('ensayo.res', v_res::text, true);
end $$;


-- ── 3 · EL RESULTADO. Esta tabla ES el ensayo. ────────────────────────────
-- ESPERADO: 13 filas, todas con ok = true.
select r.p as prueba, r.esperado, r.obtenido,
       case when r.esperado in ('ENTRA','RECHAZA')
            then split_part(r.obtenido, ':', 1) = r.esperado
            else r.obtenido = case r.p
                   when 'D1 v_ticket · estado y ultima_nota' then 'descartado · null'
                   else 'detalle «»' end
       end as ok
  from jsonb_to_recordset(current_setting('ensayo.res')::jsonb)
       as r(p text, esperado text, obtenido text);

rollback;

-- ── 4 · DESPUES DEL ROLLBACK (opcional, con pg_lector) ────────────────────
-- select pg_get_constraintdef(oid) from pg_constraint where conname='ticket_estado_nota_ok';
--   -> tiene que seguir nombrando 'descartado' y 'pospuesto': el ensayo no dejo nada.
