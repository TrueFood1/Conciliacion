-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_REFACTURA_AUTO.sql · 15-oct-2026 · ENSAYO EN SECO · TERMINA EN ROLLBACK
-- Re-facturas automáticas · REFACTURA_AUTO.sql
--
-- ⚠️ ARCHIVO GENERADO. Se regenera con
--     python3 herramientas/ensayos/armar_ensayo_refactura.py
--   El bloque DDL es el de REFACTURA_AUTO.sql BYTE A BYTE. md5: b1b55a60739e64b0ba4f5da817c3fbca
--
-- Prueba como el usuario nuevo (truefie_refactura), como socia y como equipo (sesiones simuladas
-- con RLS) y con el editor. Las facturas de prueba son números que no existen (999999990…); todo
-- se va con el rollback, también el usuario.
-- TIENE QUE DAR 33 filas, TODAS con ok = true. Si dice "Success. No rows returned",
-- no llegó al final y no vale.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ═══ DDL · DESDE ACA (ENSAYO_REFACTURA_AUTO.sql copia este bloque tal cual) ═══

-- §0 · CANDADO DE ENTRADA: nada de esto existe todavía (este pegado no pisa nada).
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'truefie_refactura') then
    raise exception 'el rol truefie_refactura ya existe: este pegado no pisa nada';
  end if;
  if to_regclass('public.ent_refactura') is not null then
    raise exception 'ent_refactura ya existe: este pegado no pisa nada';
  end if;
  if exists (select 1 from pg_proc where proname in ('refactura_entregas', 'refactura_puede_ligar')) then
    raise exception 'las funciones de re-factura ya existen: este pegado no pisa nada';
  end if;
end $$;

-- §1 · EL USUARIO. Igual de angosto que truefie_cc.
create role truefie_refactura with login nosuperuser nocreatedb nocreaterole
                                   noinherit nobypassrls noreplication;
grant usage on schema public to truefie_refactura;

-- §2 · EL RASTRO. Append-only: sin políticas de update ni delete para nadie.
create table public.ent_refactura (
  id                   bigint generated always as identity primary key,
  pedido_id            bigint  not null references public.ent_pedido(id),
  factura_vieja_id     integer not null,
  factura_vieja_nombre text,
  factura_nueva_id     integer not null,
  factura_nueva_nombre text,
  resultado            text    not null check (resultado in ('ligada', 'apartada')),
  reglas               jsonb   not null,
  motivo               text,
  origen               text    not null default 'automatico' check (origen = 'automatico'),
  creado_en            timestamptz not null default now(),
  creado_por           text    not null default 'automatico-refactura',
  -- `ligada` solo con las 4 reglas en true y sin motivo; `apartada` siempre con su motivo en palabras.
  constraint ent_refactura_ok check (
    (resultado = 'ligada'   and reglas = '{"a": true, "b": true, "c": true, "d": true}'::jsonb and motivo is null)
 or (resultado = 'apartada' and motivo is not null and length(btrim(motivo)) >= 5)),
  -- Una corrida por hora no duplica: la misma vieja→nueva con el mismo resultado entra una sola vez.
  constraint ent_refactura_una unique (factura_vieja_id, factura_nueva_id, resultado)
);
alter table public.ent_refactura enable row level security;
-- Supabase le da TODO a anon y authenticated en las tablas nuevas de public: se recorta (truncate no
-- pasa por la RLS, así que se saca explícito).
revoke all on table public.ent_refactura from anon;
revoke insert, update, delete, truncate, references, trigger on table public.ent_refactura from authenticated;
grant insert on table public.ent_refactura to truefie_refactura;

create policy ent_refactura_sel on public.ent_refactura
  for select to authenticated using (true);
create policy ent_refactura_ins_auto on public.ent_refactura
  for insert to truefie_refactura
  with check (creado_por = 'automatico-refactura' and origen = 'automatico');

-- §3 · LA GUARDIA DEL VÍNCULO. El vínculo nuevo tiene que reemplazar a la factura VIGENTE del pedido,
-- con su fila `ligada` ya en el rastro, y la factura nueva no puede ser vigente de otro pedido.
create function public.refactura_puede_ligar(p_pedido bigint, p_factura integer)
returns boolean language sql stable security definer set search_path = public as $fn$
  select exists (
           select 1 from public.ent_refactura r
            where r.pedido_id = p_pedido and r.factura_nueva_id = p_factura and r.resultado = 'ligada'
              and r.factura_vieja_id = (select v.factura_id from public.ent_pedido_factura_vigente v
                                         where v.pedido_id = p_pedido))
     and not exists (
           select 1 from public.ent_pedido_factura_vigente v
            where v.factura_id = p_factura and not v.anulado);
$fn$;
revoke all on function public.refactura_puede_ligar(bigint, integer) from public, anon, authenticated;
grant execute on function public.refactura_puede_ligar(bigint, integer) to truefie_refactura;

grant insert on table public.ent_pedido_factura to truefie_refactura;
create policy ent_pedido_factura_ins_refactura on public.ent_pedido_factura
  for insert to truefie_refactura
  with check (creado_por = 'automatico-refactura' and anulado = false
              and public.refactura_puede_ligar(pedido_id, factura_id));

-- §4 · LO QUE EL TRABAJO LEE, Y NADA MÁS: por pedido con alisto, su factura vigente, todas las que tuvo,
-- si está entregado, lo que salió del congelador por producto (alisto vigente − no entregado) y lo que
-- ya se revisó en el rastro.
create function public.refactura_entregas()
returns table (pedido_id bigint, factura_vigente integer, facturas integer[], entregado boolean,
               salio jsonb, revisadas jsonb)
language sql stable security definer set search_path = public as $fn$
  select e.pedido_id,
         fv.factura_id,
         (select array_agg(distinct f.factura_id) from public.ent_pedido_factura f where f.pedido_id = e.pedido_id),
         e.estado = 'entregado',
         (select coalesce(jsonb_object_agg(x.producto_id, x.uds), '{}'::jsonb)
            from (select l.producto_id, sum(l.cant_uds - coalesce(l.cant_no_entregada, 0)) as uds
                    from public.ent_alisto_linea l
                   where l.alisto_id = e.alisto_id and not coalesce(l.no_se_entrega, false)
                   group by l.producto_id) x),
         (select coalesce(jsonb_agg(jsonb_build_object('vieja', r.factura_vieja_id, 'nueva', r.factura_nueva_id,
                                                       'resultado', r.resultado)), '[]'::jsonb)
            from public.ent_refactura r where r.pedido_id = e.pedido_id)
    from public.v_ent_pedido_estado e
    left join public.ent_pedido_factura_vigente fv on fv.pedido_id = e.pedido_id;
$fn$;
revoke all on function public.refactura_entregas() from public, anon, authenticated;
grant execute on function public.refactura_entregas() to truefie_refactura;

-- ═══ DDL · HASTA ACA ═══

-- ── SOLO PARA ENSAYAR: que el editor pueda ponerse el usuario. Se va con el rollback.
grant truefie_refactura to postgres with set true, inherit false;

do $$
declare
  v_res jsonb := '[]'::jsonb;
  v_p bigint; v_f integer; v_p2 bigint; v_f2 integer;
  v_socia text; v_equipo text; v_n bigint; v_n2 bigint; v_t text;
begin

  -- ── los datos de prueba salen de la base: dos pedidos entregados con su factura vigente ──
  select pedido_id, factura_id into v_p, v_f from v_ent_pedido_estado where estado = 'entregado' and factura_id is not null order by pedido_id limit 1;
  select pedido_id, factura_id into v_p2, v_f2 from v_ent_pedido_estado where estado = 'entregado' and factura_id is not null and pedido_id <> v_p order by pedido_id limit 1;
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by email limit 1;
  select email into v_equipo from v_acceso_usuario where perfil = 'equipo' and activo order by email limit 1;
  if v_p is null or v_p2 is null or v_socia is null or v_equipo is null then raise exception 'falta algo para ensayar'; end if;
  if not pg_has_role('postgres', 'truefie_refactura', 'SET') then raise exception 'postgres no puede ponerse truefie_refactura'; end if;

  -- ── L · el usuario LEE solo por su función ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'truefie_refactura', true);
  select count(*), count(*) filter (where entregado) into v_n, v_n2 from refactura_entregas();
  v_res := v_res || jsonb_build_object('p', 'L1 la función devuelve pedidos (y algunos entregados)', 'esperado', '> 0 · > 0', 'obtenido', v_n::text || ' · ' || v_n2::text, 'ok', coalesce(v_n > 0 and v_n2 > 0, false));
  select salio::text into v_t from refactura_entregas() where pedido_id = 185;
  v_res := v_res || jsonb_build_object('p', 'L2 pedido 185: lo que salió del congelador', 'esperado', '{"451": 3, "453": 4, "503": 4}', 'obtenido', coalesce(v_t, '(nada)'), 'ok', coalesce(v_t::jsonb = '{"451": 3, "453": 4, "503": 4}'::jsonb, false));
  begin
    perform 1 from ent_pedido limit 1;
    v_res := v_res || jsonb_build_object('p', 'L3 leer ent_pedido directo', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_pedido', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'L3 leer ent_pedido directo', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_pedido', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table ent_pedido') > 0);
  end;
  begin
    perform 1 from ent_pedido_factura limit 1;
    v_res := v_res || jsonb_build_object('p', 'L4 leer ent_pedido_factura directo', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_pedido_factura', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'L4 leer ent_pedido_factura directo', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_pedido_factura', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table ent_pedido_factura') > 0);
  end;
  begin
    perform 1 from ent_refactura limit 1;
    v_res := v_res || jsonb_build_object('p', 'L5 leer ent_refactura directo', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_refactura', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'L5 leer ent_refactura directo', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_refactura', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table ent_refactura') > 0);
  end;

  -- ── R · el rastro: solo agregar, y con sus reglas ──
  begin
    insert into ent_refactura (pedido_id, factura_vieja_id, factura_vieja_nombre, factura_nueva_id, factura_nueva_nombre, resultado, reglas, motivo, creado_por) values (v_p, v_f, 'ENSAYO-VIEJA', 999999990, 'ENSAYO-NUEVA', 'apartada', '{"a": true, "b": true, "c": true, "d": false}'::jsonb, null, 'automatico-refactura');
    v_res := v_res || jsonb_build_object('p', 'R1 apartada SIN motivo', 'esperado', 'RECHAZA · 23514 · ent_refactura_ok', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R1 apartada SIN motivo', 'esperado', 'RECHAZA · 23514 · ent_refactura_ok', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '23514' and strpos(sqlerrm, 'ent_refactura_ok') > 0);
  end;
  begin
    insert into ent_refactura (pedido_id, factura_vieja_id, factura_vieja_nombre, factura_nueva_id, factura_nueva_nombre, resultado, reglas, motivo, creado_por) values (v_p, v_f, 'ENSAYO-VIEJA', 999999990, 'ENSAYO-NUEVA', 'ligada', '{"a": true, "b": true, "c": true, "d": false}'::jsonb, null, 'automatico-refactura');
    v_res := v_res || jsonb_build_object('p', 'R2 ligada con una regla en false', 'esperado', 'RECHAZA · 23514 · ent_refactura_ok', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R2 ligada con una regla en false', 'esperado', 'RECHAZA · 23514 · ent_refactura_ok', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '23514' and strpos(sqlerrm, 'ent_refactura_ok') > 0);
  end;
  begin
    insert into ent_refactura (pedido_id, factura_vieja_id, factura_vieja_nombre, factura_nueva_id, factura_nueva_nombre, resultado, reglas, motivo, creado_por) values (v_p, v_f, 'ENSAYO-VIEJA', 999999990, 'ENSAYO-NUEVA', 'ligada', '{"a": true, "b": true, "c": true, "d": true}'::jsonb, null, 'automatico-refactura');
    v_res := v_res || jsonb_build_object('p', 'R3 ligada con las 4 reglas (pedido 1, su vigente → nueva)', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R3 ligada con las 4 reglas (pedido 1, su vigente → nueva)', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  begin
    insert into ent_refactura (pedido_id, factura_vieja_id, factura_vieja_nombre, factura_nueva_id, factura_nueva_nombre, resultado, reglas, motivo, creado_por) values (v_p, v_f, 'ENSAYO-VIEJA', 999999990, 'ENSAYO-NUEVA', 'ligada', '{"a": true, "b": true, "c": true, "d": true}'::jsonb, null, 'automatico-refactura');
    v_res := v_res || jsonb_build_object('p', 'R4 la misma otra vez', 'esperado', 'RECHAZA · 23505 · ent_refactura_una', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R4 la misma otra vez', 'esperado', 'RECHAZA · 23505 · ent_refactura_una', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '23505' and strpos(sqlerrm, 'ent_refactura_una') > 0);
  end;
  begin
    insert into ent_refactura (pedido_id, factura_vieja_id, factura_vieja_nombre, factura_nueva_id, factura_nueva_nombre, resultado, reglas, motivo, creado_por) values (v_p, v_f, 'ENSAYO-VIEJA', 999999990, 'ENSAYO-NUEVA', 'ligada', '{"a": true, "b": true, "c": true, "d": true}'::jsonb, null, 'automatico-refactura') on conflict do nothing;
    v_res := v_res || jsonb_build_object('p', 'R5 la misma con on conflict do nothing (corrida repetida)', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R5 la misma con on conflict do nothing (corrida repetida)', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  begin
    insert into ent_refactura (pedido_id, factura_vieja_id, factura_vieja_nombre, factura_nueva_id, factura_nueva_nombre, resultado, reglas, motivo, creado_por) values (v_p, v_f, 'ENSAYO-VIEJA', 999999993, 'ENSAYO-NUEVA', 'ligada', '{"a": true, "b": true, "c": true, "d": true}'::jsonb, null, v_socia);
    v_res := v_res || jsonb_build_object('p', 'R6 firmada por una persona', 'esperado', 'RECHAZA · 42501 · row-level security', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R6 firmada por una persona', 'esperado', 'RECHAZA · 42501 · row-level security', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'row-level security') > 0);
  end;
  begin
    insert into ent_refactura (pedido_id, factura_vieja_id, factura_vieja_nombre, factura_nueva_id, factura_nueva_nombre, resultado, reglas, motivo, creado_por) values (v_p2, v_f2, 'ENSAYO-VIEJA', 999999994, 'ENSAYO-NUEVA', 'apartada', '{"a": true, "b": true, "c": true, "d": false}'::jsonb, 'cantidades distintas a lo que salió: Blanco factura 6 · salió 3', 'automatico-refactura');
    v_res := v_res || jsonb_build_object('p', 'R7 apartada con su motivo en palabras', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R7 apartada con su motivo en palabras', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;

  -- ── V · el vínculo: solo si reemplaza a la vigente con su fila «ligada» ──
  begin
    insert into ent_pedido_factura (pedido_id, factura_id, factura_nombre, anulado, nota, creado_por) values (v_p, 999999990, 'ENSAYO-NUEVA', false, 'Re-factura automática (ensayo)', 'automatico-refactura');
    v_res := v_res || jsonb_build_object('p', 'V1 ligar el pedido 1 a la nueva', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'V1 ligar el pedido 1 a la nueva', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  begin
    insert into ent_pedido_factura (pedido_id, factura_id, factura_nombre, anulado, nota, creado_por) values (v_p2, 999999991, 'ENSAYO-NUEVA', false, 'Re-factura automática (ensayo)', 'automatico-refactura');
    v_res := v_res || jsonb_build_object('p', 'V2 ligar el pedido 2 sin fila «ligada»', 'esperado', 'RECHAZA · 42501 · row-level security', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'V2 ligar el pedido 2 sin fila «ligada»', 'esperado', 'RECHAZA · 42501 · row-level security', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'row-level security') > 0);
  end;
  begin
    insert into ent_pedido_factura (pedido_id, factura_id, factura_nombre, anulado, nota, creado_por) values (v_p, 999999990, 'ENSAYO-NUEVA', false, 'Re-factura automática (ensayo)', v_socia);
    v_res := v_res || jsonb_build_object('p', 'V3 ligar firmando como persona', 'esperado', 'RECHAZA · 42501 · row-level security', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'V3 ligar firmando como persona', 'esperado', 'RECHAZA · 42501 · row-level security', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'row-level security') > 0);
  end;
  begin
    insert into ent_refactura (pedido_id, factura_vieja_id, factura_vieja_nombre, factura_nueva_id, factura_nueva_nombre, resultado, reglas, motivo, creado_por) values (v_p, v_f, 'ENSAYO-VIEJA', 999999992, 'ENSAYO-NUEVA', 'ligada', '{"a": true, "b": true, "c": true, "d": true}'::jsonb, null, 'automatico-refactura');
    v_res := v_res || jsonb_build_object('p', 'V4 rastro «ligada» con una vieja que YA no es la vigente', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'V4 rastro «ligada» con una vieja que YA no es la vigente', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  begin
    insert into ent_pedido_factura (pedido_id, factura_id, factura_nombre, anulado, nota, creado_por) values (v_p, 999999992, 'ENSAYO-NUEVA', false, 'Re-factura automática (ensayo)', 'automatico-refactura');
    v_res := v_res || jsonb_build_object('p', 'V5 … y su vínculo', 'esperado', 'RECHAZA · 42501 · row-level security', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'V5 … y su vínculo', 'esperado', 'RECHAZA · 42501 · row-level security', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'row-level security') > 0);
  end;
  begin
    insert into ent_refactura (pedido_id, factura_vieja_id, factura_vieja_nombre, factura_nueva_id, factura_nueva_nombre, resultado, reglas, motivo, creado_por) values (v_p2, v_f2, 'ENSAYO-VIEJA', 999999990, 'ENSAYO-NUEVA', 'ligada', '{"a": true, "b": true, "c": true, "d": true}'::jsonb, null, 'automatico-refactura');
    v_res := v_res || jsonb_build_object('p', 'V6 rastro: el pedido 2 «pasa» a la nueva del pedido 1', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'V6 rastro: el pedido 2 «pasa» a la nueva del pedido 1', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  begin
    insert into ent_pedido_factura (pedido_id, factura_id, factura_nombre, anulado, nota, creado_por) values (v_p2, 999999990, 'ENSAYO-NUEVA', false, 'Re-factura automática (ensayo)', 'automatico-refactura');
    v_res := v_res || jsonb_build_object('p', 'V7 … y su vínculo (la nueva ya es vigente del pedido 1)', 'esperado', 'RECHAZA · 42501 · row-level security', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'V7 … y su vínculo (la nueva ya es vigente del pedido 1)', 'esperado', 'RECHAZA · 42501 · row-level security', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'row-level security') > 0);
  end;

  -- ── N · no cambia ni borra nada, ni toca otras tablas ──
  begin
    update ent_refactura set motivo = null;
    v_res := v_res || jsonb_build_object('p', 'N1 cambiar una fila del rastro', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_refactura', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N1 cambiar una fila del rastro', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_refactura', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table ent_refactura') > 0);
  end;
  begin
    delete from ent_pedido_factura where factura_id = 999999990;
    v_res := v_res || jsonb_build_object('p', 'N2 borrar un vínculo', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_pedido_factura', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N2 borrar un vínculo', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_pedido_factura', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table ent_pedido_factura') > 0);
  end;
  begin
    insert into ent_pedido (fecha_despacho, origen, creado_por) values (current_date, 'ensayo', 'automatico-refactura');
    v_res := v_res || jsonb_build_object('p', 'N3 escribir en otra tabla (ent_pedido)', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_pedido', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N3 escribir en otra tabla (ent_pedido)', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_pedido', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table ent_pedido') > 0);
  end;

  -- ── E · el efecto, visto con el editor ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);
  select factura_id into v_n from ent_pedido_factura_vigente where pedido_id = v_p;
  v_res := v_res || jsonb_build_object('p', 'E1 la vigente del pedido 1 pasó a la nueva', 'esperado', '999999990', 'obtenido', v_n::text, 'ok', coalesce(v_n = 999999990, false));
  select count(*) into v_n from v_ent_factura_despachada where factura_id = 999999990;
  v_res := v_res || jsonb_build_object('p', 'E2 la nueva cuenta como despachada (sale de «Por preparar»)', 'esperado', '1', 'obtenido', v_n::text, 'ok', coalesce(v_n = 1, false));
  select factura_id into v_n from ent_pedido_factura_vigente where pedido_id = v_p2;
  v_res := v_res || jsonb_build_object('p', 'E3 el pedido 2 sigue con su factura', 'esperado', 'la de antes', 'obtenido', v_n::text, 'ok', coalesce(v_n = v_f2, false));

  -- ── S · socias y equipo leen el rastro; nadie más escribe ──
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  select count(*) into v_n from ent_refactura;
  v_res := v_res || jsonb_build_object('p', 'S1 socia ve el rastro (R3, R7, V4, V6)', 'esperado', '4', 'obtenido', v_n::text, 'ok', coalesce(v_n = 4, false));
  begin
    insert into ent_refactura (pedido_id, factura_vieja_id, factura_vieja_nombre, factura_nueva_id, factura_nueva_nombre, resultado, reglas, motivo, creado_por) values (v_p, v_f, 'ENSAYO-VIEJA', 999999995, 'ENSAYO-NUEVA', 'ligada', '{"a": true, "b": true, "c": true, "d": true}'::jsonb, null, v_socia);
    v_res := v_res || jsonb_build_object('p', 'S2 socia agrega al rastro', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_refactura', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'S2 socia agrega al rastro', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_refactura', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table ent_refactura') > 0);
  end;
  begin
    perform 1 from refactura_entregas();
    v_res := v_res || jsonb_build_object('p', 'S3 socia usa la función del trabajo', 'esperado', 'RECHAZA · 42501 · permission denied for function refactura_entregas', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'S3 socia usa la función del trabajo', 'esperado', 'RECHAZA · 42501 · permission denied for function refactura_entregas', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for function refactura_entregas') > 0);
  end;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  select count(*) into v_n from ent_refactura;
  v_res := v_res || jsonb_build_object('p', 'S4 equipo ve el rastro', 'esperado', '4', 'obtenido', v_n::text, 'ok', coalesce(v_n = 4, false));

  -- ── A · el usuario y los permisos, en frío ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);
  select count(*) into v_n from pg_roles where rolname = 'truefie_refactura' and rolcanlogin and not rolsuper and not rolbypassrls and not rolinherit and not rolcreaterole;
  v_res := v_res || jsonb_build_object('p', 'A1 usuario: entra, sin superusuario, sin saltear RLS, sin heredar', 'esperado', '1', 'obtenido', v_n::text, 'ok', coalesce(v_n = 1, false));
  select count(*) into v_n from information_schema.role_table_grants where table_name = 'ent_refactura' and grantee = 'anon';
  v_res := v_res || jsonb_build_object('p', 'A2 anon: permisos sobre el rastro', 'esperado', '0', 'obtenido', v_n::text, 'ok', coalesce(v_n = 0, false));
  select string_agg(privilege_type, ',' order by privilege_type) into v_t from information_schema.role_table_grants where grantee = 'truefie_refactura';
  v_res := v_res || jsonb_build_object('p', 'A3 todo lo que puede el usuario sobre tablas', 'esperado', 'INSERT,INSERT', 'obtenido', coalesce(v_t, '(nada)'), 'ok', coalesce(v_t = 'INSERT,INSERT', false));
  select count(*) into v_n from pg_policy where polrelid = 'public.ent_refactura'::regclass;
  v_res := v_res || jsonb_build_object('p', 'A4 políticas del rastro: 2 propias + 5 del asistente', 'esperado', '7', 'obtenido', v_n::text, 'ok', coalesce(v_n = 7, false));

  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('ensayo.res', v_res::text, true);
end $$;

-- ── EL RESULTADO. Esta tabla ES el ensayo. ESPERADO: 33 filas, todas ok = true.
select r.p as prueba, r.esperado, r.obtenido, r.ok
  from jsonb_to_recordset(current_setting('ensayo.res')::jsonb)
       as r(p text, esperado text, obtenido text, ok boolean);

rollback;
