-- ════════════════════════════════════════════════════════════════════════
-- DESPACHOS · EXTENSIÓN PARA EL LECTOR DE FACTURAS
-- 14-ago-2026. QUINTO PEGADO, después de ENTREGAS_ESQUEMA / ANCLA / SALIDAS /
-- CLASIFICACION. Re-ejecutable: todo es "add column if not exists" / "create
-- index if not exists". **Pegar HOY**, antes del lunes 17.
--
-- NO CREA TABLAS. Las de Despachos ya existen desde el 12-ago y están corridas:
--   ent_pedido · ent_pedido_linea · ent_alisto · ent_alisto_linea · ent_alisto_lote
-- Esto solo les agrega columnas, y por eso es corto y no toca nada existente.
-- Las políticas RLS y los grants de esas tablas ya están puestos: agregar una
-- columna no los cambia.
--
-- QUÉ PROBLEMA RESUELVE
-- `ent_pedido_linea.presentacion` admite dos valores: 'cj' o 'uds'. Cuando se
-- diseñó, alcanzaba. Ya no: el 14-ago se verificó contra facturas reales que en
-- las ventas de 2026 conviven SIETE unidades distintas —Unidades, Paquete de 2,
-- Paquete de 4, Caja, Caja (Frances), Caja (Hamburguesa), Caja (Pizza)— y que un
-- mismo producto cambia de unidad según el cliente: Buns se factura en Paquete
-- de 4 a Abner, en Caja (Hamburguesa) a Automercado y en Caja a otros.
--
-- Con 'cj'|'uds' es imposible mostrarle a Daniel la unidad TAL COMO la pidió el
-- cliente, que es el requisito: si la factura dice "24 Caja (Frances)", la
-- pantalla tiene que decir 24 cajas de francés, no "24 cj" a secas ni 576 uds.
--
-- ⚠️ Y LA UNIDAD SE GUARDA POR ID, NUNCA POR NOMBRE. Dos pares de unidades
-- comparten nombre en inglés: `Paquete de 4` [37] y `Docenas` [2] se muestran
-- ambos como "Dozens" (4 u vs 12 u), y `Caja` [46] y `Caja (Hamburguesa)` [42]
-- ambos como "Caja" (6 u vs 24 u). Guardar el nombre y reinterpretarlo después
-- descuenta el triple o la cuarta parte. Por eso se guardan las TRES cosas:
-- el id (la verdad), el nombre (para leerlo sin ir a Odoo) y las unidades ya
-- convertidas (para que el saldo por lote no dependa de recalcular nada).
-- ════════════════════════════════════════════════════════════════════════


-- ── 1 · LA LÍNEA DEL PEDIDO GUARDA LA UNIDAD DE LA FACTURA ──────────────
alter table ent_pedido_linea add column if not exists uom_id       integer;
alter table ent_pedido_linea add column if not exists uom_nombre   text;
alter table ent_pedido_linea add column if not exists cant_uom     numeric;
alter table ent_pedido_linea add column if not exists uom_factor   numeric;

comment on column ent_pedido_linea.uom_id     is 'uom.uom.id de Odoo — LA VERDAD. Nunca reinterpretar por nombre.';
comment on column ent_pedido_linea.uom_nombre is 'Nombre es_CR al momento de leer la factura, para mostrarlo sin consultar Odoo.';
comment on column ent_pedido_linea.cant_uom   is 'Cantidad EN ESA unidad: lo que dice la factura y lo que ve Daniel.';
comment on column ent_pedido_linea.uom_factor is 'factor de uom.uom al momento. 1 unidad de esa UoM = 1/factor unidades base. Se congela por si mañana alguien lo edita en Odoo.';

-- `presentacion` y `cant_present` se quedan por compatibilidad con lo ya
-- guardado y con el código que las lee. Para las líneas nuevas el par que manda
-- es (uom_id, cant_uom); `cant_uds` sigue siendo la conversión a unidades
-- individuales, que es lo único con lo que se puede restar saldo por lote.


-- ── 2 · LO ENTREGADO, TAMBIÉN EN LA UNIDAD DE LA FACTURA ────────────────
-- Daniel corrige "26 cajas → 24 cajas", no "156 uds → 144 uds". Se guarda lo que
-- él escribió, además de la conversión, porque la diferencia que van a revisar
-- las socias se lee en cajas y redondear al revés introduce fantasmas.
alter table ent_alisto_linea add column if not exists cant_uom numeric;
comment on column ent_alisto_linea.cant_uom is 'Lo entregado EN LA UNIDAD DE LA LÍNEA. cant_uds sigue siendo la conversión a unidades individuales.';

-- La diferencia facturado-vs-entregado NO se guarda: se calcula restando
-- ent_alisto_linea.cant_uds contra ent_pedido_linea.cant_uds. Un campo guardado
-- se desincroniza el día que se anula un alisto y se inserta otro.


-- ── 3 · UNA FACTURA, UN PEDIDO ──────────────────────────────────────────
-- El lector filtra las facturas que ya tienen pedido. Este índice es la red por
-- debajo: dos toques seguidos al botón, o dos teléfonos abiertos a la vez, no
-- pueden crear el mismo despacho dos veces. Solo aplica a los de origen
-- 'factura' — los manuales no tienen factura_id.
create unique index if not exists ent_pedido_factura_unico
  on ent_pedido (factura_id) where origen = 'factura' and factura_id is not null;


-- ── 4 · QUÉ FACTURAS YA ESTÁN DESPACHADAS ───────────────────────────────
-- Una sola definición de "ya no va a la bandeja de Daniel": la factura tiene
-- pedido Y ese pedido tiene un alisto vigente (el más reciente, no anulado).
-- Un pedido creado pero sin confirmar SIGUE en la bandeja, que es lo correcto:
-- si Daniel abrió el pedido y no lo terminó, tiene que volver a verlo.
create or replace view v_ent_factura_despachada as
select p.factura_id, p.id as pedido_id, a.creado_en as confirmado_en, a.creado_por
  from ent_pedido p
  join lateral (select * from ent_alisto x
                 where x.pedido_id = p.id
                 order by x.creado_en desc limit 1) a on true
 where p.origen = 'factura' and p.factura_id is not null and a.anulado = false;

grant select on v_ent_factura_despachada to authenticated;


-- ── COMPROBACIÓN, para correr después de pegar ──────────────────────────
-- select column_name, data_type from information_schema.columns
--  where table_name in ('ent_pedido_linea','ent_alisto_linea')
--    and column_name in ('uom_id','uom_nombre','cant_uom','uom_factor')
--  order by table_name, column_name;
--   → tienen que salir 5 filas (4 de ent_pedido_linea + 1 de ent_alisto_linea)
--
-- select count(*) from v_ent_factura_despachada;
--   → 0 hoy, y sube a medida que Daniel confirma
