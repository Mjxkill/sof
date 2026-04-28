# V5.4.1 Phase 1a.3 E5.c.1 — pipeline master capture avec deinterleave_8 + 1 sink local + export pour cross-pipeline
#
# Pattern miroir de pipe-volume-demux-playback.m4 (mais en capture, et avec deinterleave_8 au lieu de muxdemux).
#
# Pipeline graph :
#   source DAI -> B0 -> deinterleave_8 -> B1 -> host PCM master (mono ch0)
#                                |
#                                +-- (sink #2..8 exposés via PIPELINE_DEINTERLEAVE_<id> pour cross-pipeline)

include(`utils.m4')
include(`buffer.m4')
include(`pcm.m4')
include(`dai.m4')
include(`pipeline.m4')
include(`deinterleave_8.m4')

#
# Components and Buffers
#

# Host "Deinterleave Master Capture" PCM (mono, channel 0 du SAI)
W_PCM_CAPTURE(PCM_ID, Deinterleave Master Capture, 0, 2, SCHEDULE_CORE)

# deinterleave_8 (1 src 8ch → max 8 sinks mono)
W_DEINTERLEAVE_8(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE)

# Buffers
# B0 : post-DAI 8ch (ce qui arrive de SAI capture)
W_BUFFER(0, COMP_BUFFER_SIZE(DAI_PERIODS,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 8,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_DAI_MEM_CAP)

# B1 : sink #1 local de deinterleave_8 (mono, vers host master)
W_BUFFER(1, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)

#
# Pipeline Graph (1 sink local seulement ; les autres exposés via PIPELINE_DEINTERLEAVE_<id>)
#
#  source DAI -> B0 -> deinterleave_8 -> B1 -> host PCM_C (master)
P_GRAPH(pipe-deinterleave-master-capture, PIPELINE_ID,
	LIST(`		',
	`dapm(N_DEINTERLEAVE_8(0), N_BUFFER(0))',
	`dapm(N_BUFFER(1), N_DEINTERLEAVE_8(0))',
	`dapm(N_PCMC(PCM_ID), N_BUFFER(1))'))

#
# Pipeline Source and Sinks (export pour cross-pipeline binding)
#
indir(`define', concat(`PIPELINE_SINK_', PIPELINE_ID), N_BUFFER(0))
indir(`define', concat(`PIPELINE_DEINTERLEAVE_', PIPELINE_ID), N_DEINTERLEAVE_8(0))
indir(`define', concat(`PIPELINE_PCM_', PIPELINE_ID), Deinterleave Master Capture PCM_ID)

#
# PCM Configuration
#
PCM_CAPABILITIES(Deinterleave Master Capture PCM_ID, CAPABILITY_FORMAT_NAME(PIPELINE_FORMAT),
	PCM_MIN_RATE, PCM_MAX_RATE, 1, 1, 2, 16, 192, 16384, 65536, 65536)
