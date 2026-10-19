-- ═══════════════════════════════════════════════════════════════════════════
-- ENTREGAS_ANULAR_PEDIDO.sql · 14-oct-2026 · ANULAR UN PEDIDO ENTERO (§29)
-- ESTE ARCHIVO ES EL PEGADO. Escribe y termina en COMMIT.
-- ✅ APLICADO el 14-oct-2026 por Andrea: 1 · true · 6 · true · false · true · false · 3 · 1
--    (cola_odoo 1 = el traslado del pedido #198, entrado a las 10:33 CR: real, ajeno a esto).
--    VERIFICADO DESDE AFUERA con pg_lector: tabla con 0 filas y sus 6 políticas;
--    función security definer con search_path fijo, EXECUTE solo postgres/authenticated/
--    service_role (anon NO); authenticated solo SELECT en la tabla; las tres vistas con
--    security_invoker; ningún pedido de ensayo quedó.
-- ⚠️ No pegar sin que antes ENSAYO_ANULAR_PEDIDO.sql haya dado todas sus filas
--    con ok = true. El ensayo copia el bloque DDL de acá BYTE A BYTE
--    (herramientas/ensayos/armar_ensayo_anular_pedido.py).
--
-- QUÉ PASÓ
--   El 14-oct una regalía se registró dos veces (#194 y #195) y la #195 se anuló
--   con SQL a mano (PEGADO_ANULAR_PEDIDO_195.sql). No había forma de hacerlo
--   desde la pantalla: «Sale otro día» anula solo la salida (el producto queda
--   apartado) y no cierra la cola de Odoo. ENTREGAS_PENDIENTES.md §29.
--
-- DECISIONES DE ANDREA (14-oct)
--   · Solo socias. Motivo de una lista corta; el texto es obligatorio SOLO con
--     «Otro» (10 letras o más), opcional con los demás. Queda quién y cuándo.
--     Append-only: nada se borra ni se edita.
--   · Sin nada en Odoo: anula alisto + salida (los lotes vuelven al libro) y el
--     pedido sale de la cola de Odoo, en un paso.
--   · Con algo en Odoo registrado desde Truefie (validación, traslado, o su
--     traslado marcado «Hecho» a mano): NO deja anular; el error dice el número
--     para revertirlo allá. La reversión automática queda para después.
--   · Pedido con factura y WH/OUT sin validar: se puede anular, y la PANTALLA
--     avisa que la factura sigue en Odoo (si no hubo entrega, va NC). Lo que
--     bloquea es el movimiento de inventario, no la factura.
--     ⚠️ La base NO ve Odoo: el WH/OUT validado A MANO en Odoo (sin pasar por
--     Truefie) lo mira la pantalla, por el proxy de lectura. Esta función solo
--     conoce los rastros de Truefie.
--
-- QUÉ CREA
--   1. ent_pedido_anulacion: una fila por pedido anulado (UNIQUE pedido_id).
--      Quién = el correo de la SESIÓN (auth.jwt()), no lo elige el navegador.
--   2. ent_anular_pedido(pedido, motivo, nota, confirmar): security definer.
--      confirmar=false → VISTA PREVIA: hace todo, mide lo que vuelve al libro,
--      y DESHACE (excepción atrapada = savepoint). Mismo código que el real:
--      la previa no puede decir algo distinto de lo que después pasa.
--   3. v_ent_odoo_pendiente, ent_salida_sin_factura y ent_salida_sin_clasificar
--      excluyen los pedidos anulados. Las dos últimas leían ent_pedido directo:
--      un pedido anulado seguía figurando ahí.
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

-- CONTROL, adentro de la transacción y justo antes del commit (regla de la casa).
select (select count(*) from pg_class where oid = to_regclass('public.ent_pedido_anulacion'))      as tabla,
       (select relrowsecurity from pg_class where oid = to_regclass('public.ent_pedido_anulacion')) as rls,
       (select count(*) from pg_policy where polrelid = to_regclass('public.ent_pedido_anulacion'))  as politicas,
       (select prosecdef from pg_proc where oid = to_regproc('public.ent_anular_pedido'))           as definer,
       has_function_privilege('anon', 'public.ent_anular_pedido(bigint,text,text,boolean)', 'EXECUTE')          as anon_ejecuta,
       has_function_privilege('authenticated', 'public.ent_anular_pedido(bigint,text,text,boolean)', 'EXECUTE') as auth_ejecuta,
       has_table_privilege('authenticated', 'public.ent_pedido_anulacion', 'INSERT')                as auth_inserta,
       (select count(*) from pg_class where relname in ('v_ent_odoo_pendiente','ent_salida_sin_factura','ent_salida_sin_clasificar')
           and reloptions @> array['security_invoker=true'])                                       as vistas_invoker,
       (select count(*) from v_ent_odoo_pendiente)                                                  as cola_odoo;
-- ESPERADO: 1 · true · 6 · true · false · true · false · 3 · 0
--   (cola_odoo 0 = la cola de hoy, vacía desde la anulación de la #195; si entró
--    un traslado nuevo en el medio, es otro número y está bien)

commit;

-- ═══ ESTA ES LA TABLA QUE VAS A VER · ya con el commit hecho (el editor muestra solo la última) ═══
select (select count(*) from pg_class where oid = to_regclass('public.ent_pedido_anulacion'))      as tabla,
       (select relrowsecurity from pg_class where oid = to_regclass('public.ent_pedido_anulacion')) as rls,
       (select count(*) from pg_policy where polrelid = to_regclass('public.ent_pedido_anulacion'))  as politicas,
       (select prosecdef from pg_proc where oid = to_regproc('public.ent_anular_pedido'))           as definer,
       has_function_privilege('anon', 'public.ent_anular_pedido(bigint,text,text,boolean)', 'EXECUTE')          as anon_ejecuta,
       has_function_privilege('authenticated', 'public.ent_anular_pedido(bigint,text,text,boolean)', 'EXECUTE') as auth_ejecuta,
       has_table_privilege('authenticated', 'public.ent_pedido_anulacion', 'INSERT')                as auth_inserta,
       (select count(*) from pg_class where relname in ('v_ent_odoo_pendiente','ent_salida_sin_factura','ent_salida_sin_clasificar')
           and reloptions @> array['security_invoker=true'])                                       as vistas_invoker,
       (select count(*) from v_ent_odoo_pendiente)                                                  as cola_odoo;
-- ESPERADO: 1 · true · 6 · true · false · true · false · 3 · 0
