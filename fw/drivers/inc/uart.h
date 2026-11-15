#ifndef UART_H
#define UART_H

#include <stdint.h>

typedef enum {
    UART0 = 0,
} uart_id_t;

void uart_init(uart_id_t uart);

void uart_write_byte(uart_id_t uart, char c);

void uart_write_str(uart_id_t uart, const char *s);

uint8_t uart_rx_available(uart_id_t uart);

uint32_t uart_rx_count(uart_id_t uart);

uint32_t uart_read(uart_id_t uart, char *buf, uint32_t max);

void uart_rx_flush(uart_id_t uart);

#endif
