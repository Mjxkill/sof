/* SPDX-License-Identifier: BSD-3-Clause */
/*
 * Copyright(c) 2026 Electrosens. All rights reserved.
 *
 * V5.4.1 Phase 1a.3 E6.b — matrix_2x8 16x8 native interleaved gain matrix.
 *
 * 2 sources × 8 channels interleaved + 1 sink × 8 channels interleaved.
 * Per-cell Q1.31 gain matrix (16 inputs × 8 outputs = 128 cells = 512 B blob).
 *
 * Identity matrix at boot:
 *   - source 0 channel i (asio play) -> sink channel i, gain=Q1.31(1.0)
 *   - source 1 channel i (mics tap) -> all sinks, gain=0 (muted)
 * User can later upload a divergent gain blob via amixer cset.
 *
 * Designed to replace the mixer16 + deinterleave_8 × 2 + interleave_8 chain
 * with a single 8-ch native comp, eliminating mono branched buffers and the
 * associated F++ / walk-not-visited complications.
 */
#ifndef __SOF_AUDIO_MATRIX_2X8_H__
#define __SOF_AUDIO_MATRIX_2X8_H__

#include <stdint.h>

#define MATRIX_2X8_MAX_SOURCES   2     /* asio_play 8ch + mics_tap 8ch */
#define MATRIX_2X8_MAX_SINKS     1
#define MATRIX_2X8_OUT_CHANNELS  8
#define MATRIX_2X8_TOTAL_INPUTS  (MATRIX_2X8_MAX_SOURCES * MATRIX_2X8_OUT_CHANNELS)
#define MATRIX_2X8_PERIOD_FRAMES 96    /* 2ms @ 48kHz, force-period defensive */

struct matrix_2x8_gains {
	/* gain[input_index 0..15][output_channel 0..7] in Q1.31 signed */
	int32_t gain[MATRIX_2X8_TOTAL_INPUTS][MATRIX_2X8_OUT_CHANNELS];
};

#endif /* __SOF_AUDIO_MATRIX_2X8_H__ */
