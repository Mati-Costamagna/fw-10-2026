#include <stdio.h>

void call_counter(void) {
    static int count = 0; // Se inicializa una sola vez.
    count++;
    printf("call_counter invocado %d veces\n", count);
}

int main(void) {
    call_counter();
    call_counter();
    call_counter();
    return 0;
}
