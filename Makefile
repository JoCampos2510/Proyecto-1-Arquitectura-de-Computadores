# =========================================================
# Makefile - Proyecto: Normalizador estadistico vectorizado
# Union de: parte escalar + parte vectorial (companero)
# =========================================================

# --- Herramientas ---
CC        := gcc
NASM      := nasm
CFLAGS    := -std=gnu11 -Wall -Wextra -O2 -g
NASMFLAGS := -f elf64 -g -F dwarf
LDFLAGS   := -lm

# --- Rutas ---
SRC_DIR     := src
INC_DIR     := include
SCRIPTS_DIR := scripts
REF_DIR     := data/reference
ASM_SCALAR  := asm/scalar/stats_scalar.asm
# OJO: el Makefile del companero apunta a "statsvar_vector.asm". Si el archivo
# real se llama stats_vector.asm, cambia esta linea, o compila pasando la ruta:
#   make ASM_VECTOR=asm/vector/stats_vector.asm
ASM_VECTOR  := asm/vector/statsvar_vector.asm
OBJ_DIR     := obj
BIN_DIR     := bin

DRIVER_OBJ := $(OBJ_DIR)/driver.o
SCALAR_OBJ := $(OBJ_DIR)/stats_scalar.o
VECTOR_OBJ := $(OBJ_DIR)/stats_vector.o

# Declara que los targets no son archivos
.PHONY: all clean run-scalar run-vector dirs \
        check-avx2 gen-data verify test-vector test-scalar test-both compare \
        data reference test

# Primer target: se ejecuta con "make" a secas
all: dirs $(BIN_DIR)/norm_scalar $(BIN_DIR)/norm_vector

# Crea los directorios de trabajo
dirs:
	@mkdir -p $(OBJ_DIR) $(BIN_DIR) data

# --- Reglas de enlace ---
$(BIN_DIR)/norm_scalar: $(DRIVER_OBJ) $(SCALAR_OBJ)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

$(BIN_DIR)/norm_vector: $(DRIVER_OBJ) $(VECTOR_OBJ)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

# --- Compilacion del driver ---
$(DRIVER_OBJ): $(SRC_DIR)/driver.c $(INC_DIR)/stats.h | dirs
	$(CC) $(CFLAGS) -I$(INC_DIR) -c $< -o $@

# --- Ensamblado ---
$(SCALAR_OBJ): $(ASM_SCALAR) | dirs
	$(NASM) $(NASMFLAGS) $< -o $@

$(VECTOR_OBJ): $(ASM_VECTOR) | dirs
	$(NASM) $(NASMFLAGS) $< -o $@

# --- Atajos de conveniencia (requieren haber generado data/input.dat) ---
run-scalar: $(BIN_DIR)/norm_scalar
	./$(BIN_DIR)/norm_scalar data/input.dat data/output_scalar.dat 10

run-vector: $(BIN_DIR)/norm_vector
	./$(BIN_DIR)/norm_vector data/input.dat data/output_vector.dat 10

# =========================================================
# Herramientas del companero (parte vectorial): tools/*.py
# =========================================================
check-avx2:
	@grep -q avx2 /proc/cpuinfo && echo "AVX2: soportado" || echo "AVX2: NO soportado"

# Generador del companero (tools/gen_input.py). Es independiente de "make data".
gen-data: dirs
	python3 tools/gen_input.py 1000000 data/input.dat random 42
	python3 tools/gen_input.py 8    data/input_small.dat random 1
	python3 tools/gen_input.py 15   data/input_tail.dat  random 1
	python3 tools/gen_input.py 1000 data/input_const.dat constant
	python3 tools/gen_input.py 0    data/input_empty.dat random

verify: all
	./$(BIN_DIR)/norm_vector data/input.dat data/output_vector.dat 30
	python3 tools/verify.py data/input.dat data/output_vector.dat --label vectorial

# Bateria automatica de casos borde contra la referencia (tabla PASA/FALLA
# para el informe). No depende de scripts/, solo de tools/.
test-vector: all
	python3 tools/run_tests.py --bin $(BIN_DIR)/norm_vector

test-scalar: all
	python3 tools/run_tests.py --bin $(BIN_DIR)/norm_scalar

# Ambas versiones, una tras otra.
test-both: test-scalar test-vector

# Estadisticos de ambos kernels lado a lado contra la referencia,
# mas speedup y diferencia entre los arreglos normalizados.
# Cambia INPUT para usar otro archivo:  make compare INPUT=data/otro.dat
INPUT ?= data/input.dat
compare: all
	python3 tools/compare_kernels.py $(INPUT) --reps 30

# =========================================================
# Pruebas de correctud con NumPy (parte escalar): scripts/*.py
# =========================================================

# Genera los input_*.dat de prueba (ver seccion 2.2 del enunciado)
data: dirs
	python3 $(SCRIPTS_DIR)/generate_test_data.py --outdir data

# Calcula, con NumPy, los estadisticos y el arreglo normalizado esperados
# para cada input_*.dat de correctud (se omiten los input_perf_*, que son
# demasiado grandes para comparar elemento por elemento).
reference: data
	@mkdir -p $(REF_DIR)
	@for f in data/input_*.dat; do \
		case "$$f" in *input_perf_*) continue ;; esac; \
		python3 $(SCRIPTS_DIR)/compute_reference.py $$f --outdir $(REF_DIR); \
	done

# Corre ambos binarios sobre cada input de verificacion y compara
# contra la referencia, reportando PASA/FALLA por caso.
test: all reference
	@mkdir -p data/test_out
	@fail=0; \
	for f in data/input_*.dat; do \
		case "$$f" in *input_perf_*) continue ;; esac; \
		base=$$(basename $$f .dat); \
		./$(BIN_DIR)/norm_scalar $$f data/test_out/$${base}_scalar.dat 1 >/dev/null; \
		./$(BIN_DIR)/norm_vector $$f data/test_out/$${base}_vector.dat 1 >/dev/null; \
		python3 $(SCRIPTS_DIR)/compare_results.py $(REF_DIR)/$${base}_normalized.dat \
			data/test_out/$${base}_scalar.dat --label "escalar  $$base" || fail=1; \
		python3 $(SCRIPTS_DIR)/compare_results.py $(REF_DIR)/$${base}_normalized.dat \
			data/test_out/$${base}_vector.dat --label "vectorial $$base" || fail=1; \
	done; \
	exit $$fail

# --- Limpieza ---
clean:
	rm -rf $(OBJ_DIR) $(BIN_DIR) data/reference data/test_out data/tests data/compare
