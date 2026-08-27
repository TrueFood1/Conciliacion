# Pendientes de otros módulos

Anotados para cuando se retomen. **No construidos.** Entregas tiene su propio
archivo: `ENTREGAS_PENDIENTES.md`.

---

## F1 · Finanzas · Los montos se muestran REDONDEADOS

Reportado por Andrea el 26-ago-2026 probando desde el teléfono.

**Qué pasa.** Los montos a pagar —y probablemente también los de cobrar— se
muestran redondeados. Andrea necesita el **monto exacto**: un total redondeado no
cuadra contra el banco y **rompe el match en conciliación**, que es el trabajo
que ese número existe para permitir.

### ⚠️ Lo PRIMERO al retomarlo, antes de tocar nada

Averiguar si el redondeo es **solo de presentación** o si el número redondeado
**entra en cálculos**. Son dos problemas de gravedad muy distinta:

- **Solo presentación** → se arregla en el formateo. Molesto, no peligroso.
- **Entra en cálculos** → *más grave que lo reportado*: los totales, los saldos y
  cualquier comparación contra el banco estarían construidos sobre números que no
  son los de Odoo. Habría que revisar hacia atrás qué se decidió con ellos.

La forma de saberlo: seguir el número desde la lectura de Odoo hasta la pantalla y
ver **dónde** se redondea. Si se redondea al leer o al sumar, es el segundo caso.
Si se redondea solo en el `toLocaleString` de la vista, es el primero.

**No asumir que es presentación porque parezca presentación.** El caso de la UoM
(b34) también parecía cosmético y la cuenta estaba bien; acá puede ser al revés.

---

## O1 · Operaciones · El Planificador BLOQUEA el tope de batches, y debería avisar

Reportado por Andrea el 26-ago-2026.

**Qué pasa.** El Planificador no deja pasar del máximo de capacidad por producto
(con tres personas: Blanco 8, Semillas 10, Pizza 12, Francés 10, Buns 10).

**Decisión de Andrea: advertir y dejar pasar, con el motivo escrito. No bloquear.**

**El razonamiento, que es lo que hay que conservar:** ese tope es una **estimación
de capacidad**, no un límite físico. Se puede trabajar más horas o meter más
gente, y entonces el número deja de valer. Un bloqueo convierte una estimación en
una ley, y obliga a mentirle al sistema para reflejar lo que de verdad va a pasar.

**Es lo CONTRARIO del bloqueo de inventario**, y la diferencia es el punto:

| | Tope de batches | Saldo por lote |
|---|---|---|
| Qué es el límite | una estimación de capacidad | un hecho físico |
| ¿Se puede superar en la vida real? | **sí** — más horas, más gente | **no** — no se puede sacar pan que no existe |
| Qué debe hacer el sistema | **advertir** y dejar pasar | **bloquear** |

Al construirlo: el aviso tiene que decir **cuánto** se está pasando y **de qué
supuesto** (cuántas personas), no solo "te pasaste". Y el motivo de haberlo
superado se escribe, como todo lo demás del proyecto.
