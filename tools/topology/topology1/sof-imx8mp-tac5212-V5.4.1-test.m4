#
# V5.4.1 Phase 1a.3 — TEST topology pour valider widgets m4 tee_1to2/mixer16/interleave_8
# Étape E3 : compile-only test des widgets m4 custom + topology minimale.
#
# Topology mini test :
#   PCM 0 capture : SAI7 RX 8ch → host PCM (V3.2.2 drc.m4 inchangé)
#   PCM 1 playback : host → multiband_drc + pga + drc → SAI7 TX 8ch (V3.2.2 inchangé)
#
# Pipeline 3 (test des 3 NEW comps, isolated, sans connexion DAI) :
#   tee_1to2 (instance test, dummy)
#   mixer16 (instance test, dummy)
#   interleave_8 (instance test, dummy)
#
# But : valider que les 3 widgets m4 expand correctement et qu'alsatplg
# accepte les UUIDs custom dans le tplg. PAS un test fonctionnel runtime.
#

# Include topology builder
include(`utils.m4')
include(`dai.m4')
include(`pipeline.m4')
include(`sai.m4')
include(`pcm.m4')
include(`buffer.m4')

# Include TLV library
include(`common/tlv.m4')

# Include Token library
include(`sof/tokens.m4')

# Include DSP configuration
include(`platform/imx/imx8.m4')

# Include V5.4.1 NEW comp widgets
include(`tee_1to2.m4')
include(`mixer16.m4')
include(`interleave_8.m4')

#
# V3.2.2 baseline — capture + playback pipelines (drc.m4 inchangé)
#

# Capture pipeline with DRC
PIPELINE_PCM_ADD(sof/pipe-drc-capture.m4,
	1, 0, 8, s32le,
	1000, 0, 0,
	48000, 48000, 48000)

# Playback pipeline with DRC
PIPELINE_PCM_ADD(sof/pipe-multiband-drc-playback.m4,
	2, 1, 8, s32le,
	1000, 0, 0,
	48000, 48000, 48000)

# Capture DAI
DAI_ADD(sof/pipe-dai-capture.m4,
	1, SAI, 7, tac5212-hifi,
	PIPELINE_SINK_1, 2, s32le,
	1000, 0, 0, SCHEDULE_TIME_DOMAIN_TIMER)

# Playback DAI
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

#
# V5.4.1 NEW comps test instances (isolated, dummy — just to validate widgets compile)
#
define(`PIPELINE_ID', `99')

W_TEE_1TO2(0, s32le, 2, 2, 0)
W_MIXER16(0, s32le, 2, 2, 0, ` ')
W_INTERLEAVE_8(0, s32le, 2, 2, 0)
