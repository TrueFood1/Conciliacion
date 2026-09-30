-- ═══════════════════════════════════════════════════════════════════════════
-- ENTREGAS_VISTAS_INVOKER.sql  ·  27-sep-2026  ·  ✅ APLICADO el 27-sep (verificado)
-- Cerrar la fuga de `ent_alisto_lote_efectivo` (y de `v_ent_indeterminado_pendiente`)
--
-- ✅ APLICADO el 27-sep-2026, despues del ensayo (33/33 con ok = true: socia,
--   equipo y postgres con las mismas filas y el mismo md5 en las seis vistas).
--   La prueba de adentro devolvio 2 · 0 · 2 · 49 · 299 · 8.
--   Verificado DESPUES, desde afuera: pg_lector ve {security_invoker=true} en
--   las dos, anon sin privilegios, authenticated con SELECT, 49/49 vistas de
--   public con security_invoker. Por REST con la llave publica:
--   ent_alisto_lote_efectivo paso de 206 */299 a 401 · 42501 · permission denied.
--
-- EL HALLAZGO (medido el 27-sep, inventario tecnico)
--   Las dos vistas nacieron el 8-sep SIN `security_invoker`, o sea que corren
--   con los permisos de su dueño (`postgres`, que se salta la RLS). `anon` tiene
--   SELECT sobre las dos. Con la llave publica —que esta en index.html, en un
--   repo publico— `ent_alisto_lote_efectivo` devolvio 299 filas por REST (lote,
--   cantidad, `excepcion_por`, notas), mientras `ent_alisto_lote` devolvia 0.
--   `v_ent_indeterminado_pendiente` devolvio 0 de 8, pero por la misma puerta.
--   Las otras 47 vistas de `public` ya tienen `security_invoker = true`.
--
-- QUE HACE
--   1. `security_invoker = true` en las dos: la RLS de las tablas de abajo pasa
--      a aplicarse a quien consulta. `authenticated` tiene politica de lectura
--      `using (true)` en todas las tablas que tocan, asi que la app ve lo mismo.
--   2. `revoke all ... from anon` en las dos: la llave publica no necesita
--      ninguna. Dos capas, cada una suficiente sola (el ensayo mide cada una).
--
-- 🔴 A QUIEN MAS ALCANZA. `ent_alisto_lote_efectivo` alimenta cuatro vistas,
--   todas ya con security_invoker: `ent_salido_del_congelador_desde_ancla` (EL
--   SALDO POR LOTE), `ent_entregado_desde_ancla`, `v_ent_excepcion_pendiente` y
--   `v_ent_excepcion_pendiente_pedido`. Hasta hoy leian la de abajo "como dueño";
--   desde el cambio la leen como quien consulta. El ensayo compara las SEIS,
--   como socia, como equipo y como postgres: mismas filas y mismo contenido (md5).
--   Para `anon` las cuatro pasan a RECHAZAR (42501) en vez de devolver 0 filas.
--   Consecuencia conocida: `esquema_check.py` las va a mostrar como `?` hasta
--   que se anoten como cerradas.
--
-- LO QUE NO TOCA: ninguna tabla, politica ni funcion; ningun permiso de
--   `authenticated`, `service_role` ni de los roles propios.
--
-- ANTES DE PEGAR: correr ENSAYO_VISTAS_INVOKER.sql (el mismo bloque DDL, byte
--   a byte, mas las mediciones, y rollback).
-- SE PEGA ENTERO: un `begin`, un `commit`, cero `rollback`.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ═══ DDL · DESDE ACA (ENSAYO_VISTAS_INVOKER.sql copia este bloque tal cual) ═══

alter view public.ent_alisto_lote_efectivo      set (security_invoker = true);
alter view public.v_ent_indeterminado_pendiente set (security_invoker = true);

revoke all on table public.ent_alisto_lote_efectivo,
                    public.v_ent_indeterminado_pendiente
  from anon;

-- ═══ DDL · HASTA ACA ═══


-- 🔴 LA PRUEBA DE QUE ENTRO, ADENTRO DE LA TRANSACCION.
-- ESPERADO: 2 · 0 · 2 · 49 · 299 · 8
select
  (select count(*) from pg_class
    where oid in ('public.ent_alisto_lote_efectivo'::regclass, 'public.v_ent_indeterminado_pendiente'::regclass)
      and 'security_invoker=true' = any(reloptions))                          as invoker,
  (select count(*) from unnest(array['public.ent_alisto_lote_efectivo','public.v_ent_indeterminado_pendiente']) v
    where has_table_privilege('anon', v, 'SELECT,INSERT,UPDATE,DELETE'))      as anon_con_permiso,
  (select count(*) from unnest(array['public.ent_alisto_lote_efectivo','public.v_ent_indeterminado_pendiente']) v
    where has_table_privilege('authenticated', v, 'SELECT'))                   as authenticated_lee,
  (select count(*) from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind = 'v'
      and 'security_invoker=true' = any(c.reloptions))                        as vistas_invoker_total,
  (select count(*) from public.ent_alisto_lote_efectivo)                      as filas_efectivo,
  (select count(*) from public.v_ent_indeterminado_pendiente)                 as filas_indeterminado;

commit;


-- ── VERIFICACION DE DESPUES (fuera de la transaccion) ─────────────────────
-- Con pg_lector: reloptions de las dos = {security_invoker=true}; anon sin
-- privilegios en las dos; 49 de 49 vistas de public con security_invoker.
-- Con la llave publica, por REST:
--   GET /rest/v1/ent_alisto_lote_efectivo?limit=0  (Prefer: count=exact)
--   -> ANTES 206 con */299 ; DESPUES un rechazo (42501), no una lista.
