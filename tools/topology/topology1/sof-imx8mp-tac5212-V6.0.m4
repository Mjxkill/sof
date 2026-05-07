#
# V6.0 — Always-on DAI-to-DAI loopback + ASIO IN/OUT piggyback
#
# Architecture:
#
#   PIPE 1 (always-on, DAI-to-DAI, no HOST):
#     SAI7 RX 8ch --> B0 --> SAI7 TX 8ch
#     (V6.0 minimal: passthrough, no effects/matrix yet — to be enriched
#      with strips IN x8 + matrix_2x8 + strips OUT x8 in V6.1)
#
#   PIPE 2 (PCM capture, on-demand, piggyback on PIPE 1 sched):
#     [tap from PIPE 1] -> B(2) -> HOST PCM 0 (ASIO IN, 8ch s32le)
#     (cross-pipeline tap added via SectionGraph below — V6.1)
#
#   PIPE 3 (PCM playback, on-demand, piggyback on PIPE 1 sched):
#     HOST PCM 1 (ASIO OUT, 8ch s32le) -> B(3) -> [inject into PIPE 1]
#     (cross-pipeline inject added via SectionGraph below — V6.1)
#
# Patches required:
#   Firmware (already in feature/v6-always-on-async branch):
#     F1   : PIPELINE_ATTR_* flags in pipeline.h
#     F3   : pipeline_trigger_run() ignores STOP/PAUSE if IGNORE_STOP
#     F5   : module_adapter_set_state() short-circuits intra-pipeline
#     F2+F4: SOF_IPC_TPLG_PIPE_TRIGGER IPC (kernel triggers always-on)
#     Etape 0: multiband_drc per-channel (8 strip configs)
#
#   Kernel (TODO — K1-K5):
#     - sof-imx8m post_fw_run sends SOF_IPC_TPLG_PIPE_TRIGGER for flagged pipes
#     - topology.c parses SOF_TKN_PIPE_ALWAYS_ON
#     - pcm.c skips STOP IPC for always-on pipelines
#
# DMA scheduling 2ms NON-NÉGOCIABLE.
# TX maître ASYNC sur SAI7, BCLK continu pour TAC5212 PLL.
# NPU tap V3.2.2 (dai_dma_cb hook) untouched.
#

include(`utils.m4')
include(`dai.m4')
include(`pipeline.m4')
include(`sai.m4')
include(`pcm.m4')
include(`buffer.m4')

# Include TLV library
include(`common/tlv.m4')

# Include Token library
include(`sof/tokens.m4')

# Include imx platform definitions
include(`platform/imx/imx8.m4')

#
# PIPE 1 — Always-on DAI-to-DAI loopback (no HOST, no PCM)
#
# Note: PIPELINE_ADD here only creates the loopback buffer scheduler
# (no real source/sink comp anchor). The actual always-on flag must be
# set on the DAI capture's W_PIPELINE (which has source_comp = SAI RX
# comp_dai), so the kernel-side K1 trigger can find a valid anchor for
# pipeline_prepare/pipeline_trigger firmware-side.
#
PIPELINE_ADD(sof/pipe-dai-to-dai-loopback.m4,
	1, 8, s32le,
	2000, 0, 0,
	0, SCHEDULE_TIME_DOMAIN_DMA,
	48000, 48000, 48000)

# DAI capture (SAI7 RX) anchored on PIPE 1 sink (B0). Mark its
# scheduler as always-on so K1 triggers it post-PIPE_COMPLETE.
define(`PIPELINE_ALWAYS_ON', `1')
DAI_ADD(sof/pipe-dai-capture.m4,
	1, SAI, 7, tac5212-hifi,
	PIPELINE_SINK_1, 2, s32le,
	2000, 0, 0, SCHEDULE_TIME_DOMAIN_DMA)
undefine(`PIPELINE_ALWAYS_ON')

# DAI playback (SAI7 TX) anchored on PIPE 1 source (B0, same buffer)
DAI_ADD(sof/pipe-dai-playback.m4,
	1, SAI, 7, tac5212-hifi,
	PIPELINE_SOURCE_1, 2, s32le,
	2000, 0, 0, SCHEDULE_TIME_DOMAIN_DMA)

#
# PIPE 2 / PIPE 3 — TODO: ASIO IN/OUT piggyback (V6.1)
# Will add PIPELINE_PCM_ADD(sof/pipe-passthrough-capture.m4, ...) +
# PIPELINE_PCM_ADD(sof/pipe-passthrough-playback.m4, ...) with
# 13th arg = N_PIPELINE(scheduler-of-PIPE-1) for piggyback scheduling.
# Plus SectionGraph for cross-pipeline tap and inject.
#

#
# DAI configuration: SAI7 TDM 8x32 ASYNC, TX master, codec consumer
#
DAI_CONFIG(SAI, 7, 0, tac5212-hifi,
	SAI_CONFIG(DSP_A,
		SAI_CLOCK(mclk, 12288000, codec_mclk_in),
		SAI_CLOCK(bclk, 12288000, codec_consumer),
		SAI_CLOCK(fsync, 48000, codec_consumer),
		SAI_TDM(8, 32, 255, 255),
		SAI_CONFIG_DATA(SAI, 7, 0)))
