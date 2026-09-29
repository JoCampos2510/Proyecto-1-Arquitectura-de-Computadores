#!/usr/bin/env python3
"""
Corre la bateria completa de casos borde contra un binario del proyecto
y compara automaticamente cada resultado contra la referencia.

Para cada caso ejecuta:
  1. gen_input.py          -> genera data/tests/<caso>.dat
  2. el binario            -> produce <caso>.out.dat y <caso>.out.dat.stats.txt
  3. verify.py             -> compara el resumen de estadisticos y el
                              arreglo normalizado elemento a elemento

Imprime una tabla PASA/FALLA lista para transcribir a la seccion de
casos de prueba del informe (rubrica 3.b punto 5).

Uso:
    python3 tools/run_tests.py                       # usa bin/norm_vector
    python3 tools/run_tests.py --bin bin/norm_scalar
    python3 tools/run_tests.py -v                    # salida detallada
"""
import argparse
import os
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))

# (nombre, N, modo, descripcion para el informe)
CASOS = [
    ("n0",        0, "random",   "N = 0 (arreglo vacio)"),
    ("n1",        1, "random",   "N = 1 (var = 0)"),
    ("n7",        7, "random",   "N < 8: solo bucle remanente"),
    ("n8",        8, "random",   "N = 8: exactamente un bloque vectorial"),
    ("n15",      15, "random",   "N no multiplo de 8: 1 bloque + 7 de cola"),
    ("n16",      16, "random",   "N = 16: dos bloques exactos"),
    ("n1000",  1000, "random",   "N = 1000: 125 bloques exactos"),
    ("n1001",  1001, "random",   "N = 1001: bloques + 1 de cola"),
    ("const",  1000, "constant", "Todos los valores iguales (sigma = 0)"),
    ("neg",    1000, "negative", "Todos los valores negativos"),
    ("edge",   1000, "edge",     "Valores extremos y muy pequenos"),
]


def correr(cmd, verbose):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if verbose:
        sys.stdout.write(r.stdout)
        sys.stderr.write(r.stderr)
    return r


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--bin", default="bin/norm_vector", help="binario a probar")
    p.add_argument("--outdir", default="data/tests", help="directorio de trabajo")
    p.add_argument("--tol", type=float, default=1e-4, help="tolerancia relativa")
    p.add_argument("--seed", type=int, default=42, help="semilla del generador")
    p.add_argument("-v", "--verbose", action="store_true")
    args = p.parse_args()

    if not os.path.isfile(args.bin):
        print(f"No existe el binario '{args.bin}'. Compilalo primero (make).")
        return 2

    os.makedirs(args.outdir, exist_ok=True)
    gen = os.path.join(AQUI, "gen_input.py")
    ver = os.path.join(AQUI, "verify.py")

    print(f"Binario bajo prueba: {args.bin}")
    print(f"Tolerancia relativa: {args.tol:g}\n")

    filas = []
    for nombre, n, modo, desc in CASOS:
        dat = os.path.join(args.outdir, f"{nombre}.dat")
        out = os.path.join(args.outdir, f"{nombre}.out.dat")

        r = correr([sys.executable, gen, str(n), dat, modo, str(args.seed)], args.verbose)
        if r.returncode != 0:
            filas.append((nombre, desc, "ERROR-GEN", "-"))
            continue

        r = correr([args.bin, dat, out, "1"], args.verbose)
        if r.returncode != 0:
            filas.append((nombre, desc, "CRASH", "-"))
            continue

        r = correr(
            [sys.executable, ver, dat, out,
             "--rtol", str(args.tol), "--atol", str(args.tol), "--label", nombre],
            args.verbose,
        )
        # La ultima linea de verify.py es "RESUMEN=... ARREGLO=..."
        marcas = dict(
            tok.split("=", 1)
            for tok in r.stdout.strip().splitlines()[-1].split()
            if "=" in tok
        )
        filas.append((nombre, desc,
                      marcas.get("RESUMEN", "ERROR"),
                      marcas.get("ARREGLO", "ERROR")))

    print(f"{'caso':<8}{'descripcion':<46}{'estadisticos':>14}{'arreglo':>10}")
    print("-" * 78)
    todo_ok = True
    for nombre, desc, s, a in filas:
        todo_ok = todo_ok and s == "PASA" and a in ("PASA", "-")
        print(f"{nombre:<8}{desc:<46}{s:>14}{a:>10}")
    print("-" * 78)
    print("RESULTADO GENERAL:", "PASA" if todo_ok else "FALLA")
    print("\n(Usa -v para ver el detalle de cada comparacion.)")
    return 0 if todo_ok else 1


if __name__ == "__main__":
    sys.exit(main())
