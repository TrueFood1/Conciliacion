#!/usr/bin/env python3
"""
Puente de limpieza del extracto BAC.

Toma el XLS crudo del banco (formato viejo BIFF/CDFV2, una sola hoja "Report1")
y produce una tabla limpia lista para importar a Odoo.

Estructura del XLS crudo:
  - Decoración del banco arriba (nombre, saldos, "CURRENT PERIOD ACTIVITY DETAILS").
  - Fila de encabezado real: Date | Reference | _ | Code | Description | _ | _ | Debits | Credits | Balance*
    (índices 0-base: 0=Date, 1=Reference, 3=Code, 4=Description, 7=Debits, 8=Credits, 9=Balance)
  - Movimientos reales hasta la primera fila en blanco.
  - Después de la fila en blanco viene un "Summary chart" con totales -> se descarta.

Salida: fecha (ISO yyyy-mm-dd), referencia, codigo, descripcion, monto (un solo
número con signo), saldo.
  monto = -Debits si hay débito (sale plata), +Credits si hay crédito (entra plata).

Uso:  python3 limpiar_extracto.py "Monthly transactions (3).xls" [salida.csv]
"""
import sys
import csv
import xlrd

# Índices de columna (0-base) en el XLS crudo
C_DATE, C_REF, C_CODE, C_DESC, C_DEBIT, C_CREDIT, C_BALANCE = 0, 1, 3, 4, 7, 8, 9


def _s(v):
    """Normaliza a string limpio."""
    if v is None:
        return ""
    if isinstance(v, float) and v == int(v):
        # referencias/códigos numéricos -> sin .0
        return str(int(v))
    return str(v).strip()


def _num(v):
    """Devuelve float o 0.0 si está vacío/no numérico."""
    if isinstance(v, (int, float)):
        return float(v)
    s = str(v).strip().replace(",", "")
    try:
        return float(s)
    except ValueError:
        return 0.0


def _fecha_iso(v):
    """dd/mm/yyyy -> yyyy-mm-dd."""
    s = str(v).strip()
    if "/" in s:
        d, m, y = s.split("/")
        return "%04d-%02d-%02d" % (int(y), int(m), int(d))
    return s


def limpiar(path_xls):
    wb = xlrd.open_workbook(path_xls)
    sh = wb.sheet_by_index(0)

    def cell(r, c):
        return sh.cell_value(r, c) if c < sh.ncols else ""

    # 1) localizar la fila de encabezado real (Date + Code, no la decoración)
    header_row = None
    for r in range(sh.nrows):
        if _s(cell(r, C_DATE)) == "Date" and _s(cell(r, C_CODE)) == "Code":
            header_row = r
            break
    if header_row is None:
        raise RuntimeError("No se encontró la fila de encabezado (Date/Code).")

    filas = []
    # 2) leer desde la fila siguiente al encabezado hasta la primera fila vacía
    for r in range(header_row + 1, sh.nrows):
        vals = [cell(r, c) for c in range(sh.ncols)]
        if all(_s(v) == "" for v in vals):
            break  # corte limpio: primera fila en blanco

        debito = _num(cell(r, C_DEBIT))
        credito = _num(cell(r, C_CREDIT))

        # saltar filas sin movimiento (p. ej. "Initial balance")
        if debito == 0 and credito == 0:
            continue

        monto = -debito if debito != 0 else credito

        filas.append({
            "fecha": _fecha_iso(cell(r, C_DATE)),
            "referencia": _s(cell(r, C_REF)),
            "codigo": _s(cell(r, C_CODE)),
            "descripcion": _s(cell(r, C_DESC)),
            "monto": round(monto, 2),
            "saldo": round(_num(cell(r, C_BALANCE)), 2),
        })
    return filas


def guardar_csv(filas, path_csv):
    campos = ["fecha", "referencia", "codigo", "descripcion", "monto", "saldo"]
    with open(path_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=campos)
        w.writeheader()
        w.writerows(filas)


def guardar_js(filas, path_js):
    """Emite la tabla limpia como archivo JS para que la herramienta (index.html)
    monte exactamente estos movimientos validados en Odoo (botón Importar al BAC)."""
    import json
    with open(path_js, "w", encoding="utf-8") as f:
        f.write("// Generado por limpiar_extracto.py — NO editar a mano.\n")
        f.write("// Tabla limpia del extracto BAC, lista para montar en Odoo.\n")
        f.write("window.EXTRACTO_LIMPIO = ")
        json.dump(filas, f, ensure_ascii=False, indent=1)
        f.write(";\n")


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else "Monthly transactions (3).xls"
    out = sys.argv[2] if len(sys.argv) > 2 else "extracto_limpio.csv"
    filas = limpiar(src)
    guardar_csv(filas, out)
    guardar_js(filas, "extracto_limpio.js")
    print("OK: %d movimientos -> %s  (+ extracto_limpio.js)" % (len(filas), out))

    # vista previa
    campos = ["fecha", "referencia", "codigo", "descripcion", "monto", "saldo"]
    anchos = {"fecha": 10, "referencia": 11, "codigo": 6, "descripcion": 34, "monto": 13, "saldo": 13}
    linea = "  ".join(c.upper().ljust(anchos[c]) for c in campos)
    print(linea)
    print("-" * len(linea))
    for row in filas[:15]:
        celdas = []
        for c in campos:
            v = row[c]
            if c in ("monto", "saldo"):
                v = "{:,.2f}".format(v)
                celdas.append(str(v).rjust(anchos[c]))
            else:
                v = str(v)
                if len(v) > anchos[c]:
                    v = v[:anchos[c] - 1] + "…"
                celdas.append(v.ljust(anchos[c]))
        print("  ".join(celdas))
