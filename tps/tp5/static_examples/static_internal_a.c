#include <stdio.h>

static int file_only_total = 0; // Linkage interno: visible solo en este archivo.

static void add_to_total(int value) { // Funcion privada de este archivo.
    file_only_total += value;
}

void register_value(int value) {
    add_to_total(value);
}

int get_total(void) {
    return file_only_total;
}
