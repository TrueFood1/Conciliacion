-- ════════════════════════════════════════════════════════════════════════
-- JUSTIFICANTES · SUPABASE STORAGE   (PEGADO 3 de 3)
-- PROPUESTA 13-ago-2026. **NO PEGAR TODAVÍA** — esto es el STOP de diseño.
-- Va DESPUÉS de ACCESOS_ESQUEMA.sql y PERSONAL_ESQUEMA.sql.
--
-- PIEZA NUEVA: es el PRIMER uso de archivos en Truefie. Hasta hoy el sistema
-- solo guardaba números y texto. Vale la pena decirlo porque cambia el respaldo,
-- el costo y la superficie de exposición: una foto de una nota médica es dato de
-- salud, y una vez subida vive en un servidor que no es de la empresa.
--
-- ⚠️ HAY UN PASO MANUAL DE ANDREA EN EL PANEL — está al final del archivo.
--
-- QUÉ GUARDA. La foto del justificante: nota médica, constancia del colegio,
-- orden del INS. La sube quien registra el permiso, desde el teléfono.
--
-- CÓMO SE ORGANIZA. Una carpeta por persona, con el ID de rrhh_persona:
--
--     justificantes/{persona_id}/{año}/{uuid}-{nombre-original}
--                    └─ ESTA carpeta es la que manda la seguridad
--
-- La primera carpeta NO es decorativa: las políticas de abajo comparan ese
-- número con el rrhh_persona del que sube. Es lo que impide que alguien suba
-- (o lea) en la carpeta de otro. Si algún día se cambia la forma de la ruta,
-- estas políticas se rompen en silencio — dejarían de proteger sin dar error.
--
-- POR QUÉ EL BUCKET ES PRIVADO. Un bucket público sirve cualquier archivo a
-- quien tenga la URL, sin login. Para fotos de notas médicas eso no se discute.
-- La app tiene que pedir una URL firmada y de vida corta cada vez que muestra
-- un justificante (`createSignedUrl`, minutos, no días).
-- ════════════════════════════════════════════════════════════════════════


-- ── 1 · EL BUCKET ───────────────────────────────────────────────────────
-- Si esto da error de permisos, se crea a mano desde el panel (ver el final).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'justificantes', 'justificantes',
  false,                                  -- PRIVADO. No cambiar.
  10485760,                               -- 10 MB: una foto de teléfono entra de sobra
  array['image/jpeg','image/png','image/heic','image/webp','application/pdf']
)
on conflict (id) do update
  set public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;


-- ── 2 · A QUÉ CARPETA PERTENECE QUIEN PREGUNTA ──────────────────────────
-- `storage.foldername(name)` devuelve el arreglo de carpetas de la ruta;
-- el [1] es la primera, o sea el persona_id.
create or replace function rrhh_es_mi_carpeta(ruta text) returns boolean
language sql stable security definer set search_path = public as $$
  select (storage.foldername(ruta))[1] = rrhh_mi_persona()::text;
$$;


-- ── 3 · POLÍTICAS ───────────────────────────────────────────────────────
-- Cada quien sube lo suyo; las socias ven todo. Nadie borra ni sobrescribe:
-- un justificante es prueba de algo que ya se aprobó, y el módulo entero es
-- append-only. Corregir = subir otro archivo y anular el evento.
drop policy if exists justif_ins on storage.objects;
drop policy if exists justif_sel on storage.objects;
drop policy if exists justif_upd on storage.objects;
drop policy if exists justif_del on storage.objects;

-- SUBIR: solo a la carpeta propia. La socia puede subir a cualquiera (registra
-- permisos de gente que no tiene login, o arregla una foto que salió movida).
create policy justif_ins on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'justificantes'
    and (acceso_es_socia() or rrhh_es_mi_carpeta(name))
  );

-- VER: la carpeta propia, o todo si es socia.
create policy justif_sel on storage.objects
  for select to authenticated
  using (
    bucket_id = 'justificantes'
    and (acceso_es_socia() or rrhh_es_mi_carpeta(name))
  );

-- Sin políticas de update ni delete, a propósito. Sin política, la operación
-- queda prohibida: no hay que escribir nada para negarla, y escribir una
-- política restrictiva de más sería fingir que hay una decisión donde lo que
-- hay es la ausencia de permiso.


-- ════════════════════════════════════════════════════════════════════════
-- ⚠️ LO QUE TIENE QUE HACER ANDREA EN EL PANEL DE SUPABASE
--
-- 1) Storage → Buckets. Si después de pegar esto NO aparece `justificantes`,
--    el insert del punto 1 no tuvo permisos: crealo a mano.
--        New bucket → nombre: justificantes
--        Public bucket: DESMARCADO  ← lo más importante de todo el archivo
--        File size limit: 10 MB
--        Allowed MIME types: image/jpeg, image/png, image/heic, image/webp,
--                            application/pdf
--    Y después volvé a pegar este archivo, para que queden las políticas.
--
-- 2) Comprobación, con el bucket ya creado:
--        select id, public, file_size_limit from storage.buckets
--         where id = 'justificantes';
--    `public` tiene que salir **false**. Si sale true, el bucket sirve las
--    fotos de las notas médicas a cualquiera que tenga la URL, sin login.
--
-- 3) Comprobación de las políticas:
--        select policyname from pg_policies
--         where tablename = 'objects' and policyname like 'justif%';
--    Tienen que salir DOS: justif_ins y justif_sel. Si sale alguna de update
--    o delete, sobra: borrala.
--
-- 4) Retención — decisión pendiente, no técnica. Una foto de una nota médica
--    es dato de salud y hoy no hay ninguna regla de por cuánto tiempo se
--    guarda. Cuando lo decidas se agrega el borrado por antigüedad (es lo
--    único del módulo que necesitaría permiso de delete, y por eso hoy no
--    existe).
-- ════════════════════════════════════════════════════════════════════════
