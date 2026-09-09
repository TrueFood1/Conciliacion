-- ════════════════════════════════════════════════════════════════════════
-- b56 · los cuatro abiertos. SOLO LECTURA, no cambia nada.
--   D) BLOQUE 6.4 · "Regalia para Anne" del 8-sep: mediodia vivo o correcto
--   E) BLOQUE 2.7 · cuantos alistos estan preparados y sin salir, y desde cuando
--   F) BLOQUE 5.2 · uom_id / uom_factor nulos en las lineas nacidas sin factura
--   G) BLOQUE 7.2 · la RLS de plan_overrides deja leerla con la sesion de la app
--
--     python3 herramientas/pg_lector.py --clave --archivo DIAGNOSTICO_B56_ABIERTOS.sql
--
-- Recordatorio de las dos trampas del lector: ningun pedazo termina en linea de
-- comentario, y no hay punto y coma dentro de los comentarios.
-- ════════════════════════════════════════════════════════════════════════

-- ══ D · toda salida sin factura del 8-sep, con la hora en CR y el dia en que se
--    registro. Si salida_en cae el mismo dia que creado_en y la hora es 12:00,
--    el mediodia inventado sigue vivo y el arreglo de b55 no cerro.
select p.id as pedido, p.origen, p.motivo, p.destinatario, p.cliente_nombre,
       p.fecha_despacho,
       (s.salida_en at time zone 'America/Costa_Rica') as salida_cr,
       (s.creado_en at time zone 'America/Costa_Rica') as registrado_cr,
       (s.salida_en at time zone 'America/Costa_Rica')::date
         = (s.creado_en at time zone 'America/Costa_Rica')::date as mismo_dia,
       to_char(s.salida_en at time zone 'America/Costa_Rica', 'HH24:MI') as hora,
       s.nota, s.creado_por
  from ent_pedido p
  join ent_alisto_vigente av on av.pedido_id = p.id
  join ent_salida_vigente sv on sv.alisto_id = av.alisto_id
  join ent_salida s on s.id = sv.salida_id
 where p.origen = 'manual'
   and (s.creado_en at time zone 'America/Costa_Rica')::date >= date '2026-09-07'
 order by s.creado_en desc;

-- ══ D2 · y por si "Anne" no es un destinatario sino un cliente o una nota.
select p.id as pedido, p.origen, p.motivo, p.destinatario, p.cliente_nombre,
       p.fecha_despacho, p.creado_en
  from ent_pedido p
 where p.destinatario ilike '%anne%' or p.cliente_nombre ilike '%anne%'
 order by p.creado_en desc;

-- ══ E · BLOQUE 2.7 · los alistos preparados y SIN salir, con su antiguedad.
--    Los de dias anteriores a hoy son hueco, no pendiente del dia.
select e.pedido_id, e.cliente_nombre, e.factura_nombre, e.n_lineas,
       (e.preparado_en at time zone 'America/Costa_Rica') as preparado_cr,
       (current_date - (e.preparado_en at time zone 'America/Costa_Rica')::date) as dias_parado,
       case when (e.preparado_en at time zone 'America/Costa_Rica')::date = current_date
            then 'de hoy' else 'HUECO de dias anteriores' end as clase
  from v_ent_pedido_estado e
 where e.estado = 'preparado'
 order by e.preparado_en;

-- ══ F · BLOQUE 5.2 · el censo de uom en ent_pedido_linea, por origen del pedido.
--    Los NUMEROS ya se sabe que estan bien (cant_uds convertido correcto). Lo que
--    se mide aca es si los campos de unidad quedaron nulos, que afecta el rotulo
--    y el flujo unificado del bloque 5.
select p.origen,
       count(*) as lineas,
       count(*) filter (where l.uom_id is null)      as sin_uom_id,
       count(*) filter (where l.uom_factor is null)  as sin_uom_factor,
       count(*) filter (where l.uom_nombre is null)  as sin_uom_nombre,
       count(*) filter (where l.cant_uom is null)    as sin_cant_uom
  from ent_pedido_linea l
  join ent_pedido p on p.id = l.pedido_id
 group by p.origen
 order by p.origen;

-- ══ F2 · lo mismo en ent_alisto_linea, que es la que alimenta los saldos.
select p.origen,
       count(*) as lineas,
       count(*) filter (where al.cant_uom is null) as sin_cant_uom
  from ent_alisto_linea al
  join ent_alisto a on a.id = al.alisto_id
  join ent_pedido p on p.id = a.pedido_id
 group by p.origen
 order by p.origen;

-- ══ G · BLOQUE 7.2 · las politicas de plan_overrides. Si no hay una de SELECT
--    para authenticated, el catch mudo de nivOverrides esta tapando un problema
--    real y quitarlo lo va a hacer visible de golpe.
select tablename, policyname, cmd, roles, qual
  from pg_policies
 where schemaname = 'public' and tablename in ('plan_overrides','plan_config')
 order by tablename, cmd, policyname;

-- ══ G2 · y los grants, que es la otra mitad de la puerta.
select table_name, grantee, privilege_type
  from information_schema.role_table_grants
 where table_schema = 'public' and table_name in ('plan_overrides','plan_config')
   and grantee in ('authenticated','anon')
 order by table_name, grantee, privilege_type;
