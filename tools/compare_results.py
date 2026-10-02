#!/usr/bin/env python3
"""
compare_results.py

Compara el output_scalar.dat / output_vector.dat producido por tu programa
en C/NASM contra el arreglo normalizado de referencia generado por
compute_reference.py, verificando que el error relativo esté dentro de la
tolerancia de 1e-4 definida en la sección 2.3 del enunciado.

Uso:
    python3 compute_reference.py data/input_n1000.dat
    python3 compare_results.py reference/input_n1000_normalized.dat \
        output_vector.dat --label vectorial
"""

import argparse
import struct
import sys

import numpy as np

TOL = 1e-4


def read_output_file(path: str):
    with open(path, "rb") as f:
        data = f.read()
    n = struct.unpack("<i", data[0:4])[0]
    if n > 0:
        arr = np.frombuffer(data[4:4 + n * 4], dtype="<f4")
    else:
        arr = np.array([], dtype=np.float32)
    return n, arr


def main():
    parser = argparse.ArgumentParser(
        description="Compara la salida de tus kernels NASM contra la referencia NumPy."
    )
    parser.add_argument("reference_dat", help="archivo *_normalized.dat de compute_reference.py")
    parser.add_argument("output_dat", help="output_scalar.dat u output_vector.dat de tu programa")
    parser.add_argument("--label", default="", help="etiqueta para el reporte (ej. 'escalar')")
    args = parser.parse_args()

    n_ref, ref_arr = read_output_file(args.reference_dat)
    n_out, out_arr = read_output_file(args.output_dat)

    label = f"[{args.label}] " if args.label else ""
    ok = True

    if n_ref != n_out:
        print(f"{label}FALLA: N no coincide (referencia={n_ref}, obtenido={n_out})")
        sys.exit(1)

    if n_ref == 0:
        print(f"{label}N=0: caso borde sin arreglo que comparar. PASA.")
        sys.exit(0)

    ref64 = ref_arr.astype(np.float64)
    out64 = out_arr.astype(np.float64)
    errors = np.abs(ref64 - out64)
    denom = np.maximum(np.abs(ref64), 1e-12)  # evita división por cero en el propio comparador
    rel_errors = errors / denom

    max_rel_error = float(rel_errors.max())
    idx_worst = int(rel_errors.argmax())
    ok = max_rel_error <= TOL

    status = "PASA" if ok else "FALLA"
    print(f"{label}N={n_ref}  {status}  (error relativo máx = {max_rel_error:.2e}, "
          f"tolerancia = {TOL:.0e})")
    if not ok:
        print(f"{label}  Peor caso en índice {idx_worst}: "
              f"referencia={ref_arr[idx_worst]:.6f}  obtenido={out_arr[idx_worst]:.6f}")

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
