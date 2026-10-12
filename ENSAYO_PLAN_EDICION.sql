-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_PLAN_EDICION.sql  ·  11-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Prueba PLAN_EDICION.sql imitando a una socia (request.jwt.claims) y a anon, y lo
-- deshace todo (rollback). Corrido el 11-oct-2026 por Andrea: 11/11 ok.
--
-- CÓMO SE LEE
--   Una tabla de 11 filas, TODAS con ok = true. Un RECHAZA da ok solo si el SQLSTATE
--   esperado está en `obtenido`. Si el editor dice "Success. No rows returned", no
--   llegó al final y no vale. 42501 = RLS o sin permiso · 22P02 = valor mal formado.
--   Las fechas de prueba son de 2099: no se cruzan con ningún plan real.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE DDL (copia de PLAN_EDICION.sql) ▼▼▼
alter table public.plan_overrides add column edicion uuid;
comment on column public.plan_overrides.edicion is
  'Las filas que comparten edicion son los productos de ese día (dos productos el mismo día, 11-oct-2026). Null = fila anterior: un producto por fila.';
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

do $$
declare
  v_socia text; v_n int; v_t text; v_antes int;
  v_e uuid := gen_random_uuid();
  v_res jsonb := '[]'::jsonb;
begin
  select count(*) into v_antes from plan_overrides;
  select email into v_socia from v_acceso_usuario where perfil = 'socias' and activo order by id limit 1;
  if v_socia is null then raise exception 'el ensayo necesita una socia activa en acceso_usuario'; end if;

  -- ── editor SQL ──
  select data_type||' · '||is_nullable into v_t from information_schema.columns
   where table_schema='public' and table_name='plan_overrides' and column_name='edicion';
  v_res := v_res || jsonb_build_object('p','E1 la columna edicion es uuid y admite vacío','esperado','uuid · YES','obtenido',coalesce(v_t,'no existe'),'ok',v_t is not distinct from 'uuid · YES');
  select count(*) into v_n from plan_overrides where edicion is not null;
  v_res := v_res || jsonb_build_object('p','E2 ninguna fila existente tiene edicion','esperado','0','obtenido',v_n::text,'ok',v_n=0);

  -- ── socia ──
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into plan_overrides (fecha, producto_id, batches, tipo, semana_iso, personas, usuario, edicion)
    values ('2099-01-06', 451, 4, 'edicion', '2099-W02', 3, v_socia, v_e),
           ('2099-01-06', 472, 6, 'edicion', '2099-W02', 3, v_socia, v_e);
    v_res := v_res || jsonb_build_object('p','E3 la socia guarda un día con DOS productos (misma edicion)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E3 la socia guarda un día con DOS productos (misma edicion)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    -- La misma lectura que hace la app: la fila más nueva de la fecha y todas las de su edicion.
    select string_agg(producto_id||':'||batches, ' + ' order by producto_id) into v_t
      from plan_overrides o
     where o.fecha = '2099-01-06'
       and o.edicion = (select edicion from plan_overrides where fecha = '2099-01-06' order by creado_en desc, id desc limit 1);
    v_res := v_res || jsonb_build_object('p','E4 la socia la lee de vuelta: Blanco 4 + Pizza 6','esperado','451:4 + 472:6','obtenido',coalesce(v_t,'nada'),'ok',v_t is not distinct from '451:4 + 472:6');
  exception when others then
    v_res := v_res || jsonb_build_object('p','E4 la socia la lee de vuelta: Blanco 4 + Pizza 6','esperado','451:4 + 472:6','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into plan_overrides (fecha, producto_id, batches, tipo, semana_iso, personas, usuario)
    values ('2099-01-07', 453, 10, 'edicion', '2099-W02', 3, v_socia);
    v_res := v_res || jsonb_build_object('p','E5 una app vieja guarda SIN edicion (un producto)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E5 una app vieja guarda SIN edicion (un producto)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into plan_overrides (fecha, producto_id, batches, tipo, semana_iso, personas, usuario, edicion)
    values ('2099-01-06', null, 0, 'anulacion', '2099-W02', 3, v_socia, gen_random_uuid());
    v_res := v_res || jsonb_build_object('p','E6 «volver al plan» sobre el día de dos productos','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E6 «volver al plan» sobre el día de dos productos','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into plan_overrides (fecha, producto_id, batches, tipo, semana_iso, personas, usuario, edicion)
    values ('2099-01-08', 451, 4, 'edicion', '2099-W02', 3, v_socia, 'no-es-un-uuid');
    v_res := v_res || jsonb_build_object('p','E7 una edicion mal formada','esperado','RECHAZA · 22P02','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E7 una edicion mal formada','esperado','RECHAZA · 22P02','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='22P02');
  end;
  begin
    update plan_overrides set batches = 99 where edicion = v_e;
    get diagnostics v_n = row_count;
    v_res := v_res || jsonb_build_object('p','E8 la socia intenta reescribir la edición (append-only)','esperado','0 filas','obtenido',v_n||' filas','ok',v_n=0);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E8 la socia intenta reescribir la edición (append-only)','esperado','0 filas','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── anon ──
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  perform set_config('role', 'anon', true);
  begin
    insert into plan_overrides (fecha, producto_id, batches, tipo, edicion)
    values ('2099-01-09', 451, 4, 'edicion', gen_random_uuid());
    v_res := v_res || jsonb_build_object('p','E9 anon guarda un día','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E9 anon guarda un día','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── editor SQL ──
  perform set_config('role', 'postgres', true);
  select string_agg(polname, ' · ' order by polname) into v_t from pg_policy where polrelid = 'public.plan_overrides'::regclass;
  v_res := v_res || jsonb_build_object('p','E10 las políticas siguen siendo las dos de siempre','esperado','auth insert · auth read','obtenido',coalesce(v_t,'ninguna'),'ok',v_t is not distinct from 'auth insert · auth read');
  select count(*) into v_n from plan_overrides where fecha < '2099-01-01';
  v_res := v_res || jsonb_build_object('p','Z las filas reales quedaron intactas y sin edicion','esperado',v_antes||' · 0 con edicion','obtenido',v_n||' · '||(select count(*) from plan_overrides where fecha < '2099-01-01' and edicion is not null)||' con edicion',
    'ok',v_n=v_antes and not exists (select 1 from plan_overrides where fecha < '2099-01-01' and edicion is not null));

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: 11 filas, todas ok = true.

rollback;
