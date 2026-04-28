// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright(c) 2026 Electrosens. All rights reserved.
//
// V5.4.1 Phase 1a.3 — interleave_8 component skeleton (E1).
//
// SOURCE_SINK mode (proc_type=SOURCE_SINK), max_sources=8, max_sinks=1.
// Concatenate 8 mono sources -> 1 sink 8ch S32_LE interleaved.
// E1 = skeleton (no actual data movement). E2 = real memcpy stride loop.

#include <sof/audio/component.h>
#include <sof/audio/format.h>
#include <sof/audio/module_adapter/module/generic.h>
#include <sof/audio/sink_api.h>
#include <sof/audio/source_api.h>
#include <sof/lib/uuid.h>
#include <sof/trace/trace.h>
#include <ipc/topology.h>
#include <rtos/init.h>
#include <stddef.h>
#include <stdint.h>

LOG_MODULE_REGISTER(interleave_8, CONFIG_SOF_LOG_LEVEL);

/* c8a3b500-5b95-4cb1-a91c-5a72fa4e9c5e */
DECLARE_SOF_RT_UUID("interleave_8", interleave_8_uuid, 0xc8a3b500, 0x5b95, 0x4cb1,
		    0xa9, 0x1c, 0x5a, 0x72, 0xfa, 0x4e, 0x9c, 0x5e);

DECLARE_TR_CTX(interleave_8_tr, SOF_UUID(interleave_8_uuid), LOG_LEVEL_INFO);

#define INTERLEAVE_8_MAX_SOURCES 8

static int interleave_8_init(struct processing_module *mod)
{
	mod->max_sources = INTERLEAVE_8_MAX_SOURCES;
	mod->max_sinks = 1;
	comp_dbg(mod->dev, "interleave_8_init() — V5.4.1 skeleton");
	return 0;
}

static int interleave_8_prepare(struct processing_module *mod,
				struct sof_source **sources, int num_of_sources,
				struct sof_sink **sinks, int num_of_sinks)
{
	comp_dbg(mod->dev, "interleave_8_prepare() — sources=%d sinks=%d",
		 num_of_sources, num_of_sinks);
	mod->max_sources = INTERLEAVE_8_MAX_SOURCES;
	mod->max_sinks = 1;
	return 0;
}

/* E1 stub — no data movement. E2 will implement the memcpy stride loop:
 *   for (frame=0..n_frames-1) for (ch=0..7) dst[frame*8+ch] = src[ch][frame];
 */
static int interleave_8_process(struct processing_module *mod,
				struct sof_source **sources, int num_of_sources,
				struct sof_sink **sinks, int num_of_sinks)
{
	(void)sources;
	(void)sinks;
	(void)num_of_sources;
	(void)num_of_sinks;
	return 0;
}

static int interleave_8_reset(struct processing_module *mod)
{
	comp_dbg(mod->dev, "interleave_8_reset()");
	return 0;
}

static int interleave_8_free(struct processing_module *mod)
{
	comp_dbg(mod->dev, "interleave_8_free()");
	return 0;
}

static const struct module_interface interleave_8_interface = {
	.init = interleave_8_init,
	.prepare = interleave_8_prepare,
	.process = interleave_8_process,
	.reset = interleave_8_reset,
	.free = interleave_8_free,
};

DECLARE_MODULE_ADAPTER(interleave_8_interface, interleave_8_uuid, interleave_8_tr);
SOF_MODULE_INIT(interleave_8, sys_comp_module_interleave_8_interface_init);
