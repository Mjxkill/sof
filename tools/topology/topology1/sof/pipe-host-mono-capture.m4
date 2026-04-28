# V5.4.1 Phase 1a.3 E5.c.1 — pipeline piggyback : 1 buffer mono cross-pipeline → host PCM mono
#
# Cette pipeline est consommatrice d'un sink cross-pipeline depuis deinterleave_8 (master pipeline).
# Le buffer B0 est exporté via PIPELINE_BUFFER_<id> pour binding via SectionGraph top-level.
#
# Pipeline graph (interne) :
#   B0 (cross-pipeline) -> host PCM (mono ch1 ou autre)

include(`utils.m4')
include(`buffer.m4')
include(`pcm.m4')
include(`pipeline.m4')

#
# Components and Buffers
#

# Host "Deinterleave Piggyback Capture" PCM (mono)
W_PCM_CAPTURE(PCM_ID, Deinterleave Piggyback Capture, 0, 2, SCHEDULE_CORE)

# B0 : buffer mono recevant le cross-pipeline sink depuis deinterleave_8 master
W_BUFFER(0, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)

#
# Pipeline Graph (interne, le sink B0 vient de cross-pipeline)
#  B0 -> host PCM_C
P_GRAPH(pipe-host-mono-capture, PIPELINE_ID,
	LIST(`		',
	`dapm(N_PCMC(PCM_ID), N_BUFFER(0))'))

#
# Pipeline Source and Sinks
#
indir(`define', concat(`PIPELINE_SINK_', PIPELINE_ID), N_BUFFER(0))
indir(`define', concat(`PIPELINE_BUFFER_', PIPELINE_ID), N_BUFFER(0))
indir(`define', concat(`PIPELINE_PCM_', PIPELINE_ID), Deinterleave Piggyback Capture PCM_ID)

#
# PCM Configuration
#
PCM_CAPABILITIES(Deinterleave Piggyback Capture PCM_ID, CAPABILITY_FORMAT_NAME(PIPELINE_FORMAT),
	PCM_MIN_RATE, PCM_MAX_RATE, 1, 1, 2, 16, 192, 16384, 65536, 65536)
