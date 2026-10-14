-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_ANULAR_PEDIDO.sql · 14-oct-2026 · ENSAYO EN SECO · TERMINA EN ROLLBACK
-- ✅ CORRIDO el 14-oct-2026 por Andrea (tercer intento): 34/34 ok = true, md5 DDL c8f09ae9a0f6.
--    Verificado desde afuera despues: ni la tabla ni la funcion ni los pedidos de ensayo quedaron.
-- «Anular pedido» (§29) · ENTREGAS_ANULAR_PEDIDO.sql
--
-- ⚠️ ARCHIVO GENERADO. No se edita a mano: se regenera con
--     python3 herramientas/ensayos/armar_ensayo_anular_pedido.py
--   El bloque DDL de abajo es el de ENTREGAS_ANULAR_PEDIDO.sql BYTE A BYTE,
--   cortado por sus marcas. md5 del bloque: c8f09ae9a0f646fb2a51f97cdecaf1a9
--
-- QUE HACE
--   1. Crea todo, igual que el pegado.
--   2. Arma pedidos de ensayo ADENTRO de la transaccion (destinatario ENSAYO).
--   3. Prueba sin sesion, como equipo, como asistente, como socia y como anon
--      (sesion simulada con `request.jwt.claims` + rol `authenticated`, o sea
--      CON RLS). Las identidades salen de `v_acceso_usuario`: ningun correo va
--      escrito aca porque el repo es publico.
--   4. rollback. No queda nada: ni el esquema ni los pedidos de ensayo.
--
-- COMO SE LEE
--   Una tabla de 34 filas, TODAS con ok = true. Si el editor dice
--   "Success. No rows returned", no llego al final y no vale.
--   Un RECHAZA da ok SOLO si rebota por SU razon (SQLSTATE + pedazo del mensaje).
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ═══ DDL · DESDE ACA (ENSAYO_ANULAR_PEDIDO.sql copia este bloque tal cual) ═══

-- §0 · CANDADO DE ENTRADA: no pisa nada que ya exista.
do $$
begin
  if to_regclass('public.ent_pedido_anulacion') is not null
     or to_regproc('public.ent_anular_pedido') is not null then
    raise exception 'CANDADO: ent_pedido_anulacion o ent_anular_pedido ya existen. NO SE APLICO NADA.';
  end if;
end $$;

-- §1 · LA TABLA
create table public.ent_pedido_anulacion (
  id          bigint generated always as identity primary key,
  pedido_id   bigint not null references public.ent_pedido(id),
  motivo      text   not null,
  nota        text,
  alistos     bigint[] not null,          -- lo que anuló, para leerlo después sin reconstruirlo
  salidas     bigint[] not null,
  creado_por  text   not null,
  creado_en   timestamptz not null default now(),
  constraint ent_pedido_anulacion_unica     unique (pedido_id),
  constraint ent_pedido_anulacion_motivo_ok check (motivo in ('duplicado', 'no_salio', 'datos_mal', 'otro')),
  constraint ent_pedido_anulacion_nota_ok   check (nota is null or length(btrim(nota)) between 1 and 500),
  constraint ent_pedido_anulacion_otro_ok   check (motivo <> 'otro' or length(btrim(coalesce(nota, ''))) >= 10),
  constraint ent_pedido_anulacion_alistos_ok check (cardinality(alistos) >= 1)
);
comment on table public.ent_pedido_anulacion is
  '§29 (14-oct-2026). Un pedido anulado entero. Se escribe SOLO por ent_anular_pedido(). Append-only.';

-- ⚠️ LAS CINCO POLÍTICAS DEL ASISTENTE Y EL RLS LOS PONE LA BASE SOLA: los event
-- triggers `asistente_politicas` (asistente_crear_politicas) y `ensure_rls`
-- corren en cada CREATE TABLE de public. Escribirlas acá choca (42710, medido en
-- el primer ensayo del 14-oct). Se COMPRUEBA que estén, no se suponen.
do $$
declare v_n int;
begin
  select count(*) into v_n from pg_policy
   where polrelid = 'public.ent_pedido_anulacion'::regclass
     and polname in ('asistente_lee', 'asistente_no_inserta', 'asistente_no_actualiza', 'asistente_no_borra', 'asistente_ve_todo');
  if v_n <> 5 then
    raise exception 'CANDADO: el trigger del asistente dejó % de 5 políticas en ent_pedido_anulacion. NO SE APLICO NADA.', v_n;
  end if;
end $$;
alter table public.ent_pedido_anulacion enable row level security;   -- ya lo hizo ensure_rls; explícito no cuesta
create policy ent_pedido_anulacion_sel on public.ent_pedido_anulacion for select to authenticated using (true);
-- Sin política de INSERT: nadie inserta directo. Solo la función (security definer).
revoke all on table public.ent_pedido_anulacion from public, anon, authenticated;
grant select on table public.ent_pedido_anulacion to authenticated;
grant select on table public.ent_pedido_anulacion to truefie_pruebas;   -- como en las tablas hermanas: pg_pruebas lee las colas

-- §2 · LA FUNCIÓN
create function public.ent_anular_pedido(p_pedido bigint, p_motivo text, p_nota text default null,
                                         p_confirmar boolean default false)
returns jsonb
language plpgsql
volatile
security definer
-- ⚠️ `set search_path` NO ES DECORATIVO en una security definer (ver ent_corregir_alisto).
set search_path = public, pg_temp
as $fn$
declare
  v_quien    text := lower(btrim(coalesce(auth.jwt() ->> 'email', '')));
  v_nota     text := nullif(btrim(coalesce(p_nota, '')), '');
  v_etiqueta text;
  v_texto    text;
  v_alistos  bigint[];
  v_salidas  bigint[];
  v_x        text;
  v_n        int;
  v_id       bigint;
  v_antes    jsonb;
  v_despues  jsonb;
  v_devuelve jsonb;
  v_otros    int;
  v_fac      text;
  v_res      jsonb;
begin
  -- ── QUIÉN ──
  if v_quien = '' then
    raise exception 'sin sesion no se sabe quien anula';
  end if;
  if not acceso_es_socia() then
    raise exception 'anular un pedido es de un perfil socias';
  end if;

  -- ── QUÉ ── (el FOR UPDATE ordena dos anulaciones simultáneas del mismo pedido)
  perform 1 from ent_pedido where id = p_pedido for update;
  if not found then
    raise exception 'el pedido % no existe', p_pedido;
  end if;
  v_etiqueta := case p_motivo when 'duplicado' then 'Registrado dos veces'
                              when 'no_salio'  then 'No salió del congelador'
                              when 'datos_mal' then 'Datos equivocados'
                              when 'otro'      then 'Otro' end;
  if v_etiqueta is null then
    raise exception 'motivo invalido: %', coalesce(p_motivo, '(vacio)');
  end if;
  if p_motivo = 'otro' and length(coalesce(v_nota, '')) < 10 then
    raise exception 'con el motivo Otro hace falta explicar por que (10 letras o mas)';
  end if;
  if v_nota is not null and length(v_nota) > 500 then
    raise exception 'la nota va hasta 500 letras';
  end if;
  if exists (select 1 from ent_pedido_anulacion where pedido_id = p_pedido) then
    raise exception 'el pedido % ya esta anulado', p_pedido;
  end if;

  -- TODOS los alistos no anulados, no solo el vigente: si quedara uno viejo vivo,
  -- al anular el último ese "resucitaría" como vigente.
  select coalesce(array_agg(a.id order by a.id), '{}') into v_alistos
    from ent_alisto a
   where a.pedido_id = p_pedido and a.anulado = false
     and not exists (select 1 from ent_anulacion x where x.entidad = 'alisto' and x.entidad_id = a.id);
  if cardinality(v_alistos) = 0 then
    raise exception 'el pedido % no tiene nada vigente que anular', p_pedido;
  end if;

  -- ── LO QUE FRENA ──
  select count(*) into v_n from ent_devolucion_vigente where pedido_id = p_pedido;
  if v_n > 0 then
    raise exception 'el pedido % tiene una devolucion registrada: no se anula desde aca', p_pedido;
  end if;
  select string_agg(picking_nombre, ', ' order by id) into v_x from ent_odoo_validacion where pedido_id = p_pedido;
  if v_x is not null then
    raise exception 'ya esta validado en Odoo (%): hay que revertirlo alla antes de anular', v_x;
  end if;
  select string_agg(picking_nombre, ', ' order by id) into v_x from ent_odoo_traslado where pedido_id = p_pedido;
  if v_x is not null then
    raise exception 'ya tiene el traslado interno % en Odoo: hay que revertirlo alla antes de anular', v_x;
  end if;
  select string_agg(coalesce(h.referencia, 'sin referencia'), ', ' order by h.id) into v_x
    from ent_odoo_hecho h join ent_odoo_pendiente p on p.id = h.pendiente_id
   where p.pedido_id = p_pedido and p.tipo = 'traslado_interno';
  if v_x is not null then
    raise exception 'su traslado se marco hecho en Odoo (%): hay que revertirlo alla antes de anular', v_x;
  end if;

  select coalesce(array_agg(s.id order by s.id), '{}') into v_salidas
    from ent_salida s
   where s.alisto_id = any (v_alistos)
     and not exists (select 1 from ent_anulacion x where x.entidad = 'salida' and x.entidad_id = s.id);
  select coalesce(fv.factura_nombre, p.factura_nombre) into v_fac
    from ent_pedido p left join ent_pedido_factura_vigente fv on fv.pedido_id = p.id and fv.anulado = false
   where p.id = p_pedido;

  v_texto := 'Pedido #' || p_pedido || ' anulado · ' || v_etiqueta || coalesce(' · ' || v_nota, '');

  -- ── HACERLO, Y MEDIR. Con confirmar = false se deshace al final del bloque. ──
  begin
    select coalesce(jsonb_object_agg(producto_id || '|' || lote, uds), '{}') into v_antes
      from ent_salido_del_congelador_desde_ancla;

    insert into ent_pedido_anulacion (pedido_id, motivo, nota, alistos, salidas, creado_por)
    values (p_pedido, p_motivo, v_nota, v_alistos, v_salidas, v_quien)
    returning id into v_id;
    insert into ent_anulacion (entidad, entidad_id, motivo, creado_por)
      select 'salida', s, v_texto, v_quien from unnest(v_salidas) s;
    insert into ent_anulacion (entidad, entidad_id, motivo, creado_por)
      select 'alisto', a, v_texto, v_quien from unnest(v_alistos) a;

    -- lo que tiene que haber quedado
    select count(*) into v_n from ent_alisto_vigente where pedido_id = p_pedido;
    if v_n <> 0 then
      raise exception 'quedo un alisto vigente del pedido %: no se anulo nada', p_pedido;
    end if;
    select count(*) into v_n from ent_salida_vigente where alisto_id = any (v_alistos);
    if v_n <> 0 then
      raise exception 'quedo una salida vigente del pedido %: no se anulo nada', p_pedido;
    end if;

    -- lo que vuelve al libro: la vista ENTERA antes y después
    select coalesce(jsonb_object_agg(producto_id || '|' || lote, uds), '{}') into v_despues
      from ent_salido_del_congelador_desde_ancla;
    select coalesce(jsonb_agg(jsonb_build_object('producto_id', split_part(k, '|', 1)::int,
                                                 'lote', split_part(k, '|', 2),
                                                 'uds', (v_antes ->> k)::numeric - coalesce((v_despues ->> k)::numeric, 0))
                              order by k), '[]')
      into v_devuelve
      from jsonb_object_keys(v_antes) k
     where (v_antes ->> k)::numeric - coalesce((v_despues ->> k)::numeric, 0) <> 0;
    -- ningún lote puede SUBIR ni aparecer: anular solo devuelve
    select count(*) into v_otros
      from jsonb_object_keys(v_despues) k
     where coalesce((v_antes ->> k)::numeric, 0) < (v_despues ->> k)::numeric;
    if v_otros <> 0 or exists (select 1 from jsonb_array_elements(v_devuelve) e where (e ->> 'uds')::numeric < 0) then
      raise exception 'anular el pedido % movio lotes en la direccion equivocada: no se anulo nada', p_pedido;
    end if;

    v_res := jsonb_build_object('ok', true, 'previa', not p_confirmar, 'pedido_id', p_pedido,
               'anulacion_id', case when p_confirmar then v_id end,
               'motivo', p_motivo, 'motivo_txt', v_etiqueta, 'nota', v_nota,
               'alistos', to_jsonb(v_alistos), 'salidas', to_jsonb(v_salidas),
               'factura_nombre', v_fac, 'devuelve', v_devuelve, 'quien', v_quien);

    if not p_confirmar then
      raise exception using errcode = 'TF001', message = 'vista previa: se deshace';
    end if;
  exception when sqlstate 'TF001' then
    -- la vista previa: todo lo de arriba se deshizo; v_res queda (las variables no vuelven atrás)
    return v_res;
  end;
  return v_res;
end
$fn$;
comment on function public.ent_anular_pedido(bigint, text, text, boolean) is
  '§29 (14-oct-2026). Anula un pedido entero (alistos + salidas) y lo saca de las colas. Solo socias. '
  'confirmar=false es la vista previa: hace todo, mide y deshace. security definer para poder escribir '
  'en ent_pedido_anulacion, que no tiene política de insert.';
revoke all on function public.ent_anular_pedido(bigint, text, text, boolean) from public;
-- Supabase da EXECUTE explícito a anon en toda función nueva; `from public` no lo saca (ticket 29, §1-ter).
revoke execute on function public.ent_anular_pedido(bigint, text, text, boolean) from anon;
grant execute on function public.ent_anular_pedido(bigint, text, text, boolean) to authenticated;

-- §3 · LAS COLAS EXCLUYEN LOS ANULADOS (mismas columnas, mismo orden, security_invoker)
create or replace view public.v_ent_odoo_pendiente with (security_invoker = true) as
 SELECT id, tipo, pedido_id, devolucion_id, fecha, cliente_id, cliente_nombre, destinatario,
        factura_id, factura_nombre, nota, creado_en, creado_por
   FROM ent_odoo_pendiente p
  WHERE NOT (EXISTS ( SELECT 1 FROM ent_odoo_hecho h WHERE h.pendiente_id = p.id))
    AND NOT (EXISTS ( SELECT 1 FROM ent_pedido_anulacion a WHERE a.pedido_id = p.pedido_id));

create or replace view public.ent_salida_sin_factura with (security_invoker = true) as
 SELECT p.id, p.fecha_despacho, p.cliente_id, p.cliente_nombre, mv.motivo, p.creado_en, p.creado_por
   FROM ent_pedido p
     JOIN ent_pedido_motivo_vigente mv ON mv.pedido_id = p.id
     LEFT JOIN ent_pedido_factura_vigente v ON v.pedido_id = p.id AND v.anulado = false
  WHERE mv.motivo = 'venta'::text AND v.pedido_id IS NULL
    AND NOT (EXISTS ( SELECT 1 FROM ent_pedido_anulacion a WHERE a.pedido_id = p.id))
  ORDER BY p.fecha_despacho, p.id;

create or replace view public.ent_salida_sin_clasificar with (security_invoker = true) as
 SELECT p.id, p.fecha_despacho, p.cliente_id, p.cliente_nombre, p.creado_en, p.creado_por
   FROM ent_pedido p
     JOIN ent_pedido_motivo_vigente mv ON mv.pedido_id = p.id
  WHERE mv.motivo = 'sin_clasificar'::text
    AND NOT (EXISTS ( SELECT 1 FROM ent_pedido_anulacion a WHERE a.pedido_id = p.id))
  ORDER BY p.fecha_despacho, p.id;

-- ═══ DDL · HASTA ACA ═══

do $$
declare
  v_res jsonb := '[]'::jsonb;
  v_r   jsonb;
  v_socia text; v_equipo text; v_asist text;
  v_a bigint; v_b bigint; v_c bigint; v_d bigint; v_e bigint; v_f bigint; v_g bigint; v_h bigint; v_i bigint; v_j bigint;
  v_ali bigint; v_ali_a bigint; v_ali_g1 bigint; v_ali_g2 bigint; v_lin bigint; v_pend bigint;
  v_n1 bigint; v_n2 bigint; v_n3 bigint; v_x1 numeric; v_md5 text;
begin

  -- ── PREPARAR · los pedidos del ensayo, como postgres ──
  select email into v_socia  from v_acceso_usuario where perfil = 'socias'    and activo order by email limit 1;
  select email into v_equipo from v_acceso_usuario where perfil = 'equipo'    and activo order by email limit 1;
  select email into v_asist  from v_acceso_usuario where perfil = 'asistente' and activo order by email limit 1;
  if v_socia is null or v_equipo is null or v_asist is null then
    raise exception 'falta una identidad para ensayar (socia %, equipo %, asistente %)', v_socia is not null, v_equipo is not null, v_asist is not null;
  end if;

  -- A · regalía entregada, sin nada en Odoo, con su traslado por crear (el caso de la #195)
  insert into ent_pedido (fecha_despacho, origen, motivo, destinatario, creado_por) values (current_date, 'manual', 'regalia', 'ENSAYO', 'ensayo') returning id into v_a;
  insert into ent_alisto (pedido_id, responsable, creado_por) values (v_a, 'ensayo', 'ensayo') returning id into v_ali_a;
  insert into ent_alisto_linea (alisto_id, producto_id, cant_uds) values (v_ali_a, 452, 1) returning id into v_lin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden) values (v_lin, '281 / 7-27', 1, 1);
  insert into ent_salida (alisto_id, creado_por) values (v_ali_a, 'ensayo');
  insert into ent_odoo_pendiente (tipo, pedido_id, fecha, destinatario, creado_por) values ('traslado_interno', v_a, current_date, 'ENSAYO', 'ensayo');

  -- B · con traslado creado desde Truefie
  insert into ent_pedido (fecha_despacho, origen, motivo, destinatario, creado_por) values (current_date, 'manual', 'regalia', 'ENSAYO', 'ensayo') returning id into v_b;
  insert into ent_alisto (pedido_id, responsable, creado_por) values (v_b, 'ensayo', 'ensayo') returning id into v_ali;
  insert into ent_alisto_linea (alisto_id, producto_id, cant_uds) values (v_ali, 452, 1) returning id into v_lin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden) values (v_lin, '281 / 7-27', 1, 1);
  insert into ent_salida (alisto_id, creado_por) values (v_ali, 'ensayo');
  insert into ent_odoo_traslado (pedido_id, picking_id, picking_nombre, motivo, destino_id, contacto_id, lineas, creado_por) values (v_b, -1, 'WH/INT/ENSAYO', 'regalia', 19, 1260, '[{"ensayo": true}]', 'ensayo');

  -- C · validado en Odoo desde Truefie
  insert into ent_pedido (fecha_despacho, origen, motivo, destinatario, creado_por) values (current_date, 'manual', 'venta', 'ENSAYO', 'ensayo') returning id into v_c;
  insert into ent_alisto (pedido_id, responsable, creado_por) values (v_c, 'ensayo', 'ensayo') returning id into v_ali;
  insert into ent_alisto_linea (alisto_id, producto_id, cant_uds) values (v_ali, 452, 1) returning id into v_lin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden) values (v_lin, '281 / 7-27', 1, 1);
  insert into ent_salida (alisto_id, creado_por) values (v_ali, 'ensayo');
  insert into ent_odoo_validacion (pedido_id, factura_id, picking_id, picking_nombre, lineas, validado_por) values (v_c, 0, -2, 'WH/OUT/ENSAYO', '[{"ensayo": true}]', 'ensayo');

  -- D · con devolución
  insert into ent_pedido (fecha_despacho, origen, motivo, destinatario, creado_por) values (current_date, 'manual', 'regalia', 'ENSAYO', 'ensayo') returning id into v_d;
  insert into ent_alisto (pedido_id, responsable, creado_por) values (v_d, 'ensayo', 'ensayo') returning id into v_ali;
  insert into ent_alisto_linea (alisto_id, producto_id, cant_uds) values (v_ali, 452, 1) returning id into v_lin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden) values (v_lin, '281 / 7-27', 1, 1);
  insert into ent_salida (alisto_id, creado_por) values (v_ali, 'ensayo');
  insert into ent_devolucion (fecha, cliente_id, cliente_nombre, creado_por, pedido_id, causa) values (current_date, 0, 'ENSAYO', 'ensayo', v_d, 'producto_equivocado');

  -- E · su traslado marcado «Hecho» a mano
  insert into ent_pedido (fecha_despacho, origen, motivo, destinatario, creado_por) values (current_date, 'manual', 'regalia', 'ENSAYO', 'ensayo') returning id into v_e;
  insert into ent_alisto (pedido_id, responsable, creado_por) values (v_e, 'ensayo', 'ensayo') returning id into v_ali;
  insert into ent_alisto_linea (alisto_id, producto_id, cant_uds) values (v_ali, 452, 1) returning id into v_lin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden) values (v_lin, '281 / 7-27', 1, 1);
  insert into ent_salida (alisto_id, creado_por) values (v_ali, 'ensayo');
  insert into ent_odoo_pendiente (tipo, pedido_id, fecha, destinatario, creado_por) values ('traslado_interno', v_e, current_date, 'ENSAYO', 'ensayo') returning id into v_pend;
  insert into ent_odoo_hecho (pendiente_id, referencia, creado_por) values (v_pend, 'WH/INT/MANO', 'ensayo');

  -- F · preparado, sin salida
  insert into ent_pedido (fecha_despacho, origen, motivo, destinatario, creado_por) values (current_date, 'manual', 'regalia', 'ENSAYO', 'ensayo') returning id into v_f;
  insert into ent_alisto (pedido_id, responsable, creado_por) values (v_f, 'ensayo', 'ensayo') returning id into v_ali;
  insert into ent_alisto_linea (alisto_id, producto_id, cant_uds) values (v_ali, 452, 1) returning id into v_lin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden) values (v_lin, '281 / 7-27', 1, 1);

  -- G · dos alistos sin anular (uno viejo y el vigente): los dos tienen que caer
  insert into ent_pedido (fecha_despacho, origen, motivo, destinatario, creado_por) values (current_date, 'manual', 'regalia', 'ENSAYO', 'ensayo') returning id into v_g;
  insert into ent_alisto (pedido_id, responsable, creado_por, creado_en) values (v_g, 'ensayo', 'ensayo', now() - interval '1 hour') returning id into v_ali_g1;
  insert into ent_alisto_linea (alisto_id, producto_id, cant_uds) values (v_ali_g1, 452, 1) returning id into v_lin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden) values (v_lin, '281 / 7-27', 1, 1);
  insert into ent_salida (alisto_id, creado_por) values (v_ali_g1, 'ensayo');
  insert into ent_alisto (pedido_id, responsable, creado_por) values (v_g, 'ensayo', 'ensayo') returning id into v_ali_g2;
  insert into ent_alisto_linea (alisto_id, producto_id, cant_uds) values (v_ali_g2, 452, 1) returning id into v_lin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden) values (v_lin, '281 / 7-27', 1, 1);

  -- H · solo la cabecera, sin alisto
  insert into ent_pedido (fecha_despacho, origen, motivo, destinatario, creado_por) values (current_date, 'manual', 'regalia', 'ENSAYO', 'ensayo') returning id into v_h;

  -- I · venta sin factura vinculada · J · sin clasificar
  insert into ent_pedido (fecha_despacho, origen, motivo, destinatario, creado_por) values (current_date, 'manual', 'venta', 'ENSAYO', 'ensayo') returning id into v_i;
  insert into ent_alisto (pedido_id, responsable, creado_por) values (v_i, 'ensayo', 'ensayo') returning id into v_ali;
  insert into ent_alisto_linea (alisto_id, producto_id, cant_uds) values (v_ali, 452, 1) returning id into v_lin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden) values (v_lin, '281 / 7-27', 1, 1);
  insert into ent_salida (alisto_id, creado_por) values (v_ali, 'ensayo');
  insert into ent_pedido (fecha_despacho, origen, motivo, destinatario, creado_por) values (current_date, 'manual', 'sin_clasificar', 'ENSAYO', 'ensayo') returning id into v_j;
  insert into ent_alisto (pedido_id, responsable, creado_por) values (v_j, 'ensayo', 'ensayo') returning id into v_ali;
  insert into ent_alisto_linea (alisto_id, producto_id, cant_uds) values (v_ali, 452, 1) returning id into v_lin;
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden) values (v_lin, '281 / 7-27', 1, 1);
  insert into ent_salida (alisto_id, creado_por) values (v_ali, 'ensayo');

  -- ── S · SIN SESION (todavia como postgres) ──
  begin
    perform ent_anular_pedido(v_a, 'duplicado', null, true);
    v_res := v_res || jsonb_build_object('p', 'S1 sin sesión · anular A', 'esperado', 'RECHAZA · P0001 · sin sesion no se sabe quien anula', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'S1 sin sesión · anular A', 'esperado', 'RECHAZA · P0001 · sin sesion no se sabe quien anula', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'sin sesion no se sabe quien anula') > 0);
  end;

  -- ── De aca en adelante la RLS aplica ──
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  begin
    perform ent_anular_pedido(v_a, 'duplicado', null, true);
    v_res := v_res || jsonb_build_object('p', 'Q1 equipo · anular A', 'esperado', 'RECHAZA · P0001 · anular un pedido es de un perfil socias', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'Q1 equipo · anular A', 'esperado', 'RECHAZA · P0001 · anular un pedido es de un perfil socias', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'anular un pedido es de un perfil socias') > 0);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_asist, 'role', 'authenticated')::text, true);
  begin
    perform ent_anular_pedido(v_a, 'duplicado', null, true);
    v_res := v_res || jsonb_build_object('p', 'Q2 asistente · anular A', 'esperado', 'RECHAZA · P0001 · anular un pedido es de un perfil socias', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'Q2 asistente · anular A', 'esperado', 'RECHAZA · P0001 · anular un pedido es de un perfil socias', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'anular un pedido es de un perfil socias') > 0);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);

  -- ── N · LO QUE FRENA, como socia ──
  begin
    perform ent_anular_pedido(v_a, 'x', null, true);
    v_res := v_res || jsonb_build_object('p', 'N1 motivo inválido', 'esperado', 'RECHAZA · P0001 · motivo invalido: x', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N1 motivo inválido', 'esperado', 'RECHAZA · P0001 · motivo invalido: x', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'motivo invalido: x') > 0);
  end;
  begin
    perform ent_anular_pedido(v_a, 'otro', null, true);
    v_res := v_res || jsonb_build_object('p', 'N2 «Otro» sin texto', 'esperado', 'RECHAZA · P0001 · con el motivo Otro hace falta explicar por que', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N2 «Otro» sin texto', 'esperado', 'RECHAZA · P0001 · con el motivo Otro hace falta explicar por que', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'con el motivo Otro hace falta explicar por que') > 0);
  end;
  begin
    perform ent_anular_pedido(v_a, 'otro', 'corto', true);
    v_res := v_res || jsonb_build_object('p', 'N3 «Otro» con 5 letras', 'esperado', 'RECHAZA · P0001 · con el motivo Otro hace falta explicar por que', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N3 «Otro» con 5 letras', 'esperado', 'RECHAZA · P0001 · con el motivo Otro hace falta explicar por que', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'con el motivo Otro hace falta explicar por que') > 0);
  end;
  begin
    perform ent_anular_pedido(999999999, 'duplicado', null, true);
    v_res := v_res || jsonb_build_object('p', 'N4 pedido inexistente', 'esperado', 'RECHAZA · P0001 · el pedido 999999999 no existe', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N4 pedido inexistente', 'esperado', 'RECHAZA · P0001 · el pedido 999999999 no existe', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'el pedido 999999999 no existe') > 0);
  end;
  begin
    perform ent_anular_pedido(v_b, 'duplicado', null, true);
    v_res := v_res || jsonb_build_object('p', 'N5 B · traslado creado desde Truefie', 'esperado', 'RECHAZA · P0001 · ya tiene el traslado interno WH/INT/ENSAYO en Odoo', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N5 B · traslado creado desde Truefie', 'esperado', 'RECHAZA · P0001 · ya tiene el traslado interno WH/INT/ENSAYO en Odoo', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'ya tiene el traslado interno WH/INT/ENSAYO en Odoo') > 0);
  end;
  begin
    perform ent_anular_pedido(v_c, 'duplicado', null, true);
    v_res := v_res || jsonb_build_object('p', 'N6 C · validado en Odoo', 'esperado', 'RECHAZA · P0001 · ya esta validado en Odoo (WH/OUT/ENSAYO)', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N6 C · validado en Odoo', 'esperado', 'RECHAZA · P0001 · ya esta validado en Odoo (WH/OUT/ENSAYO)', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'ya esta validado en Odoo (WH/OUT/ENSAYO)') > 0);
  end;
  begin
    perform ent_anular_pedido(v_d, 'duplicado', null, true);
    v_res := v_res || jsonb_build_object('p', 'N7 D · con devolución', 'esperado', 'RECHAZA · P0001 · tiene una devolucion registrada', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N7 D · con devolución', 'esperado', 'RECHAZA · P0001 · tiene una devolucion registrada', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'tiene una devolucion registrada') > 0);
  end;
  begin
    perform ent_anular_pedido(v_e, 'duplicado', null, true);
    v_res := v_res || jsonb_build_object('p', 'N8 E · traslado marcado «Hecho» a mano', 'esperado', 'RECHAZA · P0001 · su traslado se marco hecho en Odoo (WH/INT/MANO)', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N8 E · traslado marcado «Hecho» a mano', 'esperado', 'RECHAZA · P0001 · su traslado se marco hecho en Odoo (WH/INT/MANO)', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'su traslado se marco hecho en Odoo (WH/INT/MANO)') > 0);
  end;
  begin
    perform ent_anular_pedido(v_h, 'duplicado', null, true);
    v_res := v_res || jsonb_build_object('p', 'N9 H · sin alisto', 'esperado', 'RECHAZA · P0001 · no tiene nada vigente que anular', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N9 H · sin alisto', 'esperado', 'RECHAZA · P0001 · no tiene nada vigente que anular', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'no tiene nada vigente que anular') > 0);
  end;

  -- ── V · VISTA PREVIA de A: dice lo que pasaría y NO deja nada ──
  v_x1 := (select coalesce(sum(uds),0) from ent_salido_del_congelador_desde_ancla where producto_id = 452 and lote = '281 / 7-27');
  begin
    v_r := ent_anular_pedido(v_a, 'duplicado', null, false);
    v_res := v_res || jsonb_build_object('p', 'V1 previa de A (duplicado)', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'V1 previa de A (duplicado)', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  v_res := v_res || jsonb_build_object('p', 'V2 previa · devuelve', 'esperado', 'previa · Semillas 281 / 7-27 · 1 u', 'obtenido', coalesce((v_r ->> 'previa') || ' · ' || (v_r -> 'devuelve')::text, 'null'), 'ok', coalesce((v_r ->> 'previa')::boolean and (v_r -> 'devuelve') = '[{"producto_id": 452, "lote": "281 / 7-27", "uds": 1}]'::jsonb, false));
  select count(*) into v_n1 from ent_pedido_anulacion where pedido_id = v_a;
  select count(*) into v_n2 from ent_alisto_vigente where pedido_id = v_a;
  select count(*) into v_n3 from v_ent_odoo_pendiente where pedido_id = v_a;
  v_res := v_res || jsonb_build_object('p', 'V3 después de la previa · anulaciones · alisto vigente · en la cola · lote 281', 'esperado', '0 · 1 · 1 · sin cambio', 'obtenido', v_n1 || ' · ' || v_n2 || ' · ' || v_n3 || ' · ' || case when (select coalesce(sum(uds),0) from ent_salido_del_congelador_desde_ancla where producto_id = 452 and lote = '281 / 7-27') = v_x1 then 'sin cambio' else 'CAMBIO' end, 'ok', coalesce(v_n1 = 0 and v_n2 = 1 and v_n3 = 1 and (select coalesce(sum(uds),0) from ent_salido_del_congelador_desde_ancla where producto_id = 452 and lote = '281 / 7-27') = v_x1, false));

  -- ── R · ANULAR A DE VERDAD ──
  v_x1 := (select coalesce(sum(uds),0) from ent_salido_del_congelador_desde_ancla where producto_id = 452 and lote = '281 / 7-27'); v_md5 := (select md5(coalesce(string_agg(producto_id||'|'||lote||'|'||uds, ',' order by producto_id, lote),'')) from ent_salido_del_congelador_desde_ancla where (producto_id, lote) <> (452, '281 / 7-27'));
  begin
    v_r := ent_anular_pedido(v_a, 'duplicado', 'ensayo: registrado dos veces', true);
    v_res := v_res || jsonb_build_object('p', 'R1 anular A (duplicado)', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R1 anular A (duplicado)', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  v_res := v_res || jsonb_build_object('p', 'R2 respuesta · previa · anulacion_id', 'esperado', 'false · con id', 'obtenido', coalesce((v_r ->> 'previa') || ' · ' || coalesce(v_r ->> 'anulacion_id', 'sin id'), 'null'), 'ok', coalesce(not (v_r ->> 'previa')::boolean and (v_r ->> 'anulacion_id') is not null, false));
  select count(*) into v_n1 from ent_pedido_anulacion where pedido_id = v_a and creado_por = lower(v_socia) and motivo = 'duplicado' and alistos = array[v_ali_a] and cardinality(salidas) = 1;
  select count(*) into v_n2 from ent_anulacion x where x.creado_por = lower(v_socia) and ((x.entidad = 'alisto' and x.entidad_id = v_ali_a) or (x.entidad = 'salida' and x.entidad_id in (select id from ent_salida where alisto_id = v_ali_a)));
  v_res := v_res || jsonb_build_object('p', 'R3 quién sale de la sesión · ent_pedido_anulacion · ent_anulacion', 'esperado', '1 · 2', 'obtenido', v_n1 || ' · ' || v_n2, 'ok', coalesce(v_n1 = 1 and v_n2 = 2, false));
  select count(*) into v_n1 from ent_alisto_vigente where pedido_id = v_a;
  select count(*) into v_n2 from v_ent_pedido_estado where pedido_id = v_a;
  select count(*) into v_n3 from v_ent_odoo_pendiente where pedido_id = v_a;
  v_res := v_res || jsonb_build_object('p', 'R4 alisto vigente · historial · cola de Odoo', 'esperado', '0 · 0 · 0', 'obtenido', v_n1 || ' · ' || v_n2 || ' · ' || v_n3, 'ok', coalesce(v_n1 = 0 and v_n2 = 0 and v_n3 = 0, false));
  v_res := v_res || jsonb_build_object('p', 'R5 lote 281 vuelve 1 u · el resto igual', 'esperado', '1 · igual', 'obtenido', (v_x1 - (select coalesce(sum(uds),0) from ent_salido_del_congelador_desde_ancla where producto_id = 452 and lote = '281 / 7-27')) || ' · ' || case when (select md5(coalesce(string_agg(producto_id||'|'||lote||'|'||uds, ',' order by producto_id, lote),'')) from ent_salido_del_congelador_desde_ancla where (producto_id, lote) <> (452, '281 / 7-27')) = v_md5 then 'igual' else 'CAMBIO' end, 'ok', coalesce(v_x1 - (select coalesce(sum(uds),0) from ent_salido_del_congelador_desde_ancla where producto_id = 452 and lote = '281 / 7-27') = 1 and (select md5(coalesce(string_agg(producto_id||'|'||lote||'|'||uds, ',' order by producto_id, lote),'')) from ent_salido_del_congelador_desde_ancla where (producto_id, lote) <> (452, '281 / 7-27')) = v_md5, false));
  begin
    perform ent_anular_pedido(v_a, 'duplicado', null, true);
    v_res := v_res || jsonb_build_object('p', 'R6 anular A otra vez', 'esperado', 'RECHAZA · P0001 · ya esta anulado', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'R6 anular A otra vez', 'esperado', 'RECHAZA · P0001 · ya esta anulado', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'ya esta anulado') > 0);
  end;

  -- ── O · LOS OTROS CASOS QUE SÍ SE ANULAN ──
  begin
    v_r := ent_anular_pedido(v_f, 'no_salio', null, true);
    v_res := v_res || jsonb_build_object('p', 'O1 F · preparado sin salida (no salió)', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'O1 F · preparado sin salida (no salió)', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  v_res := v_res || jsonb_build_object('p', 'O2 F · salidas · devuelve', 'esperado', '[] · 1 u', 'obtenido', coalesce((v_r -> 'salidas')::text || ' · ' || (v_r -> 'devuelve')::text, 'null'), 'ok', coalesce((v_r -> 'salidas') = '[]'::jsonb and jsonb_array_length(v_r -> 'devuelve') = 1 and (v_r -> 'devuelve' -> 0 ->> 'uds')::numeric = 1, false));
  begin
    v_r := ent_anular_pedido(v_g, 'otro', 'ensayo: dos alistos vivos', true);
    v_res := v_res || jsonb_build_object('p', 'O3 G · «Otro» con texto', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'O3 G · «Otro» con texto', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  select count(*) into v_n1 from ent_alisto_vigente where pedido_id = v_g;
  v_res := v_res || jsonb_build_object('p', 'O4 G · los dos alistos anulados · alisto vigente', 'esperado', '2 · 0', 'obtenido', coalesce(jsonb_array_length(v_r -> 'alistos'), -1) || ' · ' || v_n1, 'ok', coalesce(jsonb_array_length(v_r -> 'alistos') = 2 and v_n1 = 0, false));
  select count(*) into v_n1 from ent_salida_sin_factura where id = v_i;
  select count(*) into v_n2 from ent_salida_sin_clasificar where id = v_j;
  v_res := v_res || jsonb_build_object('p', 'O5 I y J figuran antes de anular', 'esperado', '1 · 1', 'obtenido', v_n1 || ' · ' || v_n2, 'ok', coalesce(v_n1 = 1 and v_n2 = 1, false));
  begin
    v_r := ent_anular_pedido(v_i, 'datos_mal', null, true);
    v_res := v_res || jsonb_build_object('p', 'O6 I · datos equivocados', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'O6 I · datos equivocados', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  begin
    v_r := ent_anular_pedido(v_j, 'duplicado', null, true);
    v_res := v_res || jsonb_build_object('p', 'O7 J · registrado dos veces', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'O7 J · registrado dos veces', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  select count(*) into v_n1 from ent_salida_sin_factura where id = v_i;
  select count(*) into v_n2 from ent_salida_sin_clasificar where id = v_j;
  v_res := v_res || jsonb_build_object('p', 'O8 I y J ya no figuran', 'esperado', '0 · 0', 'obtenido', v_n1 || ' · ' || v_n2, 'ok', coalesce(v_n1 = 0 and v_n2 = 0, false));

  -- ── U · APPEND-ONLY: nadie escribe directo en la tabla ──
  begin
    insert into ent_pedido_anulacion (pedido_id, motivo, alistos, salidas, creado_por) values (v_h, 'duplicado', array[1], '{}', v_socia);
    v_res := v_res || jsonb_build_object('p', 'U1 socia · insert directo', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_pedido_anulacion', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'U1 socia · insert directo', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_pedido_anulacion', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table ent_pedido_anulacion') > 0);
  end;
  begin
    update ent_pedido_anulacion set nota = 'otra' where pedido_id = v_a;
    v_res := v_res || jsonb_build_object('p', 'U2 socia · update', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_pedido_anulacion', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'U2 socia · update', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_pedido_anulacion', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table ent_pedido_anulacion') > 0);
  end;
  begin
    delete from ent_pedido_anulacion where pedido_id = v_a;
    v_res := v_res || jsonb_build_object('p', 'U3 socia · delete', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_pedido_anulacion', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'U3 socia · delete', 'esperado', 'RECHAZA · 42501 · permission denied for table ent_pedido_anulacion', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table ent_pedido_anulacion') > 0);
  end;

  -- ── P · anon no toca nada (al final: cambia el rol) ──
  select count(*) into v_n1 from unnest(array['public.ent_pedido_anulacion']) t
   where has_table_privilege('anon', t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE');
  v_res := v_res || jsonb_build_object('p', 'P1 anon: permisos sobre la tabla · EXECUTE de la función', 'esperado', '0 · false', 'obtenido', v_n1 || ' · ' || has_function_privilege('anon', 'public.ent_anular_pedido(bigint,text,text,boolean)', 'EXECUTE'), 'ok', coalesce(v_n1 = 0 and not has_function_privilege('anon', 'public.ent_anular_pedido(bigint,text,text,boolean)', 'EXECUTE'), false));
  perform set_config('role', 'anon', true);
  begin
    perform ent_anular_pedido(v_h, 'duplicado', null, true);
    v_res := v_res || jsonb_build_object('p', 'P2 anon · llamar la función', 'esperado', 'RECHAZA · 42501 · permission denied for function ent_anular_pedido', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'P2 anon · llamar la función', 'esperado', 'RECHAZA · 42501 · permission denied for function ent_anular_pedido', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for function ent_anular_pedido') > 0);
  end;

  perform set_config('ensayo.res', v_res::text, true);
end $$;


-- ── EL RESULTADO. Esta tabla ES el ensayo. ────────────────────────────────
-- ESPERADO: 34 filas, todas con ok = true.
select r.p as prueba, r.esperado, r.obtenido, r.ok
  from jsonb_to_recordset(current_setting('ensayo.res')::jsonb)
       as r(p text, esperado text, obtenido text, ok boolean);

rollback;
