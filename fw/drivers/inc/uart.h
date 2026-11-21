#ifndef UART_H
#define UART_H

#include <stdint.h>

/* Driver de UART0. Interfaz requerida por tps/tp5/tp5.md (3.a): uart_write_byte y
 * uart_write_str, las dos bloqueantes (al volver, la transmision termino).
 * El resto (init y RX) es extra. */

void uart_init(void);

void uart_write_byte(char c);

void uart_write_str(const char *s);

uint8_t uart_rx_available(void);

uint32_t uart_rx_count(void);

uint32_t uart_read(char *buf, uint32_t max);

void uart_rx_flush(void);

#endif
