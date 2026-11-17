#include <stdint.h>
#include "includes.h"
#include "adc.h"

#define ADC_START_BIT  (1u << 0)   /* REG_ADC_START[0]: arranca con el flanco 0->1 */
#define ADC_CIRC_BIT   (1u << 1)   /* REG_ADC_START[1]: modo circular (por nivel) */
#define ADC_ST_HALF    (1u << 0)   /* REG_ADC_STATUS[0]: half_done */
#define ADC_ST_DONE    (1u << 1)   /* REG_ADC_STATUS[1]: acq_done */
#define ADC_CLK_DIV_DEFAULT 4u

static uint8_t modo;   /* modo de la ultima captura arrancada; 0 = ninguna */

static int ocupado(void)
{
    if (modo == ADC_MODE_CIRCULAR)
        return 1;
    if (modo == ADC_MODE_SINGLE)
        return !(REG_ADC_STATUS & ADC_ST_DONE);
    return 0;
}

int adc_init(uint32_t clk_div)
{
    if (!clk_div)
        return ADC_ERR_PARAM;
    if (ocupado())
        return ADC_ERR_BUSY;
    REG_ADC_START = 0;
    REG_ADC_CLK_DIVIDER = clk_div;
    return ADC_OK;
}

int adc_start(uint8_t adc_mode)
{
    uint32_t start;

    if (adc_mode == ADC_MODE_SINGLE)        start = ADC_START_BIT;
    else if (adc_mode == ADC_MODE_CIRCULAR) start = ADC_START_BIT | ADC_CIRC_BIT;
    else return ADC_ERR_PARAM;

    if (ocupado())
        return ADC_ERR_BUSY;

    if (REG_ADC_CLK_DIVIDER == 0)
        REG_ADC_CLK_DIVIDER = ADC_CLK_DIV_DEFAULT;

    REG_ADC_START = 0;
    REG_ADC_START = start;

    /* DONE del lote anterior baja recien cuando el ADC pasa a ST_CAPT, dos ciclos despues */
    while (REG_ADC_STATUS & ADC_ST_DONE)
        ;
    modo = adc_mode;
    return ADC_OK;
}

int adc_half_done(void)
{
    uint32_t mask = ADC_ST_HALF;
    uint32_t st;

    if (!modo)
        return 0;
    if (modo == ADC_MODE_SINGLE)
        mask |= ADC_ST_DONE;    /* en modo unico HALF vuelve a 0 cuando termina el lote */
    while (!((st = REG_ADC_STATUS) & mask))
        ;
    if (!(st & ADC_ST_DONE)) {
        /* HALF sube con 127 muestras escritas; la 127 llega en el tick siguiente, hasta
         * clk_div ciclos despues. Cada vuelta de este loop tarda mas de un ciclo. */
        uint32_t n = REG_ADC_CLK_DIVIDER;
        for (volatile uint32_t i = 0; i < n; i++)
            ;
    }
    return 1;
}

int adc_done(void)
{
    if (!modo)
        return 0;
    while (!(REG_ADC_STATUS & ADC_ST_DONE))
        ;
    return 1;
}

int adc_read(uint32_t *data, uint32_t size)
{
    int r;

    if (!data || !size)
        return ADC_ERR_PARAM;
    if (size > ADC_N_SAMPLES)
        size = ADC_N_SAMPLES;

    r = adc_start(ADC_MODE_SINGLE);
    if (r != ADC_OK)
        return r;
    adc_done();

    for (uint32_t i = 0; i < size; i++)
        data[i] = REG_ARRAY_ADC_BUFF[i];
    return (int)size;
}
