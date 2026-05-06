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
 * Process loop — OUTPUT-DRIVEN (V5.4.1 E6.b final).
 *
 * Cahier des charges :
 *   - Cadence dictée UNIQUEMENT par le sink (audio_stream_get_free_frames).
 *   - Aucune dépendance à l'état des sources (active/inactive/préparée).
 *   - Sources vides ou partielles → contribution silencieuse implicite
 *     (gain * 0 = 0 dans la boucle de mix via la garde frame < src_avail).
 *   - Aucun bail-out précoce sur les entrées : si toutes vides, le mix
 *     accumule 0 et on écrit du silence dans le sink.
 *
 * Justification de sûreté : RX et TX SAI7 synchrones (même BCLK), donc pas
 * d'underrun possible côté DSP. Le PCM host alimente toujours B0. B5
 * cross-pipeline peut être vide → contribution silencieuse sur la voie mics.
 */
static int matrix_2x8_process(struct processing_module *mod,
			      struct input_stream_buffer *input_buffers, int num_input_buffers,
			      struct output_stream_buffer *output_buffers, int num_output_buffers)
{
	struct matrix_2x8_runtime *rt = module_get_private_data(mod);
	struct audio_stream *src_stream[MATRIX_2X8_MAX_SOURCES];
	struct audio_stream *sink_stream;
	uint32_t src_avail[MATRIX_2X8_MAX_SOURCES];
	uint32_t nb_frames;
	uint32_t sink_frame_bytes;
	int32_t (*gain)[MATRIX_2X8_OUT_CHANNELS];
	int s, i, j;
	uint32_t frame;
	int32_t sample;
	int64_t acc;

	/* DIAG E6.b: instrumentation AVANT les gardes — chaque appel compte.
	 * 0x150 : dbg_total (compteur appels totaux, incrémenté à chaque entrée)
	 * 0x154 : num_input_buffers (vu par matrix_2x8_process)
	 * 0x158 : num_output_buffers (forcé à 0 par module_adapter si sink->state != dev->state)
	 * 0x15C : mod->dev->state (état matrix_2x8 lui-même)
	 * 0x160 : downstream sink->state (consommateur de B100, normalement interleave_8)
	 * 0x164 : num bsink connectés (sanity check liste)
	 */
	{
		static volatile uint32_t dbg_total;
		dbg_total++;
		if ((dbg_total & 0x1F) == 1) {
			struct list_item *blist;
			struct comp_buffer *cb;
			uint32_t sink_state = 0xFFFFFFFFu;
			uint32_t bsink_count = 0;

			list_for_item(blist, &mod->dev->bsink_list) {
				cb = container_of(blist, struct comp_buffer, source_list);
				bsink_count++;
				if (cb->sink && sink_state == 0xFFFFFFFFu)
					sink_state = cb->sink->state;
			}
			mailbox_sw_reg_write(0x150, dbg_total);
			mailbox_sw_reg_write(0x154, (uint32_t)num_input_buffers);
			mailbox_sw_reg_write(0x158, (uint32_t)num_output_buffers);
			mailbox_sw_reg_write(0x15C, mod->dev->state);
			mailbox_sw_reg_write(0x160, sink_state);
			mailbox_sw_reg_write(0x164, bsink_count);
		}
	}

	/* Refresh gains if a new blob was uploaded */
	if (comp_is_new_data_blob_available(rt->blob_handler)) {
		struct matrix_2x8_gains *g =
			comp_get_data_blob(rt->blob_handler, NULL, NULL);
		if (g)
			rt->gains = *g;
	}
	gain = rt->gains.gain;

	if (num_input_buffers <= 0 || num_input_buffers > MATRIX_2X8_MAX_SOURCES)
		return 0;
	if (num_output_buffers != MATRIX_2X8_MAX_SINKS)
		return 0;

	/* DIAG E6.b: matrix process tick counter (throttled 1/16) */
	{
		static volatile uint32_t dbg_count;
		dbg_count++;
		if ((dbg_count & 0x0F) == 1) {
			mailbox_sw_reg_write(0x100, 0xDEADBEEF);
			mailbox_sw_reg_write(0x104, dbg_count);
		}
	}

	sink_stream = output_buffers[0].data;
	sink_frame_bytes = audio_stream_frame_bytes(sink_stream);

	/* DIAG E6.b: dump B100 (sink) state at every 16th tick to verify init.
	 * 0x130 : sink_frame_bytes (should be 32 = 4 bytes/sample × 8 ch)
	 * 0x134 : sink free_bytes
	 * 0x138 : sink free_frames (= free_bytes / frame_bytes, undefined if frame_bytes=0)
	 * 0x13C : sink channels (should be 8)
	 * 0x140 : sink frame_fmt (should be SOF_IPC_FRAME_S32_LE = 2)
	 */
	{
		static volatile uint32_t dbg_sink;
		dbg_sink++;
		if ((dbg_sink & 0x0F) == 1) {
			mailbox_sw_reg_write(0x130, sink_frame_bytes);
			mailbox_sw_reg_write(0x134, audio_stream_get_free_bytes(sink_stream));
			mailbox_sw_reg_write(0x138, sink_frame_bytes ?
				audio_stream_get_free_bytes(sink_stream) / sink_frame_bytes : 0xFFFFFFFFu);
			mailbox_sw_reg_write(0x13C, audio_stream_get_channels(sink_stream));
			mailbox_sw_reg_write(0x140, audio_stream_get_frm_fmt(sink_stream));
		}
	}

	if (!sink_frame_bytes)
		return 0;

	/* Cadence : sink seul. Borné par period pour rester dans le tick. */
	nb_frames = audio_stream_get_free_frames(sink_stream);
	if (nb_frames > MATRIX_2X8_PERIOD_FRAMES)
		nb_frames = MATRIX_2X8_PERIOD_FRAMES;
	if (!nb_frames)
		return 0;

	/* Snapshot des frames disponibles par source. Lecture du size posé
	 * par module_single_sink_setup via audio_stream_avail_frames_aligned.
	 * Aucune lecture d'état comp source — juste le compteur d'octets dispo.
	 */
	for (s = 0; s < num_input_buffers; s++) {
		src_stream[s] = input_buffers[s].data;
		src_avail[s] = input_buffers[s].size;
	}

	/* Mix loop output-driven. Si frame >= src_avail[s], la source contribue
	 * 0 (silence implicite). Pas de bail-out, on produit toujours nb_frames.
	 */
	for (frame = 0; frame < nb_frames; frame++) {
		for (j = 0; j < MATRIX_2X8_OUT_CHANNELS; j++) {
			acc = 0;
			for (s = 0; s < num_input_buffers; s++) {
				if (frame >= src_avail[s])
					continue; /* contribution silencieuse */
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

	/* Produced : toujours nb_frames complets vers le sink. */
	output_buffers[0].size = nb_frames * sink_frame_bytes;

	/* Consumed par source : MIN(src_avail, nb_frames). consumed=0 si vide,
	 * le framework skippe l'appel audio_stream_consume sans corrompre.
	 */
	for (s = 0; s < num_input_buffers; s++) {
		uint32_t consumed = (src_avail[s] < nb_frames) ? src_avail[s] : nb_frames;
		input_buffers[s].consumed = consumed *
			audio_stream_frame_bytes(src_stream[s]);
	}

	return 0;
}

/*
 * Trigger LOCAL — V5.4.1 E6.b final.
 *
 * Bypass délibéré de module_adapter_set_state() (branche num_of_sources > 1
 * qui couple le trigger à l'état des sources via module_source_status_count).
 *
 * Sémantique table de mixage : matrix_2x8 s'allume/s'éteint UNIQUEMENT sur
 * son propre cycle de trigger. L'état de ses entrées n'a aucune incidence
 * sur sa transition d'état.
 */
static int matrix_2x8_trigger(struct processing_module *mod, int cmd)
{
	return comp_set_state(mod->dev, cmd);
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
	.trigger = matrix_2x8_trigger,
	.reset = matrix_2x8_reset,
	.free = matrix_2x8_free,
};

DECLARE_MODULE_ADAPTER(matrix_2x8_interface, matrix_2x8_uuid, matrix_2x8_tr);
SOF_MODULE_INIT(matrix_2x8, sys_comp_module_matrix_2x8_interface_init);
