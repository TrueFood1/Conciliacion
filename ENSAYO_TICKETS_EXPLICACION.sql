-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_TICKETS_EXPLICACION.sql  ·  29-sep-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- El tipo de detalle 'explicacion' («En palabras claras»)
--
-- ⚠️ ARCHIVO GENERADO. No se edita a mano: se regenera con
--     python3 herramientas/ensayos/armar_ensayo_explicacion.py
--   El bloque DDL es el de TICKETS_EXPLICACION.sql BYTE A BYTE, cortado por
--   sus marcas. md5 del bloque: 5e1891d1744e8057d5aa843abeadfe0e
--
-- QUE HACE
--   1. Aplica todo, igual que el pegado (incluido su candado de entrada).
--   2. Le da a `postgres` permiso de ponerse truefie_cc (SOLO para ensayar: se
--      va con el rollback; el pegado no lo trae).
--   3. Prueba como truefie_cc, como anon, como socia (sesion simulada, con RLS)
--      y como el editor SQL. Ningun correo va escrito: la socia sale de
--      v_acceso_usuario. Los tickets se eligen solos: uno abierto de Truefie y
--      uno propio.
--   4. Apaga el guardia un momento para probar que la RLS SOLA frena.
--   5. rollback. No queda nada: ni las filas, ni los CHECK, ni las vistas nuevas.
--
-- ⚠️ E10 NO ES "volver a correr ENSAYO_TICKETS_CC.sql": ese ensayo CREA el rol
--   truefie_cc, y su candado de entrada frena si el rol ya existe (existe desde
--   el 27-sep). E10 repite ADENTRO de este lo que podria haberse roto: cierre y
--   anuncio siguen entrando, criterio sigue afuera, la socia lee y escribe, el
--   editor SQL tambien, y la RLS sola sigue frenando.
--
-- COMO SE LEE
--   Una tabla de 23 filas, TODAS con ok = true. Un RECHAZA da ok solo si
--   el SQLSTATE y el pedazo de mensaje de `esperado` estan en `obtenido`.
--   Si el editor dice "Success. No rows returned", no llego al final y no vale.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ═══ DDL · DESDE ACA (ENSAYO_TICKETS_EXPLICACION.sql copia este bloque tal cual) ═══

-- §0 · CANDADO DE ENTRADA: lo que se reemplaza es EXACTAMENTE lo que se leyo
-- el 29-sep. Si alguien lo cambio despues, esto no lo pisa: se vuelve a medir.
do $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.ticket_detalle_guard()'::regprocedure)
       is distinct from '67d47f5f6c65979b2cf030baeb1c5522' then
    raise exception 'ticket_detalle_guard no es el que se leyo el 29-sep: volver a medir antes de pegar';
  end if;
  if md5(pg_get_viewdef('public.v_ticket'::regclass)) is distinct from '805bb297da4a3d00bd91163253816806' then
    raise exception 'v_ticket no es la que se leyo el 29-sep: volver a medir antes de pegar';
  end if;
  if md5(pg_get_viewdef('public.v_ticket_historial'::regclass)) is distinct from '0901da22b6a09bfa45f28601015a7dab' then
    raise exception 'v_ticket_historial no es la que se leyo el 29-sep: volver a medir antes de pegar';
  end if;
  if md5(pg_get_viewdef('public.v_ticket_export'::regclass)) is distinct from '7bc7c50642c67e93497ac902dc6ac1b7' then
    raise exception 'v_ticket_export no es la que se leyo el 29-sep: volver a medir antes de pegar';
  end if;
  if exists (select 1 from ticket_detalle where clase = 'explicacion') then
    raise exception 'ya hay filas explicacion: este pegado ya corrio';
  end if;
end $$;


-- §1 · LA CLASE Y SU FORMATO
alter table public.ticket_detalle drop constraint ticket_detalle_clase_ok;
alter table public.ticket_detalle add constraint ticket_detalle_clase_ok
  check (clase in ('espera','criterio','cierre','anuncio','explicacion'));

-- Los cuatro renglones, en orden, con su titulo exacto y algo escrito en cada uno.
-- [^\r\n] y no «.»: un renglon es un renglon.
alter table public.ticket_detalle add constraint ticket_detalle_explicacion_forma
  check (clase <> 'explicacion' or texto ~ U&'^Qu!00E9 es: [^\r\n]{3,}\nPor qu!00E9 importa: [^\r\n]{3,}\nQu!00E9 har!00EDa falta: [^\r\n]{3,}\nRecomendaci!00F3n: [^\r\n]{3,}$' UESCAPE '!');

-- El tamaño, de tres. Separado del anterior para que el rechazo diga CUAL fallo.
alter table public.ticket_detalle add constraint ticket_detalle_explicacion_tamano
  check (clase <> 'explicacion' or texto ~ U&'\nQu!00E9 har!00EDa falta: (chico|mediano|grande)\M' UESCAPE '!');

-- La recomendacion, de tres. POSPONER no esta a proposito: posponer lo decide
-- Andrea con su boton, no se recomienda desde aca.
alter table public.ticket_detalle add constraint ticket_detalle_explicacion_recomienda
  check (clase <> 'explicacion' or texto ~ U&'\nRecomendaci!00F3n: (HACER|CERRAR|DESCARTAR)\M' UESCAPE '!');


-- §2 · EL GUARDIA (vivo del 29-sep + 'explicacion' en los dos filtros de clase)
create or replace function public.ticket_detalle_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare quien text; socia boolean; amb text;
begin
  -- ══ CC CON ROL PROPIO · truefie_cc (27-sep-2026) ═══════════════════════
  -- Primero, por la misma razon que en ticket_estado_guard: un propio no lo ve.
  if current_user = 'truefie_cc' then
    select t.ambito into amb from ticket t where t.id = new.ticket_id;
    if amb is distinct from 'truefie' then
      raise exception 'truefie_cc no ve el ticket %: no existe o no es de Truefie. '
        'Los pendientes propios los mueve Andrea.', new.ticket_id;
    end if;
    if new.creado_por is distinct from 'cc-truefie' then
      raise exception 'truefie_cc firma creado_por = "cc-truefie". Vino: %', new.creado_por;
    end if;
    if new.clase not in ('cierre','anuncio','explicacion') then
      raise exception 'truefie_cc solo escribe cierres, anuncios y explicaciones; "%" lo define una socia.', new.clase;
    end if;
    return new;
  end if;

  if not exists (select 1 from ticket t where t.id = new.ticket_id) then
    raise exception 'no existe el ticket %', new.ticket_id;
  end if;
  quien := nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email';

  if quien is null then
    -- Mismo aviso que en §2: esto NO es un candado, es una convencion para
    -- que la fila diga de donde vino. El trigger no puede saber quien es CC.
    if new.creado_por not like 'cc-sql%' then
      raise exception 'sin sesion de Supabase (SQL Editor) hay que firmar creado_por '
        'empezando con "cc-sql". Vino: %', new.creado_por;
    end if;
    if new.clase not in ('cierre','anuncio','explicacion') then
      raise exception 'desde el SQL Editor solo se escriben cierres, anuncios y explicaciones. '
        '"Qué se espera" y "Criterio de terminado" los define una socia: si el mismo '
        'lado que escribe el criterio es el que lo cumple, el criterio no controla nada. '
        'Vino: %', new.clase;
    end if;
    return new;
  end if;

  if lower(btrim(new.creado_por)) <> lower(btrim(quien)) then
    raise exception 'creado_por dice % y la sesion es de %. La firma no se elige.',
      new.creado_por, quien;
  end if;
  socia := exists (select 1 from acceso_usuario a
                    where lower(a.email) = lower(quien)
                      and a.perfil = 'socias' and a.activo);
  if not socia and new.clase in ('espera','criterio') then
    raise exception '"%" lo define una socia, y % no lo es.', new.clase, quien;
  end if;
  return new;
end
$function$;


-- §3 · LA RLS DE truefie_cc: la misma politica, con la clase nueva
drop policy ticket_detalle_cc_ins on public.ticket_detalle;
create policy ticket_detalle_cc_ins on public.ticket_detalle
  for insert to truefie_cc
  with check (creado_por = 'cc-truefie'
              and clase in ('cierre','anuncio','explicacion')
              and exists (select 1 from public.ticket t
                           where t.id = ticket_detalle.ticket_id and t.ambito = 'truefie'));


-- §4 · v_ticket (viva del 29-sep + en_claro al final). Desempate por id: dos
-- explicaciones en la misma transaccion tienen el mismo creado_en.
create or replace view public.v_ticket with (security_invoker = true) as
 SELECT t.id,
    t.descripcion,
    t.tipo,
    t.build,
    t.doc_modificado,
    t.vista,
    t.miga,
    t.modulo,
    t.sobre,
    t.agente,
    t.standalone,
    t.viewport,
    t.tz_offset_min,
    t.tz_nombre,
    t.creado_en,
    t.creado_por,
    COALESCE(e.estado, 'sin_triar'::text) AS estado,
    e.nota AS ultima_nota,
    e.creado_en AS estado_en,
    e.creado_por AS estado_por,
    e.build_arreglo,
    e.bloquea_ticket_id,
    e.espera,
    COALESCE(des.recien_desbloqueado, false) AS recien_desbloqueado,
    des.estado_anterior,
    m.toca_numeros,
    m.escribe_en_base,
    m.toca_numeros IS NOT NULL AND NOT m.toca_numeros AND NOT m.escribe_en_base AS agente_puede,
    m.prioridad,
    m.bloquea_entrega,
    m.razon AS marca_razon,
    m.creado_por AS marca_por,
    d_esp.texto AS que_se_espera,
    d_cri.texto AS criterio_terminado,
    COALESCE(f.estado_foto, 'sin_foto'::text) AS estado_foto,
    COALESCE(f.fotos, 0::bigint) AS fotos,
    f.ultimo_error AS foto_error,
    t.ambito,
    d_cla.texto AS en_claro
   FROM ticket t
     LEFT JOIN LATERAL ( SELECT x.estado,
            x.nota,
            x.creado_en,
            x.creado_por,
            x.build_arreglo,
            x.bloquea_ticket_id,
            x.espera
           FROM ticket_estado x
          WHERE x.ticket_id = t.id
          ORDER BY x.creado_en DESC
         LIMIT 1) e ON true
     LEFT JOIN v_ticket_desbloqueo des ON des.ticket_id = t.id
     LEFT JOIN LATERAL ( SELECT x.toca_numeros,
            x.escribe_en_base,
            x.prioridad,
            x.bloquea_entrega,
            x.razon,
            x.creado_por
           FROM ticket_marca x
          WHERE x.ticket_id = t.id
          ORDER BY x.creado_en DESC
         LIMIT 1) m ON true
     LEFT JOIN LATERAL ( SELECT x.texto
           FROM ticket_detalle x
          WHERE x.ticket_id = t.id AND x.clase = 'espera'::text
          ORDER BY x.creado_en DESC
         LIMIT 1) d_esp ON true
     LEFT JOIN LATERAL ( SELECT x.texto
           FROM ticket_detalle x
          WHERE x.ticket_id = t.id AND x.clase = 'criterio'::text
          ORDER BY x.creado_en DESC
         LIMIT 1) d_cri ON true
     LEFT JOIN v_ticket_foto f ON f.ticket_id = t.id
     LEFT JOIN LATERAL ( SELECT x.texto
           FROM ticket_detalle x
          WHERE x.ticket_id = t.id AND x.clase = 'explicacion'::text
          ORDER BY x.creado_en DESC, x.id DESC
         LIMIT 1) d_cla ON true;


-- §5 · v_ticket_historial (viva del 29-sep + la etiqueta)
create or replace view public.v_ticket_historial with (security_invoker = true) as
 SELECT t.id AS ticket_id,
    0 AS orden,
    t.creado_en AS cuando,
    'reporte'::text AS que,
    t.creado_por AS quien,
    t.descripcion AS detalle,
    NULL::text AS build_arreglo
   FROM ticket t
UNION ALL
 SELECT e.ticket_id,
    1 AS orden,
    e.creado_en AS cuando,
        CASE e.estado
            WHEN 'disponible'::text THEN 'Disponible'::text
            WHEN 'bloqueado'::text THEN 'Bloqueado'::text
            WHEN 'en_curso'::text THEN 'En curso'::text
            WHEN 'en_validacion'::text THEN 'En validación'::text
            WHEN 'cerrado'::text THEN 'Cerrado'::text
            WHEN 'pospuesto'::text THEN 'Pospuesto'::text
            ELSE 'Descartado'::text
        END AS que,
    e.creado_por AS quien,
    (COALESCE(e.nota, ''::text) || COALESCE('  · espera: '::text || e.espera, ''::text)) || COALESCE('  · bloqueado por T-'::text || lpad(e.bloquea_ticket_id::text, 4, '0'::text), ''::text) AS detalle,
    e.build_arreglo
   FROM ticket_estado e
UNION ALL
 SELECT m.ticket_id,
    1 AS orden,
    m.creado_en AS cuando,
    'triaje'::text AS que,
    m.creado_por AS quien,
    ((((
        CASE
            WHEN m.toca_numeros OR m.escribe_en_base THEN 'Un agente NO lo toma. '::text
            ELSE 'Un agente puede tomarlo. '::text
        END || 'Prioridad '::text) || m.prioridad) ||
        CASE
            WHEN m.bloquea_entrega THEN ' · bloquea una entrega'::text
            ELSE ''::text
        END) || '. '::text) || m.razon AS detalle,
    NULL::text AS build_arreglo
   FROM ticket_marca m
UNION ALL
 SELECT d.ticket_id,
    1 AS orden,
    d.creado_en AS cuando,
        CASE d.clase
            WHEN 'espera'::text THEN 'Qué se espera'::text
            WHEN 'criterio'::text THEN 'Criterio de terminado'::text
            WHEN 'cierre'::text THEN 'Cierre'::text
            WHEN 'explicacion'::text THEN 'En palabras claras'::text
            ELSE 'Anuncio'::text
        END AS que,
    d.creado_por AS quien,
    d.texto AS detalle,
    NULL::text AS build_arreglo
   FROM ticket_detalle d
UNION ALL
 SELECT f.ticket_id,
    1 AS orden,
    f.creado_en AS cuando,
        CASE f.resultado
            WHEN 'subida'::text THEN 'foto'::text
            WHEN 'fallo'::text THEN 'foto perdida'::text
            ELSE 'foto sin respuesta'::text
        END AS que,
    f.creado_por AS quien,
    COALESCE(f.error, f.ruta) AS detalle,
    NULL::text AS build_arreglo
   FROM ticket_foto f
  WHERE f.resultado <> 'intento'::text
  ORDER BY 1, 2, 3;


-- §6 · v_ticket_export (viva del 29-sep + la seccion)
create or replace view public.v_ticket_export with (security_invoker = true) as
 SELECT id,
    ('tickets/T-'::text || lpad(id::text, 4, '0'::text)) || '.md'::text AS archivo,
    concat_ws('
'::text, (('# T-'::text || lpad(id::text, 4, '0'::text)) || ' · '::text) ||
        CASE tipo
            WHEN 'no_funciona'::text THEN 'Algo no funciona'::text
            WHEN 'duda'::text THEN 'Tengo una duda'::text
            WHEN 'encargo'::text THEN 'Encargo'::text
            ELSE 'Se me ocurrió algo'::text
        END, '', ((('> **Estado:** '::text ||
        CASE estado
            WHEN 'sin_triar'::text THEN 'Sin triar'::text
            WHEN 'disponible'::text THEN 'Disponible'::text
            WHEN 'bloqueado'::text THEN 'Bloqueado'::text
            WHEN 'en_curso'::text THEN 'En curso'::text
            WHEN 'en_validacion'::text THEN 'En validación'::text
            WHEN 'cerrado'::text THEN 'Cerrado'::text
            WHEN 'pospuesto'::text THEN 'Pospuesto'::text
            ELSE 'Descartado'::text
        END) || COALESCE('  ·  **Prioridad:** '::text || prioridad, ''::text)) ||
        CASE
            WHEN bloquea_entrega THEN '  ·  ⚠️ **bloquea una entrega**'::text
            ELSE ''::text
        END) ||
        CASE
            WHEN recien_desbloqueado THEN '  ·  🆕 **recién desbloqueado**'::text
            ELSE ''::text
        END, ((('> **Reportó:** '::text || creado_por) || '  ·  **Cuándo:** '::text) || to_char(creado_en, 'YYYY-MM-DD HH24:MI'::text)) || COALESCE((' ('::text || tz_nombre) || ')'::text, ''::text), '', '## Qué pasa', '', descripcion, '',
        CASE
            WHEN en_claro IS NULL THEN ''::text
            ELSE (('## En palabras claras'::text || E'\n\n'::text) || en_claro) || E'\n'::text
        END,
        CASE
            WHEN que_se_espera IS NULL THEN ''::text
            ELSE (('## Qué se espera'::text || '

'::text) || que_se_espera) || '
'::text
        END,
        CASE
            WHEN criterio_terminado IS NULL THEN (('## Criterio de terminado'::text || '

'::text) || '_Sin escribir. **Hasta que exista, esto no se toma**: sin criterio, "terminado" se discute al final._'::text) || '
'::text
            ELSE (('## Criterio de terminado'::text || '

'::text) || criterio_terminado) || '
'::text
        END,
        CASE
            WHEN estado <> 'bloqueado'::text THEN ''::text
            ELSE (('## Bloqueado por'::text || '

'::text) || COALESCE('T-'::text || lpad(bloquea_ticket_id::text, 4, '0'::text), espera, '—'::text)) || '
'::text
        END, '## Dónde estaba parado', '', '| | |', '|---|---|', (('| Pantalla | '::text || COALESCE(miga, '—'::text)) || COALESCE((' (`'::text || vista) || '`)'::text, ''::text)) || ' |'::text, ('| Módulo | '::text || COALESCE(modulo, '—'::text)) || ' |'::text, ('| Encima | '::text || COALESCE(sobre, '— nada'::text)) || ' |'::text, ('| Build | '::text || build) || ' |'::text, ('| Archivo cargado | '::text || COALESCE(doc_modificado, '— no capturado'::text)) || ' |'::text, ('| Desde el ícono | '::text || COALESCE(standalone::text, '—'::text)) || ' |'::text, ('| Pantalla física | '::text || COALESCE(viewport, '—'::text)) || ' |'::text, ('| Aparato | '::text || COALESCE(agente, '—'::text)) || ' |'::text, ('| Foto | '::text ||
        CASE estado_foto
            WHEN 'ok'::text THEN fotos || ' adjunta(s)'::text
            WHEN 'perdida'::text THEN '⚠️ SE PERDIÓ LA SUBIDA — '::text || COALESCE(foto_error, ''::text)
            WHEN 'sin_respuesta'::text THEN '⚠️ se intentó subir y no se supo cómo terminó'::text
            ELSE 'sin foto'::text
        END) || ' |'::text, '', '## Marca', '',
        CASE
            WHEN toca_numeros IS NULL THEN '_Sin triar. Hasta que una socia lo mire, **un agente no lo toma**._'::text
            ELSE (((((((((((((('- ¿Toca números? **'::text ||
            CASE
                WHEN toca_numeros THEN 'Sí'::text
                ELSE 'No'::text
            END) || '**'::text) || '
'::text) || '- ¿Escribe en la base? **'::text) ||
            CASE
                WHEN escribe_en_base THEN 'Sí'::text
                ELSE 'No'::text
            END) || '**'::text) || '
'::text) || '- ➡️ **'::text) ||
            CASE
                WHEN agente_puede THEN 'Un agente puede tomarlo.'::text
                ELSE 'Un agente NO lo toma.'::text
            END) || '**'::text) || '

'::text) || '> '::text) || marca_razon) || '  — '::text) || COALESCE(marca_por, ''::text)
        END, '', COALESCE(( SELECT '## Cierres

'::text || string_agg((('- '::text || to_char(d.creado_en, 'YYYY-MM-DD'::text)) || ' · '::text) || d.texto, '
'::text ORDER BY d.creado_en)
           FROM ticket_detalle d
          WHERE d.ticket_id = t.id AND d.clase = 'cierre'::text), ''::text), '', COALESCE(( SELECT '## Anuncios de sesión

'::text || string_agg((('- '::text || to_char(d.creado_en, 'YYYY-MM-DD'::text)) || ' · '::text) || d.texto, '
'::text ORDER BY d.creado_en)
           FROM ticket_detalle d
          WHERE d.ticket_id = t.id AND d.clase = 'anuncio'::text), ''::text)) AS contenido
   FROM v_ticket t;

-- ═══ DDL · HASTA ACA ═══


-- ── SOLO PARA ENSAYAR: que el editor pueda ponerse el rol. Se va con el rollback.
grant truefie_cc to postgres with set true, inherit false;


-- ── LAS PRUEBAS ───────────────────────────────────────────────────────────
do $$
declare
  v_socia text;
  v_tv bigint;           -- un ticket de Truefie ABIERTO
  v_tp bigint;           -- un pendiente PROPIO
  v_x1 bigint; v_x2 bigint;
  v_t1 text; v_t2 text; v_t3 text;
  v_k1 text; v_k2 text; v_k3 text; v_k4 text; v_k5 text;
  v_k6 text; v_k7 text; v_k8 text; v_k9 text; v_k10 text;
  v_res jsonb := '[]'::jsonb;
begin
  if not pg_has_role('postgres', 'truefie_cc', 'SET') then
    raise exception 'postgres no puede ponerse truefie_cc: el ensayo no puede probar nada';
  end if;
  select email into v_socia from v_acceso_usuario where perfil = 'socias' and activo order by email limit 1;
  select id into v_tv from v_ticket
   where ambito = 'truefie' and estado not in ('cerrado','pospuesto','descartado') order by id limit 1;
  select id into v_tp from ticket where ambito = 'propio' order by id limit 1;
  if v_socia is null or v_tv is null or v_tp is null then
    raise exception 'falta algo para ensayar (socia %, abierto %, propio %)', v_socia is not null, v_tv, v_tp;
  end if;

  -- ── E1–E6 · como truefie_cc ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'truefie_cc', true);
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tv, 'explicacion', U&'Qu!00E9 es: prueba del ensayo, no queda nada.' UESCAPE '!' || chr(10) || U&'Por qu!00E9 importa: prueba que el formato entra.' UESCAPE '!' || chr(10) || U&'Qu!00E9 har!00EDa falta: chico. Nada, es un ensayo.' UESCAPE '!' || chr(10) || U&'Recomendaci!00F3n: HACER, prioridad 1.' UESCAPE '!', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'E1 explicacion bien formada, ticket de Truefie abierto', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'E1 explicacion bien formada, ticket de Truefie abierto', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tp, 'explicacion', U&'Qu!00E9 es: prueba del ensayo, no queda nada.' UESCAPE '!' || chr(10) || U&'Por qu!00E9 importa: prueba que el formato entra.' UESCAPE '!' || chr(10) || U&'Qu!00E9 har!00EDa falta: chico. Nada, es un ensayo.' UESCAPE '!' || chr(10) || U&'Recomendaci!00F3n: HACER, prioridad 1.' UESCAPE '!', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'E2 explicacion en un pendiente propio', 'esperado', 'RECHAZA · P0001 · no existe o no es de Truefie', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'E2 explicacion en un pendiente propio', 'esperado', 'RECHAZA · P0001 · no existe o no es de Truefie', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'no existe o no es de Truefie') > 0);
  end;
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tv, 'explicacion', U&'Qu!00E9 es: le falta el segundo renglon.' UESCAPE '!' || chr(10) || U&'Qu!00E9 har!00EDa falta: chico. Nada.' UESCAPE '!' || chr(10) || U&'Recomendaci!00F3n: HACER.' UESCAPE '!', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'E3 le falta un renglon', 'esperado', 'RECHAZA · 23514 · ticket_detalle_explicacion_forma"', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'E3 le falta un renglon', 'esperado', 'RECHAZA · 23514 · ticket_detalle_explicacion_forma"', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '23514' and strpos(sqlerrm, 'ticket_detalle_explicacion_forma"') > 0);
  end;
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tv, 'explicacion', U&'Qu!00E9 es: recomienda algo que no es de tres.' UESCAPE '!' || chr(10) || U&'Por qu!00E9 importa: posponer lo decide Andrea.' UESCAPE '!' || chr(10) || U&'Qu!00E9 har!00EDa falta: chico. Nada.' UESCAPE '!' || chr(10) || U&'Recomendaci!00F3n: POSPONER.' UESCAPE '!', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'E4 recomienda POSPONER', 'esperado', 'RECHAZA · 23514 · ticket_detalle_explicacion_recomienda"', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'E4 recomienda POSPONER', 'esperado', 'RECHAZA · 23514 · ticket_detalle_explicacion_recomienda"', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '23514' and strpos(sqlerrm, 'ticket_detalle_explicacion_recomienda"') > 0);
  end;
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tv, 'explicacion', U&'Qu!00E9 es: un tama!00F1o que no existe.' UESCAPE '!' || chr(10) || U&'Por qu!00E9 importa: el tama!00F1o es de tres.' UESCAPE '!' || chr(10) || U&'Qu!00E9 har!00EDa falta: enorme. Nada.' UESCAPE '!' || chr(10) || U&'Recomendaci!00F3n: HACER.' UESCAPE '!', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'E5 tamaño "enorme"', 'esperado', 'RECHAZA · 23514 · ticket_detalle_explicacion_tamano"', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'E5 tamaño "enorme"', 'esperado', 'RECHAZA · 23514 · ticket_detalle_explicacion_tamano"', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '23514' and strpos(sqlerrm, 'ticket_detalle_explicacion_tamano"') > 0);
  end;
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tv, 'espera', 'Espera de prueba del ensayo.', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'E6 truefie_cc escribe "espera"', 'esperado', 'RECHAZA · P0001 · lo define una socia', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'E6 truefie_cc escribe "espera"', 'esperado', 'RECHAZA · P0001 · lo define una socia', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'lo define una socia') > 0);
  end;
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tv, 'explicacion', U&'Qu!00E9 es: segunda prueba del ensayo.' UESCAPE '!' || chr(10) || U&'Por qu!00E9 importa: tiene que ganar la ultima.' UESCAPE '!' || chr(10) || U&'Qu!00E9 har!00EDa falta: grande. Nada, es un ensayo.' UESCAPE '!' || chr(10) || U&'Recomendaci!00F3n: DESCARTAR.' UESCAPE '!', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'E8a segunda explicacion (tiene que ganar esta)', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'E8a segunda explicacion (tiene que ganar esta)', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;

  -- ── E7 · anon ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tv, 'explicacion', U&'Qu!00E9 es: prueba del ensayo, no queda nada.' UESCAPE '!' || chr(10) || U&'Por qu!00E9 importa: prueba que el formato entra.' UESCAPE '!' || chr(10) || U&'Qu!00E9 har!00EDa falta: chico. Nada, es un ensayo.' UESCAPE '!' || chr(10) || U&'Recomendaci!00F3n: HACER, prioridad 1.' UESCAPE '!', 'anon');
    v_res := v_res || jsonb_build_object('p', 'E7 anon escribe una explicacion', 'esperado', 'RECHAZA · 42501 · permission denied for table ticket_detalle', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'E7 anon escribe una explicacion', 'esperado', 'RECHAZA · 42501 · permission denied for table ticket_detalle', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'permission denied for table ticket_detalle') > 0);
  end;

  -- ── E8–E9 · lo que se lee despues ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);
  select en_claro into v_t1 from v_ticket where id = v_tv;
  v_res := v_res || jsonb_build_object('p', 'E8 v_ticket.en_claro devuelve la ULTIMA', 'esperado', 'la segunda (DESCARTAR)', 'obtenido', coalesce(replace(v_t1, chr(10), ' / '), '(nada)'), 'ok', v_t1 = U&'Qu!00E9 es: segunda prueba del ensayo.' UESCAPE '!' || chr(10) || U&'Por qu!00E9 importa: tiene que ganar la ultima.' UESCAPE '!' || chr(10) || U&'Qu!00E9 har!00EDa falta: grande. Nada, es un ensayo.' UESCAPE '!' || chr(10) || U&'Recomendaci!00F3n: DESCARTAR.' UESCAPE '!');
  select count(*) filter (where que = 'En palabras claras'),
         count(*) filter (where que = 'Anuncio' and detalle in (U&'Qu!00E9 es: prueba del ensayo, no queda nada.' UESCAPE '!' || chr(10) || U&'Por qu!00E9 importa: prueba que el formato entra.' UESCAPE '!' || chr(10) || U&'Qu!00E9 har!00EDa falta: chico. Nada, es un ensayo.' UESCAPE '!' || chr(10) || U&'Recomendaci!00F3n: HACER, prioridad 1.' UESCAPE '!', U&'Qu!00E9 es: segunda prueba del ensayo.' UESCAPE '!' || chr(10) || U&'Por qu!00E9 importa: tiene que ganar la ultima.' UESCAPE '!' || chr(10) || U&'Qu!00E9 har!00EDa falta: grande. Nada, es un ensayo.' UESCAPE '!' || chr(10) || U&'Recomendaci!00F3n: DESCARTAR.' UESCAPE '!'))
    into v_x1, v_x2 from v_ticket_historial where ticket_id = v_tv;
  v_res := v_res || jsonb_build_object('p', 'E9 historial: «En palabras claras» · rotuladas «Anuncio»', 'esperado', '2 · 0', 'obtenido', v_x1 || ' · ' || v_x2, 'ok', v_x1 = 2 and v_x2 = 0);

  -- ── E10 · regresion: lo que ya andaba, sigue igual ──
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'truefie_cc', true);
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tv, 'anuncio', 'Anuncio de prueba del ensayo, no queda.', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'E10a truefie_cc: anuncio', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'E10a truefie_cc: anuncio', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tv, 'cierre', 'Cerrado en el ensayo: b73 (e75fa4c).', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'E10b truefie_cc: cierre', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'E10b truefie_cc: cierre', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tv, 'criterio', 'Criterio de prueba del ensayo.', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'E10c truefie_cc: "criterio"', 'esperado', 'RECHAZA · P0001 · lo define una socia', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'E10c truefie_cc: "criterio"', 'esperado', 'RECHAZA · P0001 · lo define una socia', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'lo define una socia') > 0);
  end;
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select en_claro into v_t2 from v_ticket where id = v_tv;
  v_res := v_res || jsonb_build_object('p', 'E10d la socia LEE en_claro (lo que va a pedir la pantalla)', 'esperado', 'la segunda', 'obtenido', coalesce(left(replace(v_t2, chr(10), ' / '), 60), '(nada)'), 'ok', v_t2 = U&'Qu!00E9 es: segunda prueba del ensayo.' UESCAPE '!' || chr(10) || U&'Por qu!00E9 importa: tiene que ganar la ultima.' UESCAPE '!' || chr(10) || U&'Qu!00E9 har!00EDa falta: grande. Nada, es un ensayo.' UESCAPE '!' || chr(10) || U&'Recomendaci!00F3n: DESCARTAR.' UESCAPE '!');
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tv, 'explicacion', U&'Qu!00E9 es: prueba del ensayo, no queda nada.' UESCAPE '!' || chr(10) || U&'Por qu!00E9 importa: prueba que el formato entra.' UESCAPE '!' || chr(10) || U&'Qu!00E9 har!00EDa falta: chico. Nada, es un ensayo.' UESCAPE '!' || chr(10) || U&'Recomendaci!00F3n: HACER, prioridad 1.' UESCAPE '!', v_socia);
    v_res := v_res || jsonb_build_object('p', 'E10e la socia escribe una explicacion desde la app', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'E10e la socia escribe una explicacion desde la app', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tv, 'explicacion', 'Texto libre, sin los cuatro renglones.', v_socia);
    v_res := v_res || jsonb_build_object('p', 'E10f la socia NO escribe con formato libre', 'esperado', 'RECHAZA · 23514 · violates check constraint "ticket_detalle_explicacion_', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'E10f la socia NO escribe con formato libre', 'esperado', 'RECHAZA · 23514 · violates check constraint "ticket_detalle_explicacion_', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '23514' and strpos(sqlerrm, 'violates check constraint "ticket_detalle_explicacion_') > 0);
  end;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tv, 'explicacion', U&'Qu!00E9 es: prueba del ensayo, no queda nada.' UESCAPE '!' || chr(10) || U&'Por qu!00E9 importa: prueba que el formato entra.' UESCAPE '!' || chr(10) || U&'Qu!00E9 har!00EDa falta: chico. Nada, es un ensayo.' UESCAPE '!' || chr(10) || U&'Recomendaci!00F3n: HACER, prioridad 1.' UESCAPE '!', 'cc-sql-ensayo');
    v_res := v_res || jsonb_build_object('p', 'E10g editor SQL (firma cc-sql): explicacion', 'esperado', 'ENTRA', 'obtenido', 'ENTRA', 'ok', true);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'E10g editor SQL (firma cc-sql): explicacion', 'esperado', 'ENTRA', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm, 'ok', false);
  end;
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tv, 'criterio', 'Criterio de prueba del ensayo.', 'cc-sql-ensayo');
    v_res := v_res || jsonb_build_object('p', 'E10h editor SQL: "criterio" sigue afuera', 'esperado', 'RECHAZA · P0001 · solo se escriben cierres, anuncios y explicaciones', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'E10h editor SQL: "criterio" sigue afuera', 'esperado', 'RECHAZA · P0001 · solo se escriben cierres, anuncios y explicaciones', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = 'P0001' and strpos(sqlerrm, 'solo se escriben cierres, anuncios y explicaciones') > 0);
  end;
  select contenido into v_t3 from v_ticket_export where id = v_tv;
  v_res := v_res || jsonb_build_object('p', 'E10i export: la seccion, antes del criterio', 'esperado', '## En palabras claras < ## Criterio de terminado', 'obtenido', strpos(v_t3, '## En palabras claras') || ' < ' || strpos(v_t3, '## Criterio de terminado'), 'ok', strpos(v_t3, '## En palabras claras') > 0 and strpos(v_t3, '## En palabras claras') < strpos(v_t3, '## Criterio de terminado'));
  select            (select count(*) from pg_constraint
             where conrelid = 'public.ticket_detalle'::regclass
               and conname in ('ticket_detalle_explicacion_forma','ticket_detalle_explicacion_tamano',
                               'ticket_detalle_explicacion_recomienda'))                      as formato_3,
           (select strpos(pg_get_constraintdef(oid), '''explicacion''') > 0
              from pg_constraint where conname = 'ticket_detalle_clase_ok')                   as clase_ok,
           (select strpos(pg_get_constraintdef(oid), U&'Qu!00E9 har!00EDa falta' UESCAPE '!') > 0
              from pg_constraint where conname = 'ticket_detalle_explicacion_forma')          as acentos_ok,
           (select (length(prosrc) - length(replace(prosrc, '''explicacion''', ''))) / length('''explicacion''')
              from pg_proc where oid = 'public.ticket_detalle_guard()'::regprocedure)         as guardia_2,
           (select strpos(with_check, 'explicacion') > 0
              from pg_policies where policyname = 'ticket_detalle_cc_ins')                    as politica,
           (select count(*) from information_schema.columns
             where table_schema = 'public' and table_name = 'v_ticket' and column_name = 'en_claro') as columna,
           (select count(*) from pg_class
             where relnamespace = 'public'::regnamespace
               and relname in ('v_ticket','v_ticket_historial','v_ticket_export')
               and reloptions @> array['security_invoker=true'])                              as invoker_3,
           (select strpos(pg_get_viewdef('public.v_ticket_historial'::regclass), 'En palabras claras') > 0) as historial,
           (select strpos(pg_get_viewdef('public.v_ticket_export'::regclass), U&'## Qu!00E9 pasa' UESCAPE '!') > 0
               and strpos(pg_get_viewdef('public.v_ticket_export'::regclass), '## En palabras claras') > 0) as export_ok,
           (select count(*) from information_schema.role_table_grants
             where grantee = 'anon'
               and table_name in ('v_ticket','v_ticket_historial','v_ticket_export'))          as anon_0
    into v_k1, v_k2, v_k3, v_k4, v_k5, v_k6, v_k7, v_k8, v_k9, v_k10;
  v_res := v_res || jsonb_build_object('p', 'E10j la fila de control del pegado', 'esperado', '3 · true · true · 2 · true · 1 · 3 · true · true · 0', 'obtenido', concat_ws(' · ', v_k1, v_k2, v_k3, v_k4, v_k5, v_k6, v_k7, v_k8, v_k9, v_k10), 'ok', concat_ws(' · ', v_k1, v_k2, v_k3, v_k4, v_k5, v_k6, v_k7, v_k8, v_k9, v_k10) = '3 · true · true · 2 · true · 1 · 3 · true · true · 0');

  -- ── E10k · LA RLS SOLA: se apaga el guardia (se vuelve a prender abajo) ──
  alter table ticket_detalle disable trigger ticket_detalle_guard_trg;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'truefie_cc', true);
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tv, 'espera', 'Espera de prueba del ensayo.', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'E10k sin guardia: truefie_cc escribe "espera"', 'esperado', 'RECHAZA · 42501 · new row violates row-level security policy for table "ticket_detalle"', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'E10k sin guardia: truefie_cc escribe "espera"', 'esperado', 'RECHAZA · 42501 · new row violates row-level security policy for table "ticket_detalle"', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'new row violates row-level security policy for table "ticket_detalle"') > 0);
  end;
  begin
    insert into ticket_detalle (ticket_id, clase, texto, creado_por) values (v_tp, 'explicacion', U&'Qu!00E9 es: prueba del ensayo, no queda nada.' UESCAPE '!' || chr(10) || U&'Por qu!00E9 importa: prueba que el formato entra.' UESCAPE '!' || chr(10) || U&'Qu!00E9 har!00EDa falta: chico. Nada, es un ensayo.' UESCAPE '!' || chr(10) || U&'Recomendaci!00F3n: HACER, prioridad 1.' UESCAPE '!', 'cc-truefie');
    v_res := v_res || jsonb_build_object('p', 'E10l sin guardia: explicacion en un propio', 'esperado', 'RECHAZA · 42501 · new row violates row-level security policy for table "ticket_detalle"', 'obtenido', 'ENTRA', 'ok', false);
  exception when others then
    v_res := v_res || jsonb_build_object('p', 'E10l sin guardia: explicacion en un propio', 'esperado', 'RECHAZA · 42501 · new row violates row-level security policy for table "ticket_detalle"', 'obtenido', 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm,
                                         'ok', sqlstate = '42501' and strpos(sqlerrm, 'new row violates row-level security policy for table "ticket_detalle"') > 0);
  end;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);
  alter table ticket_detalle enable trigger ticket_detalle_guard_trg;

  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('ensayo.res', v_res::text, true);
  perform set_config('ensayo.tickets', 'abierto T-' || v_tv || ' · propio T-' || v_tp, true);
end $$;


-- ── EL RESULTADO. Esta tabla ES el ensayo. ────────────────────────────────
-- ESPERADO: 23 filas, todas con ok = true.
select r.p as prueba, r.esperado, r.obtenido, r.ok
  from jsonb_to_recordset(current_setting('ensayo.res')::jsonb)
       as r(p text, esperado text, obtenido text, ok boolean)
union all
select 'Z · tickets usados', current_setting('ensayo.tickets'), '', true;

rollback;

-- ── DESPUES DEL ROLLBACK (opcional, con pg_lector) ────────────────────────
-- select count(*) from pg_constraint where conname like 'ticket_detalle_explicacion%';  -> 0
