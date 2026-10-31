-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- REFACTURA_AUTO.sql  ·  15-oct-2026  ·  ✅ APLICADO el 15-oct-2026 (noche)
-- Ensayo 33/33 ok · control en el editor 1 · 1 · 2 · 1 · 2 · false · false · verificado desde afuera con pg_lector
-- (usuario sin bypass ni herencia, sin clave todavía; rastro vacío con 7 políticas; solo INSERT en las dos tablas).
-- Re-facturas automáticas (decisión de Andrea, 15-oct: opción B, AUTOMÁTICO)
--
-- QUÉ DEJA
--   · `ent_refactura`: el rastro, append-only. Una fila por factura nueva revisada: pedido, factura vieja
--     y nueva, resultado (`ligada` o `apartada`), las 4 reglas, el motivo en palabras si se apartó, origen
--     «automatico», fecha y firma. Nada se borra ni se cambia.
--   · `truefie_refactura`: el usuario del trabajo programado (GitHub Actions del repo privado). Sin
--     superusuario, sin saltear la RLS, sin heredar nada. Puede SOLAMENTE:
--       - ejecutar `refactura_entregas()` (lectura acotada: pedidos, su factura vigente, lo que salió);
--       - AGREGAR filas en `ent_refactura` y en `ent_pedido_factura`.
--     No puede leer ninguna tabla directo, ni cambiar ni borrar nada.
--   · El vínculo en `ent_pedido_factura` entra SOLO si antes quedó en `ent_refactura` una fila `ligada`
--     que reemplaza a la factura VIGENTE de ese pedido, y la factura nueva no es vigente de otro pedido
--     (`refactura_puede_ligar`). Firma obligatoria: `automatico-refactura`.
--   · Socias y equipo LEEN `ent_refactura` (Pendientes muestra el aviso; «Por preparar» deja afuera lo
--     apartado). Anon no ve nada; nadie más escribe.
--
-- LA CLAVE del usuario NO va acá: se pega aparte UNA línea `alter role … password 'SCRAM-SHA-256$…'` con el
-- verificador (no la clave), y la clave vive solo como secreto del repo privado.
--
-- ANTES DE PEGAR: correr ENSAYO_REFACTURA_AUTO.sql (todas las filas con ok = true).
-- SE PEGA ENTERO: un `begin`, un `commit`, cero `rollback`.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
begin;

-- ═══ DDL · DESDE ACA (ENSAYO_REFACTURA_AUTO.sql copia este bloque tal cual) ═══

-- §0 · CANDADO DE ENTRADA: nada de esto existe todavía (este pegado no pisa nada).
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'truefie_refactura') then
    raise exception 'el rol truefie_refactura ya existe: este pegado no pisa nada';
  end if;
  if to_regclass('public.ent_refactura') is not null then
    raise exception 'ent_refactura ya existe: este pegado no pisa nada';
  end if;
  if exists (select 1 from pg_proc where proname in ('refactura_entregas', 'refactura_puede_ligar')) then
    raise exception 'las funciones de re-factura ya existen: este pegado no pisa nada';
  end if;
end $$;

-- §1 · EL USUARIO. Igual de angosto que truefie_cc.
create role truefie_refactura with login nosuperuser nocreatedb nocreaterole
                                   noinherit nobypassrls noreplication;
grant usage on schema public to truefie_refactura;

-- §2 · EL RASTRO. Append-only: sin políticas de update ni delete para nadie.
create table public.ent_refactura (
  id                   bigint generated always as identity primary key,
  pedido_id            bigint  not null references public.ent_pedido(id),
  factura_vieja_id     integer not null,
  factura_vieja_nombre text,
  factura_nueva_id     integer not null,
  factura_nueva_nombre text,
  resultado            text    not null check (resultado in ('ligada', 'apartada')),
  reglas               jsonb   not null,
  motivo               text,
  origen               text    not null default 'automatico' check (origen = 'automatico'),
  creado_en            timestamptz not null default now(),
  creado_por           text    not null default 'automatico-refactura',
  -- `ligada` solo con las 4 reglas en true y sin motivo; `apartada` siempre con su motivo en palabras.
  constraint ent_refactura_ok check (
    (resultado = 'ligada'   and reglas = '{"a": true, "b": true, "c": true, "d": true}'::jsonb and motivo is null)
 or (resultado = 'apartada' and motivo is not null and length(btrim(motivo)) >= 5)),
  -- Una corrida por hora no duplica: la misma vieja→nueva con el mismo resultado entra una sola vez.
  constraint ent_refactura_una unique (factura_vieja_id, factura_nueva_id, resultado)
);
alter table public.ent_refactura enable row level security;
-- Supabase le da TODO a anon y authenticated en las tablas nuevas de public: se recorta (truncate no
-- pasa por la RLS, así que se saca explícito).
revoke all on table public.ent_refactura from anon;
revoke insert, update, delete, truncate, references, trigger on table public.ent_refactura from authenticated;
grant insert on table public.ent_refactura to truefie_refactura;

create policy ent_refactura_sel on public.ent_refactura
  for select to authenticated using (true);
create policy ent_refactura_ins_auto on public.ent_refactura
  for insert to truefie_refactura
  with check (creado_por = 'automatico-refactura' and origen = 'automatico');

-- §3 · LA GUARDIA DEL VÍNCULO. El vínculo nuevo tiene que reemplazar a la factura VIGENTE del pedido,
-- con su fila `ligada` ya en el rastro, y la factura nueva no puede ser vigente de otro pedido.
create function public.refactura_puede_ligar(p_pedido bigint, p_factura integer)
returns boolean language sql stable security definer set search_path = public as $fn$
  select exists (
           select 1 from public.ent_refactura r
            where r.pedido_id = p_pedido and r.factura_nueva_id = p_factura and r.resultado = 'ligada'
              and r.factura_vieja_id = (select v.factura_id from public.ent_pedido_factura_vigente v
                                         where v.pedido_id = p_pedido))
     and not exists (
           select 1 from public.ent_pedido_factura_vigente v
            where v.factura_id = p_factura and not v.anulado);
$fn$;
revoke all on function public.refactura_puede_ligar(bigint, integer) from public, anon, authenticated;
grant execute on function public.refactura_puede_ligar(bigint, integer) to truefie_refactura;

grant insert on table public.ent_pedido_factura to truefie_refactura;
create policy ent_pedido_factura_ins_refactura on public.ent_pedido_factura
  for insert to truefie_refactura
  with check (creado_por = 'automatico-refactura' and anulado = false
              and public.refactura_puede_ligar(pedido_id, factura_id));

-- §4 · LO QUE EL TRABAJO LEE, Y NADA MÁS: por pedido con alisto, su factura vigente, todas las que tuvo,
-- si está entregado, lo que salió del congelador por producto (alisto vigente − no entregado) y lo que
-- ya se revisó en el rastro.
create function public.refactura_entregas()
returns table (pedido_id bigint, factura_vigente integer, facturas integer[], entregado boolean,
               salio jsonb, revisadas jsonb)
language sql stable security definer set search_path = public as $fn$
  select e.pedido_id,
         fv.factura_id,
         (select array_agg(distinct f.factura_id) from public.ent_pedido_factura f where f.pedido_id = e.pedido_id),
         e.estado = 'entregado',
         (select coalesce(jsonb_object_agg(x.producto_id, x.uds), '{}'::jsonb)
            from (select l.producto_id, sum(l.cant_uds - coalesce(l.cant_no_entregada, 0)) as uds
                    from public.ent_alisto_linea l
                   where l.alisto_id = e.alisto_id and not coalesce(l.no_se_entrega, false)
                   group by l.producto_id) x),
         (select coalesce(jsonb_agg(jsonb_build_object('vieja', r.factura_vieja_id, 'nueva', r.factura_nueva_id,
                                                       'resultado', r.resultado)), '[]'::jsonb)
            from public.ent_refactura r where r.pedido_id = e.pedido_id)
    from public.v_ent_pedido_estado e
    left join public.ent_pedido_factura_vigente fv on fv.pedido_id = e.pedido_id;
$fn$;
revoke all on function public.refactura_entregas() from public, anon, authenticated;
grant execute on function public.refactura_entregas() to truefie_refactura;

-- ═══ DDL · HASTA ACA ═══

-- 🔴 LA PRUEBA DE QUE ENTRÓ, ADENTRO DE LA TRANSACCIÓN Y JUSTO ANTES DEL COMMIT.
select (select count(*) from pg_roles where rolname = 'truefie_refactura'
          and rolcanlogin and not rolsuper and not rolbypassrls and not rolinherit)                     as rol,
       (select count(*) from pg_class where oid = 'public.ent_refactura'::regclass and relrowsecurity)  as tabla_con_rls,
       (select count(*) from pg_policies where tablename = 'ent_refactura'
          and policyname in ('ent_refactura_sel', 'ent_refactura_ins_auto'))                             as politicas_rastro,
       (select count(*) from pg_policies where tablename = 'ent_pedido_factura'
          and policyname = 'ent_pedido_factura_ins_refactura')                                           as politica_vinculo,
       (select count(*) from pg_proc where proname in ('refactura_entregas', 'refactura_puede_ligar')
          and prosecdef)                                                                                 as funciones,
       has_table_privilege('truefie_refactura', 'public.ent_pedido', 'select')                           as lee_pedidos_directo,
       has_table_privilege('anon', 'public.ent_refactura', 'select')                                     as anon_ve_rastro;
-- ESPERADO: 1 · 1 · 2 · 1 · 2 · false · false

commit;
