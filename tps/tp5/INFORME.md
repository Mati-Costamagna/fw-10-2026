# INFORME - TP5: Drivers de perifericos

## Resumen

| Hito | Archivos principales | Evidencia | Resultado |
|---|---|---|---|
| 1. Preparacion | `fw/drivers/{inc,src}/`, `fw/sources.mk` | compila | OK |
| 2. LED | `led.h`, `led.c` | `fw/tests/test_led.c` (propio) | PASS |
| 3.a UART0 | `uart.h`, `uart.c` | `fw/tests/test_new_uart.c` (reescrito para usar el driver) | PASS |
| 3.b UART1 | `uart1.c` | `make test_uart_serial` | PASS, `CHECK PASS (14/14)` |
| 4. DMA | `dma.h`, `dma.c` | `fw/tests/test_dma_driver.c` (propio) | PASS |
| 5. ADC | `adc.h`, `adc.c` | `test_adc`, demo y grafico con 3 divisores | PASS |
| 6. Demo | `fw/app/demo_tp5.c`, `fw_status.h`, `fw_status.c` | demo completa y camino de falla | PASS / FAIL esperado |
| 7. Cierre | todo | compilacion desde cero, `make test_drivers`, `make test_uart_serial` | PASS |

## Hito 1 - Preparacion del proyecto

### Paso a paso

1. Cree los archivos base de los cuatro drivers, vacios, en las carpetas que pide la consigna:

   | `fw/drivers/inc/` | `fw/drivers/src/` |
   |---|---|
   | `led.h` | `led.c` |
   | `uart.h` | `uart.c` |
   | `dma.h` | `dma.c` |
   | `adc.h` | `adc.c` |

2. `uart1.h` y `uart1.c` ya venian con la interfaz documentada y los cuerpos vacios (hito 3.b).
3. Fui sumando cada `.c` a `fw/sources.mk` a medida que lo implementaba (el LED en el hito 2, y asi). Al final quedo:

   ```make
   SRC += drivers/src/led.c
   SRC += drivers/src/uart.c
   SRC += drivers/src/uart1.c
   SRC += drivers/src/dma.c
   SRC += drivers/src/adc.c
   SRC += drivers/src/fw_status.c
   ```

### Decisiones tecnicas

- Cada `.c` se suma a `sources.mk` en el hito en que se implementa, asi cada hito se compila y se valida con lo que ya esta hecho.
- Los headers de mis drivers tienen include guards (`#ifndef LED_H` ...) e incluyen solo `<stdint.h>`, no `config.h`. Eso es lo que despues permite que el compilador chequee que la demo no toca registros (hito 6). `uart1.h`, que venia dado, si incluye `includes.h`.

### Errores encontrados

No hubo errores en este hito.

### Validacion

`make -C fw` compila sin errores con los archivos nuevos (todavia sin funciones).

### 1. ¿Por qué conviene separar interfaz pública en archivos .h e implementación en archivos .c?

Permite desacoplar los modulos, ocultar los detalles internos y facilitar la reutilizacion del codigo.

- El `.h` es el contrato: los prototipos que puede usar el resto del programa. El `.c` tiene la implementacion y el acceso al hardware. En el driver de LED, `REG_LED` solo aparece en `led.c`; el que llama al driver usa `led_on()`, `led_get_mask()`, etc.
- Se puede cambiar la implementacion sin tocar a quien usa el driver: pasar de guardar el estado en una variable a acceder directo a `REG_LED` (hito 2) es un cambio solo en `led.c`, los prototipos de `led.h` quedan iguales.
- El `.h` solo debe tener declaraciones. Se incluye en varios `.c`, y si tiene una definicion (como el `const uint8_t leds_num = 8;` del hito 2) el link falla con `multiple definition`.

## Hito 2 - Driver LED

### Paso a paso

1. Escribi la interfaz requerida en `fw/drivers/inc/led.h` y la implementacion en `fw/drivers/src/led.c`:

   | Funcion | Que hace |
   |---|---|
   | `led_init()` | `REG_LED = 0`, todos los LEDs apagados |
   | `led_on(idx)` | `REG_LED \|= (1u << idx)` |
   | `led_off(idx)` | `REG_LED &= ~(1u << idx)` |
   | `led_toggle(idx)` | `REG_LED ^= (1u << idx)` |
   | `led_write(value)` | `REG_LED = value` (8 bits, no conserva el estado anterior) |
   | `led_set_mask(mask)` | `REG_LED = mask & 0xFF`, descarta los bits 8 a 31 |
   | `led_get_mask()` | `REG_LED & 0xFF` |
   | `led_get_status(idx)` | `(REG_LED >> idx) & 1u`, o sea 0 o 1 |

2. Sume `drivers/src/led.c` a `fw/sources.mk`.
3. Como `test_drivers.c` necesita los cuatro drivers para linkear, escribi un test propio, `fw/tests/test_led.c`, y lo corri.

### Decisiones tecnicas

- **Sin copia del estado en RAM:** el driver lee y escribe directo `REG_LED` (`0x4_0038`). El registro es RW, asi que se puede hacer read-modify-write y el estado que devuelve el driver siempre es el del hardware. La primera version guardaba el estado en una variable; el cambio fue solo en `led.c`.
- **El registro solo se ve en `led.c`:** `led.c` incluye `includes.h` (que trae `config.h` con `REG_LED`). `led.h` solo expone la API, `LED_COUNT` y `<stdint.h>`, asi que el que usa el driver no puede tocar el registro.
- **Solo los 8 bits bajos:** `led_set_mask` y `led_get_mask` enmascaran con `0xFF`, porque los bits 8 a 31 de `REG_LED` no son LEDs.
- **`idx` invalido no modifica nada** (ver la pregunta de control).

### Errores encontrados

**`multiple definition` al linkear:** la primera version definia la cantidad de LEDs en el header como `const uint8_t leds_num = 8;`. Como `led.h` se incluye desde `led.c` y desde el test, cada objeto tenia su propia definicion de `leds_num` y el link fallaba con `multiple definition`. Lo reemplace por `#define LED_COUNT 8u`, que no reserva memoria.

### Validacion

`test_led.c` compara `led_get_mask()` con el valor esperado despues de cada operacion e imprime `OK` o `FALLA` por UART. Al final deja `REG_FW_STATUS = 0xFF` si todo dio bien o `0xBAD` si algo fallo.

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
- `led_write(0x0F)` deja `0b00001111`: pisa el `0xA5` anterior, no lo combina.
- Despues de "idx invalidos" (`led_on(8)`, `led_off(9)`, `led_toggle(255)`) no aparece ninguna linea `LED:`, o sea que el registro no cambio.

### 1. ¿Qué política usaron para idx inválido y por qué?

Si `idx >= LED_COUNT` (8), `led_on`, `led_off` y `led_toggle` retornan sin tocar `REG_LED`, y `led_get_status` devuelve 0. Lo elegi porque la consigna pide no modificar el registro con un `idx` invalido, los bits 8 a 31 de `REG_LED` no son LEDs, y chequear antes del shift evita `1u << idx` con `idx >= 32`, que en C es comportamiento indefinido.

## Hito 3.a - Driver UART0

### Paso a paso

1. Escribi `fw/drivers/inc/uart.h` y `fw/drivers/src/uart.c` y sume `uart.c` a `sources.mk`. La interfaz requerida es `uart_write_byte(char c)` y `uart_write_str(const char *s)`; `uart_init` y las funciones de recepcion son extras:

   | Funcion | Que hace |
   |---|---|
   | `uart_init()` | Baja START, espera que termine la transmision en curso y descarta lo recibido |
   | `uart_write_byte(c)` | Manda un byte y espera que termine (bloqueante) |
   | `uart_write_str(s)` | Manda `s` hasta el `'\0'`, en bloques de 256 si es mas largo, y espera que termine (bloqueante) |
   | `uart_rx_available()` | 1 si llego al menos un byte desde el ultimo flush |
   | `uart_rx_count()` | Cantidad de bytes recibidos |
   | `uart_read(buf, max)` | Copia hasta `max` bytes recibidos en `buf` y devuelve cuantos copio |
   | `uart_rx_flush()` | Descarta lo recibido |

2. `test_new_uart.c` escribia los registros de UART0 directamente, asi que lo reescribi para que use el driver.
3. Busque con `grep` los usos de `REG_UART0_*` fuera de `uart.c`.

### Decisiones tecnicas

- **Bloqueante de los dos lados:** antes de cargar el buffer se espera `TRANSMISION_DONE` (para no pisar un buffer que todavia se esta mandando), y despues de `START` se espera de nuevo, asi al volver la transmision termino, como pide la consigna.
- **`START` se escribe 1 y vuelve a 0** en cada envio, asi la siguiente transmision siempre encuentra el registro en 0.
- **Cast a `unsigned char`** al cargar el buffer: `char` tiene signo, y sin el cast un `0xE9` quedaria `0xFFFFFFE9` en el registro de 32 bits.
- **Strings largos en bloques** de `REG_ARRAY_UART0_BUFF_OUT_SIZE` (256) bytes: el buffer de salida no admite mas. `s == NULL` se ignora.
- **`uart_read` nunca lee mas alla del buffer de entrada:** recorta a `min(INDEX_IN, 256, max)`.
- `print.c` (libreria de la catedra, la usan el bootloader y varios tests) tambien escribe los registros de UART0. No lo cambie para no tocar el bootloader, pero la demo del hito 6 no lo usa.

### Errores encontrados

**Interfaz distinta de la requerida:** la primera version tenia un `uart_id_t` (con un solo valor, `UART0`) como primer parametro de todas las funciones. Cuando la catedra actualizo la consigna y `test_drivers.c`, la interfaz requerida paso a ser exactamente `uart_write_byte(char c)` y `uart_write_str(const char *s)`, y `test_drivers.c` no compilaba con mi driver. Saque el parametro de todas las funciones y el chequeo de "uart invalido" de `test_new_uart.c`; actualice las llamadas de la demo.

### Validacion

`test_new_uart.c` hace lo mismo que el original (manda `hello Luigi!`, le pide al testbench que mande `HOLA!` con `REG_AUX_0 = 0x5ED5ED` y hace el eco) y agrega chequeos de bytes sueltos, un string de 300 caracteres, `uart_read` con `max` y flush.

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
UART: flush
UART:   OK
UART: -- test UART PASS --
ending simulation, u_top.u_register_file.REGISTER_FW_STATUS = 000000ff
RESULT: PASS
```

- `hello Luigi!` y `HOLA!` son las mismas lineas que da el test original.
- Cada `uart_write_byte` es una transmision aparte (lineas `O` y `K`).
- El string de 300 caracteres sale en dos transmisiones: 256 y 44.
- Fuera de `uart.c`, `REG_UART0_*` solo aparece en `config.h` (las definiciones), en `print.c` (ver decisiones) y en `test_drivers.c`, que lee los registros para verificar. `test_new_uart.c` solo usa la constante `REG_ARRAY_UART0_BUFF_IN_SIZE`.

## Hito 3.b - Driver UART1

### Paso a paso

1. Lei el datasheet de UART1 (serie 8N1, FIFOs RX y TX de 16 bytes) y la interfaz documentada en `uart1.h`, que ya venia dada.
2. Complete los cuerpos en `fw/drivers/src/uart1.c` y sume el archivo a `fw/sources.mk`:

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
   | `uart1_set_rts()` | Vacia: el control de flujo es del TP6 |

3. Corri `test_uart_serial` con su patron y mire `tx`, `rx` y los FIFOs en las ondas.

### Decisiones tecnicas

- **`uart1_getc` lee `RX_DATA` una sola vez:** cada lectura saca un byte del FIFO, y el dato y `VALID` vienen en la misma palabra. Leer una vez para mirar `VALID` y otra para el dato perderia un byte.
- **`uart1_putc` espera mientras `TX_FULL`:** con el FIFO lleno el hardware descarta el byte sin avisar.
- **`uart1_clear_errors` conserva RTS:** escribir `CTRL` reemplaza los dos bits. Leo el RTS actual del registro (no de una copia en RAM, porque `test_uart_serial.c` lo escribe por fuera del driver) y lo escribo junto con `CLR_ERR`.
- **`gap 1` en el patron** (ver errores).

### Errores encontrados

**1. No existia `make test_uart_serial`:** la consigna lo nombraba, pero el `Makefile` de la raiz solo tenia `fw`, `sim` y `wave`. El host de UART1 del testbench solo actua si el simulador recibe `+UART1_SCRIPT=<archivo>`, y `make sim` corria `./obj_dir/Vtestbench` sin argumentos: sin patron, `test_uart_serial.c` se quedaba esperando comandos en su `for (;;)` y la simulacion no terminaba. Mientras tanto lo corri a mano, sin tocar el Makefile:

```bash
make -C fw TARGET=test_uart_serial
verilator --binary --trace -Wno-fatal -f filelist.f
./obj_dir/Vtestbench +UART1_SCRIPT=fw/tests/test_uart_serial.txt
```

Despues la catedra actualizo el `Makefile` y ahora `make test_uart_serial` compila, simula con el patron y termina con `[ OK ] PASS` (hito 7).

**2. Eco corrido un bit con `gap 0`:** el eco volvia con los bytes corridos (`00`→`80`, `40`→`a0`) y faltaban bytes, aunque la `K` del arranque llegaba bien.

- En las ondas, el FIFO RX ya guardaba `0xa0` y el FW escribia en `TX_DATA` lo mismo que leia, asi que el driver no tenia la culpa.
- En la linea `rx`, el stop del primer byte duraba 64 clocks en vez de 32: el start del byte siguiente no aparecia y el DUT tomaba el bit 0 como start.
- Causa: en el host del testbench, el `<= 1'b1` del stop y el `<= 1'b0` del start siguiente caen en el mismo timestep cuando `gap` es 0, y con Verilator 5.052 gana el 1.
- Solucion: `gap 1` en `fw/tests/test_uart_serial.txt` (un clock de idle entre bytes). Con el mismo FW y testbench, `gap 0` da `CHECK FAIL (10 fallas de 11)` y `gap 1` da `CHECK PASS (14/14)`. No afloja el test: cada trama pasa de 320 a 321 clocks y los bytes del patron son los mismos. La version actualizada del patron de la catedra ya trae `gap 1`. El analisis completo esta en `DECISIONES.md`.

### Validacion

```bash
make test_uart_serial
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

Cada linea corresponde a un punto de lo que verifica la consigna:

1. `4b`: el FW arranco y mando `K`.
2. Los ocho bloques de 32 bytes son el eco de `00`..`FF` (cuatro comandos `E` de 64 bytes), y `a5 5a 00 ff 5a a5` el de los bytes parecidos al protocolo.
3. `52 01`: el byte con el stop en 0 marco framing error. Con un stop malo el hardware no mete el byte en el FIFO RX, asi que no llega a la app.
4. `53` y `52 02`: los 40 bytes que llegaron mientras el FW no leia (el FIFO tiene 16) provocaron overrun. El framing error ya se habia limpiado con el `R` anterior.
5. `52 00`: los flags se limpiaron al leerlos.

Ademas:

- En las ondas, `CTRL` se escribe `0x2` en `uart1_init` (RTS seguia en 0, como despues del reset) y `0x3` en cada `R`: `uart1_clear_errors()` no baja RTS.
- Fuera de `uart1.c`, `REG_UART1_*` solo aparece en `config.h` y en `rts_high()` de `test_uart_serial.c` (que deja RTS en alto sin `uart1_set_rts()`).
- `test_led` y `test_new_uart` siguen dando PASS con `uart1.c` en `sources.mk`.

## Hito 4 - Driver DMA

### Paso a paso

1. Lei `dma.v` para ver como arranca la copia (flanco de `START`), cuando sube `DONE` y como recorre la memoria.
2. Escribi `fw/drivers/inc/dma.h` y `fw/drivers/src/dma.c` y sume `dma.c` a `fw/sources.mk`:

   | Funcion | Que hace |
   |---|---|
   | `dma_init()` | `REG_DMA_START = 0`, para que la primera copia genere el flanco 0->1 |
   | `dma_copy(src, dst, n_words)` | Valida `src` y `dst`, carga `SOURCE_ADDR`, `DEST_ADDR` y `SIZE`, escribe `START = 0` y `START = 1` y espera `DONE`. Devuelve `DMA_OK` (0), `DMA_ERR_ADDR` (-1) o `DMA_ERR_OVERLAP` (-2) |
   | `dma_is_done()` | `REG_DMA_DONE & 1u` |

3. Escribi `fw/tests/test_dma_driver.c`, que usa solo la API de `dma.h`, y volvi a correr `test_dma` (el de la catedra, que prueba el hardware sin driver).

### Decisiones tecnicas

- **Flanco de `START` en cada copia:** el DMA arranca con el flanco 0->1, no con el nivel, y el register file guarda el ultimo valor escrito. Si `dma_copy` solo escribiera 1, la segunda copia no arrancaria. Por eso escribe 0 y despues 1, siempre despues de cargar origen, destino y tamano.
- **`dma_copy` es bloqueante:** espera `DONE` antes de volver, como pide la consigna. Asi el que llama no puede leer `dst` ni cambiar `src` con la copia a medias.
- **`n_words == 0` no arranca el DMA:** con `SIZE = 0` el hardware copiaria una palabra igual. Lo trato como una copia vacia valida, como `memcpy` con largo 0.
- **Validacion de direcciones antes de arrancar:** el rango entero (`n_words` palabras desde la direccion) tiene que caer en una sola region mapeada (instrucciones, datos o register file, todas dentro de `0x0000_0000`–`0x0005_FFFF`). Fuera de eso el bus no responde y se cuelga todo el SoC. Tambien rechazo NULL y direcciones no alineadas a 4. El chequeo divide (`(size - off) / 4`) en vez de multiplicar `n_words * 4`, para que un `n_words` enorme no desborde y pase el chequeo.
- **Se rechaza cualquier solapamiento** con `DMA_ERR_OVERLAP` (ver la pregunta de control).
- **Codigos de retorno:** la consigna no fija que devuelve `dma_copy`; devuelvo `int` con 0 para OK y negativos para error, con constantes en `dma.h`.

### Errores encontrados

**`dma_init` se colgaba:** la primera version de `dma_init` bajaba `START` y esperaba `DONE`. Pero `dma_done` no se inicializa en el reset (el `if (i_reset)` de `dma.v` no lo toca): arranca en 0 y solo sube al terminar una copia. Sin ninguna copia previa, el `while (!REG_DMA_DONE)` no salia nunca. Lo resolvi dejando `dma_init` solo con `REG_DMA_START = 0`. Por lo mismo, `dma_is_done()` devuelve 0 antes de la primera copia.

### Validacion

El destino tiene 4 palabras de guarda a cada lado con `0xA5A5A5A5`, para detectar escrituras fuera del rango. Imprime `OK` o `FALLA` por chequeo y deja `REG_FW_STATUS` en `0xFF` o `0xBAD`.

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
- `test_dma` sigue dando PASS con `dma.c` compilado (`[ OK ] test_dma PASS clocks=1245135`).
- Fuera de `dma.c`, `REG_DMA_*` solo aparece en `config.h` (las definiciones) y en `test_dma.c`, que prueba el hardware sin driver.

### 1. ¿Qué pasa si dst y src se solapan? ¿Cómo lo documentaron?

El DMA copia hacia adelante de a una palabra: lee la `i`, la escribe y recien despues lee la `i+1`.

- Si `dst < src`, cada palabra se lee antes de que la pisen y la copia sale bien.
- Si `dst > src`, se pisan palabras del origen que todavia no se copiaron y las primeras `(dst - src) / 4` palabras se repiten. Por ejemplo, con `src = &A[0]`, `dst = &A[4]` y `n_words = 16`, `A[4..19]` termina con `A[0..3]` repetido cuatro veces.

El driver rechaza cualquier solapamiento, en las dos direcciones, con `DMA_ERR_OVERLAP` y sin arrancar el DMA. Rechazar tambien el caso `dst < src`, que funcionaria, deja una regla simple que no depende de como recorre la memoria el hardware. Los rangos se solapan si `s < d + bytes && d < s + bytes`. Esta documentado en el comentario de `dma_copy` en `dma.h`.

## Hito 5 - Driver ADC

### Paso a paso

1. Lei `adc.sv` y `DATASHEET.md` para ver el arranque por flanco, los flags `HALF` y `DONE` y el modo circular.
2. Escribi `fw/drivers/inc/adc.h` y `fw/drivers/src/adc.c` y sume `adc.c` a `fw/sources.mk`:

   | Funcion | Que hace |
   |---|---|
   | `adc_init(clk_div)` | Rechaza `clk_div = 0`, baja `START` y escribe `CLK_DIVIDER`. Devuelve `ADC_OK` (0), `ADC_ERR_PARAM` (-1) o `ADC_ERR_BUSY` (-2) si hay una captura en curso |
   | `adc_start(adc_mode)` | `ADC_MODE_SINGLE` (1) o `ADC_MODE_CIRCULAR` (3): `adc_mode` es el valor que se escribe en `START` (bit 0 inicio, bit 1 circular). Escribe `START = 0` y despues `adc_mode`, y espera que baje el `DONE` de la captura anterior. Si `CLK_DIVIDER` esta en 0 pone 4 |
   | `adc_half_done()` | Espera que esten escritas las muestras 0..127 del lote. Devuelve 1, o 0 si no hay captura |
   | `adc_done()` | Espera el fin del lote (`DONE`). Devuelve 1, o 0 si no hay captura |
   | `adc_read(data, size)` | Hace una captura unica, espera `DONE` y copia `min(size, 256)` muestras. Devuelve cuantas copio (0 si `data` es nulo o `size` es 0) o `ADC_ERR_BUSY` |

3. Corri `test_adc` (de la catedra) para confirmar que el hardware se comporta como lei, y probe el driver desde la demo del hito 6, imprimiendo las muestras y ploteandolas con tres divisores.

### Decisiones tecnicas

- **Flanco 0->1 en `adc_start`:** igual que en el DMA, `START` queda guardado en el register file, asi que escribo 0 y despues `adc_mode`.
- **`adc_start` espera que baje el `DONE` viejo:** el `DONE` de la captura anterior sigue en 1 un par de ciclos despues del flanco. Si `adc_done` leyera antes, volveria enseguida con los datos de la captura anterior.
- **`clk_div = 0` se rechaza:** el ADC compara `div_cnt == clk_div - 1`, y con 0 eso da una muestra cada 2^32 clocks: el FW quedaria esperando `DONE` para siempre. Como `CLK_DIVIDER` no tiene reset y arranca en 0, `adc_start` pone 4 solo si sigue en 0; nunca pisa un divisor configurado, como pide la consigna.
- **`adc_init` no cambia el divisor con una captura en curso** (`ADC_ERR_BUSY`): cambiaria la frecuencia a mitad del lote y, si el nuevo divisor es menor que el contador, no hay muestras hasta que de la vuelta.
- **El driver recuerda el modo** en una variable `static`: `STATUS` no distingue un circular entre lotes de una captura unica terminada. Con eso `adc_half_done` y `adc_done` devuelven 0 si no hay captura en vez de esperar para siempre.
- **`adc_half_done` espera un tick mas despues de `HALF`:** en el RTL `HALF` sube con la muestra 126 escrita, no con la 128 como dice el datasheet.
- **`adc_read` copia con la CPU,** sin `dma_copy`, para que el driver de ADC no dependa del de DMA. Espera el lote entero aunque `size` sea menor que 256.
- **Muestras de 32 bits:** `DATA_WIDTH = NB_MEM_DATA` (`top.v:281`), por eso `adc_read` recibe `uint32_t *`.

### Errores encontrados

**1. `adc_read` sin `adc_init` con `CLK_DIVIDER = 0`:** la version anterior de `test_drivers.c` llamaba a `adc_read` sin configurar el divisor. `CLK_DIVIDER` no tiene reset y arranca en 0 (lo comprobe con un FW que lo imprimia al arrancar), y con 0 la captura no termina nunca: el FW quedaria esperando `DONE`. Lo resolvi con el divisor por defecto (4) que pone `adc_start` solo si el registro esta en 0.

**2. Cambios de la consigna en `adc_mode` y `adc_read`:** cuando la catedra actualizo la consigna y `test_drivers.c`:

- `adc_mode` paso a ser el valor que se escribe en `REG_ADC_START`. Yo tenia `ADC_MODE_CIRCULAR = 2` y `adc_start` lo traducia a 3. Lo cambie a `ADC_MODE_CIRCULAR = 3` y ahora `adc_start` escribe `adc_mode` tal cual (solo acepta 1 y 3).
- `adc_read` con `data` nulo tiene que devolver 0. Devolvia `ADC_ERR_PARAM`; ahora devuelve 0 sin arrancar el ADC (`test_drivers.c:219` lo chequea).

**3. Ejemplo de la consigna con `uint16_t`:** la primera version de la consigna usaba `uint16_t samples[256]`, que no coincide con el prototipo de `adc_read` y truncaria las muestras de 32 bits. La version actualizada usa `uint32_t`, como el driver.

### Validacion

**Hardware:** `test_adc.c` (de la catedra) escribe los registros del ADC directamente. Con los divisores 4, 8 y 16 hace una captura unica y una circular y espera los cambios de `STATUS`.

```bash
make -C fw TARGET=test_adc
make sim
```

```
UART: [BL] arrancó
UART: [BL] imagen del FW valida
UART: [BL] saltando al FW, reset_handler=0x00001018
UART: --half signal pass--
UART: --full signal pass--
UART: --start without repeticion pass--
UART: --circular function pass--
UART: ------TEST 1 PASS------
UART: --half signal pass--
UART: --full signal pass--
UART: --start without repeticion pass--
UART: --circular function pass--
UART: ------TEST 2 PASS------
UART: --half signal pass--
UART: --full signal pass--
UART: --start without repeticion pass--
UART: --circular function pass--
UART: ------TEST 3 PASS------
ending simulation, u_top.u_register_file.REGISTER_FW_STATUS = 000000ff
total clocks:               796526
RESULT: PASS
```

- Con cada divisor, la captura unica pasa por `HALF` (`STATUS = 0b01`) y por `DONE` (`0b10`), y se queda en `DONE` sin arrancar otro lote. La circular pasa dos veces por `HALF` y `DONE`.

**Driver, lectura por UART y grafico:** la demo del hito 6 hace `adc_read(muestras, 256)`, imprime `-- ADC data read --` y las 256 muestras por UART0, como el ejemplo de la consigna. La corri con tres divisores y grafique las muestras (`fw/tools/plot_adc.py` hace lo mismo para un log; para comparar las tres corridas use un script con el mismo parseo y la misma escala, `vref = 3.3`, `fullscale = 2^32 - 1`):

```bash
make -C fw TARGET=demo_tp5 EXTRA_CFLAGS=-DDEMO_ADC_CLK_DIV=4    # y 8, 16
make sim
python3 fw/tools/plot_adc.py
```

| `clk_div` | min | max | periodos en 256 muestras |
|---|---|---|---|
| 4 | 1 | 4294967295 | ~3 |
| 8 | 381496 | 4294924906 | ~6 |
| 16 | 169557 | 4294797739 | ~12 |

![Muestras del ADC con clk_div 4, 8 y 16](img/adc_clk_div.png)

- Las tres capturas devuelven 256 muestras que cubren casi toda la escala (`0..VREF`).
- Al duplicar `clk_div` se duplica el tiempo entre muestras, asi que la misma senoidal entra el doble de veces en las 256 muestras: unas 84 muestras por periodo con 4, 42 con 8 y 21 con 16. Eso confirma que `adc_init` fija el divisor y que `adc_read` lo usa sin cambiarlo.
- La fase inicial cambia entre corridas porque el modelo del ADC genera la senoidal con `$realtime` y la captura arranca en otro momento.

Encapsulamiento y regresion:

- `test_led`, `test_new_uart`, `test_dma_driver` y `test_dma` siguen dando PASS con `adc.c` en `sources.mk`.
- Fuera de `adc.c`, `REG_ADC_*` y `REG_ARRAY_ADC_BUFF` solo aparecen en `config.h` (las definiciones) y en `test_adc.c` y `test_drivers.c`.

## Hito 6 - Integracion en app de demo

### Paso a paso

1. Arme la demo en `fw/app/demo_tp5.c`, usando los cuatro drivers solo por su API publica:

   | Bloque | Que hace | LED |
   |---|---|---|
   | init | `led_init`, `uart_init()`, `dma_init`, banner por UART0, chequea que los LEDs arranquen apagados y `adc_init(4)` | bit 0 |
   | DMA | Copia 64 palabras a un destino con 4 palabras de guarda a cada lado, chequea `dma_is_done`, el destino y las guardas, y que un solape y un `dst` desalineado se rechacen sin tocar memoria | bit 1 |
   | ADC | `adc_start(ADC_MODE_SINGLE)`, `adc_half_done` (prende el bit 2), `adc_done`; despues `adc_read` de 256 muestras, chequea que la senal varie y que `min < max` | bits 2 y 3 |
   | envio | Copia las muestras con `dma_copy` a un buffer de envio, chequea que coincidan y las manda por UART0 despues de `-- ADC data read --` | bit 4 |

2. Sume un modulo chico, `fw_status.h` / `fw_status.c`, para los registros que lee el testbench (`REG_FW_STATUS` y `REG_FW_REPORT`), y lo agregue a `fw/sources.mk`.
3. Corri la demo completa, y despues una version que tiene que fallar (`clk_div = 0`) para comprobar que los errores se reportan.
4. Al traer los cambios de la catedra para el TP6, movi la demo de `fw/app/main.c` a `fw/app/demo_tp5.c`, como pide `tps/tp6.md`, y ahora se compila con `TARGET=demo_tp5`.

### Decisiones tecnicas

- **`fw_status` como un driver mas:** la simulacion solo termina con PASS si el FW deja `REG_FW_STATUS = 0xFF`. Como la demo no puede escribir registros, esos dos registros tienen su `.h` con la API y su `.c` con el acceso.
- **`demo_tp5.c` no incluye `includes.h` ni `config.h`:** solo los headers de los drivers, que no traen `config.h`. Un `REG_*` en la demo no compila, asi que la regla "sin accesos a registros en main" la chequea el compilador.
- **Sin `print_str`:** `print.c` escribe los registros de UART0 sin pasar por el driver. Los mensajes salen con `uart_write_str(...)` y los numeros los arma `cat_dec` en `demo_tp5.c`.
- **Una linea de UART por chequeo** (`<bloque>: <chequeo>  OK/FALLA`), armada en un buffer y mandada con un solo `uart_write_str`, para que no quede partida en el log.
- **LEDs como progreso:** un bit por bloque, el bit 2 entre `adc_half_done` y `adc_done`, y el bit 7 si falla algun chequeo. La demo sigue despues de un fallo para ver en un solo log que bloques andan; `REG_FW_REPORT` guarda un bit por bloque que fallo.
- **Las muestras pasan por el DMA antes de salir por UART:** es el bloque que integra los tres drivers (ADC -> DMA -> UART).
- **`DEMO_ADC_CLK_DIV` se elige al compilar** (`EXTRA_CFLAGS=-DDEMO_ADC_CLK_DIV=<n>`), para plotear con otros divisores y probar el camino de falla sin tocar el codigo.

### Errores encontrados

**"LEDs apagados" fallaba despues de otro fallo:** en la primera version el chequeo de los LEDs iba despues de `adc_init`. Al probar el camino de falla con `clk_div = 0`, el `FALLA` de `adc_init` prendia el bit 7 y el chequeo siguiente veia `0x80` en vez de `0`. Lo movi antes de cualquier otro chequeo.

**`main.c` ocupado por el TP6:** al mergear `upstream/master`, el TP6 trajo en `fw/app/main.c` el esqueleto del procesador de comandos. Movi la demo a `demo_tp5.c` y actualice los comandos del informe (`TARGET=demo_tp5`).

### Validacion

```bash
make -C fw TARGET=demo_tp5
make sim
```

```
UART: [BL] arrancó
UART: [BL] imagen del FW valida
UART: [BL] saltando al FW, reset_handler=0x00001018
UART: tp5-drivers-demo v1.0.0
UART: init: LEDs apagados  OK
UART: init: adc_init(clk_div = 4)  OK
LED: 0b00000001
UART: DMA: dma_copy 64 palabras  OK
UART: DMA: dma_is_done  OK
UART: DMA: destino igual al origen y guardas intactas  OK
UART: DMA: solape rechazado  OK
UART: DMA: dst desalineado rechazado  OK
LED: 0b00000011
UART: ADC: adc_start(ADC_MODE_SINGLE)  OK
UART: ADC: adc_half_done  OK
LED: 0b00000111
UART: ADC: adc_done  OK
UART: ADC: adc_read 256 muestras  OK
UART: ADC: la senal varia  OK
UART: ADC: min = 1, max = 4294967295
UART: ADC: min < max  OK
LED: 0b00001111
UART: DMA: muestras al buffer de envio  OK
UART: DMA: buffer de envio igual a las muestras  OK
UART: -- ADC data read --
UART: 378960861
UART: 475748585
...                          (256 muestras)
LED: 0b00011111
UART: -- demo PASS --
ending simulation, u_top.u_register_file.REGISTER_FW_STATUS = 000000ff
total clocks:              5073936
RESULT: PASS
```

- **UART:** cada bloque reporta su estado y la demo termina con `-- demo PASS --`.
- **LED:** avanzan de a un bit por bloque, en el orden de los mensajes: `0x01`, `0x03`, `0x07` (mitad del lote del ADC), `0x0F` y `0x1F`. El bit 7 queda apagado.
- **DMA:** la copia de prueba coincide, las guardas estan intactas y los rechazos no tocan memoria.
- **ADC:** `adc_half_done` vuelve antes que `adc_done` (el bit 2 se prende entre los dos mensajes). `min = 1` y `max = 4294967295` (`0xFFFFFFFF`): el lote cubre la escala completa. Las 256 muestras son las que se grafican en el hito 5.

Camino de falla, con un `adc_init` que tiene que fallar:

```bash
make -C fw TARGET=demo_tp5 EXTRA_CFLAGS=-DDEMO_ADC_CLK_DIV=0
make sim
```

```
UART: tp5-drivers-demo v1.0.0
UART: init: LEDs apagados  OK
UART: init: adc_init(clk_div = 0)  FALLA
LED: 0b10000000
UART: DMA: dma_copy 64 palabras  OK
UART: DMA: dma_is_done  OK
UART: DMA: destino igual al origen y guardas intactas  OK
UART: DMA: solape rechazado  OK
UART: DMA: dst desalineado rechazado  OK
LED: 0b10000010
UART: ADC: adc_start(ADC_MODE_SINGLE)  OK
UART: ADC: adc_half_done  OK
LED: 0b10000110
UART: ADC: adc_done  OK
UART: ADC: adc_read 256 muestras  OK
UART: ADC: la senal varia  OK
UART: ADC: min = 42390, max = 4294924906
UART: ADC: min < max  OK
LED: 0b10001110
UART: DMA: muestras al buffer de envio  OK
UART: DMA: buffer de envio igual a las muestras  OK
UART: -- ADC data read --
...                          (256 muestras)
LED: 0b10011110
UART: -- demo FAIL --
ending simulation, u_top.u_register_file.REGISTER_FW_STATUS = 00000bad
RESULT: FAIL
```

- `adc_init(0)` devuelve `ADC_ERR_PARAM`, se prende el bit 7 y el bit 0 queda apagado. Los demas bloques pasan (`adc_start` usa el divisor por defecto, 4) y la simulacion termina con `0xBAD`.

Encapsulamiento:

- `demo_tp5.c` no incluye `includes.h` ni `config.h`, solo `led.h`, `uart.h`, `dma.h`, `adc.h` y `fw_status.h`. Ninguno de esos headers trae `config.h`, asi que un `REG_*` en `demo_tp5.c` no compila.
- `test_led`, `test_new_uart`, `test_dma_driver`, `test_adc`, `test_dma` y `test_uart_serial` siguen compilando con `fw_status.c` en `sources.mk`.

## Hito 7 - Cierre y validacion final

### Paso a paso

1. Borre el simulador compilado (`obj_dir`) y los builds de los tests (`fw/build/test_*`), para compilar todo desde cero.
2. Corri `make test_drivers` (compila el simulador con Verilator, compila `fw/tests/test_drivers.c` con los cuatro drivers y simula).
3. Corri `make test_uart_serial`.
4. Volvi a correr los tests de cada hito y la demo con el simulador nuevo, para confirmar que nada se rompio con los cambios de la consigna.

### Decisiones tecnicas

- Use las reglas `make test_<nombre>` del `Makefile` actualizado en vez de `make fw` + `make sim`: compilan cada test en su propio directorio (`fw/build/<nombre>/`), no pisan `fw/fw.hex` y comparan el `RESULT` con el esperado.

### Errores encontrados

No hubo errores en el cierre. Los cambios que pidio la actualizacion de la consigna (interfaz de UART0, `adc_mode`, `adc_read` con `data` nulo) ya estan resueltos en los hitos 3.a y 5.

### Validacion

```bash
rm -rf obj_dir fw/build/test_drivers fw/build/test_uart_serial
make test_drivers
make test_uart_serial
```

```
verilator: compilando el simulador (log en verilator.log)
[ OK ] test_drivers               PASS     clocks=6961547
verilator: compilando el simulador (log en verilator.log)
[ OK ] test_uart_serial           PASS     clocks=530612
```

Consola de `test_drivers` (`fw/build/test_drivers.sim.log`, resumida):

```
UART: [BL] arrancó
UART: [BL] imagen del FW valida
UART: [BL] saltando al FW, reset_handler=0x00001018
LED: 0b00000001
LED: 0b00000011
...                          (70 cambios de LED: on/off/toggle/write/set_mask)
LED: 0b00000000
UART: A
UART: z
...                          (bytes y strings por uart_write_byte/uart_write_str)
UART: -- ADC data read --
...                          (256 muestras)
ending simulation, u_top.u_register_file.REGISTER_FW_STATUS = 000000ff
total clocks:              6961547
RESULT: PASS
```

Tests de cada hito y demo, con el simulador compilado desde cero (`fw/tools/run_test.sh`, que es lo que usan las reglas `make test_<nombre>`):

```
[ OK ] test_led                   PASS     clocks=753249
[ OK ] test_new_uart              PASS     clocks=704450
[ OK ] test_dma_driver            PASS     clocks=1320807
[ OK ] test_dma                   PASS     clocks=1245135
[ OK ] test_adc                   PASS     clocks=796526
[ OK ] demo_tp5                   PASS     clocks=5073936
[ OK ] demo_tp5_div0              FAIL     clocks=5094143    (falla esperada, clk_div = 0)
```

Checklist final:

- [x] Compila desde cero.
- [x] `make test_drivers` termina en `[ OK ] PASS`.
- [x] `make test_uart_serial` termina en `[ OK ] PASS` (`CHECK PASS (14/14)`).
- [x] Ningun driver accede a registros de otro, y la demo no accede a registros.

## Resumen de errores encontrados

| Hito | Error | Solucion |
|---|---|---|
| 2 | `multiple definition` por `const uint8_t leds_num` en `led.h` | `#define LED_COUNT 8u` |
| 3.a | Interfaz con `uart_id_t`, distinta de la requerida | Saque el parametro |
| 3.b | No existia `make test_uart_serial` | Simulacion a mano con `+UART1_SCRIPT`; despues la catedra agrego la regla |
| 3.b | Eco corrido un bit con `gap 0` (start perdido en el testbench) | `gap 1` en el patron |
| 4 | `dma_init` esperaba `DONE` y se colgaba | `dma_init` solo baja `START` |
| 5 | `adc_read` sin `adc_init` no termina con `CLK_DIVIDER = 0` | Divisor por defecto 4 si el registro esta en 0 |
| 5 | Consigna actualizada: `adc_mode` y `adc_read(NULL)` | `ADC_MODE_CIRCULAR = 3`, `adc_read(NULL)` devuelve 0 |
| 6 | Chequeo de LEDs afectado por un fallo anterior | Lo movi al principio |
| 6 | `main.c` pasa a ser del TP6 | Demo movida a `demo_tp5.c` |
