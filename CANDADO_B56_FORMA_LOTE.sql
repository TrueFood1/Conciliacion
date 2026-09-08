-- ════════════════════════════════════════════════════════════════════════
-- b56 · 3.6b · EL CANDADO DE FORMA DEL LOTE
-- NO PEGAR antes de MIGRACION_B56_FANTASMAS.sql. Nunca antes.
--
-- ── QUE HACE ────────────────────────────────────────────────────────────
-- De aca en adelante, `ent_alisto_lote.lote` solo acepta la forma canonica
-- DDD / M-AA, o el centinela 'NO DETERMINADO'. Cualquier otra cadena se rechaza
-- en el motor, no en la pantalla. Es el candado que faltaba desde que existe el
-- campo de texto libre.
--
-- ── POR QUE "NOT VALID", Y QUE SIGNIFICA ────────────────────────────────
-- `not valid` NO se saltea los INSERT ni los UPDATE nuevos: solo se saltea la
-- revision de las filas que YA estaban. Eso hace falta porque la historia no se
-- puede reescribir —la tabla es append-only, no tiene grant de UPDATE— y quedan
-- siete filas que no pasarian: las seis 'sin lote' / 'Sin lote' (ya retiradas por
-- la migracion, pero la fila BASE sigue diciendo eso) y el '183 - 12/26' del
-- 18-ago, que se deja quieto a proposito.
--
-- ⚠️ ESTO NO SE CITA, SE MIDE. La verificacion 8b de ENTREGAS_INDETERMINADO.sql es
-- justamente la prueba: agrega un check `not valid` en una transaccion, intenta
-- meter una cadena invalida, y tiene que FALLAR. Correr esa prueba ANTES de pegar
-- esto. Si el insert pasa, `not valid` no alcanza y este archivo no sirve.
-- ════════════════════════════════════════════════════════════════════════


-- ── 1 · ANTES: cuantas filas NO pasarian el candado ──────────────────────
-- ESPERADO: 7. Seis 'sin lote'/'Sin lote' y un '183 - 12/26'. Si son mas, PARAR:
-- alguien escribio texto libre nuevo despues del censo del 8-sep.
select '[' || alt.lote || ']' as cadena_exacta, count(*) as filas
  from ent_alisto_lote alt
 where alt.lote !~ '^\d{1,3} / \d{1,2}-\d{2}$'
   and alt.lote <> 'NO DETERMINADO'
 group by alt.lote
 order by alt.lote;


-- ── 2 · EL CANDADO ───────────────────────────────────────────────────────
alter table ent_alisto_lote
  drop constraint if exists ent_alisto_lote_lote_forma;
alter table ent_alisto_lote
  add constraint ent_alisto_lote_lote_forma check (
    lote ~ '^\d{1,3} / \d{1,2}-\d{2}$' or lote = 'NO DETERMINADO') not valid;

comment on constraint ent_alisto_lote_lote_forma on ent_alisto_lote is
  'b56: el lote es la forma canonica DDD / M-AA o el centinela NO DETERMINADO. '
  'NOT VALID por las siete filas historicas que no pasan (append-only, no se pueden '
  'reescribir); rige para todo insert nuevo.';


-- ── 3 · VERIFICACION ─────────────────────────────────────────────────────
-- 3a · el candado existe y esta como no validado.
select conname, convalidated
  from pg_constraint
 where conrelid = 'ent_alisto_lote'::regclass
   and conname in ('ent_alisto_lote_lote_forma','ent_alisto_lote_motivo_ok')
 order by conname;
-- ESPERADO: ent_alisto_lote_lote_forma → convalidated = f
--           ent_alisto_lote_motivo_ok  → convalidated = t

-- 3b · y BLOQUEA de verdad. Va SOLA y TIENE QUE DAR ERROR — el error es el
--      resultado bueno. Se deshace, no deja nada.
--
--   begin;
--     insert into ent_alisto_lote (linea_id, lote, cant_uds, orden)
--     select al.linea_id, 'SIN LOTE', 0, 99 from ent_alisto_lote al order by al.id limit 1;
--   rollback;
--
-- ESPERADO: 'violates check constraint "ent_alisto_lote_lote_forma"'.


-- ════════════════════════════════════════════════════════════════════════
-- 4 · ⚠️ `ent_conteo_linea` NO LLEVA EL CANDADO TODAVIA, Y ES A PROPOSITO
-- ════════════════════════════════════════════════════════════════════════
-- Andrea pidio "mismo criterio para ent_conteo_linea (hoy 0 invalidas, pero el
-- candado va igual)". Medido: hoy tiene CERO cadenas invalidas, asi que el check
-- podria entrar incluso VALID. Igual NO se pone, y el motivo es concreto:
--
-- `_clAgregar` —el boton "Agregar un lote que no esta" de la pantalla de Conteo—
-- ACEPTA A PROPOSITO una cadena que no se puede leer como lote. Pregunta, avisa lo
-- que eso cuesta, y guarda igual, con el argumento de siempre del modulo: el
-- congelador fisico manda sobre el sistema. Si la base rechaza esa fila, el conteo
-- FALLA AL GUARDAR.
--
-- Y el viernes 11-sep es el conteo fisico de los seis productos y el ancla nueva.
-- Poner este candado antes del viernes es arriesgar que Andrea pierda un conteo
-- entero dentro del congelador, con guantes, sin forma de averiguar por que.
--
-- EL ORDEN CORRECTO ES:
--   1. que la pantalla de Conteo ofrezca 'NO DETERMINADO' como OPCION, igual que
--      el alisto — con su motivo de lista cerrada;
--   2. recién entonces el candado, que ya no le quita ninguna salida a nadie.
-- Eso es codigo, no esquema, y va despues del viernes.
--
-- Cuando llegue el momento, es esto:
--   alter table ent_conteo_linea
--     add constraint ent_conteo_linea_lote_forma check (
--       lote ~ '^\d{1,3} / \d{1,2}-\d{2}$' or lote = 'NO DETERMINADO');
--   (VALID, sin `not valid`, si el censo sigue dando cero invalidas — medirlo, no
--    asumirlo: entre hoy y ese dia hay un conteo entero de por medio.)
