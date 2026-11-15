#include <stdio.h>
#include <stdbool.h>

#ifndef RB_SIZE
#define RB_SIZE 4
#endif

typedef struct {
	char data[RB_SIZE];
	unsigned int head;
	unsigned int tail;
	unsigned int count; // Cantidad actual de elementos guardados en el buffer.
} buffer_circular_t;

typedef struct {
	char data[RB_SIZE];
	unsigned int count;
} cola_lineal_t;

void buffer_circular_init(buffer_circular_t *buffer) {
	buffer->head = 0;
	buffer->tail = 0;
	buffer->count = 0; // count = 0 es un buffer vacio"
}

bool buffer_circular_push(buffer_circular_t *buffer, char value) {
	if (buffer->count == RB_SIZE) {
		return false; // Si count es igual al size, el buffer esta lleno -> No se puede pushear
	}

	buffer->data[buffer->head] = value;
	buffer->head = (buffer->head + 1u) % RB_SIZE;

	buffer->count++; // Hacemos push -> avisamos que hay un elemento mas en el buffer.
	return true;
}

bool buffer_circular_pop(buffer_circular_t *buffer, char *value) {
	if (buffer->count == 0u) {
		return false; // Si count es igual a 0, el buffer esta vacio -> No se puede hacer pop  
	}

	*value = buffer->data[buffer->tail];
	buffer->tail = (buffer->tail + 1u) % RB_SIZE;
    
	buffer->count--; // Hacemos pop -> avisamos que hay un elemento menos en el buffer.
	return true;
}

void buffer_circular_print(const buffer_circular_t *buffer) {
	printf("head=%u tail=%u count=%u | [", buffer->head, buffer->tail, buffer->count);
	for (unsigned int i = 0; i < buffer->count; i++) {
		unsigned int idx = (buffer->tail + i) % RB_SIZE;
		printf("%c", buffer->data[idx]);
		if (i + 1u < buffer->count) {
			printf(" ");
		}
	}
	printf("]\n");
}

void cola_lineal_init(cola_lineal_t *cola) {
	cola->count = 0;
}

bool cola_lineal_push(cola_lineal_t *cola, char value) {
	if (cola->count == RB_SIZE) {
		return false;
	}

	cola->data[cola->count] = value;
	cola->count++;
	return true;
}

bool cola_lineal_pop(cola_lineal_t *cola, char *value) {
	if (cola->count == 0u) {
		return false;
	}

	*value = cola->data[0];
	for (unsigned int i = 1; i < cola->count; i++) {
		cola->data[i - 1u] = cola->data[i];
	}
	cola->count--;
	return true;
}

void cola_lineal_print(const cola_lineal_t *cola) {
	printf("count=%u | [", cola->count);
	for (unsigned int i = 0; i < cola->count; i++) {
		printf("%c", cola->data[i]);
		if (i + 1u < cola->count) {
			printf(" ");
		}
	}
	printf("]\n");
}

int main(void) {
	buffer_circular_t buffer = {{0}, 0, 0, 0}; // Declaramos e inicializamos una instancia del struct
	cola_lineal_t cola = {{0}, 0};
	
    char value = '?';

	printf("Demo buffer circular (size=%d)\n", RB_SIZE);
	buffer_circular_init(&buffer);
	buffer_circular_print(&buffer);

	printf("\nPush A, B, C:\n");
	buffer_circular_push(&buffer, 'A');
	buffer_circular_push(&buffer, 'B');
	buffer_circular_push(&buffer, 'C');
	
    buffer_circular_print(&buffer);

	printf("\nPop una vez:\n");
	
    if (buffer_circular_pop(&buffer, &value)) {
		printf("pop -> %c\n", value);
	}
    
	buffer_circular_print(&buffer);

	printf("\nPush D, E:\n");
	buffer_circular_push(&buffer, 'D');
	buffer_circular_push(&buffer, 'E');
	buffer_circular_print(&buffer);

	printf("\nIntento push F (debe fallar si esta lleno):\n");
	if (!buffer_circular_push(&buffer, 'F')) {
		printf("push F -> buffer lleno\n");
	}
	buffer_circular_print(&buffer);

	printf("\nVaciando:\n");
	while (buffer_circular_pop(&buffer, &value)) {
		printf("pop -> %c\n", value);
		buffer_circular_print(&buffer);
	}

	printf("\n==============================\n");
	printf("Comparacion con cola lineal\n");
	printf("(misma secuencia: A,B,C - pop - D,E - intento F - vaciar)\n");

	cola_lineal_init(&cola);
	cola_lineal_print(&cola);

	printf("\nPush A, B, C:\n");
	cola_lineal_push(&cola, 'A');
	cola_lineal_push(&cola, 'B');
	cola_lineal_push(&cola, 'C');
	cola_lineal_print(&cola);

	printf("\nPop una vez:\n");
	if (cola_lineal_pop(&cola, &value)) {
		printf("pop -> %c\n", value);
	}
	cola_lineal_print(&cola);

	printf("\nPush D, E:\n");
	cola_lineal_push(&cola, 'D');
	cola_lineal_push(&cola, 'E');
	cola_lineal_print(&cola);

	printf("\nIntento push F (debe fallar si esta llena):\n");
	if (!cola_lineal_push(&cola, 'F')) {
		printf("push F -> cola llena\n");
	}
	cola_lineal_print(&cola);

	printf("\nVaciando:\n");
	while (cola_lineal_pop(&cola, &value)) {
		printf("pop -> %c\n", value);
		cola_lineal_print(&cola);
	}

	return 0;
}
