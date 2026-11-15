/* Driver de la UART1 serie (8N1, FIFOs RX/TX de UART1_FIFO_DEPTH bytes).
 *
 * Registros (config.h, base 0x4_3000):
 *   BAUD_DIV  RW  clocks por bit
 *   CTRL      RW  bit0 RTS, bit1 CLR_ERR (escribir 1 limpia OVERRUN y FRAME_ERR)
 *   TX_DATA   WO  escribir mete el byte en el FIFO TX (si esta lleno el byte se pierde)
 *   STATUS    RO  flags, RX_LEVEL [15:8], TX_LEVEL [23:16]
 *   RX_DATA   RO  [8] VALID, [7:0] dato. Leerlo saca un byte del FIFO RX
 *
 * Solo este archivo toca los REG_UART1_*.
 * TP6: completar uart1_set_rts().
 */
#include "uart1.h"

void uart1_init(uint32_t baud_div)
{
    REG_UART1_BAUD_DIV = baud_div;
    uart1_clear_errors();
}

uint32_t uart1_rx_level(void)
{
    return UART1_ST_RX_LEVEL(REG_UART1_STATUS);
}

int uart1_getc(uint8_t *b)
{
    /* Una sola lectura: el dato y VALID salen de la misma palabra. Si el FIFO
     * esta vacio la lectura no saca nada (VALID = 0). */
    uint32_t d = REG_UART1_RX_DATA;

    if (!(d & UART1_RX_VALID))
        return 0;
    *b = (uint8_t)(d & 0xFFu);
    return 1;
}

void uart1_putc(uint8_t b)
{
    /* El hardware descarta lo que se escribe con el FIFO lleno */
    while (REG_UART1_STATUS & UART1_ST_TX_FULL)
        ;
    REG_UART1_TX_DATA = b;
}

void uart1_write(const uint8_t *buf, uint32_t n)
{
    for (uint32_t i = 0; i < n; i++)
        uart1_putc(buf[i]);
}

int uart1_tx_idle(void)
{
    return (REG_UART1_STATUS & UART1_ST_TX_IDLE) ? 1 : 0;
}

uint32_t uart1_errors(void)
{
    uint32_t st  = REG_UART1_STATUS;
    uint32_t err = 0;

    if (st & UART1_ST_FRAME_ERR) err |= UART1_ERR_FRAME;
    if (st & UART1_ST_OVERRUN)   err |= UART1_ERR_OVERRUN;
    return err;
}

void uart1_clear_errors(void)
{
    /* Escribir CTRL pisa RTS: se relee CTRL y se escribe el mismo RTS junto con CLR_ERR.
     * CLR_ERR actua solo en la escritura, no queda activo. */
    uint32_t rts = REG_UART1_CTRL & UART1_CTRL_RTS;

    REG_UART1_CTRL = rts | UART1_CTRL_CLR_ERR;
}

/* ---- TP6 ---- */

void uart1_set_rts(int ready)
{
    /* TODO TP6 */
    (void)ready;
}
