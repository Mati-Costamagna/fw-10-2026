#ifndef DMA_H
#define DMA_H

#include <stdint.h>

/* Codigos de retorno de dma_copy */
#define DMA_OK            0
#define DMA_ERR_ADDR     (-1)   /* src o dst invalido (ver dma_copy) */
#define DMA_ERR_OVERLAP  (-2)   /* src y dst se solapan */

void dma_init(void);

/*
 *
 * Solapamiento: el DMA copia hacia adelante, palabra por palabra (lee la i y la escribe antes
 * de leer la i+1). Si dst > src y los rangos se solapan, pisa origen que todavia no copio.
 * El driver rechaza cualquier solapamiento con DMA_ERR_OVERLAP.
 *
 */
int dma_copy(const void *src, void *dst, uint32_t n_words);

int dma_is_done(void);

#endif
