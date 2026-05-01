#
# V5.4.1 Phase 1a.3 E5.e.2-step1 — architecture pivot 1-comp-8ch
#
# Pivot après échec empirique de E5.e.2-multi-comp (8 instances eq_iir + 8 drc + 16 pga)
# qui retournait EIO sur PCM read malgré pas de crash firmware.
#
# Architecture corrigée :
#   PIPE 1 cap : SAI7 RX 8ch -> eq_iir(8ch) -> drc(8ch) -> pga(8ch) -> host PCM 0 (ASIO IN)
#                                  ↑                                       ↑
#                          1 comp, 8 EQ indép                  1 comp, 8 vols indép
#                          via blob multi-response               via channel-map
#
#   PIPE 2 play : host PCM 1 -> volume(8ch) -> SAI7 TX 8ch (ASIO OUT identique V3.2.2)
#
# Step 1 limitations (acceptées pour validation archi) :
#   - DRC partagé entre les 8 voies (single-config, sera per-channel après patch D3)
#   - eq_iir blob initial = pass identité (assign_response = -1 sur les 8 ch)
#   - 8 vols indép via channel positions ALSA standard (FL/FR/RL/RR/FC/LFE/SL/SR)
#
# Si Step 1 OK → archi validée → patch drc D3 séparément. Si Step 1 échoue → autre cause.

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
# PIPE 1 : capture 8ch — eq_iir + drc + pga (1 comp 8ch chacun)
#
PIPELINE_PCM_ADD(sof/pipe-eq-drc-pga-8ch-capture.m4,
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
