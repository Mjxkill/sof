// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright(c) 2026 Electrosens. All rights reserved.
//
// V5.4.1 Phase 1a.3 — deinterleave_8 component (E4 process).
//
// SOURCE_SINK mode: 1 source 8ch S32_LE interleaved -> 8 mono S32_LE sinks.
// Symetric mirror of interleave_8.
//
//   sink_data[ch][frame] = src_data[frame*8 + ch]
//
// Used to split SAI7 RX 8ch into 8 mono streams for input strip routing
// (8 strips IN avec controls indépendants par voie — Phase 1a.3 architecture).

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
#include <errno.h>
#include <limits.h>

LOG_MODULE_REGISTER(deinterleave_8, CONFIG_SOF_LOG_LEVEL);

/* f1a2b3c4-d5e6-4789-abcd-ef0123456789 */
DECLARE_SOF_RT_UUID("deinterleave_8", deinterleave_8_uuid, 0xf1a2b3c4, 0xd5e6, 0x4789,
		    0xab, 0xcd, 0xef, 0x01, 0x23, 0x45, 0x67, 0x89);

DECLARE_TR_CTX(deinterleave_8_tr, SOF_UUID(deinterleave_8_uuid), LOG_LEVEL_INFO);

#define DEINTERLEAVE_8_MAX_SINKS 8
#define DEINTERLEAVE_8_IN_CHANNELS 8
#define DEINTERLEAVE_8_SAMPLE_BYTES sizeof(int32_t)

static int deinterleave_8_init(struct processing_module *mod)
{
	mod->max_sources = 1;
	mod->max_sinks = DEINTERLEAVE_8_MAX_SINKS;
	comp_info(mod->dev, "deinterleave_8_init: V5.4.1 E4 — 1x8ch -> 8 mono");
	return 0;
}

static int deinterleave_8_prepare(struct processing_module *mod,
				  struct sof_source **sources, int num_of_sources,
				  struct sof_sink **sinks, int num_of_sinks)
{
	comp_dbg(mod->dev, "deinterleave_8_prepare: sources=%d sinks=%d",
		 num_of_sources, num_of_sinks);
	mod->max_sources = 1;
	mod->max_sinks = DEINTERLEAVE_8_MAX_SINKS;
	return 0;
}

static int deinterleave_8_process(struct processing_module *mod,
				  struct sof_source **sources, int num_of_sources,
				  struct sof_sink **sinks, int num_of_sinks)
{
	uint32_t min_frames = UINT32_MAX;
	uint32_t avail_frames, free_frames;
	int32_t *sink_data[DEINTERLEAVE_8_MAX_SINKS];
	const int32_t *src_data;
	const void *src_ptr;
	const void *src_start;
	size_t src_size;
	void *sink_ptr[DEINTERLEAVE_8_MAX_SINKS];
	void *sink_start[DEINTERLEAVE_8_MAX_SINKS];
	size_t sink_size[DEINTERLEAVE_8_MAX_SINKS];
	uint32_t frame;
	int ch, j, ret;

	if (num_of_sources != 1)
		return -EINVAL;
	if (num_of_sinks <= 0 || num_of_sinks > DEINTERLEAVE_8_MAX_SINKS)
		return -EINVAL;

	/* Compute min_frames: source is 8ch interleaved so 1 frame = 8 samples */
	avail_frames = source_get_data_frames_available(sources[0]);
	min_frames = avail_frames;

	for (j = 0; j < num_of_sinks; j++) {
		free_frames = sink_get_free_frames(sinks[j]);
		if (free_frames < min_frames)
			min_frames = free_frames;
	}

	if (min_frames == 0 || min_frames == UINT32_MAX)
		return 0;

	/* Acquire source 8ch interleaved buffer */
	ret = source_get_data(sources[0],
			      min_frames * DEINTERLEAVE_8_IN_CHANNELS *
			      DEINTERLEAVE_8_SAMPLE_BYTES,
			      &src_ptr, &src_start, &src_size);
	if (ret)
		return -ENODATA;
	src_data = (const int32_t *)src_ptr;

	/* Acquire 8 mono sink buffers */
	for (j = 0; j < num_of_sinks; j++) {
		ret = sink_get_buffer(sinks[j],
				      min_frames * DEINTERLEAVE_8_SAMPLE_BYTES,
				      &sink_ptr[j], &sink_start[j], &sink_size[j]);
		if (ret) {
			while (--j >= 0)
				sink_commit_buffer(sinks[j], 0);
			source_release_data(sources[0], 0);
			return -ENODATA;
		}
		sink_data[j] = (int32_t *)sink_ptr[j];
	}

	/* Demux: dst[ch][frame] = src[frame*DEINTERLEAVE_8_IN_CHANNELS + ch].
	 * Source channels beyond num_of_sinks are simply discarded (not routed).
	 */
	for (frame = 0; frame < min_frames; frame++) {
		for (ch = 0; ch < num_of_sinks; ch++) {
			sink_data[ch][frame] =
				src_data[frame * DEINTERLEAVE_8_IN_CHANNELS + ch];
		}
	}

	/* Commit / release */
	for (j = 0; j < num_of_sinks; j++)
		sink_commit_buffer(sinks[j], min_frames * DEINTERLEAVE_8_SAMPLE_BYTES);
	source_release_data(sources[0], min_frames * DEINTERLEAVE_8_IN_CHANNELS *
			    DEINTERLEAVE_8_SAMPLE_BYTES);

	return 0;
}

static int deinterleave_8_reset(struct processing_module *mod)
{
	comp_dbg(mod->dev, "deinterleave_8_reset()");
	return 0;
}

static int deinterleave_8_free(struct processing_module *mod)
{
	comp_dbg(mod->dev, "deinterleave_8_free()");
	return 0;
}

static const struct module_interface deinterleave_8_interface = {
	.init = deinterleave_8_init,
	.prepare = deinterleave_8_prepare,
	.process = deinterleave_8_process,
	.reset = deinterleave_8_reset,
	.free = deinterleave_8_free,
};

DECLARE_MODULE_ADAPTER(deinterleave_8_interface, deinterleave_8_uuid, deinterleave_8_tr);
SOF_MODULE_INIT(deinterleave_8, sys_comp_module_deinterleave_8_interface_init);
