-- SOLO LECTURA · DIAGNOSTICO_NOMBRES_PERSONA.sql
-- ════════════════════════════════════════════════════════════════════════
-- COMO ESTA REGISTRADO CADA NOMBRE EN rrhh_persona
-- Una sola consulta. Ni un insert, ni un update, ni un delete: solo lee
-- rrhh_persona y rrhh_persona_baja. No toca nada.
--
-- ⚠️ NO TRAE NI UN MONTO. No se asoma a rrhh_salario ni a rrhh_neto_quincena:
-- solo las columnas que IDENTIFICAN a la persona.
--
-- PARA QUE: el candado de PEGADO_NETO_QUINCENA.sql paro con «ney»: 0 personas.
-- El pegado busca asi:
--
--     lower(split_part(btrim(p.nombre), ' ', 1)) = 'ney'
--
-- O sea: le quita los espacios de los extremos al nombre, toma la PRIMERA
-- palabra separada por un espacio, la pasa a minusculas, y la compara EXACTA.
-- No es un `like`: eso fue a proposito, porque `ilike 'daniel%'` casa con Daniel
-- Y con Daniela, y con un `limit 1` encima el neto de una se le cargaria a la
-- otra sin que nada avise (ya paso, ERROR 21000).
--
-- Entonces «0 personas» puede ser por cuatro motivos distintos, y esta consulta
-- los separa:
--   1. el nombre registrado no empieza con «Ney» (p. ej. «Neydi», «Neyci»);
--   2. empieza por el apellido;
--   3. el separador no es un espacio normal (un espacio duro, una tabulacion);
--   4. la persona no esta cargada en rrhh_persona.
--
-- COMO LEER LA TABLA:
--   · `nombre_entre_corchetes` hace visibles los espacios de los extremos;
--   · `lo_que_ve_el_pegado` es EXACTAMENTE el texto con el que compara. Si para
--     alguien dice algo distinto de daniela / daniel / ney, ahi esta la respuesta;
--   · `coincide` dice con cual de los tres casa, o «—»;
--   · `caracter_raro` avisa si el nombre trae algo que no sea letra, espacio
--     normal, guion o apostrofo — un espacio duro cae ahi.
-- ════════════════════════════════════════════════════════════════════════

select p.id                                                  as id,
       p.nombre                                              as nombre,
       '[' || p.nombre || ']'                                as nombre_entre_corchetes,
       length(p.nombre)                                      as largo,
       lower(split_part(btrim(p.nombre), ' ', 1))            as lo_que_ve_el_pegado,
       case when lower(split_part(btrim(p.nombre),' ',1))
                 in ('daniela','daniel','ney')
            then lower(split_part(btrim(p.nombre),' ',1)) else '—' end
                                                             as coincide,
       -- Un espacio duro (U+00A0), una tabulacion o un caracter invisible rompen
       -- el split_part y no se ven mirando la pantalla. Esta columna los delata.
       case when p.nombre ~ '[^[:alpha:] ''´`^~¨.-]' then 'SI · revisar' else 'no' end
                                                             as caracter_raro,
       coalesce(p.email, '(sin correo)')                      as correo,
       coalesce(to_char(p.ingreso, 'DD-MM-YYYY'), '(sin fecha)') as ingreso,
       case when b.fecha is null            then 'activa'
            when coalesce(b.anulada,false)  then 'activa (reingreso)'
            else 'DE BAJA el ' || to_char(b.fecha, 'DD-MM-YYYY') end
                                                             as situacion
  from rrhh_persona p
  left join lateral (select x.anulada, x.fecha from rrhh_persona_baja x
                      where x.persona_id = p.id
                      order by x.creado_en desc, x.id desc limit 1) b on true
 order by lower(btrim(p.nombre));
