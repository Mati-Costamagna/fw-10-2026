/*
 * Ejecutar desde: bloque5/ejemplos_clase
 * Compilar: make ejemplo_puntero_funcion
 * Ver resultados: make run3
 */

#include <stdio.h>

typedef void (*accion_t)(void); // Puntero a funcion: void f(void)

typedef enum {
	ACCION_BIENVENIDA = 0,
	ACCION_DESPEDIR = 1,
	ACCION_AGRADECER = 2
} evento_t;

void bienvenida(void) {
	printf("Bienvenidos!\n");
}

void despedir(void) {
	printf("Chau!\n");
}

void agradecer(void) {
	printf("Gracias por venir!\n");
}

int main(void) {
	accion_t accion = NULL; // Buena practica: inicializar el puntero.
	evento_t evento = ACCION_AGRADECER;

	if (evento == ACCION_BIENVENIDA) {
		accion = bienvenida;
	} else if (evento == ACCION_DESPEDIR) {
		accion = despedir;
	} else if (evento == ACCION_AGRADECER) {
		accion = agradecer;
	}

	if (accion != NULL) {
		accion(); // Invocacion indirecta a traves del puntero a funcion.
	}

	return 0;
}
