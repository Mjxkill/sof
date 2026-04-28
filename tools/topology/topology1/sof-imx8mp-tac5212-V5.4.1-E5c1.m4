#
# V5.4.1 Phase 1a.3 E5.c.1 — topology multi-pipelines cross-buffer test
#
# Pattern miroir de pipe-volume-demux-playback + cross-pipeline binding via SectionGraph.
#
# Pipeline 1 (master) : SAI7 RX 8ch → deinterleave_8 → B1 → host PCM 0 (mono ch0)
# Pipeline 2 (piggyback) : B0_pipe2 ← (cross-pipeline depuis deinterleave_8 sink #2) → host PCM 1 (mono ch1)
# Pipeline 3 (playback V3.2.2-like) : host → volume → SAI7 TX 8ch
#
# But : valider que le pattern multi-pipelines cross-buffer fonctionne avec deinterleave_8.
# Si arecord sur PCM 0 et PCM 1 produisent des données cohérentes (channel 0 et channel 1 distincts) = OK.
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

# Pipeline 1 : master capture avec deinterleave_8
PIPELINE_PCM_ADD(sof/pipe-deinterleave-master-capture.m4,
	1, 0, 1, s32le,
	1000, 0, 0,
	48000, 48000, 48000)

# Pipeline 2 : piggyback host capture mono (sink cross-pipeline)
# 13e arg = sched_comp partagé sur PIPELINE 1 (master)
PIPELINE_PCM_ADD(sof/pipe-host-mono-capture.m4,
	2, 1, 1, s32le,
	1000, 0, 0,
	48000, 48000, 48000,
	SCHEDULE_TIME_DOMAIN_TIMER,
	PIPELINE_SCHED_COMP_1)

# Pipeline 3 : playback V3.2.2-like (volume passthrough)
PIPELINE_PCM_ADD(sof/pipe-volume-playback.m4,
	3, 2, 8, s32le,
	1000, 0, 0,
	48000, 48000, 48000)

# DAI capture SAI7 (vers Pipeline 1)
DAI_ADD(sof/pipe-dai-capture.m4,
	1, SAI, 7, tac5212-hifi,
	PIPELINE_SINK_1, 2, s32le,
	1000, 0, 0, SCHEDULE_TIME_DOMAIN_TIMER)

# DAI playback SAI7 (depuis Pipeline 3)
DAI_ADD(sof/pipe-dai-playback.m4,
	3, SAI, 7, tac5212-hifi,
	PIPELINE_SOURCE_3, 2, s32le,
	1000, 0, 0, SCHEDULE_TIME_DOMAIN_TIMER)

# PCM devices
PCM_CAPTURE_ADD(MasterCap, 0, PIPELINE_PCM_1)
PCM_CAPTURE_ADD(PiggyCap, 1, PIPELINE_PCM_2)
PCM_PLAYBACK_ADD(Play, 2, PIPELINE_PCM_3)

# SectionGraph cross-pipeline : sink #2 de deinterleave_8 (master pipeline 1) vers buffer pipeline 2
SectionGraph."pipe-deinterleave-fanout" {
	index "0"
	lines [
		dapm(PIPELINE_BUFFER_2, PIPELINE_DEINTERLEAVE_1)
	]
}

# SAI7 DAI configuration
DAI_CONFIG(SAI, 7, 0, tac5212-hifi,
	SAI_CONFIG(DSP_A, SAI_CLOCK(mclk, 12288000, codec_mclk_in),
		SAI_CLOCK(bclk, 12288000, codec_consumer),
		SAI_CLOCK(fsync, 48000, codec_consumer),
		SAI_TDM(8, 32, 255, 255),
		SAI_CONFIG_DATA(SAI, 7, 0)))
