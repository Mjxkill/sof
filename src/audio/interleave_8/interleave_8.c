// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright(c) 2026 Electrosens. All rights reserved.
//
// V5.4.1 Phase 1a.3 — interleave_8 component (E2 process).
//
// SOURCE_SINK mode: 8 mono S32_LE sources -> 1 sink 8ch S32_LE interleaved.
//
//   sink_buf[frame*8 + ch] = source_buf[ch][frame]
//
// Required for V5.4.1 chain end (8 strips OUT mono -> SAI7 TX 8ch).
// NPU tap V3.2.2 invariance: period_bytes = 96 frames * 8 ch * 4 B = 3072.

#include <sof/audio/component.h>
#include <sof/audio/format.h>
#include <sof/audio/module_adapter/module/generic.h>
#include <sof/audio/sink_api.h>
#include <sof/audio/source_api.h>
#include <sof/lib/uuid.h>
#include <sof/list.h>
#include <sof/trace/trace.h>
#include <ipc/topology.h>
#include <rtos/init.h>
#include <stddef.h>
#include <stdint.h>
#include <errno.h>
#include <limits.h>

LOG_MODULE_REGISTER(interleave_8, CONFIG_SOF_LOG_LEVEL);

/* c8a3b500-5b95-4cb1-a91c-5a72fa4e9c5e */
DECLARE_SOF_RT_UUID("interleave_8", interleave_8_uuid, 0xc8a3b500, 0x5b95, 0x4cb1,
		    0xa9, 0x1c, 0x5a, 0x72, 0xfa, 0x4e, 0x9c, 0x5e);

DECLARE_TR_CTX(interleave_8_tr, SOF_UUID(interleave_8_uuid), LOG_LEVEL_INFO);

#define INTERLEAVE_8_MAX_SOURCES 8
#define INTERLEAVE_8_OUT_CHANNELS 8
#define INTERLEAVE_8_SAMPLE_BYTES sizeof(int32_t)

static int interleave_8_init(struct processing_module *mod)
{
	mod->max_sources = INTERLEAVE_8_MAX_SOURCES;
	mod->max_sinks = 1;
	comp_info(mod->dev, "interleave_8_init: V5.4.1 E2 — 8 mono -> 1x8ch");
	return 0;
}

static int interleave_8_prepare(struct processing_module *mod,
				struct sof_source **sources, int num_of_sources,
				struct sof_sink **sinks, int num_of_sinks)
{
	struct comp_dev *dev = mod->dev;
	struct list_item *blist;
	struct comp_buffer *buf;

	comp_dbg(dev, "interleave_8_prepare: sources=%d sinks=%d",
		 num_of_sources, num_of_sinks);
	mod->max_sources = INTERLEAVE_8_MAX_SOURCES;
	mod->max_sinks = 1;

	list_for_item(blist, &dev->bsource_list) {
		buf = container_of(blist, struct comp_buffer, sink_list);
		audio_stream_set_channels(&buf->stream, 1);
	}
	list_for_item(blist, &dev->bsink_list) {
		buf = container_of(blist, struct comp_buffer, source_list);
		audio_stream_set_channels(&buf->stream, INTERLEAVE_8_OUT_CHANNELS);
	}
	return 0;
}

static int interleave_8_process(struct processing_module *mod,
				struct sof_source **sources, int num_of_sources,
				struct sof_sink **sinks, int num_of_sinks)
{
	uint32_t min_frames = UINT32_MAX;
	uint32_t avail_frames, free_frames;
	const int32_t *src_data[INTERLEAVE_8_MAX_SOURCES];
	int32_t *sink_data;
	const void *src_ptr[INTERLEAVE_8_MAX_SOURCES];
	const void *src_start[INTERLEAVE_8_MAX_SOURCES];
	size_t src_size[INTERLEAVE_8_MAX_SOURCES];
	void *sink_ptr;
	void *sink_start;
	size_t sink_size;
	uint32_t frame;
	int ch, i, ret;

	if (num_of_sources <= 0 || num_of_sources > INTERLEAVE_8_MAX_SOURCES)
		return -EINVAL;
	if (num_of_sinks != 1)
		return -EINVAL;

	/* Compute min_frames */
	for (i = 0; i < num_of_sources; i++) {
		avail_frames = source_get_data_frames_available(sources[i]);
		if (avail_frames < min_frames)
			min_frames = avail_frames;
	}
	free_frames = sink_get_free_frames(sinks[0]);
	if (free_frames < min_frames)
		min_frames = free_frames;

	if (min_frames == 0 || min_frames == UINT32_MAX)
		return 0;

	/* Acquire pointers */
	for (i = 0; i < num_of_sources; i++) {
		ret = source_get_data(sources[i], min_frames * INTERLEAVE_8_SAMPLE_BYTES,
				      &src_ptr[i], &src_start[i], &src_size[i]);
		if (ret) {
			while (--i >= 0)
				source_release_data(sources[i], 0);
			return -ENODATA;
		}
		src_data[i] = (const int32_t *)src_ptr[i];
	}

	ret = sink_get_buffer(sinks[0], min_frames * INTERLEAVE_8_OUT_CHANNELS *
			      INTERLEAVE_8_SAMPLE_BYTES,
			      &sink_ptr, &sink_start, &sink_size);
	if (ret) {
		for (i = 0; i < num_of_sources; i++)
			source_release_data(sources[i], 0);
		return -ENODATA;
	}
	sink_data = (int32_t *)sink_ptr;

	/* Memcpy stride: dst[frame*8 + ch] = src[ch][frame].
	 * Channels beyond num_of_sources are zero-padded.
	 */
	for (frame = 0; frame < min_frames; frame++) {
		for (ch = 0; ch < INTERLEAVE_8_OUT_CHANNELS; ch++) {
			sink_data[frame * INTERLEAVE_8_OUT_CHANNELS + ch] =
				(ch < num_of_sources) ? src_data[ch][frame] : 0;
		}
	}

	sink_commit_buffer(sinks[0], min_frames * INTERLEAVE_8_OUT_CHANNELS *
			   INTERLEAVE_8_SAMPLE_BYTES);
	for (i = 0; i < num_of_sources; i++)
		source_release_data(sources[i], min_frames * INTERLEAVE_8_SAMPLE_BYTES);

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
