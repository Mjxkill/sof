/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright(c) 2026 Electrosens. All rights reserved.
 *
 * NPU tap V3.2.2 — capture du buffer audio post-effets (post-MBDRC/PGA/DRC)
 * vers une zone DRAM partagée DSP↔A53 pour analyse ML temps réel par NPU.
 *
 * Architecture :
 *   - Adresse fixe : 0x942B0000 (256 KB no-map carve dans dsp_reserved_heap),
 *     hors SOF MEMORY{} (au-delà de 0x93400000), dans cacheattr region 4
 *     (0x80000000-0x9FFFFFFF, write-through cacheable).
 *   - Hook : dai_dma_cb() après dma_buffer_copy_to() succès (else branch).
 *   - Sentinelle mono-DAI (R7) : un seul DAI playback peut être tapé à la fois.
 *
 * R2/R5 : NPU_TAP_PHYS_ADDR DOIT correspondre à la valeur définie dans
 *   meta-local/recipes-kernel/imx-audio-tap/imx-audio-tap-uapi.h.
 *   Yocto recipe `do_configure` fait un diff au build et bbfatal si divergence.
 *   DT runtime check (A7) côté kernel valide aussi à l'init.
 *
 * M6 — LIMITATION Phase 2 (mono-DAI) :
 *   Si Phase 2 ajoute USB UAC2 playback en parallèle à SAI7 TX, soit accepter
 *   qu'UN SEUL des deux est tapé (sentinelle actuelle), soit refactor avec
 *   per-DAI buffer (4 zones DT séparées).
 */

#ifndef __SOF_AUDIO_NPU_TAP_H__
#define __SOF_AUDIO_NPU_TAP_H__

#include <stdint.h>
#include <stddef.h>
#include <xtensa/config/core-isa.h>   /* XCHAL_DCACHE_LINESIZE = 128 sur HiFi4 */

#define NPU_TAP_MAGIC          0x5441504Eu   /* "NPAT" little-endian */
#define NPU_TAP_RING_SIZE      0x40000u      /* 256 KB total (header + data) */
#define NPU_TAP_HDR_SIZE       128u          /* M2 : full HiFi4 cache line */
#define NPU_TAP_DATA_SIZE_MAX  (NPU_TAP_RING_SIZE - NPU_TAP_HDR_SIZE)  /* = 262016 */
#define NPU_TAP_PHYS_ADDR      0x942B0000u

/*
 * struct npu_tap_hdr — layout figé 128 B pour atomicité cache line HiFi4.
 *
 * Pattern publication DSP (R3 canonique smp_store_release) :
 *   1. magic = 0  (invalidate header during init)
 *   2. zero-init reserved fields
 *   3. data state : version, ring_size, hdr_size, write_idx=0, read_idx=0,
 *      period_bytes, sample_rate, channels, frame_fmt
 *   4. dcache_writeback_region(hdr, offsetof(epoch))
 *   5. memw barrier
 *   6. epoch = ++dd->tap_epoch ; dcache_writeback ; memw
 *   7. magic = NPU_TAP_MAGIC ; dcache_writeback ; memw  (publish LAST, M5)
 *
 * Pattern lecture A53 (R4 seqcount-style) :
 *   do {
 *     verify magic == NPU_TAP_MAGIC (else retry)
 *     e1 = atomic_load_acquire(&hdr->epoch)
 *     w  = atomic_load_acquire(&hdr->write_idx)
 *     read data into local buffer
 *     e2 = atomic_load_acquire(&hdr->epoch)
 *   } while (e1 != e2);
 *   if (e1 != last_seen_epoch) { reset read_idx ; last_seen_epoch = e1; }
 *
 * R6 — A53 doit utiliser hdr->ring_size (runtime), JAMAIS NPU_TAP_DATA_SIZE_MAX.
 */
struct npu_tap_hdr {
	uint32_t magic;          /* @0   : NPU_TAP_MAGIC, écrit en DERNIER (M5) */
	uint32_t version;        /* @4   : 4 (V3.2.2) */
	uint32_t ring_size;      /* @8   : R6 — runtime (multiple of period_bytes) */
	uint32_t hdr_size;       /* @12  : NPU_TAP_HDR_SIZE = 128 */
	uint32_t epoch;          /* @16  : R1 — DSP increments par dai_common_params, publish AVANT magic */
	uint32_t write_idx;      /* @20  : DSP, wrap mod ring_size */
	uint32_t read_idx;       /* @24  : A53, wrap mod ring_size */
	uint32_t period_bytes;   /* @28  : 3072 nominal (8ch × 4B × 96 frames @ 2 ms) */
	uint32_t sample_rate;    /* @32  : 48000 */
	uint32_t channels;       /* @36  : 8 */
	uint32_t frame_fmt;      /* @40  : SOF_IPC_FRAME_S32_LE */
	uint32_t reserved[19];   /* @44..@124 : zero-init, padding to 128B (M2) */
} __attribute__((packed, aligned(128)));    /* M1 : HiFi4 cache line alignment */

/* M3 : compile-time assertions */
_Static_assert(sizeof(struct npu_tap_hdr) == 128,
	"npu_tap_hdr must be exactly 128B (HiFi4 cache line)");
_Static_assert(sizeof(struct npu_tap_hdr) <= XCHAL_DCACHE_LINESIZE,
	"npu_tap_hdr must fit in one HiFi4 cache line");
_Static_assert(NPU_TAP_PHYS_ADDR == 0x942B0000u,
	"NPU_TAP_PHYS_ADDR fixed (must match imx-audio-tap-uapi.h)");
_Static_assert(offsetof(struct npu_tap_hdr, magic) == 0, "magic @0");
_Static_assert(offsetof(struct npu_tap_hdr, epoch) == 16, "epoch @16");
_Static_assert(offsetof(struct npu_tap_hdr, write_idx) == 20, "write_idx @20");
_Static_assert(NPU_TAP_HDR_SIZE == 128u, "NPU_TAP_HDR_SIZE must be 128");

/*
 * R7 sentinel ownership (mono-DAI). NULL = available.
 * Single-core CONFIG_CORE_COUNT=1 → no atomic/spinlock required.
 */
struct dai_data;
extern struct dai_data *npu_tap_owner;

#endif /* __SOF_AUDIO_NPU_TAP_H__ */
