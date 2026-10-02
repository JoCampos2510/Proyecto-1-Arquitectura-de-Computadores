#!/usr/bin/env python3
"""
compute_reference.py

Calcula, con NumPy, los estadísticos de referencia y el arreglo normalizado
esperado para un archivo input_*.dat, para comparar contra las
implementaciones en NASM (escalar y vectorial). Ver sección 2.4.a del
enunciado del proyecto.

Uso:
    python3 compute_reference.py data/input_n1000.dat
    python3 compute_reference.py data/input_n1000.dat --outdir reference
"""

import argparse
import json
import os
import struct

import numpy as np


def read_input_file(path: str):
    with open(path, "rb") as f:
        data = f.read()
    n = struct.unpack("<i", data[0:4])[0]
    if n > 0:
        arr = np.frombuffer(data[4:4 + n * 4], dtype="<f4")
    else:
        arr = np.array([], dtype=np.float32)
    return n, arr


def compute_stats(n: int, arr: np.ndarray) -> dict:
    """Replica exactamente las reglas de casos borde del enunciado (sección 2.3)."""
    if n == 0:
        return dict(n=0, sum=0.0, mean=0.0, var=0.0, std=0.0, min=0.0, max=0.0)

    # Se calcula en float64 para que la referencia tenga más precisión que
    # el kernel bajo prueba (que trabaja en float32) y no introduzca su
    # propio error de redondeo en la comparación.
    arr64 = arr.astype(np.float64)
    total = float(arr64.sum())
    mean = total / n
    var = float(np.mean((arr64 - mean) ** 2))  # varianza poblacional (ddof=0)
    std = var ** 0.5

    return dict(
        n=n, sum=total, mean=mean, var=var, std=std,
        min=float(arr64.min()), max=float(arr64.max()),
    )


def normalize(n: int, arr: np.ndarray, mean: float, std: float) -> np.ndarray:
    if n == 0:
        return np.array([], dtype=np.float32)
    if std == 0.0:
        # Mismo caso borde que normalize_array en NASM: evita división por cero.
        return np.zeros(n, dtype=np.float32)
    return ((arr.astype(np.float64) - mean) / std).astype(np.float32)


def main():
    parser = argparse.ArgumentParser(description="Genera valores de referencia con NumPy.")
    parser.add_argument("input_file", help="archivo input_*.dat a procesar")
    parser.add_argument("--outdir", default="reference", help="directorio de salida")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    base = os.path.splitext(os.path.basename(args.input_file))[0]

    n, arr = read_input_file(args.input_file)
    stats = compute_stats(n, arr)
    normalized = normalize(n, arr, stats["mean"], stats["std"])

    stats_path = os.path.join(args.outdir, f"{base}_stats.json")
    with open(stats_path, "w") as f:
        json.dump(stats, f, indent=2)

    out_path = os.path.join(args.outdir, f"{base}_normalized.dat")
    with open(out_path, "wb") as f:
        f.write(struct.pack("<i", n))
        f.write(normalized.tobytes())

    print(f"N = {n}")
    for k in ("sum", "mean", "var", "std", "min", "max"):
        print(f"  {k:5s} = {stats[k]:.6f}")
    print(f"Stats de referencia guardados en: {stats_path}")
    print(f"Arreglo normalizado de referencia en: {out_path}")


if __name__ == "__main__":
    main()
