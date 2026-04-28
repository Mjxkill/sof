#
# V5.4.1 Phase 1a.3 E5.a — topology test round-trip deinterleave_8 + interleave_8
#
# PCM 0 capture (NEW E5.a) : SAI7 RX 8ch → deinterleave_8 → 8 mono → interleave_8 → host 8ch
# PCM 1 playback (V3.2.2 inchangé) : host → volume → SAI7 TX 8ch
#
# But : valider que deinterleave_8 + interleave_8 fonctionnent dans une vraie pipeline runtime.
# Si arecord 8ch produit des samples cohérents = round-trip OK = E5.a validé.
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

# E5.a capture pipeline (round-trip deinterleave + interleave)
PIPELINE_PCM_ADD(sof/pipe-deinterleave-interleave-capture.m4,
	1, 0, 8, s32le,
	1000, 0, 0,
	48000, 48000, 48000)

# Playback pipeline V3.2.2-like (volume passthrough)
PIPELINE_PCM_ADD(sof/pipe-volume-playback.m4,
	2, 1, 8, s32le,
	1000, 0, 0,
	48000, 48000, 48000)

# Capture DAI - SAI7
DAI_ADD(sof/pipe-dai-capture.m4,
	1, SAI, 7, tac5212-hifi,
	PIPELINE_SINK_1, 2, s32le,
	1000, 0, 0, SCHEDULE_TIME_DOMAIN_TIMER)

# Playback DAI - SAI7
DAI_ADD(sof/pipe-dai-playback.m4,
	2, SAI, 7, tac5212-hifi,
	PIPELINE_SOURCE_2, 2, s32le,
	1000, 0, 0, SCHEDULE_TIME_DOMAIN_TIMER)

PCM_DUPLEX_ADD(TAC5212, 0, PIPELINE_PCM_2, PIPELINE_PCM_1)

# SAI7 DAI configuration
DAI_CONFIG(SAI, 7, 0, tac5212-hifi,
	SAI_CONFIG(DSP_A, SAI_CLOCK(mclk, 12288000, codec_mclk_in),
		SAI_CLOCK(bclk, 12288000, codec_consumer),
		SAI_CLOCK(fsync, 48000, codec_consumer),
		SAI_TDM(8, 32, 255, 255),
		SAI_CONFIG_DATA(SAI, 7, 0)))
