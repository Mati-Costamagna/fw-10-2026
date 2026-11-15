#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "[1/4] static local variable"
gcc -Wall static_local_demo.c -o static_local_demo
./static_local_demo

echo
echo "[2/4] static global + static function (internal linkage)"
gcc -Wall static_internal_a.c static_internal_b.c -o static_internal_demo
./static_internal_demo

echo
echo "[3/4] symbols from static_internal_a.o"
gcc -Wall -c static_internal_a.c -o static_internal_a.o
nm static_internal_a.o | grep -E 'file_only_total|add_to_total|register_value|get_total' || true

echo
echo "[4/4] static class member (C++)"
g++ -Wall static_class_member_demo.cpp -o static_class_member_demo
./static_class_member_demo
