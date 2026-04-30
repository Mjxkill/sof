# V5.4.1 Phase 1a.3 E5.d — pipeline capture passthrough 8ch via deinterleave_8 + interleave_8
#
# Architecture :
#   SAI7 RX 8ch -> B0(8ch) -> deinterleave_8 -> B1..B8(mono internes) -> interleave_8 -> B9(8ch) -> host PCM 8ch
#
# Contrainte Phase 1a.3 : 1 SEUL PCM ALSA cap 8ch (ASIO IN). Les 8 mono restent internes au DSP.
# Test attendu : arecord -c 8 -f S32_LE bit-perfect identique au passthrough V3.2.2.
#
# Pré-requis firmware patché :
#   - deinterleave_8.c : trigger overrun_permitted + prepare override channels (src=8, sinks=1)
#   - interleave_8.c   : trigger overrun_permitted (à patcher si besoin)
#
# Pas de cross-pipeline. Pas de PCM mono. Pas de piggyback.

include(`utils.m4')
include(`buffer.m4')
include(`pcm.m4')
include(`dai.m4')
include(`pipeline.m4')
include(`deinterleave_8.m4')
include(`interleave_8.m4')

#
# Components
#

# Host capture 8ch (ASIO IN)
W_PCM_CAPTURE(PCM_ID, ASIO IN, 0, 2, SCHEDULE_CORE)

# deinterleave_8 (1×8ch -> 8 mono)
W_DEINTERLEAVE_8(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE)

# interleave_8 (8 mono -> 1×8ch)
W_INTERLEAVE_8(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE)

#
# Buffers
#

# B0 : post-DAI 8ch
W_BUFFER(0, COMP_BUFFER_SIZE(DAI_PERIODS,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 8,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_DAI_MEM_CAP)

# B1..B8 : 8 mono buffers entre deinterleave_8 et interleave_8
W_BUFFER(1, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)
W_BUFFER(2, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)
W_BUFFER(3, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)
W_BUFFER(4, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)
W_BUFFER(5, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)
W_BUFFER(6, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)
W_BUFFER(7, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)
W_BUFFER(8, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)

# B9 : pre-host 8ch
W_BUFFER(9, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 8,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)

#
# Pipeline graph (toutes routes locales, pas de cross-pipeline)
#
P_GRAPH(pipe-deint-interleave-capture, PIPELINE_ID,
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
	`dapm(N_INTERLEAVE_8(0), N_BUFFER(1))',
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
