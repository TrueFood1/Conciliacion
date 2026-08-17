-- ════════════════════════════════════════════════════════════════════════
-- ENTREGAS · PREPARAR y ENTREGAR como DOS ETAPAS
-- 16-ago-2026. SEXTO PEGADO, después de ENTREGAS_ESQUEMA / ANCLA / SALIDAS /
-- CLASIFICACION / DESPACHOS. Re-ejecutable: todo es "if not exists" /
-- "or replace" / "drop policy if exists".
--
-- Implementa ENTREGAS_ETAPAS.md §5.1 a §5.5. Se pega ENTES de publicar el build
-- nuevo: el código nuevo escribe en ent_salida, y si la tabla no existe todavía
-- el botón "Preparar y entregar" falla a mitad de la cadena.
--
-- ── QUÉ PROBLEMA RESUELVE ──────────────────────────────────────────────
-- Hoy el módulo trata la entrega como UN SOLO momento: Daniel confirma los lotes
-- y el pedido desaparece. La operación no es así — Automercado y Walmart se
-- validan 6:30-7:00 y salen 7:30 — y con un solo momento NO SE PUEDE SABER si un
-- pedido está armado esperando el camión o si ya salió. Ese es justo el estado
-- que alguien necesita mirar entre las 6:30 y las 7:30.
--
-- ── LOS TRES ESTADOS NO SON TRES FILAS ─────────────────────────────────
-- Dos de los tres se derivan de una AUSENCIA. Es lo que mantiene el append-only
-- sin una columna de estado que haya que actualizar (y que, en un esquema donde
-- el UPDATE está negado por permiso, sería imposible de mantener):
--
--   por preparar → hay factura en Odoo y NO hay pedido en Supabase
--   preparado    → hay alisto vigente y NO hay salida
--   entregado    → hay alisto vigente Y salida
--
-- No se crea fila para "por preparar": escribiría filas para pedidos que quizá
-- nunca se despachan.
--
-- ── LO QUE YA EXISTE Y NO SE REHACE ────────────────────────────────────
-- El evento de PREPARACIÓN ya se guarda: `ent_alisto` es exactamente eso —"Daniel
-- alistó esto, con estos lotes, a esta hora"— y `creado_en` es la hora de
-- preparación. Lo que falta es la mitad que sigue: la salida. Nada de lo ya
-- guardado pierde información.
-- ════════════════════════════════════════════════════════════════════════


-- ── 1 · TABLA NUEVA: ent_salida (§5.1) ──────────────────────────────────
-- CUELGA DEL ALISTO, NO DEL PEDIDO. El alisto es el que lleva los lotes y las
-- cantidades reales; si Daniel corrige e inserta otro alisto, colgar del pedido
-- dejaría sin respuesta la pregunta "¿cuál alisto fue el que salió?".
--
-- `salida_en` es la hora REAL de salida y `creado_en` es cuándo se registró. Son
-- dos cosas distintas a propósito: si alguien marca a las 8:10 una salida que fue
-- a las 7:30, el registro puede decir la verdad sin perder la trazabilidad de
-- cuándo se escribió. Hoy la pantalla usa now() para las dos; el día que haga
-- falta corregir una hora, la columna ya está.
create table if not exists ent_salida (
  id          bigint generated always as identity primary key,
  alisto_id   bigint  not null references ent_alisto(id),
  salida_en   timestamptz not null default now(),  -- la hora REAL de salida
  nota        text,
  creado_en   timestamptz not null default now(),  -- cuándo se registró
  creado_por  text    not null                     -- email del usuario de Supabase
);
create index if not exists ent_salida_alisto_idx
  on ent_salida (alisto_id, creado_en desc);
create index if not exists ent_salida_salida_idx
  on ent_salida (salida_en);

comment on table  ent_salida            is 'La segunda etapa: el pedido salió del congelador hacia el cliente. Cuelga del alisto.';
comment on column ent_salida.salida_en  is 'Hora REAL de salida. Es la "Fecha de despacho" del AB-RE-04.';
comment on column ent_salida.creado_en  is 'Cuándo se registró la salida. Puede ser posterior a salida_en.';


-- ── 2 · TABLA NUEVA: ent_anulacion (§5.3 · HALLAZGO 1) ──────────────────
-- EL COMENTARIO DEL ESQUEMA PROMETÍA ALGO QUE POSTGRES NIEGA. `ent_alisto.anulado`
-- dice "me equivoqué de pedido: se anula, no se borra", pero las políticas y los
-- grants de ent_alisto son `select, insert` y nada más: el UPDATE está negado.
-- Anular un alisto es IMPOSIBLE hoy.
--
-- Esto no es cosmético. Sin anulación no existe el "deshacer preparación", y sin
-- él un pedido que se devuelve al congelador (se canceló, el cliente no recibió)
-- deja el saldo por lote mal PARA SIEMPRE y nadie tiene cómo corregirlo — el
-- saldo se descuenta al preparar (§6 del documento).
--
-- Salida append-only: anular es INSERTAR acá.
create table if not exists ent_anulacion (
  id          bigint generated always as identity primary key,
  entidad     text    not null check (entidad in ('alisto','salida')),
  entidad_id  bigint  not null,
  motivo      text,
  creado_en   timestamptz not null default now(),
  creado_por  text    not null
);
create index if not exists ent_anulacion_ent_idx
  on ent_anulacion (entidad, entidad_id);

comment on table ent_anulacion is
  'Anular = insertar acá. No hay FK porque apunta a dos tablas (alisto o salida); la app siempre escribe el par (entidad, entidad_id).';

-- `ent_alisto.anulado` SE QUEDA: hay filas escritas con esa columna y las vistas
-- la siguen respetando. Lo que cambia es que a partir de acá la anulación de
-- verdad vive en ent_anulacion, que es la única que se puede escribir.


-- ── 3 · RLS Y GRANTS de las dos tablas nuevas ───────────────────────────
-- Igual que el resto del módulo: select + insert, y nada más. Sin update ni
-- delete a nivel de política Y a nivel de grant — doble candado sobre el
-- append-only, que es lo que hace que ent_anulacion no herede el mismo problema
-- que vino a resolver.
alter table ent_salida    enable row level security;
alter table ent_anulacion enable row level security;

drop policy if exists ent_salida_sel on ent_salida;
drop policy if exists ent_salida_ins on ent_salida;
create policy ent_salida_sel on ent_salida
  for select to authenticated using (true);
create policy ent_salida_ins on ent_salida
  for insert to authenticated with check (true);

drop policy if exists ent_anulacion_sel on ent_anulacion;
drop policy if exists ent_anulacion_ins on ent_anulacion;
create policy ent_anulacion_sel on ent_anulacion
  for select to authenticated using (true);
create policy ent_anulacion_ins on ent_anulacion
  for insert to authenticated with check (true);

grant select, insert on ent_salida    to authenticated;
grant select, insert on ent_anulacion to authenticated;


-- ── 4 · UNA SOLA DEFINICIÓN DE "VIGENTE" ────────────────────────────────
-- Antes, "el alisto vigente de cada pedido" estaba escrito a mano dentro de dos
-- vistas distintas (ent_entregado_desde_ancla con un max() correlacionado, y
-- v_ent_factura_despachada con un join lateral). Dos redacciones de la misma
-- regla es una que se va a desincronizar. Ahora hay UNA.
--
-- Vigente = el más reciente de los NO anulados. Se miran las dos formas de
-- anulación: la columna vieja (filas ya escritas) y ent_anulacion (la de verdad).
create or replace view ent_alisto_vigente with (security_invoker = true) as
  select distinct on (a.pedido_id)
         a.id          as alisto_id,
         a.pedido_id,
         a.responsable,
         a.creado_en   as preparado_en,
         a.creado_por
    from ent_alisto a
   where a.anulado = false
     and not exists (select 1 from ent_anulacion x
                      where x.entidad = 'alisto' and x.entidad_id = a.id)
   order by a.pedido_id, a.creado_en desc;

-- La salida vigente de cada alisto. Se puede deshacer una entrega (marcada por
-- error) sin deshacer la preparación: se anula la salida y el pedido vuelve a
-- "Preparado", que es exactamente lo que hay que hacer.
create or replace view ent_salida_vigente with (security_invoker = true) as
  select distinct on (s.alisto_id)
         s.id        as salida_id,
         s.alisto_id,
         s.salida_en,
         s.nota,
         s.creado_en as registrado_en,
         s.creado_por
    from ent_salida s
   where not exists (select 1 from ent_anulacion x
                      where x.entidad = 'salida' and x.entidad_id = s.id)
   order by s.alisto_id, s.creado_en desc;

grant select on ent_alisto_vigente to authenticated;
grant select on ent_salida_vigente to authenticated;


-- ── 5 · EL SALDO SE DESCUENTA AL PREPARAR — y la vista se RENOMBRA (§6) ──
-- El ancla cuenta lo que está EN EL CONGELADOR. Un pedido preparado ya salió de
-- ahí. Si el saldo no bajara al preparar, el siguiente pedido de esa misma mañana
-- vería un lote que ya está comprometido, Daniel lo elegiría, iría a buscarlo y
-- no estaría — que es exactamente el error que el selector de lotes existe para
-- evitar.
--
-- NO HACE FALTA CAMBIAR LA LÓGICA: ya restaba desde ent_alisto_lote, o sea que ya
-- descontaba al preparar. Lo que cambia es EL NOMBRE, porque pasó a ser mentira:
-- no es "entregado", es "salido del congelador". En un módulo cuyo punto entero
-- es que las palabras signifiquen algo, un nombre que miente cuesta caro.
create or replace view ent_salido_del_congelador_desde_ancla with (security_invoker = true) as
  select al.lote, ali.producto_id, sum(al.cant_uds) as uds
    from ent_alisto_lote   al
    join ent_alisto_linea  ali on ali.id       = al.linea_id
    join ent_alisto_vigente av  on av.alisto_id = ali.alisto_id
   where av.preparado_en > (select corte from ent_ancla)
   group by al.lote, ali.producto_id;

-- ALIAS DEL NOMBRE VIEJO, VIVO UN SOLO BUILD. rpCalcSaldos() todavía lo consulta;
-- romperlo de golpe dejaría el selector de lotes sin saldos —o sea, ofreciendo
-- lotes que no existen— justo el día de la publicación.
-- ⚠️ BORRAR EN EL BUILD SIGUIENTE (checklist §10.6 de ENTREGAS_ETAPAS.md):
--      drop view if exists ent_entregado_desde_ancla;
create or replace view ent_entregado_desde_ancla with (security_invoker = true) as
  select lote, producto_id, uds from ent_salido_del_congelador_desde_ancla;

grant select on ent_salido_del_congelador_desde_ancla to authenticated;
grant select on ent_entregado_desde_ancla             to authenticated;


-- ── 6 · v_ent_factura_despachada: se corrige el HALLAZGO 2 (§5.4) ───────
-- Se creó SIN `with (security_invoker = true)`, a diferencia de las otras vistas
-- del módulo: corre con los permisos de quien la creó y se salta el RLS. Acá no
-- expone nada delicado (ids de factura), pero contradice la regla escrita en el
-- propio esquema, y una excepción sin motivo es la que después se copia.
--
-- Semántica SIN CAMBIOS a propósito: una factura sale de la bandeja "Por
-- preparar" en cuanto tiene alisto vigente, esté preparada o ya entregada. Un
-- pedido creado pero sin confirmar SIGUE en la bandeja — si Daniel abrió el
-- pedido y no lo terminó, tiene que volver a verlo.
--
-- Nota para el pegado: `create or replace view` conserva nombres y tipos de las
-- columnas, que son los mismos cuatro de antes.
create or replace view v_ent_factura_despachada with (security_invoker = true) as
  select p.factura_id,
         p.id            as pedido_id,
         av.preparado_en as confirmado_en,
         av.creado_por
    from ent_pedido p
    join ent_alisto_vigente av on av.pedido_id = p.id
   where p.origen = 'factura' and p.factura_id is not null;

grant select on v_ent_factura_despachada to authenticated;


-- ── 7 · VISTA NUEVA: v_ent_pedido_estado (§5.2) ─────────────────────────
-- De la que comen las secciones PREPARADO y el pie "Entregados hoy" de la
-- bandeja, y la pantalla Buscar.
--
-- NO TOCA ODOO: sale entera de Supabase, así que se dibuja al instante, sin
-- esperar los ~40 s del arranque en frío del proxy. Esa es la razón de que sea
-- una vista y no un armado en el navegador: lo que hay que hacer AHORA MISMO
-- —sacar lo que está armado— no puede depender de que despierte un servidor.
--
-- Solo devuelve pedidos CON alisto vigente, o sea preparados y entregados. "Por
-- preparar" no está acá porque no es una fila: es una factura de Odoo sin pedido.
create or replace view v_ent_pedido_estado with (security_invoker = true) as
  select p.id                                   as pedido_id,
         p.fecha_despacho,
         coalesce(fv.factura_id,     p.factura_id)     as factura_id,
         coalesce(fv.factura_nombre, p.factura_nombre) as factura_nombre,
         p.cliente_id,
         p.cliente_nombre,
         p.origen,
         mv.motivo,
         av.alisto_id,
         av.responsable,
         av.preparado_en,
         sv.salida_id,
         sv.salida_en,
         sv.registrado_en                       as salida_registrada_en,
         nl.n                                   as n_lineas,
         case when sv.salida_id is not null then 'entregado' else 'preparado' end as estado,
         -- La fecha del AB-RE-04 (§4.3): la salida REAL, con fallback a la fecha
         -- del pedido para las filas viejas que nunca tuvieron salida propia.
         coalesce(sv.salida_en, p.fecha_despacho::timestamptz) as fecha_ab_re_04
    from ent_pedido p
    join ent_alisto_vigente av on av.pedido_id = p.id
    left join ent_salida_vigente sv on sv.alisto_id = av.alisto_id
    left join ent_pedido_factura_vigente fv
           on fv.pedido_id = p.id and fv.anulado = false
    left join ent_pedido_motivo_vigente mv on mv.pedido_id = p.id
    left join lateral (select count(*)::int as n
                         from ent_alisto_linea l
                        where l.alisto_id = av.alisto_id) nl on true;

grant select on v_ent_pedido_estado to authenticated;


-- ── 8 · BACKFILL (§5.5) — OBLIGATORIO, y con corte congelado ────────────
-- Todo lo confirmado ANTES de que existieran las dos etapas tiene alisto y no
-- tiene salida, o sea que aparecería como "preparado" PARA SIEMPRE: una lista de
-- pendientes fantasma el primer día, que es la forma más rápida de que alguien
-- deje de mirar la lista.
--
-- ⚠️ EL CORTE SE CONGELA EN LA PRIMERA CORRIDA. Sin esto, volver a pegar el
-- archivo dentro de un mes marcaría como "entregado" todo lo que estuviera
-- preparado en ese momento esperando el camión — inventando horas de salida que
-- nadie midió. Por eso el corte se guarda en una tabla y no se recalcula.
create table if not exists ent_migracion (
  clave      text primary key,
  corte      timestamptz not null default now(),
  nota       text,
  creado_en  timestamptz not null default now()
);
alter table ent_migracion enable row level security;
drop policy if exists ent_migracion_sel on ent_migracion;
create policy ent_migracion_sel on ent_migracion
  for select to authenticated using (true);
grant select on ent_migracion to authenticated;
-- Sin grant de insert: esta tabla la escribe el pegado, no la aplicación.

insert into ent_migracion (clave, nota)
select 'entregas_etapas',
       'Corte del backfill de ent_salida. Todo alisto anterior a este instante se considera confirmado bajo el modelo de una sola etapa.'
 where not exists (select 1 from ent_migracion where clave = 'entregas_etapas');

-- LA NOTA DE CADA FILA IMPORTA: deja dicho que esa hora es la de PREPARACIÓN
-- usada como aproximación, NO una medición de cuándo salió el camión. (Regla de
-- la bitácora, 9-ago: medido vs objetivo, no confundirlos. Confundirlos costó
-- una sesión.)
insert into ent_salida (alisto_id, salida_en, nota, creado_por)
select a.id,
       a.creado_en,
       'backfill: confirmado antes de que existieran las dos etapas',
       'migracion:ENTREGAS_ETAPAS.sql'
  from ent_alisto a
 where a.creado_en <= (select corte from ent_migracion where clave = 'entregas_etapas')
   and not exists (select 1 from ent_salida s where s.alisto_id = a.id);


-- ── 9 · EL AB-RE-04, ACTUALIZADO ────────────────────────────────────────
-- Columnas del documento controlado de Daniel y de dónde sale cada una. Cambia
-- UNA respecto del esquema del 12-ago, y es la primera:
--   Fecha de despacho  → v_ent_pedido_estado.fecha_ab_re_04
--                        (= ent_salida.salida_en, la salida REAL, con fallback a
--                         ent_pedido.fecha_despacho para las filas viejas)
--   Cliente            → ent_pedido.cliente_nombre
--   Producto           → ent_alisto_linea.producto_id → nombre de las constantes
--   Cantidad Total     → ent_alisto_linea.cant_uds  (y cant_uom en la unidad de la factura)
--   Caja/Unid          → ent_pedido_linea.uom_nombre
--   Cantidad x Lote    → ent_alisto_lote.cant_uds
--   Lotes              → ent_alisto_lote.lote
--   Responsable        → ent_alisto.responsable
-- Y ADEMÁS, que antes no se podía: la hora de PREPARACIÓN (preparado_en) junto a
-- la de salida. El registro pasa a documentar los dos momentos.


-- ── 10 · COMPROBACIÓN (correr después de pegar) ─────────────────────────
-- 1) Las dos tablas nuevas, con select+insert y NADA más:
--      select tablename, policyname, cmd from pg_policies
--       where tablename in ('ent_salida','ent_anulacion') order by tablename, cmd;
--      → 4 filas: dos SELECT y dos INSERT. Ninguna UPDATE ni DELETE.
--
-- 2) TODAS las vistas del módulo con security_invoker (el hallazgo 2):
--      select c.relname,
--             coalesce(( select o from unnest(c.reloptions) o
--                         where o like 'security_invoker%'), 'FALTA') as opcion
--        from pg_class c join pg_namespace n on n.oid = c.relnamespace
--       where n.nspname='public' and c.relkind='v' and c.relname like '%ent_%'
--       order by 2 desc, 1;
--      → ninguna puede decir FALTA. v_ent_factura_despachada decía FALTA antes
--        de este pegado; ahí se ve si el arreglo entró.
--
-- 3) El backfill: cuántas filas se escribieron y con qué nota.
--      select count(*) as backfilleadas from ent_salida
--       where creado_por = 'migracion:ENTREGAS_ETAPAS.sql';
--      → tantas como alistos hubiera al pegar (hoy, 16-ago, probablemente 0:
--        la factura de Automercado …3476 se abrió pero NUNCA se confirmó).
--
-- 4) Y esto es la prueba de que el corte quedó congelado — correrlo DOS veces
--    seguidas tiene que devolver el mismo número:
--      select clave, corte from ent_migracion;
--
-- 5) El estado de cada pedido (hoy vacío o casi):
--      select pedido_id, cliente_nombre, estado, preparado_en, salida_en
--        from v_ent_pedido_estado order by preparado_en desc;
--
-- 6) Que el alias viejo y el nombre nuevo dan LO MISMO (si da alguna fila de
--    diferencia, no publicar: rpCalcSaldos() estaría leyendo otra cosa):
--      select count(*) from (
--        select * from ent_entregado_desde_ancla
--        except
--        select * from ent_salido_del_congelador_desde_ancla) d;
--      → 0
