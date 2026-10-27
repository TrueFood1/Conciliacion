do $$
declare
  v_socia text; v_socia2 text; v_equipo text; v_asis text; v_n int; r record; v_ok boolean; v_obt text;
  v_post bigint; v_res jsonb := '[]'::jsonb;
  -- %1$L creado_por · %2$L enlace_vista
  insp constant text := 'insert into public.contenido_post (titulo, fecha_planeada, formato, pilar, producto_id, texto, '
    'enlace_vista, creado_por) values (''Cookie Dough del congelador al horno'', date ''2026-10-30'', ''carrusel'', '
    '''recetas'', 519, ''17 minutos y sale como recién hecho'', %2$L, %1$L)';
  -- %1$s post · %2$L estado · %3$L fallas · %4$s vistas · %5$L creado_por
  inse constant text := 'insert into public.contenido_post_estado (post_id, estado, fallas, fallas_vistas, checklist, huella, creado_por) '
    'values (%1$s, %2$L, %3$L::jsonb, %4$s, ''["engancha","datos"]''::jsonb, ''a1b2c3d4'', %5$L)';
  -- %1$s post · %2$L momento · %3$s vistas · %4$L creado_por
  insm constant text := 'insert into public.contenido_metrica (post_id, momento, leido_en, vistas, me_gusta, respuestas, clics_enlace, creado_por) '
    'values (%1$s, %2$L, timestamptz ''2026-10-26 20:00-06'', %3$s, 5, 1, 0, %4$L)';
  -- %1$L drive_id · %2$L creado_por
  insb constant text := 'insert into public.contenido_banco (drive_id, nombre, tipo, categoria, producto_id, creado_por) '
    'values (%1$L, ''IMG_5507.HEIC'', ''foto'', ''producto'', 451, %2$L)';
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by id limit 1;
  select email into v_socia2 from v_acceso_usuario where perfil = 'socias' and activo and email <> v_socia order by id limit 1;
  select email into v_equipo from v_acceso_usuario where perfil not in ('socias', 'asistente') and activo order by id limit 1;
  select email into v_asis   from v_acceso_usuario where perfil = 'asistente' and activo order by id limit 1;
  if v_socia is null or v_equipo is null then
    raise exception 'el ensayo necesita una socia y alguien de equipo (socia %, equipo %)', v_socia, v_equipo;
  end if;

  -- un post de base, como dueño de la tabla, para colgarle estados y métricas
  insert into public.contenido_post (titulo, formato, creado_por) values ('post de base del ensayo', 'historia', 'ensayo')
    returning id into v_post;

  for r in
    select * from (values
      -- socia
      (1,  'S1 socia crea un post con SU nombre',                             'authenticated', v_socia,
           format(insp, v_socia, 'https://claude.ai/artifact/4DABEH5LSVFZK67GX1QHQf'), null),
      (2,  'S2 socia crea un post firmado por OTRA persona',                  'authenticated', v_socia,
           format(insp, 'otra@persona.com', null), '42501'),
      (3,  'S3 enlace javascript: (se pinta como enlace)',                    'authenticated', v_socia,
           format(insp, v_socia, 'javascript:alert(1)'), '23514'),
      (4,  'S4 enlace con comillas (rompería el atributo)',                   'authenticated', v_socia,
           format(insp, v_socia, 'https://x.com/"onmouseover=alert(1)'), '23514'),
      (5,  'S5 socia pasa el post a borrador',                                'authenticated', v_socia,
           format(inse, v_post, 'borrador', '[]', 'false', v_socia), null),
      (6,  'S6 APROBADO con fallas y SIN decir que se vieron',                'authenticated', v_socia,
           format(inse, v_post, 'aprobado', '["agua"]', 'false', v_socia), '23514'),
      (7,  'S7 aprobado con fallas que SÍ se vieron',                         'authenticated', v_socia,
           format(inse, v_post, 'aprobado', '["agua"]', 'true', v_socia), null),
      (8,  'S8 aprobado sin fallas',                                          'authenticated', v_socia,
           format(inse, v_post, 'aprobado', '[]', 'false', v_socia), null),
      (9,  'S9 estado inventado',                                             'authenticated', v_socia,
           format(inse, v_post, 'viral', '[]', 'false', v_socia), '23514'),
      (10, 'S10 socia anota una lectura 24 h',                                'authenticated', v_socia,
           format(insm, v_post, '24h', 623, v_socia), null),
      (11, 'S11 segunda lectura 24 h (gana la última)',                       'authenticated', v_socia,
           format(insm, v_post, '24h', 700, v_socia), null),
      (12, 'S12 vistas negativas',                                            'authenticated', v_socia,
           format(insm, v_post, '7d', -1, v_socia), '23514'),
      (13, 'S13 momento inventado',                                           'authenticated', v_socia,
           format(insm, v_post, '3d', 10, v_socia), '23514'),
      (14, 'S14 lectura sin ningún número',                                   'authenticated', v_socia,
           'insert into public.contenido_metrica (post_id, momento, leido_en, creado_por) values ('
             || v_post || ', ''final'', now(), ' || quote_literal(v_socia) || ')', '23514'),
      (15, 'S15 socia agrega una foto al banco',                              'authenticated', v_socia,
           format(insb, '1xciG2I0VtiB6ulUXQOlfvsiqZDUSIzzzz', v_socia), null),
      (16, 'S16 la misma foto dos veces',                                     'authenticated', v_socia,
           format(insb, '1xciG2I0VtiB6ulUXQOlfvsiqZDUSIzzzz', v_socia), '23505'),
      (17, 'S17 id de Drive con caracteres raros',                            'authenticated', v_socia,
           format(insb, '../../etc/passwd?x=1&y=22222', v_socia), '23514'),
      (18, 'S18 socia edita el texto del post (con SU nombre)',               'authenticated', v_socia,
           format('update public.contenido_post set texto = ''nuevo'', editado_por = %L where id = %s', v_socia, v_post), null),
      (19, 'S19 socia edita firmando por otra',                               'authenticated', v_socia,
           format('update public.contenido_post set texto = ''x'', editado_por = %L where id = %s', 'otra@persona.com', v_post), '42501'),
      (20, 'S20 socia cambia creado_por (columna no editable)',               'authenticated', v_socia,
           format('update public.contenido_post set creado_por = %L, editado_por = %L where id = %s', v_socia, v_socia, v_post), '42501'),
      (21, 'S21 socia BORRA un post',                                         'authenticated', v_socia,
           format('delete from public.contenido_post where id = %s', v_post), '42501'),
      (22, 'S22 socia EDITA un estado (append-only)',                         'authenticated', v_socia,
           'update public.contenido_post_estado set estado = ''publicado''', '42501'),
      (23, 'S23 socia EDITA una métrica (append-only)',                       'authenticated', v_socia,
           'update public.contenido_metrica set vistas = 1', '42501'),
      (24, 'S24 socia retira una foto del banco (activo = false)',            'authenticated', v_socia,
           format('update public.contenido_banco set activo = false, editado_por = %L', v_socia), null),
      (25, 'S25 socia BORRA del banco',                                       'authenticated', v_socia,
           'delete from public.contenido_banco', '42501'),
      -- equipo
      (30, 'E1 equipo crea un post',                                          'authenticated', v_equipo,
           format(insp, v_equipo, null), '42501'),
      (31, 'E2 equipo mueve un estado',                                       'authenticated', v_equipo,
           format(inse, v_post, 'publicado', '[]', 'false', v_equipo), '42501'),
      (32, 'E3 equipo anota una métrica',                                     'authenticated', v_equipo,
           format(insm, v_post, '7d', 10, v_equipo), '42501'),
      (33, 'E4 equipo agrega al banco',                                       'authenticated', v_equipo,
           format(insb, '1RTGcDcf3UUjLSleqIEUGRMFhrL6Vzzzz', v_equipo), '42501'),
      -- anon (la llave pública, que va dentro de index.html)
      (40, 'A1 anon crea un post',                                            'anon', null,
           format(insp, 'anon', null), '42501'),
      (41, 'A2 anon mueve un estado',                                         'anon', null,
           format(inse, v_post, 'publicado', '[]', 'false', 'anon'), '42501'),
      (42, 'A3 anon anota una métrica',                                       'anon', null,
           format(insm, v_post, '7d', 10, 'anon'), '42501'),
      (43, 'A4 anon agrega al banco',                                         'anon', null,
           format(insb, '1RTGcDcf3UUjLSleqIEUGRMFhrL6Vzzzz', 'anon'), '42501'),
      (44, 'A5 anon lee los posts',                                           'anon', null,
           'select count(*) from public.contenido_post', '42501'),
      (45, 'A6 anon lee la vista de posts',                                   'anon', null,
           'select count(*) from public.v_contenido_post', '42501'),
      (46, 'A7 anon lee la vista de métricas',                                'anon', null,
           'select count(*) from public.v_contenido_metrica_vigente', '42501'),
      (47, 'A8 anon lee el banco',                                            'anon', null,
           'select count(*) from public.contenido_banco', '42501'),
      (48, 'A9 anon edita un post',                                           'anon', null,
           format('update public.contenido_post set texto = ''x'' where id = %s', v_post), '42501')
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

  -- un UPDATE que la RLS filtra no da error: da 0 filas. Se mira el resultado, no el código.
  select count(*) into v_n from public.contenido_post where id = v_post and texto = 'nuevo' and editado_en is not null;
  v_res := v_res || jsonb_build_object('p', 'S18b la edición quedó, con editado_en puesto por la base', 'esperado', '1', 'obtenido', v_n::text, 'ok', v_n = 1);
  select count(*) into v_n from public.contenido_banco where not activo;
  v_res := v_res || jsonb_build_object('p', 'S24b la foto quedó retirada', 'esperado', '1', 'obtenido', v_n::text, 'ok', v_n = 1);

  -- equipo: no ve nada (ni por tabla ni por vista)
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select (select count(*) from public.contenido_post) + (select count(*) from public.v_contenido_post)
       + (select count(*) from public.v_contenido_metrica_vigente) + (select count(*) from public.contenido_banco) into v_n;
  update public.contenido_post set texto = 'equipo', editado_por = v_equipo where id = v_post;
  perform set_config('role', 'postgres', true);
  v_res := v_res || jsonb_build_object('p', 'E5 equipo no ve posts, métricas ni banco', 'esperado', '0', 'obtenido', v_n::text, 'ok', v_n = 0);
  select count(*) into v_n from public.contenido_post where texto = 'equipo';
  v_res := v_res || jsonb_build_object('p', 'E6 el UPDATE de equipo no tocó ninguna fila', 'esperado', '0', 'obtenido', v_n::text, 'ok', v_n = 0);

  -- socia: ve; la vista da el ÚLTIMO estado y la ÚLTIMA lectura
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_n from public.v_contenido_post where id = v_post and estado = 'aprobado' and fallas = '[]'::jsonb;
  perform set_config('role', 'postgres', true);
  v_res := v_res || jsonb_build_object('p', 'V1 la vista da el último estado (S8: aprobado sin fallas)', 'esperado', '1', 'obtenido', v_n::text, 'ok', v_n = 1);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_n from public.v_contenido_metrica_vigente where post_id = v_post and momento = '24h' and vistas = 700;
  perform set_config('role', 'postgres', true);
  v_res := v_res || jsonb_build_object('p', 'V2 gana la última lectura del momento (700, no 623)', 'esperado', '1', 'obtenido', v_n::text, 'ok', v_n = 1);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_n from public.v_contenido_post where estado = 'idea';
  perform set_config('role', 'postgres', true);
  v_res := v_res || jsonb_build_object('p', 'V3 un post sin estados se lee como «idea» (S1)', 'esperado', '1', 'obtenido', v_n::text, 'ok', v_n = 1);
  if v_socia2 is not null then
    perform set_config('request.jwt.claims', json_build_object('email', v_socia2, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    select count(*) into v_n from public.v_contenido_post;
    perform set_config('role', 'postgres', true);
    v_res := v_res || jsonb_build_object('p', 'V4 la otra socia ve los mismos 2 posts', 'esperado', '2', 'obtenido', v_n::text, 'ok', v_n = 2);
  end if;

  -- asistente: lee, no escribe
  if v_asis is not null then
    perform set_config('request.jwt.claims', json_build_object('email', v_asis, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    begin
      execute format(insp, v_asis, null);
      v_obt := 'ENTRA'; v_ok := false;
    exception when others then
      v_obt := 'RECHAZA: ' || sqlstate || ' · ' || sqlerrm; v_ok := sqlstate = '42501';
    end;
    perform set_config('role', 'postgres', true);
    v_res := v_res || jsonb_build_object('p', 'I1 el asistente crea un post', 'esperado', 'RECHAZA · 42501', 'obtenido', v_obt, 'ok', v_ok);
  end if;

  -- catálogo
  select count(*) into v_n from information_schema.role_table_grants
   where grantee = 'anon' and table_name like any (array['contenido\_%', 'v\_contenido\_%']);
  v_res := v_res || jsonb_build_object('p', 'C1 grants a anon en tablas y vistas de contenido', 'esperado', '0', 'obtenido', v_n::text, 'ok', v_n = 0);
  select count(*) into v_n from pg_policy where polrelid in ('public.contenido_post'::regclass, 'public.contenido_post_estado'::regclass,
                                                           'public.contenido_metrica'::regclass, 'public.contenido_banco'::regclass);
  v_res := v_res || jsonb_build_object('p', 'C2 políticas: 10 propias + 5 automáticas × 4 tablas', 'esperado', '30', 'obtenido', v_n::text, 'ok', v_n = 30);
  select count(*) into v_n from pg_class where relname in ('v_contenido_post', 'v_contenido_metrica_vigente')
     and 'security_invoker=true' = any (reloptions);
  v_res := v_res || jsonb_build_object('p', 'C3 las 2 vistas con security_invoker', 'esperado', '2', 'obtenido', v_n::text, 'ok', v_n = 2);

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
