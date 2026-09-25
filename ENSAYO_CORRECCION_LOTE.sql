-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_CORRECCION_LOTE.sql  ·  24-sep-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Correcciones de conteo por lote · Paso A
--
-- ⚠️ ARCHIVO GENERADO. No se edita a mano: se regenera con
--     python3 herramientas/ensayos/armar_ensayo_correccion_lote.py
--   El bloque DDL de abajo es el de ENTREGAS_CORRECCION_LOTE.sql BYTE A BYTE,
--   cortado por sus marcas. md5 del bloque: b4d1e43a6a47a3c3cf4a202be056863f
--
-- QUE HACE
--   1. Crea todo, igual que el pegado.
--   2. Prueba sin sesion, como socia y como equipo (sesion simulada con
--      `request.jwt.claims` + `set local role authenticated`, o sea CON RLS).
--      Las identidades salen de `v_acceso_usuario`; ningun correo va escrito
--      aca porque el repo es publico.
--   3. El caso real del ticket 30: 30 u (5 cajas) de Semillas 245 -> 247.
--   4. rollback. No queda nada.
--
-- COMO SE LEE
--   Una tabla de 32 filas, TODAS con ok = true. Si el editor dice
--   "Success. No rows returned", no llego al final y no vale.
--   Si T0 no da, los datos se movieron desde el 24-sep (una salida nueva de
--   245 o 247): R1 y R2 dejan de aplicar tal cual y hay que volver a medir.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ═══ DDL · DESDE ACA (ENSAYO_CORRECCION_LOTE.sql copia este bloque tal cual) ═══

-- §0 · CANDADO DE ENTRADA: no pisa nada que ya exista, y hace falta un ancla.
do $$
begin
  if to_regclass('public.ent_conteo_correccion') is not null
     or to_regclass('public.ent_conteo_correccion_anulacion') is not null
     or to_regclass('public.ent_conteo_correccion_vigente') is not null
     or to_regproc('public.ent_conteo_lote_neto') is not null
     or to_regproc('public.ent_conteo_correccion_guard') is not null
     or to_regproc('public.ent_conteo_correccion_anulacion_guard') is not null then
    raise exception 'ya existe algun objeto de la correccion de lote: este pegado no pisa nada';
  end if;
  if (select id from public.ent_ancla) is null then
    raise exception 'no hay ancla vigente: una correccion de conteo no tiene sobre que aplicarse';
  end if;
end $$;


-- §1 · LAS DOS TABLAS ─────────────────────────────────────────────────────
-- `uds` va en la MISMA unidad que `ent_conteo_linea.uds` (la que usa el
-- motor). La pantalla la pide y la muestra en cajas + sueltas/paquetes.
create table public.ent_conteo_correccion (
  id                  bigint generated always as identity primary key,
  conteo_id           bigint      not null references public.ent_conteo(id),
  producto_id         integer     not null,
  lote_origen         text        not null,
  lote_destino        text        not null,
  uds                 numeric     not null,
  contado_por         text        not null,
  contado_en          date        not null,
  motivo              text        not null,
  destino_orden_id    integer,
  destino_orden       text,
  destino_producto_id integer,
  autorizado_por      text        not null,
  creado_en           timestamptz not null default now(),
  constraint ent_conteo_correccion_uds_ok    check (uds > 0),
  constraint ent_conteo_correccion_lotes_ok  check (lote_origen <> lote_destino),
  constraint ent_conteo_correccion_forma_ok  check (
    lote_origen  ~ '^\d{1,3} / \d{1,2}-\d{2}$' and
    lote_destino ~ '^\d{1,3} / \d{1,2}-\d{2}$'),
  constraint ent_conteo_correccion_motivo_ok check (btrim(motivo) <> ''),
  constraint ent_conteo_correccion_conto_ok  check (btrim(contado_por) <> ''),
  -- la huella va entera o no va: tres campos, todos o ninguno
  constraint ent_conteo_correccion_huella_ok check (
    (destino_orden_id is null) = (destino_orden is null) and
    (destino_orden_id is null) = (destino_producto_id is null))
);
create index ent_conteo_correccion_conteo_idx
  on public.ent_conteo_correccion (conteo_id, producto_id);

create table public.ent_conteo_correccion_anulacion (
  id             bigint generated always as identity primary key,
  correccion_id  bigint      not null unique references public.ent_conteo_correccion(id),
  motivo         text        not null,
  anulado_por    text        not null,
  creado_en      timestamptz not null default now(),
  constraint ent_conteo_correccion_anulacion_motivo_ok check (btrim(motivo) <> '')
);

comment on table public.ent_conteo_correccion is
  'Correccion de conteo por lote (ticket 30, opcion B, 24-sep-2026): mueve uds de lote_origen a lote_destino del mismo producto sobre el ancla conteo_id. No toca ent_conteo_linea. Append-only; se anula en ent_conteo_correccion_anulacion.';
comment on table public.ent_conteo_correccion_anulacion is
  'Anulacion de una ent_conteo_correccion. Una por correccion, con motivo, solo socias. Nunca se edita ni se borra.';


-- §2 · LA VISTA QUE LEE EL MOTOR ──────────────────────────────────────────
create view public.ent_conteo_correccion_vigente with (security_invoker = true) as
select c.id, c.conteo_id, c.producto_id, c.lote_origen, c.lote_destino, c.uds,
       c.contado_por, c.contado_en, c.motivo,
       c.destino_orden_id, c.destino_orden, c.destino_producto_id,
       c.autorizado_por, c.creado_en
  from public.ent_conteo_correccion c
 where not exists (select 1 from public.ent_conteo_correccion_anulacion a
                    where a.correccion_id = c.id);


-- §3 · EL SALDO DE UN LOTE, LO QUE LA BASE VE ─────────────────────────────
-- ancla + correcciones − salidas + devoluciones. Sin produccion ni merma:
-- viven en Odoo. ⚠️ Salidas y devoluciones salen de las vistas `_desde_ancla`,
-- que miden contra el ancla VIGENTE: con otro `p_conteo` esas dos columnas no
-- significan nada. Los guardias solo la llaman con el ancla vigente.
create function public.ent_conteo_lote_neto(p_conteo bigint, p_producto integer, p_lote text)
returns table (ancla numeric, correcciones numeric, ancla_corregida numeric,
               salidas numeric, devoluciones numeric, saldo_visible numeric)
language sql stable security invoker
set search_path = public, pg_temp
as $$
  with a as (select coalesce(sum(l.uds), 0) as v from ent_conteo_linea l
              where l.conteo_id = p_conteo and l.producto_id = p_producto and l.lote = p_lote),
       c as (select coalesce(sum(case when v.lote_destino = p_lote then v.uds else 0 end), 0)
                  - coalesce(sum(case when v.lote_origen  = p_lote then v.uds else 0 end), 0) as v
               from ent_conteo_correccion_vigente v
              where v.conteo_id = p_conteo and v.producto_id = p_producto
                and p_lote in (v.lote_origen, v.lote_destino)),
       s as (select coalesce(sum(x.uds), 0) as v from ent_salido_del_congelador_desde_ancla x
              where x.producto_id = p_producto and x.lote = p_lote),
       d as (select coalesce(sum(x.uds), 0) as v from ent_devuelto_desde_ancla x
              where x.producto_id = p_producto and x.lote = p_lote)
  select a.v, c.v, a.v + c.v, s.v, d.v, a.v + c.v - s.v + d.v from a, c, s, d;
$$;


-- §4 · LOS DOS GUARDIAS ───────────────────────────────────────────────────
create function public.ent_conteo_correccion_guard()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_quien text;
  v_ancla bigint;
  v_fecha date;
  v_hoy   date;
  n       record;
begin
  -- ══ 1 · QUIEN. La firma sale de la sesion, nunca de la fila. ══════════
  v_quien := lower(btrim(nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email'));
  if v_quien is null or v_quien = '' then
    raise exception 'una correccion de lote se hace desde la pantalla, con sesion iniciada: '
      'sin sesion no se sabe quien autoriza';
  end if;
  if new.autorizado_por is not null and lower(btrim(new.autorizado_por)) <> v_quien then
    raise exception 'autorizado_por dice % y la sesion es de %. La firma no se elige.',
      new.autorizado_por, v_quien;
  end if;
  new.autorizado_por := v_quien;
  if not acceso_es_socia() then
    raise exception 'corregir un lote del conteo es de un perfil socias, y % no lo es.', v_quien;
  end if;

  -- ══ 2 · UNA CORRECCION POR PRODUCTO A LA VEZ ═══════════════════════════
  -- Sin esto, dos correcciones simultaneas leen el mismo saldo, pasan las dos
  -- el control de "no negativo", y juntas lo dejan bajo cero.
  perform pg_advisory_xact_lock(hashtext('ent_conteo_correccion'), new.producto_id);

  -- ══ 3 · SOBRE EL ANCLA VIGENTE, CON UNA FECHA QUE TENGA SENTIDO ════════
  select a.id, a.fecha into v_ancla, v_fecha from ent_ancla a;
  if v_ancla is null or new.conteo_id is distinct from v_ancla then
    raise exception 'la correccion tiene que ser sobre el ancla vigente (conteo %); vino el conteo %',
      v_ancla, new.conteo_id;
  end if;
  v_hoy := (now() at time zone 'America/Costa_Rica')::date;
  if new.contado_en > v_hoy or new.contado_en < v_fecha then
    raise exception 'la fecha del recuento (%) tiene que estar entre la del ancla (%) y hoy (%)',
      new.contado_en, v_fecha, v_hoy;
  end if;

  -- ══ 4 · ORIGEN: solo se mueve lo que se conto ══════════════════════════
  if not exists (select 1 from ent_conteo_linea l
                  where l.conteo_id = v_ancla and l.producto_id = new.producto_id
                    and l.lote = new.lote_origen) then
    raise exception 'el lote de origen % no esta en el conteo del ancla para el producto %: '
      'solo se puede mover lo que se conto', new.lote_origen, new.producto_id;
  end if;

  -- ══ 5 · DESTINO: en el ancla, o con la huella de su orden ══════════════
  if new.destino_producto_id is not null and new.destino_producto_id <> new.producto_id then
    raise exception 'la huella del lote destino es del producto %, y la correccion es del %',
      new.destino_producto_id, new.producto_id;
  end if;
  if new.destino_orden_id is null
     and not exists (select 1 from ent_conteo_linea l
                      where l.conteo_id = v_ancla and l.producto_id = new.producto_id
                        and l.lote = new.lote_destino) then
    raise exception 'el lote destino % no esta en el conteo del ancla: hace falta la huella de su '
      'orden de produccion (la pone la pantalla, leida de Odoo)', new.lote_destino;
  end if;

  -- ══ 6 · EL ORIGEN NO QUEDA NEGATIVO ════════════════════════════════════
  select * into n from ent_conteo_lote_neto(v_ancla, new.producto_id, new.lote_origen);
  if n.ancla_corregida - new.uds < 0 then
    raise exception 'el lote % quedaria en % en el ancla (tiene %, se mueven %)',
      new.lote_origen, n.ancla_corregida - new.uds, n.ancla_corregida, new.uds;
  end if;
  if n.saldo_visible - new.uds < 0 then
    raise exception 'el lote % quedaria con saldo % (ancla corregida % − salidas % + devoluciones %, '
      'se mueven %). La merma de Odoo no entra en esta cuenta y solo podria bajarlo mas.',
      new.lote_origen, n.saldo_visible - new.uds, n.ancla_corregida, n.salidas, n.devoluciones, new.uds;
  end if;

  return new;
end $$;

create function public.ent_conteo_correccion_anulacion_guard()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_quien text;
  v_ancla bigint;
  c       record;
  n       record;
begin
  v_quien := lower(btrim(nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email'));
  if v_quien is null or v_quien = '' then
    raise exception 'anular una correccion de lote se hace con sesion iniciada: sin sesion no se sabe quien anula';
  end if;
  if new.anulado_por is not null and lower(btrim(new.anulado_por)) <> v_quien then
    raise exception 'anulado_por dice % y la sesion es de %. La firma no se elige.',
      new.anulado_por, v_quien;
  end if;
  new.anulado_por := v_quien;
  if not acceso_es_socia() then
    raise exception 'anular una correccion de lote es de un perfil socias, y % no lo es.', v_quien;
  end if;

  select * into c from ent_conteo_correccion where id = new.correccion_id;
  if not found then
    raise exception 'no existe la correccion %', new.correccion_id;
  end if;
  perform pg_advisory_xact_lock(hashtext('ent_conteo_correccion'), c.producto_id);
  if exists (select 1 from ent_conteo_correccion_anulacion a where a.correccion_id = c.id) then
    raise exception 'la correccion % ya esta anulada', c.id;
  end if;

  select a.id into v_ancla from ent_ancla a;
  if c.conteo_id is distinct from v_ancla then
    raise exception 'la correccion % es del conteo %, y el ancla vigente es el %: anularla no cambia ningun saldo',
      c.id, c.conteo_id, v_ancla;
  end if;

  -- Anular devuelve la cantidad al origen y se la SACA al destino: el que
  -- puede quedar negativo es el destino.
  select * into n from ent_conteo_lote_neto(v_ancla, c.producto_id, c.lote_destino);
  if n.ancla_corregida - c.uds < 0 or n.saldo_visible - c.uds < 0 then
    raise exception 'anular la correccion % deja el lote % en % en el ancla y % de saldo: '
      'ya salio producto de ese lote contando con esta correccion',
      c.id, c.lote_destino, n.ancla_corregida - c.uds, n.saldo_visible - c.uds;
  end if;

  return new;
end $$;

create trigger ent_conteo_correccion_guard_trg
  before insert on public.ent_conteo_correccion
  for each row execute function public.ent_conteo_correccion_guard();
create trigger ent_conteo_correccion_anulacion_guard_trg
  before insert on public.ent_conteo_correccion_anulacion
  for each row execute function public.ent_conteo_correccion_anulacion_guard();


-- §5 · RLS ─────────────────────────────────────────────────────────────────
alter table public.ent_conteo_correccion           enable row level security;
alter table public.ent_conteo_correccion_anulacion enable row level security;

create policy ent_conteo_correccion_sel on public.ent_conteo_correccion
  for select to authenticated using (true);
create policy ent_conteo_correccion_ins on public.ent_conteo_correccion
  for insert to authenticated with check (acceso_es_socia());
create policy ent_conteo_correccion_anulacion_sel on public.ent_conteo_correccion_anulacion
  for select to authenticated using (true);
create policy ent_conteo_correccion_anulacion_ins on public.ent_conteo_correccion_anulacion
  for insert to authenticated with check (acceso_es_socia());


-- §6 · PERMISOS ────────────────────────────────────────────────────────────
revoke all on table public.ent_conteo_correccion,
                    public.ent_conteo_correccion_anulacion,
                    public.ent_conteo_correccion_vigente
  from public, anon, authenticated;
grant select, insert on table public.ent_conteo_correccion,
                              public.ent_conteo_correccion_anulacion to authenticated;
grant select on table public.ent_conteo_correccion_vigente to authenticated;

revoke all on function public.ent_conteo_lote_neto(bigint, integer, text),
                       public.ent_conteo_correccion_guard(),
                       public.ent_conteo_correccion_anulacion_guard()
  from public, anon;
grant execute on function public.ent_conteo_lote_neto(bigint, integer, text),
                          public.ent_conteo_correccion_guard(),
                          public.ent_conteo_correccion_anulacion_guard() to authenticated;

-- ═══ DDL · HASTA ACA ═══


-- ── LAS PRUEBAS ───────────────────────────────────────────────────────────
do $$
declare
  v_socia  text;
  v_equipo text;
  v_anc    bigint;
  v_otro   bigint;
  v_hoy    date := (now() at time zone 'America/Costa_Rica')::date;
  v_t1     bigint;
  v_n8     bigint;
  v_x1 numeric; v_x2 numeric; v_x3 numeric; v_x4 numeric;
  v_tot_a0 numeric; v_tot_s0 numeric; v_tot_a1 numeric; v_tot_s1 numeric;
  v_b      boolean;
  v_res    jsonb := '[]'::jsonb;
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by email limit 1;
  select email into v_equipo from v_acceso_usuario where perfil = 'equipo' and activo order by email limit 1;
  select id into v_anc from ent_ancla;
  select max(id) into v_otro from ent_conteo where id <> v_anc;
  if v_socia is null or v_equipo is null or v_anc is null or v_otro is null then
    raise exception 'falta algo para ensayar (socia %, equipo %, ancla %, otro conteo %)',
      v_socia is not null, v_equipo is not null, v_anc, v_otro;
  end if;

  -- ── A · SIN SESION (todavia como postgres) ──
  begin
    insert into ent_conteo_correccion (conteo_id, producto_id, lote_origen, lote_destino, uds, contado_por, contado_en, motivo) values (v_anc, 452, '245 / 6-27', '247 / 6-27', 30, 'Daniel', v_hoy, 'ensayo');
    v_res := v_res || jsonb_build_object('p', 'A1 sin sesion · 245→247 30 u', 'esperado', 'RECHAZA', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'A1 sin sesion · 245→247 30 u', 'esperado', 'RECHAZA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', true);
  end;

  -- ── T · EL CASO REAL, como socia. De aca en adelante la RLS aplica. ──
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);

  -- T0 · el terreno: si esto no da, los datos se movieron y R1/R2 no aplican
  select a.ancla, a.salidas, b.ancla, b.salidas into v_x1, v_x2, v_x3, v_x4
    from ent_conteo_lote_neto(v_anc, 452, '245 / 6-27') a, ent_conteo_lote_neto(v_anc, 452, '247 / 6-27') b;
  v_res := v_res || jsonb_build_object('p', 'T0 terreno · 245 ancla·salidas / 247 ancla·salidas', 'esperado', '114 · 78 / 12 · 12', 'obtenido', v_x1 || ' · ' || v_x2 || ' / ' || v_x3 || ' · ' || v_x4, 'ok', (v_x1, v_x2, v_x3, v_x4) = (114, 78, 12, 12));
  select sum(n.ancla_corregida), sum(n.saldo_visible) into v_tot_a0, v_tot_s0
    from (select lote from ent_conteo_linea where conteo_id = v_anc and producto_id = 452
          union select lote_destino from ent_conteo_correccion_vigente where conteo_id = v_anc and producto_id = 452) l,
         lateral ent_conteo_lote_neto(v_anc, 452, l.lote) n;
  begin
    insert into ent_conteo_correccion (conteo_id, producto_id, lote_origen, lote_destino, uds, contado_por, contado_en, motivo) values (v_anc, 452, '245 / 6-27', '247 / 6-27', 30, 'Daniel', v_hoy, 'Cinco cajas de 247 anotadas como 245 en el conteo del 10-sep') returning id into v_t1;
    v_res := v_res || jsonb_build_object('p', 'T1 socia · 245→247 30 u (5 cajas), contó Daniel', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'T1 socia · 245→247 30 u (5 cajas), contó Daniel', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', false);
  end;
  select n.ancla_corregida, n.saldo_visible into v_x1, v_x2 from ent_conteo_lote_neto(v_anc, 452, '245 / 6-27') n;
  v_res := v_res || jsonb_build_object('p', 'R1 · 245 ancla corregida · saldo', 'esperado', '84 · 6  (14 cajas · 1 caja)', 'obtenido', v_x1 || ' · ' || v_x2, 'ok', (v_x1, v_x2) = (84, 6));
  select n.ancla_corregida, n.saldo_visible into v_x1, v_x2 from ent_conteo_lote_neto(v_anc, 452, '247 / 6-27') n;
  v_res := v_res || jsonb_build_object('p', 'R2 · 247 ancla corregida · saldo', 'esperado', '42 · 30  (7 cajas · 5 cajas)', 'obtenido', v_x1 || ' · ' || v_x2, 'ok', (v_x1, v_x2) = (42, 30));
  select sum(n.ancla_corregida), sum(n.saldo_visible) into v_tot_a1, v_tot_s1
    from (select lote from ent_conteo_linea where conteo_id = v_anc and producto_id = 452
          union select lote_destino from ent_conteo_correccion_vigente where conteo_id = v_anc and producto_id = 452) l,
         lateral ent_conteo_lote_neto(v_anc, 452, l.lote) n;
  v_res := v_res || jsonb_build_object('p', 'R3 · total Semillas, ancla y saldo, antes → después', 'esperado', 'no cambia', 'obtenido', 'ancla ' || v_tot_a0 || '→' || v_tot_a1 || ' · saldo ' || v_tot_s0 || '→' || v_tot_s1, 'ok', v_tot_a0 = v_tot_a1 and v_tot_s0 = v_tot_s1);
  select autorizado_por = v_socia into v_b from ent_conteo_correccion where id = v_t1;
  v_res := v_res || jsonb_build_object('p', 'R4 · autorizado_por sale de la sesion', 'esperado', 'la socia de la sesion', 'obtenido', case when v_b then 'la socia de la sesion' else 'OTRO' end, 'ok', coalesce(v_b, false));

  -- ── N · LAS GUARDAS ──
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  begin
    insert into ent_conteo_correccion (conteo_id, producto_id, lote_origen, lote_destino, uds, contado_por, contado_en, motivo) values (v_anc, 452, '252 / 6-27', '244 / 3-27', 1, 'Daniel', v_hoy, 'ensayo');
    v_res := v_res || jsonb_build_object('p', 'N1 equipo · 252→244 1 u', 'esperado', 'RECHAZA', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N1 equipo · 252→244 1 u', 'esperado', 'RECHAZA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', true);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  begin
    insert into ent_conteo_correccion (conteo_id, producto_id, lote_origen, lote_destino, uds, contado_por, contado_en, motivo) values (v_anc, 452, '999 / 1-27', '247 / 6-27', 1, 'Daniel', v_hoy, 'ensayo');
    v_res := v_res || jsonb_build_object('p', 'N2 origen fuera del ancla (999 / 1-27)', 'esperado', 'RECHAZA', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N2 origen fuera del ancla (999 / 1-27)', 'esperado', 'RECHAZA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', true);
  end;
  begin
    insert into ent_conteo_correccion (conteo_id, producto_id, lote_origen, lote_destino, uds, contado_por, contado_en, motivo) values (v_anc, 452, '252 / 6-27', '252 / 6-27', 1, 'Daniel', v_hoy, 'ensayo');
    v_res := v_res || jsonb_build_object('p', 'N3 origen = destino', 'esperado', 'RECHAZA', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N3 origen = destino', 'esperado', 'RECHAZA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', true);
  end;
  begin
    insert into ent_conteo_correccion (conteo_id, producto_id, lote_origen, lote_destino, uds, contado_por, contado_en, motivo) values (v_anc, 452, '252 / 6-27', '244 / 3-27', 0, 'Daniel', v_hoy, 'ensayo');
    v_res := v_res || jsonb_build_object('p', 'N4 cantidad 0', 'esperado', 'RECHAZA', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N4 cantidad 0', 'esperado', 'RECHAZA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', true);
  end;
  begin
    insert into ent_conteo_correccion (conteo_id, producto_id, lote_origen, lote_destino, uds, contado_por, contado_en, motivo) values (v_anc, 452, '245 / 6-27', '247 / 6-27', 7, 'Daniel', v_hoy, 'ensayo');
    v_res := v_res || jsonb_build_object('p', 'N5 245 queda negativo (saldo 6, mover 7)', 'esperado', 'RECHAZA', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N5 245 queda negativo (saldo 6, mover 7)', 'esperado', 'RECHAZA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', true);
  end;
  begin
    insert into ent_conteo_correccion (conteo_id, producto_id, lote_origen, lote_destino, uds, contado_por, contado_en, motivo) values (v_anc, 452, '252 / 6-27', '250 / 6-27', 6, 'Daniel', v_hoy, 'ensayo');
    v_res := v_res || jsonb_build_object('p', 'N6 destino fuera del ancla SIN huella', 'esperado', 'RECHAZA', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N6 destino fuera del ancla SIN huella', 'esperado', 'RECHAZA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', true);
  end;
  begin
    insert into ent_conteo_correccion (conteo_id, producto_id, lote_origen, lote_destino, uds, contado_por, contado_en, motivo, destino_orden_id, destino_orden, destino_producto_id) values (v_anc, 452, '252 / 6-27', '250 / 6-27', 6, 'Daniel', v_hoy, 'ensayo', 99999999, 'WH/MO/ENSAYO', 451);
    v_res := v_res || jsonb_build_object('p', 'N7 destino fuera del ancla, huella de OTRO producto', 'esperado', 'RECHAZA', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N7 destino fuera del ancla, huella de OTRO producto', 'esperado', 'RECHAZA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', true);
  end;
  begin
    insert into ent_conteo_correccion (conteo_id, producto_id, lote_origen, lote_destino, uds, contado_por, contado_en, motivo, destino_orden_id, destino_orden, destino_producto_id) values (v_anc, 452, '252 / 6-27', '250 / 6-27', 6, 'Daniel', v_hoy, 'ensayo', 99999999, 'WH/MO/ENSAYO', 452) returning id into v_n8;
    v_res := v_res || jsonb_build_object('p', 'N8 destino fuera del ancla, huella completa', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N8 destino fuera del ancla, huella completa', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', false);
  end;
  begin
    insert into ent_conteo_correccion (conteo_id, producto_id, lote_origen, lote_destino, uds, contado_por, contado_en, motivo, destino_orden_id, destino_producto_id) values (v_anc, 452, '252 / 6-27', '250 / 6-27', 1, 'Daniel', v_hoy, 'ensayo', 99999999, 452);
    v_res := v_res || jsonb_build_object('p', 'N9 huella a medias (sin nombre de orden)', 'esperado', 'RECHAZA', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N9 huella a medias (sin nombre de orden)', 'esperado', 'RECHAZA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', true);
  end;
  begin
    insert into ent_conteo_correccion (conteo_id, producto_id, lote_origen, lote_destino, uds, contado_por, contado_en, motivo) values (v_otro, 452, '252 / 6-27', '244 / 3-27', 1, 'Daniel', v_hoy, 'ensayo');
    v_res := v_res || jsonb_build_object('p', 'N10 sobre un conteo que no es el ancla', 'esperado', 'RECHAZA', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N10 sobre un conteo que no es el ancla', 'esperado', 'RECHAZA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', true);
  end;
  begin
    insert into ent_conteo_correccion (conteo_id, producto_id, lote_origen, lote_destino, uds, contado_por, contado_en, motivo) values (v_anc, 452, '252 / 6-27', '244 / 3-27', 1, 'Daniel', v_hoy, '   ');
    v_res := v_res || jsonb_build_object('p', 'N11 motivo en blanco', 'esperado', 'RECHAZA', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N11 motivo en blanco', 'esperado', 'RECHAZA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', true);
  end;
  begin
    insert into ent_conteo_correccion (conteo_id, producto_id, lote_origen, lote_destino, uds, contado_por, contado_en, motivo) values (v_anc, 452, '252 / 6-27', '244 / 3-27', 1, 'Daniel', v_hoy, 'x');
    v_res := v_res || jsonb_build_object('p', 'N12 motivo de 1 caracter (sin minimo)', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N12 motivo de 1 caracter (sin minimo)', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', false);
  end;
  begin
    insert into ent_conteo_correccion (conteo_id, producto_id, lote_origen, lote_destino, uds, contado_por, contado_en, motivo, autorizado_por) values (v_anc, 452, '252 / 6-27', '244 / 3-27', 1, 'Daniel', v_hoy, 'ensayo', v_equipo);
    v_res := v_res || jsonb_build_object('p', 'N13 autorizado_por de otra persona', 'esperado', 'RECHAZA', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N13 autorizado_por de otra persona', 'esperado', 'RECHAZA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', true);
  end;
  begin
    insert into ent_conteo_correccion (conteo_id, producto_id, lote_origen, lote_destino, uds, contado_por, contado_en, motivo) values (v_anc, 452, '252 / 6-27', '244 / 3-27', 1, 'Daniel', v_hoy + 1, 'ensayo');
    v_res := v_res || jsonb_build_object('p', 'N14 fecha del recuento mañana', 'esperado', 'RECHAZA', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N14 fecha del recuento mañana', 'esperado', 'RECHAZA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', true);
  end;
  begin
    update ent_conteo_correccion set motivo = 'otro' where id = v_t1;
    v_res := v_res || jsonb_build_object('p', 'N15 editar una correccion (update)', 'esperado', 'RECHAZA', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N15 editar una correccion (update)', 'esperado', 'RECHAZA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', true);
  end;
  begin
    delete from ent_conteo_correccion where id = v_t1;
    v_res := v_res || jsonb_build_object('p', 'N16 borrar una correccion (delete)', 'esperado', 'RECHAZA', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'N16 borrar una correccion (delete)', 'esperado', 'RECHAZA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', true);
  end;

  -- ── X · ANULAR ──
  begin
    insert into ent_conteo_correccion_anulacion (correccion_id, motivo) values (v_n8, 'ensayo');
    v_res := v_res || jsonb_build_object('p', 'X1 socia anula la del N8 (250 no se usó)', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'X1 socia anula la del N8 (250 no se usó)', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', false);
  end;
  select count(*) into v_x1 from ent_conteo_correccion_vigente where id = v_n8;
  select n.ancla_corregida into v_x2 from ent_conteo_lote_neto(v_anc, 452, '250 / 6-27') n;
  v_res := v_res || jsonb_build_object('p', 'X2 · la anulada sale de la vista y el 250 vuelve a 0', 'esperado', '0 filas · 250 en 0', 'obtenido', v_x1 || ' filas · 250 en ' || v_x2, 'ok', v_x1 = 0 and v_x2 = 0);
  begin
    insert into ent_conteo_correccion_anulacion (correccion_id, motivo) values (v_n8, 'ensayo');
    v_res := v_res || jsonb_build_object('p', 'X3 anularla otra vez', 'esperado', 'RECHAZA', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'X3 anularla otra vez', 'esperado', 'RECHAZA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', true);
  end;
  begin
    insert into ent_conteo_correccion (conteo_id, producto_id, lote_origen, lote_destino, uds, contado_por, contado_en, motivo) values (v_anc, 452, '247 / 6-27', '252 / 6-27', 30, 'Daniel', v_hoy, 'ensayo');
    v_res := v_res || jsonb_build_object('p', 'X4 mover las 30 u del 247 al 252 (247 queda en 0)', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'X4 mover las 30 u del 247 al 252 (247 queda en 0)', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', false);
  end;
  begin
    insert into ent_conteo_correccion_anulacion (correccion_id, motivo) values (v_t1, 'ensayo');
    v_res := v_res || jsonb_build_object('p', 'X5 anular la T1: el 247 quedaria en −30', 'esperado', 'RECHAZA', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'X5 anular la T1: el 247 quedaria en −30', 'esperado', 'RECHAZA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', true);
  end;
  begin
    insert into ent_conteo_correccion_anulacion (correccion_id, motivo) values (v_t1, '');
    v_res := v_res || jsonb_build_object('p', 'X6 anular sin motivo', 'esperado', 'RECHAZA', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'X6 anular sin motivo', 'esperado', 'RECHAZA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', true);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  begin
    insert into ent_conteo_correccion_anulacion (correccion_id, motivo) values (v_t1, 'ensayo');
    v_res := v_res || jsonb_build_object('p', 'X7 equipo anula', 'esperado', 'RECHAZA', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'X7 equipo anula', 'esperado', 'RECHAZA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', true);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  begin
    delete from ent_conteo_correccion_anulacion where correccion_id = v_n8;
    v_res := v_res || jsonb_build_object('p', 'X8 editar una anulacion (delete)', 'esperado', 'RECHAZA', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'X8 editar una anulacion (delete)', 'esperado', 'RECHAZA', 'obtenido', 'RECHAZA: ' || sqlerrm, 'ok', true);
  end;

  -- ── P · anon no toca nada ──
  select count(*) into v_x1 from unnest(array['public.ent_conteo_correccion',
      'public.ent_conteo_correccion_anulacion', 'public.ent_conteo_correccion_vigente']) t
   where has_table_privilege('anon', t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE');
  select count(*) into v_x2 from unnest(array['public.ent_conteo_lote_neto(bigint,integer,text)',
      'public.ent_conteo_correccion_guard()', 'public.ent_conteo_correccion_anulacion_guard()']) f
   where has_function_privilege('anon', f, 'EXECUTE');
  v_res := v_res || jsonb_build_object('p', 'P1 · anon: tablas con algun permiso · funciones con EXECUTE', 'esperado', '0 · 0', 'obtenido', v_x1 || ' · ' || v_x2, 'ok', v_x1 = 0 and v_x2 = 0);

  perform set_config('ensayo.res', v_res::text, true);
end $$;


-- ── EL RESULTADO. Esta tabla ES el ensayo. ────────────────────────────────
-- ESPERADO: 32 filas, todas con ok = true.
select r.p as prueba, r.esperado, r.obtenido, r.ok
  from jsonb_to_recordset(current_setting('ensayo.res')::jsonb)
       as r(p text, esperado text, obtenido text, ok boolean);

rollback;

-- ── DESPUES DEL ROLLBACK (opcional, con pg_lector) ────────────────────────
-- select to_regclass('public.ent_conteo_correccion');   -> NULL: el ensayo no dejo nada.
