#!/usr/bin/env python3
"""
run_benchmark.py

Automatiza la medicion de rendimiento de la seccion 2.4.b del enunciado:
corre el binario indicado sobre los 4 tamanos grandes de entrada, con al
menos 30 repeticiones cada uno, y guarda promedio + desviacion estandar
en un CSV (uno por version: escalar o vectorial).

Los tiempos se leen del resumen '<output>.stats.txt' que escribe el
driver en C (campos kernel_ms, kernel_ms_sd y kernel_cycles), en lugar de
parsear la salida por consola.

Uso:
    python3 tools/run_benchmark.py bin/norm_scalar --label escalar
    python3 tools/run_benchmark.py bin/norm_vector --label vectorial --reps 50
"""

import argparse
import csv
import os
import subprocess
import sys

PERF_SIZES = [1000, 100_000, 1_000_000, 50_000_000]


def leer_resumen(path: str) -> dict:
    d = {}
    with open(path) as f:
        for linea in f:
            linea = linea.strip()
            if "=" in linea:
                k, v = linea.split("=", 1)
                d[k] = float(v)
    return d


def run_one(binary: str, input_path: str, output_path: str, reps: int):
    if not os.path.isfile(input_path):
        print(f"\n  ERROR: no existe '{input_path}' (corre 'make data').", file=sys.stderr)
        return None

    result = subprocess.run(
        [binary, input_path, output_path, str(reps)],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"\n  ERROR corriendo {binary} sobre {input_path}:", file=sys.stderr)
        print(f"  stderr: {result.stderr.strip()}", file=sys.stderr)
        return None

    stats_path = output_path + ".stats.txt"
    try:
        s = leer_resumen(stats_path)
        return s["kernel_ms"], s["kernel_ms_sd"], s.get("kernel_cycles", 0.0)
    except (OSError, KeyError) as e:
        print(f"\n  ERROR: no se pudo leer '{stats_path}': {e}", file=sys.stderr)
        return None


def main():
    parser = argparse.ArgumentParser(description="Benchmark de rendimiento (seccion 2.4.b).")
    parser.add_argument("binary", help="ruta al binario a medir, ej. bin/norm_scalar")
    parser.add_argument("--label", required=True, help="etiqueta de la version, ej. escalar")
    parser.add_argument("--datadir", default="data", help="carpeta con los input_perf_n*.dat")
    parser.add_argument("--reps", type=int, default=30, help="repeticiones por tamano (minimo 30)")
    parser.add_argument("--outfile", default=None,
                        help="CSV de salida (default: <datadir>/bench_<label>.csv)")
    args = parser.parse_args()

    if not os.path.isfile(args.binary):
        print(f"No existe el binario '{args.binary}'. Compila con make.", file=sys.stderr)
        return 2
    if args.reps < 30:
        print(f"Aviso: el enunciado pide al menos 30 repeticiones (usando {args.reps}).",
              file=sys.stderr)

    outfile = args.outfile or os.path.join(args.datadir, f"bench_{args.label}.csv")
    output_path = os.path.join(args.datadir, f"_bench_out_{args.label}.dat")
    rows = []

    print(f"Midiendo '{args.label}' ({args.binary}) con {args.reps} repeticiones por tamano...\n")
    for n in PERF_SIZES:
        input_path = os.path.join(args.datadir, f"input_perf_n{n}.dat")
        print(f"  N={n:>12,} ...", end=" ", flush=True)
        r = run_one(args.binary, input_path, output_path, args.reps)
        if r is None:
            print("FALLO")
            continue
        mean_ms, std_ms, cycles = r
        print(f"{mean_ms:.6f} ms  (+/- {std_ms:.6f} ms, {cycles:.0f} ciclos)")
        rows.append(dict(version=args.label, n=n, mean_ms=mean_ms, std_ms=std_ms,
                         cycles=cycles, reps=args.reps))

    # Borra la salida temporal (la de 5e7 pesa ~200 MB)
    for p in (output_path, output_path + ".stats.txt"):
        if os.path.exists(p):
            os.remove(p)

    with open(outfile, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["version", "n", "mean_ms", "std_ms", "cycles", "reps"])
        writer.writeheader()
        writer.writerows(rows)

    print(f"\nResultados guardados en: {outfile}")
    return 0 if len(rows) == len(PERF_SIZES) else 1


if __name__ == "__main__":
    sys.exit(main())
