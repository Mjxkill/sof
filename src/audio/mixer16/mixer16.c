// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright(c) 2026 Electrosens. All rights reserved.
//
// V5.4.1 Phase 1a.3 — mixer16 16x8 matrix component (E2 mix loop).
//
// SOURCE_SINK mode: 16 mono sources -> 8 mono sinks. Per-cell Q1.31 gains
// (128 cells = 512 B ALSA bytes blob). Initial state: identity matrix
// (gain[i][j] = INT32_MAX if i==j and i<8, else 0).
//
//   out_j[n] = sat32( SUM_{i=0..15} ( in_i[n] * gain[i][j] ) >> 31 )

#include <sof/audio/component.h>
#include <sof/audio/data_blob.h>
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
#include <errno.h>
#include <limits.h>

#include "mixer16.h"

LOG_MODULE_REGISTER(mixer16, CONFIG_SOF_LOG_LEVEL);

/* d2e64a00-e3b6-4dca-bd83-09e8aae6e1f7 */
DECLARE_SOF_RT_UUID("mixer16", mixer16_uuid, 0xd2e64a00, 0xe3b6, 0x4dca,
		    0xbd, 0x83, 0x09, 0xe8, 0xaa, 0xe6, 0xe1, 0xf7);

DECLARE_TR_CTX(mixer16_tr, SOF_UUID(mixer16_uuid), LOG_LEVEL_INFO);

/* Runtime data */
struct mixer16_runtime {
	struct mixer16_cell_gains gains;	/* effective Q1.31 gains */
	struct comp_data_blob_handler *blob_handler;
};

static void mixer16_set_identity(struct mixer16_cell_gains *g)
{
	int i, j;

	for (i = 0; i < MIXER16_MAX_SOURCES; i++)
		for (j = 0; j < MIXER16_MAX_SINKS; j++)
			g->gain[i][j] = (i == j && i < MIXER16_MAX_SINKS) ?
					INT32_MAX : 0;
}

static int mixer16_init(struct processing_module *mod)
{
	struct mixer16_runtime *rt;
	int ret;

	rt = rzalloc(SOF_MEM_ZONE_RUNTIME, 0, SOF_MEM_CAPS_RAM, sizeof(*rt));
	if (!rt)
		return -ENOMEM;

	mixer16_set_identity(&rt->gains);

	rt->blob_handler = comp_data_blob_handler_new(mod->dev);
	if (!rt->blob_handler) {
		comp_err(mod->dev, "mixer16_init: blob handler alloc failed");
		rfree(rt);
		return -ENOMEM;
	}

	/* Init blob with identity matrix */
	ret = comp_init_data_blob(rt->blob_handler,
				  sizeof(struct mixer16_cell_gains),
				  &rt->gains);
	if (ret < 0) {
		comp_err(mod->dev, "mixer16_init: comp_init_data_blob failed");
		comp_data_blob_handler_free(rt->blob_handler);
		rfree(rt);
		return ret;
	}

	module_set_private_data(mod, rt);
	mod->max_sources = MIXER16_MAX_SOURCES;
	mod->max_sinks = MIXER16_MAX_SINKS;

	comp_info(mod->dev, "mixer16_init: V5.4.1 E2 — identity matrix, %d sources x %d sinks",
		  MIXER16_MAX_SOURCES, MIXER16_MAX_SINKS);
	return 0;
}

static int mixer16_prepare(struct processing_module *mod,
			   struct sof_source **sources, int num_of_sources,
			   struct sof_sink **sinks, int num_of_sinks)
{
	comp_dbg(mod->dev, "mixer16_prepare: sources=%d sinks=%d",
		 num_of_sources, num_of_sinks);
	mod->max_sources = MIXER16_MAX_SOURCES;
	mod->max_sinks = MIXER16_MAX_SINKS;
	return 0;
}

static int mixer16_set_config(struct processing_module *mod, uint32_t param_id,
			      enum module_cfg_fragment_position pos,
			      uint32_t data_offset_size, const uint8_t *fragment,
			      size_t fragment_size, uint8_t *response,
			      size_t response_size)
{
	struct mixer16_runtime *rt = module_get_private_data(mod);

	return comp_data_blob_set(rt->blob_handler, pos, data_offset_size,
				  fragment, fragment_size);
}

static int mixer16_get_config(struct processing_module *mod,
			      uint32_t config_id, uint32_t *data_offset_size,
			      uint8_t *fragment, size_t fragment_size)
{
	struct mixer16_runtime *rt = module_get_private_data(mod);
	struct sof_ipc_ctrl_data *cdata = (struct sof_ipc_ctrl_data *)fragment;

	return comp_data_blob_get_cmd(rt->blob_handler, cdata, fragment_size);
}

/*
 * Mix loop — 16 mono sources -> 8 mono sinks via Q1.31 gain matrix.
 *
 * Each source/sink is mono S32_LE. We process min_frames at a time.
 * Memory layout: source/sink buffers come from sof_source/sof_sink API
 * with circular buffer semantics, so we read/write through helpers that
 * respect the wrap.
 */
static int mixer16_process(struct processing_module *mod,
			   struct sof_source **sources, int num_of_sources,
			   struct sof_sink **sinks, int num_of_sinks)
{
	struct mixer16_runtime *rt = module_get_private_data(mod);
	uint32_t min_frames = UINT32_MAX;
	uint32_t free_frames;
	uint32_t avail_frames;
	const int32_t *src_data[MIXER16_MAX_SOURCES];
	int32_t *sink_data[MIXER16_MAX_SINKS];
	const void *src_ptr[MIXER16_MAX_SOURCES];
	const void *src_start[MIXER16_MAX_SOURCES];
	size_t src_size[MIXER16_MAX_SOURCES];
	void *sink_ptr[MIXER16_MAX_SINKS];
	void *sink_start[MIXER16_MAX_SINKS];
	size_t sink_size[MIXER16_MAX_SINKS];
	int32_t (*gain)[MIXER16_MAX_SINKS];
	int i, j, frame, ret;

	/* Refresh gains if blob updated */
	if (comp_is_new_data_blob_available(rt->blob_handler)) {
		struct mixer16_cell_gains *g =
			comp_get_data_blob(rt->blob_handler, NULL, NULL);
		if (g)
			rt->gains = *g;
	}
	gain = rt->gains.gain;

	if (num_of_sources <= 0 || num_of_sources > MIXER16_MAX_SOURCES)
		return -EINVAL;
	if (num_of_sinks <= 0 || num_of_sinks > MIXER16_MAX_SINKS)
		return -EINVAL;

	/* Compute min_frames over all sources and sinks */
	for (i = 0; i < num_of_sources; i++) {
		avail_frames = source_get_data_frames_available(sources[i]);
		if (avail_frames < min_frames)
			min_frames = avail_frames;
	}
	for (j = 0; j < num_of_sinks; j++) {
		free_frames = sink_get_free_frames(sinks[j]);
		if (free_frames < min_frames)
			min_frames = free_frames;
	}

	if (min_frames == 0 || min_frames == UINT32_MAX)
		return 0;

	/* Acquire pointers */
	for (i = 0; i < num_of_sources; i++) {
		ret = source_get_data(sources[i], min_frames * sizeof(int32_t),
				      &src_ptr[i], &src_start[i], &src_size[i]);
		if (ret) {
			while (--i >= 0)
				source_release_data(sources[i], 0);
			return -ENODATA;
		}
		src_data[i] = (const int32_t *)src_ptr[i];
	}
	for (j = 0; j < num_of_sinks; j++) {
		ret = sink_get_buffer(sinks[j], min_frames * sizeof(int32_t),
				      &sink_ptr[j], &sink_start[j], &sink_size[j]);
		if (ret) {
			while (--j >= 0)
				sink_commit_buffer(sinks[j], 0);
			for (i = 0; i < num_of_sources; i++)
				source_release_data(sources[i], 0);
			return -ENODATA;
		}
		sink_data[j] = (int32_t *)sink_ptr[j];
	}

	/* Mix loop — Q1.31 per-cell gain */
	for (frame = 0; frame < (int)min_frames; frame++) {
		for (j = 0; j < num_of_sinks; j++) {
			int64_t acc = 0;

			for (i = 0; i < num_of_sources; i++)
				acc += ((int64_t)src_data[i][frame] *
					gain[i][j]) >> 31;

			if (acc > INT32_MAX)
				sink_data[j][frame] = INT32_MAX;
			else if (acc < INT32_MIN)
				sink_data[j][frame] = INT32_MIN;
			else
				sink_data[j][frame] = (int32_t)acc;
		}
	}

	/* Commit / release */
	for (j = 0; j < num_of_sinks; j++)
		sink_commit_buffer(sinks[j], min_frames * sizeof(int32_t));
	for (i = 0; i < num_of_sources; i++)
		source_release_data(sources[i], min_frames * sizeof(int32_t));

	return 0;
}

static int mixer16_reset(struct processing_module *mod)
{
	comp_dbg(mod->dev, "mixer16_reset()");
	return 0;
}

static int mixer16_free(struct processing_module *mod)
{
	struct mixer16_runtime *rt = module_get_private_data(mod);

	if (rt) {
		if (rt->blob_handler)
			comp_data_blob_handler_free(rt->blob_handler);
		rfree(rt);
	}
	comp_dbg(mod->dev, "mixer16_free()");
	return 0;
}

static const struct module_interface mixer16_interface = {
	.init = mixer16_init,
	.prepare = mixer16_prepare,
	.process = mixer16_process,
	.set_configuration = mixer16_set_config,
	.get_configuration = mixer16_get_config,
	.reset = mixer16_reset,
	.free = mixer16_free,
};

DECLARE_MODULE_ADAPTER(mixer16_interface, mixer16_uuid, mixer16_tr);
SOF_MODULE_INIT(mixer16, sys_comp_module_mixer16_interface_init);
