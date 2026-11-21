#ifndef ADC_H
#define ADC_H

#include <stdint.h>

/* adc_mode es el valor que se escribe en REG_ADC_START: bit 0 = inicio, bit 1 = circular */
#define ADC_MODE_SINGLE    1u   /* un lote de ADC_N_SAMPLES muestras y para */
#define ADC_MODE_CIRCULAR  3u   /* lotes seguidos, sin forma de pararlo (hasta un reset) */

#define ADC_N_SAMPLES      256u

/* Codigos de retorno */
#define ADC_OK          0
#define ADC_ERR_PARAM  (-1)   /* clk_div = 0 o modo desconocido */
#define ADC_ERR_BUSY   (-2)   /* hay una captura en curso */

int adc_init(uint32_t clk_div);

int adc_start(uint8_t adc_mode);

int adc_half_done(void);

int adc_done(void);

/* Captura unica completa: devuelve cuantas muestras copio (como maximo ADC_N_SAMPLES),
 * 0 si data es NULL o size = 0, o ADC_ERR_BUSY si el circular esta andando. */
int adc_read(uint32_t *data, uint32_t size);

#endif
