-- ═══════════════════════════════════════════════════════════════════════════
-- ASISTENTE_ROL.sql  ·  12-oct-2026  ·  ✅ APLICADO el 12-oct-2026 por Andrea, después del ensayo 28/28.
--    Fila de control: 59 · 59 · 4 · 1 · 6 · 2 · 1 · 2 · 0 · 1. VERIFICADO desde afuera (pg_lector): 0 tablas
--    sin las 4, 240 restrictivas, 129 permisivas, interruptor sin filas (apagado), 0 cuentas asistente;
--    REST anon → 42501 en las tablas y la función nuevas. NO VOLVER A CORRER.
-- El perfil «asistente» (Instinct, decisión de Andrea del 12-oct): lee Truefie, NO escribe nada.
--
-- QUÉ HACE (las piezas, en orden)
--   §1 'asistente' entra al CHECK de acceso_usuario.
--   §2 acceso_es_asistente(): por CORREO y sin mirar `activo` (desactivar no le abre nada).
--   §3 asistente_interruptor (apagar en un minuto; sin filas = apagado) y asistente_permiso
--      (escrituras de a una, más adelante). Solo socias; append-only.
--   §4 Cuatro políticas RESTRICTIVAS en CADA tabla de public que exista al pegar: no inserta, no
--      actualiza, no borra; lee solo con el interruptor encendido. Personal (rrhh_*) cerrado.
--      Se SUMAN a las de hoy: socias y equipo siguen exactamente igual.
--   §5 compra_tarifa_odoo: el asistente sí ve los precios de compra.
--   §6 storage.objects: el asistente no sube, no cambia, no borra, no ve archivos.
--   §7 Disparador de evento: toda tabla NUEVA de public nace con las cuatro políticas.
--   §8 Guardia en ent_corregir_alisto y rrhh_calendario (las dos `security definer` que lo
--      dejarían pasar), insertada en su definición viva verificada por md5. Nada más se toca.
--   NO toca: el servicio de escritura (ya rechaza a quien no es socia), el proxy de lectura
--   (paso siguiente, usa asistente_bloqueado()), la app.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- §0 · CANDADOS. No se pega dos veces, y las dos funciones que se tocan tienen que estar EXACTAMENTE
--      como se midieron el 12-oct (md5 de su definición viva). Si alguien las cambió, se para.
do $$
begin
  if to_regclass('public.asistente_interruptor') is not null then
    raise exception 'ASISTENTE_ROL ya está aplicado: este archivo no se vuelve a pegar';
  end if;
  if md5(pg_get_functiondef('public.ent_corregir_alisto(bigint,bigint,jsonb,text,text)'::regprocedure)) <> '2ab2285f528f4425be348b024943e826' then
    raise exception 'ent_corregir_alisto cambió desde el 12-oct: no se toca sin volver a medirla';
  end if;
  if md5(pg_get_functiondef('public.rrhh_calendario()'::regprocedure)) <> 'ceb691f29166811ce371553aef8a215c' then
    raise exception 'rrhh_calendario cambió desde el 12-oct: no se toca sin volver a medirla';
  end if;
end $$;

-- §1 · EL PERFIL. 'asistente' entra al CHECK de acceso_usuario (nombre medido en vivo).
alter table public.acceso_usuario drop constraint acceso_usuario_perfil_check;
alter table public.acceso_usuario add constraint acceso_usuario_perfil_check
  check (perfil in ('socias', 'equipo', 'asistente'));

-- §2 · QUIÉN ES EL ASISTENTE. Por CORREO y SIN mirar `activo`: una cuenta que alguna vez fue asistente
--      se sigue tratando como asistente. Si dependiera de `activo`, desactivar a Instinct lo
--      convertiría en un usuario autenticado cualquiera, con escritura en las 23 tablas abiertas.
--      Apagar es el INTERRUPTOR (§3), no `activo`.
create function public.acceso_es_asistente() returns boolean
language sql stable security definer set search_path = public as $f$
  select exists (select 1 from acceso_usuario a
                  where lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
                    and a.perfil = 'asistente');
$f$;

-- §3 · EL INTERRUPTOR (apagar en un minuto) y LOS PERMISOS (escrituras de a una, para más adelante).
--      Append-only; manda la última fila. Sin filas = APAGADO. Solo las socias insertan.
create table public.asistente_interruptor (
  id         bigint generated always as identity primary key,
  encendido  boolean not null,
  motivo     text not null check (length(btrim(motivo)) > 0),
  creado_por text not null,
  creado_en  timestamptz not null default now()
);
create table public.asistente_permiso (
  id         bigint generated always as identity primary key,
  capacidad  text not null check (capacidad ~ '^[a-z][a-z_]{2,39}$'),   -- p. ej. 'validar_entregas'
  encendido  boolean not null,
  motivo     text not null check (length(btrim(motivo)) > 0),
  creado_por text not null,
  creado_en  timestamptz not null default now()
);
alter table public.asistente_interruptor enable row level security;
alter table public.asistente_permiso enable row level security;
revoke all on public.asistente_interruptor, public.asistente_permiso from anon, authenticated;
grant select, insert on public.asistente_interruptor, public.asistente_permiso to authenticated;
create policy asistente_interruptor_sel on public.asistente_interruptor for select to authenticated using (acceso_es_socia());
create policy asistente_interruptor_ins on public.asistente_interruptor for insert to authenticated
  with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));
create policy asistente_permiso_sel on public.asistente_permiso for select to authenticated using (acceso_es_socia());
create policy asistente_permiso_ins on public.asistente_permiso for insert to authenticated
  with check (acceso_es_socia() and creado_por = (auth.jwt() ->> 'email'));

create function public.asistente_encendido() returns boolean
language sql stable security definer set search_path = public as $f$
  select coalesce((select i.encendido from asistente_interruptor i order by i.creado_en desc, i.id desc limit 1), false);
$f$;
-- Para el proxy de lectura (paso siguiente): true = es el asistente y está apagado → no se le lee Odoo.
create function public.asistente_bloqueado() returns boolean
language sql stable security definer set search_path = public as $f$
  select acceso_es_asistente() and not asistente_encendido();
$f$;
-- Escrituras de a una (más adelante): ninguna política la usa todavía. Habilitar una capacidad será
-- un pegado propio que cambie la política de SUS tablas a «… or asistente_puede('<capacidad>')».
create function public.asistente_puede(p_capacidad text) returns boolean
language sql stable security definer set search_path = public as $f$
  select acceso_es_asistente() and asistente_encendido()
     and coalesce((select p.encendido from asistente_permiso p where p.capacidad = p_capacidad
                    order by p.creado_en desc, p.id desc limit 1), false);
$f$;
revoke all on function public.acceso_es_asistente(), public.asistente_encendido(),
                       public.asistente_bloqueado(), public.asistente_puede(text) from public, anon;
grant execute on function public.acceso_es_asistente(), public.asistente_encendido(),
                          public.asistente_bloqueado(), public.asistente_puede(text) to authenticated;

-- §4 · EL CANDADO, tabla por tabla. Cuatro políticas RESTRICTIVAS (se suman a las de hoy, no las
--      reemplazan: socias y equipo siguen exactamente igual). Personal (rrhh_*) cerrado del todo
--      para el asistente (decisión de Andrea, 12-oct: salarios y planilla se ven con Lorena).
--      Esta función no la ejecuta nadie desde afuera: solo este pegado y el disparador del §7.
create function public.asistente_crear_politicas(p_tabla regclass) returns void
language plpgsql security definer set search_path = public as $f$
declare
  v_personal boolean := (select c.relname like 'rrhh\_%' from pg_class c where c.oid = p_tabla);
begin
  execute format('create policy asistente_no_inserta on %s as restrictive for insert to authenticated '
                 'with check (not (select public.acceso_es_asistente()))', p_tabla);
  execute format('create policy asistente_no_actualiza on %s as restrictive for update to authenticated '
                 'using (not (select public.acceso_es_asistente())) with check (not (select public.acceso_es_asistente()))', p_tabla);
  execute format('create policy asistente_no_borra on %s as restrictive for delete to authenticated '
                 'using (not (select public.acceso_es_asistente()))', p_tabla);
  execute format('create policy asistente_lee on %s as restrictive for select to authenticated using (%s)', p_tabla,
                 case when v_personal then 'not (select public.acceso_es_asistente())'
                      else 'not (select public.acceso_es_asistente()) or (select public.asistente_encendido())' end);
end;
$f$;
revoke all on function public.asistente_crear_politicas(regclass) from public, anon, authenticated;

-- Todas las tablas de public QUE EXISTEN AL PEGAR (incluidas las dos del §3), no una lista escrita a mano.
do $$
declare r record;
begin
  for r in select c.oid::regclass as t from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind in ('r', 'p') order by c.relname loop
    perform public.asistente_crear_politicas(r.t);
  end loop;
end $$;

-- §5 · PRECIOS DE COMPRA: el asistente sí los ve (decisión de Andrea). Pasa además por `asistente_lee`.
create policy compra_tarifa_odoo_sel_asistente on public.compra_tarifa_odoo
  for select to authenticated using ((select public.acceso_es_asistente()));

-- §6 · ARCHIVOS (storage): el asistente no sube, no cambia, no borra y no ve archivos.
create policy asistente_no_inserta on storage.objects as restrictive for insert to authenticated
  with check (not (select public.acceso_es_asistente()));
create policy asistente_no_actualiza on storage.objects as restrictive for update to authenticated
  using (not (select public.acceso_es_asistente())) with check (not (select public.acceso_es_asistente()));
create policy asistente_no_borra on storage.objects as restrictive for delete to authenticated
  using (not (select public.acceso_es_asistente()));
create policy asistente_lee on storage.objects as restrictive for select to authenticated
  using (not (select public.acceso_es_asistente()));

-- §7 · LAS TABLAS DE MAÑANA. Como `ensure_rls` (que ya prende RLS solo en cada tabla nueva), este
--      disparador le pone las cuatro políticas a toda tabla nueva de public. Así la próxima tabla
--      que nadie recuerde no le queda abierta al asistente.
create function public.asistente_politicas_auto() returns event_trigger
language plpgsql security definer set search_path = pg_catalog, public as $f$
declare cmd record;
begin
  for cmd in select * from pg_event_trigger_ddl_commands()
              where command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
                and object_type in ('table', 'partitioned table') and schema_name = 'public' loop
    perform public.asistente_crear_politicas(cmd.objid::regclass);
  end loop;
end;
$f$;
revoke all on function public.asistente_politicas_auto() from public, anon, authenticated;
create event trigger asistente_politicas on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function public.asistente_politicas_auto();

-- §8 · LAS DOS FUNCIONES `security definer` QUE SALTAN RLS: una guardia al principio, y NADA MÁS.
--      Se toma la definición VIVA (ya verificada por md5 en el §0) y se le inserta la guardia después
--      de su único `begin`. rrhh_resolver_evento no se toca: ya exige socia antes de hacer nada.
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.ent_corregir_alisto(bigint,bigint,jsonb,text,text)'::regprocedure);
  n := (length(d) - length(replace(d, E'\nbegin\n', ''))) / length(E'\nbegin\n');
  if n <> 1 then raise exception 'ent_corregir_alisto: esperaba un solo begin y hay %', n; end if;
  execute replace(d, E'\nbegin\n', E'\nbegin\n' || $g$  -- ASISTENTE (12-oct): el asistente no corrige preparaciones.
  if (select public.acceso_es_asistente()) then
    raise exception 'El asistente no escribe en Truefie (ent_corregir_alisto).' using errcode = '42501';
  end if;
$g$);

  d := pg_get_functiondef('public.rrhh_calendario()'::regprocedure);
  n := (length(d) - length(replace(d, E'\nbegin\n', ''))) / length(E'\nbegin\n');
  if n <> 1 then raise exception 'rrhh_calendario: esperaba un solo begin y hay %', n; end if;
  execute replace(d, E'\nbegin\n', E'\nbegin\n' || $g$  -- ASISTENTE (12-oct): Personal cerrado para el asistente. Cero filas, como sin perfil.
  if (select public.acceso_es_asistente()) then return; end if;
$g$);
end $$;

-- CONTROL, adentro de la transacción y justo antes del final. ESPERADO: una fila
--   tablas_public = tablas_con_las_4 (59 el 12-oct) · storage 4 · check 1 · funciones 6 · guardias 2 ·
--   disparador 1 · tablas_nuevas_con_rls 2 · grants_anon 0 · compra_asistente 1
select (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relkind in ('r', 'p')) as tablas_public,
       (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relkind in ('r', 'p')
           and (select count(*) from pg_policy p where p.polrelid = c.oid and not p.polpermissive
                  and p.polname in ('asistente_no_inserta', 'asistente_no_actualiza', 'asistente_no_borra', 'asistente_lee')) = 4)
         as tablas_con_las_4,
       (select count(*) from pg_policy p where p.polrelid = 'storage.objects'::regclass and not p.polpermissive
         and p.polname like 'asistente\_%') as storage,
       (select count(*) from pg_constraint where conname = 'acceso_usuario_perfil_check'
         and pg_get_constraintdef(oid) like '%asistente%') as check_asistente,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
         and p.proname in ('acceso_es_asistente', 'asistente_encendido', 'asistente_bloqueado', 'asistente_puede',
                           'asistente_crear_politicas', 'asistente_politicas_auto')) as funciones,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
         and p.proname in ('ent_corregir_alisto', 'rrhh_calendario') and p.prosrc like '%acceso_es_asistente%') as guardias,
       (select count(*) from pg_event_trigger where evtname = 'asistente_politicas' and evtenabled = 'O') as disparador,
       (select count(*) from pg_class where oid in ('public.asistente_interruptor'::regclass, 'public.asistente_permiso'::regclass)
         and relrowsecurity) as tablas_nuevas_con_rls,
       (select count(*) from information_schema.role_table_grants where grantee = 'anon'
         and table_name in ('asistente_interruptor', 'asistente_permiso')) as grants_anon,
       (select count(*) from pg_policy where polname = 'compra_tarifa_odoo_sel_asistente') as compra_asistente;
commit;
