/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright(c) 2020 Google LLC. All rights reserved.
 *
 * Author: Pin-chih Lin <johnylin@google.com>
 */
#ifndef __SOF_AUDIO_DRC_DRC_H__
#define __SOF_AUDIO_DRC_DRC_H__

#include <stdint.h>
#include <sof/audio/module_adapter/module/generic.h>
#include <sof/audio/buffer.h>
#include <sof/platform.h>

#include "drc_user.h"

struct audio_stream;
struct comp_dev;

/* Define CONFIG_DRC_MAX_PRE_DELAY_FRAMES for the build purposes without Kconfig,
 * e.g. testbench.
 * TODO: Use Kconfig on building the testbench.
 */
#ifdef CONFIG_LIBRARY
/* CONFIG_DRC_MAX_PRE_DELAY_FRAMES needs to be a 2^N number */
#define CONFIG_DRC_MAX_PRE_DELAY_FRAMES 512
#endif
#define DRC_MAX_PRE_DELAY_FRAMES_MASK (CONFIG_DRC_MAX_PRE_DELAY_FRAMES - 1)
#define DRC_DEFAULT_PRE_DELAY_FRAMES (CONFIG_DRC_MAX_PRE_DELAY_FRAMES >> 1)

/* DRC_DIVISION_FRAMES needs to be a 2^N number */
#define DRC_DIVISION_FRAMES 32
#define DRC_DIVISION_FRAMES_MASK (DRC_DIVISION_FRAMES - 1)

/* First switch control instance is zero (SOF_IPC4_SWITCH_CONTROL_PARAM_ID), and the
 * control is common for all channels.
 */
#define SOF_DRC_CTRL_INDEX_ENABLE_SWITCH 0
#define SOF_DRC_NUM_ELEMS_ENABLE_SWITCH 1

/* Stores the state of DRC.
 *
 * V5.4.1 E5.e.2 D3 — per-channel state. Each scalar field is now an array
 * indexed by channel, so each channel runs its own dynamics state machine
 * with its own params (sof_drc_params per channel, parsed from a multi-config
 * blob — see drc_user.h note). pre_delay_buffers were already per-channel.
 *
 * Back-compat: if the configuration blob is single-config (channels_in_config
 * <= 1), drc.c initialises params[0] as the shared params and all channels
 * share that params pointer at process time. State is still per-channel so
 * each channel still tracks its own envelope/gain — this is acceptable since
 * the math is identical with shared params and is more accurate per-channel
 * than the old shared-state implementation (which collapsed channels into a
 * MAX-of-channels detector).
 */
struct drc_state {
	/* Per-channel dynamics state. detector_average is the target gain
	 * obtained by looking at the future samples in the lookahead buffer
	 * and applying the compression curve on them. compressor_gain is the
	 * gain applied to the current samples. compressor_gain moves towards
	 * detector_average with the speed envelope_rate which is calculated
	 * once for each division (32 frames).
	 */
	int32_t detector_average[PLATFORM_MAX_CHANNELS]; /* Q2.30 */
	int32_t compressor_gain[PLATFORM_MAX_CHANNELS];  /* Q2.30 */

	/* envelope for the current division */
	int32_t envelope_rate[PLATFORM_MAX_CHANNELS];       /* Q2.30 */
	int32_t scaled_desired_gain[PLATFORM_MAX_CHANNELS]; /* Q2.30 */

	int32_t max_attack_compression_diff_db[PLATFORM_MAX_CHANNELS]; /* Q8.24 */

	int32_t processed; /* switch — shared (set after first init) */

	/* Lookahead section.
	 * The pre_delay ring is shared (same length and synchronous indices
	 * across channels) because per-channel lookahead would desync audio
	 * between channels. Per-channel pre_delay_buffers store deinterleaved
	 * samples for processing.
	 */
	int8_t *pre_delay_buffers[PLATFORM_MAX_CHANNELS];
	int32_t last_pre_delay_frames; /* integer (shared) */
	int32_t pre_delay_read_index;  /* integer (shared) */
	int32_t pre_delay_write_index; /* integer (shared) */
};

typedef void (*drc_func)(struct processing_module *mod,
			 const struct audio_stream *source,
			 struct audio_stream *sink,
			 uint32_t frames);

/* DRC component private data */
struct drc_comp_data {
	struct drc_state state;             /**< compressor state (per-channel) */
	struct comp_data_blob_handler *model_handler;
	struct sof_drc_config *config;      /**< pointer to setup blob */
	uint32_t channels_in_config;        /**< number of params sets in config (1 = back-compat single, N = per-channel) */
	bool config_ready;                  /**< set when fully received */
	bool enabled;                       /**< control processing via blob and switch */
	bool enable_switch;                 /**< enable switch state */
	enum sof_ipc_frame source_format;   /**< source frame format */
	drc_func drc_func;                  /**< processing function */
};

struct drc_proc_fnmap {
	enum sof_ipc_frame frame_fmt;
	drc_func drc_proc_func;
};

extern const struct drc_proc_fnmap drc_proc_fnmap[];
extern const size_t drc_proc_fncount;

void drc_default_pass(struct processing_module *mod,
		      const struct audio_stream *source,
		      struct audio_stream *sink, uint32_t frames);
/**
 * \brief Returns DRC processing function.
 */
static inline drc_func drc_find_proc_func(enum sof_ipc_frame src_fmt)
{
	int i;

	/* Find suitable processing function from map */
	for (i = 0; i < drc_proc_fncount; i++)
		if (src_fmt == drc_proc_fnmap[i].frame_fmt)
			return drc_proc_fnmap[i].drc_proc_func;

	return NULL;
}

#endif //  __SOF_AUDIO_DRC_DRC_H__
