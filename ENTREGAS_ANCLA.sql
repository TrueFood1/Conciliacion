-- ════════════════════════════════════════════════════════════════════════
-- CONTEO EN DOS PASOS: borrador → ancla confirmada
-- 12-ago-2026. SEGUNDO PEGADO, después de ENTREGAS_ESQUEMA.sql.
-- Re-ejecutable: se puede pegar de nuevo sin romper ni duplicar nada.
--
-- POR QUÉ. El conteo es la línea divisoria de todos los saldos por lote. Que un
-- error de dedo quede como ancla oficial por el solo gesto de tocar "Guardar" es
-- demasiado barato para lo que cuesta. Ahora guardar deja un BORRADOR (se puede
-- repetir las veces que haga falta) y hay un segundo gesto explícito para
-- convertirlo en ancla.
--
-- CÓMO, sin romper el append-only. No se agrega una columna `confirmado` a
-- ent_conteo: marcarla exigiría UPDATE, que es justo lo que el módulo no permite
-- (no hay política ni grant de update, a propósito). La confirmación se INSERTA
-- en su propia tabla. Anular una confirmación también se inserta — una fila nueva
-- con anulada=true. Es el mismo patrón que ya usa ent_alisto.
--
-- EL CORTE NO CAMBIA. Sigue siendo el instante en que se guardó el conteo, no el
-- de la confirmación: el corte es cuándo la foto fue verdad (cuándo se contó el
-- congelador), no cuándo Andrea le dio el visto bueno media hora después.
-- ════════════════════════════════════════════════════════════════════════

create table if not exists ent_conteo_ancla (
  id          bigint generated always as identity primary key,
  conteo_id   bigint  not null references ent_conteo(id),
  anulada     boolean not null default false,   -- para desanclar: se INSERTA otra fila con true
  nota        text,
  creado_en   timestamptz not null default now(),
  creado_por  text    not null
);
create index if not exists ent_conteo_ancla_conteo_idx
  on ent_conteo_ancla (conteo_id, creado_en desc);

alter table ent_conteo_ancla enable row level security;

drop policy if exists ent_conteo_ancla_sel on ent_conteo_ancla;
drop policy if exists ent_conteo_ancla_ins on ent_conteo_ancla;
create policy ent_conteo_ancla_sel on ent_conteo_ancla
  for select to authenticated using (true);
create policy ent_conteo_ancla_ins on ent_conteo_ancla
  for insert to authenticated with check (true);

grant select, insert on ent_conteo_ancla to authenticated;


-- ── El estado VIGENTE de cada conteo ────────────────────────────────────
-- De todas las filas de un conteo manda la más reciente: si la última dice
-- anulada=false, ese conteo está confirmado; si dice true, se desancló.
-- Un conteo sin ninguna fila acá es un BORRADOR (no aparece en esta vista).
create or replace view ent_conteo_estado with (security_invoker = true) as
  select distinct on (conteo_id)
         conteo_id, anulada, creado_en as confirmado_en, creado_por as confirmado_por
    from ent_conteo_ancla
   order by conteo_id, creado_en desc;


-- ── El ANCLA: el conteo CONFIRMADO más reciente ─────────────────────────
-- Antes era "el conteo más reciente" a secas. Ahora un borrador nuevo NO desplaza
-- al ancla vigente: hasta que alguien lo confirme, los saldos siguen contra la
-- foto anterior. Ése es todo el punto del cambio.
create or replace view ent_ancla with (security_invoker = true) as
  select c.id, c.fecha, c.corte
    from ent_conteo c
    join ent_conteo_estado e on e.conteo_id = c.id and e.anulada = false
   order by c.fecha desc, c.creado_en desc
   limit 1;

grant select on ent_conteo_estado to authenticated;
grant select on ent_ancla         to authenticated;

-- ent_entregado_desde_ancla NO se toca: ya lee `ent_ancla`, así que hereda el
-- cambio sola. Antes del primer conteo CONFIRMADO devuelve cero filas, que sigue
-- siendo lo correcto (sin ancla no hay saldo que calcular).


-- ── VERIFICACIÓN (opcional) ─────────────────────────────────────────────
-- 1) Tiene que devolver 2 filas, SELECT e INSERT, ninguna UPDATE ni DELETE:
--      select policyname, cmd from pg_policies
--       where schemaname='public' and tablename='ent_conteo_ancla' order by cmd;
-- 2) Y esto tiene que devolver 0 filas mientras no haya ningún conteo confirmado:
--      select * from ent_ancla;
