# Phase 1a.1 MVP V4.2 — Playback 8ch : effets OUT (mbdrc + pga + drc)
#
# Pipeline Endpoints:
#   host PCM_P --> B0 --> MULTIBAND_DRC --> B1 --> PGA --> B2 --> DRC --> B3 --> sink DAI
#
# Pattern direct (fusion upstream) :
#   - pipe-multiband-drc-playback.m4 (mbdrc + C_CONTROLBYTES 1024)
#   - pipe-volume-playback.m4        (pga + vendor tuples + C_CONTROLMIXER)
#   - drc widget ajouté (pattern pipe-drc-enabled-capture.m4 inversé)
#
# Blob MBDRC : multiband_drc_coef_passthrough.m4 (bypass)
# Blob DRC   : drc_coef_default.m4 (actif — T5b via variante sans W_DRC)
# PAS DE W_PIPELINE — scheduler créé par pipe-dai-playback.m4 via DAI_ADD (même pipeline_id)

# Include topology builder
include(`utils.m4')
include(`buffer.m4')
include(`pcm.m4')
include(`dai.m4')
include(`bytecontrol.m4')
include(`mixercontrol.m4')
include(`pipeline.m4')
include(`multiband_drc.m4')
include(`pga.m4')
include(`drc.m4')

#
# Controls : PGA volume mixer kcontrol
#
C_CONTROLMIXER(Master Playback Volume, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 32),
	false,
	CONTROLMIXER_TLV(TLV 32 steps from -64dB to 0dB for 2dB, vtlv_m64s2),
	Channel register and shift for Front Left/Right,
	VOLUME_CHANNEL_MAP)

#
# PGA vendor tuples + data
#
define(DEF_PGA_TOKENS, concat(`pga_tokens_', PIPELINE_ID))
define(DEF_PGA_CONF, concat(`pga_conf_', PIPELINE_ID))

W_VENDORTUPLES(DEF_PGA_TOKENS, sof_volume_tokens,
LIST(`		', `SOF_TKN_VOLUME_RAMP_STEP_TYPE	"2"'
     `		', `SOF_TKN_VOLUME_RAMP_STEP_MS		"20"'))

W_DATA(DEF_PGA_CONF, DEF_PGA_TOKENS)

#
# MBDRC byte control + passthrough blob
#
define(MULTIBAND_DRC_priv, concat(`multiband_drc_bytes_', PIPELINE_ID))
define(MY_MULTIBAND_DRC_CTRL, concat(`multiband_drc_control_', PIPELINE_ID))
include(`multiband_drc_coef_passthrough.m4')
C_CONTROLBYTES(MY_MULTIBAND_DRC_CTRL, PIPELINE_ID,
	CONTROLBYTES_OPS(bytes, 258 binds the control to bytes get/put handlers, 258, 258),
	CONTROLBYTES_EXTOPS(258 binds the control to bytes get/put handlers, 258, 258),
	, , ,
	CONTROLBYTES_MAX(, 1024),
	,
	MULTIBAND_DRC_priv)

#
# DRC byte control + default blob
#
define(DRC_priv, concat(`drc_bytes_', PIPELINE_ID))
define(MY_DRC_CTRL, concat(`drc_control_', PIPELINE_ID))
include(`drc_coef_default.m4')
C_CONTROLBYTES(MY_DRC_CTRL, PIPELINE_ID,
	CONTROLBYTES_OPS(bytes, 258 binds the control to bytes get/put handlers, 258, 258),
	CONTROLBYTES_EXTOPS(258 binds the control to bytes get/put handlers, 258, 258),
	, , ,
	CONTROLBYTES_MAX(, 1024),
	,
	DRC_priv)

#
# Components
#

# Host "SAI Playback" PCM — 2 sink, 0 source periods
W_PCM_PLAYBACK(PCM_ID, SAI Playback, 2, 0, SCHEDULE_CORE)

# MBDRC
W_MULTIBAND_DRC(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE,
	LIST(`		', "MY_MULTIBAND_DRC_CTRL"))

# PGA — sink=DAI_PERIODS, source=2 (pattern pipe-volume-playback.m4:50 inversé)
W_PGA(0, PIPELINE_FORMAT, DAI_PERIODS, 2, DEF_PGA_CONF, SCHEDULE_CORE,
	LIST(`		', "PIPELINE_ID Master Playback Volume"))

# DRC
W_DRC(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE,
	LIST(`		', "MY_DRC_CTRL"))

#
# Buffers : B0 host side, B3 DAI side, B1/B2 inter-widgets
#
W_BUFFER(0, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), PIPELINE_CHANNELS,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP, SCHEDULE_CORE)
W_BUFFER(1, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), PIPELINE_CHANNELS,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_COMP_MEM_CAP, SCHEDULE_CORE)
W_BUFFER(2, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), PIPELINE_CHANNELS,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_COMP_MEM_CAP, SCHEDULE_CORE)
W_BUFFER(3, COMP_BUFFER_SIZE(DAI_PERIODS,
	COMP_SAMPLE_SIZE(DAI_FORMAT), PIPELINE_CHANNELS,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_DAI_MEM_CAP, SCHEDULE_CORE)

#
# Pipeline Graph : playback = flux host -> DAI, dapm(sink, source)
#   host PCM_P --> B0 --> MBDRC --> B1 --> PGA --> B2 --> DRC --> B3 --> DAI
#
P_GRAPH(pipe-effects-playback, PIPELINE_ID,
	LIST(`		',
	`dapm(N_BUFFER(0), N_PCMP(PCM_ID))',
	`dapm(N_MULTIBAND_DRC(0), N_BUFFER(0))',
	`dapm(N_BUFFER(1), N_MULTIBAND_DRC(0))',
	`dapm(N_PGA(0), N_BUFFER(1))',
	`dapm(N_BUFFER(2), N_PGA(0))',
	`dapm(N_DRC(0), N_BUFFER(2))',
	`dapm(N_BUFFER(3), N_DRC(0))'))

#
# Exports for DAI_ADD : PIPELINE_SOURCE_N = DAI-side buffer (B3)
#
indir(`define', concat(`PIPELINE_SOURCE_', PIPELINE_ID), N_BUFFER(3))
indir(`define', concat(`PIPELINE_PCM_', PIPELINE_ID), SAI Playback PCM_ID)

#
# PCM capabilities : 8ch s32le @ 48k
#
PCM_CAPABILITIES(SAI Playback PCM_ID, CAPABILITY_FORMAT_NAME(PIPELINE_FORMAT),
	PCM_MIN_RATE, PCM_MAX_RATE, 2, PIPELINE_CHANNELS, 2, 16,
	192, 16384, 65536, 65536)

undefine(`MY_MULTIBAND_DRC_CTRL')
undefine(`MULTIBAND_DRC_priv')
undefine(`MY_DRC_CTRL')
undefine(`DRC_priv')
undefine(`DEF_PGA_TOKENS')
undefine(`DEF_PGA_CONF')
