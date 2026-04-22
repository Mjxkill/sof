# Phase 1a.1 MVP V4.2 — Capture 8ch : effets IN (mbdrc + pga + drc)
#
# Pipeline Endpoints:
#   host PCM_C <-- B0 <-- DRC <-- B1 <-- PGA <-- B2 <-- MULTIBAND_DRC <-- B3 <-- sink DAI
#
# Pattern direct (fusion upstream) :
#   - pipe-multiband-drc-capture.m4  (mbdrc + C_CONTROLBYTES 1024)
#   - pipe-volume-capture.m4         (pga + vendor tuples + C_CONTROLMIXER)
#   - pipe-drc-enabled-capture.m4    (drc + C_CONTROLBYTES 1024)
#
# Blob MBDRC : multiband_drc_coef_passthrough.m4 (bypass : 2 bands, emp_deemp=0)
# Blob DRC   : drc_coef_default.m4 (actif — T5b via variante sans W_DRC pour bit-perfect)
# PAS DE W_PIPELINE — scheduler créé par pipe-dai-capture.m4 via DAI_ADD (même pipeline_id)

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
C_CONTROLMIXER(Master Capture Volume, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 80),
	false,
	CONTROLMIXER_TLV(TLV 80 steps from -50dB to +30dB for 1dB, vtlv_m50s1),
	Channel register and shift for Front Left/Right,
	VOLUME_CHANNEL_MAP)

#
# PGA vendor tuples + data
#
define(DEF_PGA_TOKENS, concat(`pga_tokens_', PIPELINE_ID))
define(DEF_PGA_CONF, concat(`pga_conf_', PIPELINE_ID))

W_VENDORTUPLES(DEF_PGA_TOKENS, sof_volume_tokens,
LIST(`		', `SOF_TKN_VOLUME_RAMP_STEP_TYPE	"0"'
     `		', `SOF_TKN_VOLUME_RAMP_STEP_MS		"250"'))

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
# DRC byte control + default blob (actif — T5b via variante dédiée)
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

# Host "SAI Capture" PCM — 0 sink, 2 source periods
W_PCM_CAPTURE(PCM_ID, SAI Capture, 0, 2, SCHEDULE_CORE)

# MBDRC (first in chain from DAI, last before host)
W_MULTIBAND_DRC(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE,
	LIST(`		', "MY_MULTIBAND_DRC_CTRL"))

# PGA — sink=2, source=DAI_PERIODS (pattern pipe-volume-capture.m4:47)
W_PGA(0, PIPELINE_FORMAT, 2, DAI_PERIODS, DEF_PGA_CONF, SCHEDULE_CORE,
	LIST(`		', "PIPELINE_ID Master Capture Volume"))

# DRC
W_DRC(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE,
	LIST(`		', "MY_DRC_CTRL"))

#
# Buffers : B0 host side, B3 DAI side, B1/B2 inter-widgets
#
W_BUFFER(0, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), PIPELINE_CHANNELS,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)
W_BUFFER(1, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), PIPELINE_CHANNELS,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_COMP_MEM_CAP)
W_BUFFER(2, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), PIPELINE_CHANNELS,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_COMP_MEM_CAP)
W_BUFFER(3, COMP_BUFFER_SIZE(DAI_PERIODS,
	COMP_SAMPLE_SIZE(DAI_FORMAT), PIPELINE_CHANNELS,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_DAI_MEM_CAP)

#
# Pipeline Graph : capture = flux DAI -> host, dapm(sink, source)
#   host PCM_C <-- B0 <-- DRC <-- B1 <-- PGA <-- B2 <-- MBDRC <-- B3 <-- DAI
#
P_GRAPH(pipe-effects-capture, PIPELINE_ID,
	LIST(`		',
	`dapm(N_PCMC(PCM_ID), N_BUFFER(0))',
	`dapm(N_BUFFER(0), N_DRC(0))',
	`dapm(N_DRC(0), N_BUFFER(1))',
	`dapm(N_BUFFER(1), N_PGA(0))',
	`dapm(N_PGA(0), N_BUFFER(2))',
	`dapm(N_BUFFER(2), N_MULTIBAND_DRC(0))',
	`dapm(N_MULTIBAND_DRC(0), N_BUFFER(3))'))

#
# Exports for DAI_ADD : PIPELINE_SINK_N = DAI-side buffer (B3)
#
indir(`define', concat(`PIPELINE_SINK_', PIPELINE_ID), N_BUFFER(3))
indir(`define', concat(`PIPELINE_PCM_', PIPELINE_ID), SAI Capture PCM_ID)

#
# PCM capabilities : 8ch s32le @ 48k
#
PCM_CAPABILITIES(SAI Capture PCM_ID, CAPABILITY_FORMAT_NAME(PIPELINE_FORMAT),
	PCM_MIN_RATE, PCM_MAX_RATE, 2, PIPELINE_CHANNELS, 2, 16,
	192, 16384, 65536, 65536)

undefine(`MY_MULTIBAND_DRC_CTRL')
undefine(`MULTIBAND_DRC_priv')
undefine(`MY_DRC_CTRL')
undefine(`DRC_priv')
undefine(`DEF_PGA_TOKENS')
undefine(`DEF_PGA_CONF')
