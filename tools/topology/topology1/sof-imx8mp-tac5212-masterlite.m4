#
# Topology Phase 1a MVP V2.3 - 4 PCMs :
#   SAI_Capture (8ch), SAI_Playback (8ch), Source_Play (2ch), Master_Tap (2ch)
# Master chain stereo : multiband_drc + pga + drc (limiter)
# Baseline : etend sof-imx8mp-tac5212-drc8ms.m4 en ajoutant master chain + tap
#

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
# PIPE 1 : Dry mics capture 8ch (baseline drc8ms equivalent passthrough)
#
PIPELINE_PCM_ADD(sof/pipe-passthrough-capture.m4,
	1, 0, 8, s32le,
	2000, 0, 0,
	48000, 48000, 48000)

#
# PIPE 6 : Direct playback 8ch (baseline drc8ms equivalent passthrough)
# PCM ID 3 pour eviter collision avec les autres PCMs
#
PIPELINE_PCM_ADD(sof/pipe-passthrough-playback.m4,
	6, 3, 8, s32le,
	2000, 0, 0,
	48000, 48000, 48000)

#
# PIPE 3 : Master chain input (Source_Play PCM 1)
# pipeline CUSTOM local : HOST -> mbdrc -> pga -> drc -> buf
# 12e arg = SCHEDULE_TIME_DOMAIN_TIMER (pipeline autonome TIMER-driven)
#
PIPELINE_PCM_ADD(sof/sof-imx8mp-tac5212-pipe-masterchain.m4,
	3, 1, 2, s32le,
	2000, 0, 0,
	48000, 48000, 48000,
	SCHEDULE_TIME_DOMAIN_TIMER)

#
# PIPE 5 : Master tap (Master_Tap PCM 2)
# Co-scheduled avec PIPE 3 via PIPELINE_SCHED_COMP_3 (13e arg)
#
PIPELINE_PCM_ADD(sof/sof-imx8mp-tac5212-pipe-mastertap.m4,
	5, 2, 2, s32le,
	2000, 0, 0,
	48000, 48000, 48000,
	SCHEDULE_TIME_DOMAIN_TIMER,
	PIPELINE_SCHED_COMP_3)

#
# DAI_ADD : SAI7 RX + TX (identique baseline drc8ms qui fonctionne)
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
# PCM exports : 4 noms distincts, IDs 0/1/2/3
#
PCM_CAPTURE_ADD(SAI_Capture, 0, PIPELINE_PCM_1)
PCM_PLAYBACK_ADD(Source_Play, 1, PIPELINE_PCM_3)
PCM_CAPTURE_ADD(Master_Tap, 2, PIPELINE_PCM_5)
PCM_PLAYBACK_ADD(SAI_Playback, 3, PIPELINE_PCM_6)

#
# [V2.6] Graph cross-pipeline : MUXDEMUX de PIPE 3 -> buffer de PIPE 5
# Le source est un WIDGET (muxdemux), pas un buffer. IPC3 autorise
# dapm(BUF, WIDGET) cross-pipeline mais refuse dapm(BUF, BUF).
# Pattern: sof-smart-amplifier.m4:204 dapm(N_SMART_REF_BUF, N_SMART_DEMUX)
#
SectionGraph."master-chain-to-tap" {
	index "0"
	lines [
		dapm(PIPELINE_SINK_5, PIPELINE_DEMUX_3)
	]
}

#
# DAI config SAI7 TDM 8 slots x 32 bits @ 48kHz
#
DAI_CONFIG(SAI, 7, 0, tac5212-hifi,
	SAI_CONFIG(DSP_A, SAI_CLOCK(mclk, 12288000, codec_mclk_in),
		SAI_CLOCK(bclk, 12288000, codec_consumer),
		SAI_CLOCK(fsync, 48000, codec_consumer),
		SAI_TDM(8, 32, 255, 255),
		SAI_CONFIG_DATA(SAI, 7, 0)))
