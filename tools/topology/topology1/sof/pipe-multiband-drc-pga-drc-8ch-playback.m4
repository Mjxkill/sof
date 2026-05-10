# V7.0-E3 — playback 8ch native avec multiband_drc + pga + drc (strips OUT 8 indép)
#
# Architecture: SAI 8ch interleaved tout du long, miroir du cap V7.0-E2.
#   host PCM 1 -> B0(8ch) -> multiband_drc(8ch, params_per_band 1 ou 8)
#              -> B1(8ch) -> pga(8ch, 8 controls indép via channel-map)
#              -> B2(8ch) -> drc(8ch, blob multi-config 8 DRC indép — patch D3,
#                                  ici utilisé comme LIMITEUR de sortie)
#              -> B3(8ch) -> SAI7 TX
#
# Controls (préfixés OUT — distincts du cap PIPE 1) :
#   - 1 control bytes "Multiband DRC OUT Coefs"  (blob multi-config 8 voies)
#   - 1 control bytes "DRC OUT Config"           (blob limiteur 8 voies)
#   - 8 control mixers "Out Strip[1-8] Volume"
#
# Ordre choisi multiband -> pga -> drc :
#   - multiband fait pré-compression musicale en entrée chaîne play
#   - pga ajuste volume sur le signal pré-compressé
#   - drc en fin de chaîne agit comme limiteur de sortie (anti-clipping speaker)
#
# Indépendance per channel : même mécanique que le cap (V7.0-E2 patch).

include(`utils.m4')
include(`buffer.m4')
include(`pcm.m4')
include(`dai.m4')
include(`pipeline.m4')
include(`mixercontrol.m4')
include(`bytecontrol.m4')
include(`multiband_drc.m4')
include(`drc.m4')
include(`pga.m4')

#
# Coefs : multiband_drc 8ch (V7.0-E2) + drc 8ch (E5.e.2-D3)
#

ifdef(`PIPELINE_FILTER1', , `define(PIPELINE_FILTER1, multiband_drc_coef_default_8ch.m4)')
include(PIPELINE_FILTER1)

ifdef(`PIPELINE_DRC1', , `define(PIPELINE_DRC1, drc_coef_default_8ch.m4)')
include(PIPELINE_DRC1)

#
# Controls
#

# 1 Multiband DRC OUT control
C_CONTROLBYTES(MULTIBAND_DRC_OUT_8CH_CTRL, PIPELINE_ID,
	CONTROLBYTES_OPS(bytes,
		258 binds the control to bytes get/put handlers,
		258, 258),
	CONTROLBYTES_EXTOPS(
		258 binds the control to bytes get/put handlers,
		258, 258),
	, , ,
	CONTROLBYTES_MAX(, 4096),
	,
	MULTIBAND_DRC_priv_8ch)

# 1 DRC OUT control (limiter, multi-config 8 voies D3)
C_CONTROLBYTES(DRC_OUT_8CH_CTRL, PIPELINE_ID,
	CONTROLBYTES_OPS(bytes,
		258 binds the control to bytes get/put handlers,
		258, 258),
	CONTROLBYTES_EXTOPS(
		258 binds the control to bytes get/put handlers,
		258, 258),
	, , ,
	CONTROLBYTES_MAX(, 4096),
	,
	DRC_priv_8ch)

# 8 OUT volumes indép — un C_CONTROLMIXER par channel ALSA position
C_CONTROLMIXER(Out Strip1 Volume, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 80),
	false,
	CONTROLMIXER_TLV(TLV 80 steps from -50dB to +30dB for 1dB, vtlv_m50s1),
	Out Strip1 channel FL,
	LIST(`	', KCONTROL_CHANNEL(FL, 1, 0)))

C_CONTROLMIXER(Out Strip2 Volume, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 80),
	false,
	CONTROLMIXER_TLV(TLV 80 steps from -50dB to +30dB for 1dB, vtlv_m50s1),
	Out Strip2 channel FR,
	LIST(`	', KCONTROL_CHANNEL(FR, 1, 0)))

C_CONTROLMIXER(Out Strip3 Volume, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 80),
	false,
	CONTROLMIXER_TLV(TLV 80 steps from -50dB to +30dB for 1dB, vtlv_m50s1),
	Out Strip3 channel RL,
	LIST(`	', KCONTROL_CHANNEL(RL, 1, 0)))

C_CONTROLMIXER(Out Strip4 Volume, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 80),
	false,
	CONTROLMIXER_TLV(TLV 80 steps from -50dB to +30dB for 1dB, vtlv_m50s1),
	Out Strip4 channel RR,
	LIST(`	', KCONTROL_CHANNEL(RR, 1, 0)))

C_CONTROLMIXER(Out Strip5 Volume, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 80),
	false,
	CONTROLMIXER_TLV(TLV 80 steps from -50dB to +30dB for 1dB, vtlv_m50s1),
	Out Strip5 channel FC,
	LIST(`	', KCONTROL_CHANNEL(FC, 1, 0)))

C_CONTROLMIXER(Out Strip6 Volume, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 80),
	false,
	CONTROLMIXER_TLV(TLV 80 steps from -50dB to +30dB for 1dB, vtlv_m50s1),
	Out Strip6 channel LFE,
	LIST(`	', KCONTROL_CHANNEL(LFE, 1, 0)))

C_CONTROLMIXER(Out Strip7 Volume, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 80),
	false,
	CONTROLMIXER_TLV(TLV 80 steps from -50dB to +30dB for 1dB, vtlv_m50s1),
	Out Strip7 channel SL,
	LIST(`	', KCONTROL_CHANNEL(SL, 1, 0)))

C_CONTROLMIXER(Out Strip8 Volume, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 80),
	false,
	CONTROLMIXER_TLV(TLV 80 steps from -50dB to +30dB for 1dB, vtlv_m50s1),
	Out Strip8 channel SR,
	LIST(`	', KCONTROL_CHANNEL(SR, 1, 0)))

# Volume tokens (ramp config)
define(DEF_PGA_TOKENS, concat(`pga_tokens_', PIPELINE_ID))
define(DEF_PGA_CONF, concat(`pga_conf_', PIPELINE_ID))
W_VENDORTUPLES(DEF_PGA_TOKENS, sof_volume_tokens,
LIST(`		', `SOF_TKN_VOLUME_RAMP_STEP_TYPE	"0"'
     `		', `SOF_TKN_VOLUME_RAMP_STEP_MS		"50"'))
W_DATA(DEF_PGA_CONF, DEF_PGA_TOKENS)

#
# Components
#

# Host playback 8ch (ASIO OUT) — host est SOURCE en playback
W_PCM_PLAYBACK(PCM_ID, ASIO OUT, DAI_PERIODS, 0, SCHEDULE_CORE)

# multiband_drc 8ch
W_MULTIBAND_DRC(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE,
	LIST(`		', "MULTIBAND_DRC_OUT_8CH_CTRL"))

# pga 8ch — 8 channel-mapped indep volume controls
W_PGA(0, PIPELINE_FORMAT, 2, 2, DEF_PGA_CONF, SCHEDULE_CORE,
	LIST(`		',
	"PIPELINE_ID Out Strip1 Volume",
	"PIPELINE_ID Out Strip2 Volume",
	"PIPELINE_ID Out Strip3 Volume",
	"PIPELINE_ID Out Strip4 Volume",
	"PIPELINE_ID Out Strip5 Volume",
	"PIPELINE_ID Out Strip6 Volume",
	"PIPELINE_ID Out Strip7 Volume",
	"PIPELINE_ID Out Strip8 Volume"))

# drc 8ch (limiteur de sortie, multi-config per channel)
W_DRC(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE,
	LIST(`		', "DRC_OUT_8CH_CTRL"))

#
# Buffers (toutes 8ch)
#

# B0 : host PCM → multiband
W_BUFFER(0, COMP_BUFFER_SIZE(DAI_PERIODS,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 8,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)

# B1 : multiband → pga
W_BUFFER(1, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 8,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)

# B2 : pga → drc
W_BUFFER(2, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 8,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)

# B3 : drc → DAI sink
W_BUFFER(3, COMP_BUFFER_SIZE(DAI_PERIODS,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 8,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_DAI_MEM_CAP)

#
# Pipeline graph (linéaire, host source -> DAI sink)
#
P_GRAPH(pipe-multiband-drc-pga-drc-8ch-playback, PIPELINE_ID,
	LIST(`		',
	`dapm(N_BUFFER(0), N_PCMP(PCM_ID))',
	`dapm(N_MULTIBAND_DRC(0), N_BUFFER(0))',
	`dapm(N_BUFFER(1), N_MULTIBAND_DRC(0))',
	`dapm(N_PGA(0), N_BUFFER(1))',
	`dapm(N_BUFFER(2), N_PGA(0))',
	`dapm(N_DRC(0), N_BUFFER(2))',
	`dapm(N_BUFFER(3), N_DRC(0))'))

#
# Exports : PIPELINE_SOURCE = B3 (consommé par DAI sink playback)
#
indir(`define', concat(`PIPELINE_SOURCE_', PIPELINE_ID), N_BUFFER(3))
indir(`define', concat(`PIPELINE_PCM_', PIPELINE_ID), ASIO OUT PCM_ID)

ifdef(`CHANNELS_MIN',`define(`LOCAL_CHANNELS_MIN', `CHANNELS_MIN')',
`define(`LOCAL_CHANNELS_MIN', `2')')

#
# PCM capabilities : 8ch s32le @ 48k (stack Debix std)
#
PCM_CAPABILITIES(ASIO OUT PCM_ID, CAPABILITY_FORMAT_NAME(PIPELINE_FORMAT),
	PCM_MIN_RATE, PCM_MAX_RATE, LOCAL_CHANNELS_MIN, PIPELINE_CHANNELS, 2, 16,
	192, 16384, 65536, 65536)

undefine(`LOCAL_CHANNELS_MIN')
undefine(`DEF_PGA_TOKENS')
undefine(`DEF_PGA_CONF')
