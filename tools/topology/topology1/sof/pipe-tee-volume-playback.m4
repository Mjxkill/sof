# V5.4.1 Phase 1a.3 E3.c — pipe playback avec tee_1to2 inséré entre host et volume
#
# Pipeline : host PCM_P --> B0 --> tee_1to2 --> B1 --> volume --> B2 --> sink DAI
#
# Test fonctionnel : tee_1to2 en passthrough mode (1 source × 1 sink connecté).
# Si audio joue à travers cette pipeline = tee_1to2 fonctionne en runtime.
# Le 2e sink éventuel n'est pas utilisé pour ce premier test.

# Include topology builder
include(`utils.m4')
include(`buffer.m4')
include(`pcm.m4')
include(`pga.m4')
include(`dai.m4')
include(`mixercontrol.m4')
include(`pipeline.m4')

# V5.4.1 NEW comp widget
include(`tee_1to2.m4')

#
# Controls
#
C_CONTROLMIXER(Master Playback Volume, PIPELINE_ID,
	CONTROLMIXER_OPS(volsw, 256 binds the mixer control to volume get/put handlers, 256, 256),
	CONTROLMIXER_MAX(, 32),
	false,
	CONTROLMIXER_TLV(TLV 32 steps from -64dB to 0dB for 2dB, vtlv_m64s2),
	Channel register and shift for Front Left/Right,
	VOLUME_CHANNEL_MAP)

#
# Volume configuration
#
define(DEF_PGA_TOKENS, concat(`pga_tokens_', PIPELINE_ID))
define(DEF_PGA_CONF, concat(`pga_conf_', PIPELINE_ID))

W_VENDORTUPLES(DEF_PGA_TOKENS, sof_volume_tokens,
LIST(`		', `SOF_TKN_VOLUME_RAMP_STEP_TYPE	"2"'
     `		', `SOF_TKN_VOLUME_RAMP_STEP_MS		"20"'))

W_DATA(DEF_PGA_CONF, DEF_PGA_TOKENS)

#
# Components and Buffers
#

# Host "Tee Test Playback" PCM
W_PCM_PLAYBACK(PCM_ID, Tee Test Playback, 2, 0, SCHEDULE_CORE)

# tee_1to2 inserted between host and volume
W_TEE_1TO2(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE)

# Volume
W_PGA(0, PIPELINE_FORMAT, DAI_PERIODS, 2, DEF_PGA_CONF, SCHEDULE_CORE,
	LIST(`		', "PIPELINE_ID Master Playback Volume"))

# Playback Buffers
W_BUFFER(0, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), PIPELINE_CHANNELS, COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP, SCHEDULE_CORE)
W_BUFFER(1, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), PIPELINE_CHANNELS, COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_DAI_MEM_CAP, SCHEDULE_CORE)
W_BUFFER(2, COMP_BUFFER_SIZE(DAI_PERIODS,
	COMP_SAMPLE_SIZE(DAI_FORMAT), PIPELINE_CHANNELS, COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_DAI_MEM_CAP, SCHEDULE_CORE)

#
# Pipeline Graph
#
#  host PCM_P --> B0 --> tee_1to2 --> B1 --> Volume 0 --> B2 --> sink DAI

P_GRAPH(pipe-tee-volume-playback, PIPELINE_ID,
	LIST(`		',
	`dapm(N_BUFFER(0), N_PCMP(PCM_ID))',
	`dapm(N_TEE_1TO2(0), N_BUFFER(0))',
	`dapm(N_BUFFER(1), N_TEE_1TO2(0))',
	`dapm(N_PGA(0), N_BUFFER(1))',
	`dapm(N_BUFFER(2), N_PGA(0))'))

#
# Pipeline Source and Sinks
#
indir(`define', concat(`PIPELINE_SOURCE_', PIPELINE_ID), N_BUFFER(2))
indir(`define', concat(`PIPELINE_PCM_', PIPELINE_ID), Tee Test Playback PCM_ID)

ifdef(`CHANNELS_MIN',`define(`LOCAL_CHANNELS_MIN', `CHANNELS_MIN')',
`define(`LOCAL_CHANNELS_MIN', `2')')

#
# PCM Configuration
#
PCM_CAPABILITIES(Tee Test Playback PCM_ID, CAPABILITY_FORMAT_NAME(PIPELINE_FORMAT), PCM_MIN_RATE, PCM_MAX_RATE, LOCAL_CHANNELS_MIN, PIPELINE_CHANNELS, 2, 16, 192, 16384, 65536, 65536)

undefine(`LOCAL_CHANNELS_MIN')
undefine(`DEF_PGA_TOKENS')
undefine(`DEF_PGA_CONF')
