#
# V5.4.1 Phase 1a.3 E3.c — topology fonctionnelle test tee_1to2 inséré dans pipeline playback
#
# PCM 0 capture (V3.2.2 baseline drc inchangé) : SAI7 RX 8ch -> drc -> host
# PCM 1 playback (NEW) : host -> tee_1to2 -> volume -> SAI7 TX 8ch
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

# V3.2.2 baseline capture pipeline (drc)
PIPELINE_PCM_ADD(sof/pipe-drc-capture.m4,
	1, 0, 8, s32le,
	1000, 0, 0,
	48000, 48000, 48000)

# E3.c playback pipeline avec tee_1to2 inséré
PIPELINE_PCM_ADD(sof/pipe-tee-volume-playback.m4,
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
