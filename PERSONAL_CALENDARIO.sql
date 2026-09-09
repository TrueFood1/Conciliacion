-- ════════════════════════════════════════════════════════════════════════
-- MÓDULO PERSONAL · CALENDARIO DE AUSENCIAS   (PEGADO 4 de 4)
-- 8-set-2026. Va DESPUÉS de ACCESOS_ESQUEMA.sql (pegado 1) y de
-- PERSONAL_ESQUEMA.sql (pegado 2): usa acceso_es_socia(), acceso_perfil(),
-- rrhh_mi_persona(), rrhh_persona y rrhh_evento, y sin ellos se cae en la
-- primera política.
--
-- QUÉ AGREGA
--   · rrhh_permiso   — permisos como CATEGORÍA APARTE de vacaciones. No toca
--                      rrhh_evento, no descuenta días, no entra al saldo.
--   · rrhh_feriado   — feriados y cierres de planta. Los días que la fábrica
--                      no abre.
--   · v_rrhh_calendario — la capa que hacía falta para que el calendario
--                      exista: quién está fuera, qué día y en qué estado, de
--                      TODO el equipo. Es la primera lectura cruzada del
--                      módulo y por eso es la parte delicada de este pegado.
--   · rrhh_resolver_evento() — aprobar/rechazar una vacación resolviendo la
--                      carrera entre las dos socias EN LA ESCRITURA.
--
-- QUÉ NO TOCA, a propósito: el saldo de vacaciones (sección 8 del pegado 2),
-- v_rrhh_ajuste, rrhh_salario, y las políticas que ya existían. Lo único que
-- cambia de lo viejo es un `revoke` sobre rrhh_evento_aprob, explicado abajo.
--
-- ⚠️ SENSIBILIDAD — LA DECISIÓN CENTRAL DE ESTE PEGADO.
-- Hasta hoy cada quien leía SOLO lo suyo. Un calendario compartido rompe eso
-- por definición: para dibujar "el jueves no está Daniela" hay que dejar que
-- Daniel lea una fila de Daniela. La pregunta no es SI se abre, es CUÁNTO.
-- Lo que se abre, y nada más:
--     persona · fecha · tipo (vacación / permiso / cerrado) · estado
-- Lo que NO sale nunca de la puerta, aunque la fila sea de la misma persona:
--     motivo · justificante · salario · horas · INCAPACIDADES.
-- Las incapacidades médicas ni siquiera entran al calendario: no son una de
-- las cinco capas pedidas, y son el dato más delicado del sistema. Un permiso
-- dice "no está"; una incapacidad dice por qué, y eso no es del equipo.
-- El motivo del permiso queda PRIVADO (decisión de Andrea, 8-set-2026): lo ven
-- quien lo pidió y las socias. En el calendario un permiso dice "Permiso" y
-- el nombre, punto — porque el motivo es texto libre y ahí alguien va a
-- escribir "cita médica de mi hija", que es dato de la misma familia que una
-- incapacidad.
-- ════════════════════════════════════════════════════════════════════════


-- ── 1 · PERMISOS ────────────────────────────────────────────────────────
-- POR QUÉ UNA TABLA NUEVA Y NO UN TIPO MÁS EN rrhh_evento. Los eventos de
-- rrhh_evento existen para una sola cosa: calcular el AJUSTE de la quincena.
-- Cada tipo de ahí suma o resta plata (o días de vacaciones). Este permiso no
-- hace ninguna de las dos: no descuenta días, no mueve el banco de horas, no
-- toca el saldo. Meterlo en rrhh_evento obligaría a agregarle un tipo neutro a
-- la vista del ajuste y a que alguien, en seis meses, se pregunte por qué hay
-- un tipo que no hace nada. Es una categoría distinta y vive aparte.
--
-- Y POR QUÉ ESTA SÍ TIENE COLUMNA `estado` mientras rrhh_evento no.
-- rrhh_evento es append-only porque de él se reconstruye un número que la
-- contadora YA POSTEÓ: si se pudiera editar hacia atrás, el ajuste de agosto
-- dejaría de cuadrar con lo que se pagó en agosto. De un permiso no se
-- reconstruye ninguna plata. Sin esa carga, un `estado` con transición de una
-- sola vía es más simple de leer y —esto es lo que decide— deja que la carrera
-- entre las dos socias la resuelva Postgres en el UPDATE, que es donde tiene
-- que resolverse. Ver la sección 4.
create table if not exists rrhh_permiso (
  id            bigint generated always as identity primary key,
  persona_id    bigint not null references rrhh_persona(id),
  fecha_inicio  date   not null,
  fecha_fin     date   not null,
  motivo        text,                    -- texto libre. PRIVADO: ver el encabezado.
  estado        text   not null default 'pendiente'
                       check (estado in ('pendiente','aprobado','rechazado')),
  resolucion_nota text,                  -- por qué se rechazó, si se rechazó
  resuelto_por  text,
  resuelto_en   timestamptz,
  creado_en     timestamptz not null default now(),
  creado_por    text not null,

  constraint rrhh_permiso_rango  check (fecha_fin >= fecha_inicio),
  -- Pendiente y resuelto son estados EXCLUYENTES, y el CHECK lo obliga: una
  -- fila 'aprobado' sin resuelto_por es un permiso que nadie aprobó, y una
  -- 'pendiente' con resuelto_por es una resolución a medio escribir. Ninguna
  -- de las dos se puede mirar y entender.
  constraint rrhh_permiso_resuelto check (
    (estado = 'pendiente' and resuelto_por is null and resuelto_en is null) or
    (estado <> 'pendiente' and resuelto_por is not null and resuelto_en is not null))
);
create index if not exists rrhh_permiso_persona_idx on rrhh_permiso (persona_id, fecha_inicio desc);
create index if not exists rrhh_permiso_pend_idx    on rrhh_permiso (estado, fecha_inicio) where estado = 'pendiente';

-- QUIÉN RESOLVIÓ Y CUÁNDO LO ESCRIBE EL SERVIDOR, NO EL NAVEGADOR. Si el
-- cliente mandara `resuelto_por`, cualquiera con la anon key podría firmar una
-- aprobación con el nombre de la otra socia. Sale del JWT, que es lo único que
-- el navegador no puede inventar. Y `now()` es el reloj de Postgres: el del
-- teléfono de Daniel puede estar cuatro días corrido y nadie lo notaría.
create or replace function rrhh_permiso_sella() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.estado is distinct from old.estado and new.estado <> 'pendiente' then
    new.resuelto_por := coalesce(auth.jwt() ->> 'email', 'desconocido');
    new.resuelto_en  := now();
  end if;
  return new;
end $$;

drop trigger if exists rrhh_permiso_sella_tg on rrhh_permiso;
create trigger rrhh_permiso_sella_tg before update on rrhh_permiso
  for each row execute function rrhh_permiso_sella();


-- ── 2 · DÍAS CERRADOS ───────────────────────────────────────────────────
-- Feriados de ley y cierres de planta. Dos cosas distintas con la misma
-- consecuencia —la fábrica no abre— y por eso una sola tabla con `tipo`.
--
-- `fecha_fin` NO ESTABA EN EL PEDIDO Y SE AGREGÓ. El cierre de fin de año son
-- 25 días corridos: sin rango, son 25 filas que hay que borrar de a una para
-- corregir un día, y el CRUD de la pantalla se vuelve una lista ilegible. Con
-- rango, el cierre es UNA fila que se edita como una sola cosa. Un feriado
-- suelto deja `fecha_fin` en null y se lee como el día solo.
--
-- ESTA TABLA SÍ SE EDITA Y SE BORRA, a diferencia de todo el resto del módulo.
-- No es una excepción por comodidad: el append-only del pegado 2 existe para
-- poder reconstruir un pago ya hecho. De un feriado no cuelga ningún pago —es
-- un calendario, y un calendario con la fecha equivocada tachada y vuelta a
-- escribir al lado no es historia, es un calendario roto.
create table if not exists rrhh_feriado (
  id          bigint generated always as identity primary key,
  fecha       date not null,
  fecha_fin   date,                      -- null = un solo día
  descripcion text not null,
  tipo        text not null default 'feriado' check (tipo in ('feriado','cierre')),
  creado_en   timestamptz not null default now(),
  creado_por  text not null,

  constraint rrhh_feriado_rango check (fecha_fin is null or fecha_fin >= fecha),
  -- DOS DÍAS CERRADOS NO SE PUEDEN PISAR. Sin esto, "15 set" cargado dos veces
  -- pinta dos veces el mismo día del calendario y nadie sabe cuál borrar; y un
  -- feriado adentro del cierre de fin de año es un día contado dos veces el día
  -- que esto alimente el costeo. Lo impide Postgres, no la pantalla.
  constraint rrhh_feriado_sin_solape exclude using gist (
    daterange(fecha, coalesce(fecha_fin, fecha), '[]') with &&)
);
create index if not exists rrhh_feriado_fecha_idx on rrhh_feriado (fecha);


-- ── 3 · EL CALENDARIO — LA ÚNICA PUERTA QUE MIRA A TODOS ────────────────
-- ⚠️ ACÁ ESTÁ EL RIESGO DE ESTE PEGADO, ASÍ QUE VA DICHO ENTERO.
--
-- El problema: las políticas de rrhh_evento y rrhh_permiso dicen "socia o lo
-- tuyo". Una vista `security_invoker` encima de ellas hereda ese recorte, así
-- que corrida por Daniel devolvería SOLO las filas de Daniel — o sea, no hay
-- calendario. Y la salida fácil —ensanchar la política del select— abre la
-- TABLA ENTERA: `grant select on rrhh_evento to authenticated` ya existe, así
-- que ensanchar la política le entrega a todo el equipo el `motivo` y el
-- `justificante_path` de las incapacidades de los demás. Eso no se hace.
--
-- La salida correcta es que el ensanche viva en UN SOLO lugar, explícito y
-- angosto: esta función `security definer`, cuya LISTA DE COLUMNAS es toda la
-- protección. Lo que no está en el `select` de abajo no existe para el
-- calendario, y no hay forma de pedirlo desde afuera.
--
-- ¿No es esto la fuga del 24-ago otra vez? No, y la diferencia importa:
--   · aquella era una vista que devolvía TODAS las columnas de la tabla y a la
--     que le faltaba `security_invoker` por olvido — nadie decidió abrirla;
--   · esta abre a propósito CUATRO campos que no son sensibles, tiene puerta
--     (`acceso_perfil() is null` → no devuelve nada, así que sin login no hay
--     nada que leer) y está revocada para `anon` por los dos lados, la función
--     y la vista.
-- Y la regla del proyecto se cumple al pie: la vista `v_rrhh_calendario` lleva
-- `security_invoker = true`, como TODA vista de este módulo. Lo que la vista
-- expone es el resultado de una función que ya decidió, adentro, qué se puede
-- ver.
--
-- LO QUE NO ENTRA, y conviene leerlo como una lista de decisiones y no como un
-- olvido: incapacidades (ni INS ni CCSS), horas extra, permisos de horas del
-- pegado 2, el motivo de nada, salarios, adjuntos. El calendario contesta
-- "¿quién no está el jueves?" y ninguna otra pregunta.
create or replace function rrhh_calendario()
returns table (
  fuente     text,      -- 'vacacion' · 'permiso' · 'feriado' · 'cierre'
  ref_id     bigint,    -- id en su tabla de origen (para aprobar / editar)
  persona_id bigint,    -- null en los días cerrados
  nombre     text,
  fecha      date,
  fecha_fin  date,      -- inclusivo: un día suelto trae fecha_fin = fecha
  estado     text,      -- 'aprobado' · 'pendiente'
  etiqueta   text       -- descripción del día cerrado; null en lo demás
)
language plpgsql stable security definer set search_path = public as $$
begin
  -- LA PUERTA. Sin perfil no hay calendario: ni anon, ni una cuenta que exista
  -- en auth pero no en acceso_usuario. Devuelve cero filas, no un error — un
  -- error acá le diría a quien sondea que del otro lado hay algo.
  if acceso_perfil() is null then return; end if;

  return query
  -- VACACIONES. Del pegado 2, sin tocarlo. Se repite acá la lógica de "la
  -- última aprobación manda" en vez de leer v_rrhh_evento_estado a propósito:
  -- esa vista trae la fila COMPLETA (`e.*`, con motivo y justificante), y
  -- adentro de una función `security definer` seleccionar de más es
  -- exactamente el error que este bloque entero viene a evitar.
  select 'vacacion'::text, e.id, e.persona_id, p.nombre,
         e.fecha, (e.fecha + (coalesce(e.dias,1) - 1))::date,
         case when a.aprobado then 'aprobado' else 'pendiente' end,
         null::text
    from rrhh_evento e
    join rrhh_persona p on p.id = e.persona_id
    left join lateral (select x.aprobado, x.tipo_final from rrhh_evento_aprob x
                        where x.evento_id = e.id order by x.creado_en desc limit 1) a on true
    left join lateral (select y.anulada from rrhh_evento_anulado y
                        where y.evento_id = e.id order by y.creado_en desc limit 1) an on true
   where coalesce(a.tipo_final, e.tipo) = 'vacaciones'
     and not coalesce(an.anulada, false)
     and (a.aprobado is null or a.aprobado)      -- lo rechazado no pinta el calendario

  union all
  -- PERMISOS. Sin `motivo` — ver el encabezado.
  select 'permiso'::text, pm.id, pm.persona_id, p.nombre,
         pm.fecha_inicio, pm.fecha_fin, pm.estado, null::text
    from rrhh_permiso pm
    join rrhh_persona p on p.id = pm.persona_id
   where pm.estado in ('pendiente','aprobado')

  union all
  -- DÍAS CERRADOS. No son de nadie: sin persona y siempre firmes.
  select f.tipo, f.id, null::bigint, null::text,
         f.fecha, coalesce(f.fecha_fin, f.fecha), 'aprobado'::text, f.descripcion
    from rrhh_feriado f;
end $$;

-- La vista es lo que consulta la herramienta (y lo que ve esquema_check.py,
-- que solo mira los `from('...')` del index.html — una función llamada por
-- rpc() le sería invisible).
create or replace view v_rrhh_calendario with (security_invoker = true) as
  select * from rrhh_calendario();

-- MIS PERMISOS / LA BANDEJA. Esta sí es angosta por RLS y no por lista de
-- columnas: acá el `motivo` SÍ va, porque la política de abajo ya la recortó a
-- "lo tuyo o, si sos socia, todo".
create or replace view v_rrhh_permiso with (security_invoker = true) as
select pm.id, pm.persona_id, p.nombre, pm.fecha_inicio, pm.fecha_fin,
       (pm.fecha_fin - pm.fecha_inicio + 1) as dias,
       pm.motivo, pm.estado, pm.resolucion_nota, pm.resuelto_por, pm.resuelto_en,
       pm.creado_en, pm.creado_por
  from rrhh_permiso pm
  join rrhh_persona p on p.id = pm.persona_id;


-- ── 4 · RESOLVER SIN PISARSE ────────────────────────────────────────────
-- Andrea y Lorena aprueban las dos, sin jerarquía. Entonces las dos pueden
-- abrir la misma solicitud y decidir distinto con dos minutos de diferencia —
-- y la que llegue segunda no tiene forma de saber que ya se resolvió.
--
-- LA UI NO PUEDE RESOLVER ESTO. Refrescar la lista antes de mostrar el botón
-- solo achica la ventana; siempre queda el instante entre que se dibuja la
-- pantalla y se toca el botón. Se resuelve en la escritura o no se resuelve.
--
-- PARA PERMISOS no hace falta nada especial: la política `rrhh_permiso_upd`
-- de la sección 5 lleva `estado = 'pendiente'` adentro del USING, así que un
-- permiso ya resuelto deja de ser una fila actualizable y el UPDATE devuelve
-- CERO FILAS en vez de pisar la decisión de la otra. Postgres re-evalúa esa
-- condición contra la versión nueva de la fila después de soltar el lock, así
-- que dos UPDATE simultáneos dan exactamente un ganador. La herramienta manda
-- además `estado = 'pendiente'` en el WHERE: dos candados, uno del servidor y
-- otro del cliente, para que el contrato "0 filas = ya lo resolvió la otra"
-- sea legible desde los dos lados.
--
-- PARA VACACIONES no se puede usar el mismo camino: rrhh_evento no tiene
-- columna `estado` —el estado sale de rrhh_evento_aprob, append-only— y darle
-- una sería romper el append-only del que cuelga la reconstrucción de la
-- planilla. La misma garantía se consigue con esta función: si el evento ya
-- tiene una resolución, NO inserta y devuelve cero filas. Mismo contrato que
-- el UPDATE de permisos, así que la herramienta trata los dos casos igual.
--
-- El lock consultivo es lo que cierra el último milímetro: dos socias que
-- tocan "Aprobar" en el mismo instante pasarían las dos por el `exists` (cada
-- transacción no ve la fila sin confirmar de la otra) e insertarían las dos.
-- Con el lock, la segunda espera, vuelve a mirar y se encuentra la resolución
-- de la primera.
--
-- SECURITY INVOKER (el default, y por eso NO dice `security definer`): quién
-- puede aprobar lo sigue decidiendo la RLS de rrhh_evento_aprob, no esta
-- función. Un empleado que la llame se estrella contra `rrhh_evento_aprob_ins`
-- igual que si insertara a mano.
create or replace function rrhh_resolver_evento(
  p_evento_id     bigint,
  p_aprobado      boolean,
  p_tipo_final    text default null,     -- null = se queda el tipo solicitado
  p_destino_final text default null,
  p_motivo        text default null)
returns table (id bigint, evento_id bigint, aprobado boolean,
               creado_por text, creado_en timestamptz)
language plpgsql set search_path = public as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('rrhh_evento_aprob:' || p_evento_id, 0));

  if exists (select 1 from rrhh_evento_aprob a where a.evento_id = p_evento_id) then
    return;                                  -- 0 filas = ya estaba resuelto
  end if;

  -- El INSERT va adentro de un CTE y no suelto detrás del `return query`. Las dos
  -- formas hacen lo mismo, pero esta es indiscutiblemente un SELECT: no depende
  -- de que `return query` acepte una sentencia que escribe, y de paso los
  -- nombres salen calificados por `ins`, sin poder chocar con los parámetros de
  -- salida de la función, que se llaman igual (id, evento_id, aprobado…).
  return query
  with ins as (
    insert into rrhh_evento_aprob (evento_id, aprobado, tipo_final, destino_final,
                                   motivo, creado_por)
    values (p_evento_id, p_aprobado, p_tipo_final, p_destino_final, p_motivo,
            coalesce(auth.jwt() ->> 'email', 'desconocido'))
    returning rrhh_evento_aprob.id, rrhh_evento_aprob.evento_id,
              rrhh_evento_aprob.aprobado, rrhh_evento_aprob.creado_por,
              rrhh_evento_aprob.creado_en
  )
  select ins.id, ins.evento_id, ins.aprobado, ins.creado_por, ins.creado_en from ins;
end $$;


-- ── 5 · RLS ─────────────────────────────────────────────────────────────
alter table rrhh_permiso enable row level security;
alter table rrhh_feriado enable row level security;

-- PERMISOS · leer: la socia todo, cada quien lo suyo. Misma regla que
-- rrhh_evento, y por la misma razón: acá vive el `motivo`.
drop policy if exists rrhh_permiso_sel on rrhh_permiso;
create policy rrhh_permiso_sel on rrhh_permiso for select to authenticated
  using (acceso_es_socia() or persona_id = rrhh_mi_persona());

-- PERMISOS · pedir: lo suyo, y SIEMPRE pendiente. El `estado = 'pendiente'`
-- del with check es lo que impide que alguien se auto-apruebe insertando la
-- fila ya aprobada — sin esa línea, la política de update de abajo no protege
-- nada, porque no haría falta pasar por ella.
drop policy if exists rrhh_permiso_ins on rrhh_permiso;
create policy rrhh_permiso_ins on rrhh_permiso for insert to authenticated
  with check ((acceso_es_socia() or persona_id = rrhh_mi_persona())
              and estado = 'pendiente');

-- PERMISOS · resolver: solo socias, solo lo pendiente, y solo hacia un estado
-- final. Las tres condiciones en una política, que es donde se hacen cumplir.
-- Ojo con la asimetría entre USING y WITH CHECK: USING mira la fila VIEJA (por
-- eso 'pendiente') y WITH CHECK la NUEVA (por eso ya no puede serlo). Esto
-- convierte la resolución en una transición de una sola vía: lo aprobado no se
-- vuelve a tocar ni por la otra socia ni por la misma.
drop policy if exists rrhh_permiso_upd on rrhh_permiso;
create policy rrhh_permiso_upd on rrhh_permiso for update to authenticated
  using      (acceso_es_socia() and estado = 'pendiente')
  with check (acceso_es_socia() and estado in ('aprobado','rechazado'));

-- DÍAS CERRADOS · los lee cualquiera del módulo: no son de nadie y el
-- calendario los necesita. Los administran las socias.
drop policy if exists rrhh_feriado_sel on rrhh_feriado;
create policy rrhh_feriado_sel on rrhh_feriado for select to authenticated
  using (acceso_perfil() is not null);
drop policy if exists rrhh_feriado_ins on rrhh_feriado;
create policy rrhh_feriado_ins on rrhh_feriado for insert to authenticated
  with check (acceso_es_socia());
drop policy if exists rrhh_feriado_upd on rrhh_feriado;
create policy rrhh_feriado_upd on rrhh_feriado for update to authenticated
  using (acceso_es_socia()) with check (acceso_es_socia());
drop policy if exists rrhh_feriado_del on rrhh_feriado;
create policy rrhh_feriado_del on rrhh_feriado for delete to authenticated
  using (acceso_es_socia());


-- ── 6 · GRANTS Y REVOKES ────────────────────────────────────────────────
-- Antes del login no hay nada acá que leer. Supabase le regala `select` a
-- `anon` sobre todo lo que nace en `public`, así que esto no es decoración:
-- sin el revoke, `rrhh_permiso` y el calendario contestan por REST con la anon
-- key, que va publicada dentro de index.html.
revoke all on rrhh_permiso, rrhh_feriado, v_rrhh_calendario, v_rrhh_permiso from anon;

-- Y a las FUNCIONES también. `execute` se le da a PUBLIC por defecto, o sea
-- que sin este revoke cualquiera con la anon key llama a rrhh_calendario() por
-- rpc y se saltea el revoke de arriba — la puerta de adentro (acceso_perfil()
-- is null → cero filas) igual lo frena, pero no conviene depender de una sola
-- capa. Es la lección del 24-ago.
revoke all on function rrhh_calendario()      from anon, public;
revoke all on function rrhh_resolver_evento(bigint, boolean, text, text, text)
                                              from anon, public;

grant select on rrhh_permiso, rrhh_feriado, v_rrhh_calendario, v_rrhh_permiso
  to authenticated;
grant insert on rrhh_permiso, rrhh_feriado to authenticated;
-- UPDATE POR COLUMNA, no por tabla. Es lo que hace imposible que una
-- resolución mueva las fechas o el motivo del permiso que se está resolviendo:
-- esas columnas no son actualizables por nadie desde la herramienta, y no hace
-- falta ninguna política que lo diga. `resuelto_por` y `resuelto_en` tampoco
-- están en la lista, a propósito — los escribe el trigger de la sección 1.
grant update (estado, resolucion_nota) on rrhh_permiso to authenticated;
grant update, delete on rrhh_feriado to authenticated;
grant execute on function rrhh_calendario() to authenticated;
grant execute on function rrhh_resolver_evento(bigint, boolean, text, text, text)
  to authenticated;

-- ⚠️ ESTO CAMBIA ALGO DEL PEGADO 2, Y ES A PROPÓSITO. `rrhh_evento_aprob`
-- tenía `grant insert ... to authenticated`, o sea que se podía insertar una
-- aprobación por REST sin pasar por rrhh_resolver_evento(). Con esa puerta
-- abierta el guardia de la sección 4 es un adorno: la carrera entre las dos
-- socias vuelve a existir por el camino de al lado. Se cierra la puerta y
-- queda una sola entrada.
-- Qué NO rompe: hoy nada inserta ahí. La herramienta publicada no tiene
-- pantalla de aprobación (esta es la primera), y el SQL Editor de Supabase
-- corre como `postgres`, que no pasa por estos grants.
revoke insert on rrhh_evento_aprob from authenticated;


-- ── 7 · SIEMBRA DE DÍAS CERRADOS ────────────────────────────────────────
-- ⚠️ ANDREA / LORENA: esto SE EJECUTA al darle Run. Son los cuatro que salieron
-- del contexto maestro, confirmados el 8-set-2026. Miralos antes:
--
--     31-ago-2026   feriado   Día de la Persona Negra y la Cultura Afrocostarricense
--     15-set-2026   feriado   Día de la Independencia
--     01-dic-2026   feriado   Abolición del Ejército
--     18-dic-2026 → 11-ene-2027   cierre   Cierre de planta de fin de año
--
-- Lo que falte se agrega desde la pantalla "Días cerrados", que para eso está.
-- `where not exists` en vez de `on conflict do nothing`: la restricción que
-- protege esta tabla es un EXCLUDE (solape), y `on conflict` no sabe leerla —
-- con un solape, `on conflict do nothing` falla igual en vez de callarse.
insert into rrhh_feriado (fecha, fecha_fin, descripcion, tipo, creado_por)
select v.fecha, v.fecha_fin, v.descripcion, v.tipo, 'semilla'
  from (values
    ('2026-08-31'::date, null::date,          'Día de la Persona Negra y la Cultura Afrocostarricense', 'feriado'),
    ('2026-09-15'::date, null::date,          'Día de la Independencia',                                'feriado'),
    ('2026-12-01'::date, null::date,          'Abolición del Ejército',                                 'feriado'),
    ('2026-12-18'::date, '2027-01-11'::date,  'Cierre de planta de fin de año',                         'cierre')
  ) as v(fecha, fecha_fin, descripcion, tipo)
 where not exists (
   select 1 from rrhh_feriado f
    where daterange(f.fecha, coalesce(f.fecha_fin, f.fecha), '[]')
       && daterange(v.fecha, coalesce(v.fecha_fin, v.fecha), '[]'));


-- ── 8 · COMPROBACIÓN ────────────────────────────────────────────────────
-- Pegado esto, correr lo de abajo. Los cuatro días cerrados tienen que estar,
-- y el calendario tiene que contestar (vacío está bien: todavía nadie pidió
-- nada).
--
--   select fecha, fecha_fin, tipo, descripcion from rrhh_feriado order by fecha;
--   select * from v_rrhh_calendario order by fecha;
--
-- Y desde afuera, con la anon key, las cuatro tienen que dar permission denied
-- (lo mide `python3 esquema_check.py`, que trata todo lo que empieza con
-- `rrhh_` como sensible y BLOQUEA si la anon key atraviesa):
--   rrhh_permiso · rrhh_feriado · v_rrhh_calendario · v_rrhh_permiso
