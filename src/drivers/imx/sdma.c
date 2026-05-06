// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright 2020 NXP
//
// Author: Paul Olaru <paul.olaru@nxp.com>

#include <sof/audio/component.h>
#include <sof/drivers/memcpy_dma.h>
#include <sof/drivers/sdma.h>
#include <rtos/spinlock.h>
#include <rtos/timer.h>
#include <rtos/alloc.h>
#include <sof/lib/dma.h>
#include <sof/lib/io.h>
#include <sof/lib/mailbox.h>
#include <sof/lib/notifier.h>
#include <sof/lib/uuid.h>
#include <rtos/wait.h>
#include <sof/platform.h>
#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

LOG_MODULE_REGISTER(sdma, CONFIG_SOF_LOG_LEVEL);

/* 70d223ef-2b91-4aac-b444-d89a0db2793a */
DECLARE_SOF_UUID("sdma", sdma_uuid, 0x70d223ef, 0x2b91, 0x4aac,
		 0xb4, 0x44, 0xd8, 0x9a, 0x0d, 0xb2, 0x79, 0x3a);

DECLARE_TR_CTX(sdma_tr, SOF_UUID(sdma_uuid), LOG_LEVEL_INFO);

#define SDMA_BUFFER_PERIOD_COUNT 2

struct sdma_bd {
	/* SDMA BD (buffer descriptor) configuration */
	uint32_t config;

	/* Buffer addresses, typically source and destination in some
	 * order, dependent on script
	 */
	uint32_t buf_addr;
	uint32_t buf_xaddr;
} __packed;

/* SDMA core context */
struct sdma_context {
	uint32_t pc;
	uint32_t spc;
	uint32_t g_reg[8];
	uint32_t dma_xfer_regs[14];
	uint32_t scratch[8];
} __packed;

/* SDMA channel control block */
struct sdma_ccb {
	uint32_t current_bd_paddr;
	uint32_t base_bd_paddr;
	uint32_t status;
	uint32_t reserved; /* No channel descriptor implemented */
};

/* This structure includes all SDMA related channel data */
struct sdma_chan {
	/* Statically allocate BDs; we can change if we ever need dynamic
	 * allocation
	 */
	struct sdma_bd desc[SDMA_MAX_BDS];
	int desc_count;
	struct sdma_context *ctx;
	struct sdma_ccb *ccb;
	int hw_event;
	int next_bd;
	int current_bd;	/* BD available for host, flips each ISR */
	int sdma_chan_type;
	int fifo_paddr;

	unsigned int watermark_level;
	unsigned int sw_done_sel; /* software done selector */
};

/* Private data for the whole controller */
struct sdma_pdata {
	/* Statically allocate channel private data and contexts array.
	 * CCBs must be allocated as array anyway.
	 */
	struct sdma_chan *chan_pdata;
	struct sdma_context *contexts;
	struct sdma_ccb *ccb_array;
};

static void sdma_set_overrides(struct dma_chan_data *channel,
			       bool event_override, bool host_override)
{
	tr_dbg(&sdma_tr, "sdma_set_overrides(%d, %d)", event_override,
	       host_override);
	dma_reg_update_bits(channel->dma, SDMA_EVTOVR, BIT(channel->index),
			    event_override ? BIT(channel->index) : 0);
	dma_reg_update_bits(channel->dma, SDMA_HOSTOVR, BIT(channel->index),
			    host_override ? BIT(channel->index) : 0);
}

static void sdma_enable_channel(struct dma *dma, int channel)
{
	dma_reg_write(dma, SDMA_HSTART, BIT(channel));
}

static void sdma_disable_channel(struct dma *dma, int channel)
{
	/* DIAG E6.b: trace ALL sdma_disable_channel calls (clean zone 0x300).
	 * 0x300 : total entries
	 * 0x304 : last chan disabled
	 * 0x310-0x31F : ring 4 first chan disabled
	 */
	{
		static volatile uint32_t dbg_dis;
		uint32_t n;
		dbg_dis++;
		n = dbg_dis;
		mailbox_sw_reg_write(0x300, n);
		mailbox_sw_reg_write(0x304, (uint32_t)channel);
		if (n >= 1 && n <= 4)
			mailbox_sw_reg_write(0x310 + (n - 1) * 4,
					     (uint32_t)channel);
	}
	dma_reg_write(dma, SDMA_STOP_STAT, BIT(channel));
}

static int sdma_run_c0(struct dma *dma, uint8_t cmd, uint32_t buf_addr,
		       uint16_t sdma_addr, uint16_t count)
{
	struct dma_chan_data *c0 = dma->chan;
	struct sdma_chan *c0data = dma_chan_get_data(c0);
	int ret;

	tr_dbg(&sdma_tr, "sdma_run_c0 cmd %d buf_addr 0x%08x sdma_addr 0x%04x count %d",
	       cmd, buf_addr, sdma_addr, count);

	c0data->desc[0].config = SDMA_BD_CMD(cmd) | SDMA_BD_COUNT(count)
		| SDMA_BD_WRAP | SDMA_BD_DONE;
	c0data->desc[0].buf_addr = buf_addr;
	c0data->desc[0].buf_xaddr = sdma_addr;
	if (sdma_addr)
		c0data->desc[0].config |= SDMA_BD_EXTD;

	c0data->ccb->current_bd_paddr = (uint32_t)&c0data->desc[0];
	c0data->ccb->base_bd_paddr = (uint32_t)&c0data->desc[0];

	/* Writeback descriptors and CCB */
	dcache_writeback_region(c0data->desc,
				sizeof(c0data->desc[0]));
	dcache_writeback_region(c0data->ccb, sizeof(*c0data->ccb));

	/* Set event override to true so we can manually start channel */
	sdma_set_overrides(c0, true, false);

	sdma_enable_channel(dma, 0);

	/* 1 is BIT(0) for channel 0, the bit will be cleared as the
	 * channel finishes execution. 1ms is sufficient if everything is fine.
	 */
	ret = poll_for_register_delay(dma_base(dma) + SDMA_STOP_STAT,
				      1, 0, 1000);
	if (ret >= 0)
		ret = 0;

	if (ret < 0)
		tr_err(&sdma_tr, "SDMA channel 0 timed out");

	/* Switch to dynamic context switch mode if needed. This saves power. */
	if ((dma_reg_read(dma, SDMA_CONFIG) & SDMA_CONFIG_CSM_MSK) ==
	    SDMA_CONFIG_CSM_STATIC)
		dma_reg_update_bits(dma, SDMA_CONFIG, SDMA_CONFIG_CSM_MSK,
				    SDMA_CONFIG_CSM_DYN);

	tr_dbg(&sdma_tr, "sdma_run_c0 done, ret = %d", ret);

	return ret;
}

static int sdma_register_init(struct dma *dma)
{
	int ret;
	struct sdma_pdata *pdata = dma_get_drvdata(dma);
	int i;

	tr_dbg(&sdma_tr, "sdma_register_init");
	dma_reg_write(dma, SDMA_RESET, 1);
	/* Wait for 10us */
	ret = poll_for_register_delay(dma_base(dma) + SDMA_RESET, 1, 0, 1000);
	if (ret < 0) {
		tr_err(&sdma_tr, "SDMA reset error, base address %p",
		       (void *)dma_base(dma));
		return ret;
	}

	dma_reg_write(dma, SDMA_MC0PTR, 0);

	/* Ack all interrupts, they're leftover */
	dma_reg_write(dma, SDMA_INTR, MASK(31, 0));

	/* SDMA requires static context switch for first execution of channel 0
	 * in the future. Set it to static here, then have it change to dynamic
	 * after this first execution of channel 0 completes.
	 *
	 * Also set ACR bit according to hardware configuration. Each platform
	 * may have a different configuration.
	 */
#if SDMA_CORE_RATIO
	dma_reg_update_bits(dma, SDMA_CONFIG,
			    SDMA_CONFIG_CSM_MSK | SDMA_CONFIG_ACR,
			    SDMA_CONFIG_ACR);
#else
	dma_reg_update_bits(dma, SDMA_CONFIG,
			    SDMA_CONFIG_CSM_MSK | SDMA_CONFIG_ACR, 0);
#endif
	/* Set 32-word scratch memory size */
	dma_reg_update_bits(dma, SDMA_CHN0ADDR, BIT(14), BIT(14));

	/* Reset channel enable map (it doesn't reset with the controller).
	 * It shall be updated whenever channels need to be activated by
	 * hardware events.
	 */
	for (i = 0; i < SDMA_HWEVENTS_COUNT; i++)
		dma_reg_write(dma, SDMA_CHNENBL(i), 0);

	for (i = 0; i < dma->plat_data.channels; i++)
		dma_reg_write(dma, SDMA_CHNPRI(i), 0);

	/* Write ccb_array pointer to SDMA controller */
	dma_reg_write(dma, SDMA_MC0PTR, (uint32_t)pdata->ccb_array);

	return 0;
}

static void sdma_init_c0(struct dma *dma)
{
	struct dma_chan_data *c0 = &dma->chan[0];
	struct sdma_pdata *sdma_pdata = dma_get_drvdata(dma);
	struct sdma_chan *pdata = &sdma_pdata->chan_pdata[0];

	tr_dbg(&sdma_tr, "sdma_init_c0");
	c0->status = COMP_STATE_READY;

	/* Reset channel 0 private data */
	memset(pdata, 0, sizeof(*pdata));
	pdata->ctx = sdma_pdata->contexts;
	pdata->ccb = sdma_pdata->ccb_array;
	pdata->hw_event = -1;
	dma_chan_set_data(c0, pdata);

	dma_reg_write(dma, SDMA_CHNPRI(0), SDMA_MAXPRI);
}

static int sdma_boot(struct dma *dma)
{
	int ret;

	tr_dbg(&sdma_tr, "sdma_boot");
	ret = sdma_register_init(dma);
	if (ret < 0)
		return ret;

	sdma_init_c0(dma);

	tr_dbg(&sdma_tr, "sdma_boot done");
	return 0;
}

static int sdma_upload_context(struct dma_chan_data *chan)
{
	struct sdma_chan *pdata = dma_chan_get_data(chan);

	/* Ensure context is ready for upload */
	dcache_writeback_region(pdata->ctx, sizeof(*pdata->ctx));

	tr_dbg(&sdma_tr, "sdma_upload_context for channel %d", chan->index);

	/* Last parameters are unneeded for this command and are ignored;
	 * set to 0.
	 */
	return sdma_run_c0(chan->dma, SDMA_CMD_C0_SET_DM, (uint32_t)pdata->ctx,
			   SDMA_SRAM_CONTEXTS_BASE +
				 /* https://trac.cppcheck.net/ticket/10179 */
				 /* cppcheck-suppress divideSizeof */
			   chan->index * sizeof(*pdata->ctx) / 4,
				 /* https://trac.cppcheck.net/ticket/10179 */
				 /* cppcheck-suppress divideSizeof */
			   sizeof(*pdata->ctx) / 4);
}

#if CONFIG_HAVE_SDMA_FIRMWARE
static int sdma_load_firmware(struct dma *dma, void *buf, int addr, int size)
{
	return sdma_run_c0(dma->chan->dma, SDMA_CMD_C0_SET_PM,
			   (uint32_t)buf, addr, size / 2);
}
#endif

/* Below SOF related functions will be placed */

static int sdma_probe(struct dma *dma)
{
	int channel;
	int ret;
	struct sdma_pdata *pdata;

	if (dma->chan) {
		tr_err(&sdma_tr, "SDMA: Repeated probe");
		return -EEXIST;
	}

	tr_info(&sdma_tr, "SDMA: probe");

	dma->chan = rzalloc(SOF_MEM_ZONE_RUNTIME, 0, SOF_MEM_CAPS_RAM,
			    dma->plat_data.channels *
			    sizeof(struct dma_chan_data));
	if (!dma->chan) {
		tr_err(&sdma_tr, "SDMA: Probe failure, unable to allocate channel descriptors");
		return -ENOMEM;
	}

	pdata = rzalloc(SOF_MEM_ZONE_RUNTIME, 0, SOF_MEM_CAPS_RAM,
			sizeof(*pdata));
	if (!pdata) {
		rfree(dma->chan);
		dma->chan = NULL;
		tr_err(&sdma_tr, "SDMA: Probe failure, unable to allocate private data");
		return -ENOMEM;
	}
	dma_set_drvdata(dma, pdata);

	for (channel = 0; channel < dma->plat_data.channels; channel++) {
		dma->chan[channel].index = channel;
		dma->chan[channel].dma = dma;
	}

	pdata->chan_pdata = rzalloc(SOF_MEM_ZONE_RUNTIME, 0, SOF_MEM_CAPS_RAM,
				    dma->plat_data.channels *
				    sizeof(struct sdma_chan));
	if (!pdata->chan_pdata) {
		ret = -ENOMEM;
		tr_err(&sdma_tr, "SDMA: probe: out of memory");
		goto err;
	}

	pdata->contexts = rzalloc(SOF_MEM_ZONE_RUNTIME, 0, SOF_MEM_CAPS_RAM,
				  dma->plat_data.channels *
				  sizeof(struct sdma_context));
	if (!pdata->contexts) {
		ret = -ENOMEM;
		tr_err(&sdma_tr, "SDMA: probe: unable to allocate contexts");
		goto err;
	}

	pdata->ccb_array = rzalloc(SOF_MEM_ZONE_RUNTIME, 0, SOF_MEM_CAPS_RAM,
				   dma->plat_data.channels *
				   sizeof(struct sdma_ccb));
	if (!pdata->ccb_array) {
		ret = -ENOMEM;
		tr_err(&sdma_tr, "SDMA: probe: unable to allocate CCBs");
		goto err;
	}

	ret = sdma_boot(dma);
	if (ret < 0) {
		tr_err(&sdma_tr, "SDMA: Unable to boot");
		goto err;
	}

#if CONFIG_HAVE_SDMA_FIRMWARE
	ret = sdma_load_firmware(dma, (void *)sdma_code,
				 RAM_CODE_START_ADDR,
				 RAM_CODE_SIZE * sizeof(short));
	if (ret < 0) {
		tr_err(&sdma_tr, "SDMA: Failed to load firmware");
		goto err;
	}
#endif

	goto out;
err:
	if (pdata->chan_pdata)
		rfree(pdata->chan_pdata);
	if (pdata->contexts)
		rfree(pdata->contexts);
	if (pdata->ccb_array)
		rfree(pdata->ccb_array);
	/* Failures of allocation were treated already */
	rfree(dma_get_drvdata(dma));
	rfree(dma->chan);
	dma_set_drvdata(dma, NULL);
	dma->chan = NULL;
out:
	return ret;
}

static int sdma_remove(struct dma *dma)
{
	struct sdma_pdata *pdata = dma_get_drvdata(dma);

	if (!dma->chan) {
		tr_err(&sdma_tr, "SDMA: Remove called without probe, that's a noop");
		return 0;
	}

	tr_dbg(&sdma_tr, "sdma_remove");

	/* Prevent all channels except channel 0 from running */
	dma_reg_write(dma, SDMA_HOSTOVR, 1);
	dma_reg_write(dma, SDMA_EVTOVR, 0);

	/* Stop all channels except channel 0 */
	dma_reg_write(dma, SDMA_STOP_STAT, ~1);

	/* Reset SDMAC */
	dma_reg_write(dma, SDMA_RESET, 1);

	/* Free all memory related to SDMA */
	rfree(pdata->chan_pdata);
	rfree(pdata->contexts);
	rfree(pdata->ccb_array);
	rfree(dma->chan);
	dma->chan = NULL;

	return 0;
}

static struct dma_chan_data *sdma_channel_get(struct dma *dma,
					      unsigned int chan)
{
	struct sdma_pdata *pdata = dma_get_drvdata(dma);
	struct dma_chan_data *channel;
	struct sdma_chan *cdata;
	int i;
	/* Ignoring channel 0; let's just allocate a free channel */

	tr_dbg(&sdma_tr, "sdma_channel_get");
	{
		static volatile uint32_t dbg_get_count;
		dbg_get_count++;
		mailbox_sw_reg_write(0x7E0, dbg_get_count);
	}
	for (i = 1; i < dma->plat_data.channels; i++) {
		channel = &dma->chan[i];
		if (channel->status != COMP_STATE_INIT)
			continue;

		/* Reset channel private data */
		cdata = &pdata->chan_pdata[i];
		memset(cdata, 0, sizeof(*cdata));
		cdata->ctx = pdata->contexts + i;
		cdata->ccb = pdata->ccb_array + i;
		cdata->hw_event = -1;

		channel->status = COMP_STATE_READY;
		channel->index = i;
		dma_chan_set_data(channel, cdata);

		/* Allow events, allow manual */
		sdma_set_overrides(channel, false, false);
		/* DIAG E6.b Phase 4: log last allocated chan_index + status before alloc */
		mailbox_sw_reg_write(0x7E4, (uint32_t)i);
		mailbox_sw_reg_write(0x7E8, (uint32_t)channel->status);
		return channel;
	}
	tr_err(&sdma_tr, "sdma no channel free");
	return NULL;
}

static void sdma_enable_event(struct dma_chan_data *channel, int eventnum)
{
	struct sdma_chan *pdata = dma_chan_get_data(channel);

	tr_dbg(&sdma_tr, "sdma_enable_event(%d, %d)", channel->index, eventnum);

	if (eventnum < 0 || eventnum > SDMA_HWEVENTS_COUNT)
		return; /* No change if request is invalid */

	dma_reg_update_bits(channel->dma, SDMA_CHNENBL(eventnum),
			    BIT(channel->index), BIT(channel->index));

	if (pdata->sw_done_sel & BIT(31)) {
		unsigned int done0;

		done0 = SDMA_DONE0_CONFIG_DONE_SEL | ~SDMA_DONE0_CONFIG_DONE_DIS;
		dma_reg_update_bits(channel->dma, SDMA_DONE0_CONFIG, 0xFF, done0);
	}
}

static void sdma_disable_event(struct dma_chan_data *channel, int eventnum)
{
	tr_dbg(&sdma_tr, "sdma_disable_event(%d, %d)", channel->index, eventnum);

	if (eventnum < 0 || eventnum > SDMA_HWEVENTS_COUNT)
		return; /* No change if request is invalid */

	dma_reg_update_bits(channel->dma, SDMA_CHNENBL(eventnum),
			    BIT(channel->index), 0);
}

static void sdma_channel_put(struct dma_chan_data *channel)
{
	struct sdma_chan *pdata = dma_chan_get_data(channel);

	if (channel->status == COMP_STATE_INIT)
		return; /* Channel was already free */
	tr_dbg(&sdma_tr, "sdma_channel_put(%d)", channel->index);

	/* DIAG E6.b Phase 4: trace channel release (alloc/release sequence) */
	{
		static volatile uint32_t dbg_put_count;
		dbg_put_count++;
		mailbox_sw_reg_write(0x7F0, dbg_put_count);
		mailbox_sw_reg_write(0x7F4, (uint32_t)channel->index);
	}

	dma_interrupt_legacy(channel, DMA_IRQ_CLEAR);
	sdma_disable_event(channel, pdata->hw_event);
	sdma_set_overrides(channel, false, false);
	channel->status = COMP_STATE_INIT;
}

static int sdma_start(struct dma_chan_data *channel)
{
	struct sdma_chan *pdata = dma_chan_get_data(channel);

	tr_dbg(&sdma_tr, "sdma_start(%d)", channel->index);

	/* DIAG E6.b: count sdma_start entry + last channel index.
	 * 0x5A0: total entry, 0x5A4: last channel index, 0x5A8: last status
	 * 0x5B0: HSTART commit count, 0x5B4: last HSTART channel index
	 * 0x6B0-0x6CC: per-channel sdma_start counter (chan 0..7)
	 * 0x6D0: last sdma_chan_type at sdma_start
	 * 0x6D4: last hw_event at sdma_start
	 */
	{
		static volatile uint32_t dbg_entry;
		static volatile uint32_t dbg_chan_start[8];
		dbg_entry++;
		mailbox_sw_reg_write(0x5A0, dbg_entry);
		mailbox_sw_reg_write(0x5A4, channel->index);
		mailbox_sw_reg_write(0x5A8, channel->status);
		if (channel->index < 8) {
			dbg_chan_start[channel->index]++;
			mailbox_sw_reg_write(0x6B0 + channel->index * 4,
					     dbg_chan_start[channel->index]);
		}
		mailbox_sw_reg_write(0x6D0, (uint32_t)pdata->sdma_chan_type);
		mailbox_sw_reg_write(0x6D4, (uint32_t)pdata->hw_event);
	}

	if (channel->status != COMP_STATE_PREPARE &&
	    channel->status != COMP_STATE_PAUSED)
		return -EINVAL;

	channel->status = COMP_STATE_ACTIVE;

	/* Force dynamic context switch mode for continuous operation */
	dma_reg_update_bits(channel->dma, SDMA_CONFIG,
			    SDMA_CONFIG_CSM_MSK, SDMA_CONFIG_CSM_DYN);

	/* AP2AP one-shot channels are manually kicked by sdma_copy() each
	 * period. Calling HSTART here would trigger a premature transfer
	 * with stale/empty BD addresses (host page table or audio buffer
	 * not yet populated at trigger time) and generate an unhandled
	 * interrupt on a channel that is NOT registered with the Zephyr
	 * DMA domain (not a scheduling source) — leading to an IRQ storm
	 * once the shared SDMA3 line is enabled by the DAI sdma_start.
	 * The old dummy_dma_start was a no-op; we preserve that semantic
	 * for AP2AP.
	 */
	if (pdata->sdma_chan_type != SDMA_CHAN_TYPE_AP2AP) {
		static volatile uint32_t dbg_hstart;
		dbg_hstart++;
		mailbox_sw_reg_write(0x5B0, dbg_hstart);
		mailbox_sw_reg_write(0x5B4, channel->index);
		sdma_enable_channel(channel->dma, channel->index);
	}

	return 0;
}

static int sdma_stop(struct dma_chan_data *channel)
{
	/* DIAG E6.b: trace sdma_stop entry (BEFORE early-return guard).
	 * 0x320 : total entries (every call, regardless of status)
	 * 0x324 : last chan->index seen
	 * 0x328 : last chan->status seen on entry
	 * 0x330-0x33F : ring 4 first chan->index
	 * 0x32C : count of EARLY-RETURNS (status != ACTIVE && != PAUSED)
	 */
	{
		static volatile uint32_t dbg_stop;
		uint32_t n;
		dbg_stop++;
		n = dbg_stop;
		mailbox_sw_reg_write(0x320, n);
		mailbox_sw_reg_write(0x324, (uint32_t)channel->index);
		mailbox_sw_reg_write(0x328, (uint32_t)channel->status);
		if (n >= 1 && n <= 4)
			mailbox_sw_reg_write(0x330 + (n - 1) * 4,
					     (uint32_t)channel->index);
	}

	if (channel->status != COMP_STATE_ACTIVE &&
	    channel->status != COMP_STATE_PAUSED) {
		static volatile uint32_t dbg_stop_skip;
		dbg_stop_skip++;
		mailbox_sw_reg_write(0x32C, dbg_stop_skip);
		return 0;
	}

	channel->status = COMP_STATE_READY;

	tr_dbg(&sdma_tr, "sdma_stop(%d)", channel->index);

	sdma_disable_channel(channel->dma, channel->index);

	return 0;
}

static int sdma_pause(struct dma_chan_data *channel)
{
	struct sdma_chan *pdata = dma_chan_get_data(channel);

	if (channel->status != COMP_STATE_ACTIVE)
		return -EINVAL;

	channel->status = COMP_STATE_PAUSED;

	/* Manually controlled channels need not be paused. */
	if (pdata->hw_event != -1)
		dma_reg_update_bits(channel->dma, SDMA_HOSTOVR,
				    BIT(channel->index), 0);

	return 0;
}

static int sdma_release(struct dma_chan_data *channel)
{
	if (channel->status != COMP_STATE_PAUSED)
		return -EINVAL;

	channel->status = COMP_STATE_PREPARE;

	/* No pointer realignment is necessary for release, context points
	 * correctly to beginning of the following BD.
	 */
	return 0;
}

static int sdma_copy(struct dma_chan_data *channel, int bytes, uint32_t flags)
{
	struct sdma_chan *pdata = dma_chan_get_data(channel);
	struct dma_cb_data next = {
		.channel = channel,
		.elem.size = bytes,
	};

	tr_dbg(&sdma_tr, "sdma_copy");

	/* DIAG E6.b: count sdma_copy entry (BD reload) per channel.
	 * 0x600: total entry, 0x604: last channel index, 0x608: last bytes
	 * 0x60C: per-channel count for chan 6 (SAI TX), throttled 1/16
	 * 0x680-0x69C: per-channel sdma_copy counter (chan 0..7) — full count
	 * 0x6A0: last sdma_chan_type seen for chan 3 (probable SAI TX)
	 */
	{
		static volatile uint32_t dbg_entry, dbg_chan6;
		static volatile uint32_t dbg_chan_copy[8];
		dbg_entry++;
		if ((dbg_entry & 0x0F) == 1) {
			mailbox_sw_reg_write(0x600, dbg_entry);
			mailbox_sw_reg_write(0x604, channel->index);
			mailbox_sw_reg_write(0x608, (uint32_t)bytes);
		}
		if (channel->index == 6) {
			dbg_chan6++;
			mailbox_sw_reg_write(0x60C, dbg_chan6);
		}
		if (channel->index < 8) {
			dbg_chan_copy[channel->index]++;
			mailbox_sw_reg_write(0x680 + channel->index * 4,
					     dbg_chan_copy[channel->index]);
		}
		if (channel->index == 3)
			mailbox_sw_reg_write(0x6A0, (uint32_t)pdata->sdma_chan_type);
	}

	if (pdata->sdma_chan_type == SDMA_CHAN_TYPE_AP2AP) {
		/* Delegate AP2AP to the single memcpy_dma primitive so every
		 * SDMA memory-to-memory transfer in SOF goes through one code
		 * path (kick, poll, cache maintenance). The caller's BD was
		 * already programmed by sdma_prep_desc() via dma_set_config;
		 * we just extract src/dst and fire the framework notifier
		 * after completion.
		 */
		struct sdma_bd *bd = &pdata->desc[0];

		if (!bd->buf_addr || !bd->buf_xaddr) {
			tr_warn(&sdma_tr,
				"sdma_copy AP2AP skip null addr chan=%d",
				channel->index);
			return 0;
		}

		memcpy_dma((void *)(uintptr_t)bd->buf_xaddr,
			   (const void *)(uintptr_t)bd->buf_addr, bytes);

		notifier_event(channel, NOTIFIER_ID_DMA_COPY,
			       NOTIFIER_TARGET_CORE_LOCAL, &next,
			       sizeof(next));
		return 0;
	}

	/* Cyclic path (SHP2MCU / MCU2SHP for DAI/MICFIL): just re-arm
	 * the DONE bit on the completed BD — the SDMA hardware keeps
	 * cycling via CONT+WRAP, triggered by peripheral events.
	 */

	/* Flip first: now current_bd = the BD that just completed */
	pdata->current_bd = (pdata->current_bd + 1) % pdata->desc_count;

	/* Re-set DONE on completed BD — SDMA is on the OTHER BD now.
	 * Must invalidate+writeback: SDMA reads BDs from physical memory.
	 */
	dcache_invalidate_region(&pdata->desc[pdata->current_bd].config,
				 sizeof(pdata->desc[pdata->current_bd].config));
	pdata->desc[pdata->current_bd].config |= SDMA_BD_DONE;
	dcache_writeback_region(&pdata->desc[pdata->current_bd].config,
				sizeof(pdata->desc[pdata->current_bd].config));


	notifier_event(channel, NOTIFIER_ID_DMA_COPY,
		       NOTIFIER_TARGET_CORE_LOCAL, &next, sizeof(next));

	return 0;
}

static int sdma_status(struct dma_chan_data *channel,
		       struct dma_chan_status *status, uint8_t direction)
{
	struct sdma_chan *pdata = dma_chan_get_data(channel);
	struct sdma_bd *bd;

	tr_dbg(&sdma_tr, "sdma_status");
	if (channel->status == COMP_STATE_INIT)
		return -EINVAL;
	status->state = channel->status;
	status->flags = 0;
	status->w_pos = 0;
	status->r_pos = 0;
	status->timestamp = sof_cycle_get_64();

	/* CCB is updated by the SDMA hardware when it advances/wraps to
	 * the next BD. Invalidate before reading current_bd_paddr.
	 */
	dcache_invalidate_region(pdata->ccb, sizeof(*pdata->ccb));

	bd = (struct sdma_bd *)pdata->ccb->current_bd_paddr;

	switch (pdata->sdma_chan_type) {
	case SDMA_CHAN_TYPE_AP2AP:
		/* We won't ever enable MMU will we? */
		status->r_pos = bd->buf_addr;
		status->w_pos = bd->buf_xaddr;
		break;
	case SDMA_CHAN_TYPE_AP2MCU:
	case SDMA_CHAN_TYPE_MCU2SHP:
	case SDMA_CHAN_TYPE_SAI2MCU:
		status->r_pos = bd->buf_addr;
		status->w_pos = pdata->fifo_paddr;
		/* We cannot see the target address */
		break;
	case SDMA_CHAN_TYPE_MCU2AP:
	case SDMA_CHAN_TYPE_SHP2MCU:
		status->w_pos = bd->buf_addr;
		status->r_pos = pdata->fifo_paddr;
		break;
	}
	return 0;
}

static void sdma_set_watermarklevel(struct dma_chan_data *chan)
{
	struct sdma_chan *pdata = dma_chan_get_data(chan);

	/* TODO: retrieve this information from DAI */
	unsigned int n_fifos = 4; /* number of HW fifos used */
	unsigned int words_per_fifo = 1; /* number of audio channels per frame */

	/* sw_done_sel mimics software done configuration from Linux
	 * see Documentation/devicetree/bindings/fsl-imx-sdma.txt
	 */
	unsigned int sw_done_sel = 0;

	/* sw_done_sel configuration
	 * - bit31:  sw_done
	 * - bit15:8 selector
	 * - bit7-0  priority
	 */
	sw_done_sel |= BIT(31);

	/* watermark level:
	 * bit0~11: wartermark level(wml*fifo_number)
	 * bit15~12: to do-fifo number
	 * bit16~19: fifo offset
	 * bit27~24: sw done selector
	 * bit28~31: numbers of audio channels in one frame, 0: 1 channel,1: 2 channels
	 * bit23: sw done enable
	 */

	pdata->watermark_level |= SDMA_WATERMARK_LEVEL_SW_DONE |
		 (sw_done_sel & 0xff) << SDMA_WATERMARK_LEVEL_SW_DONE_SEL_OFF;

	pdata->watermark_level |=
		SDMA_WATERMARK_LEVEL_N_FIFOS(n_fifos);

	pdata->watermark_level |=
		SDMA_WATERMARK_LEVEL_WORDS_PER_FIFO(words_per_fifo - 1);

	pdata->sw_done_sel = sw_done_sel;
}

static int sdma_read_config(struct dma_chan_data *channel,
			    struct dma_sg_config *config)
{
	int i;
	struct sdma_chan *pdata = dma_chan_get_data(channel);

	/* Note: do NOT dereference channel->dev_data as dai_data at this
	 * scope: for host (AP2AP) channels, dev_data is host_data, not
	 * dai_data. The dai_data access must happen only in DEV cases.
	 */

	switch (config->direction) {
	case DMA_DIR_MEM_TO_DEV:
		pdata->hw_event = config->dest_dev;
		pdata->sdma_chan_type = SDMA_CHAN_TYPE_MCU2SHP;
		pdata->fifo_paddr = config->elem_array.elems[0].dest;
		break;
	case DMA_DIR_DEV_TO_MEM: {
		struct dai_data *dd = channel->dev_data;
		uint32_t dma_dev = dd->dai->drv->dma_dev;

		pdata->hw_event = config->src_dev;
		if (dma_dev == DMA_DEV_MICFIL)
			pdata->sdma_chan_type = SDMA_CHAN_TYPE_SAI2MCU;
		else
			pdata->sdma_chan_type = SDMA_CHAN_TYPE_SHP2MCU;
		pdata->fifo_paddr = config->elem_array.elems[0].src;
		break;
	}
	case DMA_DIR_MEM_TO_MEM:
	case DMA_DIR_HMEM_TO_LMEM:
	case DMA_DIR_LMEM_TO_HMEM:
		/* Host memory <-> DSP local memory via SDMA AP2AP script.
		 * No hardware event — software triggered by sdma_start().
		 */
		pdata->sdma_chan_type = SDMA_CHAN_TYPE_AP2AP;
		pdata->hw_event = -1;
		pdata->fifo_paddr = 0;
		break;
	default:
		tr_err(&sdma_tr, "sdma_set_config: Unsupported direction %d",
		       config->direction);
		return -EINVAL;
	}

	for (i = 0; i < config->elem_array.count; i++) {
		if (config->direction == DMA_DIR_MEM_TO_DEV &&
		    pdata->fifo_paddr != config->elem_array.elems[i].dest) {
			tr_err(&sdma_tr, "sdma_read_config: FIFO changes address!");
			return -EINVAL;
		}

		if (config->direction == DMA_DIR_DEV_TO_MEM &&
		    pdata->fifo_paddr != config->elem_array.elems[i].src) {
			tr_err(&sdma_tr, "sdma_read_config: FIFO changes address!");
			return -EINVAL;
		}

		if (config->elem_array.elems[i].size > SDMA_BD_MAX_COUNT) {
			/* Future improvement: Create multiple BDs so as to
			 * support this situation
			 */
			tr_err(&sdma_tr, "sdma_set_config: elem transfers too much: %d bytes",
			       config->elem_array.elems[i].size);
			return -EINVAL;
		}
	}

	return 0;
}

/* Data to store in the descriptors:
 * 1) Each descriptor corresponds to each of the
 *    config->elem_array elems; if we have more than
 *    MAX_DESCRIPTORS we bail outright. For the future, we could
 *    allocate the per-channel descriptors dynamically.
 * 2) For each of them, store the host side (SDRAM side) as
 *    buf_addr and keep the FIFO address as a separate variable.
 *    Complain if this address changes between descriptors as we
 *    do not support this for now.
 * 3) Enable interrupts, set up transfer width, length of elem,
 *    wrap bit on the last descriptor, host side address, and
 *    finally the DONE bit so the SDMA can use the descriptors.
 * 4) The FIFO address will be stored in the context.
 * 5) Actually upload context now as we are inside DAI prepare.
 *    We have no other opportunity in the future.
 */
static int sdma_prep_desc(struct dma_chan_data *channel,
			  struct dma_sg_config *config)
{
	int i;
	int width;
	int watermark;
	uint32_t sdma_script_addr;
	struct sdma_chan *pdata = dma_chan_get_data(channel);
	struct sdma_bd *bd;

	/* Validate requested configuration */
	if (config->elem_array.count > SDMA_MAX_BDS) {
		tr_err(&sdma_tr, "sdma_set_config: Unable to handle %d descriptors",
		       config->elem_array.count);
		return -EINVAL;
	}
	if (config->elem_array.count <= 0) {
		tr_err(&sdma_tr, "sdma_set_config: Invalid descriptor count: %d",
		       config->elem_array.count);
		return -EINVAL;
	}

	pdata->next_bd = 0;
	pdata->current_bd = 1; /* DMA starts on BD[0], host accesses BD[1] */

	bd = &pdata->desc[0];
	width = 0;

	for (i = 0; i < config->elem_array.count; i++) {
		bd = &pdata->desc[i];
		switch (config->direction) {
		case DMA_DIR_MEM_TO_DEV:
			bd->buf_addr = config->elem_array.elems[i].src;
			width = config->src_width;
			break;
		case DMA_DIR_DEV_TO_MEM:
			bd->buf_addr = config->elem_array.elems[i].dest;
			width = config->dest_width;
			break;
		case DMA_DIR_MEM_TO_MEM:
		case DMA_DIR_HMEM_TO_LMEM:
		case DMA_DIR_LMEM_TO_HMEM:
			/* AP2AP script consumes source in buf_addr and
			 * destination in buf_xaddr.
			 */
			bd->buf_addr = config->elem_array.elems[i].src;
			bd->buf_xaddr = config->elem_array.elems[i].dest;
			width = config->dest_width;
			/* Null addresses are expected at host_params() time
			 * (host page table not yet received). Accept silently;
			 * sdma_copy() guards the actual transfer against null
			 * addrs. dummy_dma behaved the same way.
			 */
			break;
		default:
			return -EINVAL;
		}

		bd->config = SDMA_BD_COUNT(config->elem_array.elems[i].size) |
			SDMA_BD_CMD(SDMA_CMD_XFER_SIZE(width));

		if (pdata->sdma_chan_type == SDMA_CHAN_TYPE_AP2AP) {
			/* AP2AP one-shot memcpy: match Linux upstream
			 * sdma_prep_memcpy pattern — EXTD (buf_xaddr valid),
			 * DONE (SDMA ready to run), LAST (mark end of chain
			 * so the script clears DONE on completion). No CONT
			 * (single BD only). WRAP added below.
			 *
			 * NEVER set SDMA_BD_INT for AP2AP: the channel is
			 * polled synchronously in sdma_copy() and is not a
			 * scheduling source, so its BD_INT would not be
			 * cleared by the Zephyr DMA domain ISR — causing an
			 * IRQ storm once the shared SDMA3 line is enabled by
			 * DAI sdma_start.
			 */
			bd->config |= SDMA_BD_EXTD | SDMA_BD_DONE |
				      SDMA_BD_LAST;
		} else {
			/* Cyclic DAI path (SHP2MCU/MCU2SHP): keep CONT so
			 * SDMA continues into next BD. WRAP added below for
			 * cyclic configs. BD_INT honors caller's irq_disabled
			 * flag — DAI channels are scheduling sources, their
			 * IRQs are properly cleared by the domain ISR.
			 */
			if (!config->irq_disabled)
				bd->config |= SDMA_BD_INT;
			bd->config |= SDMA_BD_CONT | SDMA_BD_DONE;
		}
	}

	/* Mark end of chain:
	 *  - cyclic DAI: WRAP on last BD to loop back to first.
	 *  - AP2AP one-shot: WRAP so SDMA halts cleanly after the single BD.
	 */
	if (config->cyclic ||
	    pdata->sdma_chan_type == SDMA_CHAN_TYPE_AP2AP)
		bd->config |= SDMA_BD_WRAP;

	/* CCB must point to buffer descriptors array */
	memset(pdata->ccb, 0, sizeof(*pdata->ccb));
	pdata->ccb->base_bd_paddr = (uint32_t)pdata->desc;
	pdata->ccb->current_bd_paddr = (uint32_t)pdata->desc;
	pdata->desc_count = config->elem_array.count;

	/* Context must be configured, dependent on transfer direction */

	switch (pdata->sdma_chan_type) {
	case SDMA_CHAN_TYPE_AP2AP:
		sdma_script_addr = SDMA_SCRIPT_AP2AP_OFF;
		break;
	case SDMA_CHAN_TYPE_MCU2SHP:
		sdma_script_addr = SDMA_SCRIPT_MCU2SHP_OFF;
		break;
	case SDMA_CHAN_TYPE_SHP2MCU:
		sdma_script_addr = SDMA_SCRIPT_SHP2MCU_OFF;
		break;
	case SDMA_CHAN_TYPE_SAI2MCU:
		sdma_script_addr = SDMA_SCRIPT_SAI2MCU_OFF;
		break;
	default:
		/* This case doesn't happen; we need to assign the other cases
		 * for AP2MCU and MCU2AP
		 */
		tr_err(&sdma_tr, "Unexpected SDMA error");
		return -EINVAL;
	}

	if (pdata->sdma_chan_type == SDMA_CHAN_TYPE_SAI2MCU) {
		/* MICFIL multi-FIFO NXP hack: needs SW_DONE + N_FIFOS bits */
		watermark = (config->burst_elems * width) / 8;
		sdma_set_watermarklevel(channel);
		watermark |= pdata->watermark_level;
	} else if (pdata->sdma_chan_type == SDMA_CHAN_TYPE_AP2AP) {
		/* AP2AP uses g_reg[7] as RAM base address (0x40000000),
		 * not a watermark. Set to 0 here; overwritten below.
		 */
		watermark = 0;
	} else {
		/* SHP2MCU/MCU2SHP: g_reg[7] expects watermark in WORDS.
		 * burst_elems = FIFO depth = 128; watermark = 64 = half FIFO.
		 */
		watermark = config->burst_elems / 2;
	}

	memset(pdata->ctx, 0, sizeof(*pdata->ctx));
	pdata->ctx->pc = sdma_script_addr;

	if (pdata->sdma_chan_type == SDMA_CHAN_TYPE_AP2AP) {
		/* ap_2_ap ROM script takes NO context parameters per
		 * i.MX8MP TRM: source/dest come from BD.buf_addr /
		 * BD.buf_xaddr. Context is already memset to 0 above.
		 */
	} else {
		if (pdata->hw_event != -1) {
			if (pdata->hw_event >= 32)
				pdata->ctx->g_reg[0] |= BIT(pdata->hw_event - 32);
			else
				pdata->ctx->g_reg[1] |= BIT(pdata->hw_event);
		}
		pdata->ctx->g_reg[6] = pdata->fifo_paddr;
		pdata->ctx->g_reg[7] = watermark;
	}

	dcache_writeback_region(pdata->desc, sizeof(pdata->desc));
	dcache_writeback_region(pdata->ccb, sizeof(*pdata->ccb));
	dcache_writeback_region(pdata->ctx,  sizeof(*pdata->ctx));

	return 0;
}

static int sdma_set_config(struct dma_chan_data *channel,
			   struct dma_sg_config *config)
{
	struct sdma_chan *pdata = dma_chan_get_data(channel);
	int ret;

	tr_dbg(&sdma_tr, "sdma_set_config channel %d", channel->index);

	/* DIAG E6.b: log config for chan 6 (SAI TX). Once-only.
	 * 0x630: chan 6 entry magic 0xC06FA1C0
	 * 0x634: cyclic flag, 0x638: irq_disabled flag, 0x63C: elem count
	 * 0x640: chan_type (AP2AP=2 etc), 0x644: direction
	 * 0x648: src_width, 0x64C: dest_width
	 * 0x650: first BD config (after sdma_prep_desc)
	 * 0x654: last BD config (after sdma_prep_desc)
	 */
	if (channel->index == 6) {
		mailbox_sw_reg_write(0x630, 0xC06FA1C0);
		mailbox_sw_reg_write(0x634, (uint32_t)config->cyclic);
		mailbox_sw_reg_write(0x638, (uint32_t)config->irq_disabled);
		mailbox_sw_reg_write(0x63C, (uint32_t)config->elem_array.count);
		mailbox_sw_reg_write(0x640, (uint32_t)pdata->sdma_chan_type);
		mailbox_sw_reg_write(0x644, (uint32_t)config->direction);
		mailbox_sw_reg_write(0x648, (uint32_t)config->src_width);
		mailbox_sw_reg_write(0x64C, (uint32_t)config->dest_width);
	}

	/* DIAG E6.b ph2: per-channel set_config trace.
	 * 0x780-0x79C : per-chan set_config counter (chan 0..7)
	 * 0x7A0-0x7BC : per-chan last direction
	 * 0x7C0       : last (chan_idx << 8) | direction at any set_config
	 */
	{
		static volatile uint32_t dbg_setcfg[8];
		static volatile uint32_t dbg_dir[8];
		if (channel->index < 8) {
			dbg_setcfg[channel->index]++;
			dbg_dir[channel->index] = (uint32_t)config->direction;
			mailbox_sw_reg_write(0x780 + channel->index * 4,
					     dbg_setcfg[channel->index]);
			mailbox_sw_reg_write(0x7A0 + channel->index * 4,
					     dbg_dir[channel->index]);
		}
		mailbox_sw_reg_write(0x7C0,
				     ((uint32_t)channel->index << 8) |
				     ((uint32_t)config->direction & 0xff));
	}

	ret = sdma_read_config(channel, config);
	if (ret < 0)
		return ret;

	channel->is_scheduling_source = config->is_scheduling_source;
	channel->direction = config->direction;

	ret = sdma_prep_desc(channel, config);
	if (ret < 0)
		return ret;

	/* DIAG E6.b: read first/last BD config after prep_desc for chan 6 */
	if (channel->index == 6 && pdata->desc_count > 0) {
		mailbox_sw_reg_write(0x650, (uint32_t)pdata->desc[0].config);
		mailbox_sw_reg_write(0x654,
			(uint32_t)pdata->desc[pdata->desc_count - 1].config);
	}

	/* AP2AP is software-triggered (no HW event). The SDMA runnability
	 * formula (TRM §7.2) requires (event_pending OR EVTOVR) to be true.
	 * With no event mapped in CHNENBL for AP2AP, event_pending=0 forever,
	 * so we MUST set EVTOVR=1 otherwise HSTART is ignored and the channel
	 * never runs. Same pattern as sdma_run_c0() for channel 0.
	 * DAI channels keep (false, false) to let the peripheral event drive
	 * the transfer.
	 */
	if (pdata->sdma_chan_type == SDMA_CHAN_TYPE_AP2AP)
		sdma_set_overrides(channel, true, false);
	else
		sdma_set_overrides(channel, false, false);

	/* Upload context */
	ret = sdma_upload_context(channel);
	if (ret < 0) {
		tr_err(&sdma_tr, "Unable to upload context, bailing");
		return ret;
	}

	tr_dbg(&sdma_tr, "SDMA context uploaded");
	/* Context uploaded, we can set up events now */
	sdma_enable_event(channel, pdata->hw_event);

	/* Finally set channel priority */
	dma_reg_write(channel->dma, SDMA_CHNPRI(channel->index), SDMA_DEFPRI);

	channel->status = COMP_STATE_PREPARE;

	/* AP2AP: do NOT auto-start here. sdma_copy() kicks the channel
	 * itself and waits synchronously for DONE (see the AP2AP branch
	 * there). Starting in set_config AND again in copy would cause
	 * the transfer to run twice on every period.
	 */

	return 0;
}

static int sdma_interrupt(struct dma_chan_data *channel, enum dma_irq_cmd cmd)
{
	if (!channel->index)
		return 0;

	switch (cmd) {
	case DMA_IRQ_STATUS_GET:
		/* Any nonzero value means interrupt is active */
		return dma_reg_read(channel->dma, SDMA_INTR) &
			BIT(channel->index);
	case DMA_IRQ_CLEAR:
		dma_reg_write(channel->dma, SDMA_INTR, BIT(channel->index));
		return 0;
	case DMA_IRQ_MASK:
	case DMA_IRQ_UNMASK:
		/* We cannot control interrupts except by resetting channel to
		 * have it reread the buffer descriptors. That cannot be done
		 * in the context where this function is called. Silently ignore
		 * requests to mask/unmask per-channel interrupts.
		 */
		return 0;
	default:
		tr_err(&sdma_tr, "sdma_interrupt unknown cmd %d", cmd);
		return -EINVAL;
	}
}

static int sdma_get_attribute(struct dma *dma, uint32_t type, uint32_t *value)
{
	switch (type) {
	case DMA_ATTR_BUFFER_ALIGNMENT:
	case DMA_ATTR_COPY_ALIGNMENT:
		/* Use a conservative value, because some scripts
		 * require an alignment of 4 while others can read
		 * unaligned data. Account for those which require
		 * aligned data.
		 */
		*value = 4;
		break;
	case DMA_ATTR_BUFFER_ADDRESS_ALIGNMENT:
		*value = PLATFORM_DCACHE_ALIGN;
		break;
	case DMA_ATTR_BUFFER_PERIOD_COUNT:
		*value = SDMA_BUFFER_PERIOD_COUNT;
		break;
	default:
		return -ENOENT; /* Attribute not found */
	}

	return 0;
}

static int sdma_get_data_size(struct dma_chan_data *channel, uint32_t *avail,
			      uint32_t *free)
{
	struct sdma_chan *pdata = dma_chan_get_data(channel);
	uint32_t result_data;

	tr_dbg(&sdma_tr, "sdma_get_data_size(%d)", channel->index);
	if (channel->index == 0) {
		*avail = *free = 0;
		return -EINVAL;
	}

	/* SDMA hardware writes the BD (clears DONE, updates count) via
	 * the DDR bus, bypassing the DSP L1 cache. Invalidate before
	 * reading so we observe the current hardware state, not a stale
	 * cache line — otherwise dai_common_copy() receives a stale
	 * free/avail and may compute copy_bytes=0, causing the DAI to
	 * replay the same dma_buffer content for multiple periods.
	 */
	dcache_invalidate_region(&pdata->desc[pdata->current_bd],
				 sizeof(pdata->desc[pdata->current_bd]));

	/* Always exactly 1 period, tracked by current_bd */
	result_data = pdata->desc[pdata->current_bd].config &
		      SDMA_BD_COUNT_MASK;


	*avail = *free = 0;
	switch (channel->direction) {
	case DMA_DIR_MEM_TO_DEV:
		*free = result_data;
		break;
	case DMA_DIR_DEV_TO_MEM:
		*avail = result_data;
		break;
	case DMA_DIR_MEM_TO_MEM:
	case DMA_DIR_HMEM_TO_LMEM:
	case DMA_DIR_LMEM_TO_HMEM:
		/* AP2AP: the period size stored in the BD count applies to
		 * both sides of the transfer (input to produce, output to
		 * consume).
		 */
		*avail = result_data;
		*free = result_data;
		break;
	default:
		tr_err(&sdma_tr, "sdma_get_data_size channel invalid direction");
		return -EINVAL;
	}
	return 0;
}

const struct dma_ops sdma_ops = {
	.channel_get	= sdma_channel_get,
	.channel_put	= sdma_channel_put,
	.start		= sdma_start,
	.stop		= sdma_stop,
	.pause		= sdma_pause,
	.release	= sdma_release,
	.copy		= sdma_copy,
	.status		= sdma_status,
	.set_config	= sdma_set_config,
	.probe		= sdma_probe,
	.remove		= sdma_remove,
	.interrupt	= sdma_interrupt,
	.get_attribute	= sdma_get_attribute,
	.get_data_size	= sdma_get_data_size,
};

/* ============================================================
 * memcpy_dma — the single SDMA-backed memcpy primitive.
 *
 * Every hardware-accelerated memory-to-memory transfer in SOF on
 * i.MX8MP flows through this function: audio_stream_copy (DSP-local
 * buffers) and sdma_copy() for DMA_DIR_*_MEM directions (host payload)
 * both call memcpy_dma() to perform the actual copy.
 *
 * Implementation lives in sdma.c because it needs direct access to
 * the channel's sdma_bd / sdma_chan internals — public DMA framework
 * calls would loop back through sdma_copy.
 *
 * Cache maintenance:
 *   - src+dst are written back before the kick so the SDMA bus master
 *     reads the freshest DSP-L1 data.
 *   - dst is invalidated after completion so the DSP reloads the
 *     newly-written DDR data on the next read.
 *
 * A short spinlock serialises callers of the shared primitive. A
 * small-size fallback (MEMCPY_DMA_MIN_BYTES) skips the hardware path
 * when setup overhead exceeds the cost of a CPU memcpy.
 * ============================================================ */

static struct memcpy_dma_ctx {
	struct dma *dmac;
	struct dma_chan_data *chan;
	struct sdma_chan *pdata;
	struct k_spinlock lock;
	bool ready;
} g_memcpy;

int memcpy_dma_init(void)
{
	struct dma_sg_elem elem;
	struct dma_sg_config cfg;
	int ret;

	if (g_memcpy.ready)
		return 0;

	k_spinlock_init(&g_memcpy.lock);

	g_memcpy.dmac = dma_get(DMA_DIR_MEM_TO_MEM, 0, DMA_DEV_HOST,
				DMA_ACCESS_SHARED);
	if (!g_memcpy.dmac) {
		tr_err(&sdma_tr, "memcpy_dma_init: no MEM_TO_MEM dmac");
		return -ENODEV;
	}

	g_memcpy.chan = dma_channel_get_legacy(g_memcpy.dmac, 0);
	if (!g_memcpy.chan) {
		tr_err(&sdma_tr, "memcpy_dma_init: no channel");
		return -ENODEV;
	}

	/* Configure the channel with placeholder AP2AP BDs. sdma_prep_desc
	 * sets the script address, flags (EXTD|DONE|LAST|WRAP) and command;
	 * memcpy_dma() reuses this setup and only rewrites buf_addr /
	 * buf_xaddr / count on each call.
	 */
	elem.src = 0;
	elem.dest = 0;
	elem.size = 4;

	memset(&cfg, 0, sizeof(cfg));
	cfg.direction = DMA_DIR_MEM_TO_MEM;
	cfg.src_width = 4;
	cfg.dest_width = 4;
	cfg.cyclic = 0;
	cfg.irq_disabled = true;
	cfg.elem_array.elems = &elem;
	cfg.elem_array.count = 1;

	ret = dma_set_config_legacy(g_memcpy.chan, &cfg);
	if (ret < 0) {
		tr_err(&sdma_tr, "memcpy_dma_init: set_config failed %d",
		       ret);
		dma_channel_put_legacy(g_memcpy.chan);
		g_memcpy.chan = NULL;
		return ret;
	}

	g_memcpy.pdata = dma_chan_get_data(g_memcpy.chan);
	g_memcpy.ready = true;
	tr_info(&sdma_tr, "memcpy_dma ready (chan=%d)", g_memcpy.chan->index);
	return 0;
}

void *memcpy_dma(void *dst, const void *src, size_t bytes)
{
	struct sdma_bd *bd;
	k_spinlock_key_t key;
	int timeout_us;

	if (!bytes)
		return dst;

	/* Small-size fallback: the SDMA setup + double cache maintenance
	 * costs more than a direct CPU copy below this threshold.
	 */
	if (!g_memcpy.ready || bytes < MEMCPY_DMA_MIN_BYTES)
		return memcpy(dst, src, bytes);

	/* Flush both src and dst to DDR so the SDMA bus master sees
	 * a consistent view (no stale dirty lines hiding in DSP L1).
	 */
	dcache_writeback_region((void *)src, bytes);
	dcache_writeback_region(dst, bytes);

	key = k_spin_lock(&g_memcpy.lock);

	bd = &g_memcpy.pdata->desc[0];
	bd->buf_addr = (uint32_t)(uintptr_t)src;
	bd->buf_xaddr = (uint32_t)(uintptr_t)dst;
	bd->config = (bd->config & ~SDMA_BD_COUNT_MASK) | SDMA_BD_COUNT(bytes);
	bd->config |= SDMA_BD_DONE;
	dcache_writeback_region(bd, sizeof(*bd));

	sdma_enable_channel(g_memcpy.chan->dma, g_memcpy.chan->index);

	/* Poll BD.DONE. 2 ms is ~200x the expected worst case
	 * (48 KB @ ~200 MB/s effective SDMA bandwidth ~= 250 us).
	 */
	timeout_us = 2000;
	while (timeout_us--) {
		dcache_invalidate_region(&bd->config, sizeof(bd->config));
		if (!(bd->config & SDMA_BD_DONE))
			break;
		wait_delay_us(1);
	}

	k_spin_unlock(&g_memcpy.lock, key);

	if (timeout_us <= 0) {
		tr_err(&sdma_tr, "memcpy_dma timeout dst=0x%p src=0x%p n=%u",
		       dst, src, (unsigned int)bytes);
		sdma_disable_channel(g_memcpy.chan->dma, g_memcpy.chan->index);
		return memcpy(dst, src, bytes);
	}

	/* dst was written by the SDMA bus bypassing the DSP cache —
	 * invalidate so subsequent DSP reads pull the fresh data.
	 */
	dcache_invalidate_region(dst, bytes);
	return dst;
}
