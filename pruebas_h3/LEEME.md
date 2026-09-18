# Pruebas de H3 — las entradas de `pg_pruebas.py`

Estos archivos **no se pegan en el editor de SQL**. Son la *entrada* de la
herramienta, que les pone el sobre (`begin` / `rollback`) y, cuando el carril
es B, también la identidad.

Por eso ningún archivo lleva `begin`, `rollback` ni un solo `set`: el SQL de
entrada tiene **prohibido** todo control de transacción (`begin`, `commit`,
`rollback`, `savepoint`, `release`) y toda palabra que cambie quién corre
(`set`, `set_config`, `reset`, `call`, `do`). **El sobre y la identidad son de
la herramienta, nunca de la prueba** — si una prueba pudiera elegir con qué
identidad corre, el carril B no probaría nada.

## Los dos carriles

| | qué es | qué prueba |
|---|---|---|
| **A** | llave maestra, `bypassrls` | reglas de **contenido**: candados, constraints, triggers |
| **B** | el mismo rol que, ya dentro del sobre, hace `set local role authenticated` y se pone los claims | reglas de **permiso**: que a quien no es socia lo rechacen |

**Cada archivo dice su carril en la primera línea.** Si una prueba no dijera
con cuál corre, volvería el problema de siempre: falla por el motivo de al lado
y nadie se entera.

## Los archivos

| archivo | carril | de dónde salió | qué espera |
|---|---|---|---|
| `b0.sql` | B | **nueva** | 🔴 **va primera.** Que el carril B *exista*: 1 fila, no 6 |
| `d0.sql` | A | extraída | control, **pasa** |
| `d1.sql` | A | extraída | **error** `ent_devolucion_causa_ok` |
| `d2.sql` | A | extraída | **error**, con pedido y sin causa |
| `d3.sql` | A | extraída | **error**, `otro` con nota de 3 caracteres |
| `d3_bis.sql` | A | extraída | **error**, `otro` con nota NULL (caza el `coalesce`) |
| `d4.sql` | A | extraída | **error** `23502` en `pedido_id` |
| `d5.sql` | A | extraída | **pasa**, 1 fila con `uds_exceso` 4 |
| `d6.sql` | A | extraída | **error** `ent_odoo_pendiente_forma_ok` |
| `d7.sql` | A | extraída | control, **pasa**, 1 fila |
| `d8.sql` | B | extraída | ⚠️ **dos identidades**, ver el archivo |
| `d9_anulacion.sql` | B | **nueva** | 🔴 **invertida el 17-sep**: ahora espera **42501** |

## ⚠️ D9 va atada a un pegado

`d9_anulacion.sql` **se invirtió el 17-sep** junto con
`CAMBIO_ANULACION_SOCIAS.sql`. Hasta ese pegado el insert entraba y eso era lo
correcto de medir; ahora tiene que dar **42501**.

**Si D9 "falla" —si el insert entra— no está mal la prueba: falta el pegado.**
Mirá la política antes de tocar el archivo:

```sql
select policyname, with_check from pg_policies
 where tablename = 'ent_anulacion' and cmd = 'INSERT';
```

Tiene que decir `acceso_es_socia()`. Si dice `true`, el cambio no se aplicó.

## Dos cosas contadas, no supuestas

**Son diez bloques, no nueve.** La bitácora habla de «las nueve pruebas»
(D0–D8) y es correcto como nombre, pero **D3-bis es un bloque aparte**: medido,
hay 10 pares `begin`/`rollback` en la sección de pruebas del original. Quien
cuente nueve archivos y encuentre diez no se equivocó.

**D8 mide dos cosas a la vez** y hay que correrla con dos identidades: con el
usuario de prueba (`equipo`) tiene que dar **error 42501**, y con una socia
tiene que vaciar la cola. Está explicado adentro del archivo.

## Cómo se extrajeron, y por qué se puede confiar

Por **contenido**, no por número de línea: cada bloque se localizó por su par
`begin`/`rollback` y su encabezado. Después se **verificó** reensamblándolo y
comparándolo con el original **carácter por carácter**.

Es la lección del 16-sep, cuando un `sed -n '141,476p'` entregó el pedazo
equivocado y se pegó P0-a creyendo que era otra cosa. No se escribió nada solo
porque P0-a terminaba en `rollback` — o sea, por suerte.

La verificación **no es una afirmación de esta sesión**: es un script que se
vuelve a correr cuando uno quiera, y sale con código 1 si algo falla.

```bash
python3 pruebas_h3/verificar.py
```

Al 17-sep-2026: **12 archivos · 10 extraídos verificados contra el original ·
2 nuevas · 0 fallas.**
