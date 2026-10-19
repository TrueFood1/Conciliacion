-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_ANULAR_PEDIDO_195.sql · 14-oct-2026 · ENSAYO EN SECO · TERMINA EN ROLLBACK
-- ✅ CORRIDO el 14-oct-2026 por Andrea: 2 · 1 · 0 · 0 · 0 · 0 · 1 · 1 · 1 · true · 1.
--    Verificado desde afuera después: nada quedó escrito (rollback).
-- Hace EXACTAMENTE lo mismo que PEGADO_ANULAR_PEDIDO_195.sql (mismo bloque, byte a
-- byte) y no deja nada escrito.
--
-- TIENE QUE DAR UNA FILA:
--   2 · 1 · 0 · 0 · 0 · 0 · 1 · 1 · 1 · true · 1
-- Si sale un error rojo que empieza con «CANDADO:», el terreno no es el medido:
-- no sigas, copiame el mensaje. Si dice «Success. No rows returned», no llegó al
-- final y no vale.
--
-- QUÉ PASÓ
--   La regalía a Hotel W del 14-oct se registró dos veces: la #194 (Daniel, 6
--   productos, con su traslado WH/INT/00149 hecho en Odoo) y la #195 (Andrea, 3
--   productos: Semillas 281 1 u · Francés 285 1 paq · Pizza 268 1 paq). Lo real
--   es la #194. La #195 no salió del congelador.
--
-- QUÉ HACE (tres inserts, ni un update ni un delete)
--   · ent_anulacion  ('salida', 143)  y  ('alisto', 154): la #195 deja de existir
--     para el saldo, el Historial y la bandeja. Hay que anular el ALISTO: con la
--     salida sola el descuento se sostiene (el coalesce cae al alisto, caso 135).
--   · ent_odoo_hecho (pendiente 37): sale de «Traslados internos por crear». La
--     cola no mira las anulaciones, solo ent_odoo_hecho.
--   · Odoo NO se toca.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

do $candado$
declare
  k_pedido  constant bigint := 195;
  k_alisto  constant bigint := 154;
  k_salida  constant bigint := 143;
  k_pend    constant bigint := 37;
  k_motivo  constant text   := 'Duplicado de la #194: la misma regalía a Hotel W se registró dos veces el 14-oct. Lo real es la #194 (6 productos, traslado WH/INT/00149). La #195 no salió.';
  k_firma   constant text   := 'correccion-sql - pedido 195 14oct - andrea@truefoodcr.com';
  k_ref     constant text   := 'anulado: duplicado de la #194, sin traslado';
  v_n int; v_a numeric; v_b numeric; v_c numeric;
  v_resto_antes text; v_resto_despues text;
  v_s0 numeric; v_f0 numeric; v_p0 numeric;
  v_s1 numeric; v_f1 numeric; v_p1 numeric;
  v_max_anu bigint; v_max_hec bigint;
begin
  -- ══ CANDADO DE ENTRADA · el terreno tiene que ser EXACTAMENTE el medido el 14-oct ══
  select count(*) into v_n from ent_alisto_vigente where pedido_id = k_pedido;
  if v_n <> 1 then raise exception 'CANDADO: el pedido 195 tiene % alistos vigentes (se esperaba 1). NO SE APLICO NADA.', v_n; end if;
  select count(*) into v_n from ent_alisto_vigente where pedido_id = k_pedido and alisto_id = k_alisto;
  if v_n <> 1 then raise exception 'CANDADO: el alisto vigente del 195 ya no es el 154. NO SE APLICO NADA.'; end if;
  select count(*) into v_n from ent_salida_vigente where alisto_id = k_alisto and salida_id = k_salida;
  if v_n <> 1 then raise exception 'CANDADO: la salida vigente del alisto 154 ya no es la 143. NO SE APLICO NADA.'; end if;
  select count(*) into v_n from ent_anulacion
   where (entidad = 'alisto' and entidad_id = k_alisto) or (entidad = 'salida' and entidad_id = k_salida);
  if v_n <> 0 then raise exception 'CANDADO: el alisto 154 o la salida 143 ya tienen % anulacion(es). NO SE APLICO NADA.', v_n; end if;
  select count(*) into v_n from ent_devolucion where pedido_id = k_pedido;
  if v_n <> 0 then raise exception 'CANDADO: el pedido 195 tiene % devolucion(es). NO SE APLICO NADA.', v_n; end if;
  select count(*) into v_n from ent_odoo_traslado where pedido_id = k_pedido;
  if v_n <> 0 then raise exception 'CANDADO: el pedido 195 YA tiene traslado en Odoo (% fila/s): no se anula sin revertirlo alla. NO SE APLICO NADA.', v_n; end if;
  -- las lineas del alisto 154: exactamente Semillas 281 x1 u, Pizza 268 x2 u, Frances 285 x4 u
  select count(*) into v_n from ent_alisto_linea where alisto_id = k_alisto;
  if v_n <> 3 then raise exception 'CANDADO: el alisto 154 tiene % lineas (se esperaban 3). NO SE APLICO NADA.', v_n; end if;
  select count(*) into v_n from ent_alisto_linea l join ent_alisto_lote lo on lo.linea_id = l.id
   where l.alisto_id = k_alisto;
  if v_n <> 3 then raise exception 'CANDADO: el alisto 154 tiene % lotes (se esperaban 3). NO SE APLICO NADA.', v_n; end if;
  select count(*) into v_n from ent_alisto_linea l join ent_alisto_lote lo on lo.linea_id = l.id
   where l.alisto_id = k_alisto
     and ((l.producto_id = 452 and lo.lote = '281 / 7-27' and lo.cant_uds = 1)
       or (l.producto_id = 472 and lo.lote = '268 / 6-27' and lo.cant_uds = 2)
       or (l.producto_id = 453 and lo.lote = '285 / 7-27' and lo.cant_uds = 4));
  if v_n <> 3 then raise exception 'CANDADO: los lotes del alisto 154 no son los medidos (% de 3). NO SE APLICO NADA.', v_n; end if;
  -- el pendiente 37: traslado interno del 195, sin hecho
  select count(*) into v_n from ent_odoo_pendiente where id = k_pend and pedido_id = k_pedido and tipo = 'traslado_interno';
  if v_n <> 1 then raise exception 'CANDADO: el pendiente 37 no es el traslado interno del 195. NO SE APLICO NADA.'; end if;
  select count(*) into v_n from ent_odoo_hecho where pendiente_id = k_pend;
  if v_n <> 0 then raise exception 'CANDADO: el pendiente 37 ya tiene % hecho(s). NO SE APLICO NADA.', v_n; end if;
  -- la #194 (la real) intacta
  select count(*) into v_n from v_ent_pedido_estado where pedido_id = 194 and estado = 'entregado';
  if v_n <> 1 then raise exception 'CANDADO: la #194 no esta entregada. NO SE APLICO NADA.'; end if;
  select count(*) into v_n from ent_odoo_traslado where pedido_id = 194 and picking_nombre = 'WH/INT/00149';
  if v_n <> 1 then raise exception 'CANDADO: la #194 no tiene su traslado WH/INT/00149. NO SE APLICO NADA.'; end if;

  -- ══ LA FOTO ANTES ══ los tres lotes, y el RESTO de la vista entera
  select coalesce(sum(uds),0) into v_s0 from ent_salido_del_congelador_desde_ancla where producto_id = 452 and lote = '281 / 7-27';
  select coalesce(sum(uds),0) into v_f0 from ent_salido_del_congelador_desde_ancla where producto_id = 453 and lote = '285 / 7-27';
  select coalesce(sum(uds),0) into v_p0 from ent_salido_del_congelador_desde_ancla where producto_id = 472 and lote = '268 / 6-27';
  select md5(coalesce(string_agg(producto_id||'|'||lote||'|'||uds, ',' order by producto_id, lote),'')) into v_resto_antes
    from ent_salido_del_congelador_desde_ancla
   where (producto_id, lote) not in ((452,'281 / 7-27'),(453,'285 / 7-27'),(472,'268 / 6-27'));
  select coalesce(max(id),0) into v_max_anu from ent_anulacion;
  select coalesce(max(id),0) into v_max_hec from ent_odoo_hecho;

  -- ══ LA ANULACION · tres inserts, ni un update ni un delete ══
  insert into ent_anulacion (entidad, entidad_id, motivo, creado_por) values ('salida', k_salida, k_motivo, k_firma);
  insert into ent_anulacion (entidad, entidad_id, motivo, creado_por) values ('alisto', k_alisto, k_motivo, k_firma);
  insert into ent_odoo_hecho (pendiente_id, referencia, creado_por) values (k_pend, k_ref, k_firma);

  -- ══ LA FOTO DESPUES ══
  select coalesce(sum(uds),0) into v_s1 from ent_salido_del_congelador_desde_ancla where producto_id = 452 and lote = '281 / 7-27';
  select coalesce(sum(uds),0) into v_f1 from ent_salido_del_congelador_desde_ancla where producto_id = 453 and lote = '285 / 7-27';
  select coalesce(sum(uds),0) into v_p1 from ent_salido_del_congelador_desde_ancla where producto_id = 472 and lote = '268 / 6-27';
  select md5(coalesce(string_agg(producto_id||'|'||lote||'|'||uds, ',' order by producto_id, lote),'')) into v_resto_despues
    from ent_salido_del_congelador_desde_ancla
   where (producto_id, lote) not in ((452,'281 / 7-27'),(453,'285 / 7-27'),(472,'268 / 6-27'));

  -- ══ CANDADO DE SALIDA · lo que tiene que haber dejado ══
  if v_s0 - v_s1 <> 1 or v_f0 - v_f1 <> 4 or v_p0 - v_p1 <> 2 then
    raise exception 'CANDADO: los lotes no recuperaron lo esperado. Semillas 281 % u (esperado 1) · Frances 285 % u (esperado 4) · Pizza 268 % u (esperado 2). NO SE APLICO NADA.',
      v_s0 - v_s1, v_f0 - v_f1, v_p0 - v_p1;
  end if;
  if v_resto_antes is distinct from v_resto_despues then
    raise exception 'CANDADO: se movio algun OTRO lote. NO SE APLICO NADA.'; end if;
  select count(*) into v_n from ent_alisto_vigente where pedido_id = k_pedido;
  if v_n <> 0 then raise exception 'CANDADO: el 195 sigue con alisto vigente. NO SE APLICO NADA.'; end if;
  select count(*) into v_n from ent_salida_vigente where salida_id = k_salida;
  if v_n <> 0 then raise exception 'CANDADO: la salida 143 sigue vigente. NO SE APLICO NADA.'; end if;
  select count(*) into v_n from v_ent_odoo_pendiente where pedido_id = k_pedido;
  if v_n <> 0 then raise exception 'CANDADO: el 195 sigue en la cola de Odoo. NO SE APLICO NADA.'; end if;
  select count(*) into v_n from v_ent_pedido_estado where pedido_id = 194 and estado = 'entregado';
  if v_n <> 1 then raise exception 'CANDADO: se toco la #194. NO SE APLICO NADA.'; end if;

  perform set_config('anul195.anu',  (select count(*) from ent_anulacion where id > v_max_anu)::text, true);
  perform set_config('anul195.hec',  (select count(*) from ent_odoo_hecho where id > v_max_hec)::text, true);
  perform set_config('anul195.sem',  (v_s0 - v_s1)::int::text, true);
  perform set_config('anul195.fra',  ((v_f0 - v_f1) / 4)::int::text, true);
  perform set_config('anul195.piz',  ((v_p0 - v_p1) / 2)::int::text, true);
  perform set_config('anul195.resto', (v_resto_antes = v_resto_despues)::text, true);
  raise notice 'CANDADO OK';
end
$candado$;

-- CONTROL, adentro de la transacción.
select current_setting('anul195.anu')                                                  as anulaciones_nuevas,
       current_setting('anul195.hec')                                                  as hechos_nuevos,
       (select count(*) from ent_alisto_vigente  where pedido_id = 195)                as alisto_vigente_195,
       (select count(*) from ent_salida_vigente  where salida_id = 143)                as salida_vigente_143,
       (select count(*) from v_ent_pedido_estado where pedido_id = 195)                as p195_en_historial,
       (select count(*) from v_ent_odoo_pendiente where pedido_id = 195)               as p195_en_pendientes,
       current_setting('anul195.sem')                                                  as vuelve_semillas_281_u,
       current_setting('anul195.fra')                                                  as vuelve_frances_285_paq,
       current_setting('anul195.piz')                                                  as vuelve_pizza_268_paq,
       current_setting('anul195.resto')                                                as resto_de_lotes_igual,
       (select count(*) from v_ent_pedido_estado where pedido_id = 194 and estado = 'entregado') as p194_sigue_entregado;
-- ESPERADO: 2 · 1 · 0 · 0 · 0 · 0 · 1 · 1 · 1 · true · 1

rollback;
