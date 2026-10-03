#!/usr/bin/env python3
"""
Verificacion completa de una corrida del kernel contra una referencia
calculada aqui mismo. Reemplaza a verify_reference.py y verify_output.py:
en una sola pasada revisa

  1. el resumen de estadisticos que el driver escribe en
     '<output>.dat.stats.txt': n, sum, mean, var, stddev, min, max
     (cubre sum_array y compute_stats)
  2. los N elementos del arreglo normalizado '<output>.dat'
     (cubre normalize_array)

Hacen falta las dos: min y max solo aparecen en el resumen, y el arreglo
normalizado es la unica evidencia de normalize_array.

Referencia (definida en stats.h / enunciado):
    mean = sum(x)/n
    var  = sum((x-mean)^2)/n        (poblacional)
    sigma = sqrt(var)
    y[i] = (x[i]-mean)/sigma        y[i] = x[i] si sigma == 0

Criterios de aceptacion, distintos porque los datos lo son:
  - resumen: error relativo puro <= rtol. Son agregados que no pasan
    por cero, asi que el error relativo es significativo.
  - arreglo: |obtenido - ref| <= atol + rtol*|ref|. Un z-score si cruza
    el cero, y ahi el error relativo puro se dispara sin que exista un
    error numerico real.

Uso:
    python3 verify.py <input.dat> <output.dat> [--rtol 1e-4] [--atol 1e-4]
                      [--stats <resumen.txt>] [--show 5] [--label texto]
    python3 verify.py <input.dat> <output.dat> --solo stats|arreglo

Codigo de salida: 0 si todo pasa, 1 si algo falla.
La ultima linea siempre es legible por maquina:
    RESUMEN=PASA ARREGLO=PASA
(el valor es OMITIDO cuando esa parte no se reviso)
"""
import argparse
import math
import os
import struct
import sys

try:
    import numpy as np
except ImportError:
    np = None

CAMPOS = ["n", "sum", "mean", "var", "stddev", "min", "max"]


def leer_dat(path):
    """Lee el formato comun de entrada/salida: int32 n + n float32."""
    with open(path, "rb") as f:
        raw = f.read()
    if len(raw) < 4:
        raise ValueError(f"'{path}': archivo demasiado corto (falta N)")
    n = struct.unpack_from("<i", raw, 0)[0]
    if n < 0:
        raise ValueError(f"'{path}': N invalido ({n})")
    esperado = 4 + 4 * n
    if len(raw) < esperado:
        raise ValueError(
            f"'{path}': archivo truncado, se esperaban {esperado} bytes y hay {len(raw)}"
        )
    if np is not None:
        vals = np.frombuffer(raw, dtype="<f4", count=n, offset=4).astype(np.float64)
    else:
        vals = list(struct.unpack_from(f"<{n}f", raw, 4)) if n else []
    return n, vals


def leer_resumen(path):
    d = {}
    with open(path) as f:
        for linea in f:
            linea = linea.strip()
            if linea and "=" in linea:
                k, v = linea.split("=", 1)
                d[k] = float(v)
    return d


def referencia(x, n):
    """Devuelve (dict de estadisticos, arreglo normalizado) en doble precision."""
    if n == 0:
        vacio = [] if np is None else np.empty(0)
        return dict.fromkeys(CAMPOS, 0.0), vacio

    if np is not None:
        total = float(x.sum())
        mean = total / n
        var = float(((x - mean) ** 2).sum() / n)
        sigma = math.sqrt(var)
        y = x.copy() if sigma == 0.0 else (x - mean) / sigma
        mn, mx = float(x.min()), float(x.max())
    else:
        total = sum(x)
        mean = total / n
        var = sum((v - mean) ** 2 for v in x) / n
        sigma = math.sqrt(var)
        y = list(x) if sigma == 0.0 else [(v - mean) / sigma for v in x]
        mn, mx = min(x), max(x)

    stats = {"n": float(n), "sum": total, "mean": mean, "var": var,
             "stddev": sigma, "min": mn, "max": mx}
    return stats, y


def err_rel(a, b):
    if abs(b) < 1e-12:
        return abs(a - b)
    return abs(a - b) / abs(b)


def revisar_resumen(ref, got, rtol):
    print("  -- resumen de estadisticos --")
    print(f"  {'campo':<9}{'referencia':>18}{'obtenido':>18}{'error rel.':>14}  resultado")
    ok_total = True
    for c in CAMPOS:
        r = ref[c]
        v = got.get(c, float("nan"))
        e = abs(v - r) if c == "n" else err_rel(v, r)
        ok = (e == 0) if c == "n" else (e <= rtol)
        ok_total = ok_total and ok
        print(f"  {c:<9}{r:>18.6f}{v:>18.6f}{e:>14.6g}  {'OK' if ok else 'FALLA'}")
    return ok_total


def revisar_arreglo(ref, got, n, rtol, atol, show, x):
    print("  -- arreglo normalizado --")
    if n == 0:
        print("  N = 0: no hay elementos que comparar.")
        return True

    if np is not None:
        finito = np.isfinite(ref) & np.isfinite(got)
        err = np.abs(got - ref)
        malos = (~finito) | (err > atol + rtol * np.abs(ref))
        idx = np.flatnonzero(malos)
        peor = float(err[finito].max()) if finito.any() else float("inf")
        fallos, ejemplos = len(idx), idx[:show].tolist()
    else:
        fallos, peor, ejemplos = 0, 0.0, []
        for i, (r, g) in enumerate(zip(ref, got)):
            if not (math.isfinite(r) and math.isfinite(g)):
                ok = False
            else:
                e = abs(g - r)
                peor = max(peor, e)
                ok = e <= atol + rtol * abs(r)
            if not ok:
                fallos += 1
                if len(ejemplos) < show:
                    ejemplos.append(i)

    print(f"  peor error absoluto: {peor:.6g}   (limite = {atol:g} + {rtol:g}*|ref|)")
    print(f"  elementos fuera de tolerancia: {fallos} de {n}")
    for i in ejemplos:
        print(f"    i={i:<10} entrada={float(x[i]):<+15.7g} "
              f"ref={float(ref[i]):<+15.7g} obtenido={float(got[i]):<+15.7g}")
    return fallos == 0


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("input", help="archivo de entrada (int32 N + N float32)")
    p.add_argument("output", help="archivo de salida normalizado del kernel")
    p.add_argument("--stats", default=None,
                   help="resumen de texto (por defecto <output>.stats.txt)")
    p.add_argument("--rtol", type=float, default=1e-4, help="tolerancia relativa")
    p.add_argument("--atol", type=float, default=1e-4,
                   help="tolerancia absoluta (solo para el arreglo)")
    p.add_argument("--show", type=int, default=5, help="elementos discrepantes a listar")
    p.add_argument("--label", default="", help="etiqueta para el reporte")
    p.add_argument("--solo", choices=["stats", "arreglo"], default=None,
                   help="revisar unicamente una de las dos partes")
    args = p.parse_args()

    stats_path = args.stats or (args.output + ".stats.txt")
    etiqueta = f"[{args.label}] " if args.label else ""
    print(f"{etiqueta}{args.input} -> {args.output}")
    print(f"  motor de referencia: {'numpy' if np is not None else 'python puro'}")

    n_in, x = leer_dat(args.input)
    n_out, y_got = leer_dat(args.output)
    if n_in != n_out:
        print(f"  FALLA: N no coincide (entrada={n_in}, salida={n_out})")
        print("RESUMEN=FALLA ARREGLO=FALLA")
        return 1

    ref_stats, y_ref = referencia(x, n_in)
    print(f"  N={n_in}  mean={ref_stats['mean']:.9g}  var={ref_stats['var']:.9g}  "
          f"sigma={ref_stats['stddev']:.9g}")
    if n_in and ref_stats["stddev"] == 0.0:
        print("  caso sigma=0: la referencia es una copia de la entrada (sin normalizar)")

    ok_stats = ok_arr = "OMITIDO"

    if args.solo != "arreglo":
        if not os.path.isfile(stats_path):
            print(f"  FALLA: no existe el resumen '{stats_path}'")
            ok_stats = False
        else:
            ok_stats = revisar_resumen(ref_stats, leer_resumen(stats_path), args.rtol)

    if args.solo != "stats":
        ok_arr = revisar_arreglo(y_ref, y_got, n_in, args.rtol, args.atol, args.show, x)

    def etq(v):
        return "OMITIDO" if v == "OMITIDO" else ("PASA" if v else "FALLA")

    todo_ok = all(v is True or v == "OMITIDO" for v in (ok_stats, ok_arr))
    print("  RESULTADO:", "PASA" if todo_ok else "FALLA")
    print(f"RESUMEN={etq(ok_stats)} ARREGLO={etq(ok_arr)}")
    return 0 if todo_ok else 1


if __name__ == "__main__":
    sys.exit(main())
