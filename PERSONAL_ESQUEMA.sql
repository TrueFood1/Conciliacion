-- ════════════════════════════════════════════════════════════════════════
-- MÓDULO PERSONAL · ESQUEMA SUPABASE   (PEGADO 2 de 3)
-- PROPUESTA 13-ago-2026. **NO PEGAR TODAVÍA** — esto es el STOP de diseño.
-- Va DESPUÉS de ACCESOS_ESQUEMA.sql, que es de donde salen los perfiles.
-- Va después de la pasada visual de Entregas y de Despachos: Daniel arranca
-- el lunes y eso manda.
--
-- Requiere Postgres 15+ por `security_invoker` en las vistas (Supabase lo es).
--
-- QUÉ ES. RRHH chico para el equipo de producción (Daniel, Daniela, Ney). Solo
-- Supabase, append-only, no toca Odoo. El módulo calcula el AJUSTE al siguiente
-- pago; la planilla la sigue posteando la contadora.
--
-- CÓMO SE USA, en dos manos:
--   · el equipo REGISTRA lo suyo (permiso, salida a reponer, incapacidad, extra)
--     y ve solo lo suyo: sus permisos y su banco de horas;
--   · las socias APRUEBAN, y solo lo aprobado entra al cálculo de la quincena.
--
-- POR QUÉ APPEND-ONLY. Un ajuste de planilla tiene que poder reconstruirse tal
-- como se calculó el día que se aplicó. Si se pudiera editar hacia atrás, el
-- número que la contadora ya posteó dejaría de cuadrar con lo que el sistema
-- muestra hoy. Corregir = anular e insertar de nuevo.
--
-- ⚠️ SENSIBILIDAD. Esto guarda SALARIOS e INCAPACIDADES MÉDICAS de personas que
-- tienen login. Es el dato más delicado de Truefie. El resto de los módulos usa
-- RLS `using (true)` —cualquier sesión autenticada lee todo— y el filtro del
-- lobby es COSMÉTICO, así está declarado en index.html. Acá NO: cada política
-- pregunta por el perfil, y lo hace cumplir Supabase del lado del servidor.
-- Es la primera puerta con llave de verdad del sistema, y es a propósito.
-- ════════════════════════════════════════════════════════════════════════


-- ── 1 · PARÁMETROS DE POLÍTICA ──────────────────────────────────────────
-- Las reglas que pueden cambiar por decisión o por ley viven acá, NO adentro de
-- las vistas. Cambiar de política es insertar una fila, no reescribir SQL.
-- Con vigencia, para que un cambio de regla no reescriba el pasado.
create table if not exists rrhh_param (
  id            bigint generated always as identity primary key,
  clave         text    not null,
  valor         numeric not null,
  vigente_desde date    not null default '2026-01-01',
  nota          text,
  creado_en     timestamptz not null default now(),
  creado_por    text    not null
);
create index if not exists rrhh_param_clave_idx on rrhh_param (clave, vigente_desde desc);

create or replace function rrhh_param(p_clave text, p_fecha date)
returns numeric language sql stable as $$
  select p.valor from rrhh_param p
   where p.clave = p_clave and p.vigente_desde <= p_fecha
   order by p.vigente_desde desc, p.creado_en desc limit 1;
$$;

insert into rrhh_param (clave, valor, nota, creado_por)
select * from (values
  ('jornada_horas',     8.0,  'Jornada diaria de 8 h.', 'semilla'),
  ('dias_mes_tarifa',   30.0, 'Tarifa horaria = salario mensual ÷ 30 ÷ 8.', 'semilla'),
  ('factor_extra',      1.5,  'Hora extra al 150%.', 'semilla'),
  ('factor_dia_extra',  2.0,  'Feriado o domingo trabajado: día doble.', 'semilla'),
  ('ccss_dias_empresa', 3.0,  'Incapacidad CCSS: los primeros 3 días los cubre la empresa.', 'semilla'),
  ('ccss_pct_empresa',  0.5,  'Y los cubre al 50%. Del día 4 en adelante paga la Caja.', 'semilla'),
  ('canje_banco',       1.0,
   'Canje 1:1 por acuerdo interno del equipo. Nota: la ley paga la extra al 150%, '
   'así que en el canje el empleado cede el recargo — si algún día se cambia a '
   '1:1,5, solo se toca esta constante.', 'semilla')
) as v(clave, valor, nota, creado_por)
where not exists (select 1 from rrhh_param p where p.clave = v.clave);


-- ── 2 · LAS PERSONAS ────────────────────────────────────────────────────
-- `email` es el puente con el login: es lo que permite que Daniela vea lo suyo
-- y nada más. Tiene que ser el MISMO correo que en acceso_usuario.
create table if not exists rrhh_persona (
  id          bigint generated always as identity primary key,
  nombre      text not null,
  email       text,                                -- null = persona sin login
  puesto      text,
  ingreso     date,
  creado_en   timestamptz not null default now(),
  creado_por  text not null
);
create unique index if not exists rrhh_persona_email_idx
  on rrhh_persona (lower(email)) where email is not null;

-- Dar de baja = insertar. Nunca se borra una persona: sus eventos viejos tienen
-- que seguir explicando los ajustes que ya se aplicaron.
create table if not exists rrhh_persona_baja (
  id          bigint generated always as identity primary key,
  persona_id  bigint  not null references rrhh_persona(id),
  anulada     boolean not null default false,      -- reingreso = otra fila con true
  fecha       date    not null,
  nota        text,
  creado_en   timestamptz not null default now(),
  creado_por  text not null
);

-- HISTORIA de salario, no salario actual. La tarifa de un evento tiene que ser
-- la vigente EL DÍA DEL EVENTO: si a Ney le suben el salario en setiembre, la
-- extra que hizo en agosto no puede recalcularse al valor nuevo.
create table if not exists rrhh_salario (
  id              bigint generated always as identity primary key,
  persona_id      bigint  not null references rrhh_persona(id),
  salario_mensual numeric not null check (salario_mensual > 0),
  vigente_desde   date    not null,
  nota            text,
  creado_en       timestamptz not null default now(),
  creado_por      text not null
);
create index if not exists rrhh_salario_persona_idx
  on rrhh_salario (persona_id, vigente_desde desc);

-- ¿Qué persona es quien está preguntando? (null si no es del equipo)
create or replace function rrhh_mi_persona() returns bigint
language sql stable security definer set search_path = public as $$
  select p.id from rrhh_persona p
   where lower(p.email) = lower(coalesce(auth.jwt() ->> 'email','')) limit 1;
$$;


-- ── 3 · LOS EVENTOS ─────────────────────────────────────────────────────
-- Un evento = algo que pasó, con fecha y persona. Ocho tipos finales:
--
--   extra                 Hora extra. `destino` decide 150% o banco.      horas
--   permiso_justificado   Con nota médica o del colegio. NO descuenta.    horas
--   permiso_reponer       Salió temprano y repone. Banco en negativo.     horas
--   reposicion            Salda el banco.                                 horas
--   permiso_sin_goce      Descuenta.                                      horas
--   incap_ins             Riesgo del trabajo. El INS cubre.               días
--   incap_ccss            Enfermedad. 3 días al 50%, luego la Caja.       días
--   dia_extra             Feriado o domingo trabajado: doble.             días
--
-- LO QUE PIDE EL EQUIPO NO ES LO QUE CUENTA. El formulario del equipo tiene
-- cuatro opciones gruesas —permiso, salida temprana a reponer, incapacidad,
-- hora extra— porque ellos no pueden saber (ni les toca decidir) si un permiso
-- es con goce o sin goce, si una incapacidad es INS o CCSS, o si una extra se
-- paga o va al banco. Eso lo resuelve la socia AL APROBAR, y queda en la fila de
-- aprobación. Por eso `tipo` acá es lo SOLICITADO y el tipo que cuenta sale de
-- coalesce(aprobación.tipo_final, tipo).
--
-- HORAS vs DÍAS: cada tipo usa una sola unidad y el CHECK lo obliga. Mezclarlas
-- en una columna "cantidad" hacía imposible leer una fila suelta, y un "3" que
-- nadie sabe si son horas o días saca el ajuste mal por un factor de 8.
create table if not exists rrhh_evento (
  id            bigint generated always as identity primary key,
  persona_id    bigint  not null references rrhh_persona(id),
  fecha         date    not null,        -- para incapacidades: el PRIMER día
  tipo          text    not null check (tipo in (
                  'extra','permiso','permiso_justificado','permiso_reponer','reposicion',
                  'permiso_sin_goce','incapacidad','incap_ins','incap_ccss','dia_extra')),
  horas         numeric check (horas > 0),
  dias          integer check (dias > 0),
  destino       text    check (destino in ('pago','banco')),
  motivo        text,                    -- lo escribe quien registra, en una línea
  justificante_path text,                -- ruta en el bucket `justificantes` (ver pegado 3)
  nota          text,
  creado_en     timestamptz not null default now(),
  creado_por    text    not null,

  constraint rrhh_evento_unidad check (
    case when tipo in ('incap_ins','incap_ccss','incapacidad','dia_extra')
         then dias is not null and horas is null
         else horas is not null and dias is null end
  )
);
create index if not exists rrhh_evento_persona_fecha_idx on rrhh_evento (persona_id, fecha);

-- APROBACIÓN. Sin fila = "solicitado". Append-only: rechazar y después aprobar
-- son dos filas, y la más reciente manda. Acá es donde la socia CLASIFICA:
-- convierte el "permiso" genérico en justificado o sin goce, la "incapacidad"
-- en INS o CCSS, y decide si la extra se paga o va al banco.
create table if not exists rrhh_evento_aprob (
  id            bigint generated always as identity primary key,
  evento_id     bigint  not null references rrhh_evento(id),
  aprobado      boolean not null,
  tipo_final    text    check (tipo_final in (
                  'extra','permiso_justificado','permiso_reponer','reposicion',
                  'permiso_sin_goce','incap_ins','incap_ccss','dia_extra')),
  destino_final text    check (destino_final in ('pago','banco')),
  motivo        text,                    -- por qué se rechazó, si se rechazó
  creado_en     timestamptz not null default now(),
  creado_por    text    not null
);
create index if not exists rrhh_evento_aprob_ev_idx on rrhh_evento_aprob (evento_id, creado_en desc);

-- Anular un evento ya aprobado (se registró mal, se cayó el permiso).
create table if not exists rrhh_evento_anulado (
  id          bigint generated always as identity primary key,
  evento_id   bigint  not null references rrhh_evento(id),
  anulada     boolean not null default false,   -- deshacer la anulación: otra fila con true
  motivo      text,
  creado_en   timestamptz not null default now(),
  creado_por  text not null
);
create index if not exists rrhh_evento_anulado_ev_idx on rrhh_evento_anulado (evento_id, creado_en desc);


-- ── 4 · QUINCENA APLICADA ───────────────────────────────────────────────
-- Andrea marca que ya le pasó el ajuste a la contadora. Es lo que APAGA la
-- alerta del lobby, y se apaga por el dato, no por un "marcar como visto".
create table if not exists rrhh_quincena_aplicada (
  id          bigint generated always as identity primary key,
  quincena    text    not null,                  -- '2026-08-Q1'
  anulada     boolean not null default false,
  nota        text,
  creado_en   timestamptz not null default now(),
  creado_por  text not null
);
create index if not exists rrhh_quincena_aplicada_q_idx
  on rrhh_quincena_aplicada (quincena, creado_en desc);

-- Q1 = 1 al 15 · Q2 = 16 al fin de mes.
create or replace function rrhh_quincena(d date) returns text
language sql immutable as $$
  select to_char(d,'YYYY-MM') || case when extract(day from d) <= 15 then '-Q1' else '-Q2' end;
$$;


-- ── 5 · ESTADO DE CADA EVENTO ───────────────────────────────────────────
-- `security_invoker` en TODAS las vistas: sin eso la vista corre con los
-- permisos del dueño y la RLS de las tablas no se aplicaría — Daniela vería
-- a todo el mundo a través de la vista. Es el punto donde este diseño se
-- rompería en silencio, así que va dicho.
create or replace view v_rrhh_evento_estado with (security_invoker = true) as
select e.*,
       p.nombre,
       a.aprobado, a.creado_por as aprobado_por, a.creado_en as aprobado_en,
       an.anulada,
       case when coalesce(an.anulada,false)  then 'anulado'
            when a.aprobado is null          then 'solicitado'
            when a.aprobado                  then 'aprobado'
            else 'rechazado' end            as estado,
       coalesce(a.tipo_final,    e.tipo)    as tipo_efectivo,
       coalesce(a.destino_final, e.destino) as destino_efectivo
  from rrhh_evento e
  join rrhh_persona p on p.id = e.persona_id
  left join lateral (select * from rrhh_evento_aprob x
                      where x.evento_id = e.id order by x.creado_en desc limit 1) a on true
  left join lateral (select * from rrhh_evento_anulado y
                      where y.evento_id = e.id order by y.creado_en desc limit 1) an on true;

-- LO QUE CUENTA: aprobado y no anulado, con la tarifa vigente el día del evento.
create or replace view v_rrhh_evento with (security_invoker = true) as
select v.id, v.persona_id, v.nombre, v.fecha, v.tipo_efectivo as tipo,
       v.destino_efectivo as destino, v.horas, v.dias, v.motivo, v.justificante_path,
       s.salario_mensual,
       s.salario_mensual
         / rrhh_param('dias_mes_tarifa', v.fecha)
         / rrhh_param('jornada_horas',   v.fecha) as tarifa_hora
  from v_rrhh_evento_estado v
  left join lateral (
       select sa.salario_mensual from rrhh_salario sa
        where sa.persona_id = v.persona_id and sa.vigente_desde <= v.fecha
        order by sa.vigente_desde desc, sa.creado_en desc limit 1
  ) s on true
 where v.estado = 'aprobado';

-- LAS SOLICITUDES PENDIENTES: la bandeja de las socias y la fuente de la alerta.
create or replace view v_rrhh_solicitud with (security_invoker = true) as
select id, persona_id, nombre, fecha, tipo, horas, dias, motivo,
       justificante_path, creado_en, creado_por
  from v_rrhh_evento_estado
 where estado = 'solicitado';


-- ── 6 · DÍA POR DÍA ─────────────────────────────────────────────────────
-- Una incapacidad de 10 días NO es un evento de una quincena: son 10 días que
-- pueden caer a caballo del 15. Y la regla de la CCSS ("los primeros 3") se
-- cuenta desde el inicio de LA INCAPACIDAD, no desde el inicio de la quincena
-- ni del mes. Por eso los eventos en días se abren en un renglón por día, cada
-- uno con su número de orden dentro del episodio y su propia quincena.
create or replace view v_rrhh_evento_dia with (security_invoker = true) as
select e.id as evento_id, e.persona_id, e.nombre, e.tipo, e.destino,
       e.motivo, e.tarifa_hora, e.horas,
       e.fecha + (g.i - 1)                as dia,
       g.i                                as dia_n,
       rrhh_quincena(e.fecha + (g.i - 1)) as quincena
  from v_rrhh_evento e
  cross join lateral generate_series(1, coalesce(e.dias, 1)) as g(i);


-- ── 7 · EL AJUSTE DE LA QUINCENA ────────────────────────────────────────
-- SUPUESTO CENTRAL, y hay que decirlo fuerte: el salario mensual YA PAGA todos
-- los días del mes. Este módulo NO recalcula la planilla — calcula solo la
-- DIFERENCIA contra ese salario. De ahí sale todo el resto:
--   · la hora extra NO está en el salario   → se suma completa, al 150%
--   · el feriado trabajado SÍ está, a 1×    → se suma 1× más, para llegar al doble
--   · la incapacidad INS está y no debería  → se resta 1×
--   · la CCSS día 1-3, la empresa paga 50%  → se resta 0,5×
--   · la CCSS día 4+, la paga la Caja       → se resta 1×
--   · el permiso sin goce                   → se resta 1× por hora
-- Si algún día la planilla pasara a construirse desde cero, esta vista cambia
-- entera. Mientras la contadora postee un salario fijo y le sume y le reste,
-- esto es lo correcto.
--
-- ⚠️ Las dos vistas de ajuste son SOLO SOCIAS (`where acceso_es_socia()`), aparte
-- de la RLS. El equipo ve sus permisos y su banco; los ajustes de quincena no.
create or replace view v_rrhh_ajuste_detalle with (security_invoker = true) as
select d.quincena, d.persona_id, d.nombre, d.evento_id, d.tipo, d.destino,
       d.dia, d.dia_n, d.horas, d.tarifa_hora, d.motivo,
       case d.tipo
         when 'extra' then case when d.destino = 'pago'
                then d.horas * d.tarifa_hora * rrhh_param('factor_extra', d.dia)
                else 0 end
         when 'dia_extra' then
                rrhh_param('jornada_horas', d.dia) * d.tarifa_hora
                * (rrhh_param('factor_dia_extra', d.dia) - 1)
         when 'permiso_sin_goce' then -(d.horas * d.tarifa_hora)
         when 'incap_ins' then -(rrhh_param('jornada_horas', d.dia) * d.tarifa_hora)
         when 'incap_ccss' then
                case when d.dia_n <= rrhh_param('ccss_dias_empresa', d.dia)
                     then -(rrhh_param('jornada_horas', d.dia) * d.tarifa_hora
                            * rrhh_param('ccss_pct_empresa', d.dia))
                     else -(rrhh_param('jornada_horas', d.dia) * d.tarifa_hora) end
         else 0
       end as monto
  from v_rrhh_evento_dia d
 where acceso_es_socia();

-- LA SALIDA: una fila por persona y quincena. Es el número que Andrea le pasa
-- a la contadora.
create or replace view v_rrhh_ajuste with (security_invoker = true) as
select quincena, persona_id, nombre,
       coalesce(sum(monto) filter (where monto > 0), 0) as suma,
       coalesce(sum(monto) filter (where monto < 0), 0) as resta,
       coalesce(sum(monto), 0)                          as neto,
       count(distinct evento_id)                        as eventos
  from v_rrhh_ajuste_detalle
 group by quincena, persona_id, nombre;

-- EL BANCO: saldo corriente por persona. NO se guarda en ninguna parte — un
-- saldo guardado se desincroniza el día que se anula un evento viejo.
-- Esta vista sí la ve el equipo (filtrada por RLS a lo suyo).
create or replace view v_rrhh_banco with (security_invoker = true) as
select d.persona_id, d.nombre,
       coalesce(sum(
         case d.tipo
           when 'extra'           then case when d.destino = 'banco'
                                        then d.horas * rrhh_param('canje_banco', d.dia) else 0 end
           when 'permiso_reponer' then -d.horas
           when 'reposicion'      then  d.horas
           else 0 end
       ), 0) as saldo_horas
  from v_rrhh_evento_dia d
 group by d.persona_id, d.nombre;


-- ── 8 · RLS — ACÁ SÍ HAY LLAVE ──────────────────────────────────────────
-- Regla de oro: socias todo; equipo SOLO SUS PROPIAS FILAS.
alter table rrhh_param             enable row level security;
alter table rrhh_persona           enable row level security;
alter table rrhh_persona_baja      enable row level security;
alter table rrhh_salario           enable row level security;
alter table rrhh_evento            enable row level security;
alter table rrhh_evento_aprob      enable row level security;
alter table rrhh_evento_anulado    enable row level security;
alter table rrhh_quincena_aplicada enable row level security;

-- Parámetros: los lee cualquiera del sistema (las vistas los necesitan para
-- calcular el banco). No se insertan desde la herramienta.
drop policy if exists rrhh_param_sel on rrhh_param;
create policy rrhh_param_sel on rrhh_param for select to authenticated
  using (acceso_perfil() is not null);

-- Personas: la socia ve a todas; cada quien se ve a sí mismo.
drop policy if exists rrhh_persona_sel on rrhh_persona;
create policy rrhh_persona_sel on rrhh_persona for select to authenticated
  using (acceso_es_socia() or id = rrhh_mi_persona());

drop policy if exists rrhh_persona_baja_sel on rrhh_persona_baja;
create policy rrhh_persona_baja_sel on rrhh_persona_baja for select to authenticated
  using (acceso_es_socia());

-- SALARIOS: solo socias. Ni siquiera el propio — el banco y los permisos se
-- muestran en horas, así que el equipo nunca necesita ver un salario para usar
-- el módulo, y no mostrarlo es una superficie menos.
drop policy if exists rrhh_salario_sel on rrhh_salario;
create policy rrhh_salario_sel on rrhh_salario for select to authenticated
  using (acceso_es_socia());

-- EVENTOS: la socia ve todo; el empleado ve lo suyo.
drop policy if exists rrhh_evento_sel on rrhh_evento;
create policy rrhh_evento_sel on rrhh_evento for select to authenticated
  using (acceso_es_socia() or persona_id = rrhh_mi_persona());

-- Y registra lo suyo, nada más. `persona_id = rrhh_mi_persona()` es lo que
-- impide que alguien registre un permiso a nombre de otro.
drop policy if exists rrhh_evento_ins on rrhh_evento;
create policy rrhh_evento_ins on rrhh_evento for insert to authenticated
  with check (acceso_es_socia() or persona_id = rrhh_mi_persona());

-- APROBAR ES SOLO DE LAS SOCIAS. Es la política que sostiene todo el flujo: sin
-- esto, cualquiera del equipo se aprueba sus propias horas extra.
drop policy if exists rrhh_evento_aprob_sel on rrhh_evento_aprob;
create policy rrhh_evento_aprob_sel on rrhh_evento_aprob for select to authenticated
  using (acceso_es_socia()
         or exists (select 1 from rrhh_evento e
                     where e.id = evento_id and e.persona_id = rrhh_mi_persona()));
drop policy if exists rrhh_evento_aprob_ins on rrhh_evento_aprob;
create policy rrhh_evento_aprob_ins on rrhh_evento_aprob for insert to authenticated
  with check (acceso_es_socia());

drop policy if exists rrhh_evento_anulado_sel on rrhh_evento_anulado;
create policy rrhh_evento_anulado_sel on rrhh_evento_anulado for select to authenticated
  using (acceso_es_socia()
         or exists (select 1 from rrhh_evento e
                     where e.id = evento_id and e.persona_id = rrhh_mi_persona()));
drop policy if exists rrhh_evento_anulado_ins on rrhh_evento_anulado;
create policy rrhh_evento_anulado_ins on rrhh_evento_anulado for insert to authenticated
  with check (acceso_es_socia());

drop policy if exists rrhh_quincena_aplicada_sel on rrhh_quincena_aplicada;
create policy rrhh_quincena_aplicada_sel on rrhh_quincena_aplicada for select to authenticated
  using (acceso_es_socia());
drop policy if exists rrhh_quincena_aplicada_ins on rrhh_quincena_aplicada;
create policy rrhh_quincena_aplicada_ins on rrhh_quincena_aplicada for insert to authenticated
  with check (acceso_es_socia());

grant select on rrhh_param, rrhh_persona, rrhh_persona_baja, rrhh_salario,
                rrhh_evento, rrhh_evento_aprob, rrhh_evento_anulado,
                rrhh_quincena_aplicada to authenticated;
grant insert on rrhh_evento, rrhh_evento_aprob, rrhh_evento_anulado,
                rrhh_quincena_aplicada to authenticated;
grant select on v_rrhh_evento_estado, v_rrhh_evento, v_rrhh_solicitud,
                v_rrhh_evento_dia, v_rrhh_ajuste_detalle, v_rrhh_ajuste,
                v_rrhh_banco to authenticated;

-- Sin update ni delete en ninguna tabla, a propósito: es lo que hace que el
-- append-only sea una propiedad del sistema y no una buena intención.


-- ── 9 · SEMILLA ─────────────────────────────────────────────────────────
-- ⚠️ ANDREA: los correos tienen que ser los MISMOS que en acceso_usuario, y los
-- salarios son datos reales — esto va directo al SQL Editor, que es privado.
-- Nunca por chat ni por correo.
--
-- insert into rrhh_persona (nombre, email, puesto, creado_por) values
--   ('Daniel',  'CAMBIAR@…', 'producción', 'semilla'),
--   ('Daniela', 'CAMBIAR@…', 'producción', 'semilla'),
--   ('Ney',     'CAMBIAR@…', 'producción', 'semilla');
--
-- insert into rrhh_salario (persona_id, salario_mensual, vigente_desde, creado_por)
-- values ((select id from rrhh_persona where nombre='Daniel'), 000000, '2026-01-01', 'semilla');
-- … una por persona.
