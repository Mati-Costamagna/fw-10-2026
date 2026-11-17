#ifndef ADC_H
#define ADC_H

#include <stdint.h>

#define ADC_MODE_SINGLE    1u   /* un lote de ADC_N_SAMPLES muestras y para */
#define ADC_MODE_CIRCULAR  2u   /* lotes seguidos, hasta adc_stop() */

#define ADC_N_SAMPLES      256u

/* Codigos de retorno */
#define ADC_OK          0
#define ADC_ERR_PARAM  (-1)   /* clk_div = 0, modo desconocido, data NULL o size = 0 */
#define ADC_ERR_BUSY   (-2)   /* hay una captura en curso */

int adc_init(uint32_t clk_div);

int adc_start(uint8_t adc_mode);

int adc_half_done(void);

int adc_done(void);

int adc_read(uint32_t *data, uint32_t size);

#endif
