# Genera ASISTENTE_ROL.sql (pegado) y ENSAYO_ASISTENTE_ROL.sql (ensayo con rollback) desde UNA fuente,
# para que el bloque DDL sea idéntico en los dos. Uso: python3 gen_asistente.py <carpeta destino>
import sys, os

DEST = sys.argv[1]
MD5_CORREGIR = "2ab2285f528f4425be348b024943e826"     # medido el 12-oct con pg_lector
MD5_CALENDARIO = "ceb691f29166811ce371553aef8a215c"
FIRMA_CORREGIR = "public.ent_corregir_alisto(bigint,bigint,jsonb,text,text)"
FIRMA_CALENDARIO = "public.rrhh_calendario()"
NO_ASIS = "not (select public.acceso_es_asistente())"

DDL = r"""
-- §0 · CANDADOS. No se pega dos veces, y las dos funciones que se tocan tienen que estar EXACTAMENTE
--      como se midieron el 12-oct (md5 de su definición viva). Si alguien las cambió, se para.
do $$
begin
  if to_regclass('public.asistente_interruptor') is not null then
    raise exception 'ASISTENTE_ROL ya está aplicado: este archivo no se vuelve a pegar';
  end if;
  if md5(pg_get_functiondef('%(FIRMA_CORREGIR)s'::regprocedure)) <> '%(MD5_CORREGIR)s' then
    raise exception 'ent_corregir_alisto cambió desde el 12-oct: no se toca sin volver a medirla';
  end if;
  if md5(pg_get_functiondef('%(FIRMA_CALENDARIO)s'::regprocedure)) <> '%(MD5_CALENDARIO)s' then
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
  v_personal boolean := (select c.relname like 'rrhh\_%%' from pg_class c where c.oid = p_tabla);
begin
  execute format('create policy asistente_no_inserta on %%s as restrictive for insert to authenticated '
                 'with check (%(NO_ASIS)s)', p_tabla);
  execute format('create policy asistente_no_actualiza on %%s as restrictive for update to authenticated '
                 'using (%(NO_ASIS)s) with check (%(NO_ASIS)s)', p_tabla);
  execute format('create policy asistente_no_borra on %%s as restrictive for delete to authenticated '
                 'using (%(NO_ASIS)s)', p_tabla);
  execute format('create policy asistente_lee on %%s as restrictive for select to authenticated using (%%s)', p_tabla,
                 case when v_personal then '%(NO_ASIS)s'
                      else '%(NO_ASIS)s or (select public.asistente_encendido())' end);
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
  with check (%(NO_ASIS)s);
create policy asistente_no_actualiza on storage.objects as restrictive for update to authenticated
  using (%(NO_ASIS)s) with check (%(NO_ASIS)s);
create policy asistente_no_borra on storage.objects as restrictive for delete to authenticated
  using (%(NO_ASIS)s);
create policy asistente_lee on storage.objects as restrictive for select to authenticated
  using (%(NO_ASIS)s);

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
  d := pg_get_functiondef('%(FIRMA_CORREGIR)s'::regprocedure);
  n := (length(d) - length(replace(d, E'\nbegin\n', ''))) / length(E'\nbegin\n');
  if n <> 1 then raise exception 'ent_corregir_alisto: esperaba un solo begin y hay %%', n; end if;
  execute replace(d, E'\nbegin\n', E'\nbegin\n' || $g$  -- ASISTENTE (12-oct): el asistente no corrige preparaciones.
  if (select public.acceso_es_asistente()) then
    raise exception 'El asistente no escribe en Truefie (ent_corregir_alisto).' using errcode = '42501';
  end if;
$g$);

  d := pg_get_functiondef('%(FIRMA_CALENDARIO)s'::regprocedure);
  n := (length(d) - length(replace(d, E'\nbegin\n', ''))) / length(E'\nbegin\n');
  if n <> 1 then raise exception 'rrhh_calendario: esperaba un solo begin y hay %%', n; end if;
  execute replace(d, E'\nbegin\n', E'\nbegin\n' || $g$  -- ASISTENTE (12-oct): Personal cerrado para el asistente. Cero filas, como sin perfil.
  if (select public.acceso_es_asistente()) then return; end if;
$g$);
end $$;
""" % dict(FIRMA_CORREGIR=FIRMA_CORREGIR, MD5_CORREGIR=MD5_CORREGIR, FIRMA_CALENDARIO=FIRMA_CALENDARIO,
           MD5_CALENDARIO=MD5_CALENDARIO, NO_ASIS=NO_ASIS)

CONTROL = r"""
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
"""

COMO = lambda quien: ("perform set_config('request.jwt.claims', json_build_object('email', %s, 'role', 'authenticated')::text, true); "
                      "perform set_config('role', 'authenticated', true);" % quien)
PG = "perform set_config('role', 'postgres', true);"
TABLAS = ("select c.relname from pg_class c join pg_namespace ns on ns.oid = c.relnamespace "
          "where ns.nspname = 'public' and c.relkind in ('r', 'p') order by 1")


def fila(p, esperado, obtenido, ok):
    return ("  v_res := v_res || jsonb_build_object('p', %s, 'esperado', %s, 'obtenido', %s, 'ok', %s);\n"
            % (p, esperado, obtenido, ok))


FOTO = r"""
-- ── FOTO ANTES DEL CANDADO: cuántas filas ve una socia y alguien de equipo en cada tabla ──
do $$
declare v_socia text; v_equipo text; r record; n bigint; js_s jsonb := '{}'; js_e jsonb := '{}';
begin
  select email into v_socia  from v_acceso_usuario where perfil = 'socias' and activo order by id limit 1;
  select email into v_equipo from v_acceso_usuario where perfil = 'equipo' and activo order by id limit 1;
  if v_socia is null or v_equipo is null then
    raise exception 'el ensayo necesita una socia y alguien de equipo activos';
  end if;
  perform set_config('ensayo.socia', v_socia, true);
  perform set_config('ensayo.equipo', v_equipo, true);
  for r in %(TABLAS)s loop
    begin %(COMO_S)s execute format('select count(*) from public.%%I', r.relname) into n; exception when others then n := -1; end;
    js_s := js_s || jsonb_build_object(r.relname, n);
    begin %(COMO_E)s execute format('select count(*) from public.%%I', r.relname) into n; exception when others then n := -1; end;
    js_e := js_e || jsonb_build_object(r.relname, n);
    %(PG)s
  end loop;
  perform set_config('ensayo.antes_socia', js_s::text, true);
  perform set_config('ensayo.antes_equipo', js_e::text, true);
end $$;
""" % dict(TABLAS=TABLAS, COMO_S=COMO("v_socia"), COMO_E=COMO("v_equipo"), PG=PG)

# El cuerpo del ensayo. Variables: v_socia, v_equipo, v_asis; v_res acumula las filas del resultado.
PRUEBAS = r"""
do $$
declare
  v_socia  text := current_setting('ensayo.socia');
  v_equipo text := current_setting('ensayo.equipo');
  v_asis   text := 'instinct@truefoodcr.com';
  v_res    jsonb := '[]'::jsonb;
  antes_s  jsonb := current_setting('ensayo.antes_socia')::jsonb;
  antes_e  jsonb := current_setting('ensayo.antes_equipo')::jsonb;
  r record; n bigint; m bigint; k bigint; t text; b boolean;
  r_eq text; r_as text; r_so text;
  l_entra text := ''; l_fuga text := ''; l_antes text := ''; l_regr text := ''; l_dif text := ''; l_pasa text := '';
  n_tablas int := 0; n_candado int := 0; n_pasa int := 0; n_previo int := 0; n_frena int := 0;
begin
  -- ═ R · REGRESIÓN DE LECTURA: socia y equipo ven EXACTAMENTE lo mismo que antes del candado ═
  for r in %(TABLAS)s loop
    begin %(COMO_S)s execute format('select count(*) from public.%%I', r.relname) into n; exception when others then n := -1; end;
    begin %(COMO_E)s execute format('select count(*) from public.%%I', r.relname) into m; exception when others then m := -1; end;
    %(PG)s
    if antes_s ? r.relname and ((antes_s ->> r.relname)::bigint <> n or (antes_e ->> r.relname)::bigint <> m) then
      l_dif := l_dif || r.relname || ' ';
    end if;
  end loop;
  %(F_R1)s

  -- ═ ALTA DE PRUEBA (se deshace con el rollback) ═
  begin
    insert into acceso_usuario (email, nombre, perfil, activo, nota, creado_por, creado_en)
      values (v_asis, 'Instinct (ensayo)', 'asistente', true, 'ENSAYO', 'ensayo', clock_timestamp());
    %(F_S1_OK)s
  exception when others then
    %(F_S1_MAL)s
  end;

  -- ═ S · ESTRUCTURA (como postgres) ═
  select count(*) filter (where (select count(*) from pg_policy p where p.polrelid = c.oid and not p.polpermissive
                                  and p.polname in ('asistente_no_inserta', 'asistente_no_actualiza', 'asistente_no_borra', 'asistente_lee')) <> 4),
         count(*)
    into n, m
    from pg_class c join pg_namespace ns on ns.oid = c.relnamespace where ns.nspname = 'public' and c.relkind in ('r', 'p');
  %(F_S2)s
  select count(*) into n from pg_policy p where p.polrelid = 'storage.objects'::regclass and not p.polpermissive and p.polname like 'asistente\_%%';
  %(F_S3)s
  select count(*) into n from pg_event_trigger where evtname = 'asistente_politicas' and evtenabled = 'O';
  %(F_S4)s
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public'
     and p.proname in ('ent_corregir_alisto', 'rrhh_calendario') and p.prosrc like '%%acceso_es_asistente%%';
  %(F_S5)s
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public'
     and p.proname in ('acceso_es_asistente', 'asistente_encendido', 'asistente_bloqueado', 'asistente_puede',
                       'asistente_crear_politicas', 'asistente_politicas_auto') and has_function_privilege('anon', p.oid, 'EXECUTE');
  select count(*) into m from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public'
     and p.proname in ('asistente_crear_politicas', 'asistente_politicas_auto') and has_function_privilege('authenticated', p.oid, 'EXECUTE');
  %(F_S6)s

  -- ═ L · LECTURA DEL ASISTENTE ═
  -- L0 · interruptor sin filas = APAGADO: no ve nada en ninguna tabla
  k := 0;
  for r in %(TABLAS)s loop
    begin %(COMO_A)s execute format('select count(*) from public.%%I', r.relname) into n; exception when others then n := 0; end;
    k := k + n;
  end loop;
  %(PG)s
  %(F_L0)s
  -- se ENCIENDE (como postgres: dueño de la tabla, salta RLS; en producción lo hace una socia)
  insert into asistente_interruptor (encendido, motivo, creado_por, creado_en) values (true, 'ENSAYO', 'ensayo', clock_timestamp());
  -- L1 · encendido: en cada tabla que no es de Personal ve lo mismo que alguien de equipo
  --      (salvo compra_tarifa_odoo, que es para él, y preferencia_tema y acceso_usuario, que son de cada uno)
  l_dif := ''; k := 0;
  for r in %(TABLAS)s loop
    begin %(COMO_A)s execute format('select count(*) from public.%%I', r.relname) into n; exception when others then n := -1; end;
    begin %(COMO_E)s execute format('select count(*) from public.%%I', r.relname) into m; exception when others then m := -1; end;
    %(PG)s
    if r.relname like 'rrhh\_%%' then k := k + greatest(n, 0);
    elsif r.relname not in ('compra_tarifa_odoo', 'preferencia_tema', 'acceso_usuario') and n <> m then
      l_dif := l_dif || r.relname || ' (' || n || ' vs ' || m || ') ';
    end if;
  end loop;
  %(F_L1)s
  %(F_L2)s
  -- L3 · precios de compra: el asistente ve todo; alguien de equipo no ve nada
  select count(*) into k from compra_tarifa_odoo;
  %(COMO_A)s select count(*) into n from compra_tarifa_odoo;
  %(COMO_E)s select count(*) into m from compra_tarifa_odoo;
  %(PG)s
  %(F_L3)s
  -- L4 · archivos: el asistente no ve ninguno
  %(COMO_A)s select count(*) into n from storage.objects; %(PG)s
  %(F_L4)s

  -- ═ K · EL INTERRUPTOR (lo que va a usar el proxy de lectura) ═
  %(COMO_A)s b := asistente_bloqueado(); %(PG)s
  %(F_K1)s
  insert into asistente_interruptor (encendido, motivo, creado_por, creado_en) values (false, 'ENSAYO', 'ensayo', clock_timestamp());
  %(COMO_A)s b := asistente_bloqueado(); select count(*) into n from ent_pedido; %(PG)s
  %(COMO_S)s m := (case when asistente_bloqueado() then 1 else 0 end); %(PG)s
  %(F_K2)s
  -- se vuelve a encender: lo que sigue prueba que la escritura está cerrada AUN ENCENDIDO
  insert into asistente_interruptor (encendido, motivo, creado_por, creado_en) values (true, 'ENSAYO', 'ensayo', clock_timestamp());

  -- ═ W · ESCRITURA, TABLA POR TABLA: equipo, asistente y socia intentan un insert vacío ═
  -- Postgres revisa primero las políticas de hoy y después las restrictivas, así que la prueba
  -- que importa es esta: donde el EQUIPO pasa RLS hoy, al asistente lo tiene que frenar
  -- «asistente_no_inserta» (el error trae su nombre). Si lo frena un P0001, fue un disparador
  -- BEFORE (una guardia) que corre ANTES de RLS: se lista aparte. Cualquier otra cosa es fuga
  -- (un NOT NULL, por ejemplo, salta DESPUÉS de RLS: querría decir que RLS lo dejó pasar).
  for r in %(TABLAS)s loop
    n_tablas := n_tablas + 1;
    begin %(COMO_E)s execute format('insert into public.%%I default values', r.relname); r_eq := 'ENTRA';
    exception when others then r_eq := sqlstate || ' ' || sqlerrm; end;
    begin %(COMO_A)s execute format('insert into public.%%I default values', r.relname); r_as := 'ENTRA';
    exception when others then r_as := sqlstate || ' ' || sqlerrm; end;
    begin %(COMO_S)s execute format('insert into public.%%I default values', r.relname); r_so := 'ENTRA';
    exception when others then r_so := sqlstate || ' ' || sqlerrm; end;
    %(PG)s
    if r_as = 'ENTRA' then l_entra := l_entra || r.relname || ' '; end if;
    if r_as like '42501%%"asistente_no_inserta"%%' then n_candado := n_candado + 1; end if;
    if r_eq = 'ENTRA' or r_eq not like '42501%%' then                -- el equipo pasa RLS hoy
      n_pasa := n_pasa + 1; l_pasa := l_pasa || r.relname || ' ';
      if r_as like '42501%%"asistente_no_inserta"%%' then n_frena := n_frena + 1;
      elsif r_as like 'P0001%%' then n_previo := n_previo + 1; l_antes := l_antes || r.relname || ' [' || left(r_as, 40) || '] ';
      else l_fuga := l_fuga || r.relname || ' [' || left(r_as, 60) || '] ';
      end if;
    end if;
    if r_eq like '%%policy "asistente\_%%' or r_so like '%%policy "asistente\_%%' then l_regr := l_regr || r.relname || ' '; end if;
  end loop;
  %(F_W1)s
  %(F_W2)s
  %(F_W3)s
  %(F_W4)s
  %(F_W5)s

  -- ═ E · UNA TABLA NUEVA (el disparador del §7) con permiso total para todos: solo el asistente queda afuera ═
  create table public.zz_ensayo_asistente (id bigint generated always as identity primary key, v text);
  select count(*) into n from pg_policy p where p.polrelid = 'public.zz_ensayo_asistente'::regclass and not p.polpermissive and p.polname like 'asistente\_%%';
  select c.relrowsecurity into b from pg_class c where c.oid = 'public.zz_ensayo_asistente'::regclass;
  %(F_E1)s
  create policy zz_todo on public.zz_ensayo_asistente for all to authenticated using (true) with check (true);
  grant select, insert, update, delete on public.zz_ensayo_asistente to authenticated;
  insert into public.zz_ensayo_asistente (v) values ('original');
  begin %(COMO_A)s insert into public.zz_ensayo_asistente (v) values ('asistente'); r_as := 'ENTRA';
  exception when others then r_as := sqlstate || ' ' || sqlerrm; end;
  %(PG)s
  %(F_E2)s
  %(COMO_A)s update public.zz_ensayo_asistente set v = 'tocado'; get diagnostics n = row_count;
  delete from public.zz_ensayo_asistente; get diagnostics m = row_count; %(PG)s
  select count(*) into k from public.zz_ensayo_asistente where v = 'original';
  %(F_E3)s
  %(COMO_S)s insert into public.zz_ensayo_asistente (v) values ('socia'); update public.zz_ensayo_asistente set v = v where v = 'socia'; get diagnostics n = row_count; %(PG)s
  %(COMO_E)s insert into public.zz_ensayo_asistente (v) values ('equipo'); delete from public.zz_ensayo_asistente where v = 'equipo'; get diagnostics m = row_count; %(PG)s
  %(F_E4)s

  -- ═ F · LAS FUNCIONES QUE SALTAN RLS ═
  begin %(COMO_A)s perform ent_corregir_alisto(0, 0, '[]'::jsonb, null, null); r_as := 'ENTRA';
  exception when others then r_as := sqlstate || ' ' || sqlerrm; end;
  %(PG)s
  %(F_F1)s
  begin %(COMO_A)s perform * from rrhh_resolver_evento(0, true, null, null, null); r_as := 'ENTRA';
  exception when others then r_as := sqlstate || ' ' || sqlerrm; end;
  %(PG)s
  %(F_F2)s
  %(COMO_A)s select count(*) into n from rrhh_calendario(); %(PG)s
  %(COMO_S)s select count(*) into m from rrhh_calendario(); %(PG)s
  %(F_F3)s
  begin %(COMO_S)s perform ent_corregir_alisto(0, 0, '[]'::jsonb, null, null); r_so := 'ENTRA';
  exception when others then r_so := sqlstate || ' ' || sqlerrm; end;
  %(PG)s
  %(F_F4)s

  -- ═ D · DESACTIVAR A INSTINCT (activo = false) NO LE ABRE NADA ═
  insert into acceso_usuario (email, nombre, perfil, activo, nota, creado_por, creado_en)
    values (v_asis, 'Instinct (ensayo)', 'asistente', false, 'ENSAYO', 'ensayo', clock_timestamp());
  %(COMO_A)s b := acceso_es_asistente(); t := coalesce(acceso_perfil(), '(nulo)');
  begin insert into ent_pedido default values; r_as := 'ENTRA'; exception when others then r_as := sqlstate || ' ' || sqlerrm; end;
  %(PG)s
  %(F_D1)s

  perform set_config('ensayo.res', v_res::text, true);
end $$;

select r->>'p' as prueba, r->>'esperado' as esperado, r->>'obtenido' as obtenido, (r->>'ok')::boolean as ok
  from jsonb_array_elements(current_setting('ensayo.res')::jsonb) r;
-- ESPERADO: %(N)s filas, todas ok = true.
"""

F = {
 "F_S1_OK": fila("'S1 el perfil «asistente» entra en acceso_usuario'", "'ENTRA'", "'ENTRA'", "true"),
 "F_S1_MAL": fila("'S1 el perfil «asistente» entra en acceso_usuario'", "'ENTRA'", "'RECHAZA: '||sqlstate||' · '||sqlerrm", "false"),
 "F_S2": fila("'S2 centinela: tablas de public sin las 4 políticas del asistente'", "'0'", "n::text || ' de ' || m", "n = 0"),
 "F_S3": fila("'S3 storage.objects tiene las 4 restrictivas'", "'4'", "n::text", "n = 4"),
 "F_S4": fila("'S4 el disparador de tablas nuevas existe y está prendido'", "'1'", "n::text", "n = 1"),
 "F_S5": fila("'S5 guardia en ent_corregir_alisto y rrhh_calendario'", "'2'", "n::text", "n = 2"),
 "F_S6": fila("'S6 anon no ejecuta ninguna función nueva · authenticated no ejecuta las internas'", "'0 · 0'", "n::text || ' · ' || m", "n = 0 and m = 0"),
 "F_R1": fila("'R1 socia y equipo ven en cada tabla lo mismo que antes del candado'", "'sin diferencias'", "coalesce(nullif(l_dif, ''), 'sin diferencias')", "l_dif = ''"),
 "F_L0": fila("'L0 interruptor APAGADO (sin filas): el asistente no ve ninguna fila en ninguna tabla'", "'0'", "k::text", "k = 0"),
 "F_L1": fila("'L1 encendido: fuera de Personal ve lo mismo que alguien de equipo'", "'sin diferencias'", "coalesce(nullif(l_dif, ''), 'sin diferencias')", "l_dif = ''"),
 "F_L2": fila("'L2 encendido: Personal (rrhh_*) sigue cerrado'", "'0'", "k::text", "k = 0"),
 "F_L3": fila("'L3 precios de compra: el asistente ve todas las filas, equipo ninguna'", "k::text || ' · 0'", "n::text || ' · ' || m", "n = k and k > 0 and m = 0"),
 "F_L4": fila("'L4 archivos (storage): el asistente no ve ninguno'", "'0'", "n::text", "n = 0"),
 "F_K1": fila("'K1 asistente_bloqueado() con el interruptor encendido'", "'false'", "b::text", "b = false"),
 "F_K2": fila("'K2 apagado: bloqueado = true, lee 0 pedidos · para la socia, false'", "'true · 0 · 0'", "b::text || ' · ' || n || ' · ' || m", "b and n = 0 and m = 0"),
 "F_W1": fila("'W1 ninguna tabla le acepta un insert al asistente (interruptor ENCENDIDO)'", "'ninguna'", "coalesce(nullif(l_entra, ''), 'ninguna')", "l_entra = ''"),
 "F_W2": fila("'W2 donde el equipo pasa RLS hoy, lo frena «asistente_no_inserta»'", "(n_pasa - n_previo)::text || ' de ' || n_pasa", "n_frena::text || ' de ' || (n_pasa - n_previo) || ' · ' || l_pasa", "l_fuga = '' and n_pasa > 0 and n_frena = n_pasa - n_previo"),
 "F_W3": fila("'W3 fugas: el equipo pasa y al asistente no lo frena el candado'", "'ninguna'", "coalesce(nullif(l_fuga, ''), 'ninguna')", "l_fuga = ''"),
 "F_W4": fila("'W4 frenadas ANTES de RLS por una guardia (P0001): informativo'", "'(lista)'", "coalesce(nullif(l_antes, ''), 'ninguna')", "true"),
 "F_W5": fila("'W5 regresión: a socia y equipo nunca los frena una política del asistente'", "'ninguna'", "coalesce(nullif(l_regr, ''), 'ninguna') || ' · ' || n_tablas || ' tablas probadas'", "l_regr = ''"),
 "F_E1": fila("'E1 tabla nueva: el disparador le puso las 4 políticas y RLS está prendido'", "'4 · true'", "n::text || ' · ' || b", "n = 4 and b"),
 "F_E2": fila("'E2 tabla nueva abierta a todos: el asistente no inserta (lo frena el candado)'", "'RECHAZA · 42501 asistente_no_inserta'", "r_as", "r_as like '42501%\"asistente_no_inserta\"%'"),
 "F_E3": fila("'E3 tabla nueva: el asistente no cambia ni borra (0 y 0 filas, el original sigue)'", "'0 · 0 · 1'", "n::text || ' · ' || m || ' · ' || k", "n = 0 and m = 0 and k = 1"),
 "F_E4": fila("'E4 tabla nueva: socia cambia 1 fila y equipo borra 1 (el candado no los toca)'", "'1 · 1'", "n::text || ' · ' || m", "n = 1 and m = 1"),
 "F_F1": fila("'F1 ent_corregir_alisto: el asistente rebota en la guardia'", "'RECHAZA · 42501 El asistente no escribe…'", "r_as", "r_as like '42501%El asistente no escribe%'"),
 "F_F2": fila("'F2 rrhh_resolver_evento: el asistente rebota en la guardia de socias (ya existía)'", "'RECHAZA · Solo una socia…'", "r_as", "r_as like '%Solo una socia%'"),
 "F_F3": fila("'F3 rrhh_calendario: 0 filas al asistente · la socia sigue viendo el suyo'", "'0 · >0'", "n::text || ' · ' || m", "n = 0 and m > 0"),
 "F_F4": fila("'F4 ent_corregir_alisto: a la socia NO la frena la guardia del asistente'", "'cualquier cosa menos la guardia'", "r_so", "r_so not like '%El asistente no escribe%'"),
 "F_D1": fila("'D1 Instinct desactivado (activo=false): sigue siendo asistente y sigue sin escribir'", "'true · (nulo) · RECHAZA asistente_no_inserta'", "b::text || ' · ' || t || ' · ' || left(r_as, 80)", "b and t = '(nulo)' and r_as like '42501%\"asistente_no_inserta\"%'"),
}
N = sum(1 for k in F if not k.endswith("_MAL"))
cuerpo = PRUEBAS % dict(F, TABLAS=TABLAS, COMO_S=COMO("v_socia"), COMO_E=COMO("v_equipo"), COMO_A=COMO("v_asis"), PG=PG, N=N)

ENCAB = """-- ═══════════════════════════════════════════════════════════════════════════
-- %s  ·  12-oct-2026  ·  %s
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
"""

pegado = (ENCAB % ("ASISTENTE_ROL.sql", "⚠ NO SE CORRIÓ — preparado, sin aplicar. Primero el ENSAYO (%d/%d)." % (N, N))
          + "begin;\n" + DDL + CONTROL + "commit;\n")
ensayo = (ENCAB % ("ENSAYO_ASISTENTE_ROL.sql", "ENSAYO EN SECO · NO ESCRIBE NADA (rollback)")
          + "--\n-- CÓMO SE LEE\n--   Una tabla de %d filas, TODAS con ok = true. Un RECHAZA vale solo con el motivo esperado (el error\n"
            "--   trae el nombre de la política o el texto de la guardia). \"Success. No rows returned\" = no llegó al final.\n"
            "--   Prueba con una cuenta de prueba instinct@truefoodcr.com que se crea y se deshace acá adentro.\n" % N
          + "begin;\n" + FOTO + "\n-- ▼▼▼ BLOQUE DDL (copia exacta de ASISTENTE_ROL.sql) ▼▼▼" + DDL + "-- ▲▲▲ FIN BLOQUE DDL ▲▲▲\n"
          + cuerpo + "\nrollback;\n")
open(os.path.join(DEST, "ASISTENTE_ROL.sql"), "w", encoding="utf-8").write(pegado)
open(os.path.join(DEST, "ENSAYO_ASISTENTE_ROL.sql"), "w", encoding="utf-8").write(ensayo)
print("filas esperadas en el ensayo:", N)
