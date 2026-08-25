-- ════════════════════════════════════════════════════════════════════════
-- JUSTIFICANTES Y AGUINALDOS · SUPABASE STORAGE   (PEGADO 3 de 3)
-- PROPUESTA 13-ago-2026. AMPLIADO 19-ago-2026 con el bucket `aguinaldos`.
-- ✅ APROBADO POR ANDREA 24-ago-2026 — se levanta el STOP de diseño.
-- Va DESPUÉS de ACCESOS_ESQUEMA.sql y PERSONAL_ESQUEMA.sql.
--
-- SON DOS BUCKETS, NO UNO, y la razón no es de orden sino de permisos:
--   · `justificantes` — el empleado lee SU carpeta. Dato de salud.
--   · `aguinaldos`    — solo socias, ni siquiera lo propio. Dato salarial.
-- Meter el documento del aguinaldo dentro de `justificantes` habría alcanzado
-- para organizarlo, pero la política de ese bucket deja al empleado leer su
-- carpeta entera: le abriría su propio cálculo de aguinaldo, y con él el
-- salario promedio del período. Reglas de acceso distintas = buckets distintos.
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


-- ── 4 · EL BUCKET DE AGUINALDOS ─────────────────────────────────────────
-- QUÉ GUARDA. El documento de respaldo del cálculo del aguinaldo: la hoja de la
-- contadora, el comprobante, lo que sea que justifique el monto que la socia
-- transcribe en `rrhh_aguinaldo`. Es el papel que explica el número.
--
-- MISMA FORMA DE RUTA que justificantes, para no tener dos convenciones:
--
--     aguinaldos/{persona_id}/{año}/{uuid}-{nombre-original}
--
-- Acá la primera carpeta NO es la que manda la seguridad —solo socias entran al
-- bucket entero, así que la carpeta es organización, no llave—. Se mantiene
-- igual de todos modos: el día que alguien decida mostrarle a cada quien su
-- propio aguinaldo, la política se escribe con `rrhh_es_mi_carpeta(name)` y ya
-- está, sin migrar archivos.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'aguinaldos', 'aguinaldos',
  false,                                  -- PRIVADO. No cambiar.
  10485760,                               -- 10 MB
  array['image/jpeg','image/png','image/heic','image/webp','application/pdf']
)
on conflict (id) do update
  set public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists aguin_ins on storage.objects;
drop policy if exists aguin_sel on storage.objects;
drop policy if exists aguin_upd on storage.objects;
drop policy if exists aguin_del on storage.objects;

-- SUBIR y VER: solo socias. Es la misma llave que `rrhh_aguinaldo` en el pegado
-- 2 — si acá quedara más abierto que la tabla, el documento contaría lo que la
-- tabla esconde.
create policy aguin_ins on storage.objects
  for insert to authenticated
  with check (bucket_id = 'aguinaldos' and acceso_es_socia());

create policy aguin_sel on storage.objects
  for select to authenticated
  using (bucket_id = 'aguinaldos' and acceso_es_socia());

-- Sin update ni delete, por la misma razón que arriba: append-only. Un monto
-- mal transcrito se corrige subiendo otro documento e insertando otra fila en
-- `rrhh_aguinaldo` — la vista `v_rrhh_aguinaldo` se queda con la última.


-- ════════════════════════════════════════════════════════════════════════
-- ⚠️ LO QUE TIENE QUE HACER ANDREA EN EL PANEL DE SUPABASE
--
-- 1) Storage → Buckets. Son DOS: `justificantes` y `aguinaldos`. Si después de
--    pegar esto falta alguno, el insert no tuvo permisos: creá a mano el que
--    falte, los dos con la misma configuración.
--        New bucket → nombre: justificantes   (y otro: aguinaldos)
--        Public bucket: DESMARCADO  ← lo más importante de todo el archivo
--        File size limit: 10 MB
--        Allowed MIME types: image/jpeg, image/png, image/heic, image/webp,
--                            application/pdf
--    Y después volvé a pegar este archivo, para que queden las políticas.
--
-- 2) Comprobación, con los buckets ya creados:
--        select id, public, file_size_limit from storage.buckets
--         where id in ('justificantes','aguinaldos');
--    Tienen que salir DOS filas y `public` tiene que salir **false** en las dos.
--    Si sale true, el bucket sirve las fotos de las notas médicas —o la hoja de
--    salarios del aguinaldo— a cualquiera que tenga la URL, sin login.
--
-- 3) Comprobación de las políticas:
--        select policyname from pg_policies
--         where tablename = 'objects'
--           and (policyname like 'justif%' or policyname like 'aguin%');
--    Tienen que salir CUATRO: justif_ins, justif_sel, aguin_ins y aguin_sel.
--    Si sale alguna de update o delete, sobra: borrala.
--
-- 4) Retención — decisión pendiente, no técnica. Una foto de una nota médica
--    es dato de salud y hoy no hay ninguna regla de por cuánto tiempo se
--    guarda. Cuando lo decidas se agrega el borrado por antigüedad (es lo
--    único del módulo que necesitaría permiso de delete, y por eso hoy no
--    existe).
-- ════════════════════════════════════════════════════════════════════════
