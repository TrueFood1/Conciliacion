-- ═══════════════════════════════════════════════════════════════════════════
-- CAMBIO_CONTENIDO_FICHAS.sql  ·  28-oct-2026  ·  Contenido b146: categoría «Fichas técnicas» en el banco
-- ⏳ NO CORRIDO EN PRODUCCIÓN. Antes: ENSAYO_CONTENIDO_FICHAS.sql (ensayo en seco, no deja nada).
--    Después: la fila de control de abajo tiene que salir EXACTA. Este header se toca DESPUÉS de
--    verificar, nunca antes.
-- Va DESPUÉS de CAMBIO_CONTENIDO_B139.sql (aplicado el 27-oct). Para saber si está aplicado, mirar la base:
--   select pg_get_constraintdef(oid) like '%fichas%' from pg_constraint
--    where conname = 'contenido_banco_categoria_check';
--
-- QUÉ HACE
--   1 · contenido_banco.categoria admite 'fichas' (fichas técnicas que se mandan a clientes, sin precios):
--       13 categorías = las 12 de b139 + fichas. Ninguna fila se mueve: el CHECK nuevo es el viejo
--       más un valor, así que toda fila que hoy entra sigue entrando (el control lo comprueba).
--   2 · contenido_banco.tipo: 'documento' YA lo admite desde b139 (medido el 28-oct con pg_lector:
--       foto · video · documento). Se vuelve a escribir el CHECK con los mismos tres valores para que
--       este archivo deje el estado completo aunque la base viniera de otro lado; no cambia nada.
  3 · ARCHIVA (activo = false, sin borrar) las 20 fotos de producto, planta y en_tienda: el banco
--       queda con lo importante de tener a la mano (pedido de Andrea, 28-oct). Siguen activas
--       logos_supermercados (2) y empaque (1). Volver atrás: update … set activo = true,
--       editado_por = '…' where editado_por = 'archivo-b146-28oct'.
--   Sin tablas nuevas, sin políticas nuevas, sin bucket nuevo: las fichas usan la misma tabla,
--   la misma RLS (acceso_es_socia()) y el mismo bucket de miniaturas que las fotos.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

do $$ begin
  if not exists (select 1 from storage.buckets where id = 'contenido-miniaturas') then
    raise exception 'falta CAMBIO_CONTENIDO_B139.sql: pegarlo primero';
  end if;
  if exists (select 1 from pg_constraint where conname = 'contenido_banco_categoria_check'
               and pg_get_constraintdef(oid) like '%''fichas''%') then
    raise exception 'la categoría fichas ya existe: este archivo no se vuelve a pegar';
  end if;
end $$;
-- cuántas filas había: el control exige las mismas (este cambio no borra ni agrega filas)
select set_config('b146.filas_antes', (select count(*) from public.contenido_banco)::text, true);

-- ── 1 · tipo: foto · video · documento (igual que b139) ───────────────────
alter table public.contenido_banco drop constraint contenido_banco_tipo_check;
alter table public.contenido_banco add constraint contenido_banco_tipo_check
  check (tipo in ('foto', 'video', 'documento'));

-- ── 2 · categorías: las 12 de b139 + fichas ───────────────────────────────
alter table public.contenido_banco drop constraint contenido_banco_categoria_check;
alter table public.contenido_banco add constraint contenido_banco_categoria_check
  check (categoria in ('producto', 'empaque', 'tabla_nutricional', 'fichas',
                       'desayunos', 'almuerzos_cenas', 'meriendas', 'nosotras', 'planta', 'en_tienda',
                       'certificaciones', 'logos_supermercados', 'marca'));

-- ── 3 · el banco queda con lo importante de tener a la mano (Andrea, 28-oct 18:23) ──
-- Se ARCHIVAN (activo = false; no se borra ninguna fila) las fotos de producto, planta y en_tienda:
-- medido el 28-oct con pg_lector, 10 + 8 + 2 = 20 activas. Quedan activas logos_supermercados (2)
-- y empaque (1). editado_en lo pone el trigger contenido_banco_editado; editado_por lleva la marca
-- del cambio, como la corrección de b139 ('correccion-b139-27oct'), no un correo (el repo es público).
update public.contenido_banco
   set activo = false, editado_por = 'archivo-b146-28oct'
 where activo and tipo = 'foto' and categoria in ('producto', 'planta', 'en_tienda');

-- Control: 2 · 1 · 1 · t · 0 · 20 · 3
--   los 2 CHECK con su nombre de siempre · tipo admite documento · categoría admite fichas ·
--   mismas filas que antes (archivar no borra) · filas fuera de las 13 categorías ·
--   fotos archivadas por este cambio · fotos que siguen activas (2 logos_supermercados + 1 empaque)
--   ⚠️ 20 y 3 son lo medido el 28-oct. Si alguien cargó fotos en el banco antes de pegar, cambian:
--   mirar antes `select categoria, count(*) from contenido_banco where activo group by 1`.
select (select count(*) from pg_constraint where conrelid = 'public.contenido_banco'::regclass
           and conname in ('contenido_banco_tipo_check', 'contenido_banco_categoria_check')) as checks,
       (select count(*) from pg_constraint where conrelid = 'public.contenido_banco'::regclass
           and conname = 'contenido_banco_tipo_check'
           and pg_get_constraintdef(oid) like '%''documento''%') as tipo_documento,
       (select count(*) from pg_constraint where conrelid = 'public.contenido_banco'::regclass
           and conname = 'contenido_banco_categoria_check'
           and pg_get_constraintdef(oid) like '%''fichas''%' and pg_get_constraintdef(oid) like '%''marca''%') as cat_fichas,
       (select count(*) from public.contenido_banco) = current_setting('b146.filas_antes')::bigint as mismas_filas,
       (select count(*) from public.contenido_banco where categoria not in ('producto', 'empaque', 'tabla_nutricional', 'fichas',
           'desayunos', 'almuerzos_cenas', 'meriendas', 'nosotras', 'planta', 'en_tienda',
           'certificaciones', 'logos_supermercados', 'marca')) as fuera_de_lista,
       (select count(*) from public.contenido_banco where not activo and editado_por = 'archivo-b146-28oct') as archivadas,
       (select count(*) from public.contenido_banco where activo and tipo = 'foto') as fotos_activas;
commit;
