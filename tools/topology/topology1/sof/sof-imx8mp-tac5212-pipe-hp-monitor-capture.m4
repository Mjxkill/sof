# Phase 1a.2 V1.2 — HP_Monitor capture pipeline (tap post-effets OUT)
#
# Pipeline Endpoints :
#   (cross-pipeline MUXDEMUX de PIPE 6) -> B0 -> PCM host HP_Monitor
#
# Piggyback scheduling sur PIPE 6 :
#   Le 13e arg PIPELINE_PCM_ADD (= PIPELINE_PLAYBACK_SCHED_COMP_6 = N_DAI_OUT = SAI7.OUT)
#   est injecté dans SCHED_COMP par pipeline.m4:84.
#   W_PIPELINE(SCHED_COMP, ...) crée un scheduler widget "PIPELINE.7.SAI7.OUT"
#   avec stream_name="SAI7.OUT" partagé avec PIPE 6.
#
# Pattern upstream : pipe-mastertap.m4:33-34, pipe-detect.m4:97.
# Pas de DAI_ADD pour PIPE 7 : tap interne cross-pipeline via SectionGraph.

# Include topology builder
include(`utils.m4')
include(`buffer.m4')
include(`pcm.m4')
include(`pipeline.m4')

#
# Host PCM endpoint
#
W_PCM_CAPTURE(PCM_ID, HP Monitor, 0, 2, SCHEDULE_CORE)

#
# Buffer : B0 reçoit du cross-pipeline MUXDEMUX (PIPE 6)
# Alimenté par SectionGraph top-level : dapm(PIPELINE_SINK_7, PIPELINE_DEMUX_6)
#
W_BUFFER(0, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), PIPELINE_CHANNELS,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP, SCHEDULE_CORE)

#
# V1.1 fix B2 : W_PIPELINE explicite OBLIGATOIRE
# SCHED_COMP est défini par le 13e arg de PIPELINE_PCM_ADD
# (= PIPELINE_PLAYBACK_SCHED_COMP_6 = N_DAI_OUT(6) = "SAI7.OUT" après V1.2 fix ordre m4).
# Pattern upstream : pipe-mastertap.m4:33-34, pipe-detect.m4:97
#
W_PIPELINE(SCHED_COMP, SCHEDULE_PERIOD, SCHEDULE_PRIORITY, SCHEDULE_CORE,
	SCHEDULE_TIME_DOMAIN, pipe_media_schedule_plat)

#
# Graph : PCM capture <- B0 (B0 alimenté cross-pipeline via SectionGraph)
#
P_GRAPH(pipe-hp-monitor-capture, PIPELINE_ID,
	LIST(`		',
	`dapm(N_PCMC(PCM_ID), N_BUFFER(0))'))

#
# Exports V1.2 :
#   PIPELINE_SINK_N = B0 (cible du SectionGraph cross-pipeline)
#
indir(`define', concat(`PIPELINE_SINK_', PIPELINE_ID), N_BUFFER(0))
indir(`define', concat(`PIPELINE_PCM_',  PIPELINE_ID), HP Monitor PCM_ID)

#
# PCM capabilities : 8ch s32le @ 48k
#
PCM_CAPABILITIES(HP Monitor PCM_ID, CAPABILITY_FORMAT_NAME(PIPELINE_FORMAT),
	PCM_MIN_RATE, PCM_MAX_RATE, 2, PIPELINE_CHANNELS, 2, 16,
	192, 16384, 65536, 65536)
