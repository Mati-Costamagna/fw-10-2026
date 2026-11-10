# TP4 — Informe (hitos 1 a 9)

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
no matchea `.sbss` (no empieza con `.bss`), asi que ld la ubica sola:

```
readelf -S:  [ 2] .sbss   NOBITS   00020000 ... 00000c  WA
nm -n:       00020000 B int_2
             00020004 B int_1
             00020008 B int_0
```

### 3. `startup.S` vs. "De 0 a main"

| Paso del arranque | `startup.S` |
|---|---|
| Vector de reset en la direccion de reset | Funciona de casualidad (orden de linkeo, ver 1) |
| Vector de IRQ (`PROGADDR_IRQ = 0x10`) | **Falta**: en `0x10` hay codigo de `print.c` (`uart0_send.part.0`) |
| Cargar `sp` | Si (`la sp, _stack_top`) |
| Copiar `.data` desde su LMA (imagen) a su VMA (RAM) | **Falta**. Ademas `linker.ld` no define `_sidata`/`_sdata`/`_edata` |
| Poner `.bss` en cero | **Falta**. Tampoco hay `_sbss`/`_ebss`, y `.sbss` queda huerfana |
| Llamar a `main` | Si |
| Si `main` vuelve: reportar o cortar | **Falta**: `1: j 1b` queda en silencio. Si `main` vuelve sin `0xFF`, la simulacion no termina |

**Por que `test_fw_status.c` anda igual:**

- **No tiene `.data`:** `int_0..2` no tienen valor inicial (`size` muestra `data = 0`), asi que no hay nada que copiar.
- **No pone `.bss` en cero, pero da lo mismo:** la RAM del modelo (`memory_d` en `mem_mux.v`) arranca en 0 en Verilator. Ademas el test no verifica los valores de `int_*`: solo los imprime en un loop.
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

- En `0x04`–`0x0C` tambien puse `j bl_unexpected`. No son vectores, pero si el PC cae ahi es un error, asi que mejor FAIL + trap que seguir ejecutando lo que venga.
- `bl.ld`: `KEEP(*(.vectors))` primero, y `ASSERT(_bl_vectors == ORIGIN(BL_ROM))`. `.data`/`.bss` tienen simbolos de inicio y fin y un `ASSERT` de tamanio 0.
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
CRC depende de la imagen ya linkeada y lo escribe `mkimage.py` despues.

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

### `bl_jump(sp, entry)` (`bl_start.S`)

Segun la ABI ILP32 los argumentos llegan en registros: `sp` en `a0` y `entry`
en `a1`. Desensamblado de `build/bl.elf`:

```
00000024 <bl_jump>:
  24:  mv   t0,a1      # guardar entry antes de pisar nada
  28:  mv   sp,a0      # sp que pide el FW (initial_sp del header)
  2c:  li   ra,0       # ra = 0
  30:  jr   t0         # salto SIN link a Reset_Handler
```

- **¿`jalr ra` o `jr`?** `jr` (sin link). El FW no vuelve al BL: no hay nada a
  donde retornar, y un `jalr` dejaria en `ra` una direccion del BL que ya no
  tiene sentido (el BL no guarda estado).
- **¿Que queda en `ra`?** `0`. Si `main` del FW retornara sin pasar por el
  `ebreak` del `Reset_Handler`, caeria en `0x0` (reset del BL) en vez de
  ejecutar basura.
- El `sp` se carga recien al final del BL porque el `Reset_Handler` del FW
  asume que ya tiene un stack valido y el BL ya no lo necesita.

### `bl_main()` (`bl_main.c`)

1. `REG_FW_STATUS = 0`, `REG_FW_REPORT = BL_REPORT_START` y mensaje `[BL] arrancó`.
2. Lee `initial_sp` y `reset_handler` del header (`__fw_slot_start`, `0x1000`).
3. Imprime el `reset_handler`, marca `BL_REPORT_JUMP` y llama a `bl_jump()`.

### Resultado de `make sim`

```
UART: [BL] arrancó
UART: [BL] saltando al FW, reset_handler=0x00001018
UART: -- running test_fw_status --
UART: 0
...
UART: -- test done! --
ending simulation, u_top.u_register_file.REGISTER_FW_STATUS = 000000ff
```

El `reset_handler=0x00001018` coincide con el que muestra `mkimage.py` (hito 4):
el BL salta efectivamente al `Reset_Handler` del FW, que corre igual que en el
flujo standalone.

---

## Hito 6 — Verificar `.data` y `.bss`

```bash
make sim APP_SRC="print.c test_data_bss.c"                # PASS
make sim APP_SRC="print.c test_data_bss.c" STANDALONE=1   # FAIL (arranque original)
```

| Flujo | `&tp4_data_word` | `tp4_data_word` | Resultado |
|---|---|---|---|
| BL + FW (`app_startup.S`) | `0x00020010` | `0x1234ABCD` | `test_data_bss: PASS`, `REGISTER_FW_STATUS = 000000ff` |
| `STANDALONE=1` (`startup.S`) | `0x00020010` | `0x00000000` | `FAIL: tp4_data_word (.sdata) no tiene su valor inicial` |

**Por que falla con el arranque original:** `startup.S` solo carga `sp` y llama
a `main`. No copia `.data` desde su LMA (en la imagen) a su VMA (RAM,
`0x0002_0000`), y `linker.ld` ni siquiera define `_sidata`/`_sdata`/`_edata`.
La imagen (`fw.hex`) solo trae el valor `0x1234ABCD` en la zona de la ROM; la
RAM no se carga desde el hex y arranca en 0, asi que `tp4_data_word` (que cae en
`.sdata`) lee `0`. Tampoco hay `_sbss`/`_ebss`: `.sbss` queda huerfana y `.bss` no se
pone en cero (en simulacion da lo mismo porque la RAM arranca en 0, pero en
hardware real tendria basura). Con `app_startup.S` el `Reset_Handler` copia
`.data` desde `_sidata` y pone `.bss` en cero antes de `main`, y el test pasa.

En el caso standalone, el test termina en FAIL dejando `REG_FW_STATUS = 0xBAD` (no 
`0xFF`), por lo que la simulacion corre hasta el timeout.

---

## Hito 7 — Validar la imagen antes de saltar (`bl_main.c`)

`bl_main()` valida, en orden y antes de `bl_jump()`: `magic`, `load_addr == slot`,
`FW_HDR_SIZE <= image_size <= tamaño del slot`, CRC-8 de `[slot+0x10, slot+image_size)`
(`str_crc8`), `initial_sp` dentro de la RAM (`ADDR_START_DATA`..`+ADDR_SIZE_DATA`) y alineado
a 16, y `reset_handler` dentro de la imagen y alineado a 4. Si todo esta bien deja
`REG_FW_REPORT = BL_REPORT_IMG_OK` e imprime `[BL] imagen del FW valida`.

`bl_fail(code, why)`: imprime `why`, `REG_FW_REPORT = BL_REPORT_ERROR | code`,
`REG_FW_STATUS = 0xBAD` y `bl_halt()`. No alcanza con `0xBAD`: el testbench solo corta con
`0xFF` o con trap, asi que hace falta el `ebreak` de `bl_halt()`.

| Corrida | Resultado |
|---|---|
| `make sim` | `[BL] imagen del FW valida` → FW → `REGISTER_FW_STATUS = 000000ff` |
| `make sim CORRUPT=1` | `[BL] ERROR: CRC invalido, imagen corrupta` → `------ TRAP! ------- clock_counts = 28874` |

Testbench del repo: `rtl/testbench.sv` declaraba `wire trap;` sin conectarlo a nada (`top` no
tiene puerto `trap`). En Verilator ese `wire` sin driver vale 0, asi que el trap nunca llegaba al
testbench y `CORRUPT=1` corria sin terminar. Es un error que viene arrastrado desde el TP1.
**Arreglo:** borre el `wire trap;` y el testbench ahora lee la senial del core por jerarquia
(`u_top.trap`, la net que `top.v` conecta al puerto `trap` de picorv32), igual que ya leia
`u_top.u_register_file.REGISTER_FW_STATUS`. Con eso `make sim CORRUPT=1` termina en
`TRAP!` (`clock_counts = 28874`) y `make sim` sigue terminando en `000000ff`.

---

## Hito 8 — Revisar la memoria y matchear con el HEX (diapo 12)

Todo con el FW que tiene `.data` y `.bss` (para el paso 4):

```bash
make sim APP_SRC="print.c test_data_bss.c"
make check
make inspect APP_SRC="print.c test_data_bss.c"
```

`make inspect` depende de `build/fw.mode`, asi que rearma la imagen si cambia `APP_SRC`. 
Un `make inspect` sin `APP_SRC` vuelve a `test_fw_status.c` y ya no muestra lo que se 
simulo: hay que pasarle el mismo `APP_SRC`. `make check` no rearma nada.

### 1. El `.hex` y los `.map`

`fw.hex` tiene una palabra de 32 bits por linea, a partir de la direccion 0:
**linea N = direccion `4·(N−1)`** (y direccion A = linea `A/4 + 1`). La imagen tiene 1468
lineas (`0x0000`–`0x16EF`):

| Lineas de `fw.hex` | Direcciones | Contenido |
|---|---|---|
| 1–5 | `0x0000`–`0x0010` | vector table del BL (5 `j`) |
| 6–354 | `0x0014`–`0x0587` | resto del BL (`bl.bin` = 1416 B) |
| 355–1024 | `0x0588`–`0x0FFF` | relleno de `mkimage.py` con `0x00000000` (instruccion ilegal → trap) |
| **1025**–1030 | `0x1000`–`0x1017` | header + vector table del FW |
| 1031–1463 | `0x1018`–`0x16DB` | `Reset_Handler`, codigo y `.rodata` del FW |
| 1464–1468 | `0x16DC`–`0x16EF` | valores iniciales de `.data` (LMA, `_sidata`) |

```
línea  dirección   fw.hex
    1  0x00000000  0140006f   j bl_reset_handler   <- PROGADDR_RESET
    5  0x00000010  0240006f   j bl_unexpected      <- PROGADDR_IRQ
    6  0x00000014  00040117   auipc sp,0x40        <- bl_reset_handler
 1024  0x00000ffc  00000000   relleno
 1025  0x00001000  46345054   magic "TP4F"         <- __fw_slot_start / __fw_header
 1030  0x00001014  00001018   reset_handler
 1031  0x00001018  0003f117   auipc sp,0x3f        <- Reset_Handler
```

Los `.map` muestran lo mismo desde el lado del linker:

```
build/bl.map
  BL_ROM 0x00000000 0x00001000 / APP_ROM 0x00001000 0x0001f000 / RAM 0x00020000 0x00020000
  .text           0x00000000      0x588
   .vectors       0x00000000       0x14       _bl_vectors          <- primera, en 0x0
  .data           0x00020000        0x0                            <- vacías: el BL no tiene globales
  .bss            0x00020000        0x0
  0x00040000  _bl_stack_top     0x00001000  __fw_slot_start     0x0001f000  __fw_slot_size

build/app.map
  .text           0x00001000      0x6dc
   .fw_header     0x00001000       0x18       __fw_header          <- primera, en 0x1000
  .data           0x00020000       0x14 load address 0x000016dc    <- VMA en RAM, LMA en APP_ROM
   .data          0x00020000       0x10       (tp4_data_array)
   .sdata         0x00020010        0x4       (tp4_data_word)
  0x000016dc  _sidata = LOADADDR (.data)
  .bss            0x00020014       0x44
   .sbss          0x00020014        0x4       (tp4_bss_word)
   .bss           0x00020018       0x40       (tp4_bss_array)
  0x000016f0  __fw_end    0x000006f0  __fw_size    0x00040000  _stack_top
```

`bl.map` dice que el BL termina en `0x587` (linea 354) y `app.map` que la imagen del FW
termina en `__fw_end = 0x16F0` (la linea 1468 es la ultima palabra, `0x16EC`). Los dos
coinciden con lo que imprime `mkimage.py` y con el largo de `fw.hex`.

### 2. readelf / objdump

Vector table del BL (`objdump -d build/bl.elf`): son **instrucciones**, y las mismas
palabras que las lineas 1–5 de `fw.hex`.

```
00000000 <_bl_vectors>:
   0:  0140006f   j  14 <bl_reset_handler>
   4:  0300006f   j  34 <bl_unexpected>
   8:  02c0006f   j  34 <bl_unexpected>
   c:  0280006f   j  34 <bl_unexpected>
  10:  0240006f   j  34 <bl_unexpected>
00000014 <bl_reset_handler>:
  14:  00040117   auipc sp,0x40
  18:  fec10113   addi  sp,sp,-20 # 40000 <_bl_stack_top>
  1c:  06c000ef   jal   88 <bl_main>
```

Header del FW (`objdump -s -j .text --start-address=0x1000 --stop-address=0x1018 build/app.elf`):
son **datos** (little-endian), y las mismas palabras que las lineas 1025–1030:

```
 1000 54503446 00100000 f0060000 ffffffff  TP4F............
 1010 00000400 18100000                    ........
```

| Direccion | Campo | `app.elf` | `fw.hex` (linea) |
|---|---|---|---|
| `0x1000` | `magic` | `0x46345054` | `46345054` (1025) |
| `0x1004` | `load_addr` | `0x00001000` | `00001000` (1026) |
| `0x1008` | `image_size` | `0x000006F0` | `000006f0` (1027) |
| `0x100C` | `image_crc` | `0xFFFFFFFF` (`FW_IMAGE_CRC_UNSET`) | **`0000003f`** (1028) |
| `0x1010` | `initial_sp` | `0x00040000` | `00040000` (1029) |
| `0x1014` | `reset_handler` | `0x00001018` | `00001018` (1030) |

La unica palabra que difiere es el CRC, porque lo escribe `mkimage.py` despues de linkear
(ver hito 4).

### 3. Vector table del FW → `Reset_Handler`

Los tres valores coinciden:

```
fw.hex línea 1030 (0x1014)          00001018
nm -n build/app.elf                 00001018 T Reset_Handler
readelf -h build/app.elf            Entry point address: 0x1018
```

`readelf -h build/bl.elf` da `Entry point address: 0x0` (`_bl_vectors`). El core no lee
ninguno de los dos *Entry point*: arranca en `PROGADDR_RESET = 0x0`, y el BL usa el campo
`reset_handler` del header, que es la misma direccion. Por eso el BL imprime
`reset_handler=0x00001018`. En `0x1018` esta la primera instruccion del `Reset_Handler`
(`auipc sp,0x3f`, linea 1031), justo despues del header, como fuerza `app.ld` con
`*(.text.Reset_Handler)`.

### 4. `.data` y `.bss` donde dice el linker script

```
readelf -S -l build/app.elf
  [1] .text  PROGBITS 00001000 size 0x6dc  AX
  [2] .data  PROGBITS 00020000 size 0x014  WA
  [3] .bss   NOBITS   00020014 size 0x044  WA
  Type  Offset   VirtAddr   PhysAddr   FileSiz MemSiz  Flg
  LOAD  0x001000 0x00001000 0x00001000 0x006dc 0x006dc R E   .text
  LOAD  0x002000 0x00020000 0x000016dc 0x00014 0x00058 RW    .data .bss

nm -n build/app.elf
  000016dc A _sidata          00020000 D _sdata, tp4_data_array
  000016f0 A __fw_end         00020010 D tp4_data_word
  000006f0 A __fw_size        00020014 D _edata
                              00020014 B _sbss, tp4_bss_word
                              00020018 B tp4_bss_array
                              00020058 B _ebss
                              00040000 B _stack_top
```

- **`.data`:** VMA `0x20000` (RAM) y LMA `0x16DC` (`PhysAddr` = `_sidata`, dentro de
  `APP_ROM`, justo despues de `.text`). `FileSiz = 0x14` son los 20 bytes de valores iniciales
  que viajan en la imagen. Estan en las lineas 1464–1468 de `fw.hex`:
  `00000001 00000002 00000003 00000004` (`tp4_data_array`) y `1234abcd` (`tp4_data_word`,
  en `.sdata`). Es lo mismo que `objdump -s -j .data` muestra en `0x20000`.
- **`.bss`:** `NOBITS`. No ocupa lugar en el archivo ni en `fw.hex` (`MemSiz − FileSiz =
  0x58 − 0x14 = 0x44`), y la imagen termina en `__fw_end = 0x16F0`, antes de su "load address".
  `.sbss` quedo dentro de `_sbss`..`_ebss`.
- **El `Reset_Handler`** usa esos mismos simbolos (`objdump -d`): copia de `0x16DC`
  (`_sidata`) a `0x20000`..`0x20014` y pone en cero `0x20014`..`0x20058`.
- **Lo que imprime `test_data_bss.c`** coincide con `nm` y con la imagen:

  ```
  UART: [FW]   &tp4_data_word  = 0x00020010     <- nm: 00020010 D tp4_data_word
  UART: [FW]    tp4_data_word  = 0x1234ABCD     <- fw.hex línea 1468 (LMA 0x16EC), copiado a RAM
  UART: [FW]   &tp4_bss_array  = 0x00020018     <- nm: 00020018 B tp4_bss_array
  UART: [FW] test_data_bss: PASS
  ending simulation, u_top.u_register_file.REGISTER_FW_STATUS = 000000ff
  ```

### 5. `fw.hex` vs. lo que cargo el simulador

`init_memory()` imprime `loading: <i> -> <dato>`, donde `<i>` es el **indice de palabra**
de `memory_i` (el comentario `// byte address` del testbench esta mal: `addr += 1` por linea).
Direccion = `4·i`, linea = `i + 1`:

```
loading: 00000000 -> 0140006f    i=0      -> 0x0000, línea 1
loading: 00000400 -> 46345054    i=0x400  -> 0x1000, línea 1025 (magic)
loading: 00000405 -> 00001018    i=0x405  -> 0x1014, línea 1030 (reset_handler)
loading: 000005bb -> 1234abcd    i=0x5bb  -> 0x16EC, línea 1468 (última)
```

```
make check
[hex] build/fw.hex: 1468 palabras (0x00000000-0x000016ef)
[log] build/sim.log: init_memory() cargó 1468 palabras en memory_i
[log] OK: lo que cargó el simulador coincide palabra por palabra con fw.hex
Vector table del BL:  0x00000000  0140006f  j 0x00000014 <bl_reset_handler>  PROGADDR_RESET
                      0x00000010  0240006f  j 0x00000034 <bl_unexpected>     PROGADDR_IRQ
Header + vector table del FW en 0x00001000 (línea 1025 de fw.hex):
  +0x00 magic         0x46345054 OK
  +0x04 load_addr     0x00001000 OK
  +0x08 image_size    0x000006f0 (1776 B, hasta 0x000016ef) OK
  +0x0C image_crc     0x0000003f (recalculado: 0x0000003f) OK
  +0x10 initial_sp    0x00040000 <_stack_top> OK
  +0x14 reset_handler 0x00001018 <Reset_Handler> OK
  Reset_Handler según nm: 0x00001018 OK
RESULTADO: OK
```

Con el FW por defecto (`make sim && make check`, `test_fw_status.c`) tambien da
**`RESULTADO: OK`**: 1302 palabras, `image_size = 0x458`, `image_crc = 0xF1`.

**Prueba negativa:** para ver que el chequeo compara de verdad, corri `check_load.py` con
una copia de `fw.hex` con un bit cambiado en la ultima palabra y el mismo `sim.log`. Da
`DIFERENCIA 0x000016ec (línea 1468): fw.hex=1234abcc cargado=1234abcd` y sale con
error. Lo mismo pasa si se rearma la imagen y se corre `make check` sin volver a simular,
porque el `sim.log` queda viejo. Con el `fw.hex` de `test_data_bss.c` contra el `sim.log` de
`test_fw_status.c` da, entre otras, `DIFERENCIA 0x00001008 (línea 1027): fw.hex=000006f0
cargado=00000458` (el `image_size` de cada FW).

---

## Hito 9 — Informe

Las comparaciones de este hito las arme en un `BUILD` aparte (`make BUILD=<dir> <dir>/fw.hex ...`,
sin `install`), para no pisar `build/` ni `fw/fw.hex`. Salvo que diga otra cosa, el FW es
`print.c test_fw_status.c`.

### 1. Vector table del BL: instrucciones vs. direcciones (Cortex-M)

En Cortex-M la vector table son datos que lee el hardware. Al salir de reset el core carga
`MSP ← [VTOR + 0x0]` y `PC ← [VTOR + 0x4]` (el `Reset_Handler`, con el bit Thumb en 1). Ante la
excepcion `n` lee la direccion en `[VTOR + 4·n]` y salta. La indireccion la hace el core.

picorv32 no lee ninguna tabla. Pone el PC en una direccion fija y ejecuta lo que haya ahi:

```
picorv32.v  if (!resetn) reg_pc <= PROGADDR_RESET;                   // 0x0000_0000
picorv32.v  ENABLE_IRQ && irq_state[0]: current_pc = PROGADDR_IRQ;   // 0x0000_0010
picorv32.v  if (~STACKADDR) ... reg_out <= STACKADDR;                // con 0xFFFF_FFFF no carga sp
```

Por eso cada "vector" del BL tiene que ser una instruccion (`j`, de 4 bytes), y entre
`PROGADDR_RESET` y `PROGADDR_IRQ` entran justo 4. Como el core tampoco carga `sp` (no hay
equivalente a la palabra 0 de Cortex-M), lo carga `bl_reset_handler` por software.

El header del FW si copia el formato de Cortex-M: `initial_sp` en `+0x10` y `reset_handler` en
`+0x14`, como `MSP` y `Reset_Handler` en `+0x0` y `+0x4`. Pero esa tabla no la lee el hardware
sino el BL: `bl_jump()` hace por software lo que el core de Cortex-M hace en el reset (cargar `sp`
y saltar a una direccion). En un RISC-V estandar pasa lo mismo que en picorv32: en modo vectorizado
de `mtvec` el core salta a `BASE + 4·causa` y ejecuta, asi que la tabla tambien son saltos.

### 2. Los pasos del `Makefile`

| Paso | Regla | Que hace |
|---|---|---|
| 0 | `build/fw.mode` | Guarda `APP_SRC`, `APP_MARCH`, `CORRUPT` y `STANDALONE`. Si cambian, rearma `app.elf` y `fw.bin` aunque ningun fuente haya cambiado |
| 1 | `bl.elf` | Compila y linkea en un paso `bl_start.S`, `bl_main.c`, `print.c` y `strutils.c` con `bl.ld`. Siempre `-march=rv32i`, con `-ffunction-sections -fdata-sections` + `--gc-sections` y `-Map=bl.map`. Despues corre `size` |
| 2 | `app.elf` | Lo mismo con `app_startup.S` + `APP_SRC`, `app.ld` y `-march=$(APP_MARCH)` |
| 3 | `%.bin` | `objcopy -O binary`: el contenido cargable de cada ELF, sin direcciones (el byte 0 es la LMA mas baja) |
| 4 | `%.sym` | `nm -n`: los simbolos ordenados, que usa `check_load.py` |
| 5 | `fw.bin` | `mkimage.py`: valida el header del FW, lo firma (CRC en `+0x0C`) y arma BL + relleno + FW. Con `STANDALONE=1` es un `cp standalone.bin` |
| 6 | `fw.hex` | `hexdump -v -e '1/4 "%08x\n"'`: una palabra little-endian por linea, el formato de `init_memory()` |
| 7 | `install` | Copia `build/fw.hex` a `fw/fw.hex`, que es lo que carga el testbench |

Ademas: `sim` (todo lo anterior + `make sim` de la raiz, con el log en `build/sim.log`), `check`
(`check_load.py`: `fw.hex` contra lo que cargo el simulador), `inspect`, `disasm` y `clean`.

**¿Por qué `bl.elf` y `app.elf` se linkean por separado?** Porque son dos programas independientes
que no comparten ningun simbolo. El unico contrato entre los dos es el header en `0x1000`
(`fw_image.h` + `memory_map.ld`): el BL encuentra el `sp` y el `reset_handler` del FW leyendo el
header en tiempo de ejecucion, no porque el linker los resuelva.

- Cada uno tiene su linker script, su region (`BL_ROM` / `APP_ROM`), su entry point (`_bl_vectors` /
  `Reset_Handler`), su arranque y sus reglas: el BL no puede tener `.data`/`.bss` (`ASSERT`), el FW si.
- Usan distinto `-march`: el BL siempre `rv32i`, para que arranque con cualquier `top.v`, y el FW el
  que soporte el core (`rv32ic`, por ejemplo).
- Los dos usan `print.c`. En un solo link, `print_str` y las demas estarian definidas dos veces.
- El FW se puede cambiar sin tocar el BL, como en una actualizacion en campo. `bl.bin` sale
  identico (`cmp`) armando la imagen con `test_fw_status.c` o con `test_data_bss.c`. Y el BL valida
  lo que encuentra en el slot en vez de confiar en que se linkeo junto con el.
- `mkimage.py` necesita el FW solo (`app.bin`) para comparar `image_size` y calcular el CRC.

**¿Qué dirección usa `objcopy -O binary` para `.data`?** La **LMA** (`PhysAddr`), no la VMA. Los
valores iniciales quedan al final de `app.bin`, en `_sidata`. Con `test_data_bss.c`:

```
readelf -l app.elf
  LOAD  0x002000  VirtAddr 0x00020000  PhysAddr 0x000016dc  FileSiz 0x00014  MemSiz 0x00058  RW
xxd -s 0x6dc app.bin                                   (0x6dc = 0x16dc - 0x1000)
  000006dc: 0100 0000 0200 0000 0300 0000 0400 0000    tp4_data_array = {1, 2, 3, 4}
  000006ec: cdab 3412                                  tp4_data_word  = 0x1234ABCD
```

`objcopy -O binary` vuelca las secciones cargables ordenadas por LMA, empezando por la mas baja
(`0x1000` = byte 0 de `app.bin`) y rellenando los huecos con ceros. `.bss` es `NOBITS` y no aparece.
Si `.data` no tuviera `AT> APP_ROM` (LMA = VMA = `0x20000`), el binario iria de `0x1000` a
`0x20014`. Lo probe con `objcopy --change-section-lma .data=0x20000`: `app.bin` pasa de 1776 B a
**126 996 B** (`0x1F014`), casi todo ceros. Eso no entra en `APP_ROM` (`0x1F000`), y ademas los
valores iniciales quedarian en una direccion de RAM que el testbench no carga.

**¿Qué agrega `mkimage.py` entre el BL y el FW?** Ceros, desde el final del BL hasta `load_addr`:
`0x588`–`0xFFF` (2680 B, lineas 355–1024 de `fw.hex`). Los `.bin` no llevan direcciones, asi que
concatenados sin relleno el FW quedaria en `0x588`, y no en `0x1000`, donde fue linkeado y donde lo
busca el BL. Rellena con `0x00` porque `0x00000000` es una instruccion ilegal en RISC-V: si el PC
cae ahi, picorv32 hace trap (`CATCH_ILLINSN = 1`). Fuera del relleno, `mkimage.py` escribe el CRC
en el header (pregunta 3), con `CORRUPT=1` invierte un bit despues de firmar, y completa la imagen
a un multiplo de 4 bytes para `hexdump`.

### 3. La palabra en `0x100C`

Es `image_crc`. En `app.elf` vale `FW_IMAGE_CRC_UNSET` (`0xFFFFFFFF`, el `.word` de
`app_startup.S`), y en `fw.hex` esta el CRC que calculo `mkimage.py`:

```
objdump -s app.elf        1000 54503446 00100000 58040000 ffffffff   <- 0x100C = 0xFFFFFFFF
fw.hex líneas 1025-1030   46345054 00001000 00000458 000000f1 00040000 00001018
                                                     ^ línea 1028 = 0x100C = 0xF1
```

El CRC no se puede poner al linkear porque depende de los bytes de la imagen terminada (de
`0x1010` hasta `__fw_end`), que incluyen las direcciones que resuelve el linker. Esa imagen recien
existe cuando termina el link, asi que se firma despues, sobre `app.bin`. El CRC cubre desde `0x10`
y no desde `0x0` para no incluirse a si mismo: escribir `+0x0C` no cambia los datos que cubre. Los
primeros 16 bytes (`magic`, `load_addr`, `image_size`) el BL los valida por separado.

Consecuencia: `app.elf` no es exactamente lo que corre. En una placa, si se cargara `app.elf`
directo (por ejemplo con `load` de GDB), el BL lo rechazaria con `BL_ERR_CRC`. Por eso `make check`
compara contra `fw.hex` y no contra el ELF.

### 4. El FW de `fw.hex` (linea 1025) vs. el `fw.hex` del TP anterior

Compare el mismo FW linkeado en `0x0` con `STANDALONE=1` (el `fw.hex` del TP anterior) y en
`0x1000` detras del BL, funcion por funcion y palabra por palabra:

| Funcion | Standalone | Combinado | Codificacion |
|---|---|---|---|
| arranque | `_start` en `0x000` | header + `Reset_Handler` en `0x1000` | otro codigo |
| `uart0_send.part.0` | `0x010` | `0x1090` | identica |
| `print_chr`, `print_str`, `print_flush_buffer` | `0x068`… | `0x10E8`… | identica |
| `print_dec` | `0x0DC` | `0x115C` | cambian los 2 `jal` a libgcc |
| `print_hex` | `0x17C`, 0x6C B | `0x11FC`, 0x70 B | +1 `lui`; cambian `li`→`addi`, un `bltz` y un `jal` |
| `main` | `0x1EC`, 0xE4 B | `0x1270`, 0xEC B | +2 `lui`; cambian 2 `li`→`addi` y 3 `jal` |
| `__divsi3`, `__udivsi3`, `__umodsi3`, `__modsi3` | `0x2D0`… | `0x135C`… | identica |

No cambian:

- Las instrucciones PC-relativas (`jal`, `beq`/`bne`…, `auipc`) cuyo origen y destino se
  movieron juntos, porque codifican la distancia y no la direccion. `uart0_send`, `print_chr`,
  `print_str` y la division de libgcc son iguales bit a bit aunque se corrieron `0x1080` bytes:

  ```
  standalone fw.hex líneas 5–8          00042737 00c70713 00072783 fe078ee3
  combinado  fw.hex líneas 1061–1064    00042737 00c70713 00072783 fe078ee3
  ```

  `objdump` muestra destinos distintos (`jal 10` vs. `jal 1090`) porque imprime la direccion final,
  pero la palabra es la misma.
- Los accesos a direcciones fijas que no dependen de donde se linkea el codigo: registros
  (`lui a4,0x42` → UART en `0x4200C`; `lui s6,0x40` → `REG_FW_STATUS`) y las globales en RAM
  (`int_0..2` siguen en `0x20000`–`0x2000B`).

Cambian:

- Las que cargan direcciones absolutas de la propia imagen: los punteros a los strings de
  `.rodata`. GCC emite `lui a0,%hi(.LC0)` + `addi a0,a0,%lo(.LC0)` (relocaciones `R_RISCV_HI20` /
  `R_RISCV_LO12_I` + `R_RISCV_RELAX`, modelo `medlow`). En el standalone los strings estan por
  debajo de `0x800`: `%hi` da 0 y el linker "relaja", borra el `lui` y deja una sola instruccion
  relativa a `zero`. En `0x1000+`, `%hi` es 1 y el `lui` se queda:

  ```
  standalone   39800513   li   a0,920                    # 0x398, una instrucción
  combinado    00001537   lui  a0,0x1
               42450513   addi a0,a0,1060  # 0x1424      # dos instrucciones
  ```

  Con `-Wl,--no-relax` el standalone tambien tiene `lui a0,0x0` + `addi`, lo que confirma que la
  diferencia viene de la relajacion.
- Como efecto secundario, los `jal`/branches cuya distancia cruza codigo que crecio. `print_hex`
  (+4 B) y `main` (+8 B) corren todo lo que viene despues. Por eso cambian los `jal` de `main` a
  `print_str`/`print_dec`, los de `print_dec` a `__umodsi3`/`__udivsi3`, y el `bltz` de `print_hex`
  que salta por encima del `lui` nuevo.

Relinkear no es "sumarle `0x1000`" a todo: cambian las direcciones absolutas y, por la relajacion,
tambien el tamanio del codigo.

### 5. `jr` y no `jalr ra`; por que el FW vuelve a cargar `sp`

`jr t0` es `jalr x0, 0(t0)`: salta sin guardar la direccion de retorno. Un `jalr ra, 0(t0)` seria
un `call`, que da a entender que el FW puede volver al BL. Pero no hay adonde volver:

- El stack del BL ya no existe. `_bl_stack_top` y el `initial_sp` del FW son la misma direccion
  (`0x40000`), asi que el stack del FW pisa los frames de `bl_main` (incluido el `line[64]` de
  `bl_log_hex`) apenas arranca.
- Despues de la llamada a `bl_jump()` no hay codigo del BL. Como es `noreturn`, GCC no genera nada
  despues del `jal`: el `jal 24 <bl_jump>` en `0x254` es la ultima instruccion de `bl_main`, y en
  `0x258` ya empieza `uart0_send.part.0`. El `ra` que trae `bl_jump` (`0x258`) apunta al medio de
  otra funcion, y por eso `bl_jump` lo pisa con `li ra,0` ademas de usar `jr`.
- Es un traspaso de control, como el reset de Cortex-M, donde el hardware tampoco "llama" al
  `Reset_Handler`.

Con `ra = 0` no queda ningun puntero a codigo del BL, y el backtrace del debugger termina ahi.

**El FW vuelve a cargar `sp`** (`la sp, _stack_top`, la primera instruccion del `Reset_Handler`)
porque no puede depender de quien lo arranco:

- `Reset_Handler` es el entry point de `app.elf` (`0x1018`). Un debugger que carga el ELF y arranca
  en el entry, otro BL o un salto "en caliente" lo ejecutan sin el `sp` del header, y picorv32 no
  inicializa `sp` (`STACKADDR = 0xFFFF_FFFF`).
- Que el BL cargue `initial_sp` es una convencion de este BL. Si tuviera un bug, el FW arrancaria
  con un stack invalido.
- Cuesta 2 instrucciones, y como los dos valores salen del mismo simbolo (`_stack_top`), no cambia
  nada cuando el BL hizo bien su parte. En Cortex-M pasa lo mismo: el hardware carga `MSP` de la
  tabla, pero muchos startups igual hacen `ldr sp, =_estack` por si los arranca un BL.

### 6. `REG_FW_STATUS`: ni `0xFF` en el BL, ni solo `0xBAD` en un error

El testbench termina en cuanto ve `0xFF`:

```
while (REGISTER_FW_STATUS != 32'hFF && trap == 0) @(posedge clk);
```

`0xFF` es el PASS **del test del FW**, no del BL. Si el BL lo escribiera, la simulacion terminaria
100 ciclos despues con `REGISTER_FW_STATUS = 000000ff` aunque el FW no hubiera llegado a correr, o
fuera a fallar: un PASS falso. Ademas, el `Reset_Handler` mira ese registro cuando `main` vuelve
para decidir entre el loop (PASS) y el `ebreak`. En hardware, donde nadie corta en `0xFF`, un
`main` que no escribe el status heredaria el PASS del BL. Por eso el BL hace lo contrario: escribe
`REG_FW_STATUS = 0` al arrancar.

**`0xBAD` no alcanza** por dos motivos:

1. El testbench solo corta con `0xFF` o con trap. Con `0xBAD` el `while` sigue y la simulacion no
   termina nunca (no hay timeout).
2. Escribir un registro no detiene el core. Si `bl_fail()` volviera, el BL seguiria hacia
   `bl_jump()` con la imagen que acaba de rechazar.

`ebreak` con `ENABLE_IRQ = 0` lleva a picorv32 a `cpu_state_trap` (`trap <= 1`): el core se
detiene y el testbench termina con `TRAP!`. El `1: j 1b` despues del `ebreak` esta por si el core
no se detuviera. `0xBAD` sirve para el diagnostico, junto con `REG_FW_REPORT = BL_REPORT_ERROR |
codigo` (`0xB007E004` para el CRC), que se ve en las ondas. Para que el testbench vea el trap
hizo falta el arreglo de `rtl/testbench.sv` que esta en el hito 7.

### 7. Qué queda de `strutils.o` en `bl.elf`

```
nm -n -S build/bl.elf | grep -E 'crc|print|uart'
  00000258 00000058 t uart0_send.part.0      <- print.c
  000002b0 00000030 T print_str              <- print.c
  000002e0 00000038 T str_crc8               <- strutils.c
```

De `strutils.o` queda **solo `str_crc8`**. Es la unica funcion que define el `strutils.c` local
(`strbuf_*` y `str_trim` solo estan declaradas en `strutils.h`) y la unica que usa el BL: `bl_main`
la llama para validar el CRC. Si `strutils.c` tuviera las demas funciones del TP3, el linker las
descartaria igual que a las de `print.c`, porque nadie las referencia.

`-ffunction-sections -fdata-sections` pone cada funcion y cada dato en su propia seccion
(`.text.str_crc8`, `.text.print_hex`…). `--gc-sections` parte del entry (`_bl_vectors`) y de las
secciones `KEEP`, sigue las relocaciones y tira toda seccion a la que no llega.
`-Wl,--print-gc-sections` muestra lo que tira:

```
removing unused section '.text.print_chr'
removing unused section '.text.print_dec'
removing unused section '.text.print_hex'           (+ '.rodata.print_hex.str1.4')
removing unused section '.text.print_flush_buffer'
removing unused section '.text' in libgcc.a(div.o)  <- __divsi3 y compañía, que solo usaba print_dec
```

Sin `--gc-sections`, o sin `-ffunction-sections` (cada `.o` queda con una sola `.text` y usar
`print_str` arrastra todo `print.c`, y con el la division de libgcc), el BL pasa de **1416 B a
1936 B**.

**Lo que `nm` no muestra:** con GCC 16.1 y `-O2`, `str_crc8` ya no es el loop bit a bit del
fuente. El pase de optimizacion de CRC (`-foptimize-crc`) lo reconoce y lo reemplaza por una
**tabla de 256 bytes** que el compilador agrega en `.rodata`, sin simbolo:

```
bl.map    .rodata  0x00000488  0x100  (el .o temporal de strutils.c)   <- 0x488–0x587, líneas 291–354
objdump   2ec:  li   a2,1160         # a2 = 0x488, la tabla
          2fc:  xor  a0,a0,a4        # crc ^= byte
          300:  add  a0,a2,a0
          304:  lbu  a0,0(a0)        # crc = tabla[crc ^ byte]
```

Con `-fno-optimize-crc`, `str_crc8` ocupa 92 B y no hay `.rodata`. Para el BL no es un problema
de reglas: la tabla es constante y vive en `BL_ROM`, no es una global, asi que no dispara los
`ASSERT` de `bl.ld`. Pero son 256 B de los 1416 B del BL (18 %), a cambio de un loop de 7
instrucciones por byte en lugar de un loop interno de 8 iteraciones.

### 8. `rv32ic` sin `.option norvc`

Lo probe compilando el BL con `-march=rv32ic`:

| Variante de `bl_start.S` | Vector table |
|---|---|
| Tal cual, con o sin `norvc` | 5 `jal` de 4 bytes, como en `rv32i` |
| Sin `norvc`, con los handlers en la misma seccion que la tabla | 5 `c.j` de 2 bytes |
| Sin `norvc`, con `tail` en vez de `j` | 5 `c.j` de 2 bytes |
| **Con** `norvc` y `tail` en vez de `j` | 5 `c.j` de 2 bytes |

El caso de la pregunta (segunda fila):

```
00000000 <_bl_vectors>:
   0:  a029      j     a <bl_reset_handler>    <- PROGADDR_RESET: el reset sigue andando
   2:  a831      j     1e <bl_unexpected>
   ...
   8:  a819      j     1e <bl_unexpected>
0000000a <bl_reset_handler>:
   a:  00040117  auipc sp,0x40
   e:  ff610113  addi  sp,sp,-10               <- 0x10 = PROGADDR_IRQ cae en la mitad de esta instrucción
```

- La tabla se achica a 10 bytes y los "vectores" dejan de estar en `0x04`…`0x10`. El reset anda
  porque esta en `0x0`, pero una IRQ saltaria a `0x10`, a la mitad del `addi`, y el core ejecutaria
  la mitad alta (`0xff61`) como si fuera una instrucciin comprimida: `c.bnez a4, …`, basura.
- Ese BL ademas deja de correr en cualquier `top.v`. Con `COMPRESSED_ISA(0)` (el default del
  `top.v` actual), el `c.j` de `0x0` es una instruccion ilegal y el core hace trap en la primera
  instruccion. Por eso el `Makefile` compila el BL siempre en `rv32i`.

**Por que con el `bl_start.S` actual no pasa:** `j bl_reset_handler` salta a otra seccion
(`.text.bl_reset_handler`). El ensamblador no conoce la distancia y emite un `jal` de 4 bytes con
`R_RISCV_JAL`, y ld no relaja `R_RISCV_JAL` a `c.j`. Es casualidad de como estan repartidas las
secciones. El resto del BL si se comprime: el `call bl_main` de `0x1c` queda como `c.jal` de 2
bytes. `.option norvc` es lo que garantiza los 4 bytes sin importar donde esten los handlers.

**Y no alcanza solo con `norvc`** (ultima fila): `.option norvc` controla al ensamblador, no al
linker. `tail` y `call` emiten `auipc` + `jalr` con `R_RISCV_CALL` + `R_RISCV_RELAX`, y ld los relaja
a `c.j` porque el objeto esta marcado como RVC, aunque esa zona sea `norvc`. `objdump` los muestra
como `.insn 2, 0xa029` porque el mapping symbol dice que ahi no hay C. Para evitarlo habria que
agregar `.option norelax`. `bl_start.S` usa `j` (`R_RISCV_JAL`, que ld no relaja) + `norvc`, y eso
asegura que cada vector ocupe 4 bytes.
