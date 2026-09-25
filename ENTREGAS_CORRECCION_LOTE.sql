-- ═══════════════════════════════════════════════════════════════════════════
-- ENTREGAS_CORRECCION_LOTE.sql  ·  24-sep-2026  ·  SIN APLICAR
-- Correcciones de conteo por lote (opcion B de Andrea, ticket 30) · Paso A
--
-- QUE ES
--   Una correccion MUEVE una cantidad de un lote a otro DEL MISMO PRODUCTO,
--   sobre el ancla vigente. El total del producto no cambia: esto corrige a
--   que lote se le anoto cada caja, no re-ancla. La foto del conteo
--   (`ent_conteo_linea`) NO se toca: la correccion se SUMA encima, con su
--   propio rastro. Es lo contrario de PEGADO_LOTE247_ANCLA.sql (descartado).
--
-- QUE TRAE
--   · `ent_conteo_correccion` ............. las correcciones (append-only)
--   · `ent_conteo_correccion_anulacion` ... anular una, con motivo. Nunca editar.
--   · `ent_conteo_correccion_vigente` ..... las no anuladas (la lee el motor)
--   · `ent_conteo_lote_neto()` ............ el saldo de un lote que la BASE ve
--   · dos guardias (triggers BEFORE INSERT), RLS y permisos.
--
-- 🔴 LAS GUARDAS, TODAS EN LA BASE (la pantalla repite algunas, pero no manda)
--   · Solo socias: RLS `acceso_es_socia()` + el guardia, con mensaje claro.
--   · Sin sesion no entra: `autorizado_por` SALE DE LA SESION. Si viene otro
--     nombre, se rechaza ("la firma no se elige", igual que ticket_estado).
--   · Sobre el ancla VIGENTE, y nada mas. Con un conteo nuevo, las
--     correcciones del viejo dejan de aplicar solas (van atadas a su conteo).
--   · Mismo producto (hay una sola columna de producto: no se puede mezclar).
--   · Origen <> destino, cantidad > 0, motivo y "quien conto" no vacios
--     (motivo OBLIGATORIO, sin minimo de caracteres — Andrea, 24-sep).
--   · Fecha del recuento entre la fecha del ancla y hoy (hora CR).
--   · ORIGEN: tiene que estar en el conteo del ancla para ese producto. Solo
--     se mueve lo que se conto.
--   · DESTINO: puede estar en el ancla o NO (el error tipico es anotar TODAS
--     las cajas de un lote bajo el nombre de otro: el lote real queda fuera
--     del conteo). Si no esta en el ancla, la fila tiene que traer la HUELLA
--     de su orden de produccion (id, nombre y producto, leidos de Odoo por la
--     pantalla) y el producto de la huella tiene que ser el de la correccion.
--     ⚠️ LA BASE NO VE ODOO: no puede saber si la huella es verdadera. Eso lo
--     re-verifica el motor cada vez que calcula (capa 3, en index.html): si la
--     huella no calza con los lotes leidos de Odoo, la correccion se aplica
--     igual pero el lote sale marcado "destino sin verificar". El riesgo que
--     queda, aceptado por Andrea el 24-sep: una huella inventada sobre un lote
--     MAS VIEJO que la ventana de 3 meses no tiene contra que compararse.
--     Queda firmada, visible y anulable, pero sin aviso automatico.
--   · EL ORIGEN NO QUEDA NEGATIVO, medido dos veces:
--       ancla corregida del origen − cantidad >= 0, y
--       ancla corregida − salidas + devoluciones − cantidad >= 0.
--     La merma y la produccion nueva viven en Odoo y la base no las ve; la
--     merma solo puede bajar el saldo, asi que la pantalla la suma y vuelve a
--     bloquear. La produccion nueva de un lote contado es rarisima (el lote es
--     el dia juliano) y solo podria subirlo.
--   · ANULAR: mismas reglas de firma y socias, una sola vez, solo sobre el
--     ancla vigente, y SIN dejar negativo al lote DESTINO (que es el que baja).
--   · Dos correcciones a la vez no pueden pasar juntas el control de "no
--     negativo": el guardia toma un candado por producto
--     (`pg_advisory_xact_lock`) que dura hasta el fin de la transaccion.
--
-- PERMISOS
--   El privilegio por defecto de `postgres` en `public` le da a `anon`
--   INSERT/SELECT/UPDATE/DELETE sobre toda tabla nueva y EXECUTE sobre toda
--   funcion nueva (medido 24-sep). Aca se le quita TODO a `anon` y a PUBLIC,
--   y a `authenticated` se le da SOLO select + insert: sin UPDATE ni DELETE ni
--   politica que los permita. Append-only por dos lados.
--
-- LO QUE NO TOCA: ninguna tabla, vista, politica ni funcion que ya exista.
--
-- ANTES DE PEGAR: correr ENSAYO_CORRECCION_LOTE.sql (el mismo bloque DDL,
--   byte a byte, mas las pruebas, y rollback).
-- SE PEGA ENTERO: un `begin`, un `commit`, cero `rollback`.
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


-- 🔴 LA PRUEBA DE QUE ENTRO, ADENTRO DE LA TRANSACCION.
-- ESPERADO: 3 · 3 · 2 · 4 · 0 · 0 · 0 · t
select
  (select count(*) from pg_class c join pg_namespace s on s.oid = c.relnamespace
    where s.nspname = 'public' and c.relname in
      ('ent_conteo_correccion','ent_conteo_correccion_anulacion','ent_conteo_correccion_vigente'))
                                                                          as relaciones,
  (select count(*) from pg_proc p join pg_namespace s on s.oid = p.pronamespace
    where s.nspname = 'public' and p.proname in
      ('ent_conteo_lote_neto','ent_conteo_correccion_guard','ent_conteo_correccion_anulacion_guard'))
                                                                          as funciones,
  (select count(*) from pg_trigger where not tgisinternal and tgname in
      ('ent_conteo_correccion_guard_trg','ent_conteo_correccion_anulacion_guard_trg'))
                                                                          as triggers,
  (select count(*) from pg_policy where polrelid in
      ('public.ent_conteo_correccion'::regclass, 'public.ent_conteo_correccion_anulacion'::regclass))
                                                                          as politicas,
  (select count(*) from unnest(array['public.ent_conteo_correccion',
                                     'public.ent_conteo_correccion_anulacion',
                                     'public.ent_conteo_correccion_vigente']) t
    where has_table_privilege('anon', t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'))
                                                                          as anon_tablas,
  (select count(*) from unnest(array['public.ent_conteo_lote_neto(bigint,integer,text)',
                                     'public.ent_conteo_correccion_guard()',
                                     'public.ent_conteo_correccion_anulacion_guard()']) f
    where has_function_privilege('anon', f, 'EXECUTE'))                   as anon_funciones,
  (select count(*) from public.ent_conteo_correccion)                     as filas,
  (select relrowsecurity from pg_class where oid = 'public.ent_conteo_correccion'::regclass)
                                                                          as rls;

commit;


-- ── VERIFICACION DE DESPUES (con pg_lector, fuera de la transaccion) ──────
-- select to_regclass('public.ent_conteo_correccion_vigente');         -> no null
-- select reloptions from pg_class where relname = 'ent_conteo_correccion_vigente';
--                                                                      -> {security_invoker=true}
-- select grantee, privilege_type from information_schema.table_privileges
--  where table_name like 'ent_conteo_correccion%' order by 1, 2;
--   -> authenticated: INSERT + SELECT en las dos tablas, SELECT en la vista.
--      anon: NADA. service_role: lo que le da Supabase por defecto.
-- select * from ent_conteo_lote_neto((select id from ent_ancla), 452, '245 / 6-27');
--   -> ancla 114 · correcciones 0 · ancla_corregida 114 · salidas 78 · devoluciones 0 · saldo 36
--      (hasta que Andrea cargue la correccion desde la pantalla)
