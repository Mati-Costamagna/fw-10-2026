#include "includes.h"
#include "uart.h"

static void uart0_send(uint32_t n)
{
    REG_UART0_SIZE_TO_TRANSMIT = n;
    REG_UART0_START_TRANSMIT   = 1;
    REG_UART0_START_TRANSMIT   = 0;
    while (!REG_UART0_TRANSMISION_DONE);
}

void uart_init(uart_id_t uart){
    if (uart != UART0) return;
    REG_UART0_START_TRANSMIT = 0;
    while (!REG_UART0_TRANSMISION_DONE);
    uart_rx_flush(uart);
}

void uart_write_byte(uart_id_t uart, char c){
    if (uart != UART0) return;
    while (!REG_UART0_TRANSMISION_DONE); 
    REG_ARRAY_UART0_BUFF_OUT[0] = (unsigned char)c;   /* sin el cast, 0xE9 quedaria 0xFFFFFFE9 */
    uart0_send(1);
}

void uart_write_str(uart_id_t uart, const char *s){
    uint32_t n;
    if (uart != UART0 || s == 0) return;
    while (*s) {
        while (!REG_UART0_TRANSMISION_DONE);
        for (n = 0; s[n] != 0 && n < REG_ARRAY_UART0_BUFF_OUT_SIZE; n++)
            REG_ARRAY_UART0_BUFF_OUT[n] = (unsigned char)s[n];
        uart0_send(n);
        s += n;
    }
}

uint8_t uart_rx_available(uart_id_t uart){
    if (uart != UART0) return 0;
    return REG_UART0_DATA_AVAILABLE != 0;
}

uint32_t uart_rx_count(uart_id_t uart){
    if (uart != UART0) return 0;
    return REG_UART0_INDEX_IN;
}

uint32_t uart_read(uart_id_t uart, char *buf, uint32_t max){
    uint32_t i, n;
    if (uart != UART0 || buf == 0) return 0;
    n = REG_UART0_INDEX_IN;
    if (n > REG_ARRAY_UART0_BUFF_IN_SIZE) n = REG_ARRAY_UART0_BUFF_IN_SIZE;
    if (n > max) n = max;
    for (i = 0; i < n; i++)
        buf[i] = (char)REG_ARRAY_UART0_BUFF_IN[i];
    return n;
}

void uart_rx_flush(uart_id_t uart){
    if (uart != UART0) return;
    REG_UART0_DATA_FLUSH = 1;
    REG_UART0_DATA_FLUSH = 0;
}
