# Preguntas para la contadora · incapacidades

**Fecha:** 3-oct-2026 · **Para:** quien lleva las planillas de True Food CR
**De:** Andrea / Lorena · **Asunto:** cómo calcular el pago de la quincena cuando
alguien del equipo de producción tiene una incapacidad.

Esta nota no lleva ningún monto ni dato personal de salario, a propósito: se puede
reenviar tal cual.

---

## Por qué preguntamos

Estamos haciendo que Truefie calcule solo el **ajuste** de la quincena (lo que se
suma y se resta sobre el salario fijo que usted ya postea). Hoy el sistema **no
toca las incapacidades**: si alguien se incapacita, la transferencia sale igual
que un mes normal y el ajuste lo hace una persona a mano. Queremos cablearlo, y
antes de escribir una fórmula necesitamos que las reglas las confirme usted.

**Mientras no estén confirmadas, el sistema va a mostrar un aviso y nadie va a
transferir contra ese número sin revisarlo a mano.** No vamos a dejar escrito en
el código ningún porcentaje ni ningún plazo: todos van a ser parámetros que se
cambian sin tocar el programa, justamente porque todavía no están confirmados.

## Lo que encontramos en fuentes oficiales (MTSS e INS) — a confirmar

- **Enfermedad común:** el patrono paga al menos el **50%** del salario los días
  **1 a 3** (art. 79 Código de Trabajo); la **CCSS** subsidia el **60%** desde el
  **día 4** (art. 35 Reglamento del Seguro de Salud).
- **Accidente de trabajo:** el **INS** paga el **60%** del salario diario
  reportado, desde el **primer día**.

> Lo anterior es lo que leímos nosotros, no una interpretación de un contador.
> Donde más dudamos es en tres puntos: (a) si ese 50% de los días 1-3 se calcula
> sobre el salario diario completo o sobre media jornada, (b) sobre qué salario
> exactamente se saca el 60% de la CCSS, y (c) si en accidente de trabajo el
> **día del accidente** lo paga el INS o la empresa. Si alguno está mal, las
> preguntas de abajo cambian.

---

## Las preguntas

**1 · Primeros 3 días (enfermedad común).** ¿Pagamos el 50% como mínimo legal, o
conviene (o ya veníamos) pagando más?

**2 · Del día 4 en adelante.** ¿La CCSS le deposita el subsidio **directo al
trabajador**, o nos lo **reembolsa a nosotros** y nosotros se lo pagamos en
planilla?

**3 · Complemento.** Si quisiéramos que el trabajador cobre el 100%, ¿es correcto
que nosotros pongamos la diferencia (40%) sobre el 60% de la CCSS? ¿Cómo se
registra contablemente?

**4 · Con qué salario se calcula.** ¿El subsidio sale del salario **reportado a la
CCSS** (promedio de meses anteriores) o del salario de la quincena? ¿Cambia algo
porque pagamos por quincena?

**5 · Días.** ¿La incapacidad se paga por **días naturales** (incluye sábados,
domingos y feriados) o **solo días hábiles**?

**6 · Accidente de trabajo (INS).** Si pasara, ¿quién paga el **primer día** y
cómo es el trámite? ¿Algo especial en planilla?

**7 · Documento.** ¿Qué comprobante hay que guardar de cada incapacidad (boleta
CCSS / INS) y por cuánto tiempo?

**8 · Permisos médicos (citas).** Confirmar que pagarlos o pedir que se repongan
las horas es **decisión nuestra**, y que no hay un máximo legal.

---

## Qué decide cada respuesta, del lado del sistema

Esto es para nosotros, no hace falta que la contadora lo lea. Está acá para que
cada respuesta tenga un destino concreto y no se quede en una conversación.

| # | Dónde cae | Hoy vale |
|---|---|---|
| 1 | parámetro `incap_patrono_pct_dias_1_3` | 50 (mínimo legal citado) |
| 1 | parámetro `incap_patrono_pct_dia_4_en_adelante` | 0 (nada por encima del subsidio) |
| 2 | parámetro `incap_subsidio_lo_paga_la_empresa` | false (la Caja paga directo) |
| 3 | sube `incap_patrono_pct_dia_4_en_adelante` a 40 | — |
| 4 | define si la tarifa sale de `rrhh_salario` o de un promedio aparte | hoy: `rrhh_salario` |
| 5 | parámetro `incap_dias_naturales` | true (días naturales) |
| 6 | si el día 1 lo paga la empresa, `accidente_trabajo` necesita su propio porcentaje | hoy: mismo trato |
| 7 | campo `incapacidad_boleta` en `rrhh_permiso` (hoy opcional) | opcional |
| 8 | nada: ya está implementado como decisión nuestra (descuento / reposición) | — |

### Las dos que más pesan

**La 2 es la que puede invalidar el diseño entero.** Todo el módulo parte de un
supuesto: *el salario mensual ya paga todos los días del mes, y el sistema calcula
solo la **diferencia***. Si la CCSS le paga **directo al trabajador**, entonces
restar de la quincena los días que paga la Caja es correcto. Si en cambio **nos
reembolsa a nosotros**, el trabajador tiene que seguir cobrando por planilla y lo
que entra es un ingreso aparte — y ahí la resta de la quincena estaría de más, o
sea que le pagaríamos de menos. Son dos mecánicas distintas y el número final no
se parece.

**La 4 decide si alcanza con los datos que tenemos.** Hoy el sistema guarda un
salario mensual con vigencia, y de ahí saca la tarifa diaria. Si el subsidio se
calcula sobre un **promedio de meses reportados a la CCSS**, ese promedio **no
existe en el sistema** y habría que cargarlo o calcularlo — no es un parámetro, es
un dato nuevo.

### Lo que ya estaba escrito y nadie confirmó

Al revisar el esquema apareció que el módulo **ya traía** un modelo de
incapacidades, sembrado el 13-ago-2026 y nunca confirmado con nadie:

- `ccss_dias_empresa = 3` — los primeros 3 días los cubre la empresa;
- `ccss_pct_empresa = 0.5` — y los cubre al 50%;
- y la vista `v_rrhh_ajuste_detalle` ya calcula con eso, distinguiendo
  `incap_ins` de `incap_ccss`.

Coincide con lo que leímos, lo cual es tranquilizador, **pero nunca lo validó un
contador** y **ninguna pantalla lo usa**: medido con `grep`, nada escribe los tipos
`incap_ins` / `incap_ccss` y nada consulta `v_rrhh_ajuste`. O sea que es una regla
de plata que está en la base, parece correcta, y no mueve ni un colón hoy.

⚠️ Ojo con las **unidades**: el parámetro viejo guarda `0.5` (fracción) y los
nuevos van a guardar `50` (porcentaje). Dos parámetros que dicen lo mismo en
unidades distintas es como alguien termina dividiendo por 100 dos veces, o
ninguna. Queda anotado en el `.sql` y con una validación que lo caza.
