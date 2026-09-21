-- ════════════════════════════════════════════════════════════════════════
-- QUITARLE TRUNCATE, REFERENCES Y TRIGGER A anon Y authenticated
-- en todas las tablas de `public`, y en las que se creen de ahora en mas.
-- PROPUESTA 21-sep-2026.
--
-- ⚠️ NO PEGADO TODAVIA. Este encabezado NO dice "aplicado" hasta DESPUES de
--    correrlo y de haber mirado la fila de control. Regla del 16-sep.
--
-- ── DE DONDE SALE ───────────────────────────────────────────────────────
-- Del §0d del 19-sep, el hallazgo del esquema de tickets: los privilegios
-- por defecto de `public` le dan a `anon` y a `authenticated` las OCHO letras
-- (`arwdDxtm`) sobre cualquier tabla nueva. Ahi se arreglo para las tablas de
-- tickets, pegando el `revoke` adentro de cada transaccion. Este pegado hace
-- lo mismo HACIA ATRAS, con todo lo que se creo antes.
--
-- Medido el 21-sep: de las 46 tablas de `public`, las unicas 18 limpias son
-- las de tickets y rrhh, `acceso_usuario` y `build_publicado` — o sea, las
-- que nacieron con el `revoke` adentro.
--
-- ── 🔴 POR QUE TRUNCATE IMPORTA: LA RLS NO LO ALCANZA ───────────────────
-- Ejercitado por el carril B el 21-sep, no leido del catalogo:
--     UPDATE    -> `UPDATE 0`      la RLS lo contiene (pero SIN error)
--     DELETE    -> `DELETE 0`      igual
--     TRUNCATE  -> 7 filas -> 0    🔴 PASA
-- Postgres no aplica politicas de RLS a TRUNCATE: ahi manda solo el GRANT.
--
-- ⚠️ Y AHORA EL TAMAÑO REAL, QUE ES MENOR DE LO QUE ASUSTA. Para usar esto
--    hace falta una conexion DIRECTA a Postgres. La anon key que va publicada
--    dentro de `index.html` solo abre PostgREST, que NO TIENE verbo TRUNCATE.
--    Esto es profundidad, no una puerta abierta. No es urgente; es correcto.
--    Lo que NO se pudo medir: si `anon` puede truncar de verdad —
--    `truefie_pruebas` no puede hacer `set role anon`, asi que ese caso queda
--    sin ejercitar. El grant es identico al de `authenticated`, que SI se
--    ejercito.
--
-- ── POR QUE TAMBIEN references Y trigger ────────────────────────────────
-- Son de la misma familia y se van gratis:
--   · TRIGGER es el que de verdad preocupa de los dos. Permite CREATE TRIGGER
--     sobre la tabla, o sea colgar codigo propio que se dispara cuando
--     escribe OTRA persona, con lo que esa persona pueda tocar. Es escalada,
--     no lectura.
--   · REFERENCES permite crear una FK que apunte a la tabla. El riesgo es
--     chico y de fuga: una violacion de FK revela si un valor existe. Se saca
--     porque no cuesta nada.
-- Las dos, como TRUNCATE, necesitan DDL, y PostgREST no hace DDL. Misma
-- exposicion, mismo arreglo, cero costo.
--
-- ── 🔴 LO QUE NO SE TOCA, Y POR QUE ─────────────────────────────────────
-- SELECT, INSERT, UPDATE y DELETE se quedan. Son los cuatro verbos que
-- PostgREST usa y de los que cuelga la app entera; lo que los gobierna es la
-- RLS, tabla por tabla. Sacarlos romperia Truefie en el acto.
-- El control del §2 cuenta esos cuatro ANTES y DESPUES y exige que no se
-- muevan: si el pegado se fuera de mano, salta ahi.
--
-- ── ⚠️ EL CABO SUELTO, MEDIDO: EL DEFAULT DE supabase_admin ─────────────
-- En `public` hay DOS default privileges para tablas: uno otorgado por
-- `postgres` y otro por `supabase_admin`, los dos dando `arwdDxtm`. Este
-- pegado arregla el de `postgres`, que es el que rige lo que se crea desde el
-- SQL Editor (y las 46 tablas de hoy son de `postgres`).
-- El de `supabase_admin` NO se puede tocar desde aca: medido el 21-sep,
-- `alter default privileges for role supabase_admin ...` devuelve
--     42501 · permission denied to change default privileges
-- O sea que una tabla creada POR supabase_admin volveria a nacer con las ocho
-- letras. Hoy eso no pasa, pero queda dicho para que nadie lea este pegado
-- como "cerrado del todo".
--
-- ── ENSAYADO EN ROLLBACK CONTRA PRODUCCION, 21-sep ──────────────────────
--   ANTES   truncate 150 · references 156 · trigger 156 · crud 611
--   DESPUES truncate   0 · references   0 · trigger   0 · crud 611
--   default de tabla nueva: anon pasa de `arwdDxtm` a `arwdm`
--
-- 🔴 Y UNA LECCION DEL ENSAYO QUE HAY QUE LEER ANTES DE PEGAR:
--    el primer ensayo corrio como `truefie_pruebas`, el editor contesto
--    `REVOKE` y `ALTER DEFAULT PRIVILEGES` como si todo hubiera salido, y
--    los contadores NO SE MOVIERON (87 antes, 87 despues). Un revoke solo
--    funciona si lo emite el DUEÑO de la tabla, y las 46 son de `postgres`.
--    **Este pegado TIENE que correrse desde el SQL Editor**, que entra como
--    `postgres`. Si alguna vez se corre desde otro lado y los contadores no
--    bajan, no es que fallo: es que no era el dueño.
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- §0 · SOLO LECTURA · la foto de antes
--
-- ESPERADO, medido el 21-sep desde el SQL Editor (como postgres):
--   truncate 150 · references 156 · trigger 156 · crud 611
-- Si el CRUD no da 611 no pasa nada — es un numero que crece con las tablas.
-- Lo que importa es que sea EL MISMO despues.
-- ════════════════════════════════════════════════════════════════════════
select
  (select count(*) from information_schema.role_table_grants
    where table_schema='public' and privilege_type='TRUNCATE'
      and grantee in ('anon','authenticated'))   as truncate_hoy,
  (select count(*) from information_schema.role_table_grants
    where table_schema='public' and privilege_type='REFERENCES'
      and grantee in ('anon','authenticated'))   as references_hoy,
  (select count(*) from information_schema.role_table_grants
    where table_schema='public' and privilege_type='TRIGGER'
      and grantee in ('anon','authenticated'))   as trigger_hoy,
  (select count(*) from information_schema.role_table_grants
    where table_schema='public'
      and privilege_type in ('SELECT','INSERT','UPDATE','DELETE')
      and grantee in ('anon','authenticated'))   as crud_hoy,
  current_user                                    as corriendo_como;


-- ════════════════════════════════════════════════════════════════════════
-- §1 · EL CAMBIO · listo para correr, con commit
--
-- 🔴 EL CANDADO exige las dos mitades: que las tres letras queden en 0, y
--    que el CRUD no se haya movido ni en uno. Si cualquiera falla, levanta
--    excepcion y el `commit` no llega a correr.
--
-- ⚠️ Van a salir varios WARNING "no privileges could be revoked for column
--    ... of relation v_ticket_historial". Es ruido esperado: el `on all
--    tables` alcanza tambien a las vistas, y ahi esas letras no existen.
--    No es un error y no impide nada.
--
-- ⚠️ SI EL CANDADO SALTA, LA TRANSACCION QUEDA ABIERTA Y ABORTADA: escribi
--    `rollback;` y corrélo.
-- ════════════════════════════════════════════════════════════════════════
begin;

do $candado$
declare
  crud_antes int; crud_despues int;
  t_ int; r_ int; g_ int;
begin
  select count(*) into crud_antes from information_schema.role_table_grants
   where table_schema='public'
     and privilege_type in ('SELECT','INSERT','UPDATE','DELETE')
     and grantee in ('anon','authenticated');

  revoke truncate, references, trigger
      on all tables in schema public
    from anon, authenticated;

  alter default privileges in schema public
    revoke truncate, references, trigger on tables from anon, authenticated;

  select count(*) into t_ from information_schema.role_table_grants
   where table_schema='public' and privilege_type='TRUNCATE'
     and grantee in ('anon','authenticated');
  select count(*) into r_ from information_schema.role_table_grants
   where table_schema='public' and privilege_type='REFERENCES'
     and grantee in ('anon','authenticated');
  select count(*) into g_ from information_schema.role_table_grants
   where table_schema='public' and privilege_type='TRIGGER'
     and grantee in ('anon','authenticated');
  select count(*) into crud_despues from information_schema.role_table_grants
   where table_schema='public'
     and privilege_type in ('SELECT','INSERT','UPDATE','DELETE')
     and grantee in ('anon','authenticated');

  if t_ <> 0 or r_ <> 0 or g_ <> 0 then
    raise exception 'CANDADO: no se fueron todas. truncate=% references=% trigger=% (los tres tenian que dar 0). '
      'Si corriste esto fuera del SQL Editor, el revoke no aplica: hay que ser DUENO. NO SE APLICO NADA.',
      t_, r_, g_;
  end if;

  if crud_despues <> crud_antes then
    raise exception 'CANDADO: el CRUD CAMBIO, de % a %. Esto romperia la app. NO SE APLICO NADA.',
      crud_antes, crud_despues;
  end if;

  raise notice 'CANDADO OK: truncate/references/trigger en 0 · CRUD intacto en %', crud_despues;
end
$candado$;

commit;


-- ════════════════════════════════════════════════════════════════════════
-- ESTA ES LA TABLA QUE VAS A VER. Ya con el commit hecho.
--
-- El SQL Editor muestra SOLO el resultado de la ULTIMA sentencia, por eso el
-- control va DESPUES del commit: asi se ve, y ademas lee lo que quedo firme.
--
-- ESPERADO:  0 · 0 · 0 · el CRUD igual que en el §0 · y el default de tabla
--            nueva con `anon=arwdm` (sin D, sin x, sin t).
-- ════════════════════════════════════════════════════════════════════════
select
  (select count(*) from information_schema.role_table_grants
    where table_schema='public' and privilege_type='TRUNCATE'
      and grantee in ('anon','authenticated'))   as truncate_debe_ser_0,
  (select count(*) from information_schema.role_table_grants
    where table_schema='public' and privilege_type='REFERENCES'
      and grantee in ('anon','authenticated'))   as references_debe_ser_0,
  (select count(*) from information_schema.role_table_grants
    where table_schema='public' and privilege_type='TRIGGER'
      and grantee in ('anon','authenticated'))   as trigger_debe_ser_0,
  (select count(*) from information_schema.role_table_grants
    where table_schema='public'
      and privilege_type in ('SELECT','INSERT','UPDATE','DELETE')
      and grantee in ('anon','authenticated'))   as crud_igual_que_el_paso_0,
  (select d.defaclacl::text from pg_default_acl d
     join pg_namespace n on n.oid=d.defaclnamespace
    where n.nspname='public' and d.defaclobjtype='r'
      and pg_get_userbyid(d.defaclrole)='postgres') as default_de_tabla_nueva;
