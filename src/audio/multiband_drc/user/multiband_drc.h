/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright(c) 2020 Google LLC. All rights reserved.
 *
 * Author: Pin-chih Lin <johnylin@google.com>
 */

#ifndef __USER_MULTIBAND_DRC_H__
#define __USER_MULTIBAND_DRC_H__

#include <stddef.h>
#include <stdint.h>
#include <user/eq.h>
#include <module/crossover/crossover_common.h>

#include "../../drc/drc_user.h"

/* Maximum number of frequency band for Multiband DRC */
#define SOF_MULTIBAND_DRC_MAX_BANDS SOF_CROSSOVER_MAX_STREAMS

/* Maximum number of Crossover LR4 highpass and lowpass filters */
#define SOF_CROSSOVER_MAX_LR4 ((SOF_CROSSOVER_MAX_STREAMS - 1) * 2)

/* The number of biquads (and biquads in series) of (De)Emphasis Equalizer */
#define SOF_EMP_DEEMP_BIQUADS 2

/* Maximum number allowed of IPC configuration blob size.
 * Bumped to 4096 in V7.0-E2 to fit per-channel-per-band drc params blobs :
 *   header (size + bands + enable + reserved + emp + deemp + crossover) ≈ 244 B
 *   drc_coef[num_bands × num_channels] = 4 × 8 × 88 B (sof_drc_params packed)
 *                                      = 2816 B
 *   total max ≈ 3060 B (4 bands × 8 ch).
 * Old limit 1024 B kept legacy single-config (4 bands × 1 ch × 88 ≈ 352 B + 244 hdr).
 */
#define SOF_MULTIBAND_DRC_MAX_BLOB_SIZE 4096

 /* multiband_drc configuration
  *     Multiband DRC is a single-source-single-sink compound component which
  *     consists of 4 stages: Emphasis Equalizer, Crossover Filter (from 1-band
  *     to 4-band), DRC (per band), and Deemphasis Equalizer of summed stream.
  *
  *     The following graph illustrates a 3-band Multiband DRC component:
  *
  *                                      low
  *                                     o----> DRC0 ----o
  *                                     |               |
  *                           3-WAY     |mid            |
  *     x(n) --> EQ EMP --> CROSSOVER --o----> DRC1 ---(+)--> EQ DEEMP --> y(n)
  *                                     |               |
  *                                     |high           |
  *                                     o----> DRC2 ----o
  *
  *     uint32_t num_bands <= 4
  *         Determines the number of frequency bands, the choice of n-way
  *         Crossover, and the number of DRC components.
  *     uint32_t enable_emp_deemp
  *         1=enable Emphasis and Deemphasis Equalizer; 0=disable (passthrough)
  *     struct sof_eq_iir_biquad emp_coef[2]
  *         The coefficient data for Emphasis Equalizer, which is a cascade of 2
  *         biquad filters.
  *     struct sof_eq_iir_biquad deemp_coef[2]
  *         The coefficient data for Deemphasis Equalizer, which is a cascade of
  *         2 biquad filters.
  *     struct sof_eq_iir_biquad crossover_coef[6]
  *         The coefficient data for Crossover LR4 filters. Please refer
  *         src/include/user/crossover.h for details. Zeros will be filled if
  *         the entries are useless. For example, when 2-way crossover is used:
  *     struct sof_drc_params drc_coef[num_bands * params_per_band]
  *         The parameter data for DRC per band. Layout :
  *           drc_coef[0..num_bands-1]                       — band 0..N-1 with
  *               single set of params (legacy, params_per_band = 1)
  *           drc_coef[band * params_per_band + ch]          — band-channel
  *               specific params (V7.0-E2 extended, params_per_band > 1).
  *         Detection : the firmware reads (size - sizeof(fixed_header)) and
  *         derives params_per_band = trailing_bytes / (num_bands * sizeof(sof_drc_params)).
  *         params_per_band == 1 keeps legacy behaviour (one params shared
  *         by all channels of the band — existing topologies continue to work).
  *         params_per_band > 1 (typically num_channels) reads N consecutive
  *         sof_drc_params per band ; channel ch uses entry[ch] if ch <
  *         params_per_band, else clamps to entry[params_per_band-1].
  *
  */
#define SOF_MULTIBAND_DRC_HEADER_FIXED_SIZE \
	(offsetof(struct sof_multiband_drc_config, drc_coef))


struct sof_multiband_drc_config {
	uint32_t size;
	uint32_t num_bands;
	uint32_t enable_emp_deemp;

	/* reserved */
	uint32_t reserved[8];

	/* config of emphasis eq-iir */
	struct sof_eq_iir_biquad emp_coef[SOF_EMP_DEEMP_BIQUADS];

	/* config of deemphasis eq-iir */
	struct sof_eq_iir_biquad deemp_coef[SOF_EMP_DEEMP_BIQUADS];

	/* config of crossover */
	struct sof_eq_iir_biquad crossover_coef[SOF_CROSSOVER_MAX_LR4];

	/* config of multi-band drc */
	struct sof_drc_params drc_coef[];
};

#endif // __USER_MULTIBAND_DRC_H__
