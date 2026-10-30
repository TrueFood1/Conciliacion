# Arma ENSAYO_RECUENTO_PENDIENTE.sql: copia LITERAL del bloque DDL del CAMBIO (por marcas) + pruebas, todo en rollback.
import sys
repo=sys.argv[1] if len(sys.argv)>1 else '.'
s=open(repo+'/CAMBIO_RECUENTO_PENDIENTE.sql',encoding='utf-8').read()
A='-- ▼▼▼ BLOQUE DDL ▼▼▼'; B='-- ▲▲▲ FIN BLOQUE DDL ▲▲▲'
assert s.count(A)==1 and s.count(B)==1
ddl=s[s.index(A):s.index(B)+len(B)]

def prueba(etq, sql, esperado):
    e=etq.replace("'","''")
    if esperado=='ENTRA':
        return f"""  begin
    {sql}
    v_res := v_res || jsonb_build_object('p','{e}','esperado','ENTRA','obtenido','ENTRA','ok',true);
  exception when others then
    v_res := v_res || jsonb_build_object('p','{e}','esperado','ENTRA','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
"""
    return f"""  begin
    {sql}
    v_res := v_res || jsonb_build_object('p','{e}','esperado','RECHAZA · {esperado}','obtenido','ENTRA','ok',false);
  exception when others then
    v_res := v_res || jsonb_build_object('p','{e}','esperado','RECHAZA · {esperado}','obtenido','RECHAZA: '||sqlstate||' · '||sqlerrm,'ok',sqlstate='{esperado}');
  end;
"""
def mide(etq, expr, esp):
    e=etq.replace("'","''")
    return f"""  begin
    v_txt := coalesce(({expr})::text, 'null');
    v_res := v_res || jsonb_build_object('p','{e}','esperado','{esp}','obtenido',v_txt,'ok',v_txt='{esp}');
  exception when others then
    v_res := v_res || jsonb_build_object('p','{e}','esperado','{esp}','obtenido','ERROR: '||sqlstate||' · '||sqlerrm,'ok',false);
  end;
"""
def como(v):
    return f"  perform set_config('request.jwt.claims', json_build_object('email', {v}, 'role', 'authenticated')::text, true);\n  perform set_config('role', 'authenticated', true);\n"
POSTGRES="  perform set_config('request.jwt.claims', '', true);\n  perform set_config('role', 'postgres', true);\n"
SINSESION="  perform set_config('request.jwt.claims', '', true);\n  perform set_config('role', 'authenticated', true);\n"
ANON="  perform set_config('request.jwt.claims', '', true);\n  perform set_config('role', 'anon', true);\n"

def ins(lote,sal,unid,al,ped,pid='451',por='null'):
    return (f"insert into ent_recuento_pendiente(producto_id,lote,saldo_resultante,unidad_venta,alisto_lote_id,pedido_id,motivo,creado_por) "
            f"values ({pid},{lote},{sal},'{unid}',{al},{ped},'despacho con lote en 0',{por});")

b=[]
b.append(POSTGRES)
b.append("""  select lower(email) into v_eq from v_acceso_usuario where activo and perfil='equipo' order by email limit 1;
  select lower(email) into v_eq2 from v_acceso_usuario where activo and perfil='equipo' and lower(email)<>v_eq order by email limit 1;
  select lower(email) into v_so from v_acceso_usuario where activo and perfil='socias' order by email limit 1;
  select lower(email) into v_as from v_acceso_usuario where activo and perfil='asistente' order by email limit 1;
  select lote into v_l250 from ent_conteo_linea where conteo_id=(select id from ent_ancla) and producto_id=451 and lote like '250 /%' limit 1;
  select lote into v_l257 from ent_conteo_linea where conteo_id=(select id from ent_ancla) and producto_id=451 and lote like '257 /%' limit 1;
  v_l250 := coalesce(v_l250,'250 / 6-27'); v_l257 := coalesce(v_l257,'257 / 6-27'); v_l266 := '266 / 6-27';
  select coalesce(sum(uds) filter (where producto_id=451 and lote=v_l250),0),
         coalesce(sum(uds) filter (where producto_id=451 and lote=v_l257),0),
         coalesce(sum(uds) filter (where producto_id=503 and lote=v_l266),0)
    into v_s250, v_s257, v_s266 from ent_salido_del_congelador_desde_ancla;
""")
# ── Íntimo: Daniel (equipo) prepara factura 3613: Blanco 3 (250×2 + 257×1) y Buns 3 paq (266) ──
b.append(como('v_eq'))
b.append("""  insert into ent_pedido(fecha_despacho,origen,factura_id,factura_nombre,cliente_id,cliente_nombre,motivo,creado_por)
    values (current_date,'factura',-3613,'ENSAYO 3613',657,'ENSAYO Intimo','venta',v_eq) returning id into v_ped;
  insert into ent_alisto(pedido_id,responsable,creado_por) values (v_ped,v_eq,v_eq) returning id into v_ali;
  insert into ent_alisto_linea(alisto_id,producto_id,cant_uds,cant_uom) values (v_ali,451,3,3) returning id into v_lnb;
  insert into ent_alisto_linea(alisto_id,producto_id,cant_uds,cant_uom) values (v_ali,503,12,3) returning id into v_lnu;
  insert into ent_alisto_lote(linea_id,lote,cant_uds,orden) values (v_lnb,v_l250,2,0) returning id into v_al250;
  insert into ent_alisto_lote(linea_id,lote,cant_uds,orden) values (v_lnb,v_l257,1,1) returning id into v_al257;
  insert into ent_alisto_lote(linea_id,lote,cant_uds,orden) values (v_lnu,v_l266,12,0) returning id into v_al266;
""")
b.append(prueba('A · Intimo: Daniel abre el pendiente del 250 (saldo -2 unidades)', ins('v_l250','-2','unidad','v_al250','v_ped'), 'ENTRA'))
b.append(mide('A · la firma sale de la sesion (creado_por = el de equipo)', "select (creado_por = v_eq) from ent_recuento_pendiente where alisto_lote_id=v_al250", 'true'))
b.append(mide('A · la vista de abiertos lo muestra: 250 · -2 · unidad', "select lote=v_l250 and saldo_resultante=-2 and unidad_venta='unidad' from ent_recuento_pendiente_abierto where alisto_lote_id=v_al250", 'true'))
b.append(mide('B · el 257 y el 266 (con saldo) no abren pendiente', "select count(*) from ent_recuento_pendiente where alisto_lote_id in (v_al257,v_al266)", '0'))
b.append(mide('A/B · un solo pendiente en todo el pedido', "select count(*) from ent_recuento_pendiente where pedido_id=v_ped", '1'))
b.append(prueba('firma ajena: creado_por de otra persona', ins('v_l250','-2','unidad','v_al250','v_ped',por='v_so'), 'P0001'))
b.append(prueba('saldo_resultante 0 no es pendiente', ins('v_l257','0','unidad','v_al257','v_ped'), '23514'))
b.append(prueba('unidad inventada (panes sueltos)', ins('v_l266','-1','pan','v_al266','v_ped','503'), '23514'))
b.append(prueba('el lote no calza con la linea', ins('v_l257','-1','unidad','v_al250','v_ped'), 'P0001'))
b.append(prueba('el producto no calza con la linea', ins('v_l250','-1','paquete','v_al250','v_ped','503'), 'P0001'))
b.append(prueba('segundo pendiente para la misma linea', ins('v_l250','-3','unidad','v_al250','v_ped'), '23505'))
b.append(como('v_eq2'))
b.append(prueba('otro del equipo no cuelga un pendiente de un pedido ajeno', ins('v_l257','-1','unidad','v_al257','v_ped'), 'P0001'))
b.append(como('v_eq'))
b.append(prueba('motivo distinto', "insert into ent_recuento_pendiente(producto_id,lote,saldo_resultante,unidad_venta,alisto_lote_id,pedido_id,motivo) values (451,v_l257,-1,'unidad',v_al257,v_ped,'otro');", '23514'))
b.append(prueba('D · equipo: UPDATE', "update ent_recuento_pendiente set saldo_resultante=-1 where alisto_lote_id=v_al250;", '42501'))
b.append(prueba('D · equipo: DELETE', "delete from ent_recuento_pendiente where alisto_lote_id=v_al250;", '42501'))
b.append(prueba('equipo no puede cerrar', "insert into ent_recuento_pendiente(cierra_id,motivo,nota) select id,'recuento','contado' from ent_recuento_pendiente where alisto_lote_id=v_al250;", 'P0001'))
b.append(SINSESION)
b.append(prueba('sin sesion no entra', ins('v_l257','-1','unidad','v_al257','v_ped'), 'P0001'))
b.append(como('v_as'))
# La asistente no puede crear pedidos (asistente_no_inserta), asi que la frena primero el guard
# (P0001) y, detras, la politica asistente_no_inserta.
b.append(prueba('la asistente no abre pendientes', ins('v_l257','-1','unidad','v_al257','v_ped'), 'P0001'))
b.append(ANON)
b.append(prueba('anon no lee', "perform count(*) from ent_recuento_pendiente;", '42501'))
b.append(POSTGRES)
b.append(prueba('D · dueño (postgres): UPDATE', "update ent_recuento_pendiente set saldo_resultante=-1 where alisto_lote_id=v_al250;", '42501'))
b.append(prueba('D · dueño (postgres): DELETE', "delete from ent_recuento_pendiente where alisto_lote_id=v_al250;", '42501'))
b.append(prueba('D · dueño (postgres): TRUNCATE', "truncate ent_recuento_pendiente;", '42501'))
b.append(mide('Intimo · salidas del 250 suben 2 unidades', "select coalesce(sum(uds),0)-v_s250 from ent_salido_del_congelador_desde_ancla where producto_id=451 and lote=v_l250", '2'))
b.append(mide('Intimo · salidas del 257 suben 1 unidad (74 -> 73)', "select coalesce(sum(uds),0)-v_s257 from ent_salido_del_congelador_desde_ancla where producto_id=451 and lote=v_l257", '1'))
b.append(mide('Intimo · salidas del Buns 266 suben 3 paquetes (12 u base)', "select coalesce(sum(uds),0)-v_s266 from ent_salido_del_congelador_desde_ancla where producto_id=503 and lote=v_l266", '12'))
b.append(como('v_so'))
b.append(prueba('socia cierra con nota corta', "insert into ent_recuento_pendiente(cierra_id,motivo,nota) select id,'recuento','ok' from ent_recuento_pendiente where alisto_lote_id=v_al250;", '23514'))
b.append(prueba('socia cierra con recuento', "insert into ent_recuento_pendiente(cierra_id,motivo,nota) select id,'recuento','contado el lunes: habia 2 de mas' from ent_recuento_pendiente where alisto_lote_id=v_al250;", 'ENTRA'))
b.append(mide('cerrado: sale de la vista de abiertos', "select count(*) from ent_recuento_pendiente_abierto where alisto_lote_id=v_al250", '0'))
b.append(prueba('segundo cierre del mismo pendiente', "insert into ent_recuento_pendiente(cierra_id,motivo,nota) select id,'recuento','otra vez' from ent_recuento_pendiente where alisto_lote_id=v_al250;", '23505'))
b.append(prueba('cerrar un cierre', "insert into ent_recuento_pendiente(cierra_id,motivo,nota) select max(id),'recuento','cierre de cierre' from ent_recuento_pendiente where cierra_id is not null;", 'P0001'))
b.append(POSTGRES)

decl="""do $ensayo$
declare
  v_res jsonb := '[]'::jsonb; v_txt text;
  v_eq text; v_eq2 text; v_so text; v_as text; v_l250 text; v_l257 text; v_l266 text;
  v_s250 numeric; v_s257 numeric; v_s266 numeric;
  v_ped bigint; v_ali bigint; v_lnb bigint; v_lnu bigint; v_al250 bigint; v_al257 bigint; v_al266 bigint;
  r jsonb; v_ok int := 0; v_n int := 0;
begin
"""
fin="""  for r in select * from jsonb_array_elements(v_res) loop
    v_n := v_n + 1; if (r->>'ok')::boolean then v_ok := v_ok + 1; end if;
    raise notice '% · % · esperado % · obtenido %', case when (r->>'ok')::boolean then 'OK ' else 'MAL' end, r->>'p', r->>'esperado', r->>'obtenido';
  end loop;
  raise notice 'RESULTADO: % de % ok', v_ok, v_n;
  perform set_config('ensayo.resultado', v_ok||' de '||v_n, true);
end $ensayo$;
select current_setting('ensayo.resultado', true) as resultado;
"""
head="""-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_RECUENTO_PENDIENTE.sql · 30-oct-2026 · b151 · TERMINA EN ROLLBACK
-- Generado por armar.py: el bloque DDL es copia LITERAL de CAMBIO_RECUENTO_PENDIENTE.sql.
-- Reproduce la entrega de Intimo (factura 3613) con un pedido de ENSAYO: Blanco 250×2 +
-- 257×1 y Buns 266×3 paquetes, como el perfil equipo; abre el pendiente del 250 y prueba
-- las guardas (firma, forma, calce con la linea, RLS, solo insercion, cierre de socias).
-- Se corre ENTERO. La ultima fila dice «N de N ok». No deja nada: rollback.
-- ═══════════════════════════════════════════════════════════════════════════
begin;
"""
out=head+ddl+"\n"+decl+"".join(b)+fin+"rollback;\n"
open(repo+'/ENSAYO_RECUENTO_PENDIENTE.sql','w',encoding='utf-8').write(out)
print('ok', out.count('begin;'), out.count('rollback;'), out.count('commit;'))
