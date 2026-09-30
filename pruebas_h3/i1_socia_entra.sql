-- PRUEBA I1 · CARRIL B · una SOCIA puede anular la salida (lo que hace el boton)
-- Se usa el pedido 132 (alisto 88, salida 77), que sigue entregado.
-- ESPERADO: el insert ENTRA · estado preparado · saldo 480 SIN CAMBIO · vigente 0
select acceso_perfil() as perfil, acceso_es_socia() as es_socia;

insert into ent_anulacion (entidad, entidad_id, motivo, creado_por)
values ('salida', 77, 'prueba-i1: sale otro dia (rollback)',
        nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email')
returning id, entidad, entidad_id, creado_por;

select (select estado from v_ent_pedido_estado where pedido_id=132)        as estado_preparado,
       (select uds from ent_salido_del_congelador_desde_ancla
         where lote='237 / 2-27' and producto_id=453)                       as saldo_480,
       (select count(*) from ent_salida_vigente where salida_id=77)         as vigente_0;
