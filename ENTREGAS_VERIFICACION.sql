-- ════════════════════════════════════════════════════════════════════════
-- ENTREGAS · VERIFICACION DE FACTURA DE CADA SALIDA — 20-ago-2026.
-- Re-ejecutable. NO TOCA ODOO.
--
-- POR QUE. Hasta hoy, si Odoo no contestaba, Despachos no dejaba entregar: fallaba
-- CERRADO. Eso paraliza el despacho por un problema de infraestructura (el arranque
-- en frio del proxy, ~40 s) y no por disciplina. Peor: empuja a Daniel al Excel, y
-- lo anotado ahi NO BAJA NUNCA AL SALDO — sin conteo fisico que reancle, ese error
-- no se limpia jamas. La emergencia se resuelve DENTRO de Truefie, con rastro.
--
-- Ahora la salida se registra igual y queda MARCADA. Cuando Odoo vuelva a contestar
-- se verifica hacia atras y la marca se limpia sola.
--
-- POR QUE UNA TABLA Y NO UNA COLUMNA EN ent_salida. Una bandera que despues se
-- limpia necesita UPDATE, y ent_salida no tiene politica ni grant de update — a
-- proposito. Verificar es INSERTAR otra fila y que gane la mas reciente. Es el
-- mismo patron de ent_conteo_ancla y ent_pedido_factura.
-- ════════════════════════════════════════════════════════════════════════


-- ── 1 · LA TABLA ────────────────────────────────────────────────────────
-- Una fila por CADA intento de verificacion. La mas reciente de cada salida manda.
--   vigente       la factura existia y no estaba reversada al momento de mirar.
--   sin_verificar no se pudo leer Odoo. La salida se registro igual, marcada.
--   anulada       la factura ESTABA reversada. Esto hay que gritarlo: salio producto
--                 contra un documento muerto.
-- No se usa la AUSENCIA de fila como estado: toda salida escribe la suya al guardarse,
-- asi que una salida sin ninguna fila es una salida vieja (anterior a este pegado) y
-- se distingue de una que quedo sin verificar hoy.
create table if not exists ent_salida_verificacion (
  id          bigint generated always as identity primary key,
  salida_id   bigint  not null references ent_salida(id),
  estado      text    not null check (estado in ('vigente','sin_verificar','anulada')),
  factura_id  integer,                        -- account.move.id mirado; null si no se pudo
  detalle     text,                           -- motivo de la NC, o el error de lectura
  creado_en   timestamptz not null default now(),
  creado_por  text    not null
);
create index if not exists ent_salida_verif_salida_idx
  on ent_salida_verificacion (salida_id, creado_en desc);
create index if not exists ent_salida_verif_estado_idx
  on ent_salida_verificacion (estado);

comment on table ent_salida_verificacion is
  'Verificar es INSERTAR, nunca actualizar. Gana la fila mas reciente de cada salida.';


-- ── 2 · RLS Y GRANTS ────────────────────────────────────────────────────
alter table ent_salida_verificacion enable row level security;
drop policy if exists ent_salida_verif_sel on ent_salida_verificacion;
drop policy if exists ent_salida_verif_ins on ent_salida_verificacion;
create policy ent_salida_verif_sel on ent_salida_verificacion
  for select to authenticated using (true);
create policy ent_salida_verif_ins on ent_salida_verificacion
  for insert to authenticated with check (true);
grant select, insert on ent_salida_verificacion to authenticated;


-- ── 3 · EL ESTADO VIGENTE DE CADA SALIDA ────────────────────────────────
create or replace view ent_salida_verif_vigente with (security_invoker = true) as
  select distinct on (salida_id)
         salida_id, estado, factura_id, detalle,
         creado_en as verificado_en, creado_por as verificado_por
    from ent_salida_verificacion
   order by salida_id, creado_en desc;

grant select on ent_salida_verif_vigente to authenticated;


-- ── 4 · LO QUE NECESITA OJO ─────────────────────────────────────────────
-- Alimenta la alerta del panel. Cumple las cinco reglas del lobby:
--   1) solo existe si hay algo que hacer — si no hay filas, no hay alerta;
--   2) trae fecha (la de la salida), que es lo que la vuelve alerta y no dato;
--   3) se apaga sola: cuando Odoo contesta se inserta 'vigente' y la fila sale de aca;
--   4) el corte a 3 y el "y N mas" los hace la pantalla;
--   5) el ambar/rojo lo decide `estado`, no la existencia.
-- Las 'anulada' van primero: esas no se apagan solas y hay que gritarlas.
create or replace view ent_salida_sin_verificar with (security_invoker = true) as
  select s.id                as salida_id,
         s.alisto_id,
         s.salida_en,
         v.estado,
         v.detalle,
         v.verificado_en,
         av.pedido_id,
         p.cliente_nombre,
         p.factura_nombre
    from ent_salida_verif_vigente v
    join ent_salida        s  on s.id = v.salida_id
    join ent_alisto_vigente av on av.alisto_id = s.alisto_id
    join ent_pedido        p  on p.id = av.pedido_id
   where v.estado in ('sin_verificar','anulada')
     and not exists (select 1 from ent_anulacion x
                      where x.entidad = 'salida' and x.entidad_id = s.id)
   order by case v.estado when 'anulada' then 0 else 1 end, s.salida_en desc;

grant select on ent_salida_sin_verificar to authenticated;


-- ── 5 · LAS QUE HAY QUE VOLVER A MIRAR ──────────────────────────────────
-- EL HUECO QUE ESTA VISTA CIERRA: una factura puede anularse DESPUES de una salida
-- que verifico bien. Daniel despacha a las 6:30 contra una factura vigente y Andrea
-- la anula a las 10:00 — esa salida quedo 'vigente' y sin esto nadie la vuelve a
-- mirar nunca. No es hipotetico: es lo que paso con la 3487, solo que sin alisto de
-- por medio.
--
-- Devuelve las salidas cuya verificacion vigente dice 'vigente' y que TIENEN factura,
-- de la mas reciente a la mas vieja, con el factura_id para que la app pueda pedirle
-- a Odoo el reversal_move_id de todas juntas. Si aparece reversada, se INSERTA una
-- fila 'anulada' encima y sale sola en ent_salida_sin_verificar.
--
-- La VENTANA la pone la app con un limit, no la vista: cuantos dias hacia atras vale
-- la pena re-mirar es una decision de producto (una factura no se anula un mes
-- despues), y hornearla acá obligaria a re-pegar SQL para cambiar un numero.
-- Las salidas sin factura (traslado interno, salida manual) no entran: no hay
-- documento que se pueda anular.
create or replace view ent_salida_a_reverificar with (security_invoker = true) as
  select s.id            as salida_id,
         s.salida_en,
         v.factura_id,
         v.verificado_en,
         av.pedido_id,
         p.cliente_nombre,
         p.factura_nombre
    from ent_salida_verif_vigente v
    join ent_salida         s  on s.id = v.salida_id
    join ent_alisto_vigente av on av.alisto_id = s.alisto_id
    join ent_pedido         p  on p.id = av.pedido_id
   where v.estado = 'vigente'
     and v.factura_id is not null
     and not exists (select 1 from ent_anulacion x
                      where x.entidad = 'salida' and x.entidad_id = s.id)
   order by s.salida_en desc;

grant select on ent_salida_a_reverificar to authenticated;
