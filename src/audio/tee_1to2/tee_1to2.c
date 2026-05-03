// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright(c) 2026 Electrosens. All rights reserved.
//
// V5.4.1 Phase 1a.3 — fan-out 1 mono source -> 2 mono sinks (identical).
// Used to split each strip-IN output into matrix-input + capture-host branches.
//
// STREAM mode (proc_type=AUDIO_STREAM, max_sources=1, max_sinks=2). The
// module_adapter.c:258 check "max_sources>1 && max_sinks>1" does NOT block
// 1x2 (1>1 = false). The framework iterates output_buffers[0..1] and calls
// comp_update_buffer_produce on each sink. We just need to write the same
// data into both sinks.

#include <sof/audio/component.h>
#include <sof/audio/format.h>
#include <sof/audio/module_adapter/module/generic.h>
#include <sof/lib/uuid.h>
#include <sof/list.h>
#include <sof/trace/trace.h>
#include <ipc/topology.h>
#include <rtos/init.h>
#include <stddef.h>
#include <stdint.h>

LOG_MODULE_REGISTER(tee_1to2, CONFIG_SOF_LOG_LEVEL);

/* e1ec7700-5e44-4abc-b1f9-3c14e2d2afe1 */
DECLARE_SOF_RT_UUID("tee_1to2", tee_1to2_uuid, 0xe1ec7700, 0x5e44, 0x4abc,
		    0xb1, 0xf9, 0x3c, 0x14, 0xe2, 0xd2, 0xaf, 0xe1);

DECLARE_TR_CTX(tee_1to2_tr, SOF_UUID(tee_1to2_uuid), LOG_LEVEL_INFO);

#define TEE_1TO2_MAX_SINKS 2

static int tee_1to2_init(struct processing_module *mod)
{
	mod->max_sources = 1;
	mod->max_sinks = TEE_1TO2_MAX_SINKS;
	comp_dbg(mod->dev, "tee_1to2_init()");
	return 0;
}

static int tee_1to2_prepare(struct processing_module *mod,
			    struct sof_source **sources, int num_of_sources,
			    struct sof_sink **sinks, int num_of_sinks)
{
	struct comp_dev *dev = mod->dev;
	struct list_item *blist;
	struct comp_buffer *src_buf = NULL;
	struct comp_buffer *buf;
	uint16_t src_channels;

	comp_dbg(dev, "tee_1to2_prepare()");
	mod->max_sources = 1;
	mod->max_sinks = TEE_1TO2_MAX_SINKS;

	list_for_item(blist, &dev->bsource_list) {
		src_buf = container_of(blist, struct comp_buffer, sink_list);
		break;
	}
	if (!src_buf)
		return 0;
	src_channels = audio_stream_get_channels(&src_buf->stream);
	if (!src_channels)
		return 0;
	list_for_item(blist, &dev->bsink_list) {
		buf = container_of(blist, struct comp_buffer, source_list);
		audio_stream_set_channels(&buf->stream, src_channels);
	}
	return 0;
}

static int tee_1to2_process(struct processing_module *mod,
			    struct input_stream_buffer *in_buf, int num_in,
			    struct output_stream_buffer *out_buf, int num_out)
{
	struct audio_stream *src;
	struct audio_stream *dst;
	uint32_t frames;
	uint32_t nch;
	uint32_t samples;
	int i;

	if (num_in < 1 || num_out < 1)
		return 0;

	src = in_buf[0].data;
	frames = in_buf[0].size;
	nch = audio_stream_get_channels(src);
	samples = frames * nch;

	/* V5.4.1 E6.b fix: output_stream_buffer.size is consumed in BYTES by the
	 * framework's comp_update_buffer_produce(). Set per-sink in BYTES.
	 * The previous code mixed units (set frames here, then called
	 * module_update_buffer_position which only adds frame_bytes*frames to
	 * out_buf[0]) — out_buf[0] over-produced and out_buf[1] under-produced
	 * proportionally to nch, freezing both endpoints in 8ch mode.
	 */
	for (i = 0; i < num_out; i++) {
		dst = out_buf[i].data;
		audio_stream_copy(src, 0, dst, 0, samples);
		out_buf[i].size = audio_stream_frame_bytes(dst) * frames;
	}

	in_buf[0].consumed = audio_stream_frame_bytes(src) * frames;
	return 0;
}

static int tee_1to2_trigger(struct processing_module *mod, int cmd)
{
	struct list_item *li;
	struct comp_buffer *b;

	/* Cross-pipeline sinks: foreign pipelines may not start synchronously
	 * with ours (host-driven). Set overrun_permitted on cross-pipeline
	 * sinks to avoid back-pressure stalls — those sinks are responsible
	 * for flushing themselves. Pattern copied from mux.c:demux_trigger.
	 */
	if (cmd == COMP_TRIGGER_PRE_START) {
		list_for_item(li, &mod->dev->bsink_list) {
			b = container_of(li, struct comp_buffer, source_list);
			if (b->sink->pipeline != mod->dev->pipeline)
				audio_stream_set_overrun(&b->stream, true);
		}
	}
	return module_adapter_set_state(mod, mod->dev, cmd);
}

static int tee_1to2_reset(struct processing_module *mod)
{
	comp_dbg(mod->dev, "tee_1to2_reset()");
	return 0;
}

static int tee_1to2_free(struct processing_module *mod)
{
	comp_dbg(mod->dev, "tee_1to2_free()");
	return 0;
}

static const struct module_interface tee_1to2_interface = {
	.init = tee_1to2_init,
	.prepare = tee_1to2_prepare,
	.process_audio_stream = tee_1to2_process,
	.trigger = tee_1to2_trigger,
	.reset = tee_1to2_reset,
	.free = tee_1to2_free,
};

DECLARE_MODULE_ADAPTER(tee_1to2_interface, tee_1to2_uuid, tee_1to2_tr);
SOF_MODULE_INIT(tee_1to2, sys_comp_module_tee_1to2_interface_init);
