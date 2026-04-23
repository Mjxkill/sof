divert(-1)

# demux_route_hpmon.m4 Phase 1a.2 V1.2
# Route matrix pour W_MUXDEMUX dans pipe-effects-playback-tap.m4
# 2 streams (duplication identite 8 canaux vers 2 sinks distincts) :
#   stream 0 : sink intra-pipeline B4 (pipeline_id=6) -> DAI SAI TX
#   stream 1 : sink cross-pipeline BUF7.0 (pipeline_id=7) -> HP_Monitor capture
#
# mux.c:44 mux_mix_check : popcount==1 par channel (pas de sommation).
# Identity identique sur les 2 sinks = pure duplication, aucun overlap.

define(`matrix_to_dai', `ROUTE_MATRIX(6,
	`BITS_TO_BYTE(1, 0, 0, 0, 0, 0, 0, 0)',
	`BITS_TO_BYTE(0, 1, 0, 0, 0, 0, 0, 0)',
	`BITS_TO_BYTE(0, 0, 1, 0, 0, 0, 0, 0)',
	`BITS_TO_BYTE(0, 0, 0, 1, 0, 0, 0, 0)',
	`BITS_TO_BYTE(0, 0, 0, 0, 1, 0, 0, 0)',
	`BITS_TO_BYTE(0, 0, 0, 0, 0, 1, 0, 0)',
	`BITS_TO_BYTE(0, 0, 0, 0, 0, 0, 1, 0)',
	`BITS_TO_BYTE(0, 0, 0, 0, 0, 0, 0, 1)')')

define(`matrix_to_hpmon', `ROUTE_MATRIX(7,
	`BITS_TO_BYTE(1, 0, 0, 0, 0, 0, 0, 0)',
	`BITS_TO_BYTE(0, 1, 0, 0, 0, 0, 0, 0)',
	`BITS_TO_BYTE(0, 0, 1, 0, 0, 0, 0, 0)',
	`BITS_TO_BYTE(0, 0, 0, 1, 0, 0, 0, 0)',
	`BITS_TO_BYTE(0, 0, 0, 0, 1, 0, 0, 0)',
	`BITS_TO_BYTE(0, 0, 0, 0, 0, 1, 0, 0)',
	`BITS_TO_BYTE(0, 0, 0, 0, 0, 0, 1, 0)',
	`BITS_TO_BYTE(0, 0, 0, 0, 0, 0, 0, 1)')')

divert(0)dnl
MUXDEMUX_CONFIG(DEMUX_priv, 2, LIST_NONEWLINE(`', `matrix_to_dai,', `matrix_to_hpmon'))
