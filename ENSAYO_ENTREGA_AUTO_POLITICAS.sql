-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_ENTREGA_AUTO_POLITICAS.sql  ·  26-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Prueba las tres políticas de ENTREGA_AUTO_POLITICAS.sql con datos inventados
-- dentro de la transacción, y lo deshace TODO (rollback). NO SE CORRIÓ.
--
-- CÓMO SE LEE
--   Una tabla de 19 filas, TODAS con ok = true. Un RECHAZA da ok solo si el
--   SQLSTATE es 42501 («new row violates row-level security policy» o
--   «permission denied for table …»). Si el editor dice "Success. No rows
--   returned", no llegó al final y no vale.
--   Necesita una socia, alguien de «equipo» y el asistente activos en acceso_usuario.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE DDL (el ensayo lo repite byte a byte) ▼▼▼
-- Las tres son PERMISSIVE y se SUMAN a las de socias (que no se tocan): un insert entra si
-- calza con cualquiera de las dos. Las restrictivas del asistente siguen mandando encima.
create policy ent_odoo_validacion_ins_auto on public.ent_odoo_validacion
  for insert to authenticated
  with check (
    acceso_perfil() = 'equipo'
    and validado_por = (auth.jwt() ->> 'email')
    and exists (select 1
                  from public.ent_salida_vigente s
                  join public.ent_alisto_vigente a on a.alisto_id = s.alisto_id
                 where a.pedido_id = ent_odoo_validacion.pedido_id
                   and lower(s.creado_por) = lower(auth.jwt() ->> 'email')
                   and s.registrado_en > now() - interval '30 minutes'));

create policy ent_odoo_traslado_ins_auto on public.ent_odoo_traslado
  for insert to authenticated
  with check (
    acceso_perfil() = 'equipo'
    and creado_por = (auth.jwt() ->> 'email')
    and exists (select 1
                  from public.ent_salida_vigente s
                  join public.ent_alisto_vigente a on a.alisto_id = s.alisto_id
                 where a.pedido_id = ent_odoo_traslado.pedido_id
                   and lower(s.creado_por) = lower(auth.jwt() ->> 'email')
                   and s.registrado_en > now() - interval '30 minutes'));

create policy ent_odoo_hecho_ins_auto on public.ent_odoo_hecho
  for insert to authenticated
  with check (
    acceso_perfil() = 'equipo'
    and creado_por = (auth.jwt() ->> 'email')
    and exists (select 1
                  from public.ent_odoo_pendiente p
                  join public.ent_odoo_traslado t on t.pedido_id = p.pedido_id
                 where p.id = ent_odoo_hecho.pendiente_id
                   and p.tipo = 'traslado_interno'
                   and t.picking_nombre = ent_odoo_hecho.referencia
                   and t.creado_por = (auth.jwt() ->> 'email')
                   and t.creado_en > now() - interval '30 minutes'));
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

do $$
declare
  v_socia text; v_equipo text; v_asist text;
  v_p1 bigint; v_p2 bigint; v_p3 bigint; v_p4 bigint; v_a bigint; v_s bigint;
  v_pn1 bigint; v_pn2 bigint; v_n int;
  v_res jsonb := '[]'::jsonb;
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by id limit 1;
  select email into v_equipo from v_acceso_usuario where perfil = 'equipo' and activo order by id limit 1;
  select email into v_asist  from v_acceso_usuario where perfil = 'asistente' and activo order by id limit 1;
  if v_socia is null or v_equipo is null or v_asist is null then
    raise exception 'el ensayo necesita una socia, alguien de equipo y el asistente (socia %, equipo %, asistente %)',
      v_socia is not null, v_equipo is not null, v_asist is not null;
  end if;

  -- ── los datos inventados (como postgres, adentro de la transacción) ──
  -- p1: Daniel entregó recién · p2: entregó la socia · p3: Daniel, hace 31 min · p4: Daniel, anulada
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por) values (current_date, 'manual', 'regalia', v_equipo) returning id into v_p1;
  insert into ent_alisto (pedido_id, responsable, creado_por) values (v_p1, v_equipo, v_equipo) returning id into v_a;
  insert into ent_salida (alisto_id, creado_por) values (v_a, v_equipo);
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por) values (current_date, 'manual', 'regalia', v_socia) returning id into v_p2;
  insert into ent_alisto (pedido_id, responsable, creado_por) values (v_p2, v_socia, v_socia) returning id into v_a;
  insert into ent_salida (alisto_id, creado_por) values (v_a, v_socia);
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por) values (current_date, 'manual', 'regalia', v_equipo) returning id into v_p3;
  insert into ent_alisto (pedido_id, responsable, creado_por) values (v_p3, v_equipo, v_equipo) returning id into v_a;
  insert into ent_salida (alisto_id, creado_por, creado_en) values (v_a, v_equipo, now() - interval '31 minutes');
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por) values (current_date, 'manual', 'regalia', v_equipo) returning id into v_p4;
  insert into ent_alisto (pedido_id, responsable, creado_por) values (v_p4, v_equipo, v_equipo) returning id into v_a;
  insert into ent_salida (alisto_id, creado_por) values (v_a, v_equipo) returning id into v_s;
  insert into ent_anulacion (entidad, entidad_id, motivo, creado_por) values ('salida', v_s, 'ensayo', v_socia);
  insert into ent_odoo_pendiente (tipo, pedido_id, fecha, creado_por) values ('traslado_interno', v_p1, current_date, v_equipo) returning id into v_pn1;
  insert into ent_odoo_pendiente (tipo, pedido_id, fecha, creado_por) values ('traslado_interno', v_p2, current_date, v_socia) returning id into v_pn2;

  -- ── equipo (Daniel) ──
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into ent_odoo_validacion (pedido_id, factura_id, picking_id, picking_nombre, lineas, validado_por) values (v_p1, -1, -101, 'WH/OUT/ENSAYO101', '[{"producto_id":481,"uds":5}]', v_equipo);
    v_res := v_res || jsonb_build_object('p','V1 equipo: SU salida de recién, con SU nombre','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','V1 equipo: SU salida de recién, con SU nombre','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ent_odoo_validacion (pedido_id, factura_id, picking_id, picking_nombre, lineas, validado_por) values (v_p1, -1, -102, 'WH/OUT/ENSAYO102', '[{"producto_id":481,"uds":5}]', v_socia);
    v_res := v_res || jsonb_build_object('p','V2 equipo firma con el nombre de la socia','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','V2 equipo firma con el nombre de la socia','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_odoo_validacion (pedido_id, factura_id, picking_id, picking_nombre, lineas, validado_por) values (v_p2, -1, -103, 'WH/OUT/ENSAYO103', '[{"producto_id":481,"uds":5}]', v_equipo);
    v_res := v_res || jsonb_build_object('p','V3 equipo sobre la salida de la socia','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','V3 equipo sobre la salida de la socia','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_odoo_validacion (pedido_id, factura_id, picking_id, picking_nombre, lineas, validado_por) values (v_p3, -1, -104, 'WH/OUT/ENSAYO104', '[{"producto_id":481,"uds":5}]', v_equipo);
    v_res := v_res || jsonb_build_object('p','V4 equipo sobre SU salida de hace 31 min','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','V4 equipo sobre SU salida de hace 31 min','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_odoo_validacion (pedido_id, factura_id, picking_id, picking_nombre, lineas, validado_por) values (v_p4, -1, -105, 'WH/OUT/ENSAYO105', '[{"producto_id":481,"uds":5}]', v_equipo);
    v_res := v_res || jsonb_build_object('p','V5 equipo sobre SU salida anulada','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','V5 equipo sobre SU salida anulada','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    update ent_odoo_validacion set picking_nombre = 'x' where picking_id = -101;
    v_res := v_res || jsonb_build_object('p','V6 equipo EDITA su fila','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','V6 equipo EDITA su fila','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    delete from ent_odoo_validacion where picking_id = -101;
    v_res := v_res || jsonb_build_object('p','V7 equipo BORRA su fila','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','V7 equipo BORRA su fila','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_odoo_traslado (pedido_id, picking_id, picking_nombre, motivo, destino_id, contacto_id, lineas, creado_por) values (v_p1, -201, 'WH/INT/ENSAYO201', 'regalia', 19, 1260, '[{"producto_id":451,"uds":6}]', v_equipo);
    v_res := v_res || jsonb_build_object('p','T1 equipo: traslado de SU salida de recién','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T1 equipo: traslado de SU salida de recién','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ent_odoo_traslado (pedido_id, picking_id, picking_nombre, motivo, destino_id, contacto_id, lineas, creado_por) values (v_p2, -202, 'WH/INT/ENSAYO202', 'regalia', 19, 1260, '[{"producto_id":451,"uds":6}]', v_equipo);
    v_res := v_res || jsonb_build_object('p','T2 equipo: traslado sobre la salida de la socia','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T2 equipo: traslado sobre la salida de la socia','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_odoo_traslado (pedido_id, picking_id, picking_nombre, motivo, destino_id, contacto_id, lineas, creado_por) values (v_p3, -203, 'WH/INT/ENSAYO203', 'regalia', 19, 1260, '[{"producto_id":451,"uds":6}]', v_socia);
    v_res := v_res || jsonb_build_object('p','T3 equipo: traslado firmado como la socia','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','T3 equipo: traslado firmado como la socia','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_odoo_hecho (pendiente_id, referencia, creado_por) values (v_pn1, 'WH/INT/ENSAYO201', v_equipo);
    v_res := v_res || jsonb_build_object('p','H1 equipo: «hecho» de SU traslado, misma referencia','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','H1 equipo: «hecho» de SU traslado, misma referencia','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ent_odoo_hecho (pendiente_id, referencia, creado_por) values (v_pn2, 'WH/INT/ENSAYO201', v_equipo);
    v_res := v_res || jsonb_build_object('p','H2 equipo: «hecho» de un pendiente sin traslado suyo','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','H2 equipo: «hecho» de un pendiente sin traslado suyo','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_odoo_hecho (pendiente_id, referencia, creado_por) values (v_pn1, 'WH/INT/OTRO', v_equipo);
    v_res := v_res || jsonb_build_object('p','H3 equipo: «hecho» con otra referencia','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','H3 equipo: «hecho» con otra referencia','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_odoo_hecho (pendiente_id, referencia, creado_por) values (v_pn1, 'WH/INT/ENSAYO201', v_socia);
    v_res := v_res || jsonb_build_object('p','H4 equipo: «hecho» firmado como la socia','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','H4 equipo: «hecho» firmado como la socia','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── el asistente, con la salida de Daniel ──
  perform set_config('request.jwt.claims', json_build_object('email', v_asist, 'role', 'authenticated')::text, true);
  begin
    insert into ent_odoo_validacion (pedido_id, factura_id, picking_id, picking_nombre, lineas, validado_por) values (v_p1, -1, -301, 'WH/OUT/ENSAYO301', '[{"producto_id":481,"uds":5}]', v_asist);
    v_res := v_res || jsonb_build_object('p','A1 el asistente valida','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A1 el asistente valida','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── la socia: lo de antes, sin cambios ──
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  begin
    insert into ent_odoo_validacion (pedido_id, factura_id, picking_id, picking_nombre, lineas, validado_por) values (v_p2, -1, -401, 'WH/OUT/ENSAYO401', '[{"producto_id":481,"uds":5}]', v_socia);
    v_res := v_res || jsonb_build_object('p','S1 la socia valida un pedido que no entregó','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S1 la socia valida un pedido que no entregó','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ent_odoo_hecho (pendiente_id, referencia, creado_por) values (v_pn2, 'a mano', v_socia);
    v_res := v_res || jsonb_build_object('p','S2 la socia marca «hecho» sin traslado','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S2 la socia marca «hecho» sin traslado','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;

  -- ── anon ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
  begin
    insert into ent_odoo_validacion (pedido_id, factura_id, picking_id, picking_nombre, lineas, validado_por) values (v_p1, -1, -501, 'WH/OUT/ENSAYO501', '[{"producto_id":481,"uds":5}]', 'anon');
    v_res := v_res || jsonb_build_object('p','N1 anon valida','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','N1 anon valida','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── editor SQL: lo que quedó adentro ──
  perform set_config('role', 'postgres', true);
  select (select count(*) from ent_odoo_validacion where picking_id in (-101, -401))
       + (select count(*) from ent_odoo_traslado where picking_id = -201)
       + (select count(*) from ent_odoo_hecho where pendiente_id in (v_pn1, v_pn2))
    into v_n;
  v_res := v_res || jsonb_build_object('p','Z1 quedaron exactamente las 5 filas que tenían que entrar','esperado','5','obtenido',v_n::text,'ok',v_n=5);

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: 19 filas, todas ok = true.

rollback;
