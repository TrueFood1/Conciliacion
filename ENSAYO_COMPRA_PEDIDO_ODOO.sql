-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_COMPRA_PEDIDO_ODOO.sql  ·  2-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Prueba las dos tablas de COMPRA_PEDIDO_ODOO.sql (T-28) y lo deshace todo (rollback).
-- ✅ CORRIDO el 2-oct-2026 por Andrea en producción: 21 de 21 ok = true, cada RECHAZA con su SQLSTATE.
--
-- CÓMO SE LEE
--   Una tabla de 21 filas, TODAS con ok = true. Un RECHAZA da ok solo si el SQLSTATE
--   esperado está en `obtenido` (no vale rechazar por el motivo de al lado). Si el
--   editor dice "Success. No rows returned", no llegó al final y no vale.
--   42501 = RLS o sin permiso · 23514 = check · 23505 = único · 23503 = clave foránea.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE DDL (copia de COMPRA_PEDIDO_ODOO.sql) ▼▼▼
create table public.compra_propuesta (
  id            bigint generated always as identity primary key,
  proveedor_id  integer not null check (proveedor_id > 0),
  proveedor     text,
  modo          text not null check (modo in ('pedir', 'registrar')),
  pedido_dia    date not null,                       -- P: cuándo se pidió / se pide
  entrega_dia   date not null,                       -- E: cuándo llega
  uso_dia       date,                                -- U: desde cuándo se puede usar (dato, no cerca)
  -- [{producto_id, nombre, uom, calculado, pedido, empaques, empaque_lab, empaque_peso, empaque_unidad}]
  -- `pedido` y `calculado` en la UoM DEL PRODUCTO (la de stock.quant: kg, o g la levadura).
  lineas        jsonb not null check (jsonb_typeof(lineas) = 'array' and jsonb_array_length(lineas) > 0),
  creado_por    text not null,
  creado_en     timestamptz not null default now(),
  constraint compra_propuesta_fechas check (entrega_dia >= pedido_dia and entrega_dia <= pedido_dia + 14)
);

create table public.compra_pedido_odoo (
  id            bigint generated always as identity primary key,
  propuesta_id  bigint not null references public.compra_propuesta(id),
  proveedor_id  integer not null check (proveedor_id > 0),
  entrega_dia   date not null,
  po_id         integer not null,
  po_nombre     text not null check (length(btrim(po_nombre)) > 0),
  lineas        jsonb not null check (jsonb_typeof(lineas) = 'array' and jsonb_array_length(lineas) > 0),
  creado_por    text not null,
  creado_en     timestamptz not null default now(),
  constraint compra_pedido_odoo_propuesta_un unique (propuesta_id),
  constraint compra_pedido_odoo_po_un unique (po_id),
  constraint compra_pedido_odoo_ciclo_un unique (proveedor_id, entrega_dia)
);

alter table public.compra_propuesta enable row level security;
alter table public.compra_pedido_odoo enable row level security;
revoke all on public.compra_propuesta, public.compra_pedido_odoo from anon, authenticated;
grant select, insert on public.compra_propuesta, public.compra_pedido_odoo to authenticated;

create policy compra_propuesta_sel on public.compra_propuesta
  for select to authenticated using (true);
create policy compra_propuesta_ins on public.compra_propuesta
  for insert to authenticated
  with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));
create policy compra_pedido_odoo_sel on public.compra_pedido_odoo
  for select to authenticated using (true);
create policy compra_pedido_odoo_ins on public.compra_pedido_odoo
  for insert to authenticated
  with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

do $$
declare
  v_socia text; v_equipo text; v_p1 bigint; v_p2 bigint; v_n int;
  v_res jsonb := '[]'::jsonb;
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by id limit 1;
  select email into v_equipo from v_acceso_usuario where perfil <> 'socias' and activo order by id limit 1;
  if v_socia is null or v_equipo is null then
    raise exception 'el ensayo necesita una socia y alguien de equipo (socia %, equipo %)', v_socia, v_equipo;
  end if;

  -- ── socia ──
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into compra_propuesta (proveedor_id, modo, pedido_dia, entrega_dia, lineas, creado_por) values (948, 'registrar', date '2026-10-01', date '2026-10-05', '[{"producto_id":464,"pedido":50}]', v_socia) returning id into v_p1;
    v_res := v_res || jsonb_build_object('p','P1 la socia guarda una propuesta con SU nombre','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P1 la socia guarda una propuesta con SU nombre','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into compra_propuesta (proveedor_id, modo, pedido_dia, entrega_dia, lineas, creado_por) values (948, 'pedir', date '2026-10-01', date '2026-10-05', '[{"producto_id":464,"pedido":50}]', 'otra@persona.com');
    v_res := v_res || jsonb_build_object('p','P2 la socia firma con OTRO nombre','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P2 la socia firma con OTRO nombre','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into compra_propuesta (proveedor_id, modo, pedido_dia, entrega_dia, lineas, creado_por) values (948, 'pedir', date '2026-10-01', date '2026-10-05', '[]', v_socia);
    v_res := v_res || jsonb_build_object('p','P3 propuesta sin líneas','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P3 propuesta sin líneas','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into compra_propuesta (proveedor_id, modo, pedido_dia, entrega_dia, lineas, creado_por) values (948, 'regalar', date '2026-10-01', date '2026-10-05', '[{"producto_id":464,"pedido":50}]', v_socia);
    v_res := v_res || jsonb_build_object('p','P4 modo inventado','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P4 modo inventado','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into compra_propuesta (proveedor_id, modo, pedido_dia, entrega_dia, lineas, creado_por) values (948, 'pedir', date '2026-10-05', date '2026-10-01', '[{"producto_id":464,"pedido":50}]', v_socia);
    v_res := v_res || jsonb_build_object('p','P5 entrega ANTES del pedido','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P5 entrega ANTES del pedido','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into compra_propuesta (proveedor_id, modo, pedido_dia, entrega_dia, lineas, creado_por) values (948, 'pedir', date '2026-10-01', date '2026-10-21', '[{"producto_id":464,"pedido":50}]', v_socia);
    v_res := v_res || jsonb_build_object('p','P6 entrega a 20 días del pedido','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P6 entrega a 20 días del pedido','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into compra_propuesta (proveedor_id, modo, pedido_dia, entrega_dia, lineas, creado_por) values (948, 'pedir', date '2026-10-08', date '2026-10-12', '[{"producto_id":464,"pedido":50}]', v_socia) returning id into v_p2;
    v_res := v_res || jsonb_build_object('p','P7 segunda propuesta (otro ciclo)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P7 segunda propuesta (otro ciclo)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into compra_pedido_odoo (propuesta_id, proveedor_id, entrega_dia, po_id, po_nombre, lineas, creado_por) values (v_p1, 948, date '2026-10-05', -1, 'P-ENSAYO-1', '[{"producto_id":464,"pedido":50}]', v_socia);
    v_res := v_res || jsonb_build_object('p','R1 la socia registra la orden de P1','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R1 la socia registra la orden de P1','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into compra_pedido_odoo (propuesta_id, proveedor_id, entrega_dia, po_id, po_nombre, lineas, creado_por) values (v_p1, 948, date '2026-10-19', -2, 'P-ENSAYO-2', '[{"producto_id":464,"pedido":50}]', v_socia);
    v_res := v_res || jsonb_build_object('p','R2 la misma propuesta dos veces','esperado','RECHAZA · 23505','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R2 la misma propuesta dos veces','esperado','RECHAZA · 23505','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23505');
  end;
  begin
    insert into compra_pedido_odoo (propuesta_id, proveedor_id, entrega_dia, po_id, po_nombre, lineas, creado_por) values (v_p2, 948, date '2026-10-12', -1, 'P-ENSAYO-1', '[{"producto_id":464,"pedido":50}]', v_socia);
    v_res := v_res || jsonb_build_object('p','R3 la misma orden de Odoo dos veces','esperado','RECHAZA · 23505','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R3 la misma orden de Odoo dos veces','esperado','RECHAZA · 23505','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23505');
  end;
  begin
    insert into compra_pedido_odoo (propuesta_id, proveedor_id, entrega_dia, po_id, po_nombre, lineas, creado_por) values (v_p2, 948, date '2026-10-05', -4, 'P-ENSAYO-4', '[{"producto_id":464,"pedido":50}]', v_socia);
    v_res := v_res || jsonb_build_object('p','R4 mismo proveedor y misma entrega','esperado','RECHAZA · 23505','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R4 mismo proveedor y misma entrega','esperado','RECHAZA · 23505','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23505');
  end;
  begin
    insert into compra_pedido_odoo (propuesta_id, proveedor_id, entrega_dia, po_id, po_nombre, lineas, creado_por) values (-999, 948, date '2026-10-26', -5, 'P-ENSAYO-5', '[{"producto_id":464,"pedido":50}]', v_socia);
    v_res := v_res || jsonb_build_object('p','R5 propuesta que no existe','esperado','RECHAZA · 23503','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R5 propuesta que no existe','esperado','RECHAZA · 23503','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23503');
  end;
  begin
    insert into compra_pedido_odoo (propuesta_id, proveedor_id, entrega_dia, po_id, po_nombre, lineas, creado_por) values (v_p2, 948, date '2026-10-12', -6, 'P-ENSAYO-6', '[{"producto_id":464,"pedido":50}]', 'otra@persona.com');
    v_res := v_res || jsonb_build_object('p','R6 registra con OTRO nombre','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R6 registra con OTRO nombre','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into compra_pedido_odoo (propuesta_id, proveedor_id, entrega_dia, po_id, po_nombre, lineas, creado_por) values (v_p2, 948, date '2026-10-12', -7, 'P-ENSAYO-7', '[]', v_socia);
    v_res := v_res || jsonb_build_object('p','R7 orden sin líneas','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R7 orden sin líneas','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    update compra_propuesta set lineas = '[{"producto_id":464,"pedido":500}]' where id = v_p1;
    v_res := v_res || jsonb_build_object('p','U1 la socia EDITA una propuesta','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','U1 la socia EDITA una propuesta','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    delete from compra_pedido_odoo where propuesta_id = v_p1;
    v_res := v_res || jsonb_build_object('p','U2 la socia BORRA el rastro','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','U2 la socia BORRA el rastro','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── equipo ──
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  begin
    insert into compra_propuesta (proveedor_id, modo, pedido_dia, entrega_dia, lineas, creado_por) values (948, 'pedir', date '2026-10-08', date '2026-10-12', '[{"producto_id":464,"pedido":50}]', v_equipo);
    v_res := v_res || jsonb_build_object('p','E1 alguien de equipo guarda una propuesta','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E1 alguien de equipo guarda una propuesta','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into compra_pedido_odoo (propuesta_id, proveedor_id, entrega_dia, po_id, po_nombre, lineas, creado_por) values (v_p2, 948, date '2026-10-12', -8, 'P-ENSAYO-8', '[{"producto_id":464,"pedido":50}]', v_equipo);
    v_res := v_res || jsonb_build_object('p','E2 alguien de equipo registra una orden','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E2 alguien de equipo registra una orden','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── anon ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
  begin
    select count(*) into v_n from compra_propuesta;
    v_res := v_res || jsonb_build_object('p','A1 anon lee las propuestas','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A1 anon lee las propuestas','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into compra_propuesta (proveedor_id, modo, pedido_dia, entrega_dia, lineas, creado_por) values (948, 'pedir', date '2026-10-08', date '2026-10-12', '[{"producto_id":464,"pedido":50}]', 'anon');
    v_res := v_res || jsonb_build_object('p','A2 anon guarda una propuesta','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A2 anon guarda una propuesta','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── editor SQL ──
  perform set_config('role', 'postgres', true);
  select count(*) into v_n from compra_pedido_odoo where propuesta_id = v_p1 and po_id = -1 and creado_por = v_socia;
  v_res := v_res || jsonb_build_object('p','Z quedó UNA orden registrada, la de la socia, intacta','esperado','1','obtenido',v_n::text,'ok',v_n=1);

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: 21 filas, todas ok = true.

rollback;
