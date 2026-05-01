#
# V5.4.1 Phase 1a.3 E5.e.1 — 1 strip IN ch1 (eq_iir + drc + pga_L + pga_R) neutre
#
# Architecture E5.d + 1 strip IN sur ch1 :
#   PIPE 1 cap : SAI7 RX 8ch -> deinterleave_8 -> [strip ch1 : eq_iir -> drc -> pga_L -> pga_R]
#                                              -> [bypass ch2..8]
#                                              -> interleave_8 -> host PCM 0 (ASIO IN 8ch)
#   PIPE 2 play : host PCM 1 -> volume -> SAI7 TX 8ch (ASIO OUT 8ch identique V3.2.2)
#
# Test attendu :
#   - Avec eq_iir blob = pass + drc default + vol_L=vol_R=0dB → ch1 doit être bit-perfect = passthrough
#   - amixer doit lister "Strip1 EQ IIR Coefs", "Strip1 DRC Config", "Strip1 Volume L", "Strip1 Volume R"
#   - NPU tap doit voir signal mic correctement traité par strip ch1
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
# PIPE 1 : capture 8ch — strip ch1 + bypass ch2..8
#
PIPELINE_PCM_ADD(sof/pipe-deint-strip1-interleave-capture.m4,
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
