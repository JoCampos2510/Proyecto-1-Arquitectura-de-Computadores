#!/usr/bin/env python3
"""
run_benchmark.py

Automatiza la medicion de rendimiento de la seccion 2.4.b del enunciado:
corre el binario indicado sobre los 4 tamanos grandes de entrada, con al
menos 30 repeticiones cada uno, y guarda promedio + desviacion estandar
en un CSV (uno por version: escalar o vectorial).

Uso:
    python3 scripts/run_benchmark.py bin/norm_scalar --label escalar
    python3 scripts/run_benchmark.py bin/norm_vector --label vectorial --reps 50
"""

import argparse
import csv
import re
import subprocess
import sys

PERF_SIZES = [1000, 100_000, 1_000_000, 50_000_000]

LINE_RE = re.compile(
    r"tiempo_prom_ms=([\d.]+)\s+tiempo_std_ms=([\d.]+)\s+reps=(\d+)"
)


def run_one(binary: str, input_path: str, output_path: str, reps: int):
    result = subprocess.run(
        [binary, input_path, output_path, str(reps)],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"  ERROR corriendo {binary} sobre {input_path}:", file=sys.stderr)
        print(f"  stderr: {result.stderr.strip()}", file=sys.stderr)
        return None

    m = LINE_RE.search(result.stdout)
    if not m:
        print(f"  ERROR: no se pudo parsear la salida de {input_path}:", file=sys.stderr)
        print(f"  salida completa: {result.stdout.strip()}", file=sys.stderr)
        return None

    mean_ms, std_ms, actual_reps = m.groups()
    return float(mean_ms), float(std_ms), int(actual_reps)


def main():
    parser = argparse.ArgumentParser(description="Benchmark de rendimiento (seccion 2.4.b).")
    parser.add_argument("binary", help="ruta al binario a medir, ej. bin/norm_scalar")
    parser.add_argument("--label", required=True, help="etiqueta de la version, ej. escalar")
    parser.add_argument("--datadir", default="data", help="carpeta con los input_perf_n*.dat")
    parser.add_argument("--reps", type=int, default=30, help="repeticiones por tamano (minimo 30)")
    parser.add_argument("--outfile", default=None, help="CSV de salida (default: data/bench_<label>.csv)")
    args = parser.parse_args()

    if args.reps < 30:
        print(f"Aviso: el enunciado pide al menos 30 repeticiones (usando {args.reps}).", file=sys.stderr)

    outfile = args.outfile or f"data/bench_{args.label}.csv"
    rows = []

    print(f"Midiendo '{args.label}' ({args.binary}) con {args.reps} repeticiones por tamano...\n")
    for n in PERF_SIZES:
        input_path = f"{args.datadir}/input_perf_n{n}.dat"
        output_path = f"{args.datadir}/_bench_out_{args.label}.dat"
        print(f"  N={n:>12,} ...", end=" ", flush=True)
        r = run_one(args.binary, input_path, output_path, args.reps)
        if r is None:
            print("FALLO")
            continue
        mean_ms, std_ms, actual_reps = r
        print(f"{mean_ms:.6f} ms  (+/- {std_ms:.6f} ms, {actual_reps} reps)")
        rows.append(dict(version=args.label, n=n, mean_ms=mean_ms, std_ms=std_ms, reps=actual_reps))

    with open(outfile, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["version", "n", "mean_ms", "std_ms", "reps"])
        writer.writeheader()
        writer.writerows(rows)

    print(f"\nResultados guardados en: {outfile}")


if __name__ == "__main__":
    main()
