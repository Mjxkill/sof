#
# V5.4.1 Phase 1a.3 E6.a — matrix 16x8 sur PIPE 2 play (Phase A : passthrough ASIO)
#
# Évolution depuis E5.e.2-D3 (commit ea984a266) :
#   - PIPE 1 cap : INCHANGÉ (eq_iir 8ch + drc 8ch D3 + pga 8ch → PCM 0)
#   - PIPE 2 play : remplace volume(8ch) par deinterleave_8 + mixer16 + interleave_8
#
# Architecture E6.a Phase A :
#   PIPE 1 cap : SAI7 RX 8ch -> eq_iir(8ch, 8 EQ indép) -> drc(8ch, 8 DRC indép D3)
#                            -> pga(8ch, 8 vols indép) -> host PCM 0 (ASIO IN 8ch)
#
#   PIPE 2 play : host PCM 1 (ASIO play) -> deinterleave_8 -> 8 mono ASIO play
#                                         -> mixer16(16x8, identity matrix) -> 8 mono
#                                         -> interleave_8 -> SAI7 TX 8ch
#
# Mixer16 (existing comp) configurable via blob de 512 octets (128 cells × 4 octets Q1.31).
# Identity matrix par défaut → passthrough source[0..7] (ASIO play) vers sinks[0..7].
# Sources [8..15] (mics) NON CONNECTÉES en Phase A → num_of_sources=8 dans process loop.
#
# Phase A valide :
#   - 16x8 matrix routing fonctionnel sur 1-pipeline (intra-pipeline, pas cross-pipeline)
#   - Identity matrix → audio bit-perfect ASIO play vers SAI TX (passthrough)
#   - 8 buffers mono branchés intra-PIPE 2 lockés par auto-detection F++ (commit 7499505ec)
#
# Phase B (E6.b future) : ajouter cross-pipeline tap mics depuis PIPE 1 cap (post-pga 8ch
# deinterleavé) vers les sources [8..15] de mixer16 — risque -22 historique à évaluer.
#
# Phase C (E6.c future) : ALSA controls weights pour permettre user de configurer la
# matrice (1 control bytes 512 octets pour la matrice complète, ou 128 controls mixer).
#
# DMA scheduling 2ms NON-NÉGOCIABLE (period=2000us, SCHEDULE_TIME_DOMAIN_DMA).
# NPU tap V3.2.2 préservé (dai_dma_cb hook orthogonal).

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
# PIPE 1 : capture 8ch — eq_iir + drc(D3 multi-config) + pga (cap E5.e.2-D3 inchangé)
#
PIPELINE_PCM_ADD(sof/pipe-eq-drc-pga-8ch-D3-capture.m4,
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
# PIPE 2 : playback 8ch — matrix 16x8 (deinterleave_8 + mixer16 + interleave_8)
#
PIPELINE_PCM_ADD(sof/pipe-matrix-playback.m4,
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
# SAI7 DAI : TDM 8 slots × 32-bit @ 48kHz, ASYNC mode (V3.2.2 baseline)
#
DAI_CONFIG(SAI, 7, 0, tac5212-hifi,
	SAI_CONFIG(DSP_A, SAI_CLOCK(mclk, 12288000, codec_mclk_in),
		SAI_CLOCK(bclk, 12288000, codec_consumer),
		SAI_CLOCK(fsync, 48000, codec_consumer),
		SAI_TDM(8, 32, 255, 255),
		SAI_CONFIG_DATA(SAI, 7, 0)))
