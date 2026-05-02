#
# V5.4.1 Phase 1a.3 E6.b (pivot 8ch natif) — matrix_2x8 + cross-pipeline mic tap
#
# Évolution depuis E6.b multi-mono (commit 3dd5bbb17, NOK runtime) :
#   - PIPE 2 play : drop deinterleave_8 x 2 + mixer16 + interleave_8
#                   → utiliser matrix_2x8 (1 comp natif 8ch interleaved 2 src → 1 sink)
#   - PIPE 1 cap : inchangé vs E6.b (tee_1to2 post-pga, B5 cross-pipeline export)
#   - SectionGraph cross-pipeline : route BUF1.5 → MATRIX_2X8_2.0
#
# Architecture E6.b pivot complète :
#
#   PIPE 1 cap : SAI RX → eq → drc → pga → B3(8ch) → tee_1to2 ─┬→ B4 → PCM 0 (ASIO IN)
#                                                                └→ B5(8ch) [cross-pipeline]
#                                                                   ↓
#                                                                   └─────────────┐
#                                                                                 ↓
#   PIPE 2 play : PCM 1 → B0(8ch) ──┐                                              │
#                                    ↓                                              │
#                            matrix_2x8 (16x8 identity, src0=ASIO, src1=mics tap)  │
#                                    ↑──────────────────────────────────────────────┘
#                                    ↓
#                                  B100(8ch) → SAI TX 8ch
#
# Identity matrix par défaut : ASIO play[0..7] → output[0..7] passthrough,
# mics[8..15] gain=0 → muet. User active mics via amixer cset (E6.c).
#
# DMA scheduling 2ms NON-NÉGOCIABLE.
# NPU tap V3.2.2 préservé (dai_dma_cb hook orthogonal).
# Fix tee_1to2 unité bytes/frames (commit local) reste actif.

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
# PIPE 1 : capture 8ch — eq + drc(D3) + pga + tee_1to2 (post-pga split, identique E6.b multi-mono)
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
# PIPE 2 : playback 8ch — matrix_2x8 natif (pivot 8ch interleaved)
#
PIPELINE_PCM_ADD(sof/pipe-matrix2x8-with-mics-playback.m4,
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
# Cross-pipeline route : B5 (PIPE 1 mic tap export) → matrix_2x8 source 1 (PIPE 2)
# PIPELINE_MIC_TAP_1 résout en BUF1.5 ; PIPELINE_MIC_INPUT_MATRIX_2 résout en MATRIX_2X8_2.0.
#
SectionGraph."pipeline-cross-mic-tap" {
	index "0"

	lines [
		dapm(PIPELINE_MIC_INPUT_MATRIX_2, PIPELINE_MIC_TAP_1)
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
