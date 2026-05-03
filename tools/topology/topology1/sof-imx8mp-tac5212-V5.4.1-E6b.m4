#
# V5.4.1 Phase 1a.3 E6.b — matrix 16x8 + cross-pipeline mic tap
#
# Évolution depuis E6.a (commit 0580b5f14) :
#   - PIPE 1 cap : ajoute tee_1to2 post-pga avec sink 1 = cross-pipeline export (B5)
#   - PIPE 2 play : ajoute deinterleave_8 instance #1 + 8 mono mic buffers + connexion
#                   à mixer16 sources [8..15] (étaient non connectés en E6.a)
#   - SectionGraph top-level : route cross-pipeline BUF1.5 → DEINTERLEAVE_82.1
#
# Architecture E6.b complète :
#
#   PIPE 1 cap : SAI RX → eq_iir → drc → pga → B3(8ch) → tee_1to2 ─┬→ B4 → PCM 0 (ASIO IN)
#                                                                    └→ B5(8ch) [cross-pipeline]
#                                                                       ↓
#                                                                       └─────────────┐
#                                                                                     ↓
#   PIPE 2 play : PCM 1 → B0(8ch) → deinterleave_8_a → 8 mono ASIO play → mixer16 src[0..7]
#                                                                              ↓
#                                                            mixer16 (16x8, identity) → 8 mono → interleave_8 → SAI TX
#                                                                              ↑
#   B5(8ch from PIPE 1) → deinterleave_8_b → 8 mono mics → mixer16 src[8..15] (gain=0 par défaut, muet)
#
# Identity matrix par défaut : sources [0..7] (ASIO play) → sinks 0..7 passthrough,
# sources [8..15] (mics) gain=0 → muet. User active mics via amixer cset E6.c.
#
# Risque historique : E5.c.1 a échoué sur cross-pipeline route -22. Ce E6.b teste
# le pattern via tee_1to2 + literal SectionGraph route. Si fail → revert tplg.
#
# DMA scheduling 2ms NON-NÉGOCIABLE (period=2000us, SCHEDULE_TIME_DOMAIN_DMA).
# NPU tap V3.2.2 préservé.

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
# PIPE 1 : capture 8ch — eq_iir + drc(D3) + pga + tee_1to2 (post-pga split)
#
PIPELINE_PCM_ADD(sof/pipe-eq-drc-pga-tee-8ch-D3-capture.m4,
	1, 0, 8, s32le,
	2000, 0, 0,
	48000, 48000, 48000,
	SCHEDULE_TIME_DOMAIN_DMA)

#
# DAI capture SAI7 (pipe 1)
#
DAI_ADD(sof/pipe-dai-capture.m4,
	1, SAI, 7, tac5212-hifi,
	PIPELINE_SINK_1, 2, s32le,
	2000, 0, 0, SCHEDULE_TIME_DOMAIN_DMA)

#
# PIPE 2 : playback 8ch — matrix 16x8 + 2nd deinterleave_8 pour mics
#
PIPELINE_PCM_ADD(sof/pipe-matrix-with-mics-playback.m4,
	2, 1, 8, s32le,
	2000, 0, 0,
	48000, 48000, 48000,
	SCHEDULE_TIME_DOMAIN_DMA)

#
# DAI playback SAI7 (pipe 2)
#
DAI_ADD(sof/pipe-dai-playback.m4,
	2, SAI, 7, tac5212-hifi,
	PIPELINE_SOURCE_2, 2, s32le,
	2000, 0, 0, SCHEDULE_TIME_DOMAIN_DMA)

#
# PCM ALSA export : 1 device duplex 8ch
#
PCM_DUPLEX_ADD(TAC5212, 0, PIPELINE_PCM_2, PIPELINE_PCM_1)

#
# Cross-pipeline route : B5 (PIPE 1 mic tap export) → deinterleave_8 instance 1 (PIPE 2)
# Pattern dapm cross-pipeline standard. PIPELINE_MIC_TAP_1 résout en BUF1.5 ;
# PIPELINE_MIC_INPUT_DEINT_2 résout en DEINTERLEAVE_82.1.
#
SectionGraph."pipeline-cross-mic-tap" {
	index "0"

	lines [
		dapm(PIPELINE_MIC_INPUT_DEINT_2, PIPELINE_MIC_TAP_1)
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
