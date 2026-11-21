
#include "includes.h"
#include "uart.h"

static int fallas = 0;

void delay(int loops){
    for(int i=0; i<loops; i++){
        REG_AUX_0 ++;
        REG_AUX_0 --;
    }
}

static void check(const char *nombre, int ok){
    uart_write_str(nombre);
    uart_write_str(ok ? "  OK" : "  FALLA");
    if (!ok) fallas++;
}

static int iguales(const char *a, const char *b){
    while (*a && *a == *b) { a++; b++; }
    return *a == *b;
}

int main(void){
    static char largo[301];
    char rx[REG_ARRAY_UART0_BUFF_IN_SIZE + 1];
    uint32_t n, i;

    REG_FW_STATUS = 0x0 ;
    REG_FW_REPORT = 0x0 ;

    uart_init();

    // TX: un string y bytes sueltos (cada uart_write_byte es una linea UART: del testbench)
    uart_write_str("hello Luigi!");
    uart_write_byte('O');
    uart_write_byte('K');

    // 300 caracteres: tienen que salir en dos transmisiones (256 + 44)
    for (i = 0; i < 300; i++)
        largo[i] = (char)('a' + i % 26);
    largo[300] = 0;
    uart_write_str(largo);

    // RX: el testbench manda "HOLA!" cuando REG_AUX_0 = 0x5ED5ED
    check("rx vacio despues de init", uart_rx_count() == 0 && !uart_rx_available());

    REG_AUX_0 = 0x5ED5ED ; // to start testbench transmision
    REG_AUX_0 = 0x0      ; // to start testbench transmision

    while (!uart_rx_available()){}
    delay(4);

    n = uart_read(rx, REG_ARRAY_UART0_BUFF_IN_SIZE);
    rx[n] = 0;
    uart_write_str(rx);      // eco de lo recibido
    check("rx = HOLA!", n == 5 && uart_rx_count() == 5 && iguales(rx, "HOLA!"));

    check("read con max = 2", uart_read(rx, 2) == 2 && rx[0] == 'H' && rx[1] == 'O');

    uart_rx_flush();
    check("flush", uart_rx_count() == 0 && !uart_rx_available());

    uart_write_str(fallas ? "-- test UART FAIL --" : "-- test UART PASS --");
    REG_FW_STATUS = fallas ? 0xBAD : 0xFF;
    return 0;
}
