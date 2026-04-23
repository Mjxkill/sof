#
# Topology V4.2 — Phase 1a.1 MVP : console 8ch end-to-end
#
# 2 pipelines 8ch autonomes avec effets linked (mbdrc + pga + drc) :
#   PIPE 1 : SAI7 RX 8ch -> mbdrc -> pga -> drc -> SAI_Capture host
#   PIPE 6 : SAI_Playback host -> mbdrc -> pga -> drc -> SAI7 TX 8ch
#
# SCHEDULE_TIME_DOMAIN_DMA partout (12e arg PIPELINE_PCM_ADD + DAI_ADD).
# Un seul W_PIPELINE par pipeline_id, créé par pipe-dai-{capture,playback}.m4
# via DAI_ADD (pas de W_PIPELINE dans pipe-effects-*.m4).
# Pas de cross-pipeline (Phase 1a.2 ajoutera le tap HP_Monitor).
#
# TAC5212 daisy chain sur SAI7 : TDM 8 slots × 32-bit @ 48kHz, ASYNC mode.

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
# PIPE 1 : Capture 8ch avec effets IN
#
PIPELINE_PCM_ADD(sof/sof-imx8mp-tac5212-pipe-effects-capture.m4,
	1, 0, 8, s32le,
	2000, 0, 0,
	48000, 48000, 48000,
	SCHEDULE_TIME_DOMAIN_DMA)

#
# PIPE 6 : Playback 8ch avec effets OUT
#
PIPELINE_PCM_ADD(sof/sof-imx8mp-tac5212-pipe-effects-playback.m4,
	6, 1, 8, s32le,
	2000, 0, 0,
	48000, 48000, 48000,
	SCHEDULE_TIME_DOMAIN_DMA)

#
# DAI_ADD : SAI7 RX (PIPE 1) et SAI7 TX (PIPE 6)
# Chacun crée le W_PIPELINE pour son pipeline_id via pipe-dai-*.m4
#
DAI_ADD(sof/pipe-dai-capture.m4,
	1, SAI, 7, tac5212-hifi,
	PIPELINE_SINK_1, 2, s32le,
	2000, 0, 0, SCHEDULE_TIME_DOMAIN_DMA)

DAI_ADD(sof/pipe-dai-playback.m4,
	6, SAI, 7, tac5212-hifi,
	PIPELINE_SOURCE_6, 2, s32le,
	2000, 0, 0, SCHEDULE_TIME_DOMAIN_DMA)

#
# PCM ALSA exports : 2 PCMs en MVP (SAI_Capture, SAI_Playback)
#
PCM_CAPTURE_ADD(SAI_Capture, 0, PIPELINE_PCM_1)
PCM_PLAYBACK_ADD(SAI_Playback, 1, PIPELINE_PCM_6)

#
# SAI7 DAI config : TDM 8 slots × 32-bit @ 48kHz, ASYNC mode
# Identique baseline masterlite V2.7 (clocks MCLK 12.288 MHz, codec consumer)
#
DAI_CONFIG(SAI, 7, 0, tac5212-hifi,
	SAI_CONFIG(DSP_A, SAI_CLOCK(mclk, 12288000, codec_mclk_in),
		SAI_CLOCK(bclk, 12288000, codec_consumer),
		SAI_CLOCK(fsync, 48000, codec_consumer),
		SAI_TDM(8, 32, 255, 255),
		SAI_CONFIG_DATA(SAI, 7, 0)))
