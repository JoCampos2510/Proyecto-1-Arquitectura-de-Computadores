#!/usr/bin/env python3
"""
plot_speedup.py

Calcula Speedup = tiempo_escalar / tiempo_vectorial por tamano de N, usando
los CSV generados por run_benchmark.py, y grafica N (escala logaritmica) vs
Speedup -- tal como pide la seccion 2.4.b, punto 4, del enunciado.

Uso:
    python3 scripts/plot_speedup.py data/bench_escalar.csv data/bench_vectorial.csv \
        --out data/speedup.png
"""

import argparse
import csv
import sys

import matplotlib
matplotlib.use("Agg")  # no requiere entorno grafico (sirve en servidores/SSH)
import matplotlib.pyplot as plt


def read_bench_csv(path):
    rows = {}
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            n = int(row["n"])
            rows[n] = (float(row["mean_ms"]), float(row["std_ms"]))
    return rows


def main():
    parser = argparse.ArgumentParser(description="Calcula y grafica el speedup escalar vs vectorial.")
    parser.add_argument("scalar_csv", help="CSV generado por run_benchmark.py para la version escalar")
    parser.add_argument("vector_csv", help="CSV generado por run_benchmark.py para la version vectorial")
    parser.add_argument("--out", default="data/speedup.png", help="archivo de imagen de salida")
    args = parser.parse_args()

    scalar = read_bench_csv(args.scalar_csv)
    vector = read_bench_csv(args.vector_csv)

    common_sizes = sorted(set(scalar) & set(vector))
    if not common_sizes:
        print("Error: los dos CSV no tienen ningun tamano de N en comun.", file=sys.stderr)
        sys.exit(1)

    print(f"{'N':>12} | {'escalar (ms)':>14} | {'vectorial (ms)':>15} | {'speedup':>8}")
    print("-" * 58)

    sizes, speedups = [], []
    for n in common_sizes:
        s_mean, _ = scalar[n]
        v_mean, _ = vector[n]
        speedup = s_mean / v_mean
        sizes.append(n)
        speedups.append(speedup)
        print(f"{n:>12,} | {s_mean:>14.6f} | {v_mean:>15.6f} | {speedup:>7.2f}x")

    missing_scalar = sorted(set(vector) - set(scalar))
    missing_vector = sorted(set(scalar) - set(vector))
    if missing_scalar:
        print(f"\nAviso: estos tamanos solo estan en el CSV vectorial, se omiten: {missing_scalar}")
    if missing_vector:
        print(f"Aviso: estos tamanos solo estan en el CSV escalar, se omiten: {missing_vector}")

    fig, ax = plt.subplots(figsize=(8, 5))
    ax.plot(sizes, speedups, marker="o", linewidth=2, color="#2563eb")
    ax.axhline(y=8, color="gray", linestyle="--", linewidth=1, label="Speedup teorico maximo (8x, AVX2)")
    ax.set_xscale("log")
    ax.set_xlabel("N (escala logaritmica)")
    ax.set_ylabel("Speedup (tiempo_escalar / tiempo_vectorial)")
    ax.set_title("Speedup: escalar vs. vectorial")
    ax.grid(True, which="both", alpha=0.3)
    ax.legend()
    fig.tight_layout()
    fig.savefig(args.out, dpi=150)
    print(f"\nGrafica guardada en: {args.out}")


if __name__ == "__main__":
    main()
