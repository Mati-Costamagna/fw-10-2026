#!/bin/bash
# Compila un FW de prueba y lo simula; informa PASS/FAIL contra lo esperado.
#
#   run_test.sh <nombre> <PASS|FAIL|TRAP> [variables de make para fw/Makefile...]
#
# Ejemplos (desde la raiz del repo, normalmente lo invoca el Makefile):
#   fw/tools/run_test.sh test_adc PASS TARGET=test_adc
#   fw/tools/run_test.sh test_data_bss_standalone FAIL TARGET=test_data_bss STANDALONE=1
#
# Variables de entorno: MAX_CYCLES (default 10000000), NOWAVE=1 (sin wave.vcd).
# Deja el log en fw/build/<nombre>.build.log y fw/build/<nombre>.sim.log, y no pisa fw/fw.hex.
# Sale con 0 solo si el resultado de la simulacion coincide con el esperado.

name=$1; expected=$2; shift 2
cd "$(dirname "$0")/../.." || exit 2          # raiz del repo
mkdir -p fw/build
blog=fw/build/$name.build.log
slog=fw/build/$name.sim.log

if ! make -C fw BUILD=build/$name INSTALL=0 "$@" > "$blog" 2>&1; then
    printf '[FAIL] %-26s no compila (ver %s)\n' "$name" "$blog"
    grep -m3 -E 'error|Error|No existe' "$blog" | sed 's/^/         /'
    exit 1
fi

nowave=""; [ -n "$NOWAVE" ] && nowave=+NOWAVE
verbose=""; [ -n "$VERBOSE" ] && verbose=+VERBOSE

# Tests con host UART1: patron fw/tests/<TARGET>.txt (o el de UART1_SCRIPT, relativo a la raiz del repo)
target=$name
for a in "$@"; do case $a in TARGET=*) target=${a#TARGET=};; esac; done
script=${UART1_SCRIPT:-fw/tests/$target.txt}
sim_script=""
if [ -f "$script" ]; then
    sim_script=+UART1_SCRIPT=$script
    MAX_CYCLES=${MAX_CYCLES:-12000000}
fi
MAX_CYCLES=${MAX_CYCLES:-10000000}

./obj_dir/Vtestbench +FW_HEX=fw/build/$name/fw.hex +MAX_CYCLES="$MAX_CYCLES" $nowave $verbose $sim_script > "$slog" 2>&1
got=$(sed -n 's/^RESULT: //p' "$slog" | tail -1)
clocks=$(sed -n 's/^total clocks: *//p;s/.*clock_counts = *//p' "$slog" | tail -1)

if [ "$got" = "$expected" ]; then
    printf '[ OK ] %-26s %-8s clocks=%s\n' "$name" "$got" "${clocks:-?}"
    exit 0
fi
printf '[FAIL] %-26s esperado=%s obtenido=%s (ver %s)\n' "$name" "$expected" "${got:-sin RESULT}" "$slog"
sed 's/\x1b\[[0-9;]*m//g' "$slog" | grep -a -E '^\[FAIL\]|^ERROR|CHECK FAIL' | head -6 | sed 's/^/         /'
exit 1
