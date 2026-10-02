#!/usr/bin/env python3
"""
generate_test_data.py

Genera los archivos binarios input_*.dat para el proyecto de curso
"Programación Vectorial en Ensamblador x86-64 (NASM/Linux)".

Formato del archivo (little endian), según la sección 2.2 del enunciado:
    int32   N            -- cantidad de elementos
    float32 x[0..N-1]    -- arreglo de datos, N * 4 bytes

Genera tres grupos de archivos:
  1. Tamaños pequeños para verificación de correctud: N = 0, 1, 7, 8, 15, 16, 1000
  2. Casos borde adicionales (sección 2.3): todos los valores iguales (sigma=0),
     valores negativos, valores extremos
  3. Tamaños grandes para medición de rendimiento: 10^3, 10^5, 10^6, 5*10^7

Uso:
    python3 generate_test_data.py [--outdir data] [--seed 42]
"""

import argparse
import os
import struct

import numpy as np


def write_input_file(path: str, arr: np.ndarray) -> None:
    """Escribe un input.dat: N (int32 LE) seguido del arreglo (float32 LE)."""
    arr = arr.astype("<f4")  # fuerza float32 little endian
    n = arr.shape[0]
    with open(path, "wb") as f:
        f.write(struct.pack("<i", n))  # N como int32 little endian
        f.write(arr.tobytes())         # arreglo empaquetado, sin padding
    size_kb = os.path.getsize(path) / 1024
    print(f"  {os.path.basename(path):26s} N={n:>10d}  ({size_kb:>12.1f} KB)")


def gen_random(n: int, rng: np.random.Generator, low=-100.0, high=100.0) -> np.ndarray:
    return rng.uniform(low, high, size=n).astype(np.float32)


def main():
    parser = argparse.ArgumentParser(
        description="Genera los datos de prueba (input.dat) para el proyecto de vectorización SIMD."
    )
    parser.add_argument("--outdir", default="data", help="directorio de salida (default: data/)")
    parser.add_argument("--seed", type=int, default=42, help="semilla del generador aleatorio (default: 42)")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    rng = np.random.default_rng(args.seed)

    print("Generando casos de verificación de correctud (tamaños pequeños):")
    small_sizes = [0, 1, 7, 8, 15, 16, 1000]
    for n in small_sizes:
        arr = gen_random(n, rng)
        write_input_file(os.path.join(args.outdir, f"input_n{n}.dat"), arr)

    print("\nGenerando casos borde adicionales (sección 2.3 del enunciado):")

    # Todos los valores iguales -> sigma = 0, debe evitarse la división por cero
    arr_equal = np.full(64, 7.5, dtype=np.float32)
    write_input_file(os.path.join(args.outdir, "input_all_equal.dat"), arr_equal)

    # Valores negativos
    arr_negative = rng.uniform(-500.0, -1.0, size=100).astype(np.float32)
    write_input_file(os.path.join(args.outdir, "input_negative.dat"), arr_negative)

    # Valores extremos (cercanos a los límites representables de float32)
    arr_extreme = np.array(
        [3.4e38, -3.4e38, 1.2e-38, -1.2e-38, 0.0, -0.0, 1.0, -1.0],
        dtype=np.float32,
    )
    write_input_file(os.path.join(args.outdir, "input_extreme.dat"), arr_extreme)

    print("\nGenerando casos de medición de rendimiento (tamaños grandes):")
    large_sizes = [10**3, 10**5, 10**6, 5 * 10**7]
    for n in large_sizes:
        arr = gen_random(n, rng)
        write_input_file(os.path.join(args.outdir, f"input_perf_n{n}.dat"), arr)

    print(f"\nListo. Archivos generados en: {os.path.abspath(args.outdir)}/")


if __name__ == "__main__":
    main()
