#ifndef FW_STATUS_H
#define FW_STATUS_H

#include <stdint.h>

/* Registros de estado que lee el testbench (REG_FW_STATUS y REG_FW_REPORT).
 * No son un periferico, pero con este modulo la app tampoco los escribe directamente. */

#define FW_STATUS_PASS  0xFFu    /* el testbench termina la simulacion con PASS */
#define FW_STATUS_FAIL  0xBADu   /* el testbench termina la simulacion con FAIL */

void fw_status_clear(void);              /* STATUS = 0 y REPORT = 0 */

void fw_status_report(uint32_t value);   /* REPORT = value (dato libre para el testbench) */

void fw_status_end(int ok);              /* STATUS = PASS si ok, FAIL si no */

#endif
