# V6.0: DAI-to-DAI loopback pipeline (always-on, no HOST)
#
# Architecture:
#   SAI RX (capture DAI) --> B0 --> SAI TX (playback DAI)
#
# This is the minimal V6.0 always-on pipeline: just a passthrough buffer
# between two DAIs, no PCM host, no effects yet. Used as a stepping stone
# to validate the always-on triggering path (F1+F2+F4 + kernel K1-K5)
# before adding strips IN/OUT and matrix_2x8.
#
# Usage:
#   PIPELINE_ALWAYS_ON_ADD(sof/pipe-dai-to-dai-loopback.m4,
#       1, 8, s32le,
#       2000, 0, 0,
#       SCHED_COMP, SCHEDULE_TIME_DOMAIN_DMA,
#       48000, 48000, 48000, 0)
#
#   DAI_ADD(sof/pipe-dai-capture.m4, 1, SAI, 7, ..., PIPELINE_SINK_1, ...)
#   DAI_ADD(sof/pipe-dai-playback.m4, 1, SAI, 7, ..., PIPELINE_SOURCE_1, ...)

# Include topology builder
include(`utils.m4')
include(`buffer.m4')
include(`pipeline.m4')

# PIPELINE_ADD does not initialise DAI_PERIODS; default to DAI_DEFAULT_PERIODS
# so the loopback buffer sizing works without a PCM front-end.
ifdef(`DAI_PERIODS', `', `define(`DAI_PERIODS', DAI_DEFAULT_PERIODS)')

#
# Components
#

# Loopback buffer (8ch, between RX DAI sink and TX DAI source)
W_BUFFER(0, COMP_BUFFER_SIZE(DAI_PERIODS,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), PIPELINE_CHANNELS,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_DAI_MEM_CAP)

#
# Pipeline scheduler widget (carries SOF_TKN_PIPE_ALWAYS_ON when set by
# PIPELINE_ALWAYS_ON_ADD). Stream name is purely informational since this
# pipeline has NO_HOST — the kernel triggers it via SOF_IPC_TPLG_PIPE_TRIGGER.
#
W_PIPELINE(N_BUFFER(0), SCHEDULE_PERIOD, SCHEDULE_PRIORITY, SCHEDULE_CORE,
	SCHEDULE_TIME_DOMAIN, pipe_dai_schedule_plat)

#
# Pipeline source/sink for DAI binding
#

# SINK = where capture DAI deposits frames (B0 input).
# SOURCE = where playback DAI picks frames from (B0 output, same buffer).
indir(`define', concat(`PIPELINE_SINK_',   PIPELINE_ID), N_BUFFER(0))
indir(`define', concat(`PIPELINE_SOURCE_', PIPELINE_ID), N_BUFFER(0))

# No PCM exposure: this is a NO_HOST pipeline. The kernel triggers it
# directly via SOF_IPC_TPLG_PIPE_TRIGGER after SOF_IPC_DAI_CONFIG.
