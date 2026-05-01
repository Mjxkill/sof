#
# V5.4.1 Phase 1a.3 E5.e.2-D3 — 8 voies totalement indépendantes (eq + drc + vol)
#
# Architecture 1-comp-8ch (validée Step 1 commit 9cf6fa257) + patch drc D3 pour
# multi-config per-channel.
#
# PIPE 1 cap : SAI7 RX 8ch -> eq_iir(8ch) -> drc(8ch) -> pga(8ch) -> host PCM 0
#                                  ↑              ↑              ↑
#                       8 EQ indép      8 DRC indép        8 vols indép
#                       (blob multi-resp) (blob multi-config) (channel-map)
#
# PIPE 2 play : host PCM 1 -> volume(8ch) -> SAI7 TX 8ch (identique V3.2.2)
#
# Différence vs E5.e.2-step1 (sof-imx8mp-tac5212-V5.4.1-E5e2.m4) :
#   - DRC blob : drc_coef_default_8ch.m4 (756 bytes, 8 params sets)
#   - DRC component : firmware D3-patché (drc.h state arrays + drc_generic.c
#     processing per-channel + back-compat single-config détecté via blob size)
#   - Le firmware D3 reste back-compat avec le tplg E5.e.2-step1 (single-config drc)
#
# DMA scheduling 2ms NON-NÉGOCIABLE (period=2000us, SCHEDULE_TIME_DOMAIN_DMA).

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
# PIPE 1 : capture 8ch — eq_iir + drc(D3 multi-config) + pga (1 comp 8ch chacun)
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
# PIPE 2 : playback V3.2.2-like (volume passthrough 8ch — ASIO OUT)
#
PIPELINE_PCM_ADD(sof/pipe-volume-playback.m4,
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
