-- ════════════════════════════════════════════════════════════════════════
-- PRUEBAS · quitar `decision` de ent_alisto_linea_autorizacion · UNA POR UNA
-- ════════════════════════════════════════════════════════════════════════
-- Preparado el 15-sep-2026. NO SE CORRIO.
--
-- CRITERIO (la leccion del 14-sep): las pruebas CREAN la fila, no la buscan.
-- Aca no es opcional: al 15-sep hay 0 lineas con no_se_entrega = true (de 199),
-- asi que una prueba que BUSQUE una linea marcada no encontraria ninguna, el
-- insert tocaria 0 filas y saldria "Success" sin haber ejercido nada. Cada
-- bloque se fabrica su linea marcada adentro de su propia transaccion.
--
-- ⚠️ `creado_por` TIENE QUE EMPEZAR CON "autorizacion-sql". El guardia
-- ent_alisto_linea_autorizacion_guard, cuando no hay JWT —o sea desde el SQL
-- Editor, que entra como postgres— lo exige a proposito, para que una firma
-- hecha a mano se distinga de una hecha desde la app. Si se pone otra cosa, la
-- prueba falla por la firma y no por lo que se queria medir.
--
-- Las que PASAN hacen un select antes del rollback: un insert exitoso es mudo,
-- y un "Success" mudo fue exactamente el sintoma de 7a el 14-sep.
--
-- Las cuatro van en begin/rollback: no dejan nada escrito.
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- P0 · ANTES DE APLICAR · la prueba tiene que poder FALLAR
-- ════════════════════════════════════════════════════════════════════════
-- Correr ESTA SOLA, ANTES del cambio. Hoy `decision` es NOT NULL, asi que un
-- insert que la omite TIENE QUE DAR ERROR. Si pasa, la columna no es NOT NULL
-- como creemos y el P1 de despues no probaria nada: PARAR.
-- ESPERADO: ERROR null value in column "decision" ... violates not-null constraint
   begin;
     insert into ent_alisto_linea
            (alisto_id, producto_id, cant_uds, cant_uom,
             no_se_entrega, motivo_no_entrega, no_entrega_por, no_entrega_en)
     values ((select id from ent_alisto where not anulado order by id desc limit 1),
             451, 0, 0, true, 'agotado', 'prueba-p0', now());
     insert into ent_alisto_linea_autorizacion (alisto_linea_id, nota, creado_por)
     select l.id, 'probando', 'autorizacion-sql · prueba p0'
       from ent_alisto_linea l where l.no_entrega_por = 'prueba-p0'
      order by l.id desc limit 1;
   rollback;


-- ════════════════════════════════════════════════════════════════════════
-- DE ACA EN ADELANTE: DESPUES DE APLICAR EL CAMBIO
-- ════════════════════════════════════════════════════════════════════════

-- ── P1 · validacion CON nota · TIENE QUE PASAR ──────────────────────────
-- El select tiene que devolver 1 fila, con la nota puesta.
   begin;
     insert into ent_alisto_linea
            (alisto_id, producto_id, cant_uds, cant_uom,
             no_se_entrega, motivo_no_entrega, no_entrega_por, no_entrega_en)
     values ((select id from ent_alisto where not anulado order by id desc limit 1),
             451, 0, 0, true, 'agotado', 'prueba-p1', now());
     insert into ent_alisto_linea_autorizacion (alisto_linea_id, nota, creado_por)
     select l.id, 'se valido con nota', 'autorizacion-sql · prueba p1'
       from ent_alisto_linea l where l.no_entrega_por = 'prueba-p1'
      order by l.id desc limit 1;
     select a.id, a.alisto_linea_id, '['||coalesce(a.nota,'(null)')||']' as nota,
            a.creado_por, a.creado_en
       from ent_alisto_linea_autorizacion a
      where a.creado_por = 'autorizacion-sql · prueba p1';
   rollback;


-- ── P2 · validacion SIN nota · TIENE QUE PASAR ──────────────────────────
-- Es el caso normal: la socia valida y no escribe nada. El select tiene que
-- devolver 1 fila con nota = (null). Si diera ERROR, la nota seguiria siendo
-- obligatoria y el cambio no quedo.
   begin;
     insert into ent_alisto_linea
            (alisto_id, producto_id, cant_uds, cant_uom,
             no_se_entrega, motivo_no_entrega, no_entrega_por, no_entrega_en)
     values ((select id from ent_alisto where not anulado order by id desc limit 1),
             451, 0, 0, true, 'agotado', 'prueba-p2', now());
     insert into ent_alisto_linea_autorizacion (alisto_linea_id, creado_por)
     select l.id, 'autorizacion-sql · prueba p2'
       from ent_alisto_linea l where l.no_entrega_por = 'prueba-p2'
      order by l.id desc limit 1;
     select a.id, a.alisto_linea_id, '['||coalesce(a.nota,'(null)')||']' as nota,
            a.creado_por
       from ent_alisto_linea_autorizacion a
      where a.creado_por = 'autorizacion-sql · prueba p2';
   rollback;


-- ── P3 · validar una linea NO marcada · TIENE QUE DAR ERROR ─────────────
-- El trigger guard sigue vivo y no lo toca este cambio (medido: su cuerpo no
-- menciona `decision` ni una vez). La linea se crea SIN marcar a proposito.
-- ESPERADO: ERROR 'la linea N no esta marcada "no se entrega": no hay nada que autorizar.'
   begin;
     insert into ent_alisto_linea
            (alisto_id, producto_id, cant_uds, no_se_entrega)
     values ((select id from ent_alisto where not anulado order by id desc limit 1),
             451, 1, false);
     insert into ent_alisto_linea_autorizacion (alisto_linea_id, creado_por)
     select l.id, 'autorizacion-sql · prueba p3'
       from ent_alisto_linea l
      where l.alisto_id = (select id from ent_alisto where not anulado order by id desc limit 1)
        and not l.no_se_entrega
      order by l.id desc limit 1;
   rollback;


-- ════════════════════════════════════════════════════════════════════════
-- VERIFICACION FINAL · las cuatro cosas del punto 4
-- ════════════════════════════════════════════════════════════════════════
-- 4a · la vista devuelve los MISMOS seis ids
with ref(id) as (values (164),(184),(192),(193),(194),(195)),
hoy as (select alisto_lote_id::int as id from v_ent_excepcion_pendiente where tipo='lote_no_determinado')
select (select count(*) from hoy)                          as filas_hoy,
       (select count(*) from ref join hoy using(id))        as coinciden,
       coalesce((select string_agg(id::text,',') from (select id from ref except select id from hoy) a),'(ninguno)') as se_fueron,
       coalesce((select string_agg(id::text,',') from (select id from hoy except select id from ref) b),'(ninguno)') as nuevos;

-- 4b · el trigger sigue habilitado (tgenabled = 'O')
select t.tgname, t.tgenabled, p.proname
  from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_proc p on p.oid=t.tgfoid
 where not t.tgisinternal and c.relname='ent_alisto_linea_autorizacion';

-- 4c · `decision` ya no existe, y los dos CHECK tampoco
select (select count(*) from information_schema.columns
         where table_schema='public' and table_name='ent_alisto_linea_autorizacion'
           and column_name='decision')                              as columna_decision,
       (select count(*) from pg_constraint
         where conrelid='ent_alisto_linea_autorizacion'::regclass
           and conname in ('autorizacion_nota_ok','ent_alisto_linea_autorizacion_decision_check')) as checks_viejos,
       (select count(*) from information_schema.columns
         where table_schema='public' and table_name='ent_alisto_linea_autorizacion') as columnas_totales;

-- 4d · la vista ya no menciona `decision`
select pg_get_viewdef('v_ent_excepcion_pendiente'::regclass,true) like '%decision%' as vista_menciona_decision,
       length(pg_get_viewdef('v_ent_excepcion_pendiente'::regclass,true))           as largo_vista;

-- 4e · y la tabla quedo vacia, como estaba
select count(*) as filas_autorizacion from ent_alisto_linea_autorizacion;
