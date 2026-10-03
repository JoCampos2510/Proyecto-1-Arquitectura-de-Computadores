# Normalizador estadístico vectorizado (x86-64 NASM, escalar vs. AVX2)

Proyecto 1 de Arquitectura de Computadores, Escuela de Ingeniería Electrónica, Tecnológico de Costa Rica.

El programa calcula los estadísticos descriptivos de un arreglo de floats de precisión simple (suma, media, varianza poblacional, desviación estándar, mínimo y máximo) y produce su versión normalizada (z-score):

y[i] = (x[i] - μ) / σ  

El núcleo de cómputo está implementado en ensamblador NASM en dos versiones funcionalmente equivalentes:

- **Escalar:** instrucciones escalares de SSE (movss, addss, divss, ...), un elemento por iteración.
- **Vectorial:** instrucciones AVX2 sobre registros YMM (vmovaps, vaddps, vdivps, ...), ocho elementos por iteración, con reducción horizontal y bucle de remanente.

Un *driver* en C lee la entrada, reserva memoria alineada a 32 bytes, mide el tiempo del kernel y escribe los resultados.

## Estudiantes

- Josué Campos Herrera
- Eduardo Franco Román Vargas

## Estructura del repositorio

.  
├── asm/  
│   ├── scalar/stats_scalar.asm      # Kernels escalares  
│   └── vector/statsvar_vector.asm   # Kernels vectoriales (AVX2)  
├── include/stats.h                  # Firmas comunes de los kernels  
├── src/driver.c                     # Driver en C (E/S, memoria, medición)  
├── tools/  
│   ├── generate_test_data.py        # Genera los archivos de entrada  
│   ├── verify.py                    # Verifica contra la referencia NumPy  
│   ├── compare_kernels.py           # Compara escalar vs. vectorial  
│   ├── run_benchmark.py             # Mide el rendimiento (30 repeticiones)  
│   └── plot_speedup.py              # Grafica el speedup  
├── Makefile  
└── README.md  

Las carpetas obj/, bin/ y data/ se generan al compilar y ejecutar.

## Requisitos

- Linux x86-64 con soporte AVX2
- NASM ≥ 2.15, GCC, GDB ≥ 10
- Python 3 con NumPy y Matplotlib
- perf (opcional, para los contadores de hardware)

En Ubuntu:

sudo apt install nasm gcc gdb python3-numpy python3-matplotlib  
sudo apt install linux-tools-common linux-tools-$(uname -r)   # perf  

Para verificar el soporte de AVX2:

make check-avx2  

## Compilación

make  

Produce dos binarios que comparten el mismo driver:

- bin/norm_scalar: enlazado con los kernels escalares
- bin/norm_vector: enlazado con los kernels vectoriales

Si el archivo vectorial se renombra, se puede indicar la ruta al compilar:

make ASM_VECTOR=asm/vector/otro_nombre.asm  

## Uso

./bin/norm_vector &lt;input.dat&gt; &lt;output.dat&gt; [repeticiones]  

- input.dat: archivo binario de entrada
- output.dat: archivo binario con el arreglo normalizado
- repeticiones: veces que se repite el kernel para promediar el tiempo (por defecto, 1)

Además de imprimir los resultados en consola, el driver escribe un resumen en texto plano en <output.dat>.stats.txt.

Ejemplo:

make data  
./bin/norm_vector data/input_n1000.dat data/output_vector.dat 10  

### Formato de los archivos (little endian)

| Campo | Tipo | Tamaño |
|-------|------|--------|
| N | int32 | 4 bytes |
| arr[0..N-1] | float32 | N × 4 bytes |

Los archivos de entrada y de salida usan el mismo formato.

## Targets del Makefile

| Comando | Descripción |
|---------|-------------|
| make | Compila ambos binarios |
| make check-avx2 | Verifica el soporte de AVX2 del procesador |
| make data | Genera los archivos de entrada (solo la primera vez) |
| make run-scalar / make run-vector | Ejecuta una versión sobre INPUT (por defecto data/input_n1000.dat) |
| make test | Verifica ambas versiones en los casos pequeños y de borde (tabla resumida) |
| make test-scalar / make test-vector | Igual que make test, para una sola versión |
| make verify-scalar / make verify-vector | Verifica **todos** los tamaños, incluidos los de rendimiento, con el detalle completo |
| make compare INPUT=... | Compara escalar contra vectorial sobre una misma entrada |
| make bench | Mide el rendimiento de ambas versiones (30 repeticiones por tamaño) |
| make plot | Genera data/speedup.png a partir de los resultados de make bench |
| make clean | Borra objetos, binarios y salidas de prueba |
| make distclean | Además borra los datos generados |

Las variables INPUT y REPS se pueden cambiar desde la línea de comandos, por ejemplo make bench REPS=50.

## Datos de prueba

make data ejecuta tools/generate_test_data.py con semilla 42 y genera:

| Grupo | Archivos |
|-------|----------|
| Correctitud | input_n0, input_n1, input_n7, input_n8, input_n15, input_n16, input_n1000 |
| Casos borde | input_all_equal (σ = 0), input_negative, input_extreme |
| Rendimiento | input_perf_n1000, input_perf_n100000, input_perf_n1000000, input_perf_n50000000 |

El archivo de 5×10⁷ elementos ocupa unos 200 MB.

## Verificación

tools/verify.py recalcula en doble precisión los estadísticos y el arreglo normalizado, y los compara con la salida del kernel:

./bin/norm_scalar data/input_n16.dat /tmp/out.dat 1  
python3 tools/verify.py data/input_n16.dat /tmp/out.dat  

Criterios de aceptación:

- **Estadísticos:** error relativo ≤ 10⁻⁴
- **Arreglo normalizado:** |obtenido − referencia| ≤ 10⁻⁴ + 10⁻⁴·|referencia|

Opciones útiles: --solo stats o --solo arreglo para revisar una sola parte, --rtol y --atol para cambiar las tolerancias, y --show N para listar más elementos discrepantes.

## Casos borde

| Caso | Comportamiento |
|------|----------------|
| N = 0 | Todos los estadísticos valen 0 y no se divide entre N |
| σ = 0 (N = 1 o todos los valores iguales) | La salida es una copia de la entrada, sin división entre cero |
| N no múltiplo de 8 | El bucle de remanente procesa los elementos sobrantes |
| Valores negativos | Mínimo y máximo se inicializan con arr[0], no con 0 |

## Medición de rendimiento

make bench  
make plot  

make bench guarda los resultados en data/bench_escalar.csv y data/bench_vectorial.csv, con el tiempo promedio, la desviación estándar y los ciclos por tamaño. El driver mide solo los kernels, excluyendo la lectura y escritura de archivos, con clock_gettime(CLOCK_MONOTONIC) y __rdtsc.

Para los contadores de hardware:

EV=cycles,instructions,cache-references,cache-misses  
perf stat -e $EV ./bin/norm_vector data/input_perf_n50000000.dat /tmp/o.dat 1  
perf stat -e $EV ./bin/norm_vector data/input_perf_n50000000.dat /tmp/o.dat 31  

Como perf mide el proceso completo, la diferencia entre las corridas de 31 y 1 repeticiones aísla 30 ejecuciones del kernel.

Si perf no tiene permisos:

sudo sysctl kernel.perf_event_paranoid=1  

## Depuración con GDB

Ejemplo de inspección del registro YMM en el bucle vectorial de sum_array con N = 16:

gdb --args ./bin/norm_vector data/input_n16.dat data/output_vector.dat 1  

(gdb) break statsvar_vector.asm:22  
(gdb) break statsvar_vector.asm:23  
(gdb) run  
(gdb) print $ymm0.v8_float  
(gdb) print $ymm1.v8_float  
(gdb) continue  
(gdb) print $ymm0.v8_float  

Los números de línea corresponden a la instrucción vaddps ymm0, ymm0, ymm1 y a la siguiente. Si el archivo cambia, se pueden ubicar con:

grep -n "vaddps ymm0, ymm0, ymm1" asm/vector/statsvar_vector.asm  
