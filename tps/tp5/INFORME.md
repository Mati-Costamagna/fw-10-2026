# INFORME - TP5

## Hito 1

Cree los archivos base de los cuatro drivers, vacios, en las carpetas que pide la consigna:

| `fw/drivers/inc/` | `fw/drivers/src/` |
|---|---|
| `led.h` | `led.c` |
| `uart.h` | `uart.c` |
| `dma.h` | `dma.c` |
| `adc.h` | `adc.c` |

- `uart1.h` y `uart1.c` ya venian de la catedra (hito 3.b).
- Los drivers se suman a `fw/sources.mk` a medida que los implemento (el LED en el hito 2).
- No hubo errores en este hito.

### 1. ¿Por qué conviene separar interfaz pública en archivos .h e implementación en archivos .c?

Permite desacoplar los modulos, ocultar los detalles internos y facilitar la reutilizacion del codigo.

- El `.h` es el contrato: los prototipos que puede usar el resto del programa. El `.c` tiene la implementacion y el acceso al hardware. En el driver de LED, `REG_LED` solo aparece en `led.c`; el que llama al driver usa `led_on()`, `led_get_mask()`, etc.
- Se puede cambiar la implementacion sin tocar a quien usa el driver: pasar de guardar el estado en una variable a acceder directo a `REG_LED` (hito 2) es un cambio solo en `led.c`, los prototipos de `led.h` quedan iguales.
- El `.h` solo debe tener declaraciones. Se incluye en varios `.c`, y si tiene una definicion (como el `const uint8_t leds_num = 8;` del hito 2) el link falla con `multiple definition`.

## Hito 2

Driver de LED en `fw/drivers/inc/led.h` y `fw/drivers/src/led.c`.

| Funcion | Que hace |
|---|---|
| `led_init()` | `REG_LED = 0`, todos los LEDs apagados |
| `led_on(idx)` | `REG_LED \|= (1u << idx)` |
| `led_off(idx)` | `REG_LED &= ~(1u << idx)` |
| `led_toggle(idx)` | `REG_LED ^= (1u << idx)` |
| `led_write(value)` | `REG_LED = value` (8 bits) |
| `led_set_mask(mask)` | `REG_LED = mask & 0xFF`, descarta los bits 8 a 31 |
| `led_get_mask()` | `REG_LED & 0xFF` |
| `led_get_status(idx)` | `(REG_LED >> idx) & 1u`, o sea 0 o 1 |

### Decisiones tecnicas

- **Sin copia del estado en RAM:** el driver lee y escribe directo `REG_LED` (`0x4_0038`). El registro es RW, asi que se puede hacer read-modify-write y el estado que devuelve el driver siempre es el del hardware.
- **El registro solo se ve en `led.c`:** `led.c` incluye `includes.h` (que trae `config.h` con `REG_LED`). `led.h` solo expone la API, `LED_COUNT` y `<stdint.h>`, asi que el que usa el driver no puede tocar el registro.
- **Solo los 8 bits bajos:** `led_set_mask` y `led_get_mask` enmascaran con `0xFF`, porque los bits 8 a 31 de `REG_LED` no son LEDs.
- `LED_COUNT` es un `#define` y el header tiene include guards (`#ifndef LED_H`).

### Validacion

`test_drivers.c` necesita los cuatro drivers para linkear, asi que para este hito arme un test propio, `fw/tests/test_led.c`. Despues de cada operacion compara `led_get_mask()` con el valor esperado e imprime `OK` o `FALLA` por UART. Al final deja `REG_FW_STATUS = 0xFF` si todo dio bien o `0xBAD` si algo fallo.

```bash
make -C fw TARGET=test_led
make sim
```

```
UART: [BL] arrancó
UART: [BL] imagen del FW valida
UART: [BL] saltando al FW, reset_handler=0x00001018
UART: init
UART:   OK
LED: 0b00000001
UART: on 0
UART:   OK
LED: 0b00001001
LED: 0b10001001
UART: on 3 y 7
UART:   OK
LED: 0b10001000
UART: off 0
UART:   OK
LED: 0b10000000
UART: toggle 3
UART:   OK
LED: 0b10001000
UART: toggle 3 otra
UART:   OK
LED: 0b10100101
UART: set_mask 0x1A5
UART:   OK
LED: 0b00001111
UART: write 0x0F
UART:   OK
UART: idx invalidos
UART:   OK
UART: -- test LED PASS --
ending simulation, u_top.u_register_file.REGISTER_FW_STATUS = 000000ff
total clocks:               753249
RESULT: PASS
```

- Cada linea `LED:` (la imprime el testbench cada vez que cambia `REG_LED`) coincide con la mascara esperada: on/off/toggle de un bit y de varios bits.
- Las lineas `LED:` salen antes que el texto de UART de cada paso porque el registro cambia en el momento y la UART tarda en transmitir.
- `led_set_mask(0x1A5)` deja `0b10100101` (`0xA5`): el bit 8 se descarta.
- Despues de "idx invalidos" (`led_on(8)`, `led_off(9)`, `led_toggle(255)`) no aparece ninguna linea `LED:`, o sea que el registro no cambio.

### 1. ¿Qué política usaron para idx inválido y por qué?

Si `idx >= LED_COUNT` (8), `led_on`, `led_off` y `led_toggle` retornan sin tocar `REG_LED`, y `led_get_status` devuelve 0. Lo elegi porque la consigna pide no modificar el registro con un `idx` invalido, los bits 8 a 31 de `REG_LED` no son LEDs, y chequear antes del shift evita `1u << idx` con `idx >= 32`, que en C es comportamiento indefinido.

## Hito 3.a

Driver de UART0 en `fw/drivers/inc/uart.h` y `fw/drivers/src/uart.c`. `uart_id_t` tiene un solo valor, `UART0`.

| Funcion | Que hace |
|---|---|
| `uart_init(uart)` | Baja START, espera que termine la transmision en curso y descarta lo recibido |
| `uart_write_byte(uart, c)` | Manda un byte y espera que termine |
| `uart_write_str(uart, s)` | Manda `s` hasta el `'\0'`, en bloques de 256 si es mas largo |
| `uart_rx_available(uart)` | 1 si llego al menos un byte desde el ultimo flush |
| `uart_rx_count(uart)` | Cantidad de bytes recibidos |
| `uart_read(uart, buf, max)` | Copia hasta `max` bytes recibidos en `buf` y devuelve cuantos copio |
| `uart_rx_flush(uart)` | Descarta lo recibido |

### Validacion

`test_new_uart.c` escribia los registros de UART0 directamente, asi que lo reescribi para que use el driver. Hace lo mismo que antes (manda `hello Luigi!`, le pide al testbench que mande `HOLA!` con `REG_AUX_0 = 0x5ED5ED` y hace el eco) y agrega chequeos de bytes sueltos, uart invalido, un string de 300 caracteres, `uart_read` con `max` y flush.

```bash
make -C fw TARGET=test_new_uart
make sim
```

```
UART: [BL] arrancó
UART: [BL] imagen del FW valida
UART: [BL] saltando al FW, reset_handler=0x00001018
UART: hello Luigi!
UART: O
UART: K
UART: abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuv
UART: wxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmn
UART: rx vacio despues de init
UART:   OK
UART: HOLA!
UART: rx = HOLA!
UART:   OK
UART: read con max = 2
UART:   OK
UART: uart invalido
UART:   OK
UART: flush
UART:   OK
UART: -- test UART PASS --
ending simulation, u_top.u_register_file.REGISTER_FW_STATUS = 000000ff
RESULT: PASS
```

- `hello Luigi!` y `HOLA!` son las mismas lineas que da el test original.
- Cada `uart_write_byte` es una transmision aparte (lineas `O` y `K`).
- Lo que se manda con un `uart_id_t` invalido no aparece.
- El string de 300 caracteres sale en dos transmisiones: 256 y 44.
- Fuera de `uart.c`, `REG_UART0_*` solo aparece en `config.h` (las definiciones), en `print.c` (ver arriba) y en los tests de la catedra `test_drivers.c` y `test_dma.c`, que leen los registros para verificar. `test_new_uart.c` solo usa la constante `REG_ARRAY_UART0_BUFF_IN_SIZE`.


## Hito 3.b

Driver de UART1 (serie 8N1, FIFOs RX y TX de 16 bytes) en `fw/drivers/src/uart1.c`. La interfaz `uart1.h` ya venia dada. Sume `drivers/src/uart1.c` a `fw/sources.mk`.

| Funcion | Que hace |
|---|---|
| `uart1_init(baud_div)` | `REG_UART1_BAUD_DIV = baud_div` y `uart1_clear_errors()` |
| `uart1_rx_level()` | `UART1_ST_RX_LEVEL(REG_UART1_STATUS)`, bits 15:8 |
| `uart1_getc(&b)` | Lee `RX_DATA` una vez; si `VALID` (bit 8) esta en 1 guarda los bits 7:0 en `*b` y devuelve 1, si no devuelve 0 sin tocar `*b` |
| `uart1_putc(b)` | Espera mientras `TX_FULL` y escribe `TX_DATA` |
| `uart1_write(buf, n)` | `uart1_putc` de cada byte |
| `uart1_tx_idle()` | Bit `TX_IDLE` del STATUS: FIFO TX vacio y ultimo byte ya enviado |
| `uart1_errors()` | Pasa `FRAME_ERR` (bit 3) a `UART1_ERR_FRAME` (bit 0) y `OVERRUN` (bit 2) a `UART1_ERR_OVERRUN` (bit 1) |
| `uart1_clear_errors()` | `REG_UART1_CTRL = (REG_UART1_CTRL & RTS) \| CLR_ERR` |

### Errores encontrados

**No existe `make test_uart_serial`:** la consigna lo nombra, pero el Makefile de la raiz solo tiene `fw`, `sim` y `wave`. El host de UART1 del testbench solo actua si el simulador recibe `+UART1_SCRIPT=<archivo>`, y `make sim` corre `./obj_dir/Vtestbench` sin argumentos. Sin patron, `test_uart_serial.c` se queda esperando comandos en su `for (;;)` y la simulacion no termina. Sin agregar reglas al Makefile, compilo el FW con `make -C fw`, compilo el simulador con el mismo comando de Verilator que usa `make sim` y lo corro pasandole el patron. Como no paso `+NOWAVE`, se genera `wave.vcd` y despues se puede usar `make wave`. Con `+VERBOSE`, el host imprime cada byte que manda.

### Validacion

```bash
make -C fw TARGET=test_uart_serial
verilator --binary --trace -Wno-fatal -f filelist.f
./obj_dir/Vtestbench +UART1_SCRIPT=fw/tests/test_uart_serial.txt
```

```
UART: [BL] arrancó
UART: [BL] imagen del FW valida
UART: [BL] saltando al FW, reset_handler=0x00001018
[ OK ] recibido: 4b 
[ OK ] recibido: 32 bytes
[ OK ] recibido: 32 bytes
[ OK ] recibido: 32 bytes
[ OK ] recibido: 32 bytes
[ OK ] recibido: 32 bytes
[ OK ] recibido: 32 bytes
[ OK ] recibido: 32 bytes
[ OK ] recibido: 32 bytes
[ OK ] recibido: a5 5a 00 ff 5a a5 
[ OK ] recibido: 52 01 
[ OK ] recibido: 53 
[ OK ] recibido: 52 02 
[ OK ] recibido: 52 00 
CHECK PASS (14/14)
ending simulation, u_top.u_register_file.REGISTER_FW_STATUS = 00000000
total clocks:               530612
RESULT: PASS
```

- `4b`: el FW arranco y mando `K`.
- Los ocho bloques de 32 bytes son el eco de `00`..`FF` (cuatro comandos `E` de 64 bytes), y `a5 5a 00 ff 5a a5` el de los bytes parecidos al protocolo.
- `52 01`: el byte con el stop en 0 marco framing error. Con un stop malo el hardware no mete el byte en el FIFO RX, asi que no llega a la app.
- `53` y `52 02`: los 40 bytes que llegaron mientras el FW no leia (el FIFO tiene 16) provocaron overrun. El framing error ya se habia limpiado con el `R` anterior.
- `52 00`: los flags se limpiaron al leerlos.
- En las ondas, `CTRL` se escribe `0x2` en `uart1_init` (RTS seguia en 0, como despues del reset) y `0x3` en cada `R`: `uart1_clear_errors()` no baja RTS.
- Fuera de `uart1.c`, `REG_UART1_*` solo aparece en `config.h` y en `rts_high()` de `test_uart_serial.c` (de la catedra, que deja RTS en alto sin `uart1_set_rts()`).
- `test_led` y `test_new_uart` siguen dando PASS con `uart1.c` en `sources.mk`.

## Hito 4

Driver de DMA en `fw/drivers/inc/dma.h` y `fw/drivers/src/dma.c`. Sume `drivers/src/dma.c` a `fw/sources.mk`.

| Funcion | Que hace |
|---|---|
| `dma_init()` | `REG_DMA_START = 0`, para que la primera copia genere el flanco 0->1 |
| `dma_copy(src, dst, n_words)` | Valida `src` y `dst`, carga `SOURCE_ADDR`, `DEST_ADDR` y `SIZE`, escribe `START = 0` y `START = 1` y espera `DONE`. Devuelve `DMA_OK` (0), `DMA_ERR_ADDR` (-1) o `DMA_ERR_OVERLAP` (-2) |
| `dma_is_done()` | `REG_DMA_DONE & 1u` |

### Validacion

`fw/tests/test_dma_driver.c` usa solo la API de `dma.h`. El destino tiene 4 palabras de guarda a cada lado con `0xA5A5A5A5`, para detectar escrituras fuera del rango. Imprime `OK` o `FALLA` por chequeo y deja `REG_FW_STATUS` en `0xFF` o `0xBAD`.

```bash
make -C fw TARGET=test_dma_driver
make sim
```

```
UART: [BL] arrancó
UART: [BL] imagen del FW valida
UART: [BL] saltando al FW, reset_handler=0x00001018
UART: copia 64 palabras
UART:   OK
UART: dma_is_done
UART:   OK
UART: segunda copia (flanco START)
UART:   OK
UART: 1 palabra
UART:   OK
UART: n_words = 0
UART:   OK
UART: desde mem. de instrucciones
UART:   OK
UART: src NULL
UART:   OK
UART: dst NULL
UART:   OK
UART: src desalineado
UART:   OK
UART: dst desalineado
UART:   OK
UART: dst fuera del mapa
UART:   OK
UART: src fuera del mapa
UART:   OK
UART: cruza fin de RAM
UART:   OK
UART: n_words enorme
UART:   OK
UART: solape dst > src
UART:   OK
UART: solape dst < src
UART:   OK
UART: mismo buffer
UART:   OK
UART: contiguos sin solape
UART:   OK
UART: copia despues de errores
UART:   OK
UART: -- test DMA driver PASS --
ending simulation, u_top.u_register_file.REGISTER_FW_STATUS = 000000ff
total clocks:              1320807
RESULT: PASS
```

- Las copias de 64, 7 y 1 palabra dejan el destino igual al origen y las guardas intactas. La segunda copia confirma que el flanco de `START` se genera en cada llamada.
- `dma_is_done` da 1 despues de una copia.
- `n_words = 0` devuelve `DMA_OK` y no toca el destino.
- La copia desde la memoria de instrucciones (`0x1000`, el codigo del FW) coincide con lo que lee la CPU.
- Las direcciones invalidas devuelven `DMA_ERR_ADDR` con el destino intacto, o sea que el DMA no arranco. Que la simulacion termine tambien lo muestra: si el DMA hubiera ido a `0x6_0000` o a `0x8000_0000`, se colgaba todo.
- Los tres casos de solapamiento devuelven `DMA_ERR_OVERLAP` sin modificar `A`. Dos bloques contiguos no se solapan y se copian.
- Despues de todos los errores, una copia de 64 palabras sigue andando.
- `test_dma` (de la catedra) sigue dando PASS con `dma.c` compilado.
- Fuera de `dma.c`, `REG_DMA_*` solo aparece en `config.h` (las definiciones) y en `test_dma.c` de la catedra, que prueba el hardware sin driver.

### 1. ¿Qué pasa si dst y src se solapan? ¿Cómo lo documentaron?

El DMA copia hacia adelante de a una palabra: lee la `i`, la escribe y recien despues lee la `i+1`.

- Si `dst < src`, cada palabra se lee antes de que la pisen y la copia sale bien.
- Si `dst > src`, se pisan palabras del origen que todavia no se copiaron y las primeras `(dst - src) / 4` palabras se repiten. Por ejemplo, con `src = &A[0]`, `dst = &A[4]` y `n_words = 16`, `A[4..19]` termina con `A[0..3]` repetido cuatro veces.

El driver rechaza cualquier solapamiento, en las dos direcciones, con `DMA_ERR_OVERLAP` y sin arrancar el DMA. Rechazar tambien el caso `dst < src`, que funcionaria, deja una regla simple que no depende de como recorre la memoria el hardware. Los rangos se solapan si `s < d + bytes && d < s + bytes`.   
