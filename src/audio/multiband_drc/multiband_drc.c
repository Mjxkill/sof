// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright(c) 2020 Google LLC. All rights reserved.
//
// Author: Pin-chih Lin <johnylin@google.com>

#include <sof/audio/module_adapter/module/generic.h>
#include <sof/audio/buffer.h>
#include <sof/audio/format.h>
#include <sof/audio/ipc-config.h>
#include <sof/audio/pipeline.h>
#include <sof/ipc/msg.h>
#include <sof/lib/memory.h>
#include <sof/lib/uuid.h>
#include <sof/math/numbers.h>
#include <module/crossover/crossover_common.h>
#include <sof/trace/trace.h>
#include <ipc/control.h>
#include <ipc/stream.h>
#include <ipc/topology.h>
#include <rtos/alloc.h>
#include <rtos/init.h>
#include <rtos/panic.h>
#include <rtos/string.h>
#include <sof/common.h>
#include <sof/list.h>
#include <sof/platform.h>
#include <sof/ut.h>
#include <user/eq.h>
#include <user/trace.h>
#include <errno.h>
#include <stddef.h>
#include <stdint.h>

#include "../drc/drc_algorithm.h"
#include "multiband_drc.h"

LOG_MODULE_REGISTER(multiband_drc, CONFIG_SOF_LOG_LEVEL);

/* 0d9f2256-8e4f-47b3-8448-239a334f1191 */
DECLARE_SOF_RT_UUID("multiband_drc", multiband_drc_uuid, 0x0d9f2256, 0x8e4f, 0x47b3,
		    0x84, 0x48, 0x23, 0x9a, 0x33, 0x4f, 0x11, 0x91);

DECLARE_TR_CTX(multiband_drc_tr, SOF_UUID(multiband_drc_uuid), LOG_LEVEL_INFO);

/* V6.0: helper — return per-channel config pointer.
 * Single-config: all channels share cd->config.
 * Multi-config: ch-th block (clamped to n_configs - 1).
 */
static inline struct sof_multiband_drc_config *
mbdrc_get_config_for_ch(struct multiband_drc_comp_data *cd, int ch)
{
	if (cd->n_configs <= 1)
		return cd->config;

	int idx = (ch < cd->n_configs) ? ch : (cd->n_configs - 1);
	return (struct sof_multiband_drc_config *)
		((uint8_t *)cd->config + (size_t)idx * cd->size_per_config);
}

static void multiband_drc_reset_state(struct multiband_drc_state *state)
{
	int i, ch;

	/* Reset emphasis eq-iir state */
	for (i = 0; i < PLATFORM_MAX_CHANNELS; i++)
		multiband_drc_iir_reset_state_ch(&state->emphasis[i]);

	/* Reset crossover state */
	for (i = 0; i < PLATFORM_MAX_CHANNELS; i++)
		crossover_reset_state_ch(&state->crossover[i]);

	/* V6.0: reset drc kernel state per [band][ch] */
	for (i = 0; i < SOF_MULTIBAND_DRC_MAX_BANDS; i++)
		for (ch = 0; ch < PLATFORM_MAX_CHANNELS; ch++)
			drc_reset_state(&state->drc[i][ch]);

	/* Reset deemphasis eq-iir state */
	for (i = 0; i < PLATFORM_MAX_CHANNELS; i++)
		multiband_drc_iir_reset_state_ch(&state->deemphasis[i]);
}

static int multiband_drc_eq_init_coef_ch(struct sof_eq_iir_biquad *coef,
					 struct iir_state_df2t *eq)
{
	int ret;

	eq->coef = rzalloc(SOF_MEM_ZONE_RUNTIME, 0, SOF_MEM_CAPS_RAM,
			   sizeof(struct sof_eq_iir_biquad) * SOF_EMP_DEEMP_BIQUADS);
	if (!eq->coef)
		return -ENOMEM;

	/* Coefficients of the first biquad and second biquad */
	ret = memcpy_s(eq->coef, sizeof(struct sof_eq_iir_biquad) * SOF_EMP_DEEMP_BIQUADS,
		       coef, sizeof(struct sof_eq_iir_biquad) * SOF_EMP_DEEMP_BIQUADS);
	assert(!ret);

	/* EQ filters are two 2nd order filters, so only need 4 delay slots
	 * delay[0..1] -> state for first biquad
	 * delay[2..3] -> state for second biquad
	 */
	eq->delay = rzalloc(SOF_MEM_ZONE_RUNTIME, 0, SOF_MEM_CAPS_RAM,
			    sizeof(uint64_t) * CROSSOVER_NUM_DELAYS_LR4);
	if (!eq->delay)
		return -ENOMEM;

	eq->biquads = SOF_EMP_DEEMP_BIQUADS;
	eq->biquads_in_series = SOF_EMP_DEEMP_BIQUADS;

	return 0;
}

static int multiband_drc_init_coef(struct processing_module *mod, int16_t nch, uint32_t rate)
{
	struct comp_dev *dev = mod->dev;
	struct multiband_drc_comp_data *cd = module_get_private_data(mod);
	struct sof_multiband_drc_config *config = cd->config;
	struct sof_multiband_drc_config *cfg_ch;
	struct multiband_drc_state *state = &cd->state;
	uint32_t sample_bytes = get_sample_bytes(cd->source_format);
	size_t size_per_config;
	int i, ch, ret, num_bands;

	if (!config) {
		comp_err(dev, "multiband_drc_init_coef(), no config is set");
		return -EINVAL;
	}

	num_bands = config->num_bands;

	/* Sanity checks */
	if (nch > PLATFORM_MAX_CHANNELS) {
		comp_err(dev,
			 "multiband_drc_init_coef(), invalid channels count(%i)", nch);
		return -EINVAL;
	}
	if (config->num_bands > SOF_MULTIBAND_DRC_MAX_BANDS) {
		comp_err(dev, "multiband_drc_init_coef(), invalid bands count(%i)",
			 config->num_bands);
		return -EINVAL;
	}

	/* V6.0: detect single-config vs multi-config (per-channel) by blob size.
	 * size_per_config = header (up to drc_coef[]) + num_bands × drc_params.
	 */
	size_per_config = offsetof(struct sof_multiband_drc_config, drc_coef)
			+ (size_t)num_bands * sizeof(struct sof_drc_params);

	if (size_per_config == 0 || config->size < size_per_config) {
		comp_err(dev, "multiband_drc_init_coef(), invalid blob size %u (expected >= %u)",
			 (unsigned)config->size, (unsigned)size_per_config);
		return -EINVAL;
	}
	if (config->size % size_per_config != 0) {
		comp_err(dev, "multiband_drc_init_coef(), blob size %u not multiple of cfg size %u",
			 (unsigned)config->size, (unsigned)size_per_config);
		return -EINVAL;
	}

	cd->size_per_config = size_per_config;
	cd->n_configs = (int)(config->size / size_per_config);

	comp_info(dev, "multiband_drc_init_coef(), %d-way crossover, n_configs=%d",
		  config->num_bands, cd->n_configs);

	/* Per-channel init: emphasis, crossover, deemphasis use cfg_ch coefs */
	for (ch = 0; ch < nch; ch++) {
		cfg_ch = mbdrc_get_config_for_ch(cd, ch);

		ret = crossover_init_coef_ch(cfg_ch->crossover_coef,
					     &state->crossover[ch],
					     cfg_ch->num_bands);
		if (ret < 0) {
			comp_err(dev,
				 "multiband_drc_init_coef(), crossover ch %d failed", ch);
			goto err;
		}

		ret = multiband_drc_eq_init_coef_ch(cfg_ch->emp_coef,
						    &state->emphasis[ch]);
		if (ret < 0) {
			comp_err(dev,
				 "multiband_drc_init_coef(), emphasis ch %d failed", ch);
			goto err;
		}

		ret = multiband_drc_eq_init_coef_ch(cfg_ch->deemp_coef,
						    &state->deemphasis[ch]);
		if (ret < 0) {
			comp_err(dev,
				 "multiband_drc_init_coef(), deemphasis ch %d failed", ch);
			goto err;
		}
	}

	/* Allocate DRC pre-delay buffers per [band][ch], mono each (nch=1).
	 * V6.0: was state->drc[band] shared across channels — now state->drc[band][ch]
	 * one mono drc_state per channel per band, with its own pre_delay buffer.
	 */
	for (i = 0; i < num_bands; i++) {
		comp_info(dev, "multiband_drc_init_coef(), initializing drc band %d", i);

		for (ch = 0; ch < nch; ch++) {
			cfg_ch = mbdrc_get_config_for_ch(cd, ch);

			ret = drc_init_pre_delay_buffers(&state->drc[i][ch],
							 (size_t)sample_bytes, 1);
			if (ret < 0) {
				comp_err(dev,
					 "multiband_drc_init_coef(), pre delay alloc band %d ch %d failed",
					 i, ch);
				goto err;
			}

			ret = drc_set_pre_delay_time(&state->drc[i][ch],
						     cfg_ch->drc_coef[i].pre_delay_time,
						     rate);
			if (ret < 0) {
				comp_err(dev,
					 "multiband_drc_init_coef(), set pre delay band %d ch %d failed",
					 i, ch);
				goto err;
			}
		}
	}

	return 0;

err:
	multiband_drc_reset_state(state);
	return ret;
}

static int multiband_drc_setup(struct processing_module *mod, int16_t channels, uint32_t rate)
{
	struct multiband_drc_comp_data *cd = module_get_private_data(mod);
	int ret;

	/* Reset any previous state */
	multiband_drc_reset_state(&cd->state);

	/* Setup Crossover, Emphasis EQ, Deemphasis EQ, and DRC */
	ret = multiband_drc_init_coef(mod, channels, rate);
	if (ret < 0)
		return ret;

	return 0;
}

/*
 * End of Multiband DRC setup code. Next the standard component methods.
 */

static int multiband_drc_init(struct processing_module *mod)
{
	struct module_data *md = &mod->priv;
	struct comp_dev *dev = mod->dev;
	struct module_config *cfg = &md->cfg;
	struct multiband_drc_comp_data *cd;
	size_t bs = cfg->size;
	int ret;

	comp_info(dev, "multiband_drc_init()");

	/* Check first before proceeding with dev and cd that coefficients
	 * blob size is sane.
	 */
	if (bs > SOF_MULTIBAND_DRC_MAX_BLOB_SIZE) {
		comp_err(dev, "multiband_drc_init(), error: configuration blob size = %u > %d",
			 bs, SOF_MULTIBAND_DRC_MAX_BLOB_SIZE);
		return -EINVAL;
	}

	cd = rzalloc(SOF_MEM_ZONE_RUNTIME, 0, SOF_MEM_CAPS_RAM, sizeof(*cd));
	if (!cd)
		return -ENOMEM;

	md->private = cd;
	cd->multiband_drc_func = NULL;
	cd->crossover_split = NULL;
	/* Initialize to enabled is a workaround for IPC4 kernel version 6.6 and
	 * before where the processing is never enabled via switch control. New
	 * kernel sends the IPC4 switch control and sets this to desired state
	 * before prepare.
	 */
	multiband_drc_process_enable(&cd->process_enabled);

	/* Handler for configuration data */
	cd->model_handler = comp_data_blob_handler_new(dev);
	if (!cd->model_handler) {
		comp_err(dev, "multiband_drc_init(): comp_data_blob_handler_new() failed.");
		ret = -ENOMEM;
		goto cd_fail;
	}

	/* Get configuration data and reset DRC state */
	ret = comp_init_data_blob(cd->model_handler, bs, cfg->data);
	if (ret < 0) {
		comp_err(dev, "multiband_drc_init(): comp_init_data_blob() failed.");
		goto cd_fail;
	}
	multiband_drc_reset_state(&cd->state);

	return 0;

cd_fail:
	comp_data_blob_handler_free(cd->model_handler);
	rfree(cd);
	return ret;
}

static int multiband_drc_free(struct processing_module *mod)
{
	struct multiband_drc_comp_data *cd = module_get_private_data(mod);

	comp_info(mod->dev, "multiband_drc_free()");

	comp_data_blob_handler_free(cd->model_handler);

	rfree(cd);
	return 0;
}

static int multiband_drc_set_config(struct processing_module *mod, uint32_t param_id,
				    enum module_cfg_fragment_position pos,
				    uint32_t data_offset_size, const uint8_t *fragment,
				    size_t fragment_size, uint8_t *response,
				    size_t response_size)
{
	struct comp_dev *dev = mod->dev;

	comp_dbg(dev, "multiband_drc_set_config()");

	return multiband_drc_set_ipc_config(mod, param_id,
					    fragment, pos, data_offset_size, fragment_size);
}

static int multiband_drc_get_config(struct processing_module *mod,
				    uint32_t config_id, uint32_t *data_offset_size,
				    uint8_t *fragment, size_t fragment_size)
{
	struct sof_ipc_ctrl_data *cdata = (struct sof_ipc_ctrl_data *)fragment;

	comp_dbg(mod->dev, "multiband_drc_get_config()");

	return multiband_drc_get_ipc_config(mod, cdata, fragment_size);
}

static int multiband_drc_process(struct processing_module *mod,
				 struct input_stream_buffer *input_buffers, int num_input_buffers,
				 struct output_stream_buffer *output_buffers,
				 int num_output_buffers)
{
	struct multiband_drc_comp_data *cd =  module_get_private_data(mod);
	struct comp_dev *dev = mod->dev;
	struct audio_stream *source = input_buffers[0].data;
	struct audio_stream *sink = output_buffers[0].data;
	int frames = input_buffers[0].size;
	int ret;

	comp_dbg(dev, "multiband_drc_process()");

	/* Check for changed configuration */
	if (comp_is_new_data_blob_available(cd->model_handler)) {
		cd->config = comp_get_data_blob(cd->model_handler, NULL, NULL);
		ret = multiband_drc_setup(mod, (int16_t)audio_stream_get_channels(sink),
					  audio_stream_get_rate(sink));
		if (ret < 0) {
			comp_err(dev, "multiband_drc_process(), failed DRC setup");
			return ret;
		}
	}

	cd->multiband_drc_func(mod, source, sink, frames);

	/* calc new free and available */
	module_update_buffer_position(&input_buffers[0], &output_buffers[0], frames);
	return 0;
}

static int multiband_drc_prepare(struct processing_module *mod,
				 struct sof_source **sources, int num_of_sources,
				 struct sof_sink **sinks, int num_of_sinks)
{
	struct multiband_drc_comp_data *cd = module_get_private_data(mod);
	struct comp_dev *dev = mod->dev;
	struct comp_buffer *sourceb;
	int channels;
	int rate;
	int ret = 0;

	comp_info(dev, "multiband_drc_prepare()");

	ret = multiband_drc_params(mod);
	if (ret < 0)
		return ret;

	/* DRC component will only ever have 1 source and 1 sink buffer */
	sourceb = list_first_item(&dev->bsource_list, struct comp_buffer, sink_list);

	/* get source data format */
	cd->source_format = audio_stream_get_frm_fmt(&sourceb->stream);
	channels = audio_stream_get_channels(&sourceb->stream);
	rate = audio_stream_get_rate(&sourceb->stream);

	/* Initialize DRC */
	comp_dbg(dev, "multiband_drc_prepare(), source_format=%d, sink_format=%d",
		 cd->source_format, cd->source_format);
	cd->config = comp_get_data_blob(cd->model_handler, NULL, NULL);
	if (cd->config && cd->process_enabled) {
		ret = multiband_drc_setup(mod, channels, rate);
		if (ret < 0) {
			comp_err(dev, "multiband_drc_prepare() error: multiband_drc_setup failed.");
			return ret;
		}

		cd->multiband_drc_func = multiband_drc_find_proc_func(cd->source_format);
		if (!cd->multiband_drc_func) {
			comp_err(dev, "multiband_drc_prepare(), No proc func");
			return -EINVAL;
		}

		cd->crossover_split = crossover_find_split_func(cd->config->num_bands);
		if (!cd->crossover_split) {
			comp_err(dev, "multiband_drc_prepare(), No crossover_split for band num %i",
				 cd->config->num_bands);
			return -EINVAL;
		}
	} else {
		comp_info(dev, "multiband_drc_prepare(), DRC is in passthrough mode");
		cd->multiband_drc_func = multiband_drc_find_proc_func_pass(cd->source_format);
		if (!cd->multiband_drc_func) {
			comp_err(dev, "multiband_drc_prepare(), No proc func passthrough");
			return -EINVAL;
		}
	}

	return ret;
}

static int multiband_drc_reset(struct processing_module *mod)
{
	struct multiband_drc_comp_data *cd = module_get_private_data(mod);

	comp_info(mod->dev, "multiband_drc_reset()");

	multiband_drc_reset_state(&cd->state);

	cd->source_format = 0;
	cd->multiband_drc_func = NULL;
	cd->crossover_split = NULL;

	return 0;
}

static const struct module_interface multiband_drc_interface = {
	.init = multiband_drc_init,
	.prepare = multiband_drc_prepare,
	.process_audio_stream = multiband_drc_process,
	.set_configuration = multiband_drc_set_config,
	.get_configuration = multiband_drc_get_config,
	.reset = multiband_drc_reset,
	.free = multiband_drc_free
};

DECLARE_MODULE_ADAPTER(multiband_drc_interface, multiband_drc_uuid, multiband_drc_tr);
SOF_MODULE_INIT(multiband_drc, sys_comp_module_multiband_drc_interface_init);
