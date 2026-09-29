-- ═══════════════════════════════════════════════════════════════════════════
-- TICKETS_EXPLICACION.sql  ·  29-sep-2026  ·  ⛔ NO SE CORRIO TODAVIA
-- Un tipo de detalle nuevo: 'explicacion' — «En palabras claras»
--
-- ⚠️ Este encabezado se cambia DESPUES de ver la fila de control, nunca antes
--    (CLAUDE.md, 16-sep). Mientras diga NO SE CORRIO, no se afirma lo contrario
--    en ningun otro lado.
--
-- POR QUE (decision de Andrea, 29-sep-2026)
--   Cada ticket abierto de Truefie lleva una explicacion para Andrea, que no es
--   tecnica, en CUATRO renglones fijos:
--       Qué es: …
--       Por qué importa: …
--       Qué haría falta: chico | mediano | grande. …
--       Recomendación: HACER | CERRAR | DESCARTAR. …
--   No va como 'anuncio': el anuncio es BITACORA (se muestran todos, y hoy se
--   usa para la procedencia). La explicacion es DEFINICION: se reescribe cuando
--   el ticket cambia y vale LA ULTIMA, igual que 'espera' y 'criterio'.
--
-- QUIEN LA ESCRIBE
--   truefie_cc (firma 'cc-truefie'), el editor SQL (firma 'cc-sql…') y las
--   socias desde la app. El FORMATO lo hace cumplir la TABLA (tres CHECK), no
--   el que escribe: vale igual para los tres caminos, y para el revisor diario
--   si algun dia existe.
--
-- QUE CAMBIA (y nada mas)
--   §1  ticket_detalle: la clase nueva + 3 CHECK de formato.
--   §2  ticket_detalle_guard(): 'explicacion' en los dos caminos que filtran
--       clase (truefie_cc y editor SQL). El resto, BYTE A BYTE el vivo del 29-sep.
--   §3  la politica ticket_detalle_cc_ins de truefie_cc: suma la clase.
--   §4  v_ticket: columna `en_claro` AL FINAL (5 vistas dependen de esta; una
--       columna en el medio haria fallar el replace).
--   §5  v_ticket_historial: la etiqueta. SIN ESTO el ELSE la rotula «Anuncio»
--       en silencio.
--   §6  v_ticket_export: la seccion «## En palabras claras», despues de «Qué pasa».
--
-- ⚠️ LAS TRES VISTAS SE REEMPLAZAN CON `with (security_invoker = true)` ESCRITO.
--    `create or replace view` SIN la clausula WITH reemplaza las opciones por
--    NINGUNA: la vista volveria a leer con los permisos de su dueño, que es la
--    fuga que se cerro el 27-sep. La fila de control lo mide (invoker_3).
--
-- ⚠️ LOS ACENTOS DE LOS CHECK VAN COMO CODIGOS (U&'…' UESCAPE '!'). El
--    portapapeles sin UTF-8 cambia «é» por otra cosa (21-sep); si pasara, el
--    CHECK exigiria un texto que nadie escribe y rechazaria TODO. Con codigos,
--    la regla sobrevive al viaje. La fila de control mide igual que llego bien
--    (acentos_ok) y que las vistas trajeron sus acentos (export_ok).
--
-- ORDEN: primero este pegado; DESPUES publicar b74. b74 pide `en_claro` en el
-- select de la lista: publicado antes, la lista de Tickets no carga.
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


-- 🔴 LA PRUEBA DE QUE ENTRO, ADENTRO DE LA TRANSACCION.
-- ESPERADO: 3 · t · t · 2 · t · 1 · 3 · t · t · 0
select
  (select count(*) from pg_constraint
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
      and table_name in ('v_ticket','v_ticket_historial','v_ticket_export'))          as anon_0;

commit;
