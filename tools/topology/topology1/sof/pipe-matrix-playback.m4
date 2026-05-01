# V5.4.1 Phase 1a.3 E6.a — playback 8ch via deinterleave_8 + mixer16 (16x8 matrix) + interleave_8
#
# Architecture E6.a (Phase A : passthrough, mics non connectés) :
#
#   PCM 1 (ASIO play 8ch) -> B0(8ch) -> deinterleave_8 -> B1..B8 (8 mono ASIO)
#                                                          ↓ (sources 0..7 of mixer16)
#                                       mixer16 (16x8 matrix, identity gain) -> B10..B17 (8 mono)
#                                                          ↑ (sources 8..15 = mics, NON CONNECTÉS Phase A)
#                                       -> interleave_8 -> B100(8ch) -> SAI7 TX 8ch
#
# Identity matrix par défaut (gain[i][j] = INT32_MAX si i==j et i<8) :
#   - sources 0..7 (ASIO play) -> sinks 0..7 en passthrough
#   - sources 8..15 (mics) -> mute (gain=0) — pas de connexion Phase A donc num_of_sources=8
#
# Auto-detection F++ (commit 7499505ec) lock channels=1 sur les buffers mono branchés
# entre deinterleave_8 et interleave_8 (B1..B8 + B10..B17). Pas besoin de tplg flag —
# la 2ᵉ walk de pipeline_complete détecte multi-sink/multi-source automatiquement.
#
# Phase B (E6.b future) : ajouter cross-pipeline tap depuis PIPE 1 cap (post-pga 8ch
# deinterleavé) vers les sources 8..15 de mixer16 — risque -22 historique à évaluer.
#
# Phase C (E6.c future) : 128 ALSA controls weights pour permettre user de configurer
# la matrice (ou 1 control bytes monolithique 512 octets pour la matrice complète).

include(`utils.m4')
include(`buffer.m4')
include(`pcm.m4')
include(`dai.m4')
include(`pipeline.m4')
include(`mixercontrol.m4')
include(`bytecontrol.m4')
include(`deinterleave_8.m4')
include(`interleave_8.m4')
include(`mixer16.m4')

#
# Components
#

# Host playback 8ch (ASIO play)
W_PCM_PLAYBACK(PCM_ID, ASIO OUT, 0, 2, SCHEDULE_CORE)

# deinterleave_8 (1×8ch → 8 mono ASIO play)
W_DEINTERLEAVE_8(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE)

# mixer16 (16 mono sources → 8 mono sinks, identity matrix par défaut)
W_MIXER16(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE, ` ')

# interleave_8 (8 mono → 1×8ch)
W_INTERLEAVE_8(0, PIPELINE_FORMAT, 2, 2, SCHEDULE_CORE)

#
# Buffers
#

# B0 : pre-deinterleave_8 (8ch from PCM)
W_BUFFER(0, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 8,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)

# B100 : post-interleave_8 (8ch to DAI) — id 100 to avoid collision with mono pool
W_BUFFER(100, COMP_BUFFER_SIZE(DAI_PERIODS,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 8,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_DAI_MEM_CAP)

# B1..B8 : mono, sortie deinterleave_8 (entry de mixer16 sources 0..7)
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

# B10..B17 : mono, sortie mixer16 (entry de interleave_8 sources 0..7)
W_BUFFER(10, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)
W_BUFFER(11, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)
W_BUFFER(12, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)
W_BUFFER(13, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)
W_BUFFER(14, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)
W_BUFFER(15, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)
W_BUFFER(16, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)
W_BUFFER(17, COMP_BUFFER_SIZE(2,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), 1,
	COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_HOST_MEM_CAP)

#
# Pipeline graph
#
P_GRAPH(pipe-matrix-playback, PIPELINE_ID,
	LIST(`		',
	`dapm(N_BUFFER(0), N_PCMP(PCM_ID))',
	`dapm(N_DEINTERLEAVE_8(0), N_BUFFER(0))',
	`dapm(N_BUFFER(1), N_DEINTERLEAVE_8(0))',
	`dapm(N_BUFFER(2), N_DEINTERLEAVE_8(0))',
	`dapm(N_BUFFER(3), N_DEINTERLEAVE_8(0))',
	`dapm(N_BUFFER(4), N_DEINTERLEAVE_8(0))',
	`dapm(N_BUFFER(5), N_DEINTERLEAVE_8(0))',
	`dapm(N_BUFFER(6), N_DEINTERLEAVE_8(0))',
	`dapm(N_BUFFER(7), N_DEINTERLEAVE_8(0))',
	`dapm(N_BUFFER(8), N_DEINTERLEAVE_8(0))',
	`dapm(N_MIXER16(0), N_BUFFER(1))',
	`dapm(N_MIXER16(0), N_BUFFER(2))',
	`dapm(N_MIXER16(0), N_BUFFER(3))',
	`dapm(N_MIXER16(0), N_BUFFER(4))',
	`dapm(N_MIXER16(0), N_BUFFER(5))',
	`dapm(N_MIXER16(0), N_BUFFER(6))',
	`dapm(N_MIXER16(0), N_BUFFER(7))',
	`dapm(N_MIXER16(0), N_BUFFER(8))',
	`dapm(N_BUFFER(10), N_MIXER16(0))',
	`dapm(N_BUFFER(11), N_MIXER16(0))',
	`dapm(N_BUFFER(12), N_MIXER16(0))',
	`dapm(N_BUFFER(13), N_MIXER16(0))',
	`dapm(N_BUFFER(14), N_MIXER16(0))',
	`dapm(N_BUFFER(15), N_MIXER16(0))',
	`dapm(N_BUFFER(16), N_MIXER16(0))',
	`dapm(N_BUFFER(17), N_MIXER16(0))',
	`dapm(N_INTERLEAVE_8(0), N_BUFFER(10))',
	`dapm(N_INTERLEAVE_8(0), N_BUFFER(11))',
	`dapm(N_INTERLEAVE_8(0), N_BUFFER(12))',
	`dapm(N_INTERLEAVE_8(0), N_BUFFER(13))',
	`dapm(N_INTERLEAVE_8(0), N_BUFFER(14))',
	`dapm(N_INTERLEAVE_8(0), N_BUFFER(15))',
	`dapm(N_INTERLEAVE_8(0), N_BUFFER(16))',
	`dapm(N_INTERLEAVE_8(0), N_BUFFER(17))',
	`dapm(N_BUFFER(100), N_INTERLEAVE_8(0))'))

#
# Exports
#
indir(`define', concat(`PIPELINE_PCM_', PIPELINE_ID), ASIO OUT PCM_ID)
indir(`define', concat(`PIPELINE_SOURCE_', PIPELINE_ID), N_BUFFER(100))

#
# PCM capabilities : 8ch s32le @ 48k
#
PCM_CAPABILITIES(ASIO OUT PCM_ID, CAPABILITY_FORMAT_NAME(PIPELINE_FORMAT),
	PCM_MIN_RATE, PCM_MAX_RATE, 2, PIPELINE_CHANNELS, 2, 16,
	192, 16384, 65536, 65536)
