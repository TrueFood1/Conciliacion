-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_COMPRA_INSUMO_ODOO.sql  ·  13-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Prueba las dos tablas de COMPRA_INSUMO_ODOO.sql (propuestas de insumo nuevo y su rastro) y lo
-- deshace todo (rollback).
-- ⏳ SIN CORRER.
--
-- CÓMO SE LEE
--   Una tabla de 34 filas, TODAS con ok = true. Un RECHAZA da ok solo si el SQLSTATE
--   esperado está en `obtenido` (no vale rechazar por el motivo de al lado). Si el
--   editor dice "Success. No rows returned", no llegó al final y no vale.
--   42501 = RLS o sin permiso · 23514 = check · 23505 = único · 23503 = clave foránea · 23502 = nulo.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE DDL (copia de COMPRA_INSUMO_ODOO.sql) ▼▼▼
create table public.compra_insumo_propuesta (
  id               bigint generated always as identity primary key,
  nombre           text not null check (nombre = btrim(nombre) and length(nombre) between 1 and 60),
  uom_id           integer not null check (uom_id in (12, 13, 10, 24)),        -- kg · g · L · gal (EE. UU.)
  iva_compra_id    integer not null check (iva_compra_id in (15, 21)),         -- 1 % · 13 % (el de la factura)
  cabys            text not null check (cabys ~ '^[0-9]{13}$'),
  proveedor_id     integer not null check (proveedor_id > 0),                  -- res.partner en Odoo
  precio           numeric(14,4) not null check (precio > 0),                  -- sin IVA, CRC, por unidad de compra
  codigo_proveedor text check (codigo_proveedor is null or (codigo_proveedor = btrim(codigo_proveedor)
                                                             and length(codigo_proveedor) between 1 and 30)),
  factura_ref      text not null check (factura_ref ~ '^[0-9]{20}$'),          -- consecutivo de la FE testigo
  nota             text,
  creado_por       text not null,
  creado_en        timestamptz not null default now()
);

create table public.compra_insumo_odoo (
  id               bigint generated always as identity primary key,
  propuesta_id     bigint not null unique references public.compra_insumo_propuesta (id),
  producto_tmpl_id integer not null unique check (producto_tmpl_id > 0),       -- product.template en Odoo
  producto_id      integer check (producto_id is null or producto_id > 0),     -- su variante (product.product)
  supplierinfo_id  integer check (supplierinfo_id is null or supplierinfo_id > 0),   -- su tarifa
  nombre           text not null check (length(btrim(nombre)) > 0),
  huella           text not null check (length(huella) between 1 and 64),      -- la de la vista previa
  creado_por       text not null,
  creado_en        timestamptz not null default now()
);

alter table public.compra_insumo_propuesta enable row level security;
alter table public.compra_insumo_odoo enable row level security;
revoke all on public.compra_insumo_propuesta, public.compra_insumo_odoo from anon, authenticated;
grant select, insert on public.compra_insumo_propuesta, public.compra_insumo_odoo to authenticated;

create policy compra_insumo_propuesta_sel on public.compra_insumo_propuesta
  for select to authenticated using (acceso_es_socia());
create policy compra_insumo_propuesta_ins on public.compra_insumo_propuesta
  for insert to authenticated with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));
create policy compra_insumo_propuesta_sel_asistente on public.compra_insumo_propuesta
  for select to authenticated using ((select public.acceso_es_asistente()));

create policy compra_insumo_odoo_sel on public.compra_insumo_odoo
  for select to authenticated using (acceso_es_socia());
create policy compra_insumo_odoo_ins on public.compra_insumo_odoo
  for insert to authenticated with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));
create policy compra_insumo_odoo_sel_asistente on public.compra_insumo_odoo
  for select to authenticated using ((select public.acceso_es_asistente()));
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

do $$
declare
  v_socia text; v_equipo text; v_n int; v_p1 bigint; v_p2 bigint;
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
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Cacao en Polvo', 12, 15, '2363000000000', 1183, 8910.89, '2292', '00100001010000008144', v_socia) returning id into v_p1;
    v_res := v_res || jsonb_build_object('p','P1 la socia propone el cacao con SU nombre','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P1 la socia propone el cacao con SU nombre','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Cacao en Polvo', 12, 15, '2363000000000', 1183, 8910.89, '2292', '00100001010000008144', 'otra@persona.com');
    v_res := v_res || jsonb_build_object('p','P2 la socia firma con OTRO nombre','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P2 la socia firma con OTRO nombre','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Cacao en Polvo', 12, 15, '236300000000', 1183, 8910.89, '2292', '00100001010000008144', v_socia);
    v_res := v_res || jsonb_build_object('p','P3 Cabys de 12 dígitos','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P3 Cabys de 12 dígitos','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Cacao en Polvo', 12, 15, '23630000000AB', 1183, 8910.89, '2292', '00100001010000008144', v_socia);
    v_res := v_res || jsonb_build_object('p','P4 Cabys con letras','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P4 Cabys con letras','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Cacao en Polvo', 12, 13, '2363000000000', 1183, 8910.89, '2292', '00100001010000008144', v_socia);
    v_res := v_res || jsonb_build_object('p','P5 IVA [13] (es el de VENTA, no de compra)','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P5 IVA [13] (es el de VENTA, no de compra)','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Cacao en Polvo', 1, 15, '2363000000000', 1183, 8910.89, '2292', '00100001010000008144', v_socia);
    v_res := v_res || jsonb_build_object('p','P6 unidad [1] Unidades','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P6 unidad [1] Unidades','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Cacao en Polvo', 12, 15, '2363000000000', 1183, 0, '2292', '00100001010000008144', v_socia);
    v_res := v_res || jsonb_build_object('p','P7 precio en cero','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P7 precio en cero','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values (' Cacao en Polvo', 12, 15, '2363000000000', 1183, 8910.89, '2292', '00100001010000008144', v_socia);
    v_res := v_res || jsonb_build_object('p','P8 nombre con espacios en los bordes','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P8 nombre con espacios en los bordes','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values (repeat('x', 61), 12, 15, '2363000000000', 1183, 8910.89, '2292', '00100001010000008144', v_socia);
    v_res := v_res || jsonb_build_object('p','P9 nombre de más de 60','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P9 nombre de más de 60','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Cacao en Polvo', 12, 15, '2363000000000', 1183, 8910.89, '2292', '8144', v_socia);
    v_res := v_res || jsonb_build_object('p','P10 factura que no es un consecutivo de 20 dígitos','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P10 factura que no es un consecutivo de 20 dígitos','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Cacao en Polvo', 12, 15, '2363000000000', 1183, 8910.89, '2292', null, v_socia);
    v_res := v_res || jsonb_build_object('p','P11 sin factura testigo','esperado','RECHAZA · 23502','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P11 sin factura testigo','esperado','RECHAZA · 23502','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23502');
  end;
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Cacao en Polvo', 12, 15, '2363000000000', 1183, 8910.89, '', '00100001010000008144', v_socia);
    v_res := v_res || jsonb_build_object('p','P12 código de proveedor vacío (o nada, o texto)','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P12 código de proveedor vacío (o nada, o texto)','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Avena Integral', 24, 21, '2363000000000', 1183, 5000, null, '00100001010000008144', v_socia) returning id into v_p2;
    v_res := v_res || jsonb_build_object('p','P13 otra propuesta, al 13 % en galones y sin código','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P13 otra propuesta, al 13 % en galones y sin código','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into compra_insumo_odoo (propuesta_id, producto_tmpl_id, producto_id, supplierinfo_id, nombre, huella, creado_por) values (v_p1, 900, 5900, 300, 'Cacao en Polvo', 'eb2df9d55fa4451b', v_socia);
    v_res := v_res || jsonb_build_object('p','R1 la socia registra el rastro del cacao','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R1 la socia registra el rastro del cacao','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into compra_insumo_odoo (propuesta_id, producto_tmpl_id, producto_id, supplierinfo_id, nombre, huella, creado_por) values (v_p1, 901, 5900, 300, 'Cacao en Polvo', 'eb2df9d55fa4451b', v_socia);
    v_res := v_res || jsonb_build_object('p','R2 la MISMA propuesta crea otro producto','esperado','RECHAZA · 23505','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R2 la MISMA propuesta crea otro producto','esperado','RECHAZA · 23505','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23505');
  end;
  begin
    insert into compra_insumo_odoo (propuesta_id, producto_tmpl_id, producto_id, supplierinfo_id, nombre, huella, creado_por) values (v_p2, 900, 5900, 300, 'Cacao en Polvo', 'eb2df9d55fa4451b', v_socia);
    v_res := v_res || jsonb_build_object('p','R3 el MISMO producto para otra propuesta','esperado','RECHAZA · 23505','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R3 el MISMO producto para otra propuesta','esperado','RECHAZA · 23505','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23505');
  end;
  begin
    insert into compra_insumo_odoo (propuesta_id, producto_tmpl_id, producto_id, supplierinfo_id, nombre, huella, creado_por) values (999999, 902, 5900, 300, 'Cacao en Polvo', 'eb2df9d55fa4451b', v_socia);
    v_res := v_res || jsonb_build_object('p','R4 rastro de una propuesta que no existe','esperado','RECHAZA · 23503','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R4 rastro de una propuesta que no existe','esperado','RECHAZA · 23503','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23503');
  end;
  begin
    insert into compra_insumo_odoo (propuesta_id, producto_tmpl_id, producto_id, supplierinfo_id, nombre, huella, creado_por) values (v_p2, 903, 5900, 300, 'Cacao en Polvo', 'eb2df9d55fa4451b', 'otra@persona.com');
    v_res := v_res || jsonb_build_object('p','R5 rastro firmado con OTRO nombre','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R5 rastro firmado con OTRO nombre','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into compra_insumo_odoo (propuesta_id, producto_tmpl_id, producto_id, supplierinfo_id, nombre, huella, creado_por) values (v_p2, 904, 5900, 300, 'Cacao en Polvo', '', v_socia);
    v_res := v_res || jsonb_build_object('p','R6 rastro sin huella','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R6 rastro sin huella','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    update compra_insumo_propuesta set precio = 1 where id = v_p1;
    v_res := v_res || jsonb_build_object('p','U1 la socia EDITA una propuesta','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','U1 la socia EDITA una propuesta','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    delete from compra_insumo_propuesta where id = v_p1;
    v_res := v_res || jsonb_build_object('p','U2 la socia BORRA una propuesta','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','U2 la socia BORRA una propuesta','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    update compra_insumo_odoo set producto_tmpl_id = 1 where propuesta_id = v_p1;
    v_res := v_res || jsonb_build_object('p','U3 la socia EDITA el rastro','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','U3 la socia EDITA el rastro','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    delete from compra_insumo_odoo where propuesta_id = v_p1;
    v_res := v_res || jsonb_build_object('p','U4 la socia BORRA el rastro','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','U4 la socia BORRA el rastro','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  select count(*) into v_n from compra_insumo_propuesta;
  v_res := v_res || jsonb_build_object('p','L1 la socia ve las 2 propuestas','esperado','2','obtenido',v_n::text,'ok',v_n=2);

  -- ── equipo ──
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Otra cosa', 12, 15, '2363000000000', 1183, 8910.89, '2292', '00100001010000008144', v_equipo);
    v_res := v_res || jsonb_build_object('p','E1 alguien de equipo propone un insumo','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E1 alguien de equipo propone un insumo','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into compra_insumo_odoo (propuesta_id, producto_tmpl_id, producto_id, supplierinfo_id, nombre, huella, creado_por) values (v_p2, 905, 5900, 300, 'Cacao en Polvo', 'eb2df9d55fa4451b', v_equipo);
    v_res := v_res || jsonb_build_object('p','E2 alguien de equipo registra un rastro','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E2 alguien de equipo registra un rastro','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  select count(*) into v_n from compra_insumo_propuesta;
  v_res := v_res || jsonb_build_object('p','E3 alguien de equipo NO ve las propuestas (precios de compra)','esperado','0','obtenido',v_n::text,'ok',v_n=0);
  select count(*) into v_n from compra_insumo_odoo;
  v_res := v_res || jsonb_build_object('p','E4 alguien de equipo NO ve el rastro','esperado','0','obtenido',v_n::text,'ok',v_n=0);

  -- ── anon ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
  begin
    perform count(*) from compra_insumo_propuesta;
    v_res := v_res || jsonb_build_object('p','A1 anon lee las propuestas','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A1 anon lee las propuestas','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    perform count(*) from compra_insumo_odoo;
    v_res := v_res || jsonb_build_object('p','A2 anon lee el rastro','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A2 anon lee el rastro','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Otra cosa', 12, 15, '2363000000000', 1183, 8910.89, '2292', '00100001010000008144', 'anon');
    v_res := v_res || jsonb_build_object('p','A3 anon propone un insumo','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A3 anon propone un insumo','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── editor SQL ──
  perform set_config('role', 'postgres', true);
  select count(*) into v_n from compra_insumo_propuesta where creado_por = v_socia;
  v_res := v_res || jsonb_build_object('p','Z1 quedaron 2 propuestas, las de la socia, intactas','esperado','2','obtenido',v_n::text,'ok',v_n=2);
  select count(*) into v_n from compra_insumo_odoo where propuesta_id = v_p1 and producto_tmpl_id = 900;
  v_res := v_res || jsonb_build_object('p','Z2 quedó 1 rastro, el del cacao, intacto','esperado','1','obtenido',v_n::text,'ok',v_n=1);
  select count(*) into v_n from pg_policy where polrelid in ('public.compra_insumo_propuesta'::regclass, 'public.compra_insumo_odoo'::regclass) and not polpermissive;
  v_res := v_res || jsonb_build_object('p','Z3 el disparador del asistente les puso sus 8 restrictivas','esperado','8','obtenido',v_n::text,'ok',v_n=8);

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: 34 filas, todas ok = true.

rollback;
