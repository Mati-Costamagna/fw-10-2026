#include "includes.h"
#include "led.h"

static int fallas = 0;

static void check(const char *nombre, uint32_t esperado)
{
    uint32_t leido = led_get_mask();
    print_str(nombre);
    if (leido != esperado) {
        print_str("  FALLA, esperado/leido:");
        print_hex(esperado, 2);
        print_hex(leido, 2);
        fallas++;
    } else {
        print_str("  OK");
    }
}

int main(void)
{
    REG_FW_STATUS = 0;

    led_init();                 check("init",          0x00);
    led_on(0);                  check("on 0",          0x01);
    led_on(3); led_on(7);       check("on 3 y 7",      0x89);
    led_off(0);                 check("off 0",         0x88);
    led_toggle(3);              check("toggle 3",      0x80);
    led_toggle(3);              check("toggle 3 otra", 0x88);
    led_set_mask(0x1A5);        check("set_mask 0x1A5",0xA5);
    led_write(0x0F);            check("write 0x0F",    0x0F);

    led_on(8); led_off(9); led_toggle(255);
                                check("idx invalidos", 0x0F);

    if (led_get_status(0) != 1 || led_get_status(4) != 0 || led_get_status(8) != 0) {
        print_str("get_status FALLA");
        fallas++;
    }

    print_str(fallas ? "-- test LED FAIL --" : "-- test LED PASS --");
    REG_FW_STATUS = fallas ? 0xBAD : 0xFF;   /* 0xFF termina la simulación con PASS */
    return 0;
}