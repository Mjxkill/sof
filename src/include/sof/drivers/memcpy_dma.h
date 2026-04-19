/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2026 NXP
 *
 * Hardware-accelerated memcpy via SDMA AP2AP script.
 * Drop-in replacement for memcpy() using the i.MX8MP SDMA3 controller
 * to offload memory-to-memory transfers from the HiFi4 DSP core.
 */

#ifndef __SOF_DRIVERS_MEMCPY_DMA_H__
#define __SOF_DRIVERS_MEMCPY_DMA_H__

#include <stddef.h>

/**
 * Initialize the memcpy_dma subsystem.
 * Must be called once, from platform init, after dmac_init().
 * Acquires a dedicated SDMA3 AP2AP channel and pre-configures it.
 *
 * @return 0 on success, negative errno on failure.
 */
int memcpy_dma_init(void);

/**
 * Copy bytes from src to dst via SDMA hardware (blocking).
 * Semantics identical to memcpy(3): caller owns both buffers,
 * the copy is complete when this function returns.
 *
 * If the hardware channel is not available, or the transfer size is
 * below MEMCPY_DMA_MIN_BYTES, falls back transparently to memcpy().
 *
 * Handles cache coherency: writeback of src before transfer,
 * invalidate of dst after transfer.
 *
 * @param dst   destination buffer (cacheable DSP-accessible memory)
 * @param src   source buffer (cacheable DSP-accessible memory)
 * @param bytes number of bytes to copy
 * @return dst (matches memcpy())
 */
void *memcpy_dma(void *dst, const void *src, size_t bytes);

/* Transfers below this size fall back to CPU memcpy — below it, the
 * DMA setup/cache-maintenance overhead exceeds the raw-copy cost.
 */
#define MEMCPY_DMA_MIN_BYTES 16

#endif /* __SOF_DRIVERS_MEMCPY_DMA_H__ */
