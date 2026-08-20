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

-- ── LAS CLAVES QUE EL CÓDIGO REALMENTE USA (auditadas 17-ago-2026) ──────
-- No hay ninguna más. Si algún día aparece una clave que no está en esta lista, es basura:
-- nadie la lee.
--
--   clave                    tipo        quién la lee            quién la escribe
--   ─────────────────────────────────────────────────────────────────────────────
--   ritmo_ventana            número      nivConfig()             NADIE (sin UI)
--   colchon_temporada        número      nivConfig()             NADIE (sin UI)
--   colchon_semanas          objeto      nivConfig()             NADIE (sin UI)
--   ventanas_estacionales    array       nivConfig()             NADIE (sin UI)
--   medir_lunes_frac         número 0–1  nivConfig()             NADIE (sin UI)
--   cierre_fecha_autowm      fecha       cierreConfig()          cierreGuardar()
--   cierre_fecha_resto       fecha       cierreConfig()          cierreGuardar()
--   cierre_galletas_dic_cj   número      cierreConfig()          cierreGuardar()
--
-- OJO con la columna "quién la escribe": las cinco primeras se LEEN pero no las guarda
-- ninguna pantalla. Hoy solo existen como default del código. Crear la tabla no las hace
-- editables por sí solo — para eso hace falta UI, y eso no está construido.
--
-- Lo que NO vive acá, para que nadie lo busque en esta tabla:
--   · El número de personas por semana → tabla `semana_capacidad` (ya existe).
--   · Las ediciones del plan por día    → tabla `plan_overrides` (ya existe).
--   · La meta de cierre (las ~966 cj)   → NO es config: la calcula cierreMeta() contra Odoo
--                                          cada vez, a partir de la venta real del año pasado.
--                                          Lo único configurable de ahí es el override manual
--                                          de galletas, que sí es una clave (cierre_galletas_dic_cj).

create table if not exists plan_config (
  id         bigint generated always as identity primary key,
  clave      text        not null,          -- ver la tabla de claves de arriba
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


-- ── SEMILLA: el único parámetro que hoy tiene sentido dejar escrito ─────
-- `medir_lunes_frac` = cuánto del LUNES SIGUIENTE entra en "Por medir". El código ya usa 0,5
-- por defecto; sembrarlo acá es lo que lo vuelve EDITABLE sin tocar código — cambiarlo es
-- insertar otra fila con la misma clave, y gana la más reciente.
-- Por qué 0,5: el lunes en la mañana se mide lo que falta para ESE día más toda la producción
-- de la semana, y del lunes siguiente solo la mitad, porque esa mañana se vuelve a medir la
-- otra mitad. El traslape es deliberado.
-- Guardado con `where not exists` para que re-pegar el archivo no duplique la semilla.
insert into plan_config (clave, valor, usuario)
select 'medir_lunes_frac', '0.5'::jsonb, 'semilla'
where not exists (select 1 from plan_config where clave = 'medir_lunes_frac');


-- ── VERIFICACIÓN (opcional) ─────────────────────────────────────────────
-- Tiene que devolver 2 filas, ambas SELECT o INSERT, ninguna UPDATE ni DELETE:
--   select policyname, cmd from pg_policies
--    where schemaname='public' and tablename='plan_config' order by cmd;
