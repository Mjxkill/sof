# V5.4.1 E6.b (pivot 8ch native) — playback via matrix_2x8 native + cross-pipeline mic tap
#
# Architecture E6.b PIPE 2 play, simplifiée vs pipe-matrix-with-mics-playback.m4 :
#
#   PCM 1 (ASIO play 8ch) → B0(8ch) ──┐
#                                      ↓
#                              matrix_2x8 (2 src 8ch → 1 sink 8ch, identity)
#                                      ↑
#   B5(8ch from PIPE 1 cross-pipeline) ┘
#                                      ↓
#                              B100(8ch) → SAI7 TX 8ch
#
# matrix_2x8 a une matrice 16x8 Q1.31 (128 cellules = 512 octets blob) :
#   - source 0 = ASIO play 8ch (input_idx 0..7)
#   - source 1 = mics tap 8ch (input_idx 8..15)
#   - 8 sinks (output channels 0..7) sortent du comp
# Identity matrix par défaut : ASIO play passthrough, mics muets (gain=0).
# User active mics via amixer cset (E6.c).
#
# Aucun deinterleave_8 ou interleave_8 → pas de buffers mono branched →
# pas de F++ complications, pas de bug deepseek (matrix sur DOWNSTREAM path),
# pas de copy_seq récursion explosive.

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

# matrix_2x8 (2 sources 8ch → 1 sink 8ch, identity matrix par défaut)
W_MATRIX_2X8(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE, ` ')

#
# Buffers (toutes 8ch — pas de mono)
#

# B0 : PCM playback → matrix_2x8 source 0 (8ch ASIO play side)
W_BUFFER(0, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 8,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)

# B100 : matrix_2x8 sink 0 → SAI TX (8ch DAI side)
W_BUFFER(100, COMP_BUFFER_SIZE(DAI_PERIODS,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 8,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_DAI_MEM_CAP)

#
# Pipeline graph (PIPE 2 internal — cross-pipeline mic tap added via top-level SectionGraph)
#
P_GRAPH(pipe-matrix2x8-with-mics-playback, PIPELINE_ID,
	LIST(`		',
	`dapm(N_BUFFER(0), N_PCMP(PCM_ID))',
	`dapm(N_MATRIX_2X8(0), N_BUFFER(0))',
	`dapm(N_BUFFER(100), N_MATRIX_2X8(0))'))

#
# Exports
#
indir(`define', concat(`PIPELINE_PCM_', PIPELINE_ID), ASIO OUT PCM_ID)
indir(`define', concat(`PIPELINE_SOURCE_', PIPELINE_ID), N_BUFFER(100))
# Export du matrix_2x8 instance pour cross-pipeline mic tap binding (vers BUF_PIPE_1_5)
indir(`define', concat(`PIPELINE_MIC_INPUT_MATRIX_', PIPELINE_ID), N_MATRIX_2X8(0))

#
# PCM capabilities : 8ch s32le @ 48k
#
PCM_CAPABILITIES(ASIO OUT PCM_ID, CAPABILITY_FORMAT_NAME(PIPELINE_FORMAT),
	PCM_MIN_RATE, PCM_MAX_RATE, 2, PIPELINE_CHANNELS, 2, 16,
	192, 16384, 65536, 65536)
