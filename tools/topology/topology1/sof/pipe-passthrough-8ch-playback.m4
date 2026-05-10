# Passthrough Playback (8 ch) — host PCM_P --> B0 --> sink DAI0
#
# Variante 8 ch de pipe-passthrough-playback.m4 (upstream SOF).
# Seule différence : PCM_CAPABILITIES aligné sur la stack V5/V7 Debix —
# period_size [192, 16384] B, buffer [65536, 65536] B (cf pipe-matrix-playback,
# pipe-eq-drc-pga-8ch-D3-capture). Permet à ALSA d'obtenir des periods
# en bas de plage (jusqu'à 6 frames @ 8ch S32 = 125 µs), alors que la
# version standard fige period à 24576 B = 768 frames = 16 ms @ 48 kHz.

include(`utils.m4')
include(`buffer.m4')
include(`pcm.m4')
include(`dai.m4')
include(`pipeline.m4')

# Host PCM with DAI_PERIODS sink periods and 0 source periods
W_PCM_PLAYBACK(PCM_ID, Passthrough Playback, DAI_PERIODS, 0, SCHEDULE_CORE)

# Playback Buffer
W_BUFFER(0, COMP_BUFFER_SIZE(DAI_PERIODS,
	COMP_SAMPLE_SIZE(PIPELINE_FORMAT), PIPELINE_CHANNELS, COMP_PERIOD_FRAMES(PCM_MAX_RATE, SCHEDULE_PERIOD)),
	PLATFORM_PASS_MEM_CAP)

# Pipeline Graph : host PCM_P --> B0 --> sink DAI0
P_GRAPH(pipe-passthrough-8ch-playback, PIPELINE_ID,
	LIST(`		',
	`dapm(N_BUFFER(0), N_PCMP(PCM_ID))'))

# Pipeline Source and PCM exports
indir(`define', concat(`PIPELINE_SOURCE_', PIPELINE_ID), N_BUFFER(0))
indir(`define', concat(`PIPELINE_PCM_', PIPELINE_ID), Passthrough Playback PCM_ID)

ifdef(`CHANNELS_MIN',`define(`LOCAL_CHANNELS_MIN', `CHANNELS_MIN')',
`define(`LOCAL_CHANNELS_MIN', `2')')

# PCM Capabilities — aligné stack Debix (period_min 192 B = 6 frames @ 8ch S32)
PCM_CAPABILITIES(Passthrough Playback PCM_ID, CAPABILITY_FORMAT_NAME(PIPELINE_FORMAT),
	PCM_MIN_RATE, PCM_MAX_RATE, LOCAL_CHANNELS_MIN, PIPELINE_CHANNELS, 2, 16,
	192, 16384, 65536, 65536)

undefine(`LOCAL_CHANNELS_MIN')
