-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_ENCENDER_INSUMO_ASISTENTE.sql  ·  19-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA (termina en rollback)
-- Prueba el encendido de 'crear_insumo' (PEGADO_ENCENDER_INSUMO_ASISTENTE.sql, local) y su apagado.
-- ✅ CORRIDO el 19-oct-2026 por Andrea en producción: 12 de 12 ok = true, cada RECHAZA con 42501 por RLS.
--    VERIFICADO desde afuera: el rollback no dejó nada (permiso vacío, sin propuestas «Ensayo», 0 vistas previas).
-- Los correos salen de la base (v_acceso_usuario), no de este archivo.
--
-- CÓMO SE LEE: 12 filas, TODAS ok = true. Un RECHAZA vale solo con su SQLSTATE (42501 = RLS o permiso).
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$
declare
  v_socia text; v_equipo text; v_asis text; v_p bigint; v_x bigint; v_b boolean;
  v_res jsonb := '[]'::jsonb;
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by id limit 1;
  select email into v_equipo from v_acceso_usuario where perfil not in ('socias', 'asistente') and activo order by id limit 1;
  select email into v_asis   from v_acceso_usuario where perfil = 'asistente' and activo order by id limit 1;
  if v_socia is null or v_equipo is null or v_asis is null then
    raise exception 'el ensayo necesita una socia, alguien de equipo y el asistente (%, %, %)', v_socia, v_equipo, v_asis;
  end if;
  if coalesce((select p.encendido from asistente_permiso p where p.capacidad = 'crear_insumo'
                order by p.creado_en desc, p.id desc limit 1), false) then
    raise exception 'crear_insumo ya está encendido: el ensayo no tiene sentido';
  end if;

  -- ── lo mismo que el pegado ──
  insert into asistente_permiso (capacidad, encendido, motivo, creado_por)
  values ('crear_insumo', true, 'Fase 2: Instinct crea insumos con «sí + código». Decisión de Andrea, 19-oct-2026.', v_socia);

  -- ── Instinct ──
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  v_b := asistente_puede('crear_insumo');
  v_res := v_res || jsonb_build_object('p','E1 Instinct PUEDE crear insumos','esperado','true','obtenido',v_b::text,'ok',v_b is true);
  v_b := asistente_puede('facturar');
  v_res := v_res || jsonb_build_object('p','E2 Instinct NO puede otra capacidad (facturar)','esperado','false','obtenido',v_b::text,'ok',v_b is false);
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por)
    values ('Ensayo Encender', 12, 15, '2363000000000', 1183, 1000, null, '00000000000000000001', v_asis) returning id into v_p;
    v_res := v_res || jsonb_build_object('p','E3 Instinct propone un insumo con SU correo','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E3 Instinct propone un insumo con SU correo','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into asistente_vista_previa (id, accion, propuesta_id, huella, codigo, creado_por)
    values (gen_random_uuid(), 'crear_insumo', v_p, 'eb2df9d55fa4451b', '4821', v_asis);
    v_res := v_res || jsonb_build_object('p','E4 Instinct anota la vista previa de SU propuesta','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E4 Instinct anota la vista previa de SU propuesta','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por)
    values ('Ensayo Firma', 12, 15, '2363000000000', 1183, 1000, null, '00000000000000000001', v_socia);
    v_res := v_res || jsonb_build_object('p','E5 Instinct propone firmando como la socia','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E5 Instinct propone firmando como la socia','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into compra_insumo_odoo (propuesta_id, producto_tmpl_id, nombre, huella, creado_por, hecho_por_asistente)
    values (v_p, 905, 'Ensayo Encender', 'eb2df9d55fa4451b', v_asis, false);
    v_res := v_res || jsonb_build_object('p','E6 Instinct deja un rastro SIN vista previa ni código','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E6 Instinct deja un rastro SIN vista previa ni código','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_pedido default values;
    v_res := v_res || jsonb_build_object('p','E7 Instinct sigue sin escribir en otras tablas (ent_pedido)','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E7 Instinct sigue sin escribir en otras tablas (ent_pedido)','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into asistente_permiso (capacidad, encendido, motivo, creado_por) values ('facturar', true, 'ensayo', v_asis);
    v_res := v_res || jsonb_build_object('p','E8 Instinct se enciende otra capacidad','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E8 Instinct se enciende otra capacidad','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── alguien de equipo ──
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  v_b := asistente_puede('crear_insumo');
  v_res := v_res || jsonb_build_object('p','E9 alguien de equipo NO puede (no es el asistente)','esperado','false','obtenido',v_b::text,'ok',v_b is false);
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por)
    values ('Ensayo Equipo', 12, 15, '2363000000000', 1183, 1000, null, '00000000000000000001', v_equipo);
    v_res := v_res || jsonb_build_object('p','E10 alguien de equipo propone un insumo','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E10 alguien de equipo propone un insumo','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── lo mismo que el APAGADO, y otra vez Instinct ──
  perform set_config('role', 'postgres', true);
  insert into asistente_permiso (capacidad, encendido, motivo, creado_por) values ('crear_insumo', false, 'Apagado por decisión de Andrea.', v_socia);
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  v_b := asistente_puede('crear_insumo');
  v_res := v_res || jsonb_build_object('p','E11 apagado: Instinct ya NO puede crear insumos','esperado','false','obtenido',v_b::text,'ok',v_b is false);
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por)
    values ('Ensayo Apagado', 12, 15, '2363000000000', 1183, 1000, null, '00000000000000000001', v_asis);
    v_res := v_res || jsonb_build_object('p','E12 apagado: Instinct propone un insumo','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E12 apagado: Instinct propone un insumo','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  perform set_config('role', 'postgres', true);
  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: 12 filas, todas ok = true.

rollback;
