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
UART: abcdefghijklmnopqrstuvwxyz ... qrstuv          (256 caracteres)
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

