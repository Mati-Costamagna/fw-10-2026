#include <stdio.h>

void register_value(int value);
int get_total(void);

int main(void) {
    register_value(10);
    register_value(5);

    printf("total compartido por archivo A: %d\n", get_total());

    // extern int file_only_total; // ERROR de link: file_only_total es static en otro archivo.
    // extern void add_to_total(int); // ERROR de link: add_to_total es static en otro archivo.

    return 0;
}
