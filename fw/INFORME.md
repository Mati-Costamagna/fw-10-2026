# TP4 — Informe (hitos 1 a 4)

---

## Hito 1 — Reconocimiento del arranque actual

```bash
make -C fw clean
make -C fw STANDALONE=1 APP_SRC="print.c test_fw_status.c"
```

### 1. Linea 1 de `fw.hex`, `_start` en `0x0` y el orden de linkeo

```
fw.hex          objdump -d build/standalone.elf
00040117   0:   auipc  sp,0x40        <- _start   \  la sp, _stack_top
00010113   4:   mv     sp,sp                      /  (sp = 0x0004_0000)
1e0000ef   8:   jal    1e8 <main>                    call main
0000006f   c:   j      c <_start+0xc>                1: j 1b
```

- **Linea 1 = `0x00040117` = `auipc sp, 0x40`**, la primera de las dos instrucciones
  en las que el ensamblador expande `la sp, _stack_top`.
- **Por que `_start` queda en `0x0`:** `linker.ld` pone `.text` primero en `FLASH`
  (`ORIGIN = 0x0`), y el patron `*(.text*)` toma las secciones de entrada en el
  orden de los archivos en la linea de comandos. El Makefile pasa `startup.S`
  primero, asi que su `.text`, que empieza en `_start`, cae en `0x0`.
  `ENTRY(_start)` no ubica nada: solo escribe el entrypoint del ELF
  (`readelf -h`), que el core no lee. El `.hex` no tiene entrypoint. picorv32
  arranca en `PROGADDR_RESET = 0x0` y ejecuta lo que haya ahi.
- **Si `print.c` se linkeara antes que `startup.S`:** lo probe linkeando
  `print.c startup.S test_fw_status.c`. En `0x0` queda `uart0_send.part.0`,
  y `_start` se corre a `0x1d0` y `main` a `0x1e0`. El link no da error, porque el
  ELF es valido y hasta conserva `Entry = _start`. Pero el core ejecuta codigo de
  `print.c` con `sp` sin inicializar y `a0`/`a1`/`ra` en su valor de reset: nunca
  pasa por `_start` ni por `main`, y el `ret` vuelve a `ra = 0`, o sea, otra vez a
  `0x0`. `REG_FW_STATUS` nunca llega a `0xFF` y la simulacion no termina
  (corre hasta el timeout sin una sola linea de UART).

### 2. `-Wl,--orphan-handling=warn`

```bash
make clean && make STANDALONE=1 APP_SRC="print.c test_fw_status.c" \
     LDFLAGS="-Wl,--gc-sections -Wl,--orphan-handling=warn"
```

**`int_0`, `int_1` e `int_2` terminan en `.sbss`.** RISC-V tiene *small data*:
GCC pone las globales chicas (≤ 8 bytes, `-msmall-data-limit=8`) en
`.sdata`/`.sbss`/`.srodata` para poder accederlas relativas a `gp`. Como son
globales sin valor inicial, van a `.sbss`. El patron `*(.bss*)` de `linker.ld`
no matchea `.sbss` (no empieza con `.bss`), así que ld la ubica sola:

```
readelf -S:  [ 2] .sbss   NOBITS   00020000 ... 00000c  WA
nm -n:       00020000 B int_2
             00020004 B int_1
             00020008 B int_0
```

### 3. `startup.S` vs. "De 0 a main"

| Paso del arranque | `startup.S` |
|---|---|
| Vector de reset en la dirección de reset | Funciona de casualidad (orden de linkeo, ver 1) |
| Vector de IRQ (`PROGADDR_IRQ = 0x10`) | **Falta**: en `0x10` hay código de `print.c` (`uart0_send.part.0`) |
| Cargar `sp` | Sí (`la sp, _stack_top`) |
| Copiar `.data` desde su LMA (imagen) a su VMA (RAM) | **Falta**. Además `linker.ld` no define `_sidata`/`_sdata`/`_edata` |
| Poner `.bss` en cero | **Falta**. Tampoco hay `_sbss`/`_ebss`, y `.sbss` queda huérfana |
| Llamar a `main` | Sí |
| Si `main` vuelve: reportar o cortar | **Falta**: `1: j 1b` queda en silencio. Si `main` vuelve sin `0xFF`, la simulacion no termina |

**Por que `test_fw_status.c` anda igual:**

- **No tiene `.data`:** `int_0..2` no tienen valor inicial (`size` muestra `data = 0`), asi que no hay nada que copiar.
- **No pone `.bss` en cero, pero da lo mismo:** la RAM del modelo (`memory_d` en `mem_mux.v`) arranca en 0 en Verilator. Además el test no verifica los valores de `int_*`: solo los imprime en un loop.
- **No usa IRQs** (`ENABLE_IRQ = 0`), asi que nadie salta a `0x10`.
- **`main` escribe `REG_FW_STATUS = 0xFF` antes de volver**, y el testbench corta la simulacion sin que importe el `j 1b`.

En cuanto el FW tiene una global inicializada, el arranque original falla. `test_data_bss.c` con `STANDALONE=1` imprime `tp4_data_word = 0x00000000` (esperado `0x1234ABCD`) y `FAIL`.

---

## Hito 2 — vector table e init del BL (`bl_start.S`, `bl.ld`)

```
readelf -h build/bl.elf | grep Entry        Entry point address: 0x0
objdump -d build/bl.elf
00000000 <_bl_vectors>:
   0:  0140006f   j  14 <bl_reset_handler>   PROGADDR_RESET
   4:  0200006f   j  24 <bl_unexpected>
   8:  01c0006f   j  24 <bl_unexpected>
   c:  0180006f   j  24 <bl_unexpected>
  10:  0140006f   j  24 <bl_unexpected>      PROGADDR_IRQ
00000014 <bl_reset_handler>:
  14:  auipc sp,0x40 / addi sp,sp,-20        sp = _bl_stack_top = 0x0004_0000
  1c:  jal   3c <bl_main>
```

- En `0x04`–`0x0C` tambien puse `j bl_unexpected`. No son vectores, pero si el PC cae ahí es un error, así que mejor FAIL + trap que seguir ejecutando lo que venga.
- `bl.ld`: `KEEP(*(.vectors))` primero, y `ASSERT(_bl_vectors == ORIGIN(BL_ROM))`. `.data`/`.bss` tienen símbolos de inicio y fin y un `ASSERT` de tamaño 0.
  Verifique que el link falla con una global inicializada (`.sdata`), una sin inicializar (`.sbss`), un array (`.bss`) y con la vector table fuera de `0x0`.
- `_bl_stack_top = ORIGIN(RAM) + LENGTH(RAM)` es el tope de la RAM, alineado a 16.

---

## Hito 3 — FW relinkeado en `0x1000` (`app.ld`)

Con `APP_SRC="print.c test_data_bss.c"`, que tiene `.data`:

```
readelf -S -l build/app.elf
  [1] .text  PROGBITS 00001000 size 0x6d0
  [2] .data  PROGBITS 00020000 size 0x014
  [3] .bss   NOBITS   00020014 size 0x044
  LOAD  VirtAddr 0x00001000 PhysAddr 0x00001000  .text
  LOAD  VirtAddr 0x00020000 PhysAddr 0x000016d0  .data .bss   <- VMA en RAM, LMA en APP_ROM
nm -n build/app.elf
  000016d0 A _sidata          00020000 D _sdata     00020014 B _sbss
  000016e4 A __fw_end         00020014 D _edata     00020058 B _ebss
  000006e4 A __fw_size  (= tamaño de app.bin = 1764 B)
  00040000   _stack_top
```

---

## Hito 4 — header + `Reset_Handler` (`app_startup.S`)

```
make
  header FW: crc8=0xdb  initial_sp=0x00040000  reset_handler=0x00001018
objdump -s (header en app.elf, antes de mkimage)
  1000 54503446 00100000 60040000 ffffffff   "TP4F" | 0x1000 | 0x460 | CRC sin firmar
  1010 00000400 18100000                     0x40000 | 0x1018
```

`image_crc` queda en `FW_IMAGE_CRC_UNSET` (`0xFFFFFFFF`) en el ELF, porque el
CRC depende de la imagen ya linkeada y lo escribe `mkimage.py` después.

Simulacion (con el arreglo de `trap` de la nota de abajo, y un `bl_main`
descartable que solo salta a `reset_handler`, porque el salto real es del hito 5):

| FW | Resultado |
|---|---|
| `print.c test_fw_status.c` | `REGISTER_FW_STATUS = 000000ff` |
| `print.c test_data_bss.c` | `tp4_data_word = 0x1234ABCD`, `PASS`, `000000ff` |
| `main` que vuelve sin dejar `0xFF` | `ebreak` → `TRAP!` |
| Imagen real del repo al hito 4 (`bl_main` sin completar) | `TRAP!` a los 29 ciclos; `make check` → `RESULTADO: OK` |

---

## Hito 5 - El salto del BL al FW
