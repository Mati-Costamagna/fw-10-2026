#include "includes.h"
#include "dma.h"

/* 1 si [addr, addr + 4*n_words) entra completo en [base, base + size). Sin multiplicar n_words,
 * para que no haya overflow. */
static int en_region(uint32_t addr, uint32_t n_words, uint32_t base, uint32_t size)
{
    uint32_t off = addr - base;
    return addr >= base && off < size && n_words <= (size - off) / 4u;
}

static int rango_valido(uint32_t addr, uint32_t n_words)
{
    if (addr == 0 || (addr & 3u))
        return 0;
    return en_region(addr, n_words, ADDR_START_INST,     ADDR_SIZE_INST)
        || en_region(addr, n_words, ADDR_START_DATA,     ADDR_SIZE_DATA)
        || en_region(addr, n_words, ADDR_START_REG_FILE, ADDR_SIZE_REG_FILE);
}

void dma_init(void){
    REG_DMA_START = 0;
}

int dma_copy(const void *src, void *dst, uint32_t n_words) {
    uint32_t s = (uint32_t)src;
    uint32_t d = (uint32_t)dst;
    uint32_t bytes;

    if (n_words == 0) return DMA_OK;
    if (!rango_valido(s, n_words) || !rango_valido(d, n_words)) return DMA_ERR_ADDR;
    bytes = n_words * 4u;               // ya validado: no hay overflow
    if (s < d + bytes && d < s + bytes) return DMA_ERR_OVERLAP;

    REG_DMA_SOURCE_ADDR = s;
    REG_DMA_DEST_ADDR   = d;
    REG_DMA_SIZE        = n_words;
    REG_DMA_START = 0;
    REG_DMA_START = 1;                  // el DMA arranca con el flanco 0->1
    while (!REG_DMA_DONE) ;
    return DMA_OK;
}

int dma_is_done(void){
    return REG_DMA_DONE & 1u;
}
