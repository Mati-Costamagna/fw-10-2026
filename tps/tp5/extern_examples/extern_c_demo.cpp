#include <iostream>
#include "extern_c_api.h"

int cpp_add(int a, int b) {
    return a + b;
}

double cpp_add(double a, double b) {
    return a + b;
}

extern "C" int c_mul(int a, int b) {
    return a * b;
}

int main() {
    int a = 3;
    int b = 4;

    std::cout << "c_add (C linkage): " << c_add(a, b) << '\n';
    std::cout << "c_mul (extern \"C\" in C++): " << c_mul(a, b) << '\n';
    std::cout << "cpp_add(int, int): " << cpp_add(a, b) << '\n';
    std::cout << "cpp_add(double, double): " << cpp_add(1.5, 2.25) << '\n';

    return 0;
}
