CC = gcc
CFLAGS = -Wall -Wextra -std=c11
CXX = g++
CXXFLAGS = -Wall -Wextra -std=c++17

.PHONY: all run run1 run2 run3 run4 clean

all: ejemplo_endianidad ejemplo_padding ejemplo_puntero_funcion ejemplo_buffer_colas

ejemplo_endianidad: ejemplo_endianidad.c
	$(CC) $(CFLAGS) $< -o $@

ejemplo_padding: ejemplo_padding.c
	$(CC) $(CFLAGS) $< -o $@

ejemplo_puntero_funcion: ejemplo_puntero_funcion.c
	$(CC) $(CFLAGS) $< -o $@

ejemplo_buffer_colas: ejemplo_buffer_colas.c
	$(CC) $(CFLAGS) $< -o $@

run: all
	@echo "== ejemplo_endianidad =="
	@./ejemplo_endianidad
	@echo "== ejemplo_padding (alineacion y padding) =="
	@./ejemplo_padding
	@echo "== ejemplo_puntero_funcion =="
	@./ejemplo_puntero_funcion
	@echo "== ejemplo_buffer_colas (buffer circular) =="
	@./ejemplo_buffer_colas

run1: ejemplo_endianidad
	@./ejemplo_endianidad

run2: ejemplo_padding
	@./ejemplo_padding

run3: ejemplo_puntero_funcion
	@./ejemplo_puntero_funcion

run4: ejemplo_buffer_colas
	@./ejemplo_buffer_colas

clean:
	rm -f ejemplo_endianidad ejemplo_padding ejemplo_puntero_funcion ejemplo_buffer_colas