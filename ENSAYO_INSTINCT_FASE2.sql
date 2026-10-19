-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_INSTINCT_FASE2.sql  ·  19-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA (termina en rollback)
-- Prueba INSTINCT_FASE2.sql: permiso por acción, vista previa con código, intentos y el rastro
-- «hecho por Instinct». Lo arma herramientas/ensayos/armar_ensayo_instinct_fase2.py (md5 del bloque DDL: 43ee85ef4bfe402859fa61101fdc5dd3).
-- ✅ CORRIDO el 19-oct-2026 por Andrea en producción: 52 de 52 ok = true, cada RECHAZA con su SQLSTATE y por
--    SU motivo (42501 RLS o sin permiso; 23514 capacidad_check, codigo_check, marca_ok; 23505 el único de
--    código). X2: 9 tablas rebotan antes por su guardia BEFORE INSERT (8 P0001 + rrhh_feriado_trabajado 23514).
--    VERIFICADO desde afuera (pg_lector): el rollback no dejó nada (sin tablas, funciones ni columnas nuevas;
--    permiso vacío; políticas 8 · 8 · 7; interruptor del asistente intacto).
--
-- CÓMO SE LEE
--   Una tabla de 52 filas, TODAS con ok = true. Un RECHAZA da ok solo si el SQLSTATE esperado está
--   en `obtenido` (no vale rechazar por el motivo de al lado). Si el editor dice "Success. No rows
--   returned", no llegó al final y no vale.
--   42501 = RLS o sin permiso · 23514 = check · 23505 = único.
--   X1/X2: Instinct intenta un INSERT en CADA tabla de public que no es de esta fase; ninguna lo
--   acepta (X1), y todas rebotan por RLS o permiso, salvo las que tienen una guardia BEFORE INSERT
--   (corre antes que el RLS): esas se nombran aparte en `obtenido` (X2).
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE DDL (copia de INSTINCT_FASE2.sql) ▼▼▼
create table public.asistente_vista_previa (
  id           uuid primary key,                                   -- lo genera el servicio (entra en el código)
  n            bigint generated always as identity unique,         -- el orden: vale la de n más alto
  accion       text not null check (accion in ('crear_insumo', 'facturar', 'validar_entrega', 'confirmar_oc')),
  propuesta_id bigint not null check (propuesta_id > 0),
  huella       text not null check (length(huella) between 1 and 64),
  codigo       text not null check (codigo ~ '^[0-9]{4}$'),
  creado_por   text not null,
  creado_en    timestamptz not null default now(),
  unique (accion, propuesta_id, codigo)
);

create table public.asistente_intento (
  id              bigint generated always as identity primary key,
  vista_previa_id uuid not null references public.asistente_vista_previa (id),
  creado_por      text not null,
  creado_en       timestamptz not null default now()
);

alter table public.asistente_vista_previa enable row level security;
alter table public.asistente_intento enable row level security;
revoke all on public.asistente_vista_previa, public.asistente_intento from anon, authenticated;
grant select, insert on public.asistente_vista_previa, public.asistente_intento to authenticated;

-- ── funciones (SECURITY DEFINER: leen por encima del RLS, solo devuelven sí o no) ──
-- asistente_puede(p_capacidad) ya existe (ASISTENTE_ROL.sql) y no se toca.
create function public.asistente_propuesta_propia(p_accion text, p_propuesta bigint) returns boolean
  language sql stable security definer set search_path = public as $f$
  select case p_accion
           when 'crear_insumo' then exists (select 1 from compra_insumo_propuesta p where p.id = p_propuesta
                                              and lower(p.creado_por) = lower(coalesce(auth.jwt() ->> 'email', '')))
           else false end;
$f$;

create function public.asistente_vista_previa_propia(p_vp uuid) returns boolean
  language sql stable security definer set search_path = public as $f$
  select exists (select 1 from asistente_vista_previa v where v.id = p_vp
                   and lower(v.creado_por) = lower(coalesce(auth.jwt() ->> 'email', ''))
                   and asistente_puede(v.accion));
$f$;

-- El rastro de una creación hecha por el asistente: su vista previa, la ÚLTIMA de esa propuesta,
-- con menos de 3 intentos fallidos, y el código de esa vista previa.
create function public.asistente_rastro_ok(p_propuesta bigint, p_vp uuid, p_codigo text) returns boolean
  language sql stable security definer set search_path = public as $f$
  select exists (select 1 from asistente_vista_previa v
                  where v.id = p_vp and v.accion = 'crear_insumo' and v.propuesta_id = p_propuesta
                    and v.codigo = p_codigo
                    and lower(v.creado_por) = lower(coalesce(auth.jwt() ->> 'email', ''))
                    and v.n = (select max(w.n) from asistente_vista_previa w
                                where w.accion = 'crear_insumo' and w.propuesta_id = p_propuesta)
                    and (select count(*) from asistente_intento i where i.vista_previa_id = v.id) < 3);
$f$;

revoke all on function public.asistente_propuesta_propia(text, bigint),
                       public.asistente_vista_previa_propia(uuid), public.asistente_rastro_ok(bigint, uuid, text)
  from public, anon;
grant execute on function public.asistente_propuesta_propia(text, bigint),
                          public.asistente_vista_previa_propia(uuid), public.asistente_rastro_ok(bigint, uuid, text)
  to authenticated;

-- ── asistente_vista_previa: la inserta el asistente (por el servicio, con su token) ──
create policy asistente_vista_previa_sel on public.asistente_vista_previa
  for select to authenticated using (acceso_es_socia());
drop policy asistente_no_inserta on public.asistente_vista_previa;
create policy asistente_inserta_con_permiso on public.asistente_vista_previa as restrictive
  for insert to authenticated
  with check (not (select public.acceso_es_asistente())
              or (asistente_puede(accion) and asistente_propuesta_propia(accion, propuesta_id)));
create policy asistente_vista_previa_ins on public.asistente_vista_previa
  for insert to authenticated
  with check ((select public.acceso_es_asistente()) and creado_por = (auth.jwt() ->> 'email')
              and asistente_puede(accion) and asistente_propuesta_propia(accion, propuesta_id));

-- ── asistente_intento: lo inserta el asistente sobre SUS vistas previas ──
create policy asistente_intento_sel on public.asistente_intento
  for select to authenticated using (acceso_es_socia());
drop policy asistente_no_inserta on public.asistente_intento;
create policy asistente_inserta_con_permiso on public.asistente_intento as restrictive
  for insert to authenticated
  with check (not (select public.acceso_es_asistente()) or asistente_vista_previa_propia(vista_previa_id));
create policy asistente_intento_ins on public.asistente_intento
  for insert to authenticated
  with check ((select public.acceso_es_asistente()) and creado_por = (auth.jwt() ->> 'email')
              and asistente_vista_previa_propia(vista_previa_id));

-- ── compra_insumo_propuesta: el asistente propone, con el permiso encendido ──
drop policy asistente_no_inserta on public.compra_insumo_propuesta;
create policy asistente_inserta_con_permiso on public.compra_insumo_propuesta as restrictive
  for insert to authenticated
  with check (not (select public.acceso_es_asistente()) or asistente_puede('crear_insumo'));
create policy compra_insumo_propuesta_ins_asistente on public.compra_insumo_propuesta
  for insert to authenticated
  with check ((select public.acceso_es_asistente()) and asistente_puede('crear_insumo')
              and creado_por = (auth.jwt() ->> 'email'));

-- ── compra_insumo_odoo: la marca de Instinct y su rastro ──
alter table public.compra_insumo_odoo
  add column hecho_por_asistente boolean not null default false,
  add column vista_previa_id uuid references public.asistente_vista_previa (id),
  add column codigo text check (codigo is null or codigo ~ '^[0-9]{4}$'),
  add constraint compra_insumo_odoo_marca_ok check (
    hecho_por_asistente = (vista_previa_id is not null) and (vista_previa_id is null) = (codigo is null));
drop policy compra_insumo_odoo_ins on public.compra_insumo_odoo;
create policy compra_insumo_odoo_ins on public.compra_insumo_odoo
  for insert to authenticated
  with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email') and not hecho_por_asistente);
drop policy asistente_no_inserta on public.compra_insumo_odoo;
create policy asistente_inserta_con_permiso on public.compra_insumo_odoo as restrictive
  for insert to authenticated
  with check (not (select public.acceso_es_asistente()) or asistente_puede('crear_insumo'));
create policy compra_insumo_odoo_ins_asistente on public.compra_insumo_odoo
  for insert to authenticated
  with check ((select public.acceso_es_asistente()) and creado_por = (auth.jwt() ->> 'email')
              and hecho_por_asistente and asistente_puede('crear_insumo')
              and asistente_propuesta_propia('crear_insumo', propuesta_id)
              and asistente_rastro_ok(propuesta_id, vista_previa_id, codigo));
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

do $$
declare
  v_socia text; v_equipo text; v_asis text; v_n int; v_t record; v_otros text := ''; v_guardia text := ''; v_entraron text := '';
  v_pa bigint; v_pb bigint; v_pc bigint; v_ps bigint; v_x bigint;
  v_vp1 uuid := gen_random_uuid(); v_vp2 uuid := gen_random_uuid(); v_vp3 uuid := gen_random_uuid();
  v_vp4 uuid := gen_random_uuid(); v_vp_ajena uuid := gen_random_uuid();
  v_res jsonb := '[]'::jsonb;
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by id limit 1;
  select email into v_equipo from v_acceso_usuario where perfil not in ('socias', 'asistente') and activo order by id limit 1;
  select email into v_asis   from v_acceso_usuario where perfil = 'asistente' and activo order by id limit 1;
  if v_socia is null or v_equipo is null or v_asis is null then
    raise exception 'el ensayo necesita una socia, alguien de equipo y el asistente (%, %, %)', v_socia, v_equipo, v_asis;
  end if;
  -- El interruptor general del asistente ENCENDIDO para el ensayo (se deshace con el rollback).
  insert into asistente_interruptor (encendido, motivo, creado_por) values (true, 'ensayo fase 2', v_socia);
  -- Una vista previa de OTRA persona, para I3 (la escribe el editor, por encima del RLS).
  insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor,
    factura_ref, creado_por) values ('Cacao Ajeno', 12, 15, '2363000000000', 1183, 8910.89, '2292',
    '00100001010000008144', v_socia) returning id into v_x;
  insert into asistente_vista_previa (id, accion, propuesta_id, huella, codigo, creado_por)
    values (v_vp_ajena, 'crear_insumo', v_x, 'eb2df9d55fa4451b', '7777', v_socia);

  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Cacao A0', 12, 15, '2363000000000', 1183, 8910.89, '2292', '00100001010000008144', v_asis) returning id into v_x;
    v_res := v_res || jsonb_build_object('p','A0 Instinct propone un insumo con el permiso APAGADO','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A0 Instinct propone un insumo con el permiso APAGADO','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_permiso (capacidad, encendido, motivo, creado_por) values ('crear_insumo', true, 'ensayo', v_socia);
    v_res := v_res || jsonb_build_object('p','S1 una socia ENCIENDE crear_insumo','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S1 una socia ENCIENDE crear_insumo','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_permiso (capacidad, encendido, motivo, creado_por) values ('facturar', true, 'ensayo', v_asis);
    v_res := v_res || jsonb_build_object('p','S2 Instinct se enciende un permiso a sí mismo','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S2 Instinct se enciende un permiso a sí mismo','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_permiso (capacidad, encendido, motivo, creado_por) values ('crear_insumo', true, 'ensayo', v_equipo);
    v_res := v_res || jsonb_build_object('p','S3 alguien de equipo enciende un permiso','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S3 alguien de equipo enciende un permiso','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_permiso (capacidad, encendido, motivo, creado_por) values ('crear_insumo', true, 'ensayo', v_equipo);
    v_res := v_res || jsonb_build_object('p','S4 una socia firma el permiso con OTRO nombre','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S4 una socia firma el permiso con OTRO nombre','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_permiso (capacidad, encendido, motivo, creado_por) values ('Crear Insumo', true, 'ensayo', v_socia);
    v_res := v_res || jsonb_build_object('p','S5 un permiso con una capacidad mal escrita (mayúsculas y espacio)','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S5 un permiso con una capacidad mal escrita (mayúsculas y espacio)','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Cacao P1', 12, 15, '2363000000000', 1183, 8910.89, '2292', '00100001010000008144', v_asis) returning id into v_pa;
    v_res := v_res || jsonb_build_object('p','P1 Instinct propone el cacao con SU correo','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P1 Instinct propone el cacao con SU correo','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Cacao P2', 12, 15, '2363000000000', 1183, 8910.89, '2292', '00100001010000008144', v_socia) returning id into v_x;
    v_res := v_res || jsonb_build_object('p','P2 Instinct propone firmando como la socia','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P2 Instinct propone firmando como la socia','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Cacao P3', 12, 15, '2363000000000', 1183, 8910.89, '2292', '00100001010000008144', v_socia) returning id into v_ps;
    v_res := v_res || jsonb_build_object('p','P3 la socia sigue proponiendo como siempre','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P3 la socia sigue proponiendo como siempre','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Cacao P4', 12, 15, '2363000000000', 1183, 8910.89, '2292', '00100001010000008144', v_asis) returning id into v_pb;
    v_res := v_res || jsonb_build_object('p','P4 Instinct propone otro (para la vista previa vieja)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P4 Instinct propone otro (para la vista previa vieja)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Cacao P5', 12, 15, '2363000000000', 1183, 8910.89, '2292', '00100001010000008144', v_asis) returning id into v_pc;
    v_res := v_res || jsonb_build_object('p','P5 Instinct propone otro (para la agotada)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','P5 Instinct propone otro (para la agotada)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_vista_previa (id, accion, propuesta_id, huella, codigo, creado_por) values (v_vp1, 'crear_insumo', v_pa, 'eb2df9d55fa4451b', '4821', v_asis);
    v_res := v_res || jsonb_build_object('p','V1 Instinct anota la vista previa de SU propuesta','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','V1 Instinct anota la vista previa de SU propuesta','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_vista_previa (id, accion, propuesta_id, huella, codigo, creado_por) values (gen_random_uuid(), 'crear_insumo', v_ps, 'eb2df9d55fa4451b', '1111', v_asis);
    v_res := v_res || jsonb_build_object('p','V2 vista previa de la propuesta de la SOCIA','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','V2 vista previa de la propuesta de la SOCIA','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_vista_previa (id, accion, propuesta_id, huella, codigo, creado_por) values (gen_random_uuid(), 'crear_insumo', v_pa, 'eb2df9d55fa4451b', '2222', v_socia);
    v_res := v_res || jsonb_build_object('p','V3 vista previa firmada como la socia','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','V3 vista previa firmada como la socia','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_vista_previa (id, accion, propuesta_id, huella, codigo, creado_por) values (gen_random_uuid(), 'crear_insumo', v_pa, 'eb2df9d55fa4451b', '482', v_asis);
    v_res := v_res || jsonb_build_object('p','V4 código de 3 dígitos','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','V4 código de 3 dígitos','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_vista_previa (id, accion, propuesta_id, huella, codigo, creado_por) values (gen_random_uuid(), 'crear_insumo', v_pa, 'eb2df9d55fa4451b', '48A1', v_asis);
    v_res := v_res || jsonb_build_object('p','V5 código con letras','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','V5 código con letras','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_vista_previa (id, accion, propuesta_id, huella, codigo, creado_por) values (gen_random_uuid(), 'crear_insumo', v_pa, 'eb2df9d55fa4451b', '4821', v_asis);
    v_res := v_res || jsonb_build_object('p','V6 MISMO código en otra vista previa de la MISMA propuesta','esperado','RECHAZA · 23505','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','V6 MISMO código en otra vista previa de la MISMA propuesta','esperado','RECHAZA · 23505','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23505');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_vista_previa (id, accion, propuesta_id, huella, codigo, creado_por) values (gen_random_uuid(), 'facturar', v_pa, 'eb2df9d55fa4451b', '3333', v_asis);
    v_res := v_res || jsonb_build_object('p','V7 vista previa para una acción sin permiso (facturar)','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','V7 vista previa para una acción sin permiso (facturar)','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_vista_previa (id, accion, propuesta_id, huella, codigo, creado_por) values (gen_random_uuid(), 'crear_insumo', v_pa, 'eb2df9d55fa4451b', '4444', v_equipo);
    v_res := v_res || jsonb_build_object('p','V8 alguien de equipo anota una vista previa','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','V8 alguien de equipo anota una vista previa','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_vista_previa (id, accion, propuesta_id, huella, codigo, creado_por) values (gen_random_uuid(), 'crear_insumo', v_ps, 'eb2df9d55fa4451b', '5555', v_socia);
    v_res := v_res || jsonb_build_object('p','V9 la socia anota una vista previa (no le toca)','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','V9 la socia anota una vista previa (no le toca)','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_vista_previa (id, accion, propuesta_id, huella, codigo, creado_por) values (v_vp2, 'crear_insumo', v_pb, 'eb2df9d55fa4451b', '1234', v_asis);
    insert into asistente_vista_previa (id, accion, propuesta_id, huella, codigo, creado_por) values (v_vp3, 'crear_insumo', v_pb, 'eb2df9d55fa4451b', '5678', v_asis);
    v_res := v_res || jsonb_build_object('p','V10 Instinct anota dos vistas previas de la propuesta P4 (vieja y vigente)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','V10 Instinct anota dos vistas previas de la propuesta P4 (vieja y vigente)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_vista_previa (id, accion, propuesta_id, huella, codigo, creado_por) values (v_vp4, 'crear_insumo', v_pc, 'eb2df9d55fa4451b', '9012', v_asis);
    v_res := v_res || jsonb_build_object('p','V11 Instinct anota la vista previa de la propuesta P5','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','V11 Instinct anota la vista previa de la propuesta P5','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_intento (vista_previa_id, creado_por) values (v_vp1, v_asis);
    v_res := v_res || jsonb_build_object('p','I1 Instinct anota un intento fallido sobre SU vista previa','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','I1 Instinct anota un intento fallido sobre SU vista previa','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_intento (vista_previa_id, creado_por) values (v_vp1, v_socia);
    v_res := v_res || jsonb_build_object('p','I2 intento firmado como la socia','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','I2 intento firmado como la socia','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_intento (vista_previa_id, creado_por) values (v_vp_ajena, v_asis);
    v_res := v_res || jsonb_build_object('p','I3 intento sobre una vista previa AJENA','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','I3 intento sobre una vista previa AJENA','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_intento (vista_previa_id, creado_por) values (v_vp4, v_asis);
    insert into asistente_intento (vista_previa_id, creado_por) values (v_vp4, v_asis);
    insert into asistente_intento (vista_previa_id, creado_por) values (v_vp4, v_asis);
    v_res := v_res || jsonb_build_object('p','I4 tres intentos sobre la de P5 (queda agotada)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','I4 tres intentos sobre la de P5 (queda agotada)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    update asistente_vista_previa set codigo = '0000' where id = v_vp1;
    v_res := v_res || jsonb_build_object('p','U1 Instinct CAMBIA el código de una vista previa','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','U1 Instinct CAMBIA el código de una vista previa','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    delete from asistente_intento where vista_previa_id = v_vp4;
    v_res := v_res || jsonb_build_object('p','U2 Instinct BORRA sus intentos','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','U2 Instinct BORRA sus intentos','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    delete from asistente_intento where vista_previa_id = v_vp4;
    v_res := v_res || jsonb_build_object('p','U3 la socia BORRA intentos','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','U3 la socia BORRA intentos','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    update asistente_permiso set encendido = false;
    v_res := v_res || jsonb_build_object('p','U4 la socia apaga un permiso CAMBIANDO la fila (no: se agrega otra)','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','U4 la socia apaga un permiso CAMBIANDO la fila (no: se agrega otra)','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into compra_insumo_odoo (propuesta_id, producto_tmpl_id, producto_id, supplierinfo_id, nombre, huella, creado_por, hecho_por_asistente, vista_previa_id, codigo) values (v_pa, 905, null, null, 'Cacao Ensayo', 'eb2df9d55fa4451b', v_asis, true, v_vp1, '4821');
    v_res := v_res || jsonb_build_object('p','R1 Instinct deja el rastro con la vista previa vigente y SU código','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R1 Instinct deja el rastro con la vista previa vigente y SU código','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into compra_insumo_odoo (propuesta_id, producto_tmpl_id, producto_id, supplierinfo_id, nombre, huella, creado_por, hecho_por_asistente, vista_previa_id, codigo) values (v_pb, 906, null, null, 'Cacao Ensayo', 'eb2df9d55fa4451b', v_asis, true, v_vp3, '0000');
    v_res := v_res || jsonb_build_object('p','R2 rastro con el código EQUIVOCADO','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R2 rastro con el código EQUIVOCADO','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into compra_insumo_odoo (propuesta_id, producto_tmpl_id, producto_id, supplierinfo_id, nombre, huella, creado_por, hecho_por_asistente, vista_previa_id, codigo) values (v_pb, 906, null, null, 'Cacao Ensayo', 'eb2df9d55fa4451b', v_asis, true, v_vp2, '1234');
    v_res := v_res || jsonb_build_object('p','R3 rastro con la vista previa VIEJA (y su código)','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R3 rastro con la vista previa VIEJA (y su código)','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into compra_insumo_odoo (propuesta_id, producto_tmpl_id, producto_id, supplierinfo_id, nombre, huella, creado_por, hecho_por_asistente, vista_previa_id, codigo) values (v_pc, 907, null, null, 'Cacao Ensayo', 'eb2df9d55fa4451b', v_asis, true, v_vp4, '9012');
    v_res := v_res || jsonb_build_object('p','R4 rastro con la vista previa AGOTADA (3 intentos) y su código','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R4 rastro con la vista previa AGOTADA (3 intentos) y su código','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into compra_insumo_odoo (propuesta_id, producto_tmpl_id, producto_id, supplierinfo_id, nombre, huella, creado_por, hecho_por_asistente, vista_previa_id, codigo) values (v_pb, 906, null, null, 'Cacao Ensayo', 'eb2df9d55fa4451b', v_asis, false, null, null);
    v_res := v_res || jsonb_build_object('p','R5 rastro de Instinct SIN la marca','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R5 rastro de Instinct SIN la marca','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into compra_insumo_odoo (propuesta_id, producto_tmpl_id, producto_id, supplierinfo_id, nombre, huella, creado_por, hecho_por_asistente, vista_previa_id, codigo) values (v_pc, 907, null, null, 'Cacao Ensayo', 'eb2df9d55fa4451b', v_asis, true, v_vp3, '5678');
    v_res := v_res || jsonb_build_object('p','R6 rastro con la vista previa de OTRA propuesta (código de P4 sobre P5)','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R6 rastro con la vista previa de OTRA propuesta (código de P4 sobre P5)','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into compra_insumo_odoo (propuesta_id, producto_tmpl_id, producto_id, supplierinfo_id, nombre, huella, creado_por, hecho_por_asistente, vista_previa_id, codigo) values (v_ps, 908, null, null, 'Cacao Ensayo', 'eb2df9d55fa4451b', v_socia, true, v_vp1, '4821');
    v_res := v_res || jsonb_build_object('p','R7 la socia firma un rastro «hecho por Instinct»','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R7 la socia firma un rastro «hecho por Instinct»','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into compra_insumo_odoo (propuesta_id, producto_tmpl_id, producto_id, supplierinfo_id, nombre, huella, creado_por, hecho_por_asistente, vista_previa_id, codigo) values (v_ps, 908, null, null, 'Cacao Ensayo', 'eb2df9d55fa4451b', v_socia, false, null, null);
    v_res := v_res || jsonb_build_object('p','R8 la socia deja su rastro de siempre (sin marca)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R8 la socia deja su rastro de siempre (sin marca)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('role', 'postgres', true);
  begin
    insert into compra_insumo_odoo (propuesta_id, producto_tmpl_id, producto_id, supplierinfo_id, nombre, huella, creado_por, hecho_por_asistente, vista_previa_id, codigo) values (v_pb, 909, null, null, 'Cacao Ensayo', 'eb2df9d55fa4451b', v_socia, true, null, null);
    v_res := v_res || jsonb_build_object('p','R9 marca sin vista previa (el check)','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R9 marca sin vista previa (el check)','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into compra_insumo_odoo (propuesta_id, producto_tmpl_id, producto_id, supplierinfo_id, nombre, huella, creado_por, hecho_por_asistente, vista_previa_id, codigo) values (v_pb, 906, null, null, 'Cacao Ensayo', 'eb2df9d55fa4451b', v_asis, true, v_vp3, '5678');
    v_res := v_res || jsonb_build_object('p','R10 Instinct deja el rastro de la vigente de P4 con su código','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','R10 Instinct deja el rastro de la vigente de P4 con su código','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Cacao E1', 12, 15, '2363000000000', 1183, 8910.89, '2292', '00100001010000008144', v_equipo) returning id into v_x;
    v_res := v_res || jsonb_build_object('p','E1 alguien de equipo propone un insumo','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E1 alguien de equipo propone un insumo','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_permiso (capacidad, encendido, motivo, creado_por) values ('crear_insumo', false, 'ensayo', v_socia);
    v_res := v_res || jsonb_build_object('p','S6 la socia APAGA crear_insumo','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S6 la socia APAGA crear_insumo','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Cacao A1', 12, 15, '2363000000000', 1183, 8910.89, '2292', '00100001010000008144', v_asis) returning id into v_x;
    v_res := v_res || jsonb_build_object('p','A1 con el permiso apagado, Instinct propone','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A1 con el permiso apagado, Instinct propone','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_vista_previa (id, accion, propuesta_id, huella, codigo, creado_por) values (gen_random_uuid(), 'crear_insumo', v_pa, 'eb2df9d55fa4451b', '6666', v_asis);
    v_res := v_res || jsonb_build_object('p','A2 con el permiso apagado, Instinct anota una vista previa','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A2 con el permiso apagado, Instinct anota una vista previa','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_permiso (capacidad, encendido, motivo, creado_por) values ('crear_insumo', true, 'ensayo', v_socia);
    v_res := v_res || jsonb_build_object('p','S7 la socia vuelve a encender crear_insumo','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S7 la socia vuelve a encender crear_insumo','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into asistente_interruptor (encendido, motivo, creado_por) values (false, 'ensayo', v_socia);
    v_res := v_res || jsonb_build_object('p','S8 la socia apaga el INTERRUPTOR GENERAL del asistente','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S8 la socia apaga el INTERRUPTOR GENERAL del asistente','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into compra_insumo_propuesta (nombre, uom_id, iva_compra_id, cabys, proveedor_id, precio, codigo_proveedor, factura_ref, creado_por) values ('Cacao A3', 12, 15, '2363000000000', 1183, 8910.89, '2292', '00100001010000008144', v_asis) returning id into v_x;
    v_res := v_res || jsonb_build_object('p','A3 interruptor general apagado (permiso encendido): Instinct propone','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A3 interruptor general apagado (permiso encendido): Instinct propone','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;

  -- ── X · Instinct contra CADA tabla de public que no es de esta fase ──
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  for v_t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
              where n.nspname = 'public' and c.relkind in ('r', 'p')
                and c.relname not in ('compra_insumo_propuesta', 'compra_insumo_odoo', 'asistente_vista_previa', 'asistente_intento')
              order by c.relname loop
    begin
      execute format('insert into public.%I default values', v_t.relname);
      v_entraron := v_entraron || v_t.relname || ' ';
    exception when others then
      if sqlstate <> '42501' then
        -- Una guardia BEFORE INSERT corre antes que el RLS: si la tabla tiene una, el rechazo es suyo.
        if exists (select 1 from pg_trigger g where g.tgrelid = ('public.' || quote_ident(v_t.relname))::regclass
                     and not g.tgisinternal and (g.tgtype & 2) = 2 and (g.tgtype & 4) = 4) then
          v_guardia := v_guardia || v_t.relname || ' (' || sqlstate || ') ';
        else
          v_otros := v_otros || v_t.relname || ' (' || sqlstate || ') ';
        end if;
      end if;
    end;
  end loop;
  v_res := v_res || jsonb_build_object('p','X1 Instinct no puede insertar en NINGUNA otra tabla de public','esperado','ninguna',
                                       'obtenido',coalesce(nullif(v_entraron,''),'ninguna'),'ok',v_entraron='');
  v_res := v_res || jsonb_build_object('p','X2 todas rebotan por RLS o permiso (42501), o por su guardia BEFORE INSERT','esperado','sin otros motivos',
                                       'obtenido',coalesce(nullif(v_otros,''),'sin otros motivos')
                                         ||coalesce(' · por guardia: '||nullif(v_guardia,''),''),'ok',v_otros='');

  -- ── Z · el editor SQL ──
  perform set_config('role', 'postgres', true);
  select count(*) into v_n from compra_insumo_odoo where hecho_por_asistente and propuesta_id in (v_pa, v_pb);
  v_res := v_res || jsonb_build_object('p','Z1 quedaron 2 rastros «hecho por Instinct» (R1 y R10)','esperado','2','obtenido',v_n::text,'ok',v_n=2);
  select count(*) into v_n from asistente_intento where vista_previa_id in (v_vp1, v_vp4);
  v_res := v_res || jsonb_build_object('p','Z2 quedaron 4 intentos (I1 + I4), ninguno borrado','esperado','4','obtenido',v_n::text,'ok',v_n=4);
  select count(*) into v_n from pg_policy where polname = 'asistente_no_inserta'
     and polrelid in ('public.asistente_vista_previa'::regclass, 'public.asistente_intento'::regclass,
                      'public.compra_insumo_propuesta'::regclass, 'public.compra_insumo_odoo'::regclass);
  v_res := v_res || jsonb_build_object('p','Z3 «asistente_no_inserta» cambiada SOLO en las 4 tablas de la fase','esperado','0','obtenido',v_n::text,'ok',v_n=0);

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: 52 filas, todas ok = true.

rollback;
