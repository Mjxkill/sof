# Phase 1a.2 V1.2 — Playback 8ch avec effets OUT + tap MUXDEMUX
#
# Pipeline Endpoints:
#   host PCM_P --> B0 --> MBDRC --> B1 --> PGA --> B2 --> DRC --> B3 --> MUXDEMUX -(B4)-> sink DAI
#                                                                             \-(cross)-> PIPE 7 HP_Monitor
#
# Extension de sof-imx8mp-tac5212-pipe-effects-playback.m4 (Phase 1a.1) avec :
#   - W_MUXDEMUX (demux=1) inséré après DRC
#   - B4 devient le buffer DAI side (au lieu de B3)
#   - Export PIPELINE_DEMUX_N = N_MUXDEMUX(0) (widget, PAS buffer — fix V1.1 B1)
#   - Pas de buffer tap intra (fix V1.1 B3 : collision pipeline_id) :
#     le MUXDEMUX alimente directement BUF7.0 de PIPE 7 via SectionGraph top-level
#
# Blob MBDRC : multiband_drc_coef_passthrough.m4 (bypass)
# Blob DRC   : drc_coef_default.m4 (actif)
# Blob DEMUX : demux_route_hpmon.m4 (identity 8ch x 2 sinks : DAI pipe=6 + HP_Monitor pipe=7)
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
include(`muxdemux.m4')

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
# MUXDEMUX byte control + route blob
#
define(DEMUX_priv, concat(`demux_priv_', PIPELINE_ID))
define(MY_DEMUX_CTRL, concat(`demux_control_', PIPELINE_ID))
include(`demux_route_hpmon.m4')
C_CONTROLBYTES(MY_DEMUX_CTRL, PIPELINE_ID,
	CONTROLBYTES_OPS(bytes, 258 binds the control to bytes get/put handlers, 258, 258),
	CONTROLBYTES_EXTOPS(258 binds the control to bytes get/put handlers, 258, 258),
	, , ,
	CONTROLBYTES_MAX(, 304),
	,
	DEMUX_priv)

#
# Components
#

# Host "SAI Playback" PCM — 2 sink, 0 source periods
W_PCM_PLAYBACK(PCM_ID, SAI Playback, 2, 0, SCHEDULE_CORE)

# MBDRC
W_MULTIBAND_DRC(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE,
	LIST(`		', "MY_MULTIBAND_DRC_CTRL"))

# PGA
W_PGA(0, PIPELINE_FORMAT, DAI_PERIODS, 2, DEF_PGA_CONF, SCHEDULE_CORE,
	LIST(`		', "PIPELINE_ID Master Playback Volume"))

# DRC
W_DRC(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE,
	LIST(`		', "MY_DRC_CTRL"))

# W_MUXDEMUX(index, mux_or_demux=1 demux, format, periods_sink, periods_source, core, kcontrols)
W_MUXDEMUX(0, 1, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE,
	LIST(`		', "MY_DEMUX_CTRL"))

#
# Buffers :
#   B0 host side (from PCM_P)
#   B1 inter MBDRC -> PGA
#   B2 inter PGA -> DRC
#   B3 inter DRC -> MUXDEMUX
#   B4 DAI side (from MUXDEMUX -> DAI)
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
W_BUFFER(3, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), PIPELINE_CHANNELS,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_COMP_MEM_CAP, SCHEDULE_CORE)
W_BUFFER(4, COMP_BUFFER_SIZE(DAI_PERIODS,
	COMP_SAMPLE_SIZE(DAI_FORMAT), PIPELINE_CHANNELS,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_DAI_MEM_CAP, SCHEDULE_CORE)

#
# Pipeline Graph : playback = flux host -> DAI, dapm(sink, source)
# Le MUXDEMUX a 1 sink intra (B4 -> DAI) + 1 sink cross (vers BUF7.0 via SectionGraph top-level)
#
P_GRAPH(pipe-effects-playback-tap, PIPELINE_ID,
	LIST(`		',
	`dapm(N_BUFFER(0), N_PCMP(PCM_ID))',
	`dapm(N_MULTIBAND_DRC(0), N_BUFFER(0))',
	`dapm(N_BUFFER(1), N_MULTIBAND_DRC(0))',
	`dapm(N_PGA(0), N_BUFFER(1))',
	`dapm(N_BUFFER(2), N_PGA(0))',
	`dapm(N_DRC(0), N_BUFFER(2))',
	`dapm(N_BUFFER(3), N_DRC(0))',
	`dapm(N_MUXDEMUX(0), N_BUFFER(3))',
	`dapm(N_BUFFER(4), N_MUXDEMUX(0))'))

#
# Exports V1.2 :
#   SOURCE_N = B4 (vers DAI via DAI_ADD)
#   DEMUX_N  = WIDGET N_MUXDEMUX(0) (V1.1 fix B1 : widget, pas buffer)
#
indir(`define', concat(`PIPELINE_SOURCE_', PIPELINE_ID), N_BUFFER(4))
indir(`define', concat(`PIPELINE_DEMUX_',  PIPELINE_ID), N_MUXDEMUX(0))
indir(`define', concat(`PIPELINE_PCM_',    PIPELINE_ID), SAI Playback PCM_ID)

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
undefine(`MY_DEMUX_CTRL')
undefine(`DEMUX_priv')
undefine(`DEF_PGA_TOKENS')
undefine(`DEF_PGA_CONF')
