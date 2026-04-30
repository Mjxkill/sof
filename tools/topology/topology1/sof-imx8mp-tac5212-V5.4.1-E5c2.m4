#
# V5.4.1 Phase 1a.3 E5.c.2 — multi-pipelines cross-buffer (1 master + 1 piggyback)
#
# Fix 2 bugs vs E5.c.1 (cf TESTS_V5.4.1_E5.c.1.md NOK -22 EINVAL) :
#   1. Ordre m4 : DAI_ADD pipe1 DOIT venir AVANT PIPELINE_PCM_ADD pipe2,
#      car DAI_ADD définit PIPELINE_SCHED_COMP_1 (pipe-dai-capture.m4:24).
#      Sans ça, le 13e arg `PIPELINE_SCHED_COMP_1` est non défini au moment
#      de l'expansion m4 → sched_comp partagé ne se met pas en place.
#   2. W_PIPELINE explicite ajouté dans pipe-host-mono-capture.m4
#      (cf note hpmon-V4.2 : "V1.1 fix B2 : W_PIPELINE explicite OBLIGATOIRE")
#
# Patches firmware E5.c.2 :
#   - deinterleave_8.c : ajout trigger overrun_permitted (pattern mux.c:demux_trigger)
#   - tee_1to2.c : idem (cross-pipeline sinks)
#
# Pipeline 1 (master, capture SAI 8ch) : SAI7 RX → B0(8ch) → deinterleave_8 → B1(mono) → host PCM 0
#                                                                   └── (sink #2 cross-pipeline)
# Pipeline 2 (piggyback, sched=N_DAI_IN(1)) : B0_pipe2(mono) → host PCM 1
# Pipeline 3 (playback) : host → volume → SAI7 TX 8ch
#
# SectionGraph cross-pipeline : dapm(B0_pipe2, deinterleave_8) — sink ← source
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
# PIPE 1 : master capture avec deinterleave_8
# PIPELINE_CHANNELS=8 (cohérent SAI 8ch — required, sinon DAI hw_params -22).
# Le PCM ALSA reste mono via PCM_CAPABILITIES (1,1).
# deinterleave_8.prepare() override les channels (src=8, sinks=1) pour gérer
# le mismatch interne pipe-channels(8) vs sinks-mono(1).
#
PIPELINE_PCM_ADD(sof/pipe-deinterleave-master-capture.m4,
	1, 0, 8, s32le,
	1000, 0, 0,
	48000, 48000, 48000,
	SCHEDULE_TIME_DOMAIN_TIMER)

#
# DAI capture SAI7 (pipe 1) — DOIT venir AVANT PIPELINE_PCM_ADD pipe 2
# car définit PIPELINE_SCHED_COMP_1 = N_DAI_IN(1) (pipe-dai-capture.m4:24)
#
DAI_ADD(sof/pipe-dai-capture.m4,
	1, SAI, 7, tac5212-hifi,
	PIPELINE_SINK_1, 2, s32le,
	1000, 0, 0, SCHEDULE_TIME_DOMAIN_TIMER)

#
# PIPE 2 : piggyback host capture mono
# 13e arg = sched_comp partagé sur PIPE 1 (= N_DAI_IN(1) = "SAI7.IN")
#
PIPELINE_PCM_ADD(sof/pipe-host-mono-capture.m4,
	2, 1, 1, s32le,
	1000, 0, 0,
	48000, 48000, 48000,
	SCHEDULE_TIME_DOMAIN_TIMER,
	PIPELINE_SCHED_COMP_1)

#
# PIPE 3 : playback V3.2.2-like (volume passthrough)
#
PIPELINE_PCM_ADD(sof/pipe-volume-playback.m4,
	3, 2, 8, s32le,
	1000, 0, 0,
	48000, 48000, 48000,
	SCHEDULE_TIME_DOMAIN_TIMER)

#
# DAI playback SAI7 (pipe 3)
#
DAI_ADD(sof/pipe-dai-playback.m4,
	3, SAI, 7, tac5212-hifi,
	PIPELINE_SOURCE_3, 2, s32le,
	1000, 0, 0, SCHEDULE_TIME_DOMAIN_TIMER)

#
# PCM ALSA exports
#
PCM_CAPTURE_ADD(MasterCap, 0, PIPELINE_PCM_1)
PCM_CAPTURE_ADD(PiggyCap, 1, PIPELINE_PCM_2)
PCM_PLAYBACK_ADD(Play, 2, PIPELINE_PCM_3)

#
# SectionGraph cross-pipeline :
#   sink #2 de deinterleave_8 (PIPE 1) → buffer B0 de PIPE 2
#   dapm(sink, source) = dapm(BUF2.0, DEINTERLEAVE_8(1).0)
#
SectionGraph."pipe-deinterleave-fanout" {
	index "0"
	lines [
		dapm(PIPELINE_SINK_2, PIPELINE_DEINTERLEAVE_1)
	]
}

#
# SAI7 DAI : TDM 8 slots × 32-bit @ 48kHz, ASYNC mode (V3.2.2 baseline)
#
DAI_CONFIG(SAI, 7, 0, tac5212-hifi,
	SAI_CONFIG(DSP_A, SAI_CLOCK(mclk, 12288000, codec_mclk_in),
		SAI_CLOCK(bclk, 12288000, codec_consumer),
		SAI_CLOCK(fsync, 48000, codec_consumer),
		SAI_TDM(8, 32, 255, 255),
		SAI_CONFIG_DATA(SAI, 7, 0)))
