-- ═══════════════════════════════════════════════════════════════════════════
-- ENSAYO_CONTENIDO_FICHAS.sql  ·  28-oct-2026  ·  ENSAYO EN SECO · NO ESCRIBE NADA
-- Prueba los CHECK de CAMBIO_CONTENIDO_FICHAS.sql (categoría 'fichas', tipo 'documento') con un
-- documento de prueba cargado como socia, el archivo de las 20 fotos, y lo deshace todo (rollback).
-- El bloque DDL es COPIA EXACTA de CAMBIO_CONTENIDO_FICHAS.sql (sin begin/commit ni el control).
-- Si se cambia aquél, se vuelve a copiar acá.
-- ✅ CORRIDO en producción por Andrea el 29-oct-2026: 19/19 ok, terminó en rollback.
--
-- CÓMO SE LEE
--   Una tabla con TODAS las filas en ok = true. Un RECHAZA da ok solo si el SQLSTATE esperado es
--   el que salió (no vale rechazar por el motivo de al lado). Si el editor dice "Success. No rows
--   returned", no llegó al final y no vale.
--   42501 = RLS o sin permiso · 23514 = check.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- ▼▼▼ BLOQUE DDL (copia de CAMBIO_CONTENIDO_FICHAS.sql, sin begin/commit ni el control) ▼▼▼

do $$ begin
  if not exists (select 1 from storage.buckets where id = 'contenido-miniaturas') then
    raise exception 'falta CAMBIO_CONTENIDO_B139.sql: pegarlo primero';
  end if;
  if exists (select 1 from pg_constraint where conname = 'contenido_banco_categoria_check'
               and pg_get_constraintdef(oid) like '%''fichas''%') then
    raise exception 'la categoría fichas ya existe: este archivo no se vuelve a pegar';
  end if;
end $$;
-- cuántas filas había: el control exige las mismas (este cambio no borra ni agrega filas)
select set_config('b146.filas_antes', (select count(*) from public.contenido_banco)::text, true);

-- ── 1 · tipo: foto · video · documento (igual que b139) ───────────────────
alter table public.contenido_banco drop constraint contenido_banco_tipo_check;
alter table public.contenido_banco add constraint contenido_banco_tipo_check
  check (tipo in ('foto', 'video', 'documento'));

-- ── 2 · categorías: las 12 de b139 + fichas ───────────────────────────────
alter table public.contenido_banco drop constraint contenido_banco_categoria_check;
alter table public.contenido_banco add constraint contenido_banco_categoria_check
  check (categoria in ('producto', 'empaque', 'tabla_nutricional', 'fichas',
                       'desayunos', 'almuerzos_cenas', 'meriendas', 'nosotras', 'planta', 'en_tienda',
                       'certificaciones', 'logos_supermercados', 'marca'));

-- ── 3 · el banco queda con lo importante de tener a la mano (Andrea, 28-oct 18:23) ──
-- Se ARCHIVAN (activo = false; no se borra ninguna fila) las fotos de producto, planta y en_tienda:
-- medido el 28-oct con pg_lector, 10 + 8 + 2 = 20 activas. Quedan activas logos_supermercados (2)
-- y empaque (1). editado_en lo pone el trigger contenido_banco_editado; editado_por lleva la marca
-- del cambio, como la corrección de b139 ('correccion-b139-27oct'), no un correo (el repo es público).
update public.contenido_banco
   set activo = false, editado_por = 'archivo-b146-28oct'
 where activo and tipo = 'foto' and categoria in ('producto', 'planta', 'en_tienda');
-- ▲▲▲ FIN BLOQUE DDL ▲▲▲

do $$
declare
  v_socia text; v_equipo text; v_n int; r record; v_ok boolean; v_obt text;
  v_res jsonb := '[]'::jsonb;
  -- %1$L categoria · %2$L tipo · %3$L creado_por · %4$L drive_id  (ids de Drive INVENTADOS: el repo es público)
  insb constant text := 'insert into public.contenido_banco (drive_id, nombre, tipo, categoria, producto_id, creado_por) '
    'values (%4$L, ''ficha-tecnica-ensayo.pdf'', %2$L, %1$L, 451, %3$L)';
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by id limit 1;
  select email into v_equipo from v_acceso_usuario where perfil not in ('socias', 'asistente') and activo order by id limit 1;
  if v_socia is null or v_equipo is null then
    raise exception 'el ensayo necesita una socia y alguien de equipo (socia %, equipo %)', v_socia, v_equipo;
  end if;

  -- ── lo que había sigue igual ──
  select count(*) into v_n from public.contenido_banco;
  v_res := v_res || jsonb_build_object('p', 'M1 mismas filas que antes del cambio', 'esperado', current_setting('b146.filas_antes'),
                                       'obtenido', v_n::text, 'ok', v_n = current_setting('b146.filas_antes')::int);

  -- ── el archivo de fotos (§3), antes de cargar nada ──
  select count(*) into v_n from public.contenido_banco where not activo and editado_por = 'archivo-b146-28oct';
  v_res := v_res || jsonb_build_object('p', 'A1 fotos archivadas (producto 10 + planta 8 + en_tienda 2)', 'esperado', '20', 'obtenido', v_n::text, 'ok', v_n = 20);
  select count(*) into v_n from public.contenido_banco where activo and tipo = 'foto';
  v_res := v_res || jsonb_build_object('p', 'A2 fotos que siguen activas (logos 2 + empaque 1)', 'esperado', '3', 'obtenido', v_n::text, 'ok', v_n = 3);
  select count(*) into v_n from public.contenido_banco where activo and categoria in ('producto', 'planta', 'en_tienda');
  v_res := v_res || jsonb_build_object('p', 'A3 nada activo en producto, planta ni en_tienda', 'esperado', '0', 'obtenido', v_n::text, 'ok', v_n = 0);
  select count(*) into v_n from public.contenido_banco where editado_por = 'archivo-b146-28oct' and editado_en > now() - interval '1 minute';
  v_res := v_res || jsonb_build_object('p', 'A4 el trigger puso editado_en a las 20', 'esperado', '20', 'obtenido', v_n::text, 'ok', v_n = 20);

  for r in
    select * from (values
      (1, 'F1 socia agrega un PDF en fichas',                   'authenticated', v_socia,
          format(insb, 'fichas', 'documento', v_socia, '1EnsayoB146FichaSocia00000000aa'), null),
      (2, 'F2 socia agrega una foto en fichas (el CHECK no ata tipo a categoría)', 'authenticated', v_socia,
          format(insb, 'fichas', 'foto', v_socia, '1EnsayoB146FichaFoto000000000aa'), null),
      (3, 'F3 socia agrega un documento en producto',           'authenticated', v_socia,
          format(insb, 'producto', 'documento', v_socia, '1EnsayoB146DocProducto0000000aa'), null),
      (4, 'F4 categoría inventada (fichas_tecnicas)',            'authenticated', v_socia,
          format(insb, 'fichas_tecnicas', 'documento', v_socia, '1EnsayoB146FichaMala0000000aa'), '23514'),
      (5, 'F5 tipo inventado (pdf)',                             'authenticated', v_socia,
          format(insb, 'fichas', 'pdf', v_socia, '1EnsayoB146TipoMalo00000000aa'), '23514'),
      (6, 'F6 equipo agrega una ficha',                          'authenticated', v_equipo,
          format(insb, 'fichas', 'documento', v_equipo, '1EnsayoB146FichaEquipo000000aa'), '42501'),
      (7, 'F7 anon agrega una ficha',                            'anon', null,
          format(insb, 'fichas', 'documento', 'anon', '1EnsayoB146FichaAnon00000000aa'), '42501'),
      (8, 'F8 socia recategoriza su PDF a certificaciones',      'authenticated', v_socia,
          format('update public.contenido_banco set categoria = ''certificaciones'', editado_por = %L '
                 'where drive_id = ''1EnsayoB146DocProducto0000000aa''', v_socia), null)
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

  -- lo que entró, mirado como dueño de la tabla
  select count(*) into v_n from public.contenido_banco
   where drive_id = '1EnsayoB146FichaSocia00000000aa' and tipo = 'documento' and categoria = 'fichas' and activo and creado_por = v_socia;
  v_res := v_res || jsonb_build_object('p', 'V1 el PDF quedó: documento · fichas · activo · creado por la socia', 'esperado', '1', 'obtenido', v_n::text, 'ok', v_n = 1);
  select count(*) into v_n from public.contenido_banco where drive_id = '1EnsayoB146DocProducto0000000aa' and categoria = 'certificaciones';
  v_res := v_res || jsonb_build_object('p', 'V2 la recategorización quedó', 'esperado', '1', 'obtenido', v_n::text, 'ok', v_n = 1);
  select count(*) into v_n from public.contenido_banco;
  v_res := v_res || jsonb_build_object('p', 'V3 filas = antes + 3 (F1, F2, F3)', 'esperado', (current_setting('b146.filas_antes')::int + 3)::text,
                                       'obtenido', v_n::text, 'ok', v_n = current_setting('b146.filas_antes')::int + 3);

  -- la socia LEE la ficha por la API (RLS de select)
  perform set_config('request.jwt.claims', json_build_object('email', v_socia, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_n from public.contenido_banco where categoria = 'fichas' and tipo = 'documento';
  perform set_config('role', 'postgres', true);
  v_res := v_res || jsonb_build_object('p', 'V4 la socia ve el PDF en fichas', 'esperado', '1', 'obtenido', v_n::text, 'ok', v_n = 1);
  -- el equipo NO lo ve
  perform set_config('request.jwt.claims', json_build_object('email', v_equipo, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_n from public.contenido_banco where categoria = 'fichas';
  perform set_config('role', 'postgres', true);
  v_res := v_res || jsonb_build_object('p', 'V5 el equipo no ve fichas', 'esperado', '0', 'obtenido', v_n::text, 'ok', v_n = 0);

  -- catálogo
  select count(*) into v_n from pg_constraint where conrelid = 'public.contenido_banco'::regclass
     and conname in ('contenido_banco_tipo_check', 'contenido_banco_categoria_check');
  v_res := v_res || jsonb_build_object('p', 'C1 los 2 CHECK con su nombre de siempre', 'esperado', '2', 'obtenido', v_n::text, 'ok', v_n = 2);

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: 19 filas, todas ok = true.

rollback;
