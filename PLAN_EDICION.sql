-- ═══════════════════════════════════════════════════════════════════════════
-- PLAN_EDICION.sql  ·  11-oct-2026  ·  ✅ APLICADO el 11-oct-2026 y VERIFICADO desde afuera
-- Ensayo 11/11 y pegado 4/4 (Andrea). CC: pg_lector ve edicion uuid · YES, 214 filas, 0 con
-- edicion, políticas intactas; la API REST la sirve (200; una columna inventada da 42703).
-- NO VOLVER A CORRER (la guarda lo frena).
-- DOS PRODUCTOS EL MISMO DÍA (decisión de Andrea, 11-oct): columna opcional
-- `edicion` en plan_overrides.
--
-- QUÉ CAMBIA
--   plan_overrides sigue siendo append-only y gana la edición más reciente de cada
--   fecha. Hasta hoy "la edición" era UNA fila (un producto). Desde ahora las filas
--   que comparten `edicion` son los productos de ese día: el lector junta todas las
--   filas de la fecha con la misma `edicion` que la fila más nueva.
--   · Filas viejas (edicion null): siguen valiendo tal cual, una fila = un día.
--   · Sin constraint nueva, sin tocar ninguna fila existente, sin cambiar permisos:
--     la columna hereda los grants de la tabla y la RLS (insert/select de
--     authenticated) no mira columnas.
--
-- ORDEN: esto se pega ANTES de publicar la rama dos-productos-dia. El código nuevo
-- pide la columna al leer; sin ella la lectura falla y el plan se queda sin ediciones.
-- ANTES DE PEGAR: ENSAYO_PLAN_EDICION.sql (11/11 ok).
-- CÓMO SE LEE: el select de control devuelve 4 filas, TODAS ok = true, antes del commit.
-- Si el editor dice "Success. No rows returned", NO llegó al final: no se aplicó nada.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'plan_overrides' and column_name = 'edicion') then
    raise exception 'plan_overrides ya tiene la columna edicion: este archivo ya se pegó. Mirar antes de seguir.';
  end if;
end $$;

-- ▼▼▼ BLOQUE DDL ▼▼▼
alter table public.plan_overrides add column edicion uuid;
comment on column public.plan_overrides.edicion is
  'Las filas que comparten edicion son los productos de ese día (dos productos el mismo día, 11-oct-2026). Null = fila anterior: un producto por fila.';
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

-- CONTROL, adentro de la transacción y justo antes del commit. ESPERADO: 4 filas, todas ok = true.
select * from (values
  ('C1 la columna edicion existe y es uuid', 'uuid',
     (select data_type from information_schema.columns where table_schema='public' and table_name='plan_overrides' and column_name='edicion'),
     (select data_type from information_schema.columns where table_schema='public' and table_name='plan_overrides' and column_name='edicion') = 'uuid'),
  ('C2 la columna admite vacío (las filas viejas siguen valiendo)', 'YES',
     (select is_nullable from information_schema.columns where table_schema='public' and table_name='plan_overrides' and column_name='edicion'),
     (select is_nullable from information_schema.columns where table_schema='public' and table_name='plan_overrides' and column_name='edicion') = 'YES'),
  ('C3 ninguna fila existente tiene edicion', '0',
     (select count(*)::text from plan_overrides where edicion is not null),
     (select count(*) from plan_overrides where edicion is not null) = 0),
  ('C4 las políticas de la tabla siguen siendo las dos de siempre', 'auth insert · auth read',
     (select string_agg(polname, ' · ' order by polname) from pg_policy where polrelid = 'public.plan_overrides'::regclass),
     (select string_agg(polname, ' · ' order by polname) from pg_policy where polrelid = 'public.plan_overrides'::regclass) = 'auth insert · auth read')
) as t(prueba, esperado, obtenido, ok);

commit;
