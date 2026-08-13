-- ════════════════════════════════════════════════════════════════════════
-- plan_config — la tabla que le falta al PLANIFICADOR
-- 12-ago-2026. LISTO PARA PEGAR UNA SOLA VEZ en el SQL Editor de Supabase.
-- Re-ejecutable: se puede pegar de nuevo sin romper ni duplicar nada.
--
-- Qué pasa hoy sin ella: `nivConfig()` y la config de fechas de cierre reciben
-- 404, lo atrapan y siguen con los VALORES POR DEFECTO del código. O sea que el
-- Planificador funciona, pero cualquier ajuste que Andrea guarde (ritmo, colchón,
-- ventanas estacionales, fechas de última entrega) se pierde al recargar.
-- El 404 en la consola de Safari viene de acá — es ruidoso, no dañino.
--
-- Mismo criterio que las tablas de Entregas: APPEND-ONLY. No se actualiza ni se
-- borra; corregir = insertar otra fila con la misma `clave` y que gane la más
-- reciente (que es exactamente como la lee el código: order creado_en desc y se
-- queda con la primera de cada clave).
-- ════════════════════════════════════════════════════════════════════════

create table if not exists plan_config (
  id         bigint generated always as identity primary key,
  clave      text        not null,          -- ritmo_ventana · colchon_temporada · colchon_semanas ·
                                            -- ventanas_estacionales · cierre_fecha_autowm ·
                                            -- cierre_fecha_resto · cierre_galletas_dic_cj
  valor      jsonb,                         -- jsonb porque hay strings, números, objetos y arrays
  usuario    text,                          -- email de quien lo guardó (puede venir null)
  creado_en  timestamptz not null default now()
);
-- El código pide "la fila más reciente por clave": este índice es justo esa consulta.
create index if not exists plan_config_clave_fecha_idx
  on plan_config (clave, creado_en desc);

alter table plan_config enable row level security;

-- Lectura y alta para cualquier usuario autenticado. Sin update ni delete:
-- el append-only se hace cumplir acá, no solo por convención.
drop policy if exists plan_config_sel on plan_config;
drop policy if exists plan_config_ins on plan_config;
create policy plan_config_sel on plan_config
  for select to authenticated using (true);
create policy plan_config_ins on plan_config
  for insert to authenticated with check (true);

grant usage on schema public to authenticated;
grant select, insert on plan_config to authenticated;


-- ── VERIFICACIÓN (opcional) ─────────────────────────────────────────────
-- Tiene que devolver 2 filas, ambas SELECT o INSERT, ninguna UPDATE ni DELETE:
--   select policyname, cmd from pg_policies
--    where schemaname='public' and tablename='plan_config' order by cmd;
