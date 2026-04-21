divert(-1)

# demux_route_default.m4 V2.6
# Route matrix pour mux en mode demux (pipe-masterchain.m4)
# 1 seul stream consommateur (cross-pipeline vers PIPE 5 Master_Tap)
#
# [V2.6 B1] stream_id = 5 (pipeline_id du SINK = Master_Tap), pas 3.
# Route identite 2ch -> 2ch (mask: in_ch0 -> out_ch0, in_ch1 -> out_ch1)

divert(0)dnl
MUXDEMUX_CONFIG(DEMUX_priv, 1,
	ROUTE_MATRIX(5, 1, 2, 0, 0, 0, 0, 0, 0))
