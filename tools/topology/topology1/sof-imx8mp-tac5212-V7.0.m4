#
# V7.0 — Phase 1 E1 — topology simplifiée (DSP indépendant + ALSA low-lat cible < 10 ms)
#
# Référence : ARCHI/ARCHI_V7.0.pdf §12.3 (E1). Diverge de E6.a (commit SOF 0580b5f14) :
#   - PIPE 1 cap : INCHANGÉ vs E6.a (eq_iir 8ch + drc 8ch D3 + pga 8ch → PCM 0 cap)
#                   → c'est notre référentiel de mesure stable.
#   - PIPE 2 play : SIMPLIFIÉ — host PCM 1 → B0 → SAI7 TX directement.
#                   Retire mixer16, deinterleave_8, interleave_8, buffers mono.
#                   Le routing/mixage est maintenant Linux userspace (V7.0 design).
#
# Architecture V7.0-E1 :
#   PIPE 1 cap : SAI7 RX 8ch -> eq_iir(8ch, 8 EQ indép) -> drc(8ch, 8 DRC indép D3)
#                            -> pga(8ch, 8 vols indép) -> host PCM 0 (ASIO IN 8ch)
#                            (à remplacer par multiband_drc → drc → pga en E2)
#
#   PIPE 2 play : host PCM 1 (ASIO OUT) -> B0 -> SAI7 TX 8ch
#                 (à enrichir par multiband_drc → pga → drc en E3)
#
# DMA scheduling 2ms NON-NÉGOCIABLE (period=2000us, SCHEDULE_TIME_DOMAIN_DMA).
# NPU tap V3.2.2 préservé en E0 ; sera adapté en 2-taps asymétrique en E4/E5.

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
# PIPE 1 : capture 8ch — eq_iir + drc(D3 multi-config) + pga (E6.a inchangé)
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
# PIPE 2 : playback 8ch — passthrough host -> B0 -> SAI7 TX (V7.0 simplifié)
#
PIPELINE_PCM_ADD(sof/pipe-passthrough-8ch-playback.m4,
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
