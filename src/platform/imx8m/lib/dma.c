// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright 2019 NXP
//
// Author: Daniel Baluta <daniel.baluta@nxp.com>

#include <sof/common.h>
#include <rtos/interrupt.h>
#include <sof/lib/dma.h>
#include <sof/lib/memory.h>
#include <rtos/sof.h>
#include <rtos/spinlock.h>

extern struct dma_ops sdma_ops;

/* Phase 2 of the i.MX8MP SDMA data path refactor:
 *
 * Previously this file declared two dma entries: one for DMA_ID_HOST
 * backed by the "dummy_dma" CPU-memcpy driver (used for moving audio
 * data between the Linux ALSA ring buffer and SOF host.dma_buffer),
 * and one for DMA_ID_SDMA3 backed by the real SDMA hardware (used for
 * the SAI TX/RX FIFO).
 *
 * The CPU memcpy path saturated the HiFi4 DSP's memory bandwidth under
 * 8-channel TDM 32-bit loads (1.5 MB/s sustained) and caused periodic
 * audio clips. The SDMA3 controller has 32 channels and a ROM script
 * at SDMA_SCRIPT_AP2AP_OFF (see src/include/sof/drivers/sdma.h) that
 * performs memory-to-memory transfers in hardware — exactly what the
 * host side needs.
 *
 * Phase 1 (commit eecb74eb) enabled SDMA_CHAN_TYPE_AP2AP end-to-end in
 * the SDMA driver. This Phase 2 rewires the platform DMA registration:
 *
 * - The single DMA entry below now advertises BOTH DAI directions
 *   (MEM_TO_DEV / DEV_TO_MEM for SAI+MICFIL) AND host directions
 *   (HMEM_TO_LMEM / LMEM_TO_HMEM / MEM_TO_MEM for DMA_DEV_HOST).
 * - dma_get() matches by dir/caps/devs bitmask, so a host-side call
 *   like dma_get(DMA_DIR_HMEM_TO_LMEM, 0, DMA_DEV_HOST, 0) will now
 *   land on this SDMA3 entry, which dispatches through sdma_ops and
 *   runs the AP2AP hardware path.
 * - dummy_dma_ops is no longer linked from this platform; the generic
 *   driver itself still exists and is used by other platforms.
 */
static SHARED_DATA struct dma dma[PLATFORM_NUM_DMACS] = {
{
	.plat_data = {
		.id		= DMA_ID_SDMA3,
		.dir		= DMA_DIR_MEM_TO_DEV | DMA_DIR_DEV_TO_MEM |
				  DMA_DIR_MEM_TO_MEM |
				  DMA_DIR_HMEM_TO_LMEM | DMA_DIR_LMEM_TO_HMEM,
		.devs		= DMA_DEV_SAI | DMA_DEV_MICFIL |
				  DMA_DEV_HOST,
		.base		= SDMA3_BASE,
		.channels	= 32,
		.irq		= SDMA3_IRQ,
		.irq_name	= SDMA3_IRQ_NAME,
	},
	.ops	= &sdma_ops,
},
};

static const struct dma_info lib_dma = {
	.dma_array = cache_to_uncache_init((struct dma *)dma),
	.num_dmas = ARRAY_SIZE(dma)
};

int dmac_init(struct sof *sof)
{
	int i;

	/* early lock initialization for ref counting */
	for (i = 0; i < ARRAY_SIZE(dma); i++)
		k_spinlock_init(&dma[i].lock);

	sof->dma_info = &lib_dma;

	return 0;
}
