-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_COMPRA_V3_E1.sql  ·  13-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Aplica COMPRA_V3_E1.sql (copia del bloque), lo prueba como socia, equipo y editor, y lo deshace
-- todo (rollback).
-- ⏳ SIN CORRER.
--
-- CÓMO SE LEE: 20 filas, TODAS con ok = true. Un RECHAZA vale solo con su SQLSTATE Y el nombre de SU
-- restricción en el mensaje (no vale rechazar por la de al lado). Si el editor dice "Success. No rows
-- returned", no llegó al final y no vale.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE (copia de COMPRA_V3_E1.sql) ▼▼▼
alter table public.compra_propuesta drop constraint compra_propuesta_modo_check;
alter table public.compra_propuesta add constraint compra_propuesta_modo_check
  check (modo in ('pedir', 'registrar', 'llego'));
alter table public.compra_propuesta add column factura_ref text, add column nota text;
alter table public.compra_propuesta add constraint compra_propuesta_factura_ref
  check (factura_ref is null or factura_ref ~ '^[0-9]{20}$');
alter table public.compra_propuesta add constraint compra_propuesta_llego_fe
  check (modo <> 'llego' or factura_ref is not null);
alter table public.compra_propuesta add constraint compra_propuesta_llego_dia
  check (modo <> 'llego' or pedido_dia = entrega_dia);
alter table public.compra_propuesta add constraint compra_propuesta_nota
  check (nota is null or length(btrim(nota)) between 1 and 500);

alter table public.compra_pedido_odoo add column factura_ref text;
alter table public.compra_pedido_odoo add constraint compra_pedido_odoo_factura_ref
  check (factura_ref is null or factura_ref ~ '^[0-9]{20}$');
-- Una FE de un proveedor se registra UNA vez desde Truefie.
create unique index compra_pedido_odoo_fe_un on public.compra_pedido_odoo (proveedor_id, factura_ref)
  where factura_ref is not null;
-- ▲▲▲ FIN BLOQUE ▲▲▲

do $$
declare
  v_socia text; v_equipo text; v_n bigint; v_p1 bigint; v_p2 bigint; v_p3 bigint; v_antes bigint;
  v_res jsonb := '[]'::jsonb;
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by id limit 1;
  select email into v_equipo from v_acceso_usuario where perfil = 'equipo' and activo order by id limit 1;
  if v_socia is null or v_equipo is null then
    raise exception 'el ensayo necesita una socia y alguien de equipo (socia %, equipo %)', v_socia, v_equipo;
  end if;

  select count(*) into v_antes from compra_propuesta;   -- las viejas, contadas antes de tocar nada
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into compra_propuesta (proveedor_id, proveedor, modo, pedido_dia, entrega_dia, lineas, creado_por, factura_ref, nota) values (1183, 'Maryanto', 'llego', date '2026-10-08', date '2026-10-08', '[{"producto_id": 526, "pedido": 20}]'::jsonb, v_socia, '00100001010000008144', 'Entregado el 8-oct · cacao lote 1/10/2026, vence 1/10/2027') returning id into v_p1;
    v_res := v_res || jsonb_build_object('p','P1 «ya llegó» con su FE y nota (la 8144)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P1 «ya llegó» con su FE y nota (la 8144)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into compra_propuesta (proveedor_id, proveedor, modo, pedido_dia, entrega_dia, lineas, creado_por) values (1183, 'Maryanto', 'pedir', current_date, current_date + 7, '[{"producto_id": 526, "pedido": 20}]'::jsonb, v_socia) returning id into v_p2;
    v_res := v_res || jsonb_build_object('p','P2 la pantalla vieja (sin las columnas nuevas) sigue guardando','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P2 la pantalla vieja (sin las columnas nuevas) sigue guardando','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into compra_propuesta (proveedor_id, proveedor, modo, pedido_dia, entrega_dia, lineas, creado_por, factura_ref, nota) values (1183, 'Maryanto', 'pedir', current_date, current_date + 7, '[{"producto_id": 526, "pedido": 20}]'::jsonb, v_socia, null, 'llamar antes') returning id into v_p3;
    v_res := v_res || jsonb_build_object('p','P3 «pedir» con nota y sin FE','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P3 «pedir» con nota y sin FE','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into compra_propuesta (proveedor_id, proveedor, modo, pedido_dia, entrega_dia, lineas, creado_por, factura_ref, nota) values (1183, 'Maryanto', 'llego', date '2026-10-08', date '2026-10-08', '[{"producto_id": 526, "pedido": 20}]'::jsonb, v_socia, null, null);
    v_res := v_res || jsonb_build_object('p','P4 «ya llegó» sin FE','esperado','RECHAZA · 23514 · compra_propuesta_llego_fe','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P4 «ya llegó» sin FE','esperado','RECHAZA · 23514 · compra_propuesta_llego_fe','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514' and sqlerrm like '%compra_propuesta_llego_fe%');
  end;
  begin
    insert into compra_propuesta (proveedor_id, proveedor, modo, pedido_dia, entrega_dia, lineas, creado_por, factura_ref, nota) values (1183, 'Maryanto', 'llego', date '2026-10-08', date '2026-10-08', '[{"producto_id": 526, "pedido": 20}]'::jsonb, v_socia, '0010000101000000814', null);
    v_res := v_res || jsonb_build_object('p','P5 FE de 19 dígitos','esperado','RECHAZA · 23514 · compra_propuesta_factura_ref','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P5 FE de 19 dígitos','esperado','RECHAZA · 23514 · compra_propuesta_factura_ref','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514' and sqlerrm like '%compra_propuesta_factura_ref%');
  end;
  begin
    insert into compra_propuesta (proveedor_id, proveedor, modo, pedido_dia, entrega_dia, lineas, creado_por, factura_ref, nota) values (1183, 'Maryanto', 'llego', date '2026-10-08', date '2026-10-08', '[{"producto_id": 526, "pedido": 20}]'::jsonb, v_socia, '0010000101000000814X', null);
    v_res := v_res || jsonb_build_object('p','P6 FE con letras','esperado','RECHAZA · 23514 · compra_propuesta_factura_ref','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P6 FE con letras','esperado','RECHAZA · 23514 · compra_propuesta_factura_ref','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514' and sqlerrm like '%compra_propuesta_factura_ref%');
  end;
  begin
    insert into compra_propuesta (proveedor_id, proveedor, modo, pedido_dia, entrega_dia, lineas, creado_por, factura_ref, nota) values (1183, 'Maryanto', 'llego', date '2026-10-07', date '2026-10-08', '[{"producto_id": 526, "pedido": 20}]'::jsonb, v_socia, '00100001010000008144', null);
    v_res := v_res || jsonb_build_object('p','P7 «ya llegó» con pedido ≠ entrega','esperado','RECHAZA · 23514 · compra_propuesta_llego_dia','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P7 «ya llegó» con pedido ≠ entrega','esperado','RECHAZA · 23514 · compra_propuesta_llego_dia','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514' and sqlerrm like '%compra_propuesta_llego_dia%');
  end;
  begin
    insert into compra_propuesta (proveedor_id, proveedor, modo, pedido_dia, entrega_dia, lineas, creado_por, factura_ref, nota) values (1183, 'Maryanto', 'regalar', date '2026-10-08', date '2026-10-08', '[{"producto_id": 526, "pedido": 20}]'::jsonb, v_socia, '00100001010000008144', null);
    v_res := v_res || jsonb_build_object('p','P8 modo inventado','esperado','RECHAZA · 23514 · compra_propuesta_modo_check','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P8 modo inventado','esperado','RECHAZA · 23514 · compra_propuesta_modo_check','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514' and sqlerrm like '%compra_propuesta_modo_check%');
  end;
  begin
    insert into compra_propuesta (proveedor_id, proveedor, modo, pedido_dia, entrega_dia, lineas, creado_por, factura_ref, nota) values (1183, 'Maryanto', 'llego', date '2026-10-08', date '2026-10-08', '[{"producto_id": 526, "pedido": 20}]'::jsonb, v_socia, '00100001010000008144', '   ');
    v_res := v_res || jsonb_build_object('p','P9 nota vacía','esperado','RECHAZA · 23514 · compra_propuesta_nota','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P9 nota vacía','esperado','RECHAZA · 23514 · compra_propuesta_nota','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514' and sqlerrm like '%compra_propuesta_nota%');
  end;
  begin
    insert into compra_propuesta (proveedor_id, proveedor, modo, pedido_dia, entrega_dia, lineas, creado_por, factura_ref, nota) values (1183, 'Maryanto', 'llego', date '2026-10-08', date '2026-10-08', '[{"producto_id": 526, "pedido": 20}]'::jsonb, v_socia, '00100001010000008144', repeat('x', 501));
    v_res := v_res || jsonb_build_object('p','P10 nota de 501 letras','esperado','RECHAZA · 23514 · compra_propuesta_nota','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P10 nota de 501 letras','esperado','RECHAZA · 23514 · compra_propuesta_nota','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514' and sqlerrm like '%compra_propuesta_nota%');
  end;
  begin
    insert into compra_propuesta (proveedor_id, proveedor, modo, pedido_dia, entrega_dia, lineas, creado_por, factura_ref, nota) values (1183, 'Maryanto', 'llego', date '2026-10-08', date '2026-10-08', '[{"producto_id": 526, "pedido": 20}]'::jsonb, 'otra@persona.com', '00100001010000008144', null);
    v_res := v_res || jsonb_build_object('p','P11 la socia firma con OTRO nombre','esperado','RECHAZA · 42501 · row-level security','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P11 la socia firma con OTRO nombre','esperado','RECHAZA · 42501 · row-level security','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501' and sqlerrm like '%row-level security%');
  end;
  begin
    insert into compra_pedido_odoo (propuesta_id, proveedor_id, entrega_dia, po_id, po_nombre, lineas, creado_por, factura_ref) values (v_p1, 1183, date '2026-10-08', 99001, 'P9' || 99001, '[{"producto_id": 526, "pedido": 20}]'::jsonb, v_socia, '00100001010000008144');
    v_res := v_res || jsonb_build_object('p','R1 rastro de la 8144 con su FE','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R1 rastro de la 8144 con su FE','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into compra_pedido_odoo (propuesta_id, proveedor_id, entrega_dia, po_id, po_nombre, lineas, creado_por, factura_ref) values (v_p3, 1183, date '2026-10-09', 99002, 'P9' || 99002, '[{"producto_id": 526, "pedido": 20}]'::jsonb, v_socia, '00100001010000008144');
    v_res := v_res || jsonb_build_object('p','R2 la MISMA FE del mismo proveedor otra vez','esperado','RECHAZA · 23505 · compra_pedido_odoo_fe_un','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R2 la MISMA FE del mismo proveedor otra vez','esperado','RECHAZA · 23505 · compra_pedido_odoo_fe_un','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23505' and sqlerrm like '%compra_pedido_odoo_fe_un%');
  end;
  begin
    insert into compra_pedido_odoo (propuesta_id, proveedor_id, entrega_dia, po_id, po_nombre, lineas, creado_por, factura_ref) values (v_p3, 948, date '2026-10-09', 99003, 'P9' || 99003, '[{"producto_id": 526, "pedido": 20}]'::jsonb, v_socia, '00100001010000008144');
    v_res := v_res || jsonb_build_object('p','R3 la misma FE pero de OTRO proveedor','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R3 la misma FE pero de OTRO proveedor','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into compra_pedido_odoo (propuesta_id, proveedor_id, entrega_dia, po_id, po_nombre, lineas, creado_por, factura_ref) values (v_p2, 1183, date '2026-10-20', 99004, 'P9' || 99004, '[{"producto_id": 526, "pedido": 20}]'::jsonb, v_socia, null);
    v_res := v_res || jsonb_build_object('p','R4 rastros sin FE no chocan entre sí','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R4 rastros sin FE no chocan entre sí','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into compra_pedido_odoo (propuesta_id, proveedor_id, entrega_dia, po_id, po_nombre, lineas, creado_por, factura_ref) values (v_p2, 1183, date '2026-10-21', 99005, 'P9' || 99005, '[{"producto_id": 526, "pedido": 20}]'::jsonb, v_socia, '8144');
    v_res := v_res || jsonb_build_object('p','R5 FE mal formada en el rastro','esperado','RECHAZA · 23514 · compra_pedido_odoo_factura_ref','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R5 FE mal formada en el rastro','esperado','RECHAZA · 23514 · compra_pedido_odoo_factura_ref','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514' and sqlerrm like '%compra_pedido_odoo_factura_ref%');
  end;
  begin
    update compra_propuesta set factura_ref = null where id = v_p1;
    v_res := v_res || jsonb_build_object('p','U1 la socia EDITA una propuesta','esperado','RECHAZA · 42501 · permission denied','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','U1 la socia EDITA una propuesta','esperado','RECHAZA · 42501 · permission denied','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501' and sqlerrm like '%permission denied%');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  begin
    insert into compra_propuesta (proveedor_id, proveedor, modo, pedido_dia, entrega_dia, lineas, creado_por, factura_ref, nota) values (1183, 'Maryanto', 'llego', date '2026-10-08', date '2026-10-08', '[{"producto_id": 526, "pedido": 20}]'::jsonb, v_equipo, '00100001010000008144', null);
    v_res := v_res || jsonb_build_object('p','E1 alguien de equipo propone una compra','esperado','RECHAZA · 42501 · row-level security','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E1 alguien de equipo propone una compra','esperado','RECHAZA · 42501 · row-level security','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501' and sqlerrm like '%row-level security%');
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into v_n from compra_propuesta where id in (v_p1, v_p2, v_p3);
  v_res := v_res || jsonb_build_object('p','Z1 quedaron las 3 propuestas que entraron','esperado','3','obtenido',v_n::text,'ok',v_n=3);
  select count(*) into v_n from compra_propuesta where id < v_p1;
  v_res := v_res || jsonb_build_object('p','Z2 las propuestas viejas, intactas','esperado',v_antes::text,'obtenido',v_n::text,'ok',v_n=v_antes);

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: 20 filas, todas ok = true.

rollback;
