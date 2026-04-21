# Master tap V2.3 : buf (shared avec PIPE 3) -> host PCM "Master Tap"
#
# Pipeline Endpoints :
#  shared_buffer --> B0 --> host PCM_C
#
# Le buffer B0 est le sink import de la pipeline, lie via DAPM
# cross-pipeline au buffer de sortie (B3) de pipe-masterchain.
# PIPE 5 piggyback sur le scheduler de PIPE 3 via W_PIPELINE(SCHED_COMP, ...)
# ou SCHED_COMP est defini par PIPELINE_PCM_ADD 13e arg dans masterlite.m4.

include(`utils.m4')
include(`buffer.m4')
include(`pcm.m4')
include(`pipeline.m4')

#
# Host PCM capture endpoint ("Master Tap")
#
W_PCM_CAPTURE(PCM_ID, Master Tap, 0, 2, SCHEDULE_CORE)

#
# Buffer d'entree (sera lie au N_BUFFER(3) de masterchain via DAPM externe)
#
W_BUFFER(0, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), PIPELINE_CHANNELS,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)

#
# Widget scheduler explicite, piggyback sur l'upstream SCHED_COMP
# (SCHED_COMP = PIPELINE_SCHED_COMP_3 defini par masterchain.m4)
#
W_PIPELINE(SCHED_COMP, SCHEDULE_PERIOD, SCHEDULE_PRIORITY, SCHEDULE_CORE,
           SCHEDULE_TIME_DOMAIN, pipe_media_schedule_plat)

#
# Pipeline Graph : buf -> host
#
P_GRAPH(pipe-master-tap, PIPELINE_ID,
	LIST(`		',
		`dapm(N_PCMC(PCM_ID), N_BUFFER(0))'))

#
# Export buffer 0 comme SINK de la pipeline pour le graph externe
#
indir(`define', concat(`PIPELINE_SINK_', PIPELINE_ID), N_BUFFER(0))
indir(`define', concat(`PIPELINE_PCM_', PIPELINE_ID), Master Tap PCM_ID)

#
# PCM capabilities : 2ch s32le @ 48k
#
PCM_CAPABILITIES(Master Tap PCM_ID, CAPABILITY_FORMAT_NAME(PIPELINE_FORMAT),
	PCM_MIN_RATE, PCM_MAX_RATE, 2, 2, 2, 16, 192, 16384, 65536, 65536)
