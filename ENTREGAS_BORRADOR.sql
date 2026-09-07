-- ════════════════════════════════════════════════════════════════════════
-- MÓDULO DE ENTREGAS · BORRADOR PERSISTENTE DEL ALISTO
-- Diseño aprobado por Andrea el 7-sep-2026. LISTO PARA PEGAR UNA SOLA VEZ
-- en el SQL Editor de Supabase.
--
-- Se puede correr más de una vez sin romper nada (todo es "if not exists" /
-- "or replace" / "drop policy if exists").
--
-- ⚠️ HASTA QUE ESTO ESTÉ PEGADO, EL CÓDIGO QUE LO USA NO VA A `main`.
--    Es la regla que dejó `esquema_check.py` después del 17-ago, cuando se
--    publicó código que dependía de ENTREGAS_ETAPAS.sql sin pegar y Andrea
--    lo descubrió el 18 registrando entregas reales.
--
-- ── POR QUÉ EXISTE ──────────────────────────────────────────────────────
-- El 7-sep-2026 Daniel se quedó sin batería en el iPad a mitad de la entrega
-- de Automercado. Terminó de entregar de memoria y los lotes de Pan Blanco se
-- perdieron: ocho horas después la entrega no estaba en Truefie y el dato
-- dependía de que contestara el chofer.
--
-- El bloqueo duro —no se cierra una entrega sin el lote de todos los
-- productos— NO se toca, y la razón es de Andrea: el único que sabe qué lote
-- salió es Daniel, y solo lo sabe mientras las cajas están enfrente. Un
-- "pendiente de lote" lo vería Andrea, que no es quien entrega: sería un hueco
-- permanente, no una tarea. La fricción de anotarlo es lo que hace que se
-- anote.
--
-- Este borrador existe para que ese bloqueo sea VIVIBLE: la espera puede durar
-- horas o días sin que se pierda nada, y sin que el aparato sea el dueño del
-- dato.
--
-- ── LO QUE ESTA TABLA NO HACE ───────────────────────────────────────────
-- ⛔ NO TOCA NINGÚN SALDO POR LOTE. Nada se descuenta del inventario hasta que
--    Daniel cierra la entrega. Un borrador abandonado no puede dejar producto
--    restado. Es decisión no negociable de Andrea, y es del mismo tipo que el
--    defecto ya medido en `ent_salido_del_congelador_desde_ancla` (descontar
--    en el momento equivocado): no se repite por otra vía.
--    Se hace cumplir por construcción: NINGUNA vista del saldo nombra esta
--    tabla, y no lleva trigger. Si alguna vez alguien la mete en el cálculo,
--    está rompiendo esto a propósito.
--
-- ── LA LLAVE: POR ENTREGA, NO POR APARATO NI POR SESIÓN ─────────────────
-- Medido antes de diseñar: mientras Daniel alista, el `ent_pedido` TODAVÍA NO
-- EXISTE — se inserta dentro de `despConfirmar()`, o sea al cerrar. Así que
-- "identificar el borrador por pedido" no tiene referente en el momento en que
-- el borrador hace falta. Lo que sí existe y es estable:
--   · camino con factura → `factura_id` de Odoo (account.move.id)
--   · camino manual      → un uuid que genera la pantalla al primer toque
-- De ahí el par (origen, ref). Al cerrar, la fila de cierre guarda `pedido_id`
-- y el borrador queda ligado al pedido para siempre.
--
-- La alternativa —crear el `ent_pedido` desde el primer toque— se descartó con
-- razón medida: obligaría a estampar `fecha_despacho` días antes de que la
-- entrega ocurra, que es exactamente el bug abierto del pedido 44 (nació con
-- fecha 3-sep estando su alisto fechado el 7-sep). Y dejaría un pedido
-- huérfano por cada borrador abandonado.
-- ════════════════════════════════════════════════════════════════════════


-- ── 1 · LA TABLA ────────────────────────────────────────────────────────
-- APPEND-ONLY, igual que todo `ent_*`: un borrador que se actualiza NO pisa al
-- anterior, inserta una fila nueva. La cadena de filas es cómo se armó la
-- entrega, y es evidencia: no se borra ni cuando la entrega se cierra.
--
-- `datos` es la foto entera en JSONB, no un delta. Es la misma forma que ya usa
-- la tabla `conteos` del inventario, y por la misma razón: reconstruir por
-- reproducción de deltas es más frágil, y la foto sobrevive a que cambie la
-- forma del borrador sin migrar nada.
-- Costo medido a ojo: ~30 filas por entrega × ~2 KB ≈ 60 KB; con ~40 entregas
-- al mes son ~2,4 MB/mes. Irrelevante para el plan Free; engorda un poco el
-- respaldo diario, que desde el 7-sep-2026 sí existe.
create table if not exists ent_alisto_borrador (
  id          bigint generated always as identity primary key,
  origen      text        not null check (origen in ('factura','manual')),
  ref         text        not null,            -- factura_id de Odoo, o un uuid
  estado      text        not null default 'abierto'
                          check (estado in ('abierto','cerrado','descartado')),
  -- Se llena SOLO en la fila de cierre. Antes de cerrar no hay pedido que
  -- referenciar, y esa es justamente la razón de que la llave sea (origen, ref).
  pedido_id   bigint      references ent_pedido(id),
  datos       jsonb       not null,
  -- De qué aparato vino. Es diagnóstico, NO es parte de la identidad: el
  -- borrador se sigue en el teléfono aunque se haya empezado en el iPad.
  dispositivo text,
  nota        text,
  creado_en   timestamptz not null default now(),
  creado_por  text        not null             -- email del usuario de Supabase
);

-- Para "dame el estado actual de esta entrega": la fila más reciente del par.
create index if not exists ent_alisto_borrador_ref_idx
  on ent_alisto_borrador (origen, ref, creado_en desc);
-- Para "¿qué quedó abierto?", que es la pantalla del requisito 2. Parcial a
-- propósito: lo cerrado no se consulta por estado, se consulta por su entrega.
create index if not exists ent_alisto_borrador_abierto_idx
  on ent_alisto_borrador (creado_en desc) where estado = 'abierto';


-- ── 2 · EL VIGENTE ──────────────────────────────────────────────────────
-- Mismo idioma que `ent_alisto_vigente` y `ent_pedido_factura_vigente`: gana la
-- fila más reciente de cada llave. Cerrar es INSERTAR una fila con
-- estado='cerrado', no actualizar la anterior — por eso el borrador deja de
-- estar activo sin dejar de existir (requisito 6).
--
-- security_invoker = true es OBLIGATORIO en Supabase: sin eso la vista corre con
-- los permisos de quien la creó y se saltaría el RLS de la tabla de abajo. Es la
-- lección del 24-ago con `v_acceso_usuario`.
create or replace view ent_alisto_borrador_vigente with (security_invoker = true) as
  select distinct on (origen, ref)
         id, origen, ref, estado, pedido_id, datos, dispositivo, nota,
         creado_en, creado_por
    from ent_alisto_borrador
   order by origen, ref, creado_en desc;

grant select on ent_alisto_borrador_vigente to authenticated;


-- ── 3 · RLS ─────────────────────────────────────────────────────────────
-- Igual que el resto de `ent_*`: entra quien tiene sesión.
-- Lectura y alta, NADA de update ni delete. Append-only se hace cumplir ACÁ, no
-- solo por convención: sin política, Postgres las niega.
alter table ent_alisto_borrador enable row level security;

drop policy if exists ent_alisto_borrador_sel on ent_alisto_borrador;
drop policy if exists ent_alisto_borrador_ins on ent_alisto_borrador;
create policy ent_alisto_borrador_sel on ent_alisto_borrador
  for select to authenticated using (true);
create policy ent_alisto_borrador_ins on ent_alisto_borrador
  for insert to authenticated with check (true);


-- ── 4 · CÓMO VERIFICAR QUE QUEDÓ ────────────────────────────────────────
-- Pegar esto DESPUÉS y mirar que devuelva las tres filas esperadas:
--
--   select 'tabla' as que, count(*)::text as v from ent_alisto_borrador
--   union all
--   select 'vista', count(*)::text from ent_alisto_borrador_vigente
--   union all
--   select 'políticas', count(*)::text from pg_policies
--    where tablename='ent_alisto_borrador';
--
-- Esperado recién pegado: tabla 0 · vista 0 · políticas 2.
-- Si "políticas" da 0, la RLS quedó a medias y la tabla no es escribible por
-- nadie; si da más de 2, hay políticas viejas de otra corrida.


-- ── 5 · LO QUE ESTA TABLA DELIBERADAMENTE NO RESUELVE ───────────────────
-- Andrea decidió el 7-sep registrar dos salidas viejas con el lote marcado como
-- NO DETERMINADO, con la razón escrita y quién lo decidió:
--   · el traslado del summit (WH/INT/00137, 2-sep), y
--   · el Pan Blanco de la entrega de Automercado del 7-sep.
-- Eso es una EXCEPCIÓN que registra Andrea, no Daniel, y el bloqueo duro de la
-- pantalla de alisto no se toca. No se construye acá y esta tabla no lo cubre:
-- vive en `ent_alisto_lote`, no en el borrador. `datos` es JSONB, así que nada
-- de lo de acá le cierra la puerta.
