#ifndef LED_H
#define LED_H

#include <stdint.h>

#define LED_COUNT 8u

void led_init(void);

void led_on(uint8_t idx);

void led_off(uint8_t idx);

void led_toggle(uint8_t idx);

void led_write(uint8_t value);

void led_set_mask(uint32_t mask);

uint32_t led_get_mask(void);

uint8_t led_get_status(uint8_t idx);

#endif
