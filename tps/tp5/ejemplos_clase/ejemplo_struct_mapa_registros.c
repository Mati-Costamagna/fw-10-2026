#include <stdint.h>
#include <stddef.h>

/*
 * Ejemplo Structs como mapa de registros​:
 *  - BUTTON0: estado actual del boton + evento de flanco
 */

/* ---------------------------- Direcciones base ---------------------------- */
#define BUTTON0_BASE 0x40002000u

/*
 * Version MACROS
 *
 * #define BUTTON0_STATE    (*(volatile uint32_t *)(BUTTON0_BASE + 0x00u))
 * #define BUTTON0_EVENT    (*(volatile uint32_t *)(BUTTON0_BASE + 0x04u))
 *
 * Mismo hardware, distinta forma de mapear.
 */

/* ------------------------ Mapa de registros: BUTTON ----------------------- */
typedef struct {
    volatile uint32_t STATE;     /* 0x00: bit0 = estado actual */
    volatile uint32_t EVENT;     /* 0x04: bit0 = flanco detectado (W1C) */
} button_regs_t;

/* Puntero al bloque de registros del periferico. */
#define BUTTON0 ((button_regs_t *)BUTTON0_BASE)

/* ------------------------------ Bits de control --------------------------- */
enum {
    BUTTON_ST_PRESSED   = 1u << 0,
    BUTTON_EV_EDGE      = 1u << 0
};

/* ----------------------- Uso directo de un periferico ---------------------- */
void demo_boton_directo(void)
{
    uint32_t samples_pressed = 0u; // Va a contar cuantas veces el software leyó el botón en estado presionado.
    uint32_t edge_count = 0u; // Va a contar cuantas veces se detectó un flanco en el botón.

    for (;;) {
        if ((BUTTON0->STATE & BUTTON_ST_PRESSED) != 0u) {
            samples_pressed++;
        }

        if ((BUTTON0->EVENT & BUTTON_EV_EDGE) != 0u) {
            edge_count++;
        }
    }
}

/*
 * Implementacion equivalente usando MACROS
 *
 * void demo_boton_directo_macros(void)
 * {
 *     uint32_t samples_pressed = 0u;
 *     uint32_t edge_count = 0u;
 *
 *     for (;;) {
 *         if ((BUTTON0_STATE & BUTTON_ST_PRESSED) != 0u) {
 *             samples_pressed++;
 *         }
 *
 *         if ((BUTTON0_EVENT & BUTTON_EV_EDGE) != 0u) {
 *             edge_count++;
 *             BUTTON0_EVENT = BUTTON_EV_EDGE;
 *         }
 *     }
 * }
 */
