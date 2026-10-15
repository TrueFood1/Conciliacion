# Preguntas para la contadora · feriados y valor del día

**Fecha:** 15-oct-2026 · **Para:** quien lleva las planillas de True Food CR
**De:** Andrea / Lorena

Esta nota no lleva ningún monto ni dato personal de salario: se puede reenviar tal
cual. Hermana de [`PREGUNTAS_contadora_incapacidades.md`](PREGUNTAS_contadora_incapacidades.md).

---

## Lo que ya decidimos nosotras (y que conviene que usted valide)

1. **Valor del día = neto de la quincena ÷ días hábiles de esa quincena**, y valor
   de la hora = valor del día ÷ 8. **No** se usa ÷15 ni ÷30.
2. **Días hábiles = lunes a viernes.** Sábado y domingo no cuentan ni descuentan.
3. **El divisor incluye los feriados.** Para el 1–15 de octubre de 2026 son **11**.
4. **Un feriado de pago obligatorio trabajado se paga doble**, y solo si cae de
   lunes a viernes. Se suma un día (o las horas × valor de hora) una sola vez,
   porque el feriado ya viene dentro del neto de la quincena.

## Las tres suposiciones que necesitamos que confirme

### 1 · Una ausencia que cae en un feriado, ¿descuenta?

**Nosotras supusimos que NO**, porque el feriado se paga igual. O sea: un permiso
sin goce del 9 al 13 de octubre descontaría 4 días y no 5, porque el 12 es feriado.

Es una suposición nuestra, no una regla que hayamos leído. Si está mal, cambia el
descuento de todo permiso que cruce un feriado.

### 2 · Un feriado OBLIGATORIO que no se trabaja, ¿suma un día?

Acá encontramos dos lecturas que no coinciden, y es plata:

- Para salario quincenal, el MTSS dice que el feriado **ya está incluido** en el
  pago ordinario y que **si se trabaja se paga doble**. Eso coincide con lo que
  armamos.
- Pero un informe del CIJUL-UCR sobre el art. 148 dice que, cuando el feriado es
  de **pago obligatorio**, *«debe adicionarse el día sencillo de salario, aunque al
  trabajador no le hubiera correspondido trabajar ese día bajo su jornada usual»*.

Si vale la segunda, el **25 de diciembre suma un día aunque nadie trabaje**, y lo
que armamos estaría de menos. **No lo implementamos hasta que usted lo diga.**

### 3 · Un feriado obligatorio que cae en sábado o domingo

Hoy **no sumamos nada**. Pero si la ley exige el día sencillo extra incluso cuando
el feriado cae en día no laborable, faltaría.

En lo que queda de 2026 **el caso no se presenta** (ninguno de los tres feriados
cae en fin de semana), así que no urge — pero en 2027 sí va a pasar.

---

## Los feriados que quedan en 2026 · verificado, para que lo confirme

| fecha | feriado | pago | día | ¿paga doble si se trabaja? |
|---|---|---|---|---|
| 12-10-2026 | Día de las Culturas | **no obligatorio** | lunes | no · *ya pasó* |
| 01-12-2026 | Abolición del Ejército | **no obligatorio** | martes | no |
| 25-12-2026 | Navidad | **OBLIGATORIO** | viernes | **sí** |

**Lo que queda del año tiene un solo feriado de pago obligatorio: el 25 de
diciembre.** Y es el único que califica para pago doble si se trabaja.

Lorena dijo que en True Food **solo se pagan los obligatorios**. Confírmenos que
esta lista es la correcta y completa.

Fuentes consultadas:
- [MTSS · el 1 de diciembre es de pago no obligatorio](https://www.mtss.go.cr/prensa/comunicados/2025/noviembre/cp_052_2025.html)
- [MTSS · el 25 de diciembre y el 1 de enero son de pago obligatorio](https://www.mtss.go.cr/prensa/comunicados/2024/diciembre/cp_061_2024.html)
- [Código de Trabajo de Costa Rica, art. 148 (PDF)](https://cuc.ac.cr/userfiles/files/normativa/externa/codigos/Codigo_Trabajo_RPL.pdf)
- [CIJUL-UCR · El pago de los días feriados en Costa Rica](https://cijulenlinea.ucr.ac.cr/portal/descargar.php?q=MjQ4OA%3D%3D)

---

## Pendientes nuestros, que no son de la contadora

Van acá para que no se pierdan.

### La segunda quincena en los meses de 31 días

`rrhh_quincena()` define Q2 = **día 16 hasta fin de mes**, o sea **16 días** en
octubre y diciembre. La regla del valor del día habla de «los 15 días del
período». **Se contradicen.**

En octubre da igual (11 hábiles de las dos formas). **En diciembre no:**

| quincena | divisor |
|---|---|
| 16 al 31 de diciembre | **12** |
| 16 al 30 de diciembre | **11** |

Hay que elegir, y afecta el valor del día de esa quincena.

### El cierre de planta de fin de año

`index.html` declara que el **18 de diciembre es el último día productivo** y que
la fábrica reabre el **11 de enero de 2027**.

Con el divisor nuevo eso no cambia el cálculo —el divisor es puro lunes a
viernes—, pero sí significa que en la segunda quincena de diciembre **se paga la
quincena completa trabajando 3 días** (16, 17 y 18). Probablemente sea lo
correcto, pero conviene que sea una decisión y no una sorpresa.

### Dos listas de feriados que no coinciden

La app tiene **dos** fuentes de feriados:

- **`rrhh_feriado`**, la tabla que usa el módulo Personal para el pago (y que
  desde ahora lleva la marca de pago obligatorio);
- una **lista quemada en el JS** (`index.html:9584`) que usa el planificador de
  producción y que en esta ventana solo conoce el 1 de diciembre: **no tiene el
  25 de diciembre**.

Pueden decir cosas distintas. Lo que manda para el pago es `rrhh_feriado`.
