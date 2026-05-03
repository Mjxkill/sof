# V5.4.1 E6.b — TEST D'ISOLATION : matrix_2x8 avec B0 seul (pas de B5 cross-pipeline)
#
# Variante de pipe-matrix2x8-with-mics-playback.m4 pour le test d'isolation GLM :
# matrix_2x8 n'a qu'UNE source (B0 host PCM ASIO play). Pas de cross-pipeline mics tap.
#
#   PCM 1 (ASIO play 8ch) → B0(8ch) → matrix_2x8 (1 src 8ch → 1 sink 8ch)
#                                       ↓
#                                     B100(8ch) → SAI7 TX 8ch
#
# matrix_2x8 reste configuré 16x8 dans le firmware (MATRIX_2X8_MAX_SOURCES=2),
# mais seulement source 0 est branchée. Le code accepte num_input_buffers=1.
#
# Si play-seul cold-boot OK avec cette topology → cause = B5 cross-pipeline confirmée.

include(`utils.m4')
include(`buffer.m4')
include(`pcm.m4')
include(`dai.m4')
include(`pipeline.m4')
include(`mixercontrol.m4')
include(`bytecontrol.m4')
include(`matrix_2x8.m4')

#
# Components
#

W_PCM_PLAYBACK(PCM_ID, ASIO OUT, 0, 2, SCHEDULE_CORE)

# matrix_2x8 (1 source connectée seulement, pas de B5)
W_MATRIX_2X8(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE, ` ')

#
# Buffers (toutes 8ch)
#

# B0 : PCM playback → matrix_2x8 source 0
W_BUFFER(0, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 8,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)

# B100 : matrix_2x8 sink 0 → SAI TX
W_BUFFER(100, COMP_BUFFER_SIZE(DAI_PERIODS,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 8,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_DAI_MEM_CAP)

#
# Pipeline graph (linéaire, single-source — donc pas de pipeline_lock_branched)
#
P_GRAPH(pipe-matrix2x8-playback, PIPELINE_ID,
	LIST(`		',
	`dapm(N_BUFFER(0), N_PCMP(PCM_ID))',
	`dapm(N_MATRIX_2X8(0), N_BUFFER(0))',
	`dapm(N_BUFFER(100), N_MATRIX_2X8(0))'))

#
# Exports
#
indir(`define', concat(`PIPELINE_PCM_', PIPELINE_ID), ASIO OUT PCM_ID)
indir(`define', concat(`PIPELINE_SOURCE_', PIPELINE_ID), N_BUFFER(100))

#
# PCM capabilities
#
PCM_CAPABILITIES(ASIO OUT PCM_ID, CAPABILITY_FORMAT_NAME(PIPELINE_FORMAT),
	PCM_MIN_RATE, PCM_MAX_RATE, 2, PIPELINE_CHANNELS, 2, 16,
	192, 16384, 65536, 65536)
