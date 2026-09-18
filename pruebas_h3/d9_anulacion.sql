-- ════════════════════════════════════════════════════════════════════
-- PRUEBA D9 · CARRIL B · ent_anulacion: "solo socias" no esta en la base
--
-- ⚠️ ESTE ARCHIVO NO SE PEGA EN EL EDITOR DE SQL. Es la ENTRADA de
--    pg_pruebas.py, que le pone el sobre y la identidad.
--
-- NO ES UNA PRUEBA EXTRAIDA: se escribio el 17-sep-2026, a partir de un
-- hallazgo medido contra produccion ese mismo dia.
--
-- 🔴 ESTA PRUEBA SE INVIRTIO EL 17-sep-2026, JUNTO CON
--    `CAMBIO_ANULACION_SOCIAS.sql`. Hasta ese pegado el insert ENTRABA, y eso
--    era lo correcto de medir: confirmaba el hueco. Ahora tiene que dar ERROR.
--
--    ⚠️ SI ESTA PRUEBA "FALLA" —o sea, si el insert ENTRA— NO ESTA MAL LA
--    PRUEBA: significa que `CAMBIO_ANULACION_SOCIAS.sql` todavia no se pego, o
--    se pego a medias. Mirá la politica ANTES de tocar este archivo:
--        select policyname, with_check from pg_policies
--         where tablename = 'ent_anulacion' and cmd = 'INSERT';
--    Tiene que decir `acceso_es_socia()`. Si dice `true`, falta el pegado.
--
--    Se deja escrito el cambio de direccion, y no se reescribe en silencio,
--    porque una prueba que quedo midiendo lo contrario de lo que se construyo
--    es el modo de falla del 15-sep (P0-a "fallando" por la escalera rota) y
--    el de la 7a del 14-ago: da el resultado de otra cosa y nadie lo nota. Es
--    el mismo tratamiento que lleva D4, invertida el 16-sep.
--
-- EL HALLAZGO QUE LA ORIGINO, y por que valia la pena
--   La pantalla de Devoluciones (b61) decia que anular era SOLO SOCIAS. La
--   base decia otra cosa: `ent_anulacion_ins` era
--     for insert to authenticated with check (TRUE)
--   la tabla NO tiene ningun trigger (0), y `authenticated` tiene el grant de
--   INSERT. O sea que cualquier usuario logueado pasaba; lo unico que detenia
--   a Daniel era que la interfaz no le mostraba el boton.
--   No se leyo de un catalogo: se MIDIO con esta misma prueba, por el carril
--   B, el 17-sep — y el insert entro.
--
-- ESPERADO AHORA · DEPENDE DE CON QUIEN CORRA, y la prueba lo dice sola:
--   · identidad 'equipo' (la de siempre) →  **ERROR 42501**
--       "new row violates row-level security policy for table ent_anulacion"
--   · identidad de SOCIA (--identidad socia) →  **INSERT 0 1**
--   Las dos lineas de arriba son resultados CORRECTOS, cada una en su caso.
--   El primer select del archivo imprime con que perfil corrio y que tiene que
--   pasar en ese caso, y el ultimo lee el resultado segun esa misma identidad.
--   Antes ese cartel final estaba escrito para 'equipo' y se leia AL REVES
--   cuando la prueba corria como socia: decia "D9 MAL" sobre el resultado
--   correcto. Un cartel que dice lo contrario del resultado es peor que no
--   tenerlo — es el mismo problema que un mensaje que no distingue "no existe"
--   de "ya no queda".
--
-- ⚠️ Y LO QUE EL CAMBIO NO HIZO: cerro la puerta de la APP, no la del editor.
--    El SQL Editor entra como `postgres` y saltea la RLS, asi que un pegado a
--    mano sigue pudiendo anular. Esta bien que asi sea — quien tiene el editor
--    ya puede todo. Pero que nadie lea esta prueba en verde como "ahora solo
--    las socias pueden anular, punto".
--
-- ⚠️ IDENTIDAD: por defecto corre con el usuario de prueba, perfil 'equipo',
--    y ASI ES COMO MIDE QUE EL AGUJERO ESTE CERRADO. Con una socia NO mide
--    eso —una socia pasaba antes del cambio y pasa despues—, pero mide la otra
--    mitad, que vale igual: que a una socia la politica la SIGA DEJANDO. Una
--    politica que no deja pasar a nadie tambien "protege", y rompe la pantalla.
--    Correr las dos es lo que deja el cambio medido por los dos lados.
--    Si B0 no dio 1, ninguna de las dos significa nada.
--
-- El `entidad_id` 999999 no existe y no hace falta que exista: la tabla
-- no tiene clave foranea hacia la devolucion (medido: los unicos
-- constraints son la PK y el check de `entidad`). Si algun dia se le
-- agrega la FK, esta prueba va a empezar a fallar por OTRO motivo — y
-- ese es justo el caso que hay que poder distinguir.
-- ════════════════════════════════════════════════════════════════════
-- ⚠️ Las frases de abajo son CORTAS a proposito: `pg_pruebas.py` corta las
-- columnas en 60 caracteres y NO avisa que corto, asi que una frase larga sale
-- mutilada y parece entera. Y el veredicto va al PRINCIPIO de cada una por lo
-- mismo. Si alguien las alarga, revisar que sigan entrando.
--
-- Quien corre y que tiene que pasar EN ESTE CASO. Va PRIMERO a proposito: si
-- el insert rebota (42501), la transaccion se aborta y nada de lo que sigue se
-- ejecuta, asi que este es el unico cartel que se ve en el caso 'equipo'.
select coalesce(acceso_perfil(), '(sin perfil: el claim no llego)') as corre_como,
       case when acceso_es_socia()
            then 'ESPERADO: INSERT 0 1 · a la SOCIA la sigue dejando'
            else 'ESPERADO: ERROR 42501 · a quien NO es socia la rechaza'
       end as que_tiene_que_pasar;

insert into ent_anulacion (entidad, entidad_id, motivo, creado_por)
values ('devolucion', 999999, 'prueba-d9 H3', 'prueba-d9');

-- Este select SOLO corre si el insert entro. O sea que la pregunta aca no es
-- "entro o no" —ya sabemos que si— sino si entrar estaba bien PARA ESTA
-- IDENTIDAD, que es justo lo que el cartel viejo no distinguia.
select case when acceso_es_socia()
            then 'D9 OK · corrio como SOCIA y ENTRO: es lo CORRECTO'
            else 'D9 MAL · corrio como ' || coalesce(acceso_perfil(), '?') ||
                 ' y ENTRO: la politica NO quedo cerrada'
       end as resultado;
