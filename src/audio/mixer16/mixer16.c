// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright(c) 2026 Electrosens. All rights reserved.
//
// V5.4.1 Phase 1a.3 — mixer16 16x8 matrix component skeleton (E1).
//
// SOURCE_SINK mode (proc_type=SOURCE_SINK), max_sources=16, max_sinks=8.
// E1 = skeleton (passthrough through sink[0] only). E2 = full mix loop with
// per-cell Q1.31 gains and 128-cell bytes blob ALSA control.

#include <sof/audio/component.h>
#include <sof/audio/format.h>
#include <sof/audio/module_adapter/module/generic.h>
#include <sof/audio/sink_api.h>
#include <sof/audio/source_api.h>
#include <sof/lib/uuid.h>
#include <sof/trace/trace.h>
#include <ipc/topology.h>
#include <rtos/init.h>
#include <rtos/alloc.h>
#include <stddef.h>
#include <stdint.h>

#include "mixer16.h"

LOG_MODULE_REGISTER(mixer16, CONFIG_SOF_LOG_LEVEL);

/* d2e64a00-e3b6-4dca-bd83-09e8aae6e1f7 */
DECLARE_SOF_RT_UUID("mixer16", mixer16_uuid, 0xd2e64a00, 0xe3b6, 0x4dca,
		    0xbd, 0x83, 0x09, 0xe8, 0xaa, 0xe6, 0xe1, 0xf7);

DECLARE_TR_CTX(mixer16_tr, SOF_UUID(mixer16_uuid), LOG_LEVEL_INFO);

static int mixer16_init(struct processing_module *mod)
{
	struct mixer16_cd *cd;

	cd = rzalloc(SOF_MEM_ZONE_RUNTIME, 0, SOF_MEM_CAPS_RAM, sizeof(*cd));
	if (!cd)
		return -ENOMEM;

	module_set_private_data(mod, cd);
	mod->max_sources = MIXER16_MAX_SOURCES;
	mod->max_sinks = MIXER16_MAX_SINKS;

	comp_dbg(mod->dev, "mixer16_init() — V5.4.1 skeleton");
	return 0;
}

static int mixer16_prepare(struct processing_module *mod,
			   struct sof_source **sources, int num_of_sources,
			   struct sof_sink **sinks, int num_of_sinks)
{
	comp_dbg(mod->dev, "mixer16_prepare() — sources=%d sinks=%d",
		 num_of_sources, num_of_sinks);
	mod->max_sources = MIXER16_MAX_SOURCES;
	mod->max_sinks = MIXER16_MAX_SINKS;
	return 0;
}

/* E1 stub — no actual mix, just returns 0. E2 will implement the
 * 16-source x 8-sink Q1.31 mix loop here.
 */
static int mixer16_process(struct processing_module *mod,
			   struct sof_source **sources, int num_of_sources,
			   struct sof_sink **sinks, int num_of_sinks)
{
	(void)sources;
	(void)sinks;
	(void)num_of_sources;
	(void)num_of_sinks;
	return 0;
}

static int mixer16_reset(struct processing_module *mod)
{
	comp_dbg(mod->dev, "mixer16_reset()");
	return 0;
}

static int mixer16_free(struct processing_module *mod)
{
	struct mixer16_cd *cd = module_get_private_data(mod);

	if (cd)
		rfree(cd);

	comp_dbg(mod->dev, "mixer16_free()");
	return 0;
}

static const struct module_interface mixer16_interface = {
	.init = mixer16_init,
	.prepare = mixer16_prepare,
	.process = mixer16_process,
	.reset = mixer16_reset,
	.free = mixer16_free,
};

DECLARE_MODULE_ADAPTER(mixer16_interface, mixer16_uuid, mixer16_tr);
SOF_MODULE_INIT(mixer16, sys_comp_module_mixer16_interface_init);
