/* Hito 6: app de demo que integra los drivers de LED, UART0, DMA y ADC.
 *
 * Usa solo la API publica de los drivers. No incluye includes.h/config.h, asi que un
 * REG_* en este archivo no compila.
 *
 * Bloques:
 *   1. init   inicializa los cuatro drivers y manda el banner por UART0
 *   2. DMA    copia un bloque de prueba, valida destino y guardas, y prueba los rechazos
 *   3. ADC    captura con adc_start/adc_half_done/adc_done y lee un lote con adc_read
 *   4. envio  copia las muestras con DMA a un buffer de envio y las manda por UART0
 *
 * LEDs (progreso):
 *   bit 0  drivers inicializados        bit 3  lectura del ADC validada
 *   bit 1  copia DMA validada           bit 4  muestras enviadas por UART0
 *   bit 2  ADC: mitad del lote          bit 7  fallo algun chequeo
 *
 * Al final: REG_FW_STATUS = 0xFF (PASS) o 0xBAD (FAIL) via fw_status, y REG_FW_REPORT con
 * un bit por bloque que fallo (bit 0 init, 1 DMA, 2 ADC, 3 envio).
 *
 * El divisor del ADC se puede cambiar al compilar:
 *   make -C fw EXTRA_CFLAGS=-DDEMO_ADC_CLK_DIV=16
 */
#include <stdint.h>
#include "led.h"
#include "uart.h"
#include "dma.h"
#include "adc.h"
#include "fw_status.h"

#ifndef DEMO_ADC_CLK_DIV
#define DEMO_ADC_CLK_DIV 4u
#endif

#define LED_INIT      0
#define LED_DMA       1
#define LED_ADC_HALF  2
#define LED_ADC       3
#define LED_ENVIO     4
#define LED_ERROR     7

#define DMA_N      64
#define GUARD      4
#define MARCA      0xA5A5A5A5u

static const char PROGRAM_NAME[]    = "tp5-drivers-demo";
static const char PROGRAM_VERSION[] = "1.0.0";

static uint32_t dma_src[DMA_N];
static uint32_t dma_dst[DMA_N + 2 * GUARD];   /* destino con palabras de guarda a cada lado */
static uint32_t muestras[ADC_N_SAMPLES];
static uint32_t envio[ADC_N_SAMPLES];

static uint32_t fallas;   /* un bit por bloque que fallo */

/* ---------------- Mensajes por UART0 ---------------- */

static char *cat(char *p, const char *s)
{
    while (*s)
        *p++ = *s++;
    *p = 0;
    return p;
}

static char *cat_dec(char *p, uint32_t v)
{
    char t[10];
    int n = 0;

    do {
        t[n++] = (char)('0' + v % 10u);
        v /= 10u;
    } while (v);
    while (n)
        *p++ = t[--n];
    *p = 0;
    return p;
}

static void say(const char *s)
{
    uart_write_str(s);
}

/* "<bloque>: <nombre>  OK" o "...  FALLA" en una sola transmision.
 * Si falla, marca el bloque en fallas y prende el LED de error. */
static int check(uint32_t bloque, const char *nombre, int ok)
{
    char m[64];
    char *p = cat(m, nombre);

    cat(p, ok ? "  OK" : "  FALLA");
    say(m);
    if (!ok) {
        fallas |= 1u << bloque;
        led_on(LED_ERROR);
    }
    return ok;
}

/* ---------------- Bloques ---------------- */

static int bloque_init(void)
{
    char m[64];
    char *p;
    int ok;

    led_init();
    uart_init();
    dma_init();

    p = cat(m, PROGRAM_NAME);
    p = cat(p, " v");
    cat(p, PROGRAM_VERSION);
    say(m);

    /* antes que cualquier check: un FALLA prende el LED de error */
    ok = check(0, "init: LEDs apagados", led_get_mask() == 0);

    p = cat(m, "init: adc_init(clk_div = ");
    p = cat_dec(p, DEMO_ADC_CLK_DIV);
    cat(p, ")");
    ok &= check(0, m, adc_init(DEMO_ADC_CLK_DIV) == ADC_OK);

    if (ok)
        led_on(LED_INIT);
    return ok;
}

static int bloque_dma(void)
{
    uint32_t i;
    int ok, cmp = 1;

    for (i = 0; i < DMA_N; i++)
        dma_src[i] = 0xC0DE0000u ^ (i * 0x01010101u);
    for (i = 0; i < DMA_N + 2 * GUARD; i++)
        dma_dst[i] = MARCA;

    ok = check(1, "DMA: dma_copy 64 palabras", dma_copy(dma_src, &dma_dst[GUARD], DMA_N) == DMA_OK);
    ok &= check(1, "DMA: dma_is_done", dma_is_done() == 1);

    for (i = 0; i < DMA_N + 2 * GUARD; i++) {
        uint32_t esperado = (i >= GUARD && i < GUARD + DMA_N) ? dma_src[i - GUARD] : MARCA;
        cmp &= (dma_dst[i] == esperado);
    }
    ok &= check(1, "DMA: destino igual al origen y guardas intactas", cmp);

    /* rechazos: no tienen que arrancar el DMA ni tocar memoria */
    ok &= check(1, "DMA: solape rechazado",
                dma_copy(&dma_src[0], &dma_src[4], 16) == DMA_ERR_OVERLAP &&
                dma_src[4] == (0xC0DE0000u ^ 0x04040404u));
    ok &= check(1, "DMA: dst desalineado rechazado",
                dma_copy(dma_src, (uint8_t *)&dma_dst[GUARD] + 2, 4) == DMA_ERR_ADDR &&
                dma_dst[GUARD] == dma_src[0]);

    if (ok)
        led_on(LED_DMA);
    return ok;
}

/* 1 si las muestras cambian (al menos 64 diferencias entre consecutivas), como una senoidal */
static int muestras_varian(const uint32_t *s, uint32_t n)
{
    uint32_t i, d = 0;

    for (i = 1; i < n; i++)
        d += (s[i] != s[i - 1]);
    return d >= 64;
}

static int bloque_adc(void)
{
    char m[64];
    char *p;
    uint32_t i, min, max;
    int ok, n;

    /* captura unica mirando el progreso */
    ok = check(2, "ADC: adc_start(ADC_MODE_SINGLE)", adc_start(ADC_MODE_SINGLE) == ADC_OK);
    if (ok) {
        ok &= check(2, "ADC: adc_half_done", adc_half_done() == 1);
        led_on(LED_ADC_HALF);
        ok &= check(2, "ADC: adc_done", adc_done() == 1);
    }

    /* lectura de un lote completo */
    n = adc_read(muestras, ADC_N_SAMPLES);
    ok &= check(2, "ADC: adc_read 256 muestras", n == (int)ADC_N_SAMPLES);
    ok &= check(2, "ADC: la senal varia", muestras_varian(muestras, ADC_N_SAMPLES));

    min = max = muestras[0];
    for (i = 1; i < ADC_N_SAMPLES; i++) {
        if (muestras[i] < min) min = muestras[i];
        if (muestras[i] > max) max = muestras[i];
    }
    p = cat(m, "ADC: min = ");
    p = cat_dec(p, min);
    p = cat(p, ", max = ");
    cat_dec(p, max);
    say(m);
    ok &= check(2, "ADC: min < max", min < max);

    if (ok)
        led_on(LED_ADC);
    return ok;
}

static int bloque_envio(void)
{
    char m[12];
    uint32_t i;
    int ok, cmp = 1;

    for (i = 0; i < ADC_N_SAMPLES; i++)
        envio[i] = 0;
    ok = check(3, "DMA: muestras al buffer de envio", dma_copy(muestras, envio, ADC_N_SAMPLES) == DMA_OK);
    for (i = 0; i < ADC_N_SAMPLES; i++)
        cmp &= (envio[i] == muestras[i]);
    ok &= check(3, "DMA: buffer de envio igual a las muestras", cmp);

    /* mismo formato que test_drivers: lo lee fw/tools/plot_adc.py */
    say("-- ADC data read --");
    for (i = 0; i < ADC_N_SAMPLES; i++) {
        cat_dec(m, envio[i]);
        say(m);
    }

    if (ok)
        led_on(LED_ENVIO);
    return ok;
}

int main(void)
{
    int ok;

    fw_status_clear();
    fallas = 0;

    ok  = bloque_init();
    ok &= bloque_dma();
    ok &= bloque_adc();
    ok &= bloque_envio();

    fw_status_report(fallas);
    say(ok ? "-- demo PASS --" : "-- demo FAIL --");
    fw_status_end(ok);
    return 0;
}
