#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include "test_const1.h"

extern const int const_var;

int main () {

    //const uint8_t var = 5;
    //var = var + 1;            // This line will cause a compilation error because 'var' is declared as const
    //uint8_t var_1 = var + 1;    // This line is valid because 'var_1' is not declared as const
    //printf("The value of var_1 is: %d\n", var_1);

    int result = suma(3, 4) + const_var;
    printf("The result of suma(3, 4) + const_var is: %d\n", result);

    //int x = 10;
    //int y = 20;

    // 1) dato const, ptr mutable
    //const int *p1 = &x;
    //*p1 = 11;               // ERROR: no se puede modificar el dato via p1
    //p1 = &y;                  // OK: el puntero puede cambiar de direccion

    // 2) ptr const, dato mutable
    //int *const p2 = &x;
    //*p2 = 11;                 // OK: se puede modificar el dato
    //p2 = &y;                // ERROR: no se puede cambiar la direccion del puntero

    // 3) todo const
    //const int *const p3 = &x;
    //*p3 = 12;               // ERROR: no se puede modificar el dato
    //p3 = &y;                // ERROR: no se puede cambiar la direccion

    //printf("x=%d, y=%d\n", x, y);
    //printf("p1 apunta a %d\n", *p1);
    //printf("p2 apunta a %d\n", *p2);
    //printf("p3 apunta a %d\n", *p3);



    return 0;
}

// gcc -Wall test_const.c test1.c -o salida