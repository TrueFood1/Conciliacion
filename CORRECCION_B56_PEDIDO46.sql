-- ════════════════════════════════════════════════════════════════════════
-- b56 · EL MEDIODIA INVENTADO DEL PEDIDO 46 ("Regalia para Anne", 8-sep)
-- LISTO PARA PEGAR UNA SOLA VEZ en el SQL Editor de Supabase.
-- Append-only, con guarda: se puede correr dos veces sin danio.
--
-- ── EL DEFECTO, Y POR QUE NO ES EL MISMO QUE EL DEL 44 ──────────────────
-- El 44 tenia la FECHA pegada. Este tiene la fecha bien y la HORA inventada:
--     fecha_despacho  2026-09-08   (hoy)
--     salida_en       2026-09-08 12:00:00 CR   ← mediodia exacto
--     registrado      2026-09-08 08:33:35 CR   ← se tecleo a las 8:33
-- Y como el dia de la salida es el mismo dia del registro, `_despCuandoSalida`
-- MUESTRA la hora: el Historial ensenia "12:00" con cara de medida. Es la regla
-- de Andrea del 25-ago al reves — la hora se muestra solo si esta medida.
--
-- ── QUIEN ESCRIBIO ESTO, Y ES EL HALLAZGO QUE IMPORTA ───────────────────
-- La fila trae la nota 'Reporte de despacho: la fecha es la registrada, la hora
-- NO es medida'. Esa cadena NO existe en el index.html de hoy: la quito b54
-- (`f1e51b6`). El codigo de antes de b54 era literalmente
--     salida_en:_rp.fecha+'T12:00:00-06:00'
-- o sea mediodia SIEMPRE, incluso cuando la salida era de hoy y la hora real se
-- sabia. Esta fila se escribio HOY a las 08:33, con b55 publicado en main desde
-- ayer 20:25.
--
-- CONCLUSION: el iPad de Daniel corrio codigo anterior a b54 durante horas. El
-- arreglo de b55 no fallo — nunca se cargo en ese aparato. Los dos pedidos que
-- Daniel hizo despues (49 a las 09:34 y 54 a las 12:01) tienen hora real y nota
-- vacia, o sea codigo nuevo: la PWA se actualizo sola entre las 08:33 y las 09:34,
-- sin que nadie lo pidiera y sin que nadie se enterara. Por eso el sello de
-- version subio de prioridad, y se disenia junto con el login del Bloque 1.
-- Registros afectados: UNO, este.
--
-- ── DE DONDE SALE LA HORA ───────────────────────────────────────────────
-- De `ent_salida.creado_en` de la salida vigente: 8-sep 08:33:35.020272 CR, el
-- instante en que Daniel registro la salida. NO es un literal tecleado: se LEE de
-- la fila. Y es exactamente lo que b55 habria escrito si el aparato lo hubiera
-- tenido: `_despSalidaPayload` devuelve {} cuando la fecha es hoy, y entonces gana
-- el `default now()` de la base, que es el instante del registro. Esta correccion
-- reproduce eso, no inventa un criterio nuevo.
--
-- Y esta vez el Historial SI va a mostrar la hora, con razon: el dia de la salida
-- y el del registro coinciden, asi que 8:33 es un dato medido.
--
-- ── QUE NO CAMBIA ───────────────────────────────────────────────────────
-- Ningun saldo. El corte del ancla es el 29-ago 00:07 UTC, y las dos horas del
-- 8-sep estan despues. Se verifica DIFERENCIAL abajo, no contra un numero de otra
-- medicion (la leccion de la consulta 3 del pedido 44).
-- ════════════════════════════════════════════════════════════════════════


-- ── 1 · ANTES DE ESCRIBIR ────────────────────────────────────────────────
-- Tiene que devolver UNA fila: destinatario Anne, motivo regalia, salida 12:00 y
-- registro 08:33:35. Si devuelve otra cosa, NO SEGUIR.
select p.id as pedido, p.motivo, p.destinatario, p.fecha_despacho,
       sv.alisto_id, sv.salida_id,
       (sv.salida_en at time zone 'America/Costa_Rica') as salida_cr,
       (s.creado_en  at time zone 'America/Costa_Rica') as registrado_cr,
       s.nota
  from ent_pedido p
  join ent_alisto_vigente av on av.pedido_id = p.id
  join ent_salida_vigente sv on sv.alisto_id = av.alisto_id
  join ent_salida s on s.id = sv.salida_id
 where p.id = 46;


-- ── 2 · LA CORRECCION ────────────────────────────────────────────────────
insert into ent_salida (alisto_id, salida_en, nota, creado_por)
select sv.alisto_id,
       s.creado_en,
       'Hora de salida corregida: la hora es el instante del registro, y ES medida'
         || ' · b56 8-sep-2026: la fila original decia mediodia con la fecha de HOY,'
         || ' escrita por codigo anterior a b54 que ponia 12:00 siempre. El iPad de'
         || ' Daniel no habia cargado b55 todavia. La hora nueva es el creado_en de'
         || ' esa misma fila (08:33:35 CR), que es lo que b55 habria escrito por el'
         || ' default now() de la base. Decidido por Andrea.',
       'correccion-sql · b56 · andrea@truefoodcr.com'
  from ent_pedido p
  join ent_alisto_vigente av on av.pedido_id = p.id
  join ent_salida_vigente sv on sv.alisto_id = av.alisto_id
  join ent_salida s on s.id = sv.salida_id
 where p.id = 46
   and not exists (select 1 from ent_salida s2
                    where s2.alisto_id = sv.alisto_id
                      and s2.creado_por like 'correccion-sql · b56%');

select s.id, s.alisto_id,
       (s.salida_en at time zone 'America/Costa_Rica') as salida_cr,
       (s.creado_en at time zone 'America/Costa_Rica') as registrado_cr,
       s.creado_por
  from ent_salida s
  join ent_alisto a on a.id = s.alisto_id
 where a.pedido_id = 46
 order by s.creado_en;
-- Esperado: DOS filas. La vieja (12:00, danielnu…) y la nueva (08:33:35.020272,
-- correccion-sql · b56 …). Si sale una sola, no escribio.
