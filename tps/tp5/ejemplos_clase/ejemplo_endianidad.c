/*
 * Ejecutar desde: bloque5/ejemplos_clase
 * Compilar: make ejemplo_endianidad
 * Ver resultados: make run1
 */

#include <stdio.h>
#include <stdint.h>

int main(void) {
	union { // varios campos compartan la misma zona de memoria. Esto permite interpretar los mismos bytes como un entero o como un arreglo de bytes.
		uint32_t entero;
		uint8_t bytes[4];
	} dato; 

	dato.entero = 0x01020304;

	printf("Entero: 0x%08X\n", dato.entero);
	printf("Bytes en memoria: %02X %02X %02X %02X\n",
	       dato.bytes[0], dato.bytes[1], dato.bytes[2], dato.bytes[3]);

	if (dato.bytes[0] == 0x04) {
		printf("Endianidad: little-endian\n");
	} else {
		printf("Endianidad: big-endian\n");
	}

	return 0;
}
