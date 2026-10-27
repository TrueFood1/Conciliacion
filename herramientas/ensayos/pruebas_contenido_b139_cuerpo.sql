do $$
declare
  v_socia text; v_equipo text; v_asis text; v_n int; v_esp int; r record; v_ok boolean; v_obt text;
  v_res jsonb := '[]'::jsonb;
  -- ids de Drive INVENTADOS para el ensayo (nunca uno real: este archivo va al repo público)
  v_mini constant text := '1EnsayoB139MiniaturaSocia0000aa';
  -- %1$L categoria · %2$L tipo · %3$L creado_por · %4$L drive_id
  insb constant text := 'insert into public.contenido_banco (drive_id, nombre, tipo, categoria, creado_por) '
    'values (%4$L, ''certificado-gf.pdf'', %2$L, %1$L, %3$L)';
  -- %1$L nombre del objeto
  inso constant text := 'insert into storage.objects (bucket_id, name, metadata) '
    'values (''contenido-miniaturas'', %1$L, ''{"mimetype":"image/jpeg","size":48000}''::jsonb)';
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by id limit 1;
  select email into v_equipo from v_acceso_usuario where perfil not in ('socias', 'asistente') and activo order by id limit 1;
  select email into v_asis   from v_acceso_usuario where perfil = 'asistente' and activo order by id limit 1;
  if v_socia is null or v_equipo is null then
    raise exception 'el ensayo necesita una socia y alguien de equipo (socia %, equipo %)', v_socia, v_equipo;
  end if;

  -- ── la migración (las 3 filas viejas las sembró el bloque de antes del DDL) ──
  select count(*) into v_n from public.contenido_banco where drive_id = '1EnsayoB139Fabrica000000000000aa' and categoria = 'planta';
  v_res := v_res || jsonb_build_object('p', 'M1 fabrica → planta', 'esperado', '1', 'obtenido', v_n::text, 'ok', v_n = 1);
  select count(*) into v_n from public.contenido_banco where drive_id = '1EnsayoB139PuntoVenta0000000000aa' and categoria = 'en_tienda';
  v_res := v_res || jsonb_build_object('p', 'M2 punto_de_venta → en_tienda', 'esperado', '1', 'obtenido', v_n::text, 'ok', v_n = 1);
  select count(*) into v_n from public.contenido_banco where drive_id = '1EnsayoB139Otro0000000000000000aa' and categoria = 'marca';
  v_res := v_res || jsonb_build_object('p', 'M3 otro → marca', 'esperado', '1', 'obtenido', v_n::text, 'ok', v_n = 1);
  select count(*) into v_n from public.contenido_banco where categoria in ('fabrica', 'punto_de_venta', 'otro');
  v_res := v_res || jsonb_build_object('p', 'M4 ninguna fila queda con categoría vieja', 'esperado', '0', 'obtenido', v_n::text, 'ok', v_n = 0);
  select count(*) into v_n from public.contenido_banco where drive_id like '1EnsayoB139%' and editado_en is not null;
  v_res := v_res || jsonb_build_object('p', 'M5 la base pone editado_en a las 3 movidas', 'esperado', '3', 'obtenido', v_n::text, 'ok', v_n = 3);
  select count(*) into v_n from public.contenido_banco;
  v_res := v_res || jsonb_build_object('p', 'M6 mismas filas que antes de migrar', 'esperado', current_setting('b139.filas_antes'),
                                       'obtenido', v_n::text, 'ok', v_n = current_setting('b139.filas_antes')::int);

  -- un objeto que no es de la socia de turno: la miniatura de la «otra» fila, como dueño de la tabla
  execute format(inso, '1EnsayoB139MiniaturaPrevia00000aa.jpg');

  for r in
    select * from (values
      -- socia: categorías y tipos nuevos
      (1,  'K1 socia agrega un PDF en certificaciones',                       'authenticated', v_socia,
           format(insb, 'certificaciones', 'documento', v_socia, '1EnsayoB139Certificado0000000aa'), null),
      (2,  'K2 socia agrega una foto en desayunos',                           'authenticated', v_socia,
           format(insb, 'desayunos', 'foto', v_socia, '1EnsayoB139Desayuno00000000000aa'), null),
      (3,  'K3 categoría vieja (fabrica) ya no entra',                        'authenticated', v_socia,
           format(insb, 'fabrica', 'foto', v_socia, '1EnsayoB139Vieja0000000000000aa'), '23514'),
      (4,  'K4 categoría inventada',                                          'authenticated', v_socia,
           format(insb, 'memes', 'foto', v_socia, '1EnsayoB139Memes0000000000000aa'), '23514'),
      (5,  'K5 tipo inventado (audio)',                                       'authenticated', v_socia,
           format(insb, 'marca', 'audio', v_socia, '1EnsayoB139Audio0000000000000aa'), '23514'),
      (6,  'K6 socia recategoriza a logos_supermercados',                     'authenticated', v_socia,
           format('update public.contenido_banco set categoria = ''logos_supermercados'', editado_por = %L '
                  'where drive_id = ''1EnsayoB139PuntoVenta0000000000aa''', v_socia), null),
      (7,  'K7 socia recategoriza a otro (ya no existe)',                     'authenticated', v_socia,
           format('update public.contenido_banco set categoria = ''otro'', editado_por = %L '
                  'where drive_id = ''1EnsayoB139Fabrica000000000000aa''', v_socia), '23514'),
      -- storage: subir
      (10, 'B1 socia sube la miniatura <drive_id>.jpg',                       'authenticated', v_socia,
           format(inso, v_mini || '.jpg'), null),
      (11, 'B2 socia sube dentro de una carpeta',                             'authenticated', v_socia,
           format(inso, 'otra/' || v_mini || '.jpg'), '42501'),
      (12, 'B3 socia sube otra extensión (.png)',                             'authenticated', v_socia,
           format(inso, v_mini || '.png'), '42501'),
      (13, 'B4 socia sube con un nombre que no es id de Drive',               'authenticated', v_socia,
           format(inso, '../../x.jpg'), '42501'),
      (14, 'B5 equipo sube una miniatura',                                    'authenticated', v_equipo,
           format(inso, '1EnsayoB139MiniaturaEquipo000aa.jpg'), '42501'),
      (15, 'B6 anon sube una miniatura',                                      'anon', null,
           format(inso, '1EnsayoB139MiniaturaAnon00000aa.jpg'), '42501'),
      -- storage: reemplazar (upsert = update) y borrar
      (20, 'B7 socia reemplaza su miniatura',                                 'authenticated', v_socia,
           format('update storage.objects set metadata = ''{"mimetype":"image/jpeg","size":51000}''::jsonb '
                  'where bucket_id = ''contenido-miniaturas'' and name = %L', v_mini || '.jpg'), null),
      (21, 'B8 socia renombra la miniatura a una carpeta',                    'authenticated', v_socia,
           format('update storage.objects set name = ''x/'' || name where bucket_id = ''contenido-miniaturas'' and name = %L',
                  v_mini || '.jpg'), '42501'),
      (22, 'B9 socia BORRA una miniatura',                                    'authenticated', v_socia,
           format('delete from storage.objects where bucket_id = ''contenido-miniaturas'' and name = %L', v_mini || '.jpg'), '42501'),
      (23, 'B10 anon BORRA una miniatura',                                    'anon', null,
           'delete from storage.objects where bucket_id = ''contenido-miniaturas''', '42501')
    ) v(n, p, rol, email, q, esp)
    order by n
  loop
    perform set_config('request.jwt.claims',
                       case when r.email is null then '' else json_build_object('email', r.email, 'role', 'authenticated')::text end, true);
    perform set_config('role', r.rol, true);
    begin
      execute r.q;
      v_obt := 'ENTRA'; v_ok := r.esp is null;
    exception when others then
      v_obt := 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm; v_ok := r.esp is not null and sqlstate = r.esp;
    end;
    perform set_config('role', 'postgres', true);
    v_res := v_res || jsonb_build_object('p', r.p, 'esperado', coalesce('RECHAZA · ' || r.esp, 'ENTRA'), 'obtenido', v_obt, 'ok', v_ok);
  end loop;

  -- los UPDATE que la RLS filtra no dan error: dan 0 filas. Se mira el resultado, no el código.
  select count(*) into v_n from public.contenido_banco where drive_id = '1EnsayoB139PuntoVenta0000000000aa' and categoria = 'logos_supermercados';
  v_res := v_res || jsonb_build_object('p', 'K6b la recategorización quedó', 'esperado', '1', 'obtenido', v_n::text, 'ok', v_n = 1);
  select count(*) into v_n from storage.objects where bucket_id = 'contenido-miniaturas' and name = v_mini || '.jpg'
     and metadata ->> 'size' = '51000';
  v_res := v_res || jsonb_build_object('p', 'B7b el reemplazo quedó', 'esperado', '1', 'obtenido', v_n::text, 'ok', v_n = 1);

  -- equipo y anon intentan reemplazar: 0 filas tocadas
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  update storage.objects set metadata = '{"de":"equipo"}'::jsonb where bucket_id = 'contenido-miniaturas';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
  update storage.objects set metadata = '{"de":"anon"}'::jsonb where bucket_id = 'contenido-miniaturas';
  perform set_config('role', 'postgres', true);
  select count(*) into v_n from storage.objects where bucket_id = 'contenido-miniaturas' and metadata ? 'de';
  v_res := v_res || jsonb_build_object('p', 'B11 el UPDATE de equipo y de anon no tocó ninguna miniatura', 'esperado', '0', 'obtenido', v_n::text, 'ok', v_n = 0);
  select count(*) into v_n from storage.objects where bucket_id = 'contenido-miniaturas';
  v_res := v_res || jsonb_build_object('p', 'B12 quedan las 2 miniaturas (nadie borró)', 'esperado', '2', 'obtenido', v_n::text, 'ok', v_n = 2);

  -- leer: la socia ve las 2 (la suya y la previa); equipo y anon, nada
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_n from storage.objects where bucket_id = 'contenido-miniaturas';
  perform set_config('role', 'postgres', true);
  v_res := v_res || jsonb_build_object('p', 'R1 socia lee las miniaturas del bucket', 'esperado', '2', 'obtenido', v_n::text, 'ok', v_n = 2);
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_n from storage.objects where bucket_id = 'contenido-miniaturas';
  perform set_config('role', 'postgres', true);
  v_res := v_res || jsonb_build_object('p', 'R2 equipo no ve ninguna miniatura', 'esperado', '0', 'obtenido', v_n::text, 'ok', v_n = 0);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
  begin
    select count(*) into v_n from storage.objects where bucket_id = 'contenido-miniaturas';
    v_obt := v_n::text; v_ok := v_n = 0;
  exception when others then
    v_obt := 'RECHAZA: ' || sqlstate; v_ok := sqlstate = '42501';
  end;
  perform set_config('role', 'postgres', true);
  v_res := v_res || jsonb_build_object('p', 'R3 anon lista el bucket', 'esperado', '0 (o RECHAZA · 42501)', 'obtenido', v_obt, 'ok', v_ok);
  perform set_config('role', 'anon', true);
  begin
    select count(*) into v_n from storage.buckets where id = 'contenido-miniaturas';
    v_obt := v_n::text; v_ok := v_n = 0;
  exception when others then
    v_obt := 'RECHAZA: ' || sqlstate; v_ok := sqlstate = '42501';
  end;
  perform set_config('role', 'postgres', true);
  v_res := v_res || jsonb_build_object('p', 'R4 anon ve el bucket en storage.buckets', 'esperado', '0 (o RECHAZA · 42501)', 'obtenido', v_obt, 'ok', v_ok);

  -- asistente: ve si está encendido (asistente_ve_archivos, como en las tablas), nunca sube
  if v_asis is not null then
    v_esp := case when asistente_encendido() then 2 else 0 end;
    perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    select count(*) into v_n from storage.objects where bucket_id = 'contenido-miniaturas';
    begin
      execute format(inso, '1EnsayoB139MiniaturaAsis00000aa.jpg');
      v_obt := 'ENTRA'; v_ok := false;
    exception when others then
      v_obt := 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm; v_ok := sqlstate = '42501';
    end;
    perform set_config('role', 'postgres', true);
    v_res := v_res || jsonb_build_object('p', 'I1 el asistente lee (2 si está encendido, 0 si no)', 'esperado', v_esp::text, 'obtenido', v_n::text, 'ok', v_n = v_esp);
    v_res := v_res || jsonb_build_object('p', 'I2 el asistente sube una miniatura', 'esperado', 'RECHAZA · 42501', 'obtenido', v_obt, 'ok', v_ok);
  end if;

  -- catálogo
  select count(*) into v_n from storage.buckets where id = 'contenido-miniaturas' and not public;
  v_res := v_res || jsonb_build_object('p', 'C1 el bucket es privado', 'esperado', '1', 'obtenido', v_n::text, 'ok', v_n = 1);
  select count(*) into v_n from pg_policy where polrelid = 'storage.objects'::regclass and polname like 'contenido\_min\_%'
     and polroles = array['authenticated'::regrole]::oid[];
  v_res := v_res || jsonb_build_object('p', 'C2 3 políticas contenido_min_*, solo para authenticated', 'esperado', '3', 'obtenido', v_n::text, 'ok', v_n = 3);
  select count(*) into v_n from pg_policy where polrelid = 'storage.objects'::regclass and polcmd = 'd'
     and pg_get_expr(polqual, polrelid) like '%contenido-miniaturas%';
  v_res := v_res || jsonb_build_object('p', 'C3 ninguna política de borrado sobre el bucket', 'esperado', '0', 'obtenido', v_n::text, 'ok', v_n = 0);
  select count(*) into v_n from pg_constraint where conrelid = 'public.contenido_banco'::regclass
     and conname in ('contenido_banco_tipo_check', 'contenido_banco_categoria_check');
  v_res := v_res || jsonb_build_object('p', 'C4 los 2 CHECK nuevos con su nombre de siempre', 'esperado', '2', 'obtenido', v_n::text, 'ok', v_n = 2);

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
