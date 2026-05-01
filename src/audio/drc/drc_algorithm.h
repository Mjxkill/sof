/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright(c) 2020 Google LLC. All rights reserved.
 *
 * Author: Pin-chih Lin <johnylin@google.com>
 */
#ifndef __SOF_AUDIO_DRC_DRC_ALGORITHM_H__
#define __SOF_AUDIO_DRC_DRC_ALGORITHM_H__

#include <stdint.h>
#include <sof/platform.h>

#include "drc_user.h"
#include "drc.h"

/* drc reset function */
void drc_reset_state(struct drc_state *state);

/* drc init functions */
int drc_init_pre_delay_buffers(struct drc_state *state,
			       size_t sample_bytes,
			       int channels);
int drc_set_pre_delay_time(struct drc_state *state,
			   int32_t pre_delay_time,
			   int32_t rate);

/* Resolve params for a given channel index in a (possibly multi-config) blob. */
const struct sof_drc_params *drc_get_params(const struct drc_comp_data *cd, int ch);

/* drc process functions — V5.4.1 D3: per-channel processing.
 * Each call processes a single channel using state->fields[ch] and
 * pre_delay_buffers[ch]. nbyte is sample size in bytes (2 or 4).
 */
void drc_update_detector_average(struct drc_state *state,
				 const struct sof_drc_params *p,
				 int nbyte,
				 int ch);
void drc_update_envelope(struct drc_state *state,
			 const struct sof_drc_params *p,
			 int ch);
void drc_compress_output(struct drc_state *state,
			 const struct sof_drc_params *p,
			 int nbyte,
			 int ch);

#endif //  __SOF_AUDIO_DRC_DRC_ALGORITHM_H__
