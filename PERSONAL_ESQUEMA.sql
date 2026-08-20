-- ════════════════════════════════════════════════════════════════════════
-- MÓDULO PERSONAL · ESQUEMA SUPABASE   (PEGADO 2 de 3)
-- PROPUESTA 13-ago-2026. **NO PEGAR TODAVÍA** — esto es el STOP de diseño.
-- AMPLIADO 19-ago-2026 con vacaciones y aguinaldo. Sigue el MISMO STOP: no se
-- pega nada hasta que Andrea y Lorena revisen.
-- Va DESPUÉS de ACCESOS_ESQUEMA.sql, que es de donde salen los perfiles.
-- Va después de la pasada visual de Entregas y de Despachos: Daniel arranca
-- el lunes y eso manda.
--
-- QUÉ SE AGREGÓ EL 19-ago (secciones 8 y 9, más la pantalla del equipo):
--   · VACACIONES con saldo CONTINUO desde el ingreso — nunca reinicia en enero.
--   · AGUINALDO anual, transcrito por la socia (no se recalcula la fórmula).
--   · Ya NO hay liquidación anual: Daniel, Neybel y Daniela siguen contratados
--     de forma continua y en diciembre solo se les paga aguinaldo. Sin preaviso
--     ni cesantía cada año. Por eso el `ingreso` de los tres es una fecha FIJA
--     (2026-01-05) y por eso el saldo de vacaciones se acumula sin cortes.
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
   '1:1,5, solo se toca esta constante.', 'semilla'),
  ('vacacion_dias_por_mes', 1.0,
   'Política interna: 1 día por mes trabajado, 12 días/año. Más generoso que el '
   'mínimo legal (Art. 153, ~10 días/50 semanas para jornada de 5 días) — sin '
   'riesgo legal.', 'semilla')
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
-- Un evento = algo que pasó, con fecha y persona. Nueve tipos finales:
--
--   extra                 Hora extra. `destino` decide 150% o banco.      horas
--   permiso_justificado   Con nota médica o del colegio. NO descuenta.    horas
--   permiso_reponer       Salió temprano y repone. Banco en negativo.     horas
--   reposicion            Salda el banco.                                 horas
--   permiso_sin_goce      Descuenta.                                      horas
--   incap_ins             Riesgo del trabajo. El INS cubre.               días
--   incap_ccss            Enfermedad. 3 días al 50%, luego la Caja.       días
--   dia_extra             Feriado o domingo trabajado: doble.             días
--   vacaciones            Descanso ganado. NO genera ajuste de pago.      días
--
-- VACACIONES VA EN DÍAS, no en horas, y por eso entra al mismo grupo que las
-- incapacidades y el día extra en el CHECK de abajo. Se puede tomar poco a poco
-- (un día suelto, tres días, una semana): cada toma es un evento y el saldo de
-- la sección 8 se mueve solo.
--
-- QUIÉN LA REGISTRA (decidido 19-ago-2026): la vacación la SOLICITA la persona
-- y la APRUEBA la socia, exactamente igual que un permiso. Mismo camino que ya
-- existe —`rrhh_evento` para la solicitud, `rrhh_evento_aprob` para el visto
-- bueno— y por eso no hizo falta ni una tabla ni una política nueva:
--   · la política `rrhh_evento_ins` ya deja a cada quien insertar lo suyo;
--   · `rrhh_evento_aprob_ins` ya restringe el aprobar a las socias;
--   · el saldo de la sección 8 lee `v_rrhh_evento`, que solo cuenta lo
--     aprobado y no anulado — así que los días pedidos y todavía sin aprobar
--     NO bajan el saldo, y la solicitud aparece sola en la bandeja de
--     `v_rrhh_solicitud` junto con los permisos y las extras.
-- En el formulario del equipo, vacaciones es una quinta opción gruesa al lado
-- de permiso, salida a reponer, incapacidad y hora extra.
--
-- LO QUE PIDE EL EQUIPO NO ES LO QUE CUENTA. El formulario del equipo tiene
-- cinco opciones gruesas —permiso, salida temprana a reponer, incapacidad,
-- hora extra, vacaciones— porque ellos no pueden saber (ni les toca decidir)
-- si un permiso es con goce o sin goce, si una incapacidad es INS o CCSS, o si
-- una extra se paga o va al banco. Eso lo resuelve la socia AL APROBAR, y queda
-- en la fila de aprobación. Por eso `tipo` acá es lo SOLICITADO y el tipo que
-- cuenta sale de coalesce(aprobación.tipo_final, tipo).
--
-- Vacaciones es la única de las cinco que NO se reclasifica: lo solicitado y lo
-- aprobado son la misma cosa. La socia solo dice sí o no, y por eso puede
-- aprobarla sin tocar `tipo_final` — el coalesce se queda con 'vacaciones'.
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
                  'permiso_sin_goce','incapacidad','incap_ins','incap_ccss','dia_extra',
                  'vacaciones')),
  horas         numeric check (horas > 0),
  dias          integer check (dias > 0),
  destino       text    check (destino in ('pago','banco')),
  motivo        text,                    -- lo escribe quien registra, en una línea
  justificante_path text,                -- ruta en el bucket `justificantes` (ver pegado 3)
  nota          text,
  creado_en     timestamptz not null default now(),
  creado_por    text    not null,

  constraint rrhh_evento_unidad check (
    case when tipo in ('incap_ins','incap_ccss','incapacidad','dia_extra','vacaciones')
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
                  'permiso_sin_goce','incap_ins','incap_ccss','dia_extra',
                  'vacaciones')),
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
--   · las VACACIONES están y son con goce   → no se suma ni se resta: 0
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
         -- 'vacaciones' NO tiene rama a propósito: cae en este ELSE y vale 0.
         -- El día de vacaciones ya viene pagado dentro del salario mensual, así
         -- que no hay diferencia que pasarle a la contadora. Lo que sí se mueve
         -- es el SALDO de la sección 9. No agregar una rama acá.
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


-- ── 8 · VACACIONES — SALDO CONTINUO ─────────────────────────────────────
-- EL SALDO NUNCA REINICIA. No hay corte el 1° de enero, no hay "vacaciones del
-- 2026" y "vacaciones del 2027": hay UN saldo que corre desde el día de ingreso
-- y que sube un poco cada mes y baja cada vez que se toman días. Esto es
-- consecuencia directa de la decisión de no liquidar cada diciembre: si el
-- contrato no se corta, el saldo tampoco.
--
-- CÓMO SE GANA. Un día por mes COMPLETO trabajado (parámetro
-- `vacacion_dias_por_mes`), o sea 12 días al año. Es más de lo que pide el
-- mínimo legal (Art. 153: ~10 días por cada 50 semanas en jornada de 5 días),
-- así que ser más generoso no tiene riesgo legal — el piso es el mínimo, no el
-- máximo.
--
-- POR QUÉ SE SUMA MES A MES Y NO meses × tarifa_de_hoy. El parámetro tiene
-- vigencia, igual que todos los de la sección 1. Si algún día suben la política
-- a 1,25 días/mes, multiplicar el total de meses por el valor nuevo le
-- regalaría retroactivamente días por años ya cumplidos. Sumando el valor
-- vigente EN CADA MES, el cambio de política solo afecta hacia adelante. Hoy,
-- con una sola fila de parámetro, las dos formas dan el mismo número; la
-- diferencia aparece el día que se cambie la regla, que es justo cuando ya
-- nadie se va a acordar de esto.
--
-- ⚠️ NO SE IMPLEMENTA EXPIRACIÓN. NUNCA. Esta vista no resta días por viejos,
-- y no se le va a agregar. Las vacaciones ganadas son plata ganada: no existe
-- forma legal de quitárselas a alguien sin pagarlas. Si algún día alguien pide
-- "que venzan al año", la respuesta es que no, y la razón está en esta línea.
create or replace view v_rrhh_vacacion_saldo with (security_invoker = true) as
with limite as (
  -- HASTA CUÁNDO SE ACUMULA. Normalmente hasta hoy. Pero si la persona está de
  -- baja, la acumulación se CONGELA el día de la baja: quien ya no trabaja no
  -- sigue ganando vacaciones. Sin esto, un saldo viejo seguiría creciendo solo
  -- y nadie lo miraría hasta que hubiera que pagarlo.
  -- Ojo: `rrhh_persona_baja` es solo-socias por RLS, así que corrida por un
  -- empleado esta rama nunca ve una baja. No importa para el caso que existe
  -- —quien está de baja no entra al sistema— pero conviene saberlo antes de
  -- usar esta vista para otra cosa.
  select p.id as persona_id, p.nombre, p.ingreso,
         case when b.fecha is not null and not b.anulada
              then least(b.fecha, current_date)
              else current_date end as hasta
    from rrhh_persona p
    left join lateral (
      select x.fecha, x.anulada from rrhh_persona_baja x
       where x.persona_id = p.id
       order by x.creado_en desc limit 1
    ) b on true
   where p.ingreso is not null
),
acumulado as (
  select l.persona_id,
         l.nombre,
         l.ingreso,
         coalesce(m.meses_completos, 0) as meses_completos,
         coalesce(m.dias_ganados,    0) as dias_ganados
    from limite l
    left join lateral (
      -- Un renglón por mes CUMPLIDO: la serie arranca un mes después del
      -- ingreso, así que el mes en curso todavía no cuenta.
      select count(*)::int as meses_completos,
             sum(rrhh_param('vacacion_dias_por_mes', g.mes::date)) as dias_ganados
        from generate_series(l.ingreso + interval '1 month',
                             l.hasta::timestamp,
                             interval '1 month') as g(mes)
    ) m on true
),
tomadas as (
  -- v_rrhh_evento ya viene filtrada a aprobado y no anulado.
  select v.persona_id, coalesce(sum(v.dias), 0) as dias_tomados
    from v_rrhh_evento v
   where v.tipo = 'vacaciones'
   group by v.persona_id
)
select a.persona_id,
       a.nombre,
       a.ingreso,
       a.meses_completos,
       a.dias_ganados,
       coalesce(t.dias_tomados, 0)                      as dias_tomados,
       a.dias_ganados - coalesce(t.dias_tomados, 0)     as dias_disponibles,
       12 * rrhh_param('vacacion_dias_por_mes', current_date) as dias_periodo,

       -- LA ALERTA: un período entero sin usar (hoy, 12 días). El umbral se
       -- deriva del parámetro y no se escribe "12" a mano, para que cambiar la
       -- política no deje la alerta apuntando a un número viejo.
       (a.dias_ganados - coalesce(t.dias_tomados, 0))
         >= 12 * rrhh_param('vacacion_dias_por_mes', current_date)
                                                        as alerta_acumulacion,

       -- Y su FECHA, que es lo que la convierte en alerta y no en información
       -- (regla 2 del lobby). El Art. 159 prohíbe, como regla general, acumular
       -- más allá de un período: la empresa tiene que PROGRAMAR el descanso
       -- dentro de las 15 semanas siguientes a que se cumple cada ciclo. Esa es
       -- la fecha contra la que corre la alerta — es un recordatorio para las
       -- socias, no un vencimiento del saldo.
       case when a.meses_completos >= 12
            then (a.ingreso + ((a.meses_completos / 12) * interval '12 months'))::date
       end                                              as ciclo_completo_en,
       case when a.meses_completos >= 12
            then (a.ingreso + ((a.meses_completos / 12) * interval '12 months')
                            + interval '15 weeks')::date
       end                                              as programar_antes_de
  from acumulado a
  left join tomadas t on t.persona_id = a.persona_id;

-- ┌ PANTALLA "MIS VACACIONES" (equipo) ────────────────────────────────────┐
-- │ La primera pantalla del módulo pensada para el equipo, no para las      │
-- │ socias. Daniel, Neybel o Daniela entran y ven UN número: los días que   │
-- │ tienen disponibles. Nada más.                                           │
-- │                                                                          │
-- │ NO NECESITA POLÍTICA NUEVA, y eso es lo importante del diseño: la vista │
-- │ es `security_invoker`, lee `rrhh_persona` y `v_rrhh_evento`, y las dos  │
-- │ ya están filtradas por `persona_id = rrhh_mi_persona()`. O sea que la   │
-- │ misma consulta, corrida por Daniela, devuelve UNA fila —la de ella—     │
-- │ y corrida por una socia devuelve las tres. La pantalla no filtra nada:  │
-- │ filtra Supabase, del lado del servidor.                                 │
-- │                                                                          │
-- │ NO MUESTRA PLATA. Solo días. `rrhh_salario` sigue siendo solo-socias y  │
-- │ esta vista no lo toca, así que no hay forma de deducir un salario desde │
-- │ acá. Una superficie sensible menos.                                     │
-- │                                                                          │
-- │ Columnas que dibuja: dias_disponibles (el número grande), y             │
-- │ dias_ganados / dias_tomados como el detalle de cómo se llegó a él.      │
-- │ `alerta_acumulacion` y `programar_antes_de` son para el lobby de las    │
-- │ socias — el equipo no tiene nada que hacer con esa alerta.              │
-- │                                                                          │
-- │ LO PEDIDO Y SIN APROBAR NO BAJA EL SALDO, y eso hay que mostrarlo o se  │
-- │ lee como un error: quien pidió tres días el lunes entra el martes, ve   │
-- │ el saldo igualito y piensa que la solicitud se perdió. La pantalla saca │
-- │ esos días de `v_rrhh_solicitud` (tipo = 'vacaciones', ya filtrada a lo  │
-- │ suyo por RLS) y los muestra como una línea aparte, no restados. Es      │
-- │ ESTADO DEL DATO, no instrucción de uso — entra dentro del estándar.     │
-- └──────────────────────────────────────────────────────────────────────────┘


-- ── 9 · AGUINALDO ───────────────────────────────────────────────────────
-- CAMBIO DE FONDO, 19-ago-2026: se dejó de liquidar en diciembre. Daniel,
-- Neybel y Daniela quedan contratados de forma continua y en diciembre reciben
-- SOLO el aguinaldo — no hay preaviso ni cesantía anual. Por eso esto es una
-- tabla de aguinaldos y no una de liquidaciones.
--
-- NO SE RECALCULA LA FÓRMULA. El aguinaldo es la suma de salarios del período
-- ÷ 12, pero ese cálculo lo hace la contadora con la planilla real —que incluye
-- cosas que este módulo no conoce— y acá se GUARDA EL RESULTADO YA VALIDADO. La
-- socia sube el documento de respaldo y transcribe el monto. Si el sistema
-- recalculara por su cuenta, tendríamos dos números discrepando y ninguna forma
-- de saber cuál se pagó; guardando el que se pagó, siempre cuadra.
--
-- `salario_promedio_periodo` se guarda igual, aunque no se use para calcular:
-- es lo que permite entender un aguinaldo viejo sin ir a buscar la planilla.
create table if not exists rrhh_aguinaldo (
  id                       bigint generated always as identity primary key,
  persona_id               bigint  not null references rrhh_persona(id),
  periodo_desde            date    not null,
  periodo_hasta            date    not null,
  salario_promedio_periodo numeric not null check (salario_promedio_periodo > 0),
  monto_aguinaldo          numeric not null check (monto_aguinaldo > 0),
  documento_path           text,           -- ruta en el bucket `aguinaldos` (pegado 3)
  nota                     text,
  creado_en                timestamptz not null default now(),
  creado_por               text    not null,

  constraint rrhh_aguinaldo_periodo check (periodo_hasta > periodo_desde)
);
create index if not exists rrhh_aguinaldo_persona_idx
  on rrhh_aguinaldo (persona_id, periodo_hasta desc, creado_en desc);

-- Append-only como todo el módulo: corregir un monto mal transcrito es INSERTAR
-- otra fila para el mismo período, no editar la vieja. Esta vista se queda con
-- la más reciente de cada (persona, período) — mismo patrón de "la última
-- manda" que ya usan las aprobaciones y las anulaciones.
create or replace view v_rrhh_aguinaldo with (security_invoker = true) as
select distinct on (a.persona_id, a.periodo_desde, a.periodo_hasta)
       a.id, a.persona_id, p.nombre, a.periodo_desde, a.periodo_hasta,
       a.salario_promedio_periodo, a.monto_aguinaldo, a.documento_path,
       a.nota, a.creado_en, a.creado_por
  from rrhh_aguinaldo a
  join rrhh_persona p on p.id = a.persona_id
 order by a.persona_id, a.periodo_desde, a.periodo_hasta, a.creado_en desc;


-- ── 10 · RLS — ACÁ SÍ HAY LLAVE ─────────────────────────────────────────
-- Regla de oro: socias todo; equipo SOLO SUS PROPIAS FILAS.
alter table rrhh_param             enable row level security;
alter table rrhh_persona           enable row level security;
alter table rrhh_persona_baja      enable row level security;
alter table rrhh_salario           enable row level security;
alter table rrhh_evento            enable row level security;
alter table rrhh_evento_aprob      enable row level security;
alter table rrhh_evento_anulado    enable row level security;
alter table rrhh_quincena_aplicada enable row level security;
alter table rrhh_aguinaldo         enable row level security;

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

-- AGUINALDO: solo socias, de los dos lados. Misma regla que `rrhh_salario` y
-- por la misma razón — `monto_aguinaldo` y `salario_promedio_periodo` SON dato
-- salarial, y el equipo no necesita verlos para usar el módulo. Ojo: acá el
-- empleado no ve ni lo suyo, a diferencia de los eventos. Es a propósito.
drop policy if exists rrhh_aguinaldo_sel on rrhh_aguinaldo;
create policy rrhh_aguinaldo_sel on rrhh_aguinaldo for select to authenticated
  using (acceso_es_socia());
drop policy if exists rrhh_aguinaldo_ins on rrhh_aguinaldo;
create policy rrhh_aguinaldo_ins on rrhh_aguinaldo for insert to authenticated
  with check (acceso_es_socia());

grant select on rrhh_param, rrhh_persona, rrhh_persona_baja, rrhh_salario,
                rrhh_evento, rrhh_evento_aprob, rrhh_evento_anulado,
                rrhh_quincena_aplicada, rrhh_aguinaldo to authenticated;
grant insert on rrhh_evento, rrhh_evento_aprob, rrhh_evento_anulado,
                rrhh_quincena_aplicada, rrhh_aguinaldo to authenticated;
grant select on v_rrhh_evento_estado, v_rrhh_evento, v_rrhh_solicitud,
                v_rrhh_evento_dia, v_rrhh_ajuste_detalle, v_rrhh_ajuste,
                v_rrhh_banco, v_rrhh_vacacion_saldo, v_rrhh_aguinaldo
                to authenticated;

-- Sin update ni delete en ninguna tabla, a propósito: es lo que hace que el
-- append-only sea una propiedad del sistema y no una buena intención.


-- ── 11 · SEMILLA ────────────────────────────────────────────────────────
-- ⚠️ ANDREA: los correos tienen que ser los MISMOS que en acceso_usuario, y los
-- salarios son datos reales — esto va directo al SQL Editor, que es privado.
-- Nunca por chat ni por correo. Los tres correos hay que CONFIRMARLOS con vos
-- antes de insertar; acá quedan como CAMBIAR@… a propósito.
--
-- ⚠️ `ingreso` NO ES DECORATIVO. Es de donde sale todo el saldo de vacaciones
-- (sección 8). Si se inserta mal, el saldo sale mal y nadie lo va a notar hasta
-- que alguien pida días. Los tres arrancan el 2026-01-05 y esa fecha ya NO se
-- mueve cada enero: al no liquidarse en diciembre, el ingreso es fijo y la
-- antigüedad corre continua.
--
-- insert into rrhh_persona (nombre, email, puesto, ingreso, creado_por) values
--   ('Daniel',  'CAMBIAR@…', 'producción', '2026-01-05', 'semilla'),
--   ('Neybel',  'CAMBIAR@…', 'producción', '2026-01-05', 'semilla'),
--   ('Daniela', 'CAMBIAR@…', 'producción', '2026-01-05', 'semilla');
--
-- insert into rrhh_salario (persona_id, salario_mensual, vigente_desde, creado_por)
-- values ((select id from rrhh_persona where nombre='Daniel'), 000000, '2026-01-01', 'semilla');
-- … una por persona.
--
-- COMPROBACIÓN, ya con las tres personas insertadas:
--   select nombre, ingreso, meses_completos, dias_ganados, dias_tomados,
--          dias_disponibles, alerta_acumulacion
--     from v_rrhh_vacacion_saldo order by nombre;
-- Con ingreso 2026-01-05 y sin vacaciones tomadas todavía, al 19-ago-2026 los
-- tres tienen que dar meses_completos = 7 y dias_disponibles = 7. Si da 8, la
-- serie está contando el mes en curso; si da 0, `ingreso` quedó en null.
--
-- El aguinaldo NO se siembra: la primera fila la carga la socia en diciembre,
-- con su documento de respaldo.
