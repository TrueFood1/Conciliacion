# Respaldo de Truefie

Copia diaria de la base de Supabase del proyecto **truefie**.

**Este repo es PRIVADO y tiene que seguir siéndolo.** Los dumps llevan nombres
de clientes, cantidades y fechas de entrega. No es el mismo repo que
`TrueFood1/Conciliacion`, que es público y donde vive el código.

## Por qué existe

Desde el **28-ago-2026** el equipo dejó de usar el Excel de despachos: Truefie
es el único registro de entregas. El proyecto de Supabase está en plan **Free**,
que no tiene ningún respaldo automático — la documentación lo dice sin vueltas:
*"Free plan projects do not receive automated backups"*. Sin esto, la base viva
sería la única copia que existe.

## Cómo funciona

- `.github/workflows/respaldo.yml` — corre todos los días a las 03:17 de Costa
  Rica, vuelca la base entera con `pg_dump`, verifica el archivo y lo commitea
  en `respaldos/`.
- `.github/workflows/vigia.yml` — corre los lunes y **falla a propósito** si el
  sello tiene más de 3 días.
- `SELLO.md` — fecha de la última corrida buena. Lo escribe el workflow.
  **No editar a mano**: editarlo es apagar la alarma, no atender el fuego.

Hace falta un solo secret: `SUPABASE_DB_URL`, la cadena del *pooler en modo
sesión* (IPv4). La conexión directa de Supabase es IPv6 y los runners de GitHub
no tienen IPv6.

## Las cuatro alarmas

1. **Correo de GitHub** cuando el workflow corre y falla.
2. **Vigía semanal**, para cuando el respaldo deja de correr y por lo tanto no
   puede fallar.
3. **La verificación del propio archivo** — cinco pruebas sobre el dump, no el
   código de salida de `pg_dump`.
4. **`/retomar` mira este sello desde la Mac de Andrea.** Es la única que no
   vive adentro de GitHub: si se cae Actions, las otras tres se caen con él.

## Restaurar

```bash
gunzip -c respaldos/truefie_2026-09-04.sql.gz | psql "<cadena de conexion>"
```

Antes de restaurar sobre algo que importa, mirá el archivo:

```bash
gunzip -c respaldos/truefie_2026-09-04.sql.gz | less
```

## Cuántas copias se acumulan

Una por día, menos de 1 MB cada una: unos 365 MB al año. **No hay que borrar
nada** — para uso de auditoría conservar todo es más seguro que podar, y el
espacio no es un problema en años.
