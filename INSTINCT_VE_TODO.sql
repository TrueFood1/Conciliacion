-- ═══════════════════════════════════════════════════════════════════════════
-- INSTINCT_VE_TODO.sql  ·  13-oct-2026  ·  Instinct lee TODO Truefie (Personal y archivos incluidos)
-- ✅ APLICADO el 13-oct-2026 por Andrea (ensayo 23/23). Control 61 · 61 · 0 · 1 · true · true · 4. Verificado desde afuera (pg_lector). NO VOLVER A CORRER.
--
-- DECISIÓN DE ANDREA (13-oct): Instinct ve todo Truefie, sin excepciones: salarios, planilla,
--   quincenas, aguinaldos, ajustes, bajas, parámetros, feriados, permisos, el calendario y los
--   archivos (justificantes, aguinaldos, tickets). Sigue SIN escribir nada. Regla general: Lorena
--   decide cómo se construyen sus módulos; Andrea y Lorena ven todo, siempre.
--
-- QUÉ CAMBIA (y nada más):
--   §1 asistente_lee en rrhh_* y storage.objects: de «cerrado siempre» a «solo con el interruptor».
--   §2 asistente_ve_todo: lectura del asistente en las 61 tablas de public (antes dependía de cada una).
--   §3 asistente_ve_archivos: lectura de archivos.
--   §4 rrhh_calendario(): la guardia pasa de «asistente → nada» a «asistente bloqueado → nada».
--   §5 asistente_crear_politicas(): sin excepción de Personal y con la lectura, para las tablas nuevas.
--   NO toca: las tres restrictivas de escritura (no inserta, no actualiza, no borra), las guardias
--   de ent_corregir_alisto, ni nada de socias y equipo.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- §0 · CANDADOS: no se pega dos veces, y las dos funciones que se tocan están como se midieron hoy.
do $$
begin
  if exists (select 1 from pg_policy where polname in ('asistente_ve_todo', 'asistente_ve_archivos')) then
    raise exception 'INSTINCT_VE_TODO ya está aplicado: este archivo no se vuelve a pegar';
  end if;
  if md5(pg_get_functiondef('public.rrhh_calendario()'::regprocedure)) <> '85f7f87782f8cf33b1aff7a2bc0e4f73' then
    raise exception 'rrhh_calendario cambió desde el 13-oct: no se toca sin volver a medirla';
  end if;
  if md5(pg_get_functiondef('public.asistente_crear_politicas(regclass)'::regprocedure)) <> '8bfe14b176cb90b1e8c0348c7979be52' then
    raise exception 'asistente_crear_politicas cambió desde el 13-oct: no se toca sin volver a medirla';
  end if;
end $$;

-- §1 · LA RESTRICCIÓN DE LECTURA, IGUAL PARA TODO: Personal (rrhh_*) y archivos (storage.objects) dejan de
--      estar cerrados para el asistente; quedan como todas las demás: solo con su interruptor encendido.
do $$
declare r record;
begin
  for r in select p.polrelid::regclass as t
             from pg_policy p join pg_class c on c.oid = p.polrelid join pg_namespace n on n.oid = c.relnamespace
            where p.polname = 'asistente_lee' and n.nspname in ('public', 'storage')
              and pg_get_expr(p.polqual, p.polrelid) not ilike '%asistente_encendido%' loop
    execute format('drop policy asistente_lee on %s', r.t);
    execute format('create policy asistente_lee on %s as restrictive for select to authenticated '
                   'using (not (select public.acceso_es_asistente()) or (select public.asistente_encendido()))', r.t);
  end loop;
end $$;

-- §2 · LA LECTURA DEL ASISTENTE EN TODA TABLA DE public. Hasta hoy dependía de la regla de cada tabla, y
--      muchas son «solo socias» (salarios, planilla, compras…). Instinct ve todo, como Andrea y Lorena.
do $$
declare r record;
begin
  for r in select c.oid::regclass as t from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind in ('r', 'p') loop
    execute format('create policy asistente_ve_todo on %s for select to authenticated '
                   'using ((select public.acceso_es_asistente()))', r.t);
  end loop;
end $$;

-- §3 · ARCHIVOS: justificantes, aguinaldos y tickets, en lectura.
create policy asistente_ve_archivos on storage.objects for select to authenticated
  using ((select public.acceso_es_asistente()));

-- §4 · rrhh_calendario(): la guardia del 12-oct le devolvía CERO filas al asistente siempre. Ahora solo
--      cuando está bloqueado (interruptor apagado). Se cambian SOLO esas dos líneas de la definición viva.
do $$
declare d text; viejo text; nuevo text;
begin
  d := pg_get_functiondef('public.rrhh_calendario()'::regprocedure);
  viejo := E'  -- ASISTENTE (12-oct): Personal cerrado para el asistente. Cero filas, como sin perfil.\n'
        || E'  if (select public.acceso_es_asistente()) then return; end if;\n';
  nuevo := E'  -- ASISTENTE (13-oct, Andrea: Instinct ve todo): solo con su interruptor encendido.\n'
        || E'  if (select public.asistente_bloqueado()) then return; end if;\n';
  if (length(d) - length(replace(d, viejo, ''))) / length(viejo) <> 1 then
    raise exception 'rrhh_calendario: la guardia del 12-oct no está una sola vez';
  end if;
  execute replace(d, viejo, nuevo);
end $$;

-- §5 · LAS TABLAS DE MAÑANA: el disparador `asistente_politicas` llama a esta función en cada tabla nueva.
--      Sin la excepción de Personal, y con la lectura del asistente incluida.
create or replace function public.asistente_crear_politicas(p_tabla regclass) returns void
language plpgsql security definer set search_path = public as $f$
begin
  execute format('create policy asistente_no_inserta on %s as restrictive for insert to authenticated '
                 'with check (not (select public.acceso_es_asistente()))', p_tabla);
  execute format('create policy asistente_no_actualiza on %s as restrictive for update to authenticated '
                 'using (not (select public.acceso_es_asistente())) with check (not (select public.acceso_es_asistente()))', p_tabla);
  execute format('create policy asistente_no_borra on %s as restrictive for delete to authenticated '
                 'using (not (select public.acceso_es_asistente()))', p_tabla);
  execute format('create policy asistente_lee on %s as restrictive for select to authenticated '
                 'using (not (select public.acceso_es_asistente()) or (select public.asistente_encendido()))', p_tabla);
  -- Instinct ve todo (Andrea, 13-oct): también las tablas que se creen después.
  execute format('create policy asistente_ve_todo on %s for select to authenticated '
                 'using ((select public.acceso_es_asistente()))', p_tabla);
end;
$f$;
revoke all on function public.asistente_crear_politicas(regclass) from public, anon, authenticated;

-- CONTROL, justo antes del commit. ESPERADO: una fila  61 · 61 · 0 · 1 · true · true · 4
--   (tablas de public · con asistente_ve_todo · asistente_lee que no miran el interruptor · lectura de
--    archivos · calendario con la guardia nueva · función de tablas nuevas sin excepción de Personal ·
--    restrictivas del asistente en archivos, intactas)
select (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relkind in ('r', 'p')) as tablas_public,
       (select count(*) from pg_policy where polname = 'asistente_ve_todo') as con_ve_todo,
       (select count(*) from pg_policy p join pg_class c on c.oid = p.polrelid join pg_namespace n on n.oid = c.relnamespace
         where p.polname = 'asistente_lee' and n.nspname in ('public', 'storage')
           and pg_get_expr(p.polqual, p.polrelid) not ilike '%asistente_encendido%') as lee_sin_interruptor,
       (select count(*) from pg_policy where polname = 'asistente_ve_archivos') as archivos,
       (select pg_get_functiondef('public.rrhh_calendario()'::regprocedure) like '%asistente_bloqueado()) then return%') as calendario,
       (select pg_get_functiondef('public.asistente_crear_politicas(regclass)'::regprocedure) not like '%rrhh%') as funcion,
       (select count(*) from pg_policy where polrelid = 'storage.objects'::regclass and not polpermissive) as restrictivas_archivos;
commit;
