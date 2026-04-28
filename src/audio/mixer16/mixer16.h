/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright(c) 2026 Electrosens. All rights reserved.
 *
 * V5.4.1 Phase 1a.3 — mixer16 matrix component header.
 */

#ifndef __SOF_AUDIO_MIXER16_H__
#define __SOF_AUDIO_MIXER16_H__

#include <stdint.h>

#define MIXER16_MAX_SOURCES	16
#define MIXER16_MAX_SINKS	8
#define MIXER16_GAIN_BITS	31	/* Q1.31 */

/* ALSA bytes blob layout: 16 x 8 = 128 cells x 4 bytes = 512 B. */
struct mixer16_cell_gains {
	int32_t gain[MIXER16_MAX_SOURCES][MIXER16_MAX_SINKS];
} __attribute__((packed));

/* Component runtime data */
struct mixer16_cd {
	struct mixer16_cell_gains gains;
	uint32_t source_format;
	uint32_t sample_rate;
};

#endif /* __SOF_AUDIO_MIXER16_H__ */
