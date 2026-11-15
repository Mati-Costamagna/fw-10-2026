#!/usr/bin/env bash
set -euo pipefail

# Demo rapido: compila y muestra simbolos mangled vs demangled.
cd "$(dirname "$0")"

echo "[1/5] Compilando objetos..."
gcc -Wall -c extern_c_api.c -o extern_c_api.o
g++ -Wall -c extern_c_demo.cpp -o extern_c_demo.o

echo
echo "[2/5] Simbolos C (sin mangling):"
nm extern_c_api.o | grep -E 'c_add|c_mul|cpp_add' || true

echo
echo "[3/5] Simbolos C++ crudos (mangled):"
nm extern_c_demo.o | grep -E 'c_add|c_mul|cpp_add' || true

echo
echo "[4/5] Simbolos C++ demangled (legible):"
nm -C extern_c_demo.o | grep -E 'c_add|c_mul|cpp_add' || true

echo
echo "[5/5] Link + ejecucion:"
g++ extern_c_demo.o extern_c_api.o -o extern_c_demo
./extern_c_demo

echo
echo "Listo: arriba viste nombres mangled (_Z...) y no mangled (c_add, c_mul)."
