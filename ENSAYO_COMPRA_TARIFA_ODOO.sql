-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_COMPRA_TARIFA_ODOO.sql  ·  12-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Prueba la tabla de COMPRA_TARIFA_ODOO.sql (el rastro de las tarifas de BIO) y lo deshace
-- todo (rollback).
--
-- CÓMO SE LEE
--   Una tabla de 18 filas, TODAS con ok = true. Un RECHAZA da ok solo si el SQLSTATE
--   esperado está en `obtenido` (no vale rechazar por el motivo de al lado). Si el
--   editor dice "Success. No rows returned", no llegó al final y no vale.
--   42501 = RLS o sin permiso · 23514 = check · 23505 = único.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE DDL (copia de COMPRA_TARIFA_ODOO.sql) ▼▼▼
create table public.compra_tarifa_odoo (
  id               bigint generated always as identity primary key,
  motivo           text not null check (motivo in ('correccion_inicial', 'factura_nueva')),
  proveedor_id     integer not null check (proveedor_id > 0),
  supplierinfo_id  integer not null check (supplierinfo_id > 0),     -- la tarifa en Odoo
  producto_tmpl_id integer not null check (producto_tmpl_id > 0),
  producto         text not null check (length(btrim(producto)) > 0),
  unidad           text,                                             -- la de compra del insumo (kg)
  precio_antes     numeric(14,4) not null check (precio_antes > 0),
  precio_nuevo     numeric(14,4) not null check (precio_nuevo > 0),
  factura_id       integer not null check (factura_id > 0),          -- la factura de BIO testigo
  factura_nombre   text not null check (length(btrim(factura_nombre)) > 0),
  factura_fecha    date,
  linea_id         integer not null check (linea_id > 0),            -- su línea (account.move.line)
  huella           text not null check (length(huella) between 1 and 64),   -- la de la vista previa
  creado_por       text not null,
  creado_en        timestamptz not null default now(),
  constraint compra_tarifa_odoo_cambia check (precio_nuevo <> precio_antes),
  constraint compra_tarifa_odoo_banda check (precio_nuevo between precio_antes * 0.5 and precio_antes * 2)
);
-- La corrección inicial, una sola vez por tarifa.
create unique index compra_tarifa_odoo_inicial_un on public.compra_tarifa_odoo (supplierinfo_id)
  where motivo = 'correccion_inicial';

alter table public.compra_tarifa_odoo enable row level security;
revoke all on public.compra_tarifa_odoo from anon, authenticated;
grant select, insert on public.compra_tarifa_odoo to authenticated;

create policy compra_tarifa_odoo_sel on public.compra_tarifa_odoo
  for select to authenticated using (acceso_es_socia());
create policy compra_tarifa_odoo_ins on public.compra_tarifa_odoo
  for insert to authenticated
  with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

do $$
declare
  v_socia text; v_equipo text; v_n int;
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
    insert into compra_tarifa_odoo (motivo, proveedor_id, supplierinfo_id, producto_tmpl_id, producto, unidad, precio_antes, precio_nuevo, factura_id, factura_nombre, factura_fecha, linea_id, huella, creado_por) values ('correccion_inicial', 948, 2, 61, 'Almidon de Maiz', 'kg', 594.63, 470, 1, '2579', date '2026-10-05', 1, 'f279358d96e2953f', v_socia);
    v_res := v_res || jsonb_build_object('p','T1 la socia registra la corrección inicial con SU nombre','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T1 la socia registra la corrección inicial con SU nombre','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into compra_tarifa_odoo (motivo, proveedor_id, supplierinfo_id, producto_tmpl_id, producto, unidad, precio_antes, precio_nuevo, factura_id, factura_nombre, factura_fecha, linea_id, huella, creado_por) values ('correccion_inicial', 948, 3, 61, 'Almidon de Maiz', 'kg', 891.94, 890, 1, '2579', date '2026-10-05', 1, 'f279358d96e2953f', 'otra@persona.com');
    v_res := v_res || jsonb_build_object('p','T2 la socia firma con OTRO nombre','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T2 la socia firma con OTRO nombre','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into compra_tarifa_odoo (motivo, proveedor_id, supplierinfo_id, producto_tmpl_id, producto, unidad, precio_antes, precio_nuevo, factura_id, factura_nombre, factura_fecha, linea_id, huella, creado_por) values ('a_mano', 948, 3, 61, 'Almidon de Maiz', 'kg', 891.94, 890, 1, '2579', date '2026-10-05', 1, 'f279358d96e2953f', v_socia);
    v_res := v_res || jsonb_build_object('p','T3 motivo inventado','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T3 motivo inventado','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into compra_tarifa_odoo (motivo, proveedor_id, supplierinfo_id, producto_tmpl_id, producto, unidad, precio_antes, precio_nuevo, factura_id, factura_nombre, factura_fecha, linea_id, huella, creado_por) values ('correccion_inicial', 948, 3, 61, 'Almidon de Maiz', 'kg', 891.94, 891.94, 1, '2579', date '2026-10-05', 1, 'f279358d96e2953f', v_socia);
    v_res := v_res || jsonb_build_object('p','T4 precio nuevo igual al de antes','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T4 precio nuevo igual al de antes','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into compra_tarifa_odoo (motivo, proveedor_id, supplierinfo_id, producto_tmpl_id, producto, unidad, precio_antes, precio_nuevo, factura_id, factura_nombre, factura_fecha, linea_id, huella, creado_por) values ('correccion_inicial', 948, 20, 61, 'linaza', 'kg', 1750, 700, 1, '2579', date '2026-10-05', 1, 'f279358d96e2953f', v_socia);
    v_res := v_res || jsonb_build_object('p','T5 fuera de banda: 0,40× (linaza 1.750 → 700)','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T5 fuera de banda: 0,40× (linaza 1.750 → 700)','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into compra_tarifa_odoo (motivo, proveedor_id, supplierinfo_id, producto_tmpl_id, producto, unidad, precio_antes, precio_nuevo, factura_id, factura_nombre, factura_fecha, linea_id, huella, creado_por) values ('correccion_inicial', 948, 8, 61, 'Sal', 'kg', 396, 990, 1, '2579', date '2026-10-05', 1, 'f279358d96e2953f', v_socia);
    v_res := v_res || jsonb_build_object('p','T6 fuera de banda: 2,5× (sal 396 → 990)','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T6 fuera de banda: 2,5× (sal 396 → 990)','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into compra_tarifa_odoo (motivo, proveedor_id, supplierinfo_id, producto_tmpl_id, producto, unidad, precio_antes, precio_nuevo, factura_id, factura_nombre, factura_fecha, linea_id, huella, creado_por) values ('correccion_inicial', 948, 3, 61, 'Almidon de Maiz', 'kg', 891.94, 0, 1, '2579', date '2026-10-05', 1, 'f279358d96e2953f', v_socia);
    v_res := v_res || jsonb_build_object('p','T7 precio nuevo en cero','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T7 precio nuevo en cero','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into compra_tarifa_odoo (motivo, proveedor_id, supplierinfo_id, producto_tmpl_id, producto, unidad, precio_antes, precio_nuevo, factura_id, factura_nombre, factura_fecha, linea_id, huella, creado_por) values ('correccion_inicial', 948, 2, 61, 'Almidon de Maiz', 'kg', 594.63, 480, 1, '2579', date '2026-10-05', 1, 'f279358d96e2953f', v_socia);
    v_res := v_res || jsonb_build_object('p','T8 la MISMA tarifa con corrección inicial dos veces','esperado','RECHAZA · 23505','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T8 la MISMA tarifa con corrección inicial dos veces','esperado','RECHAZA · 23505','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23505');
  end;
  begin
    insert into compra_tarifa_odoo (motivo, proveedor_id, supplierinfo_id, producto_tmpl_id, producto, unidad, precio_antes, precio_nuevo, factura_id, factura_nombre, factura_fecha, linea_id, huella, creado_por) values ('factura_nueva', 948, 2, 61, 'Almidon de Maiz', 'kg', 470, 480, 1, '2579', date '2026-10-05', 1, 'f279358d96e2953f', v_socia);
    v_res := v_res || jsonb_build_object('p','T9 la misma tarifa después, por factura_nueva','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T9 la misma tarifa después, por factura_nueva','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into compra_tarifa_odoo (motivo, proveedor_id, supplierinfo_id, producto_tmpl_id, producto, unidad, precio_antes, precio_nuevo, factura_id, factura_nombre, factura_fecha, linea_id, huella, creado_por) values ('correccion_inicial', 948, 3, 61, 'Almidon de Maiz', 'kg', 891.94, 890, 1, '2579', date '2026-10-05', 1, '', v_socia);
    v_res := v_res || jsonb_build_object('p','T10 sin huella','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T10 sin huella','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into compra_tarifa_odoo (motivo, proveedor_id, supplierinfo_id, producto_tmpl_id, producto, unidad, precio_antes, precio_nuevo, factura_id, factura_nombre, factura_fecha, linea_id, huella, creado_por) values ('correccion_inicial', 948, 3, 61, '  ', 'kg', 891.94, 890, 1, '2579', date '2026-10-05', 1, 'f279358d96e2953f', v_socia);
    v_res := v_res || jsonb_build_object('p','T11 producto en blanco','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T11 producto en blanco','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    update compra_tarifa_odoo set precio_nuevo = 1 where supplierinfo_id = 2;
    v_res := v_res || jsonb_build_object('p','U1 la socia EDITA el rastro','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','U1 la socia EDITA el rastro','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    delete from compra_tarifa_odoo where supplierinfo_id = 2;
    v_res := v_res || jsonb_build_object('p','U2 la socia BORRA el rastro','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','U2 la socia BORRA el rastro','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── equipo ──
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  begin
    insert into compra_tarifa_odoo (motivo, proveedor_id, supplierinfo_id, producto_tmpl_id, producto, unidad, precio_antes, precio_nuevo, factura_id, factura_nombre, factura_fecha, linea_id, huella, creado_por) values ('correccion_inicial', 948, 3, 61, 'Almidon de Maiz', 'kg', 891.94, 890, 1, '2579', date '2026-10-05', 1, 'f279358d96e2953f', v_equipo);
    v_res := v_res || jsonb_build_object('p','E1 alguien de equipo registra una tarifa','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E1 alguien de equipo registra una tarifa','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  select count(*) into v_n from compra_tarifa_odoo;
  v_res := v_res || jsonb_build_object('p','E2 alguien de equipo NO ve el rastro (precios de compra)','esperado','0','obtenido',v_n::text,'ok',v_n=0);

  -- ── anon ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
  begin
    select count(*) into v_n from compra_tarifa_odoo;
    v_res := v_res || jsonb_build_object('p','A1 anon lee el rastro','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A1 anon lee el rastro','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into compra_tarifa_odoo (motivo, proveedor_id, supplierinfo_id, producto_tmpl_id, producto, unidad, precio_antes, precio_nuevo, factura_id, factura_nombre, factura_fecha, linea_id, huella, creado_por) values ('correccion_inicial', 948, 3, 61, 'Almidon de Maiz', 'kg', 891.94, 890, 1, '2579', date '2026-10-05', 1, 'f279358d96e2953f', 'anon');
    v_res := v_res || jsonb_build_object('p','A2 anon registra una tarifa','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A2 anon registra una tarifa','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── editor SQL ──
  perform set_config('role', 'postgres', true);
  select count(*) into v_n from compra_tarifa_odoo where supplierinfo_id = 2 and creado_por = v_socia;
  v_res := v_res || jsonb_build_object('p','Z quedaron 2 filas, las de la socia (T1 y T9), intactas','esperado','2','obtenido',v_n::text,'ok',v_n=2);

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: 18 filas, todas ok = true.

rollback;
