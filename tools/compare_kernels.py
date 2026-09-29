#!/usr/bin/env python3
"""
Corre ambos kernels sobre la misma entrada y muestra lado a lado los
estadisticos que reporta cada uno, junto con la referencia calculada
en Python y el error relativo de cada version.

Ademas compara los dos arreglos normalizados entre si, para mostrar
que las diferencias de redondeo (orden distinto de las sumas en la
reduccion horizontal) caen dentro de la tolerancia del enunciado.

Uso:
    python3 tools/compare_kernels.py <input.dat> [--reps 30] [--tol 1e-4]
"""
import argparse
import math
import os
import struct
import subprocess
import sys

CAMPOS = ["n", "sum", "mean", "var", "stddev", "min", "max"]


def leer_dat(path):
    with open(path, "rb") as f:
        raw = f.read()
    n = struct.unpack_from("<i", raw, 0)[0]
    vals = list(struct.unpack_from(f"<{n}f", raw, 4)) if n else []
    return n, vals


def leer_resumen(path):
    d = {}
    with open(path) as f:
        for linea in f:
            if "=" in linea:
                k, v = linea.strip().split("=", 1)
                d[k] = float(v)
    return d


def referencia(vals, n):
    if n == 0:
        return dict.fromkeys(CAMPOS, 0.0)
    total = sum(vals)
    mean = total / n
    var = sum((x - mean) ** 2 for x in vals) / n
    return {
        "n": float(n), "sum": total, "mean": mean, "var": var,
        "stddev": math.sqrt(var), "min": min(vals), "max": max(vals),
    }


def err_rel(a, b):
    if abs(b) < 1e-12:
        return abs(a - b)
    return abs(a - b) / abs(b)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("input")
    p.add_argument("--scalar", default="bin/norm_scalar")
    p.add_argument("--vector", default="bin/norm_vector")
    p.add_argument("--outdir", default="data/compare")
    p.add_argument("--reps", type=int, default=30,
                   help="repeticiones del kernel para promediar el tiempo")
    p.add_argument("--tol", type=float, default=1e-4)
    args = p.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    base = os.path.splitext(os.path.basename(args.input))[0]
    salidas = {}
    for etiqueta, binario in (("escalar", args.scalar), ("vectorial", args.vector)):
        if not os.path.isfile(binario):
            print(f"No existe '{binario}'. Compila con make.")
            return 2
        out = os.path.join(args.outdir, f"{base}_{etiqueta}.dat")
        r = subprocess.run([binario, args.input, out, str(args.reps)],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(f"'{binario}' fallo:\n{r.stderr}")
            return 2
        salidas[etiqueta] = (out, leer_resumen(out + ".stats.txt"))

    n, vals = leer_dat(args.input)
    ref = referencia(vals, n)
    esc = salidas["escalar"][1]
    vec = salidas["vectorial"][1]

    print(f"Entrada: {args.input}   N = {n}   repeticiones = {args.reps}\n")
    print(f"{'campo':<9}{'referencia':>18}{'escalar':>18}{'vectorial':>18}"
          f"{'err esc':>12}{'err vec':>12}")
    print("-" * 87)
    todo_ok = True
    for c in CAMPOS:
        e, v, r = esc.get(c, float("nan")), vec.get(c, float("nan")), ref[c]
        ee, ev = err_rel(e, r), err_rel(v, r)
        todo_ok = todo_ok and ee <= args.tol and ev <= args.tol
        print(f"{c:<9}{r:>18.6f}{e:>18.6f}{v:>18.6f}{ee:>12.3g}{ev:>12.3g}")
    print("-" * 87)

    t_esc, t_vec = esc.get("kernel_ms", 0.0), vec.get("kernel_ms", 0.0)
    print(f"\n{'tiempo kernel':<20}escalar = {t_esc:.6f} ms    vectorial = {t_vec:.6f} ms")
    if t_vec > 0:
        print(f"{'speedup':<20}{t_esc / t_vec:.3f}x")

    # --- Arreglos normalizados: escalar vs vectorial ---
    _, y_esc = leer_dat(salidas["escalar"][0])
    _, y_vec = leer_dat(salidas["vectorial"][0])
    print("\nComparacion elemento a elemento de los arreglos normalizados:")
    if n == 0:
        print("  N = 0: no hay elementos que comparar.")
    else:
        peor, fuera, idx = 0.0, 0, -1
        for i, (a, b) in enumerate(zip(y_esc, y_vec)):
            d = abs(a - b)
            if d > peor:
                peor, idx = d, i
            if d > args.tol + args.tol * abs(b):
                fuera += 1
        print(f"  peor diferencia absoluta: {peor:.6g} (i = {idx})")
        print(f"  elementos fuera de tolerancia: {fuera} de {n}")
        todo_ok = todo_ok and fuera == 0

    print("\nRESULTADO:", "PASA" if todo_ok else "FALLA")
    return 0 if todo_ok else 1


if __name__ == "__main__":
    sys.exit(main())
