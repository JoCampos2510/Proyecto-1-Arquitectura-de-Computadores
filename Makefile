# =========================================================
# Makefile - Proyecto: Normalizador estadistico vectorizado
# =========================================================


#Variables de herramientas
CC        := gcc
NASM      := nasm
CFLAGS    := -std=gnu11 -Wall -Wextra -O2 -g
NASMFLAGS := -f elf64 -g -F dwarf
LDFLAGS   := -lm

#Rutas
SRC_DIR    := src
INC_DIR    := include
ASM_SCALAR := asm/scalar/stats_scalar.asm
ASM_VECTOR := asm/vector/statsvar_vector.asm
OBJ_DIR    := obj
BIN_DIR    := bin

DRIVER_OBJ := $(OBJ_DIR)/driver.o
SCALAR_OBJ := $(OBJ_DIR)/stats_scalar.o
VECTOR_OBJ := $(OBJ_DIR)/stats_vector.o

#Declara que los targets no son archivos
.PHONY: all clean run-scalar run-vector dirs check-avx2 gen-data verify

#Primer target, corre con el make 
all: dirs $(BIN_DIR)/norm_scalar $(BIN_DIR)/norm_vector

#Crea los directorios
dirs:
	@mkdir -p $(OBJ_DIR) $(BIN_DIR) data

#Reglas de enlace
$(BIN_DIR)/norm_scalar: $(DRIVER_OBJ) $(SCALAR_OBJ)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

$(BIN_DIR)/norm_vector: $(DRIVER_OBJ) $(VECTOR_OBJ)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

#Compilacion del driver 
$(DRIVER_OBJ): $(SRC_DIR)/driver.c $(INC_DIR)/stats.h | dirs
	$(CC) $(CFLAGS) -I$(INC_DIR) -c $< -o $@

#Ensamblado
$(SCALAR_OBJ): $(ASM_SCALAR) | dirs
	$(NASM) $(NASMFLAGS) $< -o $@

$(VECTOR_OBJ): $(ASM_VECTOR) | dirs
	$(NASM) $(NASMFLAGS) $< -o $@

# Atajos de conveniencia (requieren haber generado data/input.dat)
run-scalar: $(BIN_DIR)/norm_scalar
	./$(BIN_DIR)/norm_scalar data/input.dat data/output_scalar.dat 10

run-vector: $(BIN_DIR)/norm_vector
	./$(BIN_DIR)/norm_vector data/input.dat data/output_vector.dat 10

# Atajos de conveniencia para generacion de datos
check-avx2:
	@grep -q avx2 /proc/cpuinfo && echo "AVX2: soportado" || echo "AVX2: NO soportado"

gen-data: dirs
	python3 tools/gen_input.py 1000000 data/input.dat random 42
	python3 tools/gen_input.py 8    data/input_small.dat random 1
	python3 tools/gen_input.py 15   data/input_tail.dat  random 1
	python3 tools/gen_input.py 1000 data/input_const.dat constant
	python3 tools/gen_input.py 0    data/input_empty.dat random

verify: all
	./$(BIN_DIR)/norm_vector data/input.dat data/output_vector.dat 5
	python3 tools/verify_reference.py data/input.dat data/output_vector.dat.stats.txt

clean:
	rm -rf $(OBJ_DIR) $(BIN_DIR)
