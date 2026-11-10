# TP4 — Informe (hitos 1 a 8)

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
RAM no se carga desde el hex y arranca en 0, así que `tp4_data_word` (que cae en
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
`0xFF` o con trap, así que hace falta el `ebreak` de `bl_halt()`.

| Corrida | Resultado |
|---|---|
| `make sim` | `[BL] imagen del FW valida` → FW → `REGISTER_FW_STATUS = 000000ff` |
| `make sim CORRUPT=1` | `[BL] ERROR: CRC invalido, imagen corrupta` → `------ TRAP! ------- clock_counts = 28874` |

Testbench del repo: `rtl/testbench.sv` declara `wire trap;` sin conectarlo a `u_top.trap` 
(`top` no tiene puerto `trap`), por lo que tal cual está el trap nunca llega al testbench y 
`CORRUPT=1` corre sin terminar. Error que viene arrastrado desde el TP1.

---

## Hito 8 — Revisar la memoria y matchear con el HEX (diapo 12)

Todo con el FW que tiene `.data` y `.bss` (para el paso 4):

```bash
make sim APP_SRC="print.c test_data_bss.c"
make check
make inspect APP_SRC="print.c test_data_bss.c"
```

`make inspect` depende de `build/fw.mode`, así que rearma la imagen si cambia `APP_SRC`. 
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

`bl.map` dice que el BL termina en `0x587` (línea 354) y `app.map` que la imagen del FW
termina en `__fw_end = 0x16F0` (la linea 1468 es la ultima palabra, `0x16EC`). Los dos
coinciden con lo que imprime `mkimage.py` y con el largo de `fw.hex`.

### 2. readelf / objdump

Vector table del BL (`objdump -d build/bl.elf`): son **instrucciones**, y las mismas
palabras que las líneas 1–5 de `fw.hex`.

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

| Dirección | Campo | `app.elf` | `fw.hex` (línea) |
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
de `memory_i` (el comentario `// byte address` del testbench está mal: `addr += 1` por linea).
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
