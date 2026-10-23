-- ════════════════════════════════════════════════════════════════════════
-- COBRO_GRUPO_ENLACE · enlaces de invitación de los grupos de WhatsApp de cobro
-- APLICADO en producción por Andrea (23-oct-2026, b121). Control: t·8·0·0·DELETE,INSERT,SELECT,UPDATE·0.
-- Verificado desde afuera con pg_lector: la tabla existe, RLS t, 4 restrictivas del asistente
-- + 4 propias, sin asistente_ve_todo. esquema_check y sonda_front en verde.
-- [Origen: chat «Retomar 23-oct» + consulta de Instinct «Diseño CRM WA Cobros»]
--
-- Qué guarda: UNA fila por grupo de cobro. `partner_id` es el contacto del grupo en
-- Odoo (hijo de la ficha del cliente, tipo «Otro», etiquetas WA Cobros + WA Grupo).
-- El enlace vive SOLO acá, nunca en Odoo (decisión 6 de Andrea, 23-oct).
--
-- Quién: SOLO las dos socias leen, cargan, reemplazan y borran (acceso_es_socia(), T-148).
--   ⚠ Excepción deliberada a «Instinct ve todo» (13-oct): el event trigger
--   `asistente_politicas` le crea a toda tabla nueva la permisiva `asistente_ve_todo`.
--   Acá se BORRA, porque la decisión 6 dice que los enlaces los ven solo las socias.
--   Las cuatro restrictivas del asistente (no_inserta/no_actualiza/no_borra/lee) quedan.
--   Las políticas automáticas NO se escriben a mano (chocan con 42710): se cuentan.
--
-- Sin historial a propósito: un enlace reemplazado o borrado no tiene que quedar en
-- ninguna parte. El valor nunca va a logs, tickets, bitácora, BUILD ni commits.
--
-- CÓMO SE PEGA: una sola transacción con su control adentro, antes del commit.
-- Si el control no sale, no hubo cambio.
-- ════════════════════════════════════════════════════════════════════════

begin;

create table public.cobro_grupo_enlace (
  partner_id     bigint primary key check (partner_id > 0),
  enlace         text not null
                 check (enlace ~ '^https://chat\.whatsapp\.com/(invite/)?[A-Za-z0-9]{10,40}$'),
  actualizado_por text not null default (auth.jwt() ->> 'email'),
  actualizado_en timestamptz not null default now()
);

alter table public.cobro_grupo_enlace enable row level security;   -- ya lo prende ensure_rls; no estorba

revoke all on public.cobro_grupo_enlace from anon, authenticated;
grant select, insert, update, delete on public.cobro_grupo_enlace to authenticated;

drop policy asistente_ve_todo on public.cobro_grupo_enlace;

create policy cobro_grupo_enlace_sel on public.cobro_grupo_enlace
  for select to authenticated using (acceso_es_socia());
create policy cobro_grupo_enlace_ins on public.cobro_grupo_enlace
  for insert to authenticated
  with check (acceso_es_socia() and actualizado_por = (auth.jwt() ->> 'email'));
create policy cobro_grupo_enlace_upd on public.cobro_grupo_enlace
  for update to authenticated using (acceso_es_socia())
  with check (acceso_es_socia() and actualizado_por = (auth.jwt() ->> 'email'));
create policy cobro_grupo_enlace_del on public.cobro_grupo_enlace
  for delete to authenticated using (acceso_es_socia());

-- Control (tiene que decir): rls t · politicas 8 (4 restrictivas del asistente + 4 propias) ·
--   ve_todo 0 · grants_anon 0 · grants_authenticated DELETE,INSERT,SELECT,UPDATE · filas 0
select (select relrowsecurity from pg_class where oid = 'public.cobro_grupo_enlace'::regclass) as rls,
       (select count(*) from pg_policy where polrelid = 'public.cobro_grupo_enlace'::regclass) as politicas,
       (select count(*) from pg_policy where polrelid = 'public.cobro_grupo_enlace'::regclass
          and polname = 'asistente_ve_todo') as ve_todo,
       (select count(*) from information_schema.role_table_grants
         where table_name = 'cobro_grupo_enlace' and grantee = 'anon') as grants_anon,
       (select string_agg(distinct privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
         where table_name = 'cobro_grupo_enlace' and grantee = 'authenticated') as grants_authenticated,
       (select count(*) from public.cobro_grupo_enlace) as filas;

commit;

-- DESHACER (solo si hace falta, y antes de que haya enlaces cargados):
--   drop table public.cobro_grupo_enlace;
