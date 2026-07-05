# V7.0-E2 — capture 8ch native avec multiband_drc + drc D3 + pga 8ch indép
#
# Architecture: SAI 8ch interleaved tout du long, pas de split mono.
#   SAI7 RX 8ch -> B0(8ch) -> multiband_drc(8ch, params_per_band 1 ou 8)
#               -> B1(8ch) -> drc(8ch, blob multi-config 8 DRC indép — patch D3)
#               -> B2(8ch) -> pga(8ch, 8 controls indép via channel-map)
#               -> B3(8ch) -> host PCM 0
#
# Controls:
#   - 1 control bytes "Multiband DRC Coefs" (legacy default OR V7.0-E2 8 configs)
#   - 1 control bytes "DRC Config"   (blob multi-config 8 DRC indép — D3 patch)
#   - 8 control mixers "Strip[1-8] Volume"
#
# Indépendance per channel :
#   - multiband_drc : params_per_band auto-détecté par taille blob (patch V7.0-E2)
#                     1 = legacy comportement, N = N params per band per channel
#   - drc           : sof_drc_config size > sizeof(struct) -> N consecutive params per-channel
#   - pga           : channel-map FL/FR/RL/RR/FC/LFE/SL/SR sur 1 comp 8ch
#
# NPU tap V3.2.2 préservé (dai_dma_cb hook orthogonal au pipeline DSP).

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
# Coefs : multiband_drc default + drc default
#

ifdef(`PIPELINE_FILTER1', , `define(PIPELINE_FILTER1, multiband_drc_coef_default_8ch.m4)')
include(PIPELINE_FILTER1)

ifdef(`PIPELINE_DRC1', , `define(PIPELINE_DRC1, drc_coef_default_8ch.m4)')
include(PIPELINE_DRC1)

#
# Controls
#

# 1 Multiband DRC control (blob — auto-détection params_per_band par taille)
C_CONTROLBYTES(MULTIBAND_DRC_8CH_CTRL, PIPELINE_ID,
	CONTROLBYTES_OPS(bytes,
		258 binds the control to bytes get/put handlers,
		258, 258),
	CONTROLBYTES_EXTOPS(
		258 binds the control to bytes get/put handlers,
		258, 258),
	, , ,
	CONTROLBYTES_MAX(, 6144),
	,
	MULTIBAND_DRC_priv_8ch)

# 1 DRC control (blob multi-config 8 DRC indép — D3 patch)
C_CONTROLBYTES(DRC_8CH_CTRL, PIPELINE_ID,
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

# 8 volumes indép — un C_CONTROLMIXER par channel ALSA position
C_CONTROLMIXER(Strip1 Volume, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 80),
	false,
	CONTROLMIXER_TLV(TLV 80 steps from -50dB to +30dB for 1dB, vtlv_m50s1),
	Strip1 channel FL,
	LIST(`	', KCONTROL_CHANNEL(FL, 1, 0)))

C_CONTROLMIXER(Strip2 Volume, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 80),
	false,
	CONTROLMIXER_TLV(TLV 80 steps from -50dB to +30dB for 1dB, vtlv_m50s1),
	Strip2 channel FR,
	LIST(`	', KCONTROL_CHANNEL(FR, 1, 0)))

C_CONTROLMIXER(Strip3 Volume, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 80),
	false,
	CONTROLMIXER_TLV(TLV 80 steps from -50dB to +30dB for 1dB, vtlv_m50s1),
	Strip3 channel RL,
	LIST(`	', KCONTROL_CHANNEL(RL, 1, 0)))

C_CONTROLMIXER(Strip4 Volume, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 80),
	false,
	CONTROLMIXER_TLV(TLV 80 steps from -50dB to +30dB for 1dB, vtlv_m50s1),
	Strip4 channel RR,
	LIST(`	', KCONTROL_CHANNEL(RR, 1, 0)))

C_CONTROLMIXER(Strip5 Volume, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 80),
	false,
	CONTROLMIXER_TLV(TLV 80 steps from -50dB to +30dB for 1dB, vtlv_m50s1),
	Strip5 channel FC,
	LIST(`	', KCONTROL_CHANNEL(FC, 1, 0)))

C_CONTROLMIXER(Strip6 Volume, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 80),
	false,
	CONTROLMIXER_TLV(TLV 80 steps from -50dB to +30dB for 1dB, vtlv_m50s1),
	Strip6 channel LFE,
	LIST(`	', KCONTROL_CHANNEL(LFE, 1, 0)))

C_CONTROLMIXER(Strip7 Volume, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 80),
	false,
	CONTROLMIXER_TLV(TLV 80 steps from -50dB to +30dB for 1dB, vtlv_m50s1),
	Strip7 channel SL,
	LIST(`	', KCONTROL_CHANNEL(SL, 1, 0)))

C_CONTROLMIXER(Strip8 Volume, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 80),
	false,
	CONTROLMIXER_TLV(TLV 80 steps from -50dB to +30dB for 1dB, vtlv_m50s1),
	Strip8 channel SR,
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

# Host capture 8ch (ASIO IN)
W_PCM_CAPTURE(PCM_ID, ASIO IN, 0, 2, SCHEDULE_CORE)

# multiband_drc 8ch — default blob (params_per_band = 1, legacy compat ; T2.0)
W_MULTIBAND_DRC(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE,
	LIST(`		', "MULTIBAND_DRC_8CH_CTRL"))

# drc 8ch — multi-config blob (8 DRC indép — patch D3)
W_DRC(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE,
	LIST(`		', "DRC_8CH_CTRL"))

# pga 8ch — 8 channel-mapped indep volume controls
W_PGA(0, PIPELINE_FORMAT, 2, 2, DEF_PGA_CONF, SCHEDULE_CORE,
	LIST(`		',
	"PIPELINE_ID Strip1 Volume",
	"PIPELINE_ID Strip2 Volume",
	"PIPELINE_ID Strip3 Volume",
	"PIPELINE_ID Strip4 Volume",
	"PIPELINE_ID Strip5 Volume",
	"PIPELINE_ID Strip6 Volume",
	"PIPELINE_ID Strip7 Volume",
	"PIPELINE_ID Strip8 Volume"))

#
# Buffers (toutes 8ch — pas de mono)
#

W_BUFFER(0, COMP_BUFFER_SIZE(DAI_PERIODS,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 8,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_DAI_MEM_CAP)

W_BUFFER(1, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 8,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)

W_BUFFER(2, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 8,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)

W_BUFFER(3, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 8,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)

#
# Pipeline graph (linéaire)
#
P_GRAPH(pipe-multiband-drc-pga-8ch-capture, PIPELINE_ID,
	LIST(`		',
	`dapm(N_MULTIBAND_DRC(0), N_BUFFER(0))',
	`dapm(N_BUFFER(1), N_MULTIBAND_DRC(0))',
	`dapm(N_DRC(0), N_BUFFER(1))',
	`dapm(N_BUFFER(2), N_DRC(0))',
	`dapm(N_PGA(0), N_BUFFER(2))',
	`dapm(N_BUFFER(3), N_PGA(0))',
	`dapm(N_PCMC(PCM_ID), N_BUFFER(3))'))

#
# Exports
#
indir(`define', concat(`PIPELINE_SINK_', PIPELINE_ID), N_BUFFER(0))
indir(`define', concat(`PIPELINE_PCM_', PIPELINE_ID), ASIO IN PCM_ID)

#
# PCM capabilities : 8ch s32le @ 48k (stack Debix std)
#
PCM_CAPABILITIES(ASIO IN PCM_ID, CAPABILITY_FORMAT_NAME(PIPELINE_FORMAT),
	PCM_MIN_RATE, PCM_MAX_RATE, 2, PIPELINE_CHANNELS, 2, 16,
	192, 16384, 65536, 65536)

undefine(`DEF_PGA_TOKENS')
undefine(`DEF_PGA_CONF')
