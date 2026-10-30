-- ════════════════════════════════════════════════════════════════════════
-- CAMBIO_DEVOLUCION_CAMBIO.sql · 30-oct-2026 · b150
-- ⛔ NO SE CORRIO. Este header se cambia DESPUES de verificar, nunca antes.
--
-- QUE PIDIO ANDREA (30-oct): al registrar una devolucion, Daniel elige que se hizo.
--   1 · SOLO DEVOLUCION  -> como hoy: el producto vuelve a su lote (suma) y queda
--                           la nota de credito pendiente para las socias.
--   2 · CAMBIO           -> el producto devuelto vuelve a su lote igual (se le
--                           cambia la bolsa y se vuelve a vender), y sale OTRO del
--                           mismo producto, del lote que Daniel elige: eso RESTA.
--                           NO hay nota de credito (el cliente se quedo con lo que
--                           pago) y NO hay traslado interno (en Odoo no cambio nada
--                           neto: salio 1 y volvio 1).
-- Caso que lo abrio: devolucion 68 (Abner, 1 paquete de Buns, lote 286, bolsa
-- rota). Esa ya tiene su NC hecha y NO se toca: queda como 'devolucion'.
--
-- LA ELECCION ES POR DEVOLUCION ENTERA, NO POR LINEA. Tres razones del esquema:
--   · la nota de credito es UNA por devolucion (`ent_odoo_pendiente.devolucion_id`);
--     por linea habria que partirla, y una NC a medias es peor que dos registros.
--   · la causa ya es por devolucion, y el cambio es una sola conversacion con el
--     cliente, no un atributo de cada bolsa.
--   · el candado de abajo (§D) se escribe sobre la cabecera: "una devolucion que es
--     cambio no lleva NC". Por linea no hay donde colgarlo.
--   Si alguna vez llega una devolucion mixta (cambian una cosa y devuelven otra),
--   se registran DOS: una de cada tipo. Sale exacta y sin columna nueva.
--
-- QUE TRAE, y nada mas:
--   §A  `ent_devolucion.resolucion` ('devolucion' | 'cambio'), NOT NULL con
--       default 'devolucion': las filas que ya existen quedan como lo que fueron.
--   §B  `ent_devolucion_vigente` la expone, AL FINAL (ver la nota alla).
--   §C  `ent_devolucion_reemplazo`: lo que SALE en lugar de lo devuelto. Misma
--       forma que `ent_devolucion_linea` (producto, lote canonico, uds, unidad
--       congelada), y un candado de ESCALA que aquella no tiene.
--   §D  `ent_reemplazo_desde_ancla`: lo que el reemplazo RESTA al saldo por lote.
--       La lee `_rpCalcularPuntas` (index.html) al lado de las devoluciones.
--   §E  `ent_odoo_pendiente_ins` cambia: no entra un pendiente de Odoo colgado de
--       una devolucion que es cambio. Ni NC ni traslado. Es el "Odoo descontaria
--       dos veces" puesto en la base, no solo en la pantalla.
--
-- LO QUE NO CAMBIA, a proposito:
--   · El reemplazo NO es un pedido. No pasa por ent_pedido/ent_alisto/ent_salida:
--     ese camino dispara el traslado interno (`rpGuardar`) y la automatizacion de
--     Odoo (`entOdooAuto`), y aparece en Historial y en Pendientes como una salida
--     sin factura — una regalia que no fue. Cuelga de la devolucion y vive y muere
--     con ella: anular la devolucion deshace LAS DOS mitades, porque las dos vistas
--     del saldo pasan por `ent_devolucion_vigente`.
--   · Sin update ni delete. Corregir es anular e insertar, como en todo el modulo.
--   · Odoo no se toca.
--
-- ⚠️ SE PEGA ANTES DE PUBLICAR b150. `esquema_check.py` lo exige (dos objetos
-- nuevos: ent_devolucion_reemplazo y ent_reemplazo_desde_ancla) y la pantalla de
-- Devoluciones lee `resolucion` desde que abre.
--
-- ⚠️ DE UNA SOLA CORRIDA. El bloque arranca con una guarda que grita si la columna
-- o la tabla ya existen, y la transaccion entera se deshace sin escribir nada.
--
-- COMO SE PEGA: EL ARCHIVO ENTERO de una vez (Cmd+A en el editor, despues Run). Es
-- un solo begin, un solo commit y CERO rollback; la ultima fila que muestra el editor
-- es la de control, con lo ESPERADO escrito al lado. Las verificaciones de despues
-- (V1-V4) van al pie, COMENTADAS: se corren aparte, una por una, despues del commit.
-- Antes de pegar, opcional: la huella del saldo, para comparar con V3.
--   select producto_id, sum(uds) as uds, count(*) as filas
--     from ent_devuelto_desde_ancla group by 1 order by 1;
-- ════════════════════════════════════════════════════════════════════════
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

-- ── LA PRUEBA DE QUE ESTO CORRIO · ADENTRO DE LA TRANSACCION ────────────
-- Si el editor dice "Success. No rows returned", NO llego hasta aca.
-- Si da otros numeros: `rollback;` a mano o cerrar la pestaña. Nada quedo escrito.
select (select count(*) from information_schema.columns
         where table_schema = 'public' and table_name = 'ent_devolucion'
           and column_name = 'resolucion')                                as columna,
       (select count(*) from pg_constraint
         where conname in ('ent_devolucion_resolucion_ok',
                           'ent_devolucion_reemplazo_escala_ok'))         as checks,
       (select count(*) from information_schema.columns
         where table_schema = 'public' and table_name = 'ent_devolucion_vigente'
           and column_name = 'resolucion')                                as vigente,
       (select count(*) from pg_policies
         where schemaname = 'public' and tablename = 'ent_devolucion_reemplazo') as politicas,
       (select count(*) from pg_class
         where oid = 'public.ent_reemplazo_desde_ancla'::regclass
           and 'security_invoker=true' = any(reloptions))                as vista_invoker,
       (select count(*) from pg_policies
         where schemaname = 'public' and tablename = 'ent_odoo_pendiente'
           and policyname = 'ent_odoo_pendiente_ins'
           and with_check like '%cambio%')                                as candado_nc,
       has_table_privilege('anon', 'public.ent_devolucion_reemplazo', 'select') as anon_lee,
       (select count(*) from public.ent_devolucion
         where resolucion <> 'devolucion')                                as filas_cambio;
-- ESPERADO: 1 · 2 · 1 · 7 · 1 · 1 · f · 0
--   politicas 7 = las 2 de §C + las 5 que pone el event trigger del asistente.

commit;


-- ════════════════════════════════════════════════════════════════════════
-- V · DESPUES · VERIFICAR, fuera de la transaccion. Solo lectura, una por una.
-- ════════════════════════════════════════════════════════════════════════
-- V1 · las devoluciones de antes quedaron como 'devolucion' (la 68 entre ellas).
--   select resolucion, count(*) from ent_devolucion group by 1 order by 1;
--   ESPERADO: una sola fila, 'devolucion', con el total de devoluciones.
--
-- V2 · la tabla y la vista nuevas, vacias.
--   select (select count(*) from ent_devolucion_reemplazo)  as reemplazos,
--          (select count(*) from ent_reemplazo_desde_ancla) as en_saldo;
--   ESPERADO: 0 · 0
--
-- V3 · la huella del saldo: IGUAL a la de antes de pegar.
--   select producto_id, sum(uds) as uds, count(*) as filas
--     from ent_devuelto_desde_ancla group by 1 order by 1;
--
-- V4 · las politicas de ent_odoo_pendiente: las mismas de siempre, con el insert nuevo.
--   select policyname, cmd, with_check from pg_policies
--    where tablename = 'ent_odoo_pendiente' order by policyname;
