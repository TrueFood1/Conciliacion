-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_PERFIL_INSTINCT.sql  ·  13-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Pone la fila de Instinct (copia de PERFIL_INSTINCT.sql), lo prueba apagado, encendido por una socia
-- y vuelto a apagar, y lo deshace todo (rollback). Supone el interruptor SIN filas (como hoy).
-- ✅ CORRIDO el 13-oct-2026 por Andrea en producción: 37 de 37 ok = true; I7/E8 rechazados por
--    asistente_no_inserta, I12 por la guardia de ent_corregir_alisto; el equipo sin cambios.
--
-- CÓMO SE LEE
--   Una tabla de 37 filas, TODAS con ok = true. Un RECHAZA da ok solo si el SQLSTATE esperado está
--   en `obtenido` (I12 además exige que el mensaje sea el de la guardia del asistente). «0 filas» en
--   un update/delete = la política no le dejó tocar nada. Si el editor dice "Success. No rows
--   returned", no llegó al final y no vale.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE (copia de PERFIL_INSTINCT.sql) ▼▼▼
insert into public.acceso_usuario (email, nombre, perfil, activo, nota, creado_por)
values ('instinct@truefoodcr.com', 'Instinct', 'asistente', true,
        'Asistente de Andrea por voz/WhatsApp (decisión del 12/13-oct). Solo lectura con su interruptor; cada escritura se habilita aparte (asistente_permiso + interruptor del carril).',
        'andrea@truefoodcr.com');
-- ▲▲▲ FIN BLOQUE ▲▲▲

do $$
declare
  v_socia text; v_equipo text; v_n bigint; v_t text; v_total bigint; v_tar bigint; v_prop bigint;
  v_res jsonb := '[]'::jsonb;
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by id limit 1;
  select email into v_equipo from v_acceso_usuario where perfil = 'equipo' and activo order by id limit 1;
  if v_socia is null or v_equipo is null then
    raise exception 'el ensayo necesita una socia y alguien de equipo (socia %, equipo %)', v_socia, v_equipo;
  end if;

  -- ── el punto de partida (editor SQL) ──
  select count(*) into v_n from asistente_interruptor;
  if v_n > 0 then raise exception 'el interruptor ya tiene % filas: este ensayo supone que está APAGADO sin filas', v_n; end if;
  select count(*) into v_total from ent_pedido;
  select count(*) into v_tar from compra_tarifa_odoo;
  select count(*) into v_prop from compra_insumo_propuesta;
  -- una fila sana de ent_pedido para intentar copiarla (si un candado fallara, lo deshace el rollback)
  create temp table ent_pedido_copia on commit drop as select * from ent_pedido order by id desc limit 1;
  grant select on ent_pedido_copia to authenticated;

  begin
    v_t := (v_total > 0)::text;
    v_res := v_res || jsonb_build_object('p','Z0 ent_pedido tiene filas para la prueba','esperado',true::text,'obtenido',v_t,'ok',v_t = (true)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','Z0 ent_pedido tiene filas para la prueba','esperado',true::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;

  -- ── Instinct, interruptor APAGADO ──
  perform set_config('request.jwt.claims', json_build_object('email', 'instinct@truefoodcr.com', 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    v_t := (acceso_perfil())::text;
    v_res := v_res || jsonb_build_object('p','I1 acceso_perfil() de Instinct','esperado','asistente'::text,'obtenido',v_t,'ok',v_t = ('asistente')::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','I1 acceso_perfil() de Instinct','esperado','asistente'::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := (acceso_es_asistente())::text;
    v_res := v_res || jsonb_build_object('p','I2 acceso_es_asistente() de Instinct','esperado',true::text,'obtenido',v_t,'ok',v_t = (true)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','I2 acceso_es_asistente() de Instinct','esperado',true::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := (asistente_bloqueado())::text;
    v_res := v_res || jsonb_build_object('p','I3 asistente_bloqueado(): el proxy no le lee Odoo','esperado',true::text,'obtenido',v_t,'ok',v_t = (true)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','I3 asistente_bloqueado(): el proxy no le lee Odoo','esperado',true::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := ((select count(*) from ent_pedido))::text;
    v_res := v_res || jsonb_build_object('p','I4 apagado: lee 0 pedidos','esperado',0::text,'obtenido',v_t,'ok',v_t = (0)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','I4 apagado: lee 0 pedidos','esperado',0::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := ((select count(*) from acceso_usuario))::text;
    v_res := v_res || jsonb_build_object('p','I5 apagado: ni su propia fila de acceso','esperado',0::text,'obtenido',v_t,'ok',v_t = (0)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','I5 apagado: ni su propia fila de acceso','esperado',0::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := ((select count(*) from compra_tarifa_odoo))::text;
    v_res := v_res || jsonb_build_object('p','I6 apagado: 0 tarifas de compra','esperado',0::text,'obtenido',v_t,'ok',v_t = (0)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','I6 apagado: 0 tarifas de compra','esperado',0::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ent_pedido (fecha_despacho, origen, motivo, creado_por) select fecha_despacho, origen, motivo, 'instinct@truefoodcr.com' from ent_pedido_copia limit 1;
    v_res := v_res || jsonb_build_object('p','I7 inserta un pedido (tabla con INSERT abierto)','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','I7 inserta un pedido (tabla con INSERT abierto)','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    update ent_pedido set motivo = motivo;
    get diagnostics v_n = row_count;
    v_res := v_res || jsonb_build_object('p','I8 actualiza pedidos','esperado',(0)::text||' filas','obtenido',v_n::text||' filas','ok',v_n = (0));
  exception when others then
    v_res := v_res || jsonb_build_object('p','I8 actualiza pedidos','esperado',(0)::text||' filas','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    delete from ent_pedido;
    get diagnostics v_n = row_count;
    v_res := v_res || jsonb_build_object('p','I9 borra pedidos','esperado',(0)::text||' filas','obtenido',v_n::text||' filas','ok',v_n = (0));
  exception when others then
    v_res := v_res || jsonb_build_object('p','I9 borra pedidos','esperado',(0)::text||' filas','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into asistente_interruptor (encendido, motivo, creado_por) values (true, 'yo', 'instinct@truefoodcr.com');
    v_res := v_res || jsonb_build_object('p','I10 se enciende a sí mismo','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','I10 se enciende a sí mismo','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into asistente_permiso (capacidad, encendido, motivo, creado_por) values ('crear_insumo', true, 'yo', 'instinct@truefoodcr.com');
    v_res := v_res || jsonb_build_object('p','I11 se da un permiso','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','I11 se da un permiso','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    perform ent_corregir_alisto(1, 1, '[]'::jsonb, 'x', 'x');
    v_res := v_res || jsonb_build_object('p','I12 ent_corregir_alisto (la guardia)','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','I12 ent_corregir_alisto (la guardia)','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501' and sqlerrm like '%asistente%');
  end;
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, factura_ref, creado_por) values ('X', 12, 15, '2363000000000', 1183, 1, '00100001010000008144', 'instinct@truefoodcr.com');
    v_res := v_res || jsonb_build_object('p','I13 propone un insumo','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','I13 propone un insumo','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── una socia ENCIENDE ──
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_interruptor (encendido, motivo, creado_por) values (true, 'ensayo', v_socia);
    v_res := v_res || jsonb_build_object('p','S1 la socia enciende el interruptor','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S1 la socia enciende el interruptor','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := (acceso_es_asistente())::text;
    v_res := v_res || jsonb_build_object('p','S2 la socia no es asistente','esperado',false::text,'obtenido',v_t,'ok',v_t = (false)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S2 la socia no es asistente','esperado',false::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := (asistente_bloqueado())::text;
    v_res := v_res || jsonb_build_object('p','S3 a la socia el proxy le sigue leyendo','esperado',false::text,'obtenido',v_t,'ok',v_t = (false)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S3 a la socia el proxy le sigue leyendo','esperado',false::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := ((select count(*) from ent_pedido))::text;
    v_res := v_res || jsonb_build_object('p','S4 la socia sigue viendo todos los pedidos','esperado',v_total::text,'obtenido',v_t,'ok',v_t = (v_total)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S4 la socia sigue viendo todos los pedidos','esperado',v_total::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;

  -- ── Instinct, ENCENDIDO ──
  perform set_config('request.jwt.claims', json_build_object('email', 'instinct@truefoodcr.com', 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    v_t := (asistente_bloqueado())::text;
    v_res := v_res || jsonb_build_object('p','E1 asistente_bloqueado(): ahora el proxy le lee','esperado',false::text,'obtenido',v_t,'ok',v_t = (false)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E1 asistente_bloqueado(): ahora el proxy le lee','esperado',false::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := ((select count(*) from ent_pedido))::text;
    v_res := v_res || jsonb_build_object('p','E2 lee todos los pedidos','esperado',v_total::text,'obtenido',v_t,'ok',v_t = (v_total)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E2 lee todos los pedidos','esperado',v_total::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := ((select count(*) from compra_tarifa_odoo))::text;
    v_res := v_res || jsonb_build_object('p','E3 ve los precios de compra (tarifas)','esperado',v_tar::text,'obtenido',v_t,'ok',v_t = (v_tar)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E3 ve los precios de compra (tarifas)','esperado',v_tar::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := ((select count(*) from compra_insumo_propuesta))::text;
    v_res := v_res || jsonb_build_object('p','E4 ve las propuestas de insumo','esperado',v_prop::text,'obtenido',v_t,'ok',v_t = (v_prop)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E4 ve las propuestas de insumo','esperado',v_prop::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := ((select count(*) from rrhh_persona))::text;
    v_res := v_res || jsonb_build_object('p','E5 Personal cerrado: 0 personas','esperado',0::text,'obtenido',v_t,'ok',v_t = (0)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E5 Personal cerrado: 0 personas','esperado',0::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := ((select count(*) from rrhh_salario))::text;
    v_res := v_res || jsonb_build_object('p','E6 Personal cerrado: 0 salarios','esperado',0::text,'obtenido',v_t,'ok',v_t = (0)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E6 Personal cerrado: 0 salarios','esperado',0::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := ((select count(*) from storage.objects))::text;
    v_res := v_res || jsonb_build_object('p','E7 no ve archivos (storage)','esperado',0::text,'obtenido',v_t,'ok',v_t = (0)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E7 no ve archivos (storage)','esperado',0::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ent_pedido (fecha_despacho, origen, motivo, creado_por) select fecha_despacho, origen, motivo, 'instinct@truefoodcr.com' from ent_pedido_copia limit 1;
    v_res := v_res || jsonb_build_object('p','E8 encendido igual no inserta pedidos','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E8 encendido igual no inserta pedidos','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    update ent_pedido set motivo = motivo;
    get diagnostics v_n = row_count;
    v_res := v_res || jsonb_build_object('p','E9 encendido igual no actualiza','esperado',(0)::text||' filas','obtenido',v_n::text||' filas','ok',v_n = (0));
  exception when others then
    v_res := v_res || jsonb_build_object('p','E9 encendido igual no actualiza','esperado',(0)::text||' filas','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    delete from ent_pedido;
    get diagnostics v_n = row_count;
    v_res := v_res || jsonb_build_object('p','E10 encendido igual no borra','esperado',(0)::text||' filas','obtenido',v_n::text||' filas','ok',v_n = (0));
  exception when others then
    v_res := v_res || jsonb_build_object('p','E10 encendido igual no borra','esperado',(0)::text||' filas','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into asistente_permiso (capacidad, encendido, motivo, creado_por) values ('crear_insumo', true, 'yo', 'instinct@truefoodcr.com');
    v_res := v_res || jsonb_build_object('p','E11 encendido igual no se da permisos','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E11 encendido igual no se da permisos','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into asistente_interruptor (encendido, motivo, creado_por) values (false, 'yo', 'instinct@truefoodcr.com');
    v_res := v_res || jsonb_build_object('p','E12 encendido igual no se apaga ni se enciende','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E12 encendido igual no se apaga ni se enciende','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── la socia APAGA ──
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_interruptor (encendido, motivo, creado_por) values (false, 'ensayo', v_socia);
    v_res := v_res || jsonb_build_object('p','S5 la socia apaga','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S5 la socia apaga','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', 'instinct@truefoodcr.com', 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    v_t := (asistente_bloqueado())::text;
    v_res := v_res || jsonb_build_object('p','A1 apagado otra vez: bloqueado','esperado',true::text,'obtenido',v_t,'ok',v_t = (true)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A1 apagado otra vez: bloqueado','esperado',true::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := ((select count(*) from ent_pedido))::text;
    v_res := v_res || jsonb_build_object('p','A2 apagado otra vez: 0 pedidos','esperado',0::text,'obtenido',v_t,'ok',v_t = (0)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A2 apagado otra vez: 0 pedidos','esperado',0::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;

  -- ── alguien de equipo: nada cambia ──
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    v_t := (acceso_es_asistente())::text;
    v_res := v_res || jsonb_build_object('p','Q1 equipo no es asistente','esperado',false::text,'obtenido',v_t,'ok',v_t = (false)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','Q1 equipo no es asistente','esperado',false::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := (asistente_bloqueado())::text;
    v_res := v_res || jsonb_build_object('p','Q2 al equipo el proxy le sigue leyendo','esperado',false::text,'obtenido',v_t,'ok',v_t = (false)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','Q2 al equipo el proxy le sigue leyendo','esperado',false::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;

  perform set_config('role', 'postgres', true);
  begin
    v_t := ((select count(*) from acceso_usuario where lower(email) = 'instinct@truefoodcr.com' and perfil = 'asistente'))::text;
    v_res := v_res || jsonb_build_object('p','Z1 la fila de Instinct quedó (dentro del ensayo)','esperado',1::text,'obtenido',v_t,'ok',v_t = (1)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','Z1 la fila de Instinct quedó (dentro del ensayo)','esperado',1::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_t := ((select count(*) from ent_pedido))::text;
    v_res := v_res || jsonb_build_object('p','Z2 los pedidos, intactos','esperado',v_total::text,'obtenido',v_t,'ok',v_t = (v_total)::text);
  exception when others then
    v_res := v_res || jsonb_build_object('p','Z2 los pedidos, intactos','esperado',v_total::text,'obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: 37 filas, todas ok = true.

rollback;
