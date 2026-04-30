#
# V5.4.1 Phase 1a.3 E5.d — passthrough 8ch via deinterleave_8 + interleave_8 (sans cross-pipeline)
#
# Architecture conforme cahier des charges :
#   - 1 PCM ALSA capture 8ch (ASIO IN)
#   - 1 PCM ALSA playback 8ch (ASIO OUT, identique V3.2.2 baseline)
#   - 8 mono buffers RESTENT INTERNES au DSP (jamais exposés à Linux)
#
# Test attendu : arecord -Dhw:2,0 -c 8 -f S32_LE bit-perfect identique au V3.2.2 baseline.
# Si OK → valide deinterleave_8 + interleave_8 + max_sinks=8 + override channels in prepare.
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
# PIPE 1 : capture 8ch — SAI RX → deinterleave_8 → 8 mono internes → interleave_8 → host PCM 0 (8ch)
#
PIPELINE_PCM_ADD(sof/pipe-deint-interleave-capture.m4,
	1, 0, 8, s32le,
	1000, 0, 0,
	48000, 48000, 48000,
	SCHEDULE_TIME_DOMAIN_TIMER)

#
# DAI capture SAI7 (pipe 1)
#
DAI_ADD(sof/pipe-dai-capture.m4,
	1, SAI, 7, tac5212-hifi,
	PIPELINE_SINK_1, 2, s32le,
	1000, 0, 0, SCHEDULE_TIME_DOMAIN_TIMER)

#
# PIPE 2 : playback V3.2.2-like (volume passthrough 8ch — ASIO OUT)
#
PIPELINE_PCM_ADD(sof/pipe-volume-playback.m4,
	2, 1, 8, s32le,
	1000, 0, 0,
	48000, 48000, 48000,
	SCHEDULE_TIME_DOMAIN_TIMER)

#
# DAI playback SAI7 (pipe 2)
#
DAI_ADD(sof/pipe-dai-playback.m4,
	2, SAI, 7, tac5212-hifi,
	PIPELINE_SOURCE_2, 2, s32le,
	1000, 0, 0, SCHEDULE_TIME_DOMAIN_TIMER)

#
# PCM ALSA exports : 2 devices séparés (cap=hw:2,0, play=hw:2,1)
# Cohérent avec scripts utilisateur loopback-lowlat.sh / loopback-pipe.sh.
#
PCM_CAPTURE_ADD(SAI_Capture, 0, PIPELINE_PCM_1)
PCM_PLAYBACK_ADD(SAI_Playback, 1, PIPELINE_PCM_2)

#
# SAI7 DAI : TDM 8 slots × 32-bit @ 48kHz, ASYNC mode (V3.2.2 baseline)
#
DAI_CONFIG(SAI, 7, 0, tac5212-hifi,
	SAI_CONFIG(DSP_A, SAI_CLOCK(mclk, 12288000, codec_mclk_in),
		SAI_CLOCK(bclk, 12288000, codec_consumer),
		SAI_CLOCK(fsync, 48000, codec_consumer),
		SAI_TDM(8, 32, 255, 255),
		SAI_CONFIG_DATA(SAI, 7, 0)))
