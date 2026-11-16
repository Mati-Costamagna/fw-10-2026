/* Hito 4: prueba del driver DMA usando solo su API (dma.h). make test_dma_driver */
#include "includes.h"
#include "dma.h"

#define N      64
#define GUARD  4
#define MARCA  0xA5A5A5A5u

static uint32_t A[N];
static uint32_t B[N + 2 * GUARD];   /* destino con palabras de guarda a cada lado */
static int fallas = 0;

static void check(const char *nombre, int ok)
{
    print_str(nombre);
    print_str(ok ? "  OK" : "  FALLA");
    if (!ok)
        fallas++;
}

static void preparar(uint32_t semilla)
{
    for (int i = 0; i < N; i++)
        A[i] = semilla + 0x01010101u * (uint32_t)i;
    for (int i = 0; i < N + 2 * GUARD; i++)
        B[i] = MARCA;
}

/* B[GUARD .. GUARD+n) == A[0..n) y el resto de B intacto */
static int destino_ok(uint32_t n)
{
    for (uint32_t i = 0; i < N + 2 * GUARD; i++) {
        uint32_t esperado = (i >= GUARD && i < GUARD + n) ? A[i - GUARD] : MARCA;
        if (B[i] != esperado)
            return 0;
    }
    return 1;
}

static int intacto(void)
{
    return destino_ok(0);
}

int main(void)
{
    REG_FW_STATUS = 0;
    dma_init();

    /* copias validas */
    preparar(0x11000000u);
    check("copia 64 palabras", dma_copy(A, &B[GUARD], N) == DMA_OK && destino_ok(N));
    check("dma_is_done", dma_is_done() == 1);

    preparar(0x22000000u);
    check("segunda copia (flanco START)", dma_copy(A, &B[GUARD], 7) == DMA_OK && destino_ok(7));

    preparar(0x33000000u);
    check("1 palabra", dma_copy(A, &B[GUARD], 1) == DMA_OK && destino_ok(1));

    preparar(0x44000000u);
    check("n_words = 0", dma_copy(A, &B[GUARD], 0) == DMA_OK && intacto());

    /* desde memoria de instrucciones (codigo del FW) */
    {
        const uint32_t *codigo = (const uint32_t *)0x00001000u;
        int ok = dma_copy(codigo, &B[GUARD], 16) == DMA_OK;
        for (int i = 0; i < 16; i++)
            ok &= (B[GUARD + i] == codigo[i]);
        check("desde mem. de instrucciones", ok);
    }

    /* direcciones invalidas: no tienen que arrancar el DMA ni tocar el destino */
    preparar(0x55000000u);
    check("src NULL",            dma_copy(0, &B[GUARD], 4) == DMA_ERR_ADDR && intacto());
    check("dst NULL",            dma_copy(A, 0, 4) == DMA_ERR_ADDR);
    check("src desalineado",     dma_copy((const uint8_t *)A + 1, &B[GUARD], 4) == DMA_ERR_ADDR && intacto());
    check("dst desalineado",     dma_copy(A, (uint8_t *)&B[GUARD] + 2, 4) == DMA_ERR_ADDR && intacto());
    check("dst fuera del mapa",  dma_copy(A, (void *)0x00060000u, 4) == DMA_ERR_ADDR);
    check("src fuera del mapa",  dma_copy((const void *)0x80000000u, &B[GUARD], 4) == DMA_ERR_ADDR && intacto());
    check("cruza fin de RAM",    dma_copy(A, (void *)(ADDR_START_DATA + ADDR_SIZE_DATA - 8), 4) == DMA_ERR_ADDR);
    check("n_words enorme",      dma_copy(A, &B[GUARD], 0x40000001u) == DMA_ERR_ADDR && intacto());

    /* solapamiento */
    preparar(0x66000000u);
    check("solape dst > src",    dma_copy(&A[0], &A[4], 16) == DMA_ERR_OVERLAP && A[4] == 0x66000000u + 0x04040404u);
    check("solape dst < src",    dma_copy(&A[4], &A[0], 16) == DMA_ERR_OVERLAP && A[0] == 0x66000000u);
    check("mismo buffer",        dma_copy(A, A, 8) == DMA_ERR_OVERLAP);
    check("contiguos sin solape", dma_copy(&A[0], &A[16], 16) == DMA_OK && A[16] == A[0] && A[31] == A[15]);

    /* despues de los errores el DMA sigue funcionando */
    preparar(0x77000000u);
    check("copia despues de errores", dma_copy(A, &B[GUARD], N) == DMA_OK && destino_ok(N));

    print_str(fallas ? "-- test DMA driver FAIL --" : "-- test DMA driver PASS --");
    REG_FW_STATUS = fallas ? 0xBAD : 0xFF;
    return 0;
}
