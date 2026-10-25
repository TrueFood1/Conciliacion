# Plan a 4 meses — factores de temporada (evidencia, 25-oct-2026)

Medido el domingo 25-oct-2026 con lecturas de Odoo producción (solo `search_read`/`read`)
y de Supabase con `pg_lector` (solo `select`). Rama `plan-4-meses`. Cantidades en **unidad
de venta**: Blanco, Semillas y Galletas en unidades; Francés y Buns en paquetes de 4; Pizza
en paquetes de 2. UoM convertida por `product_uom_id` → `factor`, nunca por nombre.

## Regla (la que corre en `_temporadaCalc`, `index.html`)

    factor(M) = promedio sobre 2 años de  [venta neta por día hábil de M ese año]
                                        ÷ [venta neta por día hábil de sep–oct del año anterior a M]

- Venta neta = facturas − notas de crédito, `parent_state = posted`, `display_type = 'product'`.
- **Por día hábil (lun–vie)**, no por mes: febrero tiene 20 y octubre 23.
- **Enero cuenta desde su primer día con venta.** En 2026 la planta volvió el **mar 6-ene**
  (19 días hábiles en vez de 21); en 2025, el jue 2-ene. Sin esto, enero 2026 salía bajo por
  días en que no se vendía porque no se abría.
- Un año **no cuenta** si la base de sep–oct del producto era menos de la mitad del ritmo de
  hoy (el producto no existía o era otro negocio). Sin ningún año: factor **1**, marcado
  "sin historia".
- Feriados dentro del mes **no** se descuentan de los días hábiles (Semana Santa 2026 cae en
  abril: 2 días de 22).
- Se verificó que la versión JS (`_temporadaCalc` bajo `jsc`) y la de Python dan **los mismos
  números a 3 decimales** en los 6 meses.

## Ritmo de hoy (`nivRitmo`, 6 semanas ISO 37–42 de 2026), por semana

| Blanco | Semillas | Francés | Buns | Pizza | Galletas |
|---|---|---|---|---|---|
| 174,0 u | 131,7 u | 131,7 paq | 75,7 paq | 48,3 paq | 32,0 u |

## Factores

| Mes | Blanco | Semillas | Francés | Buns | Pizza | Galletas |
|---|---|---|---|---|---|---|
| nov-2026 *(no se aplica: meta de cierre)* | 1,017 | 1,162 | 1,138 | 0,851 | sin historia | sin historia |
| dic-2026 *(no se aplica: meta de cierre)* | 1,077 | 1,331 | 1,119 | 0,940 | sin historia | sin historia |
| **ene-2027** | **0,884** | **1,131** | **0,990** | **0,937** | sin historia (×1) | sin historia (×1) |
| **feb-2027** | **1,174** | **1,474** | **1,334** | **1,217** | sin historia (×1) | sin historia (×1) |
| mar-2027 *(fuera del horizonte hoy)* | 1,151 | 1,558 | 1,097 | 0,891 | sin historia | sin historia |
| abr-2027 *(fuera del horizonte hoy)* | 0,802 | 1,214 | 0,974 | 0,762 | sin historia | sin historia |

### Detalle de enero y febrero (venta por día hábil)

| Producto | Base sep–oct 2025 | ene-2026 (desde 6-ene) | Base sep–oct 2024 | ene-2025 | **ene** | feb-2026 | feb-2025 | **feb** |
|---|---|---|---|---|---|---|---|---|
| Blanco (u) | 52,0 | 44,8 → 0,863 | 49,5 | 44,8 → 0,904 | **0,884** | 56,5 → 1,088 | 62,4 → 1,260 | **1,174** |
| Semillas (u) | 28,2 | 28,5 → 1,009 | 29,0 | 36,4 → 1,254 | **1,131** | 44,9 → 1,589 | 39,4 → 1,359 | **1,474** |
| Francés (paq) | 29,3 | 27,7 → 0,946 | 30,8 | 31,9 → 1,034 | **0,990** | 38,1 → 1,301 | 42,1 → 1,367 | **1,334** |
| Buns (paq) | 25,0 | 25,8 → 1,034 | 27,0 | 22,7 → 0,840 | **0,937** | 31,2 → 1,250 | 31,9 → 1,183 | **1,217** |

- **Pizza**: base sep–oct 2025 = 1,8 paq/día y sep–oct 2024 = 0,6, contra un ritmo de hoy de
  ~9,7 paq/día. Despegó en nov-2025 (515 paq ese mes); los cocientes (×8,5 en enero) miden el
  lanzamiento, no la temporada. Descartado → ×1.
- **Galletas**: primera venta en abr-2026. Sin base → ×1.

## Dónde se aplica

- **Antes del cierre** (hasta la semana del lun 14-dic): ritmo de hoy **sin factor**. Ahí manda
  la meta de cierre (`cierreMeta`), que ya trae el pico de diciembre en sus bloques 1 y 2;
  aplicar además el factor de diciembre lo contaría dos veces. Medido: con los datos reales,
  las 8 semanas del 26-oct al 14-dic salen **idénticas** a `origin/main` (5b276c7).
- **Cierre** 18-dic → 11-ene (de `rrhh_feriado`, 5 tramos juntados en un bloque): semanas del
  21-dic, 28-dic y 4-ene vacías, sin venta. Al terminar la semana del 14-dic se descuentan las
  dos entregas de la meta (b1 + b2).
- **Desde el 11-ene**: ritmo × factor del mes.

## Qué muestra el plan para la semana del lunes 11-ene-2027 (datos reales del 25-oct)

Stock de hoy: Blanco 1.178 u · Semillas 869 u · Francés 421 paq · Buns 675 paq · Pizza 228 paq ·
Galletas 321 u. Con la meta de cierre vigente, las 39 ediciones futuras de `plan_overrides` y
`semana_capacidad`:

| lun 11 | mar 12 | mié 13 | jue 14 | vie 15 |
|---|---|---|---|---|
| 8 Blanco | 12 Pizza | 10 Buns | 10 Semillas | Picado |

Total de la semana, en tandas: **8 Blanco · 10 Semillas · 10 Buns · 12 Pizza** (Francés y
Galletas no entran esa semana: el stock al volver los cubre).
