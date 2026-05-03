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
#include <sof/lib/mailbox.h>
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
	unsigned int dbg_count;	/* DIAG E6.b: log first ticks */
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
	 * on multi-source comps (pipeline_lock_branched forces channels=1 on
	 * branched buffers). Structural to F++, not a "patch".
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
 * Process loop — AUDIO_STREAM mode (V5.4.1 E6.b iter7).
 *
 * The matrix_2x8 component now uses the AUDIO_STREAM dispatch path
 * (module_adapter_audio_stream_type_copy) instead of SOURCE_SINK. The
 * framework calls module_single_sink_setup which computes input_buffers[s].size
 * via audio_stream_avail_frames_aligned for each source — this is the same
 * path used by eq/drc/pga and properly handles TDM 8-slot frame alignment.
 *
 * For each frame, each output channel j is the Q1.31-weighted sum of the 16
 * input channels (8 from src 0 + 8 from src 1). audio_stream_read/write_frag_s32
 * gives wrap-safe access to circular buffers (no manual wrap handling needed).
 *
 * Sources with input_buffers[s].size < min_frames contribute silence for the
 * frames beyond their available count (mix loop skip).
 */
static int matrix_2x8_process(struct processing_module *mod,
			      struct input_stream_buffer *input_buffers, int num_input_buffers,
			      struct output_stream_buffer *output_buffers, int num_output_buffers)
{
	struct matrix_2x8_runtime *rt = module_get_private_data(mod);
	struct audio_stream *src_stream[MATRIX_2X8_MAX_SOURCES];
	struct audio_stream *sink_stream;
	uint32_t src_frames[MATRIX_2X8_MAX_SOURCES];
	uint32_t min_frames = UINT32_MAX;
	int32_t (*gain)[MATRIX_2X8_OUT_CHANNELS];
	int s, i, j;
	uint32_t frame;
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

	if (num_input_buffers <= 0 || num_input_buffers > MATRIX_2X8_MAX_SOURCES)
		return -EINVAL;
	if (num_output_buffers != MATRIX_2X8_MAX_SINKS)
		return -EINVAL;

	/* DIAG E6.b: minimal mailbox writes. Local counter, snapshots only at
	 * specific ticks (1, 5, 10, 100, 500, 1000). Live counter republished
	 * every 256 ticks (~500ms) only. REMOVE after diag.
	 *
	 * Mailbox layout:
	 *   0x100: magic 0xDEADBEEF
	 *   0x104: live tick counter (refreshed every 256 ticks)
	 *   0x108: number of snapshots stored
	 *   0x110-0x14F: slot 0 (tick=1)    +0x40 each slot
	 *   0x150-0x18F: slot 1 (tick=5)
	 *   0x190-0x1CF: slot 2 (tick=10)
	 *   0x1D0-0x20F: slot 3 (tick=100)
	 *   0x210-0x24F: slot 4 (tick=500)
	 *   0x250-0x28F: slot 5 (tick=1000)
	 */
	rt->dbg_count++;

	/* Periodic live publish: every 16 ticks (~32ms) — limit SRAM writes */
	if ((rt->dbg_count & 0x0F) == 1) {
		mailbox_sw_reg_write(0x100, 0xDEADBEEF);
		mailbox_sw_reg_write(0x104, rt->dbg_count);
	}

	{
		uint32_t slot_off = 0;
		switch (rt->dbg_count) {
		case 1:    slot_off = 0x110; break;
		case 5:    slot_off = 0x150; break;
		case 10:   slot_off = 0x190; break;
		case 100:  slot_off = 0x1D0; break;
		case 500:  slot_off = 0x210; break;
		case 1000: slot_off = 0x250; break;
		default:   slot_off = 0; break;
		}
		if (slot_off) {
			struct comp_buffer *cb0 = NULL, *cb1 = NULL;

			mailbox_sw_reg_write(slot_off + 0x00, rt->dbg_count);
			mailbox_sw_reg_write(slot_off + 0x04, num_input_buffers);
			if (num_input_buffers >= 1) {
				cb0 = container_of(input_buffers[0].data,
						   struct comp_buffer, stream);
				mailbox_sw_reg_write(slot_off + 0x08,
					input_buffers[0].size);
				mailbox_sw_reg_write(slot_off + 0x0C,
					audio_stream_get_avail_bytes(input_buffers[0].data));
				mailbox_sw_reg_write(slot_off + 0x10,
					audio_stream_frame_bytes(input_buffers[0].data));
				mailbox_sw_reg_write(slot_off + 0x14,
					audio_stream_get_channels(input_buffers[0].data));
				mailbox_sw_reg_write(slot_off + 0x18,
					cb0->source ? cb0->source->state : 0xFFFFFFFF);
			}
			if (num_input_buffers >= 2) {
				cb1 = container_of(input_buffers[1].data,
						   struct comp_buffer, stream);
				mailbox_sw_reg_write(slot_off + 0x1C,
					input_buffers[1].size);
				mailbox_sw_reg_write(slot_off + 0x20,
					audio_stream_get_avail_bytes(input_buffers[1].data));
				mailbox_sw_reg_write(slot_off + 0x24,
					audio_stream_frame_bytes(input_buffers[1].data));
				mailbox_sw_reg_write(slot_off + 0x28,
					audio_stream_get_channels(input_buffers[1].data));
				mailbox_sw_reg_write(slot_off + 0x2C,
					cb1->source ? cb1->source->state : 0xFFFFFFFF);
			}
			mailbox_sw_reg_write(slot_off + 0x30,
				audio_stream_get_free_bytes(output_buffers[0].data));
			mailbox_sw_reg_write(slot_off + 0x34,
				audio_stream_frame_bytes(output_buffers[0].data));
			mailbox_sw_reg_write(slot_off + 0x38,
				audio_stream_get_channels(output_buffers[0].data));
			mailbox_sw_reg_write(0x108,
				(rt->dbg_count >= 1000) ? 6 :
				(rt->dbg_count >= 500) ? 5 :
				(rt->dbg_count >= 100) ? 4 :
				(rt->dbg_count >= 10) ? 3 :
				(rt->dbg_count >= 5) ? 2 : 1);
		}
	}

	/* RESET — minimal mixer logic. Pure MIN over sources, mix loop, commit.
	 * No iter1/4/6/8/9/10 patches. Naive reference state to study real bug.
	 */
	sink_stream = output_buffers[0].data;
	for (s = 0; s < num_input_buffers; s++) {
		src_stream[s] = input_buffers[s].data;
		src_frames[s] = input_buffers[s].size;
		if (src_frames[s] < min_frames)
			min_frames = src_frames[s];
	}

	if (min_frames == 0 || min_frames == UINT32_MAX)
		return 0;

	/* Mix loop. audio_stream_read/write_frag_s32 handle wrap automatically.
	 * Sources whose src_frames[s] < frame contribute silence implicitly via
	 * skip — their gain contribution is 0 for those frames.
	 */
	for (frame = 0; frame < min_frames; frame++) {
		for (j = 0; j < MATRIX_2X8_OUT_CHANNELS; j++) {
			acc = 0;
			for (s = 0; s < num_input_buffers; s++) {
				if (frame >= src_frames[s])
					continue;
				for (i = 0; i < MATRIX_2X8_OUT_CHANNELS; i++) {
					int32_t *src_ptr = audio_stream_read_frag_s32(
						src_stream[s],
						frame * MATRIX_2X8_OUT_CHANNELS + i);
					sample = *src_ptr;
					acc += ((int64_t)sample *
						gain[s * MATRIX_2X8_OUT_CHANNELS + i][j]) >> 31;
				}
			}
			{
				int32_t *dst_ptr = audio_stream_write_frag_s32(
					sink_stream,
					frame * MATRIX_2X8_OUT_CHANNELS + j);
				if (acc > INT32_MAX)
					*dst_ptr = INT32_MAX;
				else if (acc < INT32_MIN)
					*dst_ptr = INT32_MIN;
				else
					*dst_ptr = (int32_t)acc;
			}
		}
	}

	/* Inform framework: produced and consumed bytes.
	 * output_buffers[0].size is in BYTES. input_buffers[s].consumed is in BYTES.
	 */
	output_buffers[0].size = audio_stream_frame_bytes(sink_stream) * min_frames;
	for (s = 0; s < num_input_buffers; s++) {
		uint32_t consumed = (src_frames[s] < min_frames) ? src_frames[s] : min_frames;
		input_buffers[s].consumed = audio_stream_frame_bytes(src_stream[s]) * consumed;
	}

	return 0;
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
	.process_audio_stream = matrix_2x8_process,
	.set_configuration = matrix_2x8_set_config,
	.get_configuration = matrix_2x8_get_config,
	.reset = matrix_2x8_reset,
	.free = matrix_2x8_free,
};

DECLARE_MODULE_ADAPTER(matrix_2x8_interface, matrix_2x8_uuid, matrix_2x8_tr);
SOF_MODULE_INIT(matrix_2x8, sys_comp_module_matrix_2x8_interface_init);
