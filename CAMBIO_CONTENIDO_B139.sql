-- ═══════════════════════════════════════════════════════════════════════════
-- CAMBIO_CONTENIDO_B139.sql  ·  27-oct-2026  ·  Contenido b139: categorías del banco, documentos y miniaturas
-- ✅ APLICADO en producción por Andrea (27-oct), control 3·1·0·t·1·0·3·1·1; ensayo 37/37. Antes: ENSAYO_CONTENIDO_B139.sql (ensayo en seco, no deja nada). Después: la fila de
--    control de abajo tiene que salir EXACTA. Este header se toca DESPUÉS de verificar, nunca antes.
-- Va DESPUÉS de CONTENIDO.sql (aplicado el 27-oct). Para saber si está aplicado, mirar la base:
--   `select id, public from storage.buckets where id = 'contenido-miniaturas'`.
--
-- QUÉ HACE
--   1 · contenido_banco.tipo admite 'documento' además de 'foto' y 'video' (los certificados son PDF).
--   2 · contenido_banco.categoria pasa a las 12 categorías de b139, en tres grupos:
--         Producto        producto · empaque · tabla_nutricional
--         Para historias  desayunos · almuerzos_cenas · meriendas · nosotras · planta · en_tienda
--         Marca           certificaciones · logos_supermercados · marca
--       Lo que ya está cargado se MUEVE antes de poner el CHECK nuevo:
--         fabrica → planta · punto_de_venta → en_tienda · otro → marca (hoy no hay ninguna fila en
--         'otro'; la regla queda para que el CHECK no reviente si alguien cargó una desde la pantalla).
--       Lo que pide criterio fila por fila (qué gráfico es de marca y no de tienda) NO va acá: va en
--       PEGADO_CONTENIDO_B139_DATOS.sql, fuera de git.
--       El UPDATE dispara contenido_banco_editado (editado_en = now()); editado_por queda como estaba.
--   3 · Bucket PRIVADO `contenido-miniaturas`: una miniatura JPEG por archivo del banco, en
--       `<drive_id>.jpg` (la arma la pantalla: máx. 480 px). Hasta hoy la miniatura salía de Drive y
--       solo llegaba si el archivo estaba compartido por enlace.
--       QUIÉN: la MISMA llave que las tablas de CONTENIDO.sql, `acceso_es_socia()`, para subir, leer y
--       reemplazar. anon: nada (ni listar). equipo: nada. Nadie borra (sin política de delete, y además
--       storage.protect_delete frena el borrado directo). El asistente VE, igual que en las tablas: lo
--       da su política automática `asistente_ve_archivos` sobre storage.objects, que ya existe; no
--       sube ni reemplaza (asistente_no_inserta / asistente_no_actualiza, restrictivas).
--       La ruta se valida en la base (`^[A-Za-z0-9_-]{20,80}\.jpg$`, el mismo patrón del drive_id):
--       sin carpetas ni otra extensión. Tamaño (1 MB) y tipo (image/jpeg) los frena el bucket.
--       Reemplazar = subir con upsert: por eso hay política de UPDATE (y la de SELECT, que el upsert
--       necesita para ver la fila que pisa).
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$ begin
  if to_regclass('public.contenido_banco') is null then
    raise exception 'falta CONTENIDO.sql: pegarlo primero';
  end if;
  if exists (select 1 from storage.buckets where id = 'contenido-miniaturas') then
    raise exception 'el bucket contenido-miniaturas ya existe: este archivo no se vuelve a pegar';
  end if;
end $$;
-- cuántas filas había: el control de abajo exige las mismas (la migración mueve, no borra ni agrega)
select set_config('b139.filas_antes', (select count(*) from public.contenido_banco)::text, true);

-- ── 1 · tipo: también documento ───────────────────────────────────────────
alter table public.contenido_banco drop constraint contenido_banco_tipo_check;
alter table public.contenido_banco add constraint contenido_banco_tipo_check
  check (tipo in ('foto', 'video', 'documento'));

-- ── 2 · categorías: mover lo viejo y después cerrar con el CHECK nuevo ─────
alter table public.contenido_banco drop constraint contenido_banco_categoria_check;
update public.contenido_banco set categoria = case categoria
         when 'fabrica'        then 'planta'
         when 'punto_de_venta' then 'en_tienda'
         when 'otro'           then 'marca' end
 where categoria in ('fabrica', 'punto_de_venta', 'otro');
alter table public.contenido_banco add constraint contenido_banco_categoria_check
  check (categoria in ('producto', 'empaque', 'tabla_nutricional',
                       'desayunos', 'almuerzos_cenas', 'meriendas', 'nosotras', 'planta', 'en_tienda',
                       'certificaciones', 'logos_supermercados', 'marca'));

-- ── 3 · el bucket de miniaturas ─────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('contenido-miniaturas', 'contenido-miniaturas',
        false,                       -- PRIVADO. No cambiar: la pantalla pide URLs firmadas.
        1048576,                     -- 1 MB: una miniatura de 480 px pesa ~40–80 KB
        array['image/jpeg']);

create policy contenido_min_ins on storage.objects
  for insert to authenticated
  with check (bucket_id = 'contenido-miniaturas' and acceso_es_socia()
              and name ~ '^[A-Za-z0-9_-]{20,80}\.jpg$');
create policy contenido_min_sel on storage.objects
  for select to authenticated
  using (bucket_id = 'contenido-miniaturas' and acceso_es_socia());
create policy contenido_min_upd on storage.objects
  for update to authenticated
  using (bucket_id = 'contenido-miniaturas' and acceso_es_socia())
  with check (bucket_id = 'contenido-miniaturas' and acceso_es_socia()
              and name ~ '^[A-Za-z0-9_-]{20,80}\.jpg$');

-- Control: 3 · 1 · 0 · t · 1 · 0 · 3 · 1 · 1
--   tipo admite documento (CHECK nuevo) · bucket privado · filas con categoría vieja ·
--   mismas filas que antes · CHECK de categoría nuevo (con en_tienda y sin fabrica) ·
--   filas fuera de las 12 categorías · políticas contenido_min_* · tamaño máximo 1 MB · solo image/jpeg
select (select count(*) from pg_constraint where conrelid = 'public.contenido_banco'::regclass
           and conname = 'contenido_banco_tipo_check'
           and pg_get_constraintdef(oid) like '%documento%')
     + (select count(*) from pg_constraint where conrelid = 'public.contenido_banco'::regclass
           and conname in ('contenido_banco_tipo_check', 'contenido_banco_categoria_check')) as checks,
       (select count(*) from storage.buckets where id = 'contenido-miniaturas' and not public) as bucket_privado,
       (select count(*) from public.contenido_banco where categoria in ('fabrica', 'punto_de_venta', 'otro')) as categoria_vieja,
       (select count(*) from public.contenido_banco) = current_setting('b139.filas_antes')::bigint as mismas_filas,
       (select count(*) from pg_constraint where conrelid = 'public.contenido_banco'::regclass
           and conname = 'contenido_banco_categoria_check'
           and pg_get_constraintdef(oid) like '%en_tienda%' and pg_get_constraintdef(oid) not like '%fabrica%') as check_categoria,
       (select count(*) from public.contenido_banco where categoria not in ('producto', 'empaque', 'tabla_nutricional',
           'desayunos', 'almuerzos_cenas', 'meriendas', 'nosotras', 'planta', 'en_tienda',
           'certificaciones', 'logos_supermercados', 'marca')) as fuera_de_lista,
       (select count(*) from pg_policy where polrelid = 'storage.objects'::regclass
           and polname in ('contenido_min_ins', 'contenido_min_sel', 'contenido_min_upd')) as politicas,
       (select count(*) from storage.buckets where id = 'contenido-miniaturas' and file_size_limit = 1048576) as limite,
       (select count(*) from storage.buckets where id = 'contenido-miniaturas' and allowed_mime_types = array['image/jpeg']) as mime;
commit;
