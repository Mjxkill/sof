// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright(c) 2026 Electrosens. All rights reserved.
//
// V5.4.1 Phase 1a.3 E6.b — matrix_2x8 native 8-channel matrix mixer.
//
// SOURCE_SINK mode: 2 sources × 8ch interleaved -> 1 sink × 8ch interleaved.
// Per-cell Q1.31 gains (128 cells = 512 B ALSA bytes blob).
//
//   sink[frame][j] = sat32( SUM_{s=0..1, ch=0..7} src[s][frame][ch] * gain[s*8+ch][j] )
//
// Identity init: source 0 channel i (asio play) passes through to sink channel i;
// source 1 (mics) muted (gain=0). User can diverge via amixer cset.

#include <sof/audio/component.h>
#include <sof/audio/data_blob.h>
#include <sof/audio/format.h>
#include <sof/audio/module_adapter/module/generic.h>
#include <sof/audio/sink_api.h>
#include <sof/audio/source_api.h>
#include <sof/lib/uuid.h>
#include <sof/list.h>
#include <sof/trace/trace.h>
#include <ipc/topology.h>
#include <rtos/init.h>
#include <rtos/alloc.h>
#include <stddef.h>
#include <stdint.h>
#include <errno.h>
#include <limits.h>

#include "matrix_2x8.h"

LOG_MODULE_REGISTER(matrix_2x8, CONFIG_SOF_LOG_LEVEL);

/* a3c7e012-4f29-4d8b-9e15-7a6c8b3d2f01 */
DECLARE_SOF_RT_UUID("matrix_2x8", matrix_2x8_uuid, 0xa3c7e012, 0x4f29, 0x4d8b,
		    0x9e, 0x15, 0x7a, 0x6c, 0x8b, 0x3d, 0x2f, 0x01);

DECLARE_TR_CTX(matrix_2x8_tr, SOF_UUID(matrix_2x8_uuid), LOG_LEVEL_INFO);

struct matrix_2x8_runtime {
	struct matrix_2x8_gains gains;
	struct comp_data_blob_handler *blob_handler;
};

static void matrix_2x8_set_identity(struct matrix_2x8_gains *g)
{
	int i, j;

	for (i = 0; i < MATRIX_2X8_TOTAL_INPUTS; i++)
		for (j = 0; j < MATRIX_2X8_OUT_CHANNELS; j++)
			g->gain[i][j] = (i < MATRIX_2X8_OUT_CHANNELS && i == j) ?
					INT32_MAX : 0;
}

static int matrix_2x8_init(struct processing_module *mod)
{
	struct matrix_2x8_runtime *rt;
	int ret;

	rt = rzalloc(SOF_MEM_ZONE_RUNTIME, 0, SOF_MEM_CAPS_RAM, sizeof(*rt));
	if (!rt)
		return -ENOMEM;

	matrix_2x8_set_identity(&rt->gains);

	rt->blob_handler = comp_data_blob_handler_new(mod->dev);
	if (!rt->blob_handler) {
		comp_err(mod->dev, "matrix_2x8_init: blob handler alloc failed");
		rfree(rt);
		return -ENOMEM;
	}

	ret = comp_init_data_blob(rt->blob_handler,
				  sizeof(struct matrix_2x8_gains),
				  &rt->gains);
	if (ret < 0) {
		comp_err(mod->dev, "matrix_2x8_init: comp_init_data_blob failed");
		comp_data_blob_handler_free(rt->blob_handler);
		rfree(rt);
		return ret;
	}

	module_set_private_data(mod, rt);
	mod->max_sources = MATRIX_2X8_MAX_SOURCES;
	mod->max_sinks = MATRIX_2X8_MAX_SINKS;

	comp_info(mod->dev,
		  "matrix_2x8_init: V5.4.1 E6.b — 2 sources x 8ch -> 1 sink x 8ch, identity matrix");
	return 0;
}

static int matrix_2x8_prepare(struct processing_module *mod,
			      struct sof_source **sources, int num_of_sources,
			      struct sof_sink **sinks, int num_of_sinks)
{
	struct comp_dev *dev = mod->dev;
	struct list_item *blist;
	struct comp_buffer *buf;

	comp_dbg(dev, "matrix_2x8_prepare: sources=%d sinks=%d",
		 num_of_sources, num_of_sinks);
	mod->max_sources = MATRIX_2X8_MAX_SOURCES;
	mod->max_sinks = MATRIX_2X8_MAX_SINKS;

	/* All buffers stay 8ch. Override the F++ auto-detection lock that fires
	 * on multi-source comps: pipeline_lock_branched would otherwise force
	 * channels=1 + preserve_channels=true on our 2 sources. We re-set 8ch
	 * here and clear preserve_channels so subsequent buffer_set_params
	 * calls don't restore the wrong saved value.
	 */
	list_for_item(blist, &dev->bsource_list) {
		buf = container_of(blist, struct comp_buffer, sink_list);
		audio_stream_set_channels(&buf->stream, MATRIX_2X8_OUT_CHANNELS);
		buf->preserve_channels = false;
	}
	list_for_item(blist, &dev->bsink_list) {
		buf = container_of(blist, struct comp_buffer, source_list);
		audio_stream_set_channels(&buf->stream, MATRIX_2X8_OUT_CHANNELS);
		buf->preserve_channels = false;
	}
	return 0;
}

static int matrix_2x8_set_config(struct processing_module *mod, uint32_t param_id,
				 enum module_cfg_fragment_position pos,
				 uint32_t data_offset_size, const uint8_t *fragment,
				 size_t fragment_size, uint8_t *response,
				 size_t response_size)
{
	struct matrix_2x8_runtime *rt = module_get_private_data(mod);

	return comp_data_blob_set(rt->blob_handler, pos, data_offset_size,
				  fragment, fragment_size);
}

static int matrix_2x8_get_config(struct processing_module *mod,
				 uint32_t config_id, uint32_t *data_offset_size,
				 uint8_t *fragment, size_t fragment_size)
{
	struct matrix_2x8_runtime *rt = module_get_private_data(mod);
	struct sof_ipc_ctrl_data *cdata = (struct sof_ipc_ctrl_data *)fragment;

	return comp_data_blob_get_cmd(rt->blob_handler, cdata, fragment_size);
}

/*
 * Process loop — 2 sources × 8ch interleaved -> 1 sink × 8ch interleaved.
 * For each frame, each output channel j is the Q1.31-weighted sum of the 16
 * input channels (8 from src 0 + 8 from src 1).
 */
static int matrix_2x8_process(struct processing_module *mod,
			      struct sof_source **sources, int num_of_sources,
			      struct sof_sink **sinks, int num_of_sinks)
{
	struct matrix_2x8_runtime *rt = module_get_private_data(mod);
	uint32_t min_frames = UINT32_MAX;
	uint32_t free_frames;
	uint32_t avail_frames;
	const int32_t *src_data[MATRIX_2X8_MAX_SOURCES];
	int32_t *sink_data;
	const void *src_ptr[MATRIX_2X8_MAX_SOURCES];
	const void *src_start[MATRIX_2X8_MAX_SOURCES];
	size_t src_size[MATRIX_2X8_MAX_SOURCES];
	void *sink_ptr;
	void *sink_start;
	size_t sink_size;
	int32_t (*gain)[MATRIX_2X8_OUT_CHANNELS];
	int s, i, j, frame, ret;
	int32_t sample;
	int64_t acc;

	/* Refresh gains if a new blob was uploaded */
	if (comp_is_new_data_blob_available(rt->blob_handler)) {
		struct matrix_2x8_gains *g =
			comp_get_data_blob(rt->blob_handler, NULL, NULL);
		if (g)
			rt->gains = *g;
	}
	gain = rt->gains.gain;

	if (num_of_sources <= 0 || num_of_sources > MATRIX_2X8_MAX_SOURCES)
		return -EINVAL;
	if (num_of_sinks != MATRIX_2X8_MAX_SINKS)
		return -EINVAL;

	/* min_frames over sources + sinks (8ch interleaved) */
	for (s = 0; s < num_of_sources; s++) {
		avail_frames = source_get_data_frames_available(sources[s]);
		if (avail_frames < min_frames)
			min_frames = avail_frames;
	}
	free_frames = sink_get_free_frames(sinks[0]);
	if (free_frames < min_frames)
		min_frames = free_frames;

	if (min_frames == 0 || min_frames == UINT32_MAX)
		return 0;

	/* Acquire pointers — 8ch interleaved means min_frames * 8 * sizeof(int32_t) bytes */
	for (s = 0; s < num_of_sources; s++) {
		ret = source_get_data(sources[s],
				      min_frames * MATRIX_2X8_OUT_CHANNELS * sizeof(int32_t),
				      &src_ptr[s], &src_start[s], &src_size[s]);
		if (ret) {
			while (--s >= 0)
				source_release_data(sources[s], 0);
			return -ENODATA;
		}
		src_data[s] = (const int32_t *)src_ptr[s];
	}
	ret = sink_get_buffer(sinks[0],
			      min_frames * MATRIX_2X8_OUT_CHANNELS * sizeof(int32_t),
			      &sink_ptr, &sink_start, &sink_size);
	if (ret) {
		for (s = 0; s < num_of_sources; s++)
			source_release_data(sources[s], 0);
		return -ENODATA;
	}
	sink_data = (int32_t *)sink_ptr;

	/*
	 * Mix loop. For each frame and each output channel j, sum over all 16
	 * inputs (8 channels × num_of_sources) with the Q1.31 gain matrix.
	 * num_of_sources < MAX is supported (single-source isolation test, etc.):
	 * inputs from missing sources contribute 0 implicitly.
	 */
	for (frame = 0; frame < (int)min_frames; frame++) {
		for (j = 0; j < MATRIX_2X8_OUT_CHANNELS; j++) {
			acc = 0;
			for (s = 0; s < num_of_sources; s++) {
				for (i = 0; i < MATRIX_2X8_OUT_CHANNELS; i++) {
					sample = src_data[s][frame * MATRIX_2X8_OUT_CHANNELS + i];
					acc += ((int64_t)sample *
						gain[s * MATRIX_2X8_OUT_CHANNELS + i][j]) >> 31;
				}
			}
			if (acc > INT32_MAX)
				sink_data[frame * MATRIX_2X8_OUT_CHANNELS + j] = INT32_MAX;
			else if (acc < INT32_MIN)
				sink_data[frame * MATRIX_2X8_OUT_CHANNELS + j] = INT32_MIN;
			else
				sink_data[frame * MATRIX_2X8_OUT_CHANNELS + j] = (int32_t)acc;
		}
	}

	sink_commit_buffer(sinks[0],
			   min_frames * MATRIX_2X8_OUT_CHANNELS * sizeof(int32_t));
	for (s = 0; s < num_of_sources; s++)
		source_release_data(sources[s],
				    min_frames * MATRIX_2X8_OUT_CHANNELS * sizeof(int32_t));

	return 0;
}

static int matrix_2x8_trigger(struct processing_module *mod, int cmd)
{
	struct list_item *li;
	struct comp_buffer *b;

	/* Cross-pipeline source 1 (mics tap from PIPE 1): foreign pipeline may
	 * not start synchronously with ours. Set underrun_permitted on cross-
	 * pipeline source-side buffers so source_get_data_frames_available
	 * reports stream->size instead of 0 when avail==0 — prevents min_frames=0
	 * stalling SAI TX during boot transient. Symmetric counterpart to the
	 * overrun_permitted pattern used by tee_1to2/deinterleave_8 on sinks.
	 */
	if (cmd == COMP_TRIGGER_PRE_START) {
		list_for_item(li, &mod->dev->bsource_list) {
			b = container_of(li, struct comp_buffer, sink_list);
			if (b->source && b->source->pipeline != mod->dev->pipeline)
				audio_stream_set_underrun(&b->stream, true);
		}
	}
	return module_adapter_set_state(mod, mod->dev, cmd);
}

static int matrix_2x8_reset(struct processing_module *mod)
{
	comp_dbg(mod->dev, "matrix_2x8_reset()");
	return 0;
}

static int matrix_2x8_free(struct processing_module *mod)
{
	struct matrix_2x8_runtime *rt = module_get_private_data(mod);

	if (rt) {
		if (rt->blob_handler)
			comp_data_blob_handler_free(rt->blob_handler);
		rfree(rt);
	}
	comp_dbg(mod->dev, "matrix_2x8_free()");
	return 0;
}

static const struct module_interface matrix_2x8_interface = {
	.init = matrix_2x8_init,
	.prepare = matrix_2x8_prepare,
	.process = matrix_2x8_process,
	.set_configuration = matrix_2x8_set_config,
	.get_configuration = matrix_2x8_get_config,
	.trigger = matrix_2x8_trigger,
	.reset = matrix_2x8_reset,
	.free = matrix_2x8_free,
};

DECLARE_MODULE_ADAPTER(matrix_2x8_interface, matrix_2x8_uuid, matrix_2x8_tr);
SOF_MODULE_INIT(matrix_2x8, sys_comp_module_matrix_2x8_interface_init);
