# V5.4.1 Phase 1a.3 E5.e.1 — passthrough 8ch via deinterleave_8 + 1 strip IN ch1 + interleave_8
#
# Architecture testée :
#   SAI7 RX 8ch -> B0(8ch) -> deinterleave_8 -> B1..B8 (mono internes)
#                                                ch1: B1 -> eq_iir -> B_eq1 -> drc -> B_drc1
#                                                            -> pga_L -> B_volL1 -> pga_R -> B_volR1
#                                                            -> interleave_8 (sink slot 1)
#                                                ch2..8: B2..B8 -> interleave_8 (slots 2..8 bypass)
#                                  -> interleave_8 -> B9(8ch) -> host PCM 8ch
#
# Pas de cross-pipeline. Le PCM ALSA reste 8ch (cap "ASIO IN").
# Les comps eq_iir, drc, pga supportent mono nativement (vérifié source : audio_stream_get_channels()).
# Les buffers intra-strip sont déclarés mono (1ch) et propagés en passthrough mono.
# Strip ch1 = blobs eq_iir_coef_pass (identité) + drc_coef_default + vol L/R = 0 dB → identité fonctionnelle.

include(`utils.m4')
include(`buffer.m4')
include(`pcm.m4')
include(`dai.m4')
include(`pipeline.m4')
include(`mixercontrol.m4')
include(`bytecontrol.m4')
include(`deinterleave_8.m4')
include(`interleave_8.m4')
include(`eq_iir.m4')
include(`drc.m4')
include(`pga.m4')

#
# Controls strip ch1
#

# ch1 EQ IIR — pass-through coefficients (identité)
ifdef(`PIPELINE_FILTER1', , `define(PIPELINE_FILTER1, eq_iir_coef_pass.m4)')
include(PIPELINE_FILTER1)

C_CONTROLBYTES(STRIP1_EQ_CTRL, PIPELINE_ID,
	CONTROLBYTES_OPS(bytes,
		258 binds the control to bytes get/put handlers,
		258, 258),
	CONTROLBYTES_EXTOPS(
		258 binds the control to bytes get/put handlers,
		258, 258),
	, , ,
	CONTROLBYTES_MAX(, 4096),
	,
	DEF_EQIIR_PRIV)

# ch1 DRC — default coefficients (compresseur léger neutre)
ifdef(`PIPELINE_DRC1', , `define(PIPELINE_DRC1, drc_coef_default.m4)')
include(PIPELINE_DRC1)

C_CONTROLBYTES(STRIP1_DRC_CTRL, PIPELINE_ID,
	CONTROLBYTES_OPS(bytes,
		258 binds the control to bytes get/put handlers,
		258, 258),
	CONTROLBYTES_EXTOPS(
		258 binds the control to bytes get/put handlers,
		258, 258),
	, , ,
	CONTROLBYTES_MAX(, 4096),
	,
	DRC_priv)

# ch1 PGA L (vol_L)
C_CONTROLMIXER(Strip1 Volume L, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 80),
	false,
	CONTROLMIXER_TLV(TLV 80 steps from -50dB to +30dB for 1dB, vtlv_m50s1),
	Channel register and shift for L,
	LIST(`	', KCONTROL_CHANNEL(FL, 1, 0)))

# ch1 PGA R (vol_R)
C_CONTROLMIXER(Strip1 Volume R, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 80),
	false,
	CONTROLMIXER_TLV(TLV 80 steps from -50dB to +30dB for 1dB, vtlv_m50s1),
	Channel register and shift for R,
	LIST(`	', KCONTROL_CHANNEL(FR, 1, 0)))

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

# deinterleave_8 (1×8ch -> 8 mono)
W_DEINTERLEAVE_8(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE)

# interleave_8 (8 mono -> 1×8ch)
W_INTERLEAVE_8(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE)

# Strip ch1 : eq_iir -> drc -> pga_L (W_PGA 0) -> pga_R (W_PGA 1)
W_EQ_IIR(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE,
	LIST(`		', "STRIP1_EQ_CTRL"))
W_DRC(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE,
	LIST(`		', "STRIP1_DRC_CTRL"))
W_PGA(0, PIPELINE_FORMAT, 2, 2, DEF_PGA_CONF, SCHEDULE_CORE,
	LIST(`		', "PIPELINE_ID Strip1 Volume L"))
W_PGA(1, PIPELINE_FORMAT, 2, 2, DEF_PGA_CONF, SCHEDULE_CORE,
	LIST(`		', "PIPELINE_ID Strip1 Volume R"))

#
# Buffers
#

# B0 : post-DAI 8ch
W_BUFFER(0, COMP_BUFFER_SIZE(DAI_PERIODS,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 8,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_DAI_MEM_CAP)

# B1..B8 : mono, sortie deinterleave_8
# flags = SOF_BUF_PRESERVE_CHANNELS (BIT(2)=4) | (1 << 8) = 260
# Lock channels=1 at topology load to prevent pipeline_comp_params_neg FORCE corruption.
W_BUFFER(1, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP, 0, 4)
W_BUFFER(2, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP, 0, 4)
W_BUFFER(3, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP, 0, 4)
W_BUFFER(4, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP, 0, 4)
W_BUFFER(5, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP, 0, 4)
W_BUFFER(6, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP, 0, 4)
W_BUFFER(7, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP, 0, 4)
W_BUFFER(8, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP, 0, 4)

# Strip ch1 internal buffers (mono): B10=post eq_iir, B11=post drc, B12=post pga_L, B13=post pga_R
W_BUFFER(10, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP, 0, 4)
W_BUFFER(11, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP, 0, 4)
W_BUFFER(12, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP, 0, 4)
W_BUFFER(13, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP, 0, 4)

# B9 : pre-host 8ch
W_BUFFER(9, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 8,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)

#
# Pipeline graph (1 strip ch1 effets neutres + 7 channels bypass)
#
P_GRAPH(pipe-deint-strip1-interleave-capture, PIPELINE_ID,
	LIST(`		',
	`dapm(N_DEINTERLEAVE_8(0), N_BUFFER(0))',
	`dapm(N_BUFFER(1), N_DEINTERLEAVE_8(0))',
	`dapm(N_BUFFER(2), N_DEINTERLEAVE_8(0))',
	`dapm(N_BUFFER(3), N_DEINTERLEAVE_8(0))',
	`dapm(N_BUFFER(4), N_DEINTERLEAVE_8(0))',
	`dapm(N_BUFFER(5), N_DEINTERLEAVE_8(0))',
	`dapm(N_BUFFER(6), N_DEINTERLEAVE_8(0))',
	`dapm(N_BUFFER(7), N_DEINTERLEAVE_8(0))',
	`dapm(N_BUFFER(8), N_DEINTERLEAVE_8(0))',
	`dapm(N_EQ_IIR(0), N_BUFFER(1))',
	`dapm(N_BUFFER(10), N_EQ_IIR(0))',
	`dapm(N_DRC(0), N_BUFFER(10))',
	`dapm(N_BUFFER(11), N_DRC(0))',
	`dapm(N_PGA(0), N_BUFFER(11))',
	`dapm(N_BUFFER(12), N_PGA(0))',
	`dapm(N_PGA(1), N_BUFFER(12))',
	`dapm(N_BUFFER(13), N_PGA(1))',
	`dapm(N_INTERLEAVE_8(0), N_BUFFER(13))',
	`dapm(N_INTERLEAVE_8(0), N_BUFFER(2))',
	`dapm(N_INTERLEAVE_8(0), N_BUFFER(3))',
	`dapm(N_INTERLEAVE_8(0), N_BUFFER(4))',
	`dapm(N_INTERLEAVE_8(0), N_BUFFER(5))',
	`dapm(N_INTERLEAVE_8(0), N_BUFFER(6))',
	`dapm(N_INTERLEAVE_8(0), N_BUFFER(7))',
	`dapm(N_INTERLEAVE_8(0), N_BUFFER(8))',
	`dapm(N_BUFFER(9), N_INTERLEAVE_8(0))',
	`dapm(N_PCMC(PCM_ID), N_BUFFER(9))'))

#
# Exports
#
indir(`define', concat(`PIPELINE_SINK_', PIPELINE_ID), N_BUFFER(0))
indir(`define', concat(`PIPELINE_PCM_', PIPELINE_ID), ASIO IN PCM_ID)

#
# PCM capabilities : 8ch s32le @ 48k
#
PCM_CAPABILITIES(ASIO IN PCM_ID, CAPABILITY_FORMAT_NAME(PIPELINE_FORMAT),
	PCM_MIN_RATE, PCM_MAX_RATE, 2, PIPELINE_CHANNELS, 2, 16,
	192, 16384, 65536, 65536)

undefine(`DEF_PGA_TOKENS')
undefine(`DEF_PGA_CONF')
