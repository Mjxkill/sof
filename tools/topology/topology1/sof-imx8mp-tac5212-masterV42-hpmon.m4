#
# Topology V4.2 + Phase 1a.2 V1.2 — HP_Monitor tap post-effets OUT
#
# 3 pipelines :
#   PIPE 1 : SAI7 RX 8ch -> mbdrc -> pga -> drc -> SAI_Capture (host)
#   PIPE 6 : SAI_Playback (host) -> mbdrc -> pga -> drc -> MUXDEMUX -> SAI7 TX 8ch
#                                                             \-(cross)-> PIPE 7
#   PIPE 7 : (cross-pipeline) -> B0 -> HP_Monitor (host)
#
# PIPE 7 piggyback sched sur PIPE 6 via PIPELINE_PLAYBACK_SCHED_COMP_6 = N_DAI_OUT = SAI7.OUT
# Le sched_comp partagé fait passer le guard pipeline-stream.c:505 is_same_sched.
#
# ORDRE V1.2 CRITIQUE (fix bug m4 V1.1 identifié par gemini+claude-code) :
#   DAI_ADD PIPE 6 DOIT venir AVANT PIPELINE_PCM_ADD PIPE 7
#   car il définit PIPELINE_PLAYBACK_SCHED_COMP_6 via pipe-dai-playback.m4:24.
#   Pattern upstream confirmé : sof-imx8mp-wm8960-kwd.m4 (DAI_ADD maître avant piggyback).

include(`utils.m4')
include(`dai.m4')
include(`pipeline.m4')
include(`sai.m4')
include(`pcm.m4')
include(`buffer.m4')

include(`common/tlv.m4')
include(`sof/tokens.m4')
include(`platform/imx/imx8.m4')

#
# PIPE 1 : Capture 8ch avec effets IN (inchangé Phase 1a.1)
#
PIPELINE_PCM_ADD(sof/sof-imx8mp-tac5212-pipe-effects-capture.m4,
	1, 0, 8, s32le,
	2000, 0, 0,
	48000, 48000, 48000,
	SCHEDULE_TIME_DOMAIN_DMA)

#
# PIPE 6 : Playback 8ch avec effets OUT + MUXDEMUX tap en fin
#
PIPELINE_PCM_ADD(sof/sof-imx8mp-tac5212-pipe-effects-playback-tap.m4,
	6, 1, 8, s32le,
	2000, 0, 0,
	48000, 48000, 48000,
	SCHEDULE_TIME_DOMAIN_DMA)

#
# DAI_ADD PIPE 6 : DOIT être ici pour définir PIPELINE_PLAYBACK_SCHED_COMP_6
# (utilisé par PIPE 7 piggyback ci-dessous)
#
DAI_ADD(sof/pipe-dai-playback.m4,
	6, SAI, 7, tac5212-hifi,
	PIPELINE_SOURCE_6, 2, s32le,
	2000, 0, 0, SCHEDULE_TIME_DOMAIN_DMA)

#
# PIPE 7 : HP_Monitor capture, piggyback sched sur PIPE 6
#   12e arg SCHEDULE_TIME_DOMAIN_DMA (requis par W_PIPELINE)
#   13e arg PIPELINE_PLAYBACK_SCHED_COMP_6 = N_DAI_OUT(6) = "SAI7.OUT"
#
PIPELINE_PCM_ADD(sof/sof-imx8mp-tac5212-pipe-hp-monitor-capture.m4,
	7, 2, 8, s32le,
	2000, 0, 0,
	48000, 48000, 48000,
	SCHEDULE_TIME_DOMAIN_DMA,
	PIPELINE_PLAYBACK_SCHED_COMP_6)

#
# DAI_ADD PIPE 1 (ordre indifférent, PIPE 1 autonome sans piggyback)
#
DAI_ADD(sof/pipe-dai-capture.m4,
	1, SAI, 7, tac5212-hifi,
	PIPELINE_SINK_1, 2, s32le,
	2000, 0, 0, SCHEDULE_TIME_DOMAIN_DMA)

#
# PCM ALSA exports : 3 PCMs
#
PCM_CAPTURE_ADD(SAI_Capture, 0, PIPELINE_PCM_1)
PCM_PLAYBACK_ADD(SAI_Playback, 1, PIPELINE_PCM_6)
PCM_CAPTURE_ADD(HP_Monitor, 2, PIPELINE_PCM_7)

#
# Graph cross-pipeline : tap PIPE 6 MUXDEMUX -> PIPE 7 sink buffer
# dapm(sink, source) = dapm(BUF7.0, MUXDEMUX6.0)
#
SectionGraph."pipe-tap-hpmon" {
	index "0"
	lines [
		dapm(PIPELINE_SINK_7, PIPELINE_DEMUX_6)
	]
}

#
# SAI7 DAI config : TDM 8 slots × 32-bit @ 48kHz, ASYNC mode (identique Phase 1a.1)
#
DAI_CONFIG(SAI, 7, 0, tac5212-hifi,
	SAI_CONFIG(DSP_A, SAI_CLOCK(mclk, 12288000, codec_mclk_in),
		SAI_CLOCK(bclk, 12288000, codec_consumer),
		SAI_CLOCK(fsync, 48000, codec_consumer),
		SAI_TDM(8, 32, 255, 255),
		SAI_CONFIG_DATA(SAI, 7, 0)))
