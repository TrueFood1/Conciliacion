-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_DEVOLUCION_CAMBIO.sql  ·  30-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Prueba CAMBIO_DEVOLUCION_CAMBIO.sql entero (copia LITERAL de su bloque DDL, extraida por
-- las marcas ▼▼▼/▲▲▲, no por numero de linea) con los roles reales, y lo deshace (rollback).
-- ⛔ NO CORRIDO EN PRODUCCION. Este header se cambia DESPUES de correrlo.
-- ✅ CORRIDO en Postgres 17 local (espejo del respaldo del 23-oct, con los event triggers
--    asistente_politicas y ensure_rls, y los grants por defecto de Supabase repuestos):
--    35 de 35 ok = true, con Instinct presente. Y CAMBIO_DEVOLUCION_CAMBIO.sql aplicado en
--    una copia del espejo dio la fila de control 1 · 2 · 1 · 7 · 1 · 1 · f · 0, y re-pegado
--    grito en la guarda sin escribir nada. Eso NO reemplaza la corrida en produccion.
--
-- COMO SE LEE
--   Una tabla con TODAS las filas en ok = true. Un RECHAZA da ok solo si el SQLSTATE
--   esperado es el que salio (no vale rechazar por el motivo de al lado).
--   42501 = RLS o sin permiso · 23514 = check.
--   Si el editor dice "Success. No rows returned", no llego al final y no vale.
--
-- QUIEN ES QUIEN (de v_acceso_usuario, activos):
--   equipo  = Daniel si esta (danielnu…), si no el primero de perfil 'equipo'.
--   socia   = la primera de perfil 'socias'.
--   asist.  = Instinct (perfil 'asistente'); si no hay, A1 no corre.
--   Los lotes 993-999 / 9-99 NO existen: no tocan el saldo de ningun lote real.
--
-- ⚠️ SECUENCIAS: `nextval` no se deshace con el rollback. ent_devolucion,
--   ent_devolucion_linea, ent_odoo_pendiente y ent_anulacion van a quedar con ids
--   salteados. Es cosmetico (ya paso el 16-sep).
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE DDL ▼▼▼  (ENSAYO_DEVOLUCION_CAMBIO.sql lleva una copia literal)
do $$ begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'ent_devolucion'
                and column_name = 'resolucion') then
    raise exception 'ent_devolucion.resolucion ya existe: este archivo no se vuelve a pegar';
  end if;
  if to_regclass('public.ent_devolucion_reemplazo') is not null
     or to_regclass('public.ent_reemplazo_desde_ancla') is not null then
    raise exception 'ent_devolucion_reemplazo o ent_reemplazo_desde_ancla ya existen: este archivo no se vuelve a pegar';
  end if;
end $$;

-- ── §A · QUE SE HIZO CON LA DEVOLUCION ──────────────────────────────────
-- NOT NULL con default: las filas de hoy fueron todas devoluciones con NC, y
-- quedan dichas asi. La pantalla de Daniel siempre la escribe explicita.
alter table public.ent_devolucion
  add column resolucion text not null default 'devolucion';
alter table public.ent_devolucion
  add constraint ent_devolucion_resolucion_ok check (resolucion in ('devolucion','cambio'));

comment on column public.ent_devolucion.resolucion is
  'devolucion = vuelve al lote y lleva nota de credito. cambio = vuelve al lote y sale '
  'otro del mismo producto (ent_devolucion_reemplazo); sin NC y sin traslado interno. '
  'Por devolucion entera: una mixta se registra como dos. Desde el 30-oct-2026.';

-- ── §B · LA VISTA VIGENTE LA EXPONE, AL FINAL ───────────────────────────
-- Postgres deja AGREGAR columnas al final de una vista con dependientes, pero no
-- quitar ni reordenar: `ent_devuelto_desde_ancla` y `v_ent_devolucion_exceso`
-- cuelgan de esta. El cuerpo es copia literal de CAMBIO_DEVOLUCIONES.sql §A
-- (verificado contra el respaldo del 23-oct), mas la columna nueva.
create or replace view public.ent_devolucion_vigente with (security_invoker = true) as
  select d.id as devolucion_id, d.fecha, d.recibido_en, d.cliente_id,
         d.cliente_nombre, d.nota, d.creado_en, d.creado_por,
         d.pedido_id,
         d.causa,
         d.resolucion                                            -- NUEVO, al final
    from public.ent_devolucion d
   where not exists (select 1 from public.ent_anulacion x
                      where x.entidad = 'devolucion' and x.entidad_id = d.id);

-- ── §C · LO QUE SALE EN LUGAR DE LO DEVUELTO ────────────────────────────
-- Misma forma que ent_devolucion_linea, y por la misma razon: producto, lote,
-- cuanto, en que unidad. El lote en FORMA CANONICA (la clave del saldo es
-- `producto|lote` como texto).
-- ⚠️ EL CANDADO DE ESCALA ES NUEVO y es la regla de las unidades puesta en la base:
-- `cant_uds = cant_uom / uom_factor`. 1 paquete de Buns = cant_uom 1, factor 0.25,
-- cant_uds 4. Si la pantalla guardara "1" en cant_uds, el saldo bajaria un cuarto de
-- lo que salio y nadie lo veria — es el error de escala del lote 191.
create table public.ent_devolucion_reemplazo (
  id            bigint  generated always as identity primary key,
  devolucion_id bigint  not null references public.ent_devolucion(id),
  producto_id   integer not null,
  lote          text    not null check (lote ~ '^\d{1,3} / \d{1,2}-\d{2}$'),
  cant_uds      numeric not null check (cant_uds > 0),
  uom_id        integer not null,
  uom_nombre    text    not null,
  cant_uom      numeric not null check (cant_uom > 0),
  uom_factor    numeric not null check (uom_factor > 0),
  creado_en     timestamptz not null default now(),
  constraint ent_devolucion_reemplazo_escala_ok
    check (abs(cant_uds - cant_uom / uom_factor) < 0.001)
);
create index ent_devolucion_reemplazo_dev_idx  on public.ent_devolucion_reemplazo (devolucion_id);
create index ent_devolucion_reemplazo_lote_idx on public.ent_devolucion_reemplazo (producto_id, lote);

comment on table public.ent_devolucion_reemplazo is
  'Lo que sale del congelador en un CAMBIO, en lugar de lo devuelto. Resta al saldo '
  'por lote (ent_reemplazo_desde_ancla). Cuelga de la devolucion: anularla lo deshace.';

-- RLS: select + insert, y el insert SOLO contra una devolucion que es cambio y SOLO
-- del mismo producto que volvio ("cambio por otro del MISMO producto").
-- ⚠️ `revoke all` primero: Supabase da por defecto los siete privilegios a anon y
-- authenticated sobre toda tabla nueva, y un `grant` agrega, no revoca (la deuda
-- medida en CAMBIO_DEVOLUCIONES.sql §C). Esta tabla nace cerrada.
-- Las cinco politicas del asistente las pone sola `asistente_politicas` (event trigger).
alter table public.ent_devolucion_reemplazo enable row level security;
revoke all on public.ent_devolucion_reemplazo from anon, authenticated;
grant select, insert on public.ent_devolucion_reemplazo to authenticated;

create policy ent_devolucion_reemplazo_sel on public.ent_devolucion_reemplazo
  for select to authenticated using (true);
create policy ent_devolucion_reemplazo_ins on public.ent_devolucion_reemplazo
  for insert to authenticated
  with check (
        exists (select 1 from public.ent_devolucion d
                 where d.id = ent_devolucion_reemplazo.devolucion_id
                   and d.resolucion = 'cambio')
    and exists (select 1 from public.ent_devolucion_linea dl
                 where dl.devolucion_id = ent_devolucion_reemplazo.devolucion_id
                   and dl.producto_id   = ent_devolucion_reemplazo.producto_id));

-- ── §D · LO QUE EL REEMPLAZO RESTA AL SALDO ─────────────────────────────
-- Mismo criterio que ent_devuelto_desde_ancla, y por eso sale de la MISMA vista
-- vigente con el MISMO corte: solo lo posterior al ancla (lo anterior ya esta en la
-- foto del conteo), y una devolucion anulada deja de restar sola.
-- La lee `_rpCalcularPuntas` y la resta. Si nadie la leyera, esquema_check no
-- subiria de numero — ver CLAUDE.md, "un esquema que no lee nadie esta muerto".
create view public.ent_reemplazo_desde_ancla with (security_invoker = true) as
  select r.lote, r.producto_id, sum(r.cant_uds) as uds
    from public.ent_devolucion_reemplazo r
    join public.ent_devolucion_vigente   dv on dv.devolucion_id = r.devolucion_id
   where dv.recibido_en > (select corte from public.ent_ancla)
   group by r.lote, r.producto_id;

revoke all on public.ent_reemplazo_desde_ancla from anon, authenticated;
grant select on public.ent_reemplazo_desde_ancla to authenticated;

comment on view public.ent_reemplazo_desde_ancla is
  'Lo que salio en CAMBIOS despues del corte. Resta: disponible = ancla + correcciones '
  '+ produccion - salidas + devoluciones - reemplazos - merma.';

-- ── §E · UNA DEVOLUCION QUE ES CAMBIO NO LLEVA PENDIENTE DE ODOO ─────────
-- Ni NC (la factura quedo bien: el cliente se quedo con lo que pago) ni traslado
-- (en Odoo no cambio nada neto). La pantalla ya no lo pide; esto es la red para el
-- dia que otra pantalla, o un ajuste a esta, se olvide.
-- Hasta hoy la politica era `with check (true)`. La condicion nueva solo mira las
-- filas con `devolucion_id` de un CAMBIO: la NC de una devolucion comun y el
-- traslado de una salida sin factura (devolucion_id null) entran igual que antes.
-- Sin `if exists` en el drop: si la politica no estuviera, algo no es lo que se cree,
-- y es mejor que grite.
drop policy ent_odoo_pendiente_ins on public.ent_odoo_pendiente;
create policy ent_odoo_pendiente_ins on public.ent_odoo_pendiente
  for insert to authenticated
  with check (not exists (select 1 from public.ent_devolucion d
                           where d.id = ent_odoo_pendiente.devolucion_id
                             and d.resolucion = 'cambio'));
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

do $$
declare
  v_socia text; v_equipo text; v_asis text; v_ped bigint; v_dc bigint; v_dd bigint;
  v_n int; v_txt text;
  v_res jsonb := '[]'::jsonb;
begin
  select email into v_equipo from v_acceso_usuario
   where perfil = 'equipo' and activo order by (email like 'danielnu%') desc, id limit 1;
  select email into v_socia from v_acceso_usuario where perfil = 'socias' and activo order by id limit 1;
  select email into v_asis  from v_acceso_usuario where perfil = 'asistente' and activo order by id limit 1;
  select max(id) into v_ped from ent_pedido;
  if v_socia is null or v_equipo is null or v_ped is null then
    raise exception 'el ensayo necesita una socia, alguien de equipo y un pedido (socia %, equipo %, pedido %)', v_socia, v_equipo, v_ped;
  end if;

  -- ── EQUIPO (Daniel): registra un CAMBIO ──
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, causa, creado_por, resolucion) values (current_date, -1, 'ENSAYO', v_ped, 'producto_equivocado', v_equipo, 'cambio') returning id into v_dc;
    v_res := v_res || jsonb_build_object('p','E1 equipo registra una devolución CAMBIO','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E1 equipo registra una devolución CAMBIO','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ent_devolucion_linea (devolucion_id, producto_id, lote, cant_uds, uom_id, uom_nombre, cant_uom, uom_factor) values (v_dc, 503, '999 / 9-99', 4, 0, 'Paquete de 4', 1, 0.25);
    v_res := v_res || jsonb_build_object('p','E2 equipo: lo que volvió (1 paq Buns, lote 999)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E2 equipo: lo que volvió (1 paq Buns, lote 999)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ent_devolucion_reemplazo (devolucion_id, producto_id, lote, cant_uds, uom_id, uom_nombre, cant_uom, uom_factor) values (v_dc, 503, '998 / 9-99', 4, 0, 'Paquete de 4', 1, 0.25);
    v_res := v_res || jsonb_build_object('p','E3 equipo: lo que sale en su lugar (1 paq Buns, lote 998)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E3 equipo: lo que sale en su lugar (1 paq Buns, lote 998)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_txt := coalesce((select uds from ent_reemplazo_desde_ancla where producto_id = 503 and lote = '998 / 9-99')::text, 'null');
    v_res := v_res || jsonb_build_object('p','E4 el reemplazo RESTA: ent_reemplazo_desde_ancla 503|998 (uds)','esperado','4','obtenido',v_txt,'ok',v_txt='4');
  exception when others then
    v_res := v_res || jsonb_build_object('p','E4 el reemplazo RESTA: ent_reemplazo_desde_ancla 503|998 (uds)','esperado','4','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_txt := coalesce((select uds from ent_devuelto_desde_ancla where producto_id = 503 and lote = '999 / 9-99')::text, 'null');
    v_res := v_res || jsonb_build_object('p','E5 lo devuelto SUMA igual: ent_devuelto_desde_ancla 503|999 (uds)','esperado','4','obtenido',v_txt,'ok',v_txt='4');
  exception when others then
    v_res := v_res || jsonb_build_object('p','E5 lo devuelto SUMA igual: ent_devuelto_desde_ancla 503|999 (uds)','esperado','4','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_txt := coalesce((select resolucion from ent_devolucion_vigente where devolucion_id = v_dc)::text, 'null');
    v_res := v_res || jsonb_build_object('p','E6 la vigente expone resolucion','esperado','cambio','obtenido',v_txt,'ok',v_txt='cambio');
  exception when others then
    v_res := v_res || jsonb_build_object('p','E6 la vigente expone resolucion','esperado','cambio','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ent_odoo_pendiente (tipo, pedido_id, devolucion_id, fecha, cliente_id, cliente_nombre, factura_id, factura_nombre, creado_por) values ('nota_credito', v_ped, v_dc, current_date, -1, 'ENSAYO', -1, 'ENSAYO', v_equipo);
    v_res := v_res || jsonb_build_object('p','E7 equipo: NC para un CAMBIO','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E7 equipo: NC para un CAMBIO','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_odoo_pendiente (tipo, pedido_id, devolucion_id, fecha, destinatario, nota, creado_por) values ('traslado_interno', v_ped, v_dc, current_date, 'ENSAYO', 'reposicion', v_equipo);
    v_res := v_res || jsonb_build_object('p','E8 equipo: traslado interno colgado de un CAMBIO','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E8 equipo: traslado interno colgado de un CAMBIO','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_devolucion_reemplazo (devolucion_id, producto_id, lote, cant_uds, uom_id, uom_nombre, cant_uom, uom_factor) values (v_dc, 451, '998 / 9-99', 4, 0, 'Paquete de 4', 1, 0.25);
    v_res := v_res || jsonb_build_object('p','E9 equipo: reemplazo de OTRO producto (Blanco 451)','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E9 equipo: reemplazo de OTRO producto (Blanco 451)','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_devolucion_reemplazo (devolucion_id, producto_id, lote, cant_uds, uom_id, uom_nombre, cant_uom, uom_factor) values (v_dc, 503, '998 / 9-99', 1, 0, 'Paquete de 4', 1, 0.25);
    v_res := v_res || jsonb_build_object('p','E10 equipo: reemplazo con escala mala (1 paq guardado como 1 u)','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E10 equipo: reemplazo con escala mala (1 paq guardado como 1 u)','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into ent_devolucion_reemplazo (devolucion_id, producto_id, lote, cant_uds, uom_id, uom_nombre, cant_uom, uom_factor) values (v_dc, 503, '183 - 12/26', 4, 0, 'Paquete de 4', 1, 0.25);
    v_res := v_res || jsonb_build_object('p','E11 equipo: reemplazo con lote no canónico','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E11 equipo: reemplazo con lote no canónico','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, causa, creado_por, resolucion) values (current_date, -1, 'ENSAYO', v_ped, 'producto_equivocado', v_equipo, 'otra');
    v_res := v_res || jsonb_build_object('p','E12 equipo: resolucion inventada','esperado','RECHAZA · 23514','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E12 equipo: resolucion inventada','esperado','RECHAZA · 23514','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='23514');
  end;
  begin
    update ent_devolucion_reemplazo set cant_uds = 8, cant_uom = 2 where devolucion_id = v_dc;
    v_res := v_res || jsonb_build_object('p','E13 equipo: EDITA un reemplazo','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E13 equipo: EDITA un reemplazo','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    delete from ent_devolucion_reemplazo where devolucion_id = v_dc;
    v_res := v_res || jsonb_build_object('p','E14 equipo: BORRA un reemplazo','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E14 equipo: BORRA un reemplazo','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  -- ── EQUIPO: SOLO DEVOLUCION, el camino de siempre, sin tocar ──
  begin
    insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, causa, creado_por) values (current_date, -1, 'ENSAYO', v_ped, 'producto_equivocado', v_equipo) returning id into v_dd;
    v_res := v_res || jsonb_build_object('p','E15 equipo: devolución SIN decir resolucion (como b149)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E15 equipo: devolución SIN decir resolucion (como b149)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_txt := coalesce((select resolucion from ent_devolucion where id = v_dd)::text, 'null');
    v_res := v_res || jsonb_build_object('p','E16 sin decirla, queda devolucion','esperado','devolucion','obtenido',v_txt,'ok',v_txt='devolucion');
  exception when others then
    v_res := v_res || jsonb_build_object('p','E16 sin decirla, queda devolucion','esperado','devolucion','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ent_devolucion_linea (devolucion_id, producto_id, lote, cant_uds, uom_id, uom_nombre, cant_uom, uom_factor) values (v_dd, 503, '997 / 9-99', 4, 0, 'Paquete de 4', 1, 0.25);
    v_res := v_res || jsonb_build_object('p','E17 equipo: su línea','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E17 equipo: su línea','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ent_odoo_pendiente (tipo, pedido_id, devolucion_id, fecha, cliente_id, cliente_nombre, factura_id, factura_nombre, creado_por) values ('nota_credito', v_ped, v_dd, current_date, -1, 'ENSAYO', -1, 'ENSAYO', v_equipo);
    v_res := v_res || jsonb_build_object('p','E18 equipo: su NC pendiente (como siempre)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E18 equipo: su NC pendiente (como siempre)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ent_devolucion_reemplazo (devolucion_id, producto_id, lote, cant_uds, uom_id, uom_nombre, cant_uom, uom_factor) values (v_dd, 503, '998 / 9-99', 4, 0, 'Paquete de 4', 1, 0.25);
    v_res := v_res || jsonb_build_object('p','E19 equipo: reemplazo sobre una devolución que NO es cambio','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E19 equipo: reemplazo sobre una devolución que NO es cambio','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_odoo_pendiente (tipo, pedido_id, devolucion_id, fecha, destinatario, nota, creado_por) values ('traslado_interno', v_ped, null, current_date, 'ENSAYO', 'reposicion', v_equipo);
    v_res := v_res || jsonb_build_object('p','E20 equipo: traslado interno de una salida sin factura (sin devolución)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E20 equipo: traslado interno de una salida sin factura (sin devolución)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  -- ── SOCIA ──
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into ent_odoo_pendiente (tipo, pedido_id, devolucion_id, fecha, cliente_id, cliente_nombre, factura_id, factura_nombre, creado_por) values ('nota_credito', v_ped, v_dc, current_date, -1, 'ENSAYO', -1, 'ENSAYO', v_socia);
    v_res := v_res || jsonb_build_object('p','S1 socia: NC para un CAMBIO (tampoco)','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S1 socia: NC para un CAMBIO (tampoco)','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_devolucion_reemplazo (devolucion_id, producto_id, lote, cant_uds, uom_id, uom_nombre, cant_uom, uom_factor) values (v_dc, 503, '996 / 9-99', 4, 0, 'Paquete de 4', 1, 0.25);
    v_res := v_res || jsonb_build_object('p','S2 socia: un segundo reemplazo del cambio (lote 996)','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S2 socia: un segundo reemplazo del cambio (lote 996)','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    update ent_devolucion_reemplazo set lote = '995 / 9-99' where devolucion_id = v_dc;
    v_res := v_res || jsonb_build_object('p','S3 socia: EDITA un reemplazo','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S3 socia: EDITA un reemplazo','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    v_txt := coalesce((select sum(uds) from ent_reemplazo_desde_ancla where producto_id = 503 and lote in ('998 / 9-99','996 / 9-99'))::text, 'null');
    v_res := v_res || jsonb_build_object('p','S4 antes de anular: reemplazos del cambio en el saldo (uds)','esperado','8','obtenido',v_txt,'ok',v_txt='8');
  exception when others then
    v_res := v_res || jsonb_build_object('p','S4 antes de anular: reemplazos del cambio en el saldo (uds)','esperado','8','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    insert into ent_anulacion (entidad, entidad_id, motivo, creado_por) values ('devolucion', v_dc, 'ensayo', v_socia);
    v_res := v_res || jsonb_build_object('p','S5 socia ANULA el cambio','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','S5 socia ANULA el cambio','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_txt := coalesce((select count(*) from ent_reemplazo_desde_ancla where producto_id = 503 and lote in ('998 / 9-99','996 / 9-99'))::text, 'null');
    v_res := v_res || jsonb_build_object('p','S6 anulado: el reemplazo deja de restar (filas)','esperado','0','obtenido',v_txt,'ok',v_txt='0');
  exception when others then
    v_res := v_res || jsonb_build_object('p','S6 anulado: el reemplazo deja de restar (filas)','esperado','0','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_txt := coalesce((select count(*) from ent_devuelto_desde_ancla where producto_id = 503 and lote = '999 / 9-99')::text, 'null');
    v_res := v_res || jsonb_build_object('p','S7 anulado: lo devuelto deja de sumar (filas)','esperado','0','obtenido',v_txt,'ok',v_txt='0');
  exception when others then
    v_res := v_res || jsonb_build_object('p','S7 anulado: lo devuelto deja de sumar (filas)','esperado','0','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  -- ── EQUIPO no anula ──
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into ent_anulacion (entidad, entidad_id, motivo, creado_por) values ('devolucion', v_dd, 'ensayo', v_equipo);
    v_res := v_res || jsonb_build_object('p','E21 equipo ANULA una devolución','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','E21 equipo ANULA una devolución','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  -- ── ASISTENTE (Instinct) ──
  if v_asis is not null then
  perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into ent_devolucion_reemplazo (devolucion_id, producto_id, lote, cant_uds, uom_id, uom_nombre, cant_uom, uom_factor) values (v_dc, 503, '994 / 9-99', 4, 0, 'Paquete de 4', 1, 0.25);
    v_res := v_res || jsonb_build_object('p','A1 asistente: registra un reemplazo','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','A1 asistente: registra un reemplazo','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  end if;
  -- ── ANON ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
  begin
    select count(*) into v_n from ent_devolucion_reemplazo;
    v_res := v_res || jsonb_build_object('p','N1 anon lee ent_devolucion_reemplazo','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','N1 anon lee ent_devolucion_reemplazo','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    select count(*) into v_n from ent_reemplazo_desde_ancla;
    v_res := v_res || jsonb_build_object('p','N2 anon lee ent_reemplazo_desde_ancla','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','N2 anon lee ent_reemplazo_desde_ancla','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  begin
    insert into ent_devolucion_reemplazo (devolucion_id, producto_id, lote, cant_uds, uom_id, uom_nombre, cant_uom, uom_factor) values (v_dc, 503, '993 / 9-99', 4, 0, 'Paquete de 4', 1, 0.25);
    v_res := v_res || jsonb_build_object('p','N3 anon registra un reemplazo','esperado','RECHAZA · 42501','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','N3 anon registra un reemplazo','esperado','RECHAZA · 42501','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='42501');
  end;
  -- ── EDITOR SQL ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);
  begin
    v_txt := coalesce((select (count(*) >= 0) from v_ent_devolucion_exceso)::text, 'null');
    v_res := v_res || jsonb_build_object('p','X1 v_ent_devolucion_exceso sigue compilando (lee sin error)','esperado','true','obtenido',v_txt,'ok',v_txt='true');
  exception when others then
    v_res := v_res || jsonb_build_object('p','X1 v_ent_devolucion_exceso sigue compilando (lee sin error)','esperado','true','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_txt := coalesce((select count(*) from ent_devolucion where id < v_dc and resolucion <> 'devolucion')::text, 'null');
    v_res := v_res || jsonb_build_object('p','X2 las devoluciones de ANTES quedaron todas devolucion','esperado','0','obtenido',v_txt,'ok',v_txt='0');
  exception when others then
    v_res := v_res || jsonb_build_object('p','X2 las devoluciones de ANTES quedaron todas devolucion','esperado','0','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
  begin
    v_txt := coalesce((select count(*) from ent_devolucion_reemplazo where devolucion_id = v_dc)::text, 'null');
    v_res := v_res || jsonb_build_object('p','X3 reemplazos escritos en el ensayo (E3 + S2)','esperado','2','obtenido',v_txt,'ok',v_txt='2');
  exception when others then
    v_res := v_res || jsonb_build_object('p','X3 reemplazos escritos en el ensayo (E3 + S2)','esperado','2','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: 35 filas (34 si no hay asistente), todas ok = true.

rollback;
