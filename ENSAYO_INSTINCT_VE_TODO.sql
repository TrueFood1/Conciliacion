-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_INSTINCT_VE_TODO.sql  ·  13-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Aplica el bloque de INSTINCT_VE_TODO.sql, prueba a Instinct encendido y apagado TABLA POR TABLA
-- (las 61 de public), Personal, el calendario y los archivos, que siga sin escribir, y que socias y
-- equipo sigan igual. Lo deshace todo (rollback).
-- ⏳ SIN CORRER.
--
-- W1 y W4: sin regla permisiva de inserción (salarios) o solo de socias (archivos), Postgres rechaza con el
-- mensaje genérico de RLS; W6 (pedidos, permisiva `true`) prueba que el que frena es asistente_no_inserta.
--
-- CÓMO SE LEE: 23 filas, TODAS con ok = true. T1 y A1 listan las tablas que fallen (si no, «todas» y
-- «ninguna»). Un RECHAZA vale solo con su SQLSTATE y su motivo. Si el editor dice "Success. No rows
-- returned", no llegó al final y no vale.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE (copia de INSTINCT_VE_TODO.sql, §1 a §5) ▼▼▼
-- §1 · LA RESTRICCIÓN DE LECTURA, IGUAL PARA TODO: Personal (rrhh_*) y archivos (storage.objects) dejan de
--      estar cerrados para el asistente; quedan como todas las demás: solo con su interruptor encendido.
do $$
declare r record;
begin
  for r in select p.polrelid::regclass as t
             from pg_policy p join pg_class c on c.oid = p.polrelid join pg_namespace n on n.oid = c.relnamespace
            where p.polname = 'asistente_lee' and n.nspname in ('public', 'storage')
              and pg_get_expr(p.polqual, p.polrelid) not ilike '%asistente_encendido%' loop
    execute format('drop policy asistente_lee on %s', r.t);
    execute format('create policy asistente_lee on %s as restrictive for select to authenticated '
                   'using (not (select public.acceso_es_asistente()) or (select public.asistente_encendido()))', r.t);
  end loop;
end $$;

-- §2 · LA LECTURA DEL ASISTENTE EN TODA TABLA DE public. Hasta hoy dependía de la regla de cada tabla, y
--      muchas son «solo socias» (salarios, planilla, compras…). Instinct ve todo, como Andrea y Lorena.
do $$
declare r record;
begin
  for r in select c.oid::regclass as t from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind in ('r', 'p') loop
    execute format('create policy asistente_ve_todo on %s for select to authenticated '
                   'using ((select public.acceso_es_asistente()))', r.t);
  end loop;
end $$;

-- §3 · ARCHIVOS: justificantes, aguinaldos y tickets, en lectura.
create policy asistente_ve_archivos on storage.objects for select to authenticated
  using ((select public.acceso_es_asistente()));

-- §4 · rrhh_calendario(): la guardia del 12-oct le devolvía CERO filas al asistente siempre. Ahora solo
--      cuando está bloqueado (interruptor apagado). Se cambian SOLO esas dos líneas de la definición viva.
do $$
declare d text; viejo text; nuevo text;
begin
  d := pg_get_functiondef('public.rrhh_calendario()'::regprocedure);
  viejo := E'  -- ASISTENTE (12-oct): Personal cerrado para el asistente. Cero filas, como sin perfil.\n'
        || E'  if (select public.acceso_es_asistente()) then return; end if;\n';
  nuevo := E'  -- ASISTENTE (13-oct, Andrea: Instinct ve todo): solo con su interruptor encendido.\n'
        || E'  if (select public.asistente_bloqueado()) then return; end if;\n';
  if (length(d) - length(replace(d, viejo, ''))) / length(viejo) <> 1 then
    raise exception 'rrhh_calendario: la guardia del 12-oct no está una sola vez';
  end if;
  execute replace(d, viejo, nuevo);
end $$;

-- §5 · LAS TABLAS DE MAÑANA: el disparador `asistente_politicas` llama a esta función en cada tabla nueva.
--      Sin la excepción de Personal, y con la lectura del asistente incluida.
create or replace function public.asistente_crear_politicas(p_tabla regclass) returns void
language plpgsql security definer set search_path = public as $f$
begin
  execute format('create policy asistente_no_inserta on %s as restrictive for insert to authenticated '
                 'with check (not (select public.acceso_es_asistente()))', p_tabla);
  execute format('create policy asistente_no_actualiza on %s as restrictive for update to authenticated '
                 'using (not (select public.acceso_es_asistente())) with check (not (select public.acceso_es_asistente()))', p_tabla);
  execute format('create policy asistente_no_borra on %s as restrictive for delete to authenticated '
                 'using (not (select public.acceso_es_asistente()))', p_tabla);
  execute format('create policy asistente_lee on %s as restrictive for select to authenticated '
                 'using (not (select public.acceso_es_asistente()) or (select public.asistente_encendido()))', p_tabla);
  -- Instinct ve todo (Andrea, 13-oct): también las tablas que se creen después.
  execute format('create policy asistente_ve_todo on %s for select to authenticated '
                 'using ((select public.acceso_es_asistente()))', p_tabla);
end;
$f$;
revoke all on function public.asistente_crear_politicas(regclass) from public, anon, authenticated;
-- ▲▲▲ FIN BLOQUE ▲▲▲

do $$
declare
  v_socia text; v_equipo text; v_n bigint; v_tot bigint; v_t text; v_dif text; r record;
  v_sal bigint; v_per bigint; v_qui bigint; v_arch bigint; v_cal bigint;
  v_res jsonb := '[]'::jsonb;
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by id limit 1;
  select email into v_equipo from v_acceso_usuario where perfil = 'equipo' and activo order by id limit 1;
  if v_socia is null or v_equipo is null then
    raise exception 'el ensayo necesita una socia y alguien de equipo (socia %, equipo %)', v_socia, v_equipo;
  end if;

  -- ── punto de partida: el interruptor ENCENDIDO por una socia (dentro del ensayo) ──
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_interruptor (encendido, motivo, creado_por) values (true, 'ensayo', v_socia);
    v_res := v_res || jsonb_build_object('p','S0 la socia enciende (dentro del ensayo)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S0 la socia enciende (dentro del ensayo)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into v_sal from rrhh_salario;
  select count(*) into v_per from rrhh_persona;
  select count(*) into v_qui from rrhh_quincena_aplicada;
  select count(*) into v_arch from storage.objects;
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_cal from rrhh_calendario();
  -- tabla por tabla: lo que ve Instinct contra lo que hay (postgres ve todo)
  v_dif := '';
  for r in select c.oid::regclass as t from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind in ('r', 'p') order by c.relname loop
    perform set_config('role', 'postgres', true);
    execute format('select count(*) from %s', r.t) into v_tot;
    perform set_config('request.jwt.claims', json_build_object('email', 'instinct@truefoodcr.com', 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    execute format('select count(*) from %s', r.t) into v_n;
    if v_n <> v_tot then v_dif := v_dif || r.t::text || ' (' || v_n || ' de ' || v_tot || ') '; end if;
  end loop;
  perform set_config('role', 'postgres', true);
  begin
    v_t := (case when v_dif = '' then 'todas' else v_dif end)::text;
    v_res := v_res || jsonb_build_object('p','T1 encendido: Instinct ve TODAS las filas de TODAS las tablas de public','esperado',('todas')::text,'obtenido',v_t,'ok',v_t = ('todas')::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T1 encendido: Instinct ve TODAS las filas de TODAS las tablas de public','esperado',('todas')::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', 'instinct@truefoodcr.com', 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    v_t := ((select count(*) from rrhh_salario))::text;
    v_res := v_res || jsonb_build_object('p','T2 salarios: todos','esperado',(v_sal)::text,'obtenido',v_t,'ok',v_t = (v_sal)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T2 salarios: todos','esperado',(v_sal)::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := ((select count(*) from rrhh_persona))::text;
    v_res := v_res || jsonb_build_object('p','T3 personas: todas','esperado',(v_per)::text,'obtenido',v_t,'ok',v_t = (v_per)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T3 personas: todas','esperado',(v_per)::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := ((select count(*) from rrhh_quincena_aplicada))::text;
    v_res := v_res || jsonb_build_object('p','T4 quincenas aplicadas: todas','esperado',(v_qui)::text,'obtenido',v_t,'ok',v_t = (v_qui)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T4 quincenas aplicadas: todas','esperado',(v_qui)::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := ((select count(*) from rrhh_calendario()))::text;
    v_res := v_res || jsonb_build_object('p','T5 rrhh_calendario(): lo mismo que una socia','esperado',(v_cal)::text,'obtenido',v_t,'ok',v_t = (v_cal)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T5 rrhh_calendario(): lo mismo que una socia','esperado',(v_cal)::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := ((select count(*) from storage.objects))::text;
    v_res := v_res || jsonb_build_object('p','T6 archivos: todos','esperado',(v_arch)::text,'obtenido',v_t,'ok',v_t = (v_arch)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T6 archivos: todos','esperado',(v_arch)::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := (acceso_es_asistente())::text;
    v_res := v_res || jsonb_build_object('p','T7 sigue siendo asistente','esperado',(true)::text,'obtenido',v_t,'ok',v_t = (true)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T7 sigue siendo asistente','esperado',(true)::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into rrhh_salario default values;
    v_res := v_res || jsonb_build_object('p','W1 NO inserta un salario','esperado','RECHAZA · 42501 · row-level security','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','W1 NO inserta un salario','esperado','RECHAZA · 42501 · row-level security','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501' and sqlerrm like '%row-level security%');
  end;
  begin
    update rrhh_persona set nombre = nombre;
    get diagnostics v_n = row_count;
    v_res := v_res || jsonb_build_object('p','W2 NO actualiza personas','esperado',(0)::text||' filas','obtenido',v_n::text||' filas','ok',v_n = (0));
  exception when others then
    v_res := v_res || jsonb_build_object('p','W2 NO actualiza personas','esperado',(0)::text||' filas','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    delete from rrhh_salario;
    get diagnostics v_n = row_count;
    v_res := v_res || jsonb_build_object('p','W3 NO borra salarios','esperado',(0)::text||' filas','obtenido',v_n::text||' filas','ok',v_n = (0));
  exception when others then
    v_res := v_res || jsonb_build_object('p','W3 NO borra salarios','esperado',(0)::text||' filas','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into storage.objects (bucket_id, name) values ('justificantes', 'ensayo/x.txt');
    v_res := v_res || jsonb_build_object('p','W4 NO sube archivos','esperado','RECHAZA · 42501 · row-level security','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','W4 NO sube archivos','esperado','RECHAZA · 42501 · row-level security','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501' and sqlerrm like '%row-level security%');
  end;
  begin
    insert into asistente_permiso (capacidad, encendido, motivo, creado_por) values ('leer_todo', true, 'yo', 'instinct@truefoodcr.com');
    v_res := v_res || jsonb_build_object('p','W5 NO se da permisos','esperado','RECHAZA · 42501 · row-level security','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','W5 NO se da permisos','esperado','RECHAZA · 42501 · row-level security','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501' and sqlerrm like '%row-level security%');
  end;
  begin
    insert into ent_pedido (fecha_despacho, origen, motivo, creado_por) values (current_date, 'x', 'x', 'instinct@truefoodcr.com');
    v_res := v_res || jsonb_build_object('p','W6 NO inserta un pedido','esperado','RECHAZA · 42501 · asistente_no_inserta','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','W6 NO inserta un pedido','esperado','RECHAZA · 42501 · asistente_no_inserta','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501' and sqlerrm like '%asistente_no_inserta%');
  end;

  -- ── la socia APAGA ──
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_interruptor (encendido, motivo, creado_por) values (false, 'ensayo', v_socia);
    v_res := v_res || jsonb_build_object('p','S1 la socia apaga','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S1 la socia apaga','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  -- tabla por tabla: lo que ve Instinct contra lo que hay (postgres ve todo)
  v_dif := '';
  for r in select c.oid::regclass as t from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind in ('r', 'p') order by c.relname loop
    perform set_config('role', 'postgres', true);
    execute format('select count(*) from %s', r.t) into v_tot;
    perform set_config('request.jwt.claims', json_build_object('email', 'instinct@truefoodcr.com', 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    execute format('select count(*) from %s', r.t) into v_n;
    if v_n > 0 then v_dif := v_dif || r.t::text || ' (' || v_n || ' de ' || v_tot || ') '; end if;
  end loop;
  perform set_config('role', 'postgres', true);
  begin
    v_t := (case when v_dif = '' then 'ninguna' else v_dif end)::text;
    v_res := v_res || jsonb_build_object('p','A1 apagado: Instinct no ve NINGUNA fila de NINGUNA tabla','esperado',('ninguna')::text,'obtenido',v_t,'ok',v_t = ('ninguna')::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A1 apagado: Instinct no ve NINGUNA fila de NINGUNA tabla','esperado',('ninguna')::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', 'instinct@truefoodcr.com', 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    v_t := ((select count(*) from rrhh_calendario()))::text;
    v_res := v_res || jsonb_build_object('p','A2 apagado: rrhh_calendario() vacío','esperado',(0)::text,'obtenido',v_t,'ok',v_t = (0)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A2 apagado: rrhh_calendario() vacío','esperado',(0)::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := ((select count(*) from storage.objects))::text;
    v_res := v_res || jsonb_build_object('p','A3 apagado: 0 archivos','esperado',(0)::text,'obtenido',v_t,'ok',v_t = (0)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A3 apagado: 0 archivos','esperado',(0)::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;

  -- ── socias y equipo: igual que antes ──
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    v_t := ((select count(*) from rrhh_salario))::text;
    v_res := v_res || jsonb_build_object('p','Q1 la socia sigue viendo todos los salarios','esperado',(v_sal)::text,'obtenido',v_t,'ok',v_t = (v_sal)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','Q1 la socia sigue viendo todos los salarios','esperado',(v_sal)::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := ((select count(*) from rrhh_calendario()))::text;
    v_res := v_res || jsonb_build_object('p','Q2 la socia sigue viendo el calendario','esperado',(v_cal)::text,'obtenido',v_t,'ok',v_t = (v_cal)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','Q2 la socia sigue viendo el calendario','esperado',(v_cal)::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    v_t := ((select count(*) from rrhh_salario))::text;
    v_res := v_res || jsonb_build_object('p','Q3 alguien de equipo sigue SIN ver salarios','esperado',(0)::text,'obtenido',v_t,'ok',v_t = (0)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','Q3 alguien de equipo sigue SIN ver salarios','esperado',(0)::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := (acceso_es_asistente())::text;
    v_res := v_res || jsonb_build_object('p','Q4 alguien de equipo no es asistente','esperado',(false)::text,'obtenido',v_t,'ok',v_t = (false)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','Q4 alguien de equipo no es asistente','esperado',(false)::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('role', 'postgres', true);
  begin
    v_t := ((select count(*) from rrhh_salario))::text;
    v_res := v_res || jsonb_build_object('p','Z1 salarios intactos','esperado',(v_sal)::text,'obtenido',v_t,'ok',v_t = (v_sal)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','Z1 salarios intactos','esperado',(v_sal)::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: 23 filas, todas ok = true.

rollback;
