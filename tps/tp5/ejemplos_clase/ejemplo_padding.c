/*
 * Ejecutar desde: bloque5/ejemplos_clase
 * Compilar: make ejemplo_padding
 * Ver resultados: make run2
 */

#include <stdio.h>
#include <stddef.h>
#include <string.h>

typedef struct {
	int  b; // 4 bytes
	char a; // 1 byte
	char c; // 1 byte
} struct_ejemplo;

int main(void) {
	struct_ejemplo ejemplo;
	unsigned char *raw = (unsigned char *)&ejemplo; // Convertimos la dirección del struct en un puntero a bytes 

	memset(&ejemplo, 0x00, sizeof(ejemplo)); // Escribimos todo el struct con 0x00
	
    ejemplo.a = 'A';
	ejemplo.b = 0x11223344;
	ejemplo.c = 'Z';

	printf("Estructura struct_ejemplo:\n");
	printf("sizeof(struct_ejemplo) = %zu\n", sizeof(struct_ejemplo));
	printf("offsetof(a) = %zu\n", offsetof(struct_ejemplo, a));
	printf("offsetof(b) = %zu\n", offsetof(struct_ejemplo, b));
	printf("offsetof(c) = %zu\n", offsetof(struct_ejemplo, c));
	printf("Bytes en memoria: ");
	for (size_t i = 0; i < sizeof(struct_ejemplo); i++) {
		printf("%02X ", raw[i]);
	}
	printf("\n");

	return 0;
}