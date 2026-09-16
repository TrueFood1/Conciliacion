-- ════════════════════════════════════════════════════════════════════════
-- CAMBIO_DEVOLUCIONES.sql · 16-sep-2026
-- ✅ APLICADO EL 16-sep-2026, Y VERIFICADO DESPUES (no antes — ver abajo).
--    Evidencia: el select interno dio **2 · 1 · 3**; V1 → `pedido_id bigint NO`
--    (el NOT NULL entro) y `causa text YES`; V3 → las 3 tablas + las 2 vistas +
--    el indice; V5 → 0 filas, identico a 0e. Reconfirmado aparte con pg_lector.
--
-- ✅ **LAS NUEVE PRUEBAS CORRIERON, LAS NUEVE EN VERDE** (16-sep, Andrea, una
--    por una desde el SQL Editor). D0 paso (la escalera nueva anda) · D1 rechazo
--    la causa inventada · D2 la falta de causa · D3 la nota corta · D3-bis la nota
--    NULL —con `nota = null` en el DETAIL, o sea el `coalesce` visto funcionando—
--    · D4 dio 23502 en `pedido_id` (la entrada suelta, cerrada) · D5 devolvio
--    `10 · 6 · 4` (marca sin bloquear) · D6 rechazo la NC sin devolucion · D7
--    devolvio `6 · 0.25 · 24` (las dos ramas del tipo, y el factor) · D8 vacio la
--    cola al marcar hecho.
--    V7 despues: CERO filas `prueba-%` en las cinco tablas. Nada quedo escrito.
--
-- 🔴 **LO QUE LAS NUEVE NO PROBARON: que marcar hecho sea solo de socias.**
--    La politica `ent_odoo_hecho_ins` exige `acceso_es_socia()`, pero el SQL
--    Editor entra como `postgres`, que SALTEA LA RLS. D8 paso sin ejercitarla: si
--    la politica estuviera mal escrita, D8 seguiria en verde. Esto NO se puede
--    probar desde el SQL Editor por construccion — hace falta una sesion de la app
--    (o los dos roles del pendiente H3). Anotado, no resuelto.
--
-- ⚠️ SECUENCIAS QUEMADAS, y es esperado: `nextval` no se deshace con el rollback.
--    Despues de las nueve, `ent_devolucion.id` va en 11 y `ent_pedido.id` en 88
--    sin que exista ninguna fila. Los ids van a tener huecos. Es cosmetico, pero
--    conviene que este escrito antes de que alguien lo vea y se preocupe.
--
-- ⚠️ HALLAZGO AL VERIFICAR: **V4 DIO 12, NO 0.** Ver la nota en §C y en V4.
--
-- ════════════════════════════════════════════════════════════════════════
-- LO QUE COSTO APLICARLO, que vale mas que el cambio
-- ════════════════════════════════════════════════════════════════════════
-- Tres pasos fallaron en cadena, y los tres por lo mismo: **nadie los verificaba.**
--
-- 1 · EL PRIMER PEGADO DIJO "Success. No rows returned" Y NO APLICO NADA.
--     Medido despues con pg_lector: 0 columnas, 0 check, 0 vistas, 0 tablas, 0
--     politicas — y, esto salio bien, 0 a medias, porque la transaccion era una
--     sola. Causa probable: **seleccion parcial en el editor** (Supabase corre
--     solo lo seleccionado, y el bloque arranca con ~40 lineas de comentario;
--     un tramo de puro comentario devuelve exactamente ese mensaje).
--     **El `select` interno de antes del commit lo hace imposible**: o se ve la
--     fila 2·1·3, o no llego hasta ahi y se sabe en el momento.
--
-- 2 · SOBRE ESE "Success" SE ESCRIBIO QUE ESTABA APLICADO. Este header y la
--     bitacora afirmaron durante unos minutos algo falso. Es el error del 15-sep
--     con CAMBIO_AUTORIZACION.sql en la direccion contraria. La regla, en las dos:
--     **el header y la bitacora se tocan DESPUES de la verificacion**, nunca sobre
--     lo que alguien anuncio que iba a hacer.
--
-- 3 · AISLAR EL BLOQUE CON `sed -n '141,476p'` DIO EL PEDAZO EQUIVOCADO y se pego
--     **P0-a** en vez de §A+§B+§C — salio el error del lote_check, y no se
--     escribio nada solo porque P0-a termina en rollback. El numero salio de
--     suponer que el `begin;` transaccional era el segundo: hay **14** begin, los
--     tres primeros son las P0 y el transaccional es el **cuarto**. Y los numeros
--     se habian corrido al agregar el select del punto 1.
--     **Un bloque no se aisla por numero de linea.** Se extrae por contenido —el
--     unico `commit;`, y el ultimo `begin;` antes de el— y se comprueba el archivo
--     YA ESCRITO antes de ofrecerlo: un begin, un commit, cero rollback, que
--     empiece y termine donde debe, y que no traiga marcas de las pruebas.
--
-- Las tres estan escritas como regla en CLAUDE.md, reglas madre.
--
-- Tres cosas, y ninguna se puede pegar sola:
--   §A  `ent_devolucion` gana `pedido_id` y `causa`.
--   §B  la vista del EXCESO — la que marca cuando vuelve mas de lo que salio.
--   §C  la pareja de tablas de pendientes de Odoo (NC + traslado interno).
--
-- ⚠️ ESTE ARCHIVO SE PEGA **ANTES** DE PUBLICAR LA PANTALLA DE DEVOLUCIONES.
-- Es el incidente del 17-ago (codigo publicado que dependia de un .sql sin
-- pegar: tres errores encadenados en produccion y una factura a medio registrar)
-- y esta escrito aca para que no haya que acordarse.
--
-- ⚠️ EL HEADER "NO SE CORRIO" NO ES PRUEBA DE NADA. Medido el 16-sep con
-- CAMBIO_AUTORIZACION.sql: decia "NO SE CORRIO" y estaba pegado hace un dia.
-- Cuando se pegue esto, cambiar esta linea Y anotarlo en la bitacora.
--
-- ⚠️ ESTE ARCHIVO ES DE **UNA SOLA CORRIDA**. El `add column` de §A va sin
-- `if not exists` a proposito: si se re-pega, Postgres grita y la transaccion se
-- deshace entera, que es lo correcto. Antes de pegarlo, mirar 0c y 0d.
--
-- ⚠️ SE CIERRA LA ENTRADA SUELTA (decision de Andrea, 16-sep, con la tabla en 0
-- filas). `pedido_id` es NOT NULL. El argumento entero esta en §A; en una linea:
-- hoy es gratis y manana no, y el flujo nuevo hace que hasta una devolucion
-- avisada por telefono tenga su pedido.
--
-- LO QUE **NO** CAMBIA, y es deliberado:
--   · NO hay tope que bloquee. Devolver mas de lo que salio ENTRA y queda
--     marcado. Decision de Andrea del 16-sep, revertida por ella misma el mismo
--     dia: puede volver producto de una entrega anterior en el mismo camion, y
--     con un bloqueo ese producto vuelve al congelador SIN QUE EL SISTEMA LO
--     SEPA. Un saldo que no cuadra y lo dice es mejor que producto invisible.
--   · La marca NO es una columna. Es §B, una vista derivada. Un flag que
--     escribe el cliente es un flag que puede mentir.
--   · Sin update ni delete en ninguna tabla nueva, ni en politica ni en grant.
--     Corregir es anular e insertar, como en todo el modulo.
--   · Odoo NO se toca. §C guarda lo que VA a ir a Odoo. No escribe nada alla.
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- §0 · ANTES · MEDIR. Solo lectura. Correr y GUARDAR la salida.
-- No hay numeros esperados entre [] porque NO SE PUDO MEDIR DESDE ACA: la
-- anon key no atraviesa la RLS de ent_devolucion, asi que estos son los
-- numeros que Andrea tiene que traer. Si 0c no da cero, PARAR y decidir
-- antes de tocar nada.
-- ════════════════════════════════════════════════════════════════════════

-- 0a · cuantas devoluciones hay, y de cuando
select count(*) as filas, min(fecha) as primera, max(fecha) as ultima,
       count(*) filter (where exists (select 1 from ent_anulacion x
         where x.entidad='devolucion' and x.entidad_id=d.id)) as anuladas
  from ent_devolucion d;

-- 0b · cabeceras y lineas, de un saque. Reemplaza a la version vieja (que
--      listaba las filas una por una): medido el 16-sep, las dos dan CERO, y con
--      la cabecera vacia no puede haber lineas — el FK de `devolucion_id` lo
--      impide. ⚠️ Los dos ceros son lo que habilita el NOT NULL de §A.
select (select count(*) from ent_devolucion)       as cabeceras,
       (select count(*) from ent_devolucion_linea) as lineas;

-- 0c · ⚠️ EL NUMERO QUE MANDA. Si NO da cero, alguna columna ya existe y este
--      archivo fue pegado antes — PARAR, no volver a pegarlo a ciegas.
select count(*) as columnas_que_no_deberian_existir
  from information_schema.columns
 where table_name = 'ent_devolucion' and column_name in ('pedido_id','causa');

-- 0d · lo mismo para §C: si no da cero, las tablas ya estan.
select count(*) as tablas_que_no_deberian_existir
  from information_schema.tables
 where table_name in ('ent_odoo_pendiente','ent_odoo_pendiente_linea','ent_odoo_hecho');

-- 0e · la huella del saldo, para comparar DESPUES. Nada de esto se mueve:
--      §A/§B/§C no tocan ninguna fila de ninguna tabla existente.
select producto_id, sum(uds) as uds, count(*) as filas
  from ent_devuelto_desde_ancla group by 1 order by 1;

-- 0f · un pedido REAL con alisto y lotes, para las pruebas de §B.
--      Se anota el id que salga: D5 lo usa.
select p.pedido_id, p.cliente_nombre, p.factura_nombre, count(al.id) as lotes
  from v_ent_pedido_estado p
  join ent_alisto_linea li on li.alisto_id = p.alisto_id
  join ent_alisto_lote  al on al.linea_id  = li.id
 where al.lote <> 'NO DETERMINADO'
 group by 1,2,3 order by p.pedido_id desc limit 5;


-- ════════════════════════════════════════════════════════════════════════
-- P0 · LO QUE TIENE QUE PASAR **ANTES** DE APLICAR NADA
--
-- ⚠️ CADA PRUEBA SE CONSTRUYE SU PROPIO CASO. Nada de
-- `(select id from ent_devolucion order by id desc limit 1)`: esa forma fallo
-- el 15-sep con el error EQUIVOCADO —la ultima fila resulto ser otra cosa y el
-- candado de al lado contesto primero—. Una prueba que depende del estado de
-- los datos no prueba lo que dice probar, y el dia que se equivoca lo hace en
-- silencio o con el error de otro.
--
-- Todo dentro de begin/rollback: no se escribe nada.
--
-- ⚠️ LAS TRES SON DE **ANTES** Y SOLO DE ANTES. Insertan devoluciones sin
-- `pedido_id`, que es legal hoy y deja de serlo en cuanto §A corra. Re-correrlas
-- despues del commit da not-null y NO significa que algo se rompio: significa que
-- §A hizo su trabajo. La que comprueba eso a proposito es D4.
-- ════════════════════════════════════════════════════════════════════════

-- P0-0 · CONTROL · ESPERADO: PASA (Success, y la fila del eco)
--        SIN ESTA NO SE PUEDE LEER NINGUNA DE LAS OTRAS DOS. Prueba que la
--        escalera funciona: que una devolucion con su linea se puede crear hoy.
--        Si P0-0 falla, P0-a va a "fallar" por la escalera rota y no por el
--        candado — que es exactamente el modo de falla del 15-sep.
begin;
  insert into ent_devolucion (fecha, cliente_id, cliente_nombre, creado_por)
  values (current_date, 999999, 'PRUEBA p0-0', 'prueba-p0-0');
  insert into ent_devolucion_linea
    (devolucion_id, producto_id, lote, cant_uds, uom_id, uom_nombre, cant_uom, uom_factor)
  select id, 451, '100 / 1-27', 6, 1, 'Unidades', 6, 1
    from ent_devolucion where creado_por = 'prueba-p0-0';
  select 'P0-0 OK: la escalera anda' as resultado;
rollback;

-- P0-a · ESPERADO: **ERROR** de `ent_devolucion_linea_lote_check`.
--        Verifica el candado de forma canonica que YA existe — la red contra el
--        "183 - 12/26" del 18-ago. Si esto NO da error, el esquema no es el que
--        este archivo supone: PARAR.
begin;
  insert into ent_devolucion (fecha, cliente_id, cliente_nombre, creado_por)
  values (current_date, 999999, 'PRUEBA p0-a', 'prueba-p0a');
  insert into ent_devolucion_linea
    (devolucion_id, producto_id, lote, cant_uds, uom_id, uom_nombre, cant_uom, uom_factor)
  select id, 451, '183 - 12/26', 6, 1, 'Unidades', 6, 1
    from ent_devolucion where creado_por = 'prueba-p0a';
  select 'P0-a MAL: el lote torcido entro' as resultado;
rollback;

-- P0-b · ESPERADO: PASA — **y eso es el agujero que §A viene a tapar.**
--        Hoy se registra una devolucion sin decir contra que entrega fue ni por
--        que. Despues de §A, la misma sentencia con `pedido_id` puesto y sin
--        causa tiene que dar ERROR (es D2).
begin;
  insert into ent_devolucion (fecha, cliente_id, cliente_nombre, creado_por)
  values (current_date, 999999, 'PRUEBA p0-b', 'prueba-p0b');
  select 'P0-b PASA: hoy no hay nada que exija ni pedido ni causa' as resultado;
rollback;


-- ════════════════════════════════════════════════════════════════════════
-- EL PEGADO · §A + §B + §C EN UNA SOLA TRANSACCION
--
-- Postgres hace DDL transaccional, asi que esto es TODO O NADA: si algo revienta
-- en §C, las columnas de §A y la vista de §B se deshacen solas y la base queda
-- como estaba. Con tres transacciones separadas, un error en §C dejaria la base
-- a mitad de camino — columnas nuevas, vista nueva, tablas a medias. Es el mismo
-- criterio de PARA_PEGAR_EXCEPCIONES_1a6.sql y de CAMBIO_MOTIVOS_INDET.sql.
-- ════════════════════════════════════════════════════════════════════════

begin;

-- ── §A · ent_devolucion: contra QUE entrega, y POR QUE ──────────────────
-- POR QUE `pedido_id` Y NO `factura_id`. La factura es el nombre; el PEDIDO es
-- lo que ata a los lotes (pedido -> alisto -> ent_alisto_lote), que es contra lo
-- que se devuelve. Y de paso resuelve el Historial: una devolucion cuelga del
-- despacho porque comparte el pedido. `v_ent_pedido_estado` ya expone las dos,
-- con el mismo coalesce(fv, p) que usa el resto del modulo.
--
-- ⚠️ NOT NULL, Y LA RAZON ES UNA VENTANA QUE SE CIERRA. Decidido por Andrea el
-- 16-sep, DESPUES de medir: `ent_devolucion` tiene CERO filas. Los costos no son
-- simetricos y por eso la decision es hoy o nunca:
--   · nullable -> NOT NULL manana: scan completo, y FALLA si existe una sola fila
--     suelta. Y esa fila no se podria arreglar: no se puede rellenar un pedido que
--     no existe, y el modulo no tiene grant de DELETE en ninguna tabla. Quedaria
--     convivir con la columna floja para siempre.
--   · NOT NULL -> nullable manana: `alter column pedido_id drop not null`,
--     instantaneo y siempre funciona.
-- O sea que NOT NULL hoy no cierra ninguna puerta, y nullable hoy SI cierra la
-- otra en cuanto se escriba una suelta.
--
-- ⚠️ Y LA RAMA `pedido_id is null or (...)` ERA UN ESCAPE REAL, no teorico. Una
-- fila sin pedido no pasaba por NINGUNA validacion de causa, y la RLS de
-- ent_devolucion es `with check (true)` para cualquier autenticado: ese camino se
-- alcanza desde el cliente de la app, no solo desde el SQL Editor.
--
-- ⚠️ QUE SE PIERDE, dicho completo: la ENTRADA SUELTA que defendia
-- `ENTREGAS_DEVOLUCIONES.sql` ("una devolucion llega por telefono o en el camion
-- de vuelta, y esperar a saber contra que factura fue es esperar a nunca"). Se
-- cierra POR DECISION, con este argumento: el flujo nuevo arranca por cliente y
-- entregas, asi que incluso una devolucion avisada por telefono va a tener su
-- pedido — solo que elegido despues, cuando el producto llega. Queda escrito en
-- ENTREGAS_PENDIENTES §12 para que no se vuelva a discutir.
--
-- ⚠️ SIN `if not exists`, A PROPOSITO. Si la columna ya existiera, `if not
-- exists` la saltaria EN SILENCIO y el archivo seguiria de largo: quedaria una
-- columna nullable debajo de un archivo que dice NOT NULL, que es la peor de las
-- divergencias porque nadie la ve. Sin el, Postgres grita "column already exists"
-- y la transaccion entera se deshace. Este archivo es de UNA sola corrida, y 0c
-- es lo que hay que mirar antes.
alter table ent_devolucion
  add column pedido_id bigint not null references ent_pedido(id),
  add column causa     text;

create index if not exists ent_devolucion_pedido_idx on ent_devolucion (pedido_id);

-- EL CANDADO DE FORMA. Ya no cuelga de nada: con `pedido_id` NOT NULL, TODA fila
-- de esta tabla entro por la pantalla nueva y toda fila tiene que decir por que.
-- (Hasta el 16-sep esto estaba escrito `pedido_id is null or (...)`, para no
-- romper filas viejas. No hay filas viejas: la tabla esta vacia.)
--
-- ⚠️ Y LOS `coalesce` NO SON ADORNO. En Postgres un CHECK se satisface con TRUE
-- **o con NULL**. Sin el coalesce, `causa = null` haria NULL a toda la
-- conjuncion y la fila entraria igual — que es EXACTAMENTE el hueco medido el
-- 14-ago en `ent_alisto_linea_no_entrega_ok` y que quedo abierto. Aca se cierra
-- de entrada en vez de descubrirlo despues. D3-bis existe para cazar a quien los
-- saque.
--
-- El minimo de la nota es 6 y es EL MISMO numero que ENT_NM_NOTA_MIN y
-- ENT_INDET_NOTA_MIN, a proposito: tres minimos distintos para el mismo tipo de
-- campo son tres que se desincronizan. Ver el 15-sep, cuando bajo de 10 a 6
-- porque "consigna" (8) no pasaba.
alter table ent_devolucion drop constraint if exists ent_devolucion_causa_ok;
alter table ent_devolucion add constraint ent_devolucion_causa_ok check (
      coalesce(causa in ('producto_equivocado','otro'), false)
  and (causa <> 'otro' or coalesce(length(btrim(nota)) >= 6, false))
  );

comment on column ent_devolucion.pedido_id is
  'Contra QUE entrega vuelve. NOT NULL desde el 16-sep-2026: no hay devolucion suelta. '
  'El flujo arranca por cliente y entregas, asi que hasta una devolucion avisada por '
  'telefono tiene su pedido, elegido cuando el producto llega. Se decidio con la tabla '
  'en CERO filas porque despues deja de ser gratis: una sola fila suelta lo impediria '
  'para siempre (no hay grant de DELETE ni forma de rellenar un pedido inexistente).';
-- ⚠️ Y LA VISTA VIGENTE TIENE QUE EXPONERLAS, o §B no compila. `ent_devolucion_vigente`
-- se escribio el 20-ago, antes de que estas columnas existieran, y lista sus campos uno
-- por uno: sin este `create or replace` la vista del exceso falla con
-- "column dv.pedido_id does not exist" y se cae LA TRANSACCION ENTERA.
--
-- LAS DOS COLUMNAS VAN **AL FINAL**, y eso no es estetica: Postgres permite agregar
-- columnas al final de una vista que tiene dependientes, pero NO quitar, renombrar ni
-- cambiar el tipo de una que ya existe. `ent_devuelto_desde_ancla` cuelga de esta vista
-- —es la cuarta punta del saldo— y no se toca. Mismo criterio que el §D del 15-sep.
-- El cuerpo de arriba es copia literal de lo que ya hay.
create or replace view ent_devolucion_vigente with (security_invoker = true) as
  select d.id as devolucion_id, d.fecha, d.recibido_en, d.cliente_id,
         d.cliente_nombre, d.nota, d.creado_en, d.creado_por,
         d.pedido_id,                                            -- NUEVO, al final
         d.causa                                                 -- NUEVO, al final
    from ent_devolucion d
   where not exists (select 1 from ent_anulacion x
                      where x.entidad = 'devolucion' and x.entidad_id = d.id);

comment on column ent_devolucion.causa is
  'Lista cerrada: producto_equivocado | otro. Con "otro" la nota es obligatoria (>=6). '
  'Hasta el 16-sep-2026 no existia: ENTREGAS_PENDIENTES §12 pedia texto libre y se '
  'cambio porque un campo libre no se puede sumar.';


-- ── §B · EL EXCESO · la marca, derivada y no escrita ────────────────────
-- Devolver mas de lo que salio ENTRA. Esta vista dice cuando pasa.
--
-- ⚠️ NO BLOQUEA NADA Y NO TIENE QUE BLOQUEAR. Puede volver producto de una
-- entrega anterior en el mismo camion. Si se bloqueara, ese producto vuelve al
-- congelador sin que el sistema lo sepa — y un saldo invisible es peor que uno
-- que no cuadra y lo dice.
--
-- SE COMPARA POR (pedido, producto, lote) Y ACUMULANDO TODAS LAS DEVOLUCIONES
-- VIGENTES de ese pedido: "si esa entrega ya tuvo una devolucion, el tope baja".
-- Con una sola devolucion por vez el numero seria el mismo; con dos, no.
--
-- SALIO = ent_alisto_lote del alisto VIGENTE. No `ent_alisto_lote_efectivo`
-- (que aplica correcciones) a proposito: lo que se puede devolver es lo que
-- fisicamente salio, y una correccion de lote no cambia cuanto salio.
create or replace view v_ent_devolucion_exceso
  with (security_invoker = true) as
  with salio as (
    select av.pedido_id, li.producto_id, al.lote, sum(al.cant_uds) as uds_salio
      from ent_alisto_vigente av
      join ent_alisto_linea   li on li.alisto_id = av.alisto_id
      join ent_alisto_lote    al on al.linea_id  = li.id
     group by 1,2,3
  ), volvio as (
    -- SIN `where dv.pedido_id is not null`: con la columna NOT NULL esa condicion
    -- es siempre verdadera. Y dejarla escrita seria peor que redundante — diria
    -- que existe un caso sin pedido, que es justo lo que §A cerro. Mientras estuvo,
    -- hacia que una devolucion suelta fuera INVISIBLE para esta vista.
    select dv.pedido_id, dl.producto_id, dl.lote, sum(dl.cant_uds) as uds_volvio
      from ent_devolucion_vigente dv
      join ent_devolucion_linea   dl on dl.devolucion_id = dv.devolucion_id
     group by 1,2,3
  )
  select v.pedido_id, v.producto_id, v.lote,
         v.uds_volvio,
         coalesce(s.uds_salio, 0)                       as uds_salio,
         v.uds_volvio - coalesce(s.uds_salio, 0)        as uds_exceso
    from volvio v
    left join salio s
      on s.pedido_id = v.pedido_id and s.producto_id = v.producto_id and s.lote = v.lote
   where v.uds_volvio > coalesce(s.uds_salio, 0);

grant select on v_ent_devolucion_exceso to authenticated;

comment on view v_ent_devolucion_exceso is
  'Las lineas donde volvio MAS de lo que salio en esa entrega. Es un AVISO, no un '
  'bloqueo: puede volver producto de una entrega anterior en el mismo camion. '
  'Derivada a proposito — un flag escrito por la app puede mentir, una vista no. '
  'El `left join` sin fila (uds_salio 0) es el caso de un lote que nunca salio en '
  'ese pedido: tambien es exceso, y del grande.';


-- ── §C · LO QUE VA A IR A ODOO, guardado entero ─────────────────────────
-- UNA sola pareja de tablas con `tipo`, y no dos parejas gemelas. Las CUATRO
-- automatizaciones pendientes —traslado interno, NC, validacion de entregas,
-- orden de fabricacion— entran por la misma puerta. Dos esquemas gemelos son
-- dos que se desincronizan, que es el modo de falla de siempre en este repo.
--
-- ⚠️ ESTO NO ESCRIBE EN ODOO NI LO INTENTA. Guarda el payload completo para que
-- el dia que se abra el carril de escritura, automatizar sea conectar un boton a
-- datos que YA estan — no salir a reconstruirlos.
create table if not exists ent_odoo_pendiente (
  id             bigint generated always as identity primary key,
  tipo           text    not null check (tipo in ('nota_credito','traslado_interno')),
  -- de donde nacio
  pedido_id      bigint  references ent_pedido(id),
  devolucion_id  bigint  references ent_devolucion(id),
  -- lo que va a ir a Odoo
  fecha          date    not null,
  cliente_id     integer,
  cliente_nombre text,
  destinatario   text,                     -- el traslado interno no tiene cliente
  factura_id     integer,                  -- account.move.id de la factura ORIGINAL
  factura_nombre text,
  nota           text,
  creado_en      timestamptz not null default now(),
  creado_por     text    not null,
  -- CADA TIPO PIDE LO SUYO, y el coalesce cierra el hueco del NULL por la misma
  -- razon que en §A: un CHECK se satisface con TRUE o con NULL.
  constraint ent_odoo_pendiente_forma_ok check (coalesce(
    case tipo
      when 'nota_credito' then
        devolucion_id is not null and factura_id is not null and cliente_id is not null
      when 'traslado_interno' then
        pedido_id is not null
    end, false))
);
create index if not exists ent_odoo_pendiente_tipo_idx on ent_odoo_pendiente (tipo, fecha desc);
create index if not exists ent_odoo_pendiente_ped_idx  on ent_odoo_pendiente (pedido_id);

-- La linea: MISMA forma que ent_devolucion_linea, y no por copiar. Es el mismo
-- dato —producto, lote, cuanto, en que unidad— y la unidad va congelada por la
-- misma razon: es la que va a ir al documento de Odoo, no la de hoy.
create table if not exists ent_odoo_pendiente_linea (
  id            bigint  generated always as identity primary key,
  pendiente_id  bigint  not null references ent_odoo_pendiente(id),
  producto_id   integer not null,
  lote          text    not null check (lote ~ '^\d{1,3} / \d{1,2}-\d{2}$'),
  cant_uds      numeric not null,
  uom_id        integer not null,
  uom_nombre    text    not null,
  cant_uom      numeric not null,
  uom_factor    numeric not null
);
create index if not exists ent_odoo_pendiente_linea_idx on ent_odoo_pendiente_linea (pendiente_id);

-- ── LA MARCA DE HECHO · POR QUE EXISTE ─────────────────────────────────
-- Andrea pidio "una pareja de tablas". Esta es la tercera y la agrego con su
-- razon: sin ella la lista NUNCA se vacia, y una lista de la que nada sale deja
-- de leerse. Es literalmente la leccion del pendiente 24 —las "sin lote" salian
-- por un criterio cierto para siempre— y la de ent_factura_decision.
--
-- ES UNA TABLA APARTE Y NO UNA COLUMNA `estado`, porque el modulo entero es
-- append-only: no hay grant de UPDATE en ninguna parte. Marcar hecho es
-- insertar, igual que ent_pedido_valida y ent_alisto_linea_autorizacion.
create table if not exists ent_odoo_hecho (
  id           bigint generated always as identity primary key,
  pendiente_id bigint not null references ent_odoo_pendiente(id),
  referencia   text,                       -- el documento creado en Odoo, si se sabe
  creado_en    timestamptz not null default now(),
  creado_por   text   not null
);
create index if not exists ent_odoo_hecho_pend_idx on ent_odoo_hecho (pendiente_id, creado_en desc);

-- La cola: lo que TODAVIA no se hizo. Misma sonda de existencia que
-- v_ent_excepcion_pendiente: se pregunta si HAY fila, no que dice.
-- ⚠️ LAS COLUMNAS, UNA POR UNA, Y NO `select p.*`. Un `*` en una vista se congela
-- en el momento de crearla: agregarle una columna a la tabla NO la agrega a la
-- vista, y el dia que alguien la agregue va a buscar por que no aparece. Listarlas
-- ademas deja escrito que `creado_por` se expone a proposito (D8 lo usa).
create or replace view v_ent_odoo_pendiente
  with (security_invoker = true) as
  select p.id, p.tipo, p.pedido_id, p.devolucion_id, p.fecha,
         p.cliente_id, p.cliente_nombre, p.destinatario,
         p.factura_id, p.factura_nombre, p.nota, p.creado_en, p.creado_por
    from ent_odoo_pendiente p
   where not exists (select 1 from ent_odoo_hecho h where h.pendiente_id = p.id);

-- RLS Y GRANTS · select + insert y nada mas **EN POLITICA**.
-- ⚠️ EN GRANT NO, Y ESTO SE MIDIO DESPUES DE APLICAR: `anon` y `authenticated`
-- quedan con UPDATE y DELETE sobre las tres tablas (12 = 3 tablas x 2 privilegios
-- x 2 roles). No lo pone este archivo: es el default de Supabase sobre `public`,
-- y un `grant select, insert` AGREGA, no revoca. Este comentario decia "en
-- politica Y en grant" y era FALSO.
-- QUE PROTEGE IGUAL: la RLS esta activa y no hay politica de update ni de delete,
-- asi que por PostgREST un update o un delete no toca ninguna fila. El append-only
-- se sostiene por la RLS, no por el grant.
-- ES LA MISMA DEUDA DEL §6 de ENTREGAS_EXCEPCIONES_LINEA.sql —"los grants abiertos
-- (anon con los siete privilegios) quedan como deuda, por decision de Andrea"— y
-- estas tres tablas se suman a esa lista. No se toca aca: revocar defaults es una
-- sesion de permisos, no un anexo de este cambio.
alter table ent_odoo_pendiente       enable row level security;
alter table ent_odoo_pendiente_linea enable row level security;
alter table ent_odoo_hecho           enable row level security;

drop policy if exists ent_odoo_pendiente_sel       on ent_odoo_pendiente;
drop policy if exists ent_odoo_pendiente_ins       on ent_odoo_pendiente;
drop policy if exists ent_odoo_pendiente_linea_sel on ent_odoo_pendiente_linea;
drop policy if exists ent_odoo_pendiente_linea_ins on ent_odoo_pendiente_linea;
drop policy if exists ent_odoo_hecho_sel           on ent_odoo_hecho;
drop policy if exists ent_odoo_hecho_ins           on ent_odoo_hecho;

create policy ent_odoo_pendiente_sel       on ent_odoo_pendiente       for select to authenticated using (true);
create policy ent_odoo_pendiente_ins       on ent_odoo_pendiente       for insert to authenticated with check (true);
create policy ent_odoo_pendiente_linea_sel on ent_odoo_pendiente_linea for select to authenticated using (true);
create policy ent_odoo_pendiente_linea_ins on ent_odoo_pendiente_linea for insert to authenticated with check (true);
create policy ent_odoo_hecho_sel           on ent_odoo_hecho           for select to authenticated using (true);
-- ⚠️ MARCAR HECHO ES DE SOCIAS. Registrar la devolucion la puede hacer Daniel
-- (es quien recibe el producto); decir "ya hice la NC en Odoo" no. Se usa
-- `acceso_es_socia()`, la definicion unica desde el 24-ago — NO se re-escribe la
-- condicion a mano, que es lo que hizo la politica del 8-sep y quedo como deuda.
create policy ent_odoo_hecho_ins on ent_odoo_hecho for insert to authenticated
  with check (acceso_es_socia());

grant select, insert on ent_odoo_pendiente       to authenticated;
grant select, insert on ent_odoo_pendiente_linea to authenticated;
grant select, insert on ent_odoo_hecho           to authenticated;
grant select on v_ent_odoo_pendiente to authenticated;

comment on table ent_odoo_pendiente is
  'Lo que hay que crear en Odoo y todavia no se creo, con el payload COMPLETO. '
  'tipo = nota_credito (nace de una devolucion) | traslado_interno (nace de una entrega '
  'sin factura). NO escribe en Odoo. Hecho se marca insertando en ent_odoo_hecho.';


-- ── LA PRUEBA DE QUE ESTO CORRIO · ADENTRO DE LA TRANSACCION ────────────
-- ⚠️ ESPERADO: **2 · 1 · 3**. Una fila, tres numeros.
--
-- POR QUE EXISTE, medido el 16-sep: el primer intento de pegar este bloque
-- devolvio "Success. No rows returned" y NO APLICO NADA — ni una columna, ni el
-- check, ni una tabla. Un "Success" del editor no prueba que el DDL entro, y
-- sobre ese Success se llego a escribir en el header y en la bitacora que el
-- cambio estaba aplicado. Durante unos minutos los dos decian algo falso.
--
-- Con esta consulta eso no puede volver a pasar en silencio:
--   · si el editor muestra la fila con 2 · 1 · 3 -> corrio hasta el final;
--   · si vuelve a decir "Success. No rows returned" -> NI SIQUIERA LLEGO ACA,
--     y se sabe en el momento en vez de dos pasos despues.
--
-- ⚠️ VA ADENTRO DEL begin/commit A PROPOSITO. Afuera mediria otra cosa: que el
-- cambio quedo. Aca mide que la transaccion llego al final, que es la pregunta
-- que el "Success" dejo sin contestar. Las dos hacen falta — V1/V3/V5/V6 siguen
-- corriendose DESPUES.
--
-- ⚠️ Y SI DA OTROS NUMEROS, no hay que limpiar nada: la transaccion todavia no
-- commiteo. Un `rollback;` a mano, o cerrar la pestaña, y la base queda intacta.
select (select count(*) from information_schema.columns
         where table_name = 'ent_devolucion'
           and column_name in ('pedido_id','causa'))              as columnas_nuevas,
       (select count(*) from pg_constraint
         where conname = 'ent_devolucion_causa_ok')               as check_nuevo,
       (select count(*) from pg_class c
          join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public'
           and c.relname in ('ent_odoo_pendiente','ent_odoo_pendiente_linea',
                             'ent_odoo_hecho'))                   as tablas_nuevas;

commit;


-- ════════════════════════════════════════════════════════════════════════
-- PRUEBAS · correr DESPUES del commit, UNA POR UNA.
-- Varias terminan a proposito en error, y un error aborta el resto del lote si
-- se pegan todas juntas.
--
-- ⚠️ CADA UNA CONSTRUYE SU PROPIO CASO, y las dos CONTROLES (D0 y D4) tienen que
-- PASAR: sin ellas, una prueba que espera ERROR no distingue "el candado
-- funciono" de "la escalera estaba rota".
-- Todo dentro de begin/rollback: no queda nada escrito.
-- ════════════════════════════════════════════════════════════════════════

-- D0 · CONTROL · ESPERADO: PASA. La escalera nueva anda: devolucion CON pedido
--      y CON causa valida entra.
begin;
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por)
  values (current_date, 'manual', 'regalia', 'prueba-d0');
  insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, causa, creado_por)
  select current_date, 999999, 'PRUEBA d0', id, 'producto_equivocado', 'prueba-d0'
    from ent_pedido where creado_por = 'prueba-d0';
  select 'D0 OK: con pedido y causa valida, entra' as resultado;
rollback;

-- D1 · ESPERADO: **ERROR** de `ent_devolucion_causa_ok` — causa fuera de lista.
begin;
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por)
  values (current_date, 'manual', 'regalia', 'prueba-d1');
  insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, causa, creado_por)
  select current_date, 999999, 'PRUEBA d1', id, 'se_mojo', 'prueba-d1'
    from ent_pedido where creado_por = 'prueba-d1';
  select 'D1 MAL: entro una causa inventada' as resultado;
rollback;

-- D2 · ESPERADO: **ERROR** — con pedido y SIN causa. Es el espejo de P0-b: lo
--      que hoy pasa, despues de §A no tiene que pasar.
begin;
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por)
  values (current_date, 'manual', 'regalia', 'prueba-d2');
  insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, creado_por)
  select current_date, 999999, 'PRUEBA d2', id, 'prueba-d2'
    from ent_pedido where creado_por = 'prueba-d2';
  select 'D2 MAL: entro sin causa' as resultado;
rollback;

-- D3 · ESPERADO: **ERROR** — causa 'otro' con nota de 3 caracteres (minimo 6).
--      ⚠️ Y ESTA ES LA QUE CAZA EL HUECO DEL NULL: si se "arregla" el CHECK
--      sacando los coalesce, esta prueba sigue dando error pero D3-bis no.
begin;
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por)
  values (current_date, 'manual', 'regalia', 'prueba-d3');
  insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, causa, nota, creado_por)
  select current_date, 999999, 'PRUEBA d3', id, 'otro', 'abc', 'prueba-d3'
    from ent_pedido where creado_por = 'prueba-d3';
  select 'D3 MAL: entro otro con nota corta' as resultado;
rollback;

-- D3-bis · ESPERADO: **ERROR** — causa 'otro' con nota NULL.
--      Sin el `coalesce` del CHECK esta fila ENTRARIA: `length(btrim(null)) >= 6`
--      da NULL, la conjuncion queda NULL y Postgres deja pasar. Es el hueco
--      medido el 14-ago en ent_alisto_linea_no_entrega_ok. Si D3 da error y
--      D3-bis pasa, alguien saco los coalesce.
begin;
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por)
  values (current_date, 'manual', 'regalia', 'prueba-d3b');
  insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, causa, creado_por)
  select current_date, 999999, 'PRUEBA d3b', id, 'otro', 'prueba-d3b'
    from ent_pedido where creado_por = 'prueba-d3b';
  select 'D3-bis MAL: entro otro sin nota — se perdio el coalesce' as resultado;
rollback;

-- D4 · ESPERADO: **ERROR** — `null value in column "pedido_id" violates not-null`.
--      ⚠️ ESTA PRUEBA SE INVIRTIO EL 16-sep. Hasta esa fecha era un CONTROL que
--      tenia que PASAR ("la devolucion suelta sigue entrando sin causa"), porque la
--      columna era nullable. Con la opcion A ya no: la suelta NO entra, y eso es lo
--      que hay que comprobar.
--      Se deja escrito el cambio porque una prueba que quedo midiendo lo contrario
--      de lo que se construyo es el modo de falla del 15-sep (P0-a "fallando" por
--      la escalera rota) y el de la 7a del 14-ago: da el resultado de otra cosa y
--      nadie lo nota.
begin;
  insert into ent_devolucion (fecha, cliente_id, cliente_nombre, creado_por)
  values (current_date, 999999, 'PRUEBA d4 suelta', 'prueba-d4');
  select 'D4 MAL: entro una devolucion sin pedido' as resultado;
rollback;

-- D5 · §B · la vista del exceso MARCA y NO BLOQUEA.
--      ESPERADO: PASA, y la ultima consulta devuelve UNA fila con uds_exceso > 0.
--      Construye su propio pedido con alisto, saca 6 y devuelve 10.
begin;
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por)
  values (current_date, 'manual', 'regalia', 'prueba-d5');
  insert into ent_alisto (pedido_id, responsable, creado_por)
  select id, 'prueba-d5', 'prueba-d5' from ent_pedido where creado_por = 'prueba-d5';
  insert into ent_alisto_linea (alisto_id, producto_id, cant_uds, cant_uom)
  select id, 451, 6, 6 from ent_alisto where creado_por = 'prueba-d5';
  insert into ent_alisto_lote (linea_id, lote, cant_uds, orden)
  select l.id, '100 / 1-27', 6, 0
    from ent_alisto_linea l join ent_alisto a on a.id = l.alisto_id
   where a.creado_por = 'prueba-d5';

  -- vuelven DIEZ de un lote del que salieron SEIS: entra igual.
  insert into ent_devolucion (fecha, cliente_id, cliente_nombre, pedido_id, causa, creado_por)
  select current_date, 999999, 'PRUEBA d5', id, 'producto_equivocado', 'prueba-d5'
    from ent_pedido where creado_por = 'prueba-d5';
  insert into ent_devolucion_linea
    (devolucion_id, producto_id, lote, cant_uds, uom_id, uom_nombre, cant_uom, uom_factor)
  select id, 451, '100 / 1-27', 10, 1, 'Unidades', 10, 1
    from ent_devolucion where creado_por = 'prueba-d5';

  -- ESPERADO: 1 fila · uds_salio 6 · uds_volvio 10 · uds_exceso 4
  select e.* from v_ent_devolucion_exceso e
    join ent_pedido p on p.id = e.pedido_id
   where p.creado_por = 'prueba-d5';
rollback;

-- D6 · §C · ESPERADO: **ERROR** de `ent_odoo_pendiente_forma_ok`.
--      Una nota de credito sin devolucion no es una nota de credito.
begin;
  insert into ent_odoo_pendiente (tipo, fecha, cliente_id, cliente_nombre, factura_id, creado_por)
  values ('nota_credito', current_date, 999999, 'PRUEBA d6', 4321, 'prueba-d6');
  select 'D6 MAL: entro una NC sin devolucion' as resultado;
rollback;

-- D7 · §C · CONTROL · ESPERADO: PASA, y la ultima consulta devuelve 1 fila.
--      Un traslado interno completo, con su linea, aparece en la cola.
begin;
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por)
  values (current_date, 'manual', 'consumo_interno', 'prueba-d7');
  insert into ent_odoo_pendiente (tipo, pedido_id, fecha, destinatario, creado_por)
  select 'traslado_interno', id, current_date, 'Cocina', 'prueba-d7'
    from ent_pedido where creado_por = 'prueba-d7';
  insert into ent_odoo_pendiente_linea
    (pendiente_id, producto_id, lote, cant_uds, uom_id, uom_nombre, cant_uom, uom_factor)
  select id, 453, '100 / 1-27', 24, 37, 'Paquete de 4', 6, 0.25
    from ent_odoo_pendiente where creado_por = 'prueba-d7';
  -- ESPERADO: 1 fila. (Y ojo al factor: 6 paq x 4 = 24 uds. Escrito a mano
  -- entraria 4x corto, que es la trampa que §12 documenta.)
  select v.id, v.tipo, v.destinatario, l.producto_id, l.cant_uom, l.uom_factor, l.cant_uds
    from v_ent_odoo_pendiente v
    join ent_odoo_pendiente_linea l on l.pendiente_id = v.id
   where v.creado_por = 'prueba-d7';
rollback;

-- D8 · §C · la cola se VACIA al marcar hecho.
--      ESPERADO: la primera consulta 1 fila, la segunda 0 filas.
--      ⚠️ Si el insert en ent_odoo_hecho da "new row violates row-level security",
--      la sesion no es de una socia: es lo correcto, pero entonces esta prueba hay
--      que correrla con una sesion que lo sea, o desde el SQL Editor (postgres
--      saltea la RLS).
begin;
  insert into ent_pedido (fecha_despacho, origen, motivo, creado_por)
  values (current_date, 'manual', 'consumo_interno', 'prueba-d8');
  insert into ent_odoo_pendiente (tipo, pedido_id, fecha, destinatario, creado_por)
  select 'traslado_interno', id, current_date, 'Cocina', 'prueba-d8'
    from ent_pedido where creado_por = 'prueba-d8';
  select count(*) as antes_debe_ser_1 from v_ent_odoo_pendiente where creado_por = 'prueba-d8';
  insert into ent_odoo_hecho (pendiente_id, referencia, creado_por)
  select id, 'WH/INT/00001', 'prueba-d8' from ent_odoo_pendiente where creado_por = 'prueba-d8';
  select count(*) as despues_debe_ser_0 from v_ent_odoo_pendiente where creado_por = 'prueba-d8';
rollback;


-- ════════════════════════════════════════════════════════════════════════
-- DESPUES · VERIFICAR. Solo lectura.
-- ════════════════════════════════════════════════════════════════════════

-- V1 · las dos columnas existen   [2 filas · pedido_id NO · causa YES]
--      ⚠️ `pedido_id` tiene que decir is_nullable = NO. Si dice YES, el
--      `add column` se salteo y la columna quedo floja debajo de un archivo que
--      dice lo contrario.
select column_name, data_type, is_nullable
  from information_schema.columns
 where table_name = 'ent_devolucion' and column_name in ('pedido_id','causa')
 order by column_name;

-- V2 · el CHECK quedo VALIDO, no NOT VALID        [convalidated = t]
select conname, convalidated, pg_get_constraintdef(oid) as definicion
  from pg_constraint
 where conrelid = 'ent_devolucion'::regclass and conname = 'ent_devolucion_causa_ok';

-- V3 · las tres tablas y la vista existen         [4 filas]
select table_name, table_type from information_schema.tables
 where table_name in ('ent_odoo_pendiente','ent_odoo_pendiente_linea',
                      'ent_odoo_hecho','v_ent_odoo_pendiente')
 order by 1;

-- V4 · ⚠️ DIO **12**, NO 0. La expectativa estaba MAL escrita, no el resultado:
--      `anon` y `authenticated` traen UPDATE y DELETE por el default de Supabase
--      sobre `public`, y `grant select, insert` agrega sin revocar. 12 = 3 tablas
--      x 2 privilegios x 2 roles. Protege la RLS (no hay politica de update ni de
--      delete), no el grant. Se suma a la deuda del §6. Ver la nota en §C.
select table_name, privilege_type, grantee
  from information_schema.role_table_grants
 where table_name in ('ent_odoo_pendiente','ent_odoo_pendiente_linea','ent_odoo_hecho')
   and privilege_type in ('UPDATE','DELETE')
   and grantee in ('anon','authenticated')
 order by 1,2;

-- V5 · ⚠️ NADA SE MOVIO. Tiene que dar EXACTAMENTE lo mismo que 0e.
--      MEDIDO en 0e el 16-sep: **0 filas**. Asi que V5 tiene que dar 0 filas.
--      Si devuelve aunque sea una, algo escribio: §A/§B/§C no insertan nada y las
--      pruebas van todas en rollback. Seria el momento de parar y mirar que.
--      (Ojo: 0 filas no es "no hay devoluciones que contar". La vista filtra por
--      `recibido_en > corte`, y ademas ent_devolucion esta vacia — las dos cosas
--      dan 0 y por caminos distintos.)
select producto_id, sum(uds) as uds, count(*) as filas
  from ent_devuelto_desde_ancla group by 1 order by 1;

-- V6 · la tabla sigue vacia                         [0 filas]
--      §A/§B/§C no escriben ninguna fila, y las pruebas van todas en rollback.
--      Si aca aparece algo, alguna prueba se corrio sin su `rollback`.
select id, fecha, cliente_nombre, pedido_id, causa from ent_devolucion order by id;

-- V7 · sin rastro de las pruebas    [0 en las tres]
select (select count(*) from ent_pedido        where creado_por like 'prueba-%') as pedidos,
       (select count(*) from ent_devolucion    where creado_por like 'prueba-%') as devoluciones,
       (select count(*) from ent_odoo_pendiente where creado_por like 'prueba-%') as pendientes;

-- V8 · la vista del exceso contesta y no hay ninguno hoy   [0 filas esperadas,
--      porque ninguna devolucion vieja tiene pedido_id]
select * from v_ent_devolucion_exceso order by pedido_id, producto_id, lote;

-- V9 · ⚠️ LA CUARTA PUNTA SIGUE VIVA. `ent_devuelto_desde_ancla` cuelga de
--      `ent_devolucion_vigente`, que §A redefine. Si esto contesta, el
--      `create or replace` no la rompio. (V5 ya compara los numeros; esto
--      comprueba que el objeto existe y responde.)
select count(*) as responde from ent_devuelto_desde_ancla;

-- V10 · las dos columnas nuevas llegaron a la vista vigente   [2 filas]
select column_name from information_schema.columns
 where table_name = 'ent_devolucion_vigente' and column_name in ('pedido_id','causa')
 order by 1;
