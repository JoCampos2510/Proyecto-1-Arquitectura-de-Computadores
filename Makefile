# =========================================================
# Makefile - Proyecto: Normalizador estadistico vectorizado
# =========================================================

# --- Herramientas ---
CC        := gcc
NASM      := nasm
PYTHON    := python3
CFLAGS    := -std=gnu11 -Wall -Wextra -O2 -g
NASMFLAGS := -f elf64 -g -F dwarf
LDFLAGS   := -lm

# --- Rutas ---
SRC_DIR     := src
INC_DIR     := include
SCRIPTS_DIR := tools
DATA_DIR    := data
TEST_DIR    := $(DATA_DIR)/test_out
OBJ_DIR     := obj
BIN_DIR     := bin
ASM_SCALAR  := asm/scalar/stats_scalar.asm
# Si el archivo vectorial se renombra a stats_vector.asm, cambiar aqui.
ASM_VECTOR  := asm/vector/statsvar_vector.asm

DRIVER_OBJ := $(OBJ_DIR)/driver.o
SCALAR_OBJ := $(OBJ_DIR)/stats_scalar.o
VECTOR_OBJ := $(OBJ_DIR)/stats_vector.o
SCALAR_BIN := $(BIN_DIR)/norm_scalar
VECTOR_BIN := $(BIN_DIR)/norm_vector

# Marca para no regenerar los datos (el de 5e7 pesa ~200 MB)
DATA_STAMP := $(DATA_DIR)/.generated

REPS  ?= 30
INPUT ?= $(DATA_DIR)/input_n1000.dat

.PHONY: all dirs clean distclean check-avx2 data \
        run-scalar run-vector test test-scalar test-vector \
        verify-scalar verify-vector \
        compare bench plot

# =========================================================
# Compilacion
# =========================================================
all: $(SCALAR_BIN) $(VECTOR_BIN)

dirs:
	@mkdir -p $(OBJ_DIR) $(BIN_DIR) $(DATA_DIR)

$(SCALAR_BIN): $(DRIVER_OBJ) $(SCALAR_OBJ) | dirs
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

$(VECTOR_BIN): $(DRIVER_OBJ) $(VECTOR_OBJ) | dirs
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

$(DRIVER_OBJ): $(SRC_DIR)/driver.c $(INC_DIR)/stats.h | dirs
	$(CC) $(CFLAGS) -I$(INC_DIR) -c $< -o $@

$(SCALAR_OBJ): $(ASM_SCALAR) | dirs
	$(NASM) $(NASMFLAGS) $< -o $@

$(VECTOR_OBJ): $(ASM_VECTOR) | dirs
	$(NASM) $(NASMFLAGS) $< -o $@

check-avx2:
	@grep -q avx2 /proc/cpuinfo && echo "AVX2: soportado" || echo "AVX2: NO soportado"

# =========================================================
# Datos de prueba (seccion 2.2)
# =========================================================
data: $(DATA_STAMP)

$(DATA_STAMP): $(SCRIPTS_DIR)/generate_test_data.py | dirs
	$(PYTHON) $< --outdir $(DATA_DIR)
	@touch $@

# =========================================================
# Ejecucion manual:  make run-vector INPUT=data/input_n16.dat
# =========================================================
run-scalar: $(SCALAR_BIN)
	./$(SCALAR_BIN) $(INPUT) $(DATA_DIR)/output_scalar.dat 10

run-vector: $(VECTOR_BIN)
	./$(VECTOR_BIN) $(INPUT) $(DATA_DIR)/output_vector.dat 10


define RUN_TESTS
	@mkdir -p $(TEST_DIR); fail=0; \
	for f in $(DATA_DIR)/input_*.dat; do \
		case "$$f" in *input_perf_*) [ "$(2)" = "skip-perf" ] && continue ;; esac; \
		b=$$(basename $$f .dat); \
		for v in $(1); do \
			out=$(TEST_DIR)/$${b}_$$v.dat; log=$(TEST_DIR)/$${b}_$$v.log; \
			if ! ./$(BIN_DIR)/norm_$$v $$f $$out 1 >/dev/null 2>&1; then \
				printf "%-8s %-20s CRASH\n" $$v $$b; fail=1; continue; \
			fi; \
			$(PYTHON) $(SCRIPTS_DIR)/verify.py $$f $$out --label "$$v $$b" > $$log 2>&1 || fail=1; \
			if [ "$(3)" = "detalle" ]; then cat $$log; echo; \
			else printf "%-8s %-20s %s\n" $$v $$b "$$(tail -n 1 $$log)"; fi; \
		done; \
	done; \
	echo "------------------------------------------------------------"; \
	if [ $$fail -eq 0 ]; then echo "RESULTADO GENERAL: PASA"; \
	else echo "RESULTADO GENERAL: FALLA (ver $(TEST_DIR)/*.log)"; fi; \
	exit $$fail
endef

# Rapidos: solo los tamanos pequenos y casos borde
test: all data
	$(call RUN_TESTS,scalar vector,skip-perf)

test-scalar: $(SCALAR_BIN) data
	$(call RUN_TESTS,scalar,skip-perf)

test-vector: $(VECTOR_BIN) data
	$(call RUN_TESTS,vector,skip-perf)

# Completos: TODOS los N, incluidos los de rendimiento (hasta 5e7)
verify-scalar: $(SCALAR_BIN) data
	$(call RUN_TESTS,scalar,all,detalle)

verify-vector: $(VECTOR_BIN) data
	$(call RUN_TESTS,vector,all,detalle)

# Escalar vs vectorial entre si:  make compare INPUT=data/input_n16.dat
compare: all
	$(PYTHON) $(SCRIPTS_DIR)/compare_kernels.py $(INPUT) \
		--scalar $(SCALAR_BIN) --vector $(VECTOR_BIN) \
		--outdir $(DATA_DIR)/compare --reps $(REPS)

# =========================================================
# Rendimiento (seccion 2.4.b)
# =========================================================
bench: all data
	$(PYTHON) $(SCRIPTS_DIR)/run_benchmark.py $(SCALAR_BIN) --label escalar   --datadir $(DATA_DIR) --reps $(REPS)
	$(PYTHON) $(SCRIPTS_DIR)/run_benchmark.py $(VECTOR_BIN) --label vectorial --datadir $(DATA_DIR) --reps $(REPS)

plot: $(DATA_DIR)/bench_escalar.csv $(DATA_DIR)/bench_vectorial.csv
	$(PYTHON) $(SCRIPTS_DIR)/plot_speedup.py $^ --out $(DATA_DIR)/speedup.png

$(DATA_DIR)/bench_escalar.csv $(DATA_DIR)/bench_vectorial.csv:
	@echo "Faltan los CSV de benchmark: corre 'make bench' primero."; exit 1

# =========================================================
# Limpieza
# =========================================================
clean:
	rm -rf $(OBJ_DIR) $(BIN_DIR) $(TEST_DIR) $(DATA_DIR)/compare

# Ademas borra los datos generados y los resultados de benchmark
distclean: clean
	rm -rf $(DATA_DIR)
