# Master chain input V2.6 : host PCM -> mbdrc -> pga -> drc -> muxdemux (cross-pipe)
# Patterns: pipe-volume-playback.m4 (PGA) + pipe-multiband-drc-playback.m4 (mbdrc)
#        + pipe-amp-ref-capture.m4 (muxdemux, 1 sink cross-pipeline uniquement)
#
# Pipeline Endpoints :
#  host PCM_P --B0--> MBDRC --B1--> PGA --B2--> DRC --B3--> MUXDEMUX
#  (puis MUXDEMUX -> PIPELINE_SINK_5 via dapm top-level dans masterlite.m4)
#
# [V2.6 B1] ROUTE_MATRIX stream_id = 5 (SINK pipeline) dans demux_route_default.m4
# [V2.5 K7/K8] Pas de buffer sink local au mux (supprime B4/B5 locaux pour
# eviter same-pipeline sink overwrite + back-pressure fatale).

include(`utils.m4')
include(`buffer.m4')
include(`pcm.m4')
include(`pipeline.m4')
include(`bytecontrol.m4')
include(`mixercontrol.m4')
include(`multiband_drc.m4')
include(`pga.m4')
include(`drc.m4')
include(`muxdemux.m4')
include(`common/tlv.m4')

#
# Controls - Master Volume (mixer control)
#
C_CONTROLMIXER(Master Volume, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 32),
	false,
	CONTROLMIXER_TLV(TLV 32 steps from -64dB to 0dB for 2dB, vtlv_m64s2),
	Channel register and shift for Front Left/Right,
	VOLUME_CHANNEL_MAP)

#
# PGA volume token configuration (prelude canonique)
#
define(DEF_PGA_TOKENS, concat(`pga_tokens_', PIPELINE_ID))
define(DEF_PGA_CONF,   concat(`pga_conf_',   PIPELINE_ID))

W_VENDORTUPLES(DEF_PGA_TOKENS, sof_volume_tokens,
LIST(`		', `SOF_TKN_VOLUME_RAMP_STEP_TYPE	"2"'
     `		', `SOF_TKN_VOLUME_RAMP_STEP_MS		"20"'))

W_DATA(DEF_PGA_CONF, DEF_PGA_TOKENS)

#
# Host PCM playback endpoint ("Source Play")
#
W_PCM_PLAYBACK(PCM_ID, Source Play, 2, 0, SCHEDULE_CORE)

#
# multiband_drc (3 bandes, linked stereo, bypass bit-perfect dispo)
#
define(MULTIBAND_DRC_priv,    concat(`multiband_drc_bytes_',   PIPELINE_ID))
define(MY_MULTIBAND_DRC_CTRL, concat(`multiband_drc_control_', PIPELINE_ID))
include(`multiband_drc_coef_default.m4')
C_CONTROLBYTES(MY_MULTIBAND_DRC_CTRL, PIPELINE_ID,
	CONTROLBYTES_OPS(bytes, 258 binds the control to bytes get/put handlers, 258, 258),
	CONTROLBYTES_EXTOPS(258 binds the control to bytes get/put handlers, 258, 258),
	, , ,
	CONTROLBYTES_MAX(, 1024),
	,
	MULTIBAND_DRC_priv)
W_MULTIBAND_DRC(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE,
	LIST(`		', "MY_MULTIBAND_DRC_CTRL"))

#
# PGA (Programmable Gain Amplifier = volume DVC)
#
W_PGA(0, PIPELINE_FORMAT, 2, 2, DEF_PGA_CONF, SCHEDULE_CORE,
	LIST(`		', "PIPELINE_ID Master Volume"))

#
# drc (final limiter, tunable runtime via Master Limiter Config)
#
define(DRC_priv,    concat(`drc_bytes_',   PIPELINE_ID))
define(MY_DRC_CTRL, concat(`drc_control_', PIPELINE_ID))
include(`drc_coef_default.m4')
C_CONTROLBYTES(MY_DRC_CTRL, PIPELINE_ID,
	CONTROLBYTES_OPS(bytes, 258 binds the control to bytes get/put handlers, 258, 258),
	CONTROLBYTES_EXTOPS(258 binds the control to bytes get/put handlers, 258, 258),
	, , ,
	CONTROLBYTES_MAX(, 1024),
	,
	DRC_priv)
W_DRC(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE,
	LIST(`		', "MY_DRC_CTRL"))

#
# [V2.4+] MUXDEMUX : 1 input (DRC out) -> 1 sink cross-pipeline (PIPE 5)
# Mode demux ($2=1). Pas de sink DAPM local.
#
define(DEMUX_priv,    concat(`demux_priv_', PIPELINE_ID))
define(MY_DEMUX_CTRL, concat(`demux_ctrl_', PIPELINE_ID))
include(`demux_route_default.m4')
C_CONTROLBYTES(MY_DEMUX_CTRL, PIPELINE_ID,
	CONTROLBYTES_OPS(bytes, 258 binds the control to bytes get/put handlers, 258, 258),
	CONTROLBYTES_EXTOPS(258 binds the control to bytes get/put handlers, 258, 258),
	, , ,
	CONTROLBYTES_MAX(, 304),
	,
	DEMUX_priv)
W_MUXDEMUX(0, 1, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE,
	LIST(`		', "MY_DEMUX_CTRL"))

#
# Buffers : host | mbdrc-out | pga-out | drc-out
# Pas de buffer apres le mux - son sink unique est cross-pipeline.
#
W_BUFFER(0, COMP_BUFFER_SIZE(3,
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
W_BUFFER(3, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), PIPELINE_CHANNELS,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_COMP_MEM_CAP)

#
# Pipeline Graph : host -> B0 -> mbdrc -> B1 -> pga -> B2 -> drc -> B3 -> demux
#
P_GRAPH(pipe-master-chain, PIPELINE_ID,
	LIST(`		',
		`dapm(N_BUFFER(0), N_PCMP(PCM_ID))',
		`dapm(N_MULTIBAND_DRC(0), N_BUFFER(0))',
		`dapm(N_BUFFER(1), N_MULTIBAND_DRC(0))',
		`dapm(N_PGA(0), N_BUFFER(1))',
		`dapm(N_BUFFER(2), N_PGA(0))',
		`dapm(N_DRC(0), N_BUFFER(2))',
		`dapm(N_BUFFER(3), N_DRC(0))',
		`dapm(N_MUXDEMUX(0), N_BUFFER(3))'))

#
# Export SCHED_COMP pour permettre a PIPE 5 master tap de piggyback
#
indir(`define', concat(`PIPELINE_SCHED_COMP_', PIPELINE_ID),
      N_PCMP(PCM_ID))

#
# Widget scheduler explicite (PIPE 3 autonome, driven par TIMER)
#
W_PIPELINE(N_PCMP(PCM_ID), SCHEDULE_PERIOD, SCHEDULE_PRIORITY, SCHEDULE_CORE,
           SCHEDULE_TIME_DOMAIN, pipe_media_schedule_plat)

#
# Pas d'export PIPELINE_SOURCE local (pas de sink local en V2.6).
# Le monitor master->HP arrive en Phase 1a.3 via mux merge.
#
indir(`define', concat(`PIPELINE_PCM_', PIPELINE_ID), Source Play PCM_ID)

#
# Export MUXDEMUX widget pour lien cross-pipeline depuis le top-level
# (sink unique = B0 de PIPE 5 Master_Tap, via dapm dans masterlite.m4)
#
indir(`define', concat(`PIPELINE_DEMUX_', PIPELINE_ID), N_MUXDEMUX(0))

#
# PCM capabilities : 2ch s32le @ 48k
#
PCM_CAPABILITIES(Source Play PCM_ID, CAPABILITY_FORMAT_NAME(PIPELINE_FORMAT),
	PCM_MIN_RATE, PCM_MAX_RATE, 2, 2, 2, 16, 192, 16384, 65536, 65536)

undefine(`MY_MULTIBAND_DRC_CTRL')
undefine(`MULTIBAND_DRC_priv')
undefine(`MY_DRC_CTRL')
undefine(`DRC_priv')
undefine(`MY_DEMUX_CTRL')
undefine(`DEMUX_priv')
undefine(`DEF_PGA_TOKENS')
undefine(`DEF_PGA_CONF')
