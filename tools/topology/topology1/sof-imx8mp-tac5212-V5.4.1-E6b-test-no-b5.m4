#
# V5.4.1 Phase 1a.3 E6.b — TEST D'ISOLATION : matrix_2x8 avec B0 seul (pas de B5)
#
# Variante de sof-imx8mp-tac5212-V5.4.1-E6b-pivot.m4 pour le test GLM job 183689a7 :
# objectif → vérifier si la dépendance cross-pipeline B5 (PIPE 1 mics → matrix_2x8)
# est la cause des échecs play-seul cold-boot et loopback-c 4k fps.
#
# Différences vs E6b-pivot :
#   1. PIPE 1 cap : pipe-eq-drc-pga-8ch-D3-capture (SANS tee_1to2, SANS B5)
#   2. PIPE 2 play : pipe-matrix2x8-playback (matrix B0 seul, pas de mics tap)
#   3. SectionGraph "pipeline-cross-mic-tap" SUPPRIMÉ
#
# Architecture de test :
#
#   PIPE 1 cap : SAI RX → eq → drc → pga → B3(8ch) → PCM 0 (ASIO IN)
#   PIPE 2 play : PCM 1 → B0(8ch) → matrix_2x8 → B100(8ch) → SAI TX 8ch
#
# Si tests 4/4 PASS avec cette topology → cause = B5 cross-pipeline confirmée.
# Si tests restent 1/4 PASS → bug ailleurs (DAI, params propagation pure, scheduler).
#
# DMA scheduling 2ms NON-NÉGOCIABLE.
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
# PIPE 1 : capture 8ch — eq + drc(D3) + pga (SANS tee_1to2)
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
# PIPE 2 : playback 8ch — matrix_2x8 avec B0 seul (pas de cross-pipeline)
#
PIPELINE_PCM_ADD(sof/pipe-matrix2x8-playback.m4,
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

# Pas de SectionGraph cross-pipeline (test d'isolation B5).

#
# SAI7 DAI : TDM 8 slots × 32-bit @ 48kHz, ASYNC mode (V3.2.2 baseline)
#
DAI_CONFIG(SAI, 7, 0, tac5212-hifi,
	SAI_CONFIG(DSP_A, SAI_CLOCK(mclk, 12288000, codec_mclk_in),
		SAI_CLOCK(bclk, 12288000, codec_consumer),
		SAI_CLOCK(fsync, 48000, codec_consumer),
		SAI_TDM(8, 32, 255, 255),
		SAI_CONFIG_DATA(SAI, 7, 0)))
