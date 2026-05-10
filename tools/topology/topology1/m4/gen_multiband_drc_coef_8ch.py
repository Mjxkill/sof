#!/usr/bin/env python3
"""
gen_multiband_drc_coef_8ch.py

Extends the stock multiband_drc_coef_default.m4 blob from
  [header + num_bands × 1 × sof_drc_params]   (legacy, params_per_band = 1)
to
  [header + num_bands × N × sof_drc_params]   (V7.0-E2, params_per_band = N)

For E2 initial validation we use N = 8 (= 8 channels) and DUPLICATE the
per-band params 8 times — same compression behaviour across channels.
Differentiation per channel (T2.5 / T2.6) is a follow-up that just tweaks
the bytes at offset (band*8 + ch)*88 within the drc_coef[] array.

Constants must match :
  - sizeof(struct sof_drc_params) = 88 bytes (cf src/audio/drc/drc_user.h)
  - SOF_MULTIBAND_DRC_HEADER_FIXED_SIZE = offsetof(.., drc_coef[])
    computed dynamically here from the source blob.

Source m4 layout (CONTROLBYTES_PRIV with `bytes "0xNN,0xNN,..."` lines).
We parse the lines, rebuild bytes, replicate, and dump back to m4.

Usage :
  python3 gen_multiband_drc_coef_8ch.py
    -> generates multiband_drc_coef_default_8ch.m4 next to this script

  python3 gen_multiband_drc_coef_8ch.py --channels N
    -> N copies per band (default 8)
"""
import argparse
import re
import struct
from pathlib import Path

DRC_PARAMS_SIZE = 88   # bytes, must match struct sof_drc_params packed
SOF_ABI_HDR_SIZE = 32  # struct sof_abi_hdr packed (magic+type+size+abi+reserved[4])
SCRIPT_DIR = Path(__file__).parent
SRC_M4 = SCRIPT_DIR / "multiband_drc_coef_default.m4"
DST_M4 = SCRIPT_DIR / "multiband_drc_coef_default_8ch.m4"


def parse_m4_blob(path: Path) -> tuple[str, bytes, str]:
    """Returns (prefix_text_before_bytes, raw_bytes, suffix_text_after_bytes)."""
    text = path.read_text()
    # Match the block : bytes "0xNN,..,(continued lines)" — first `bytes "` to closing `"`
    m = re.search(r'`\s*bytes\s+"', text)
    if not m:
        raise SystemExit("could not find 'bytes \"' opening in source m4")
    start = m.end()
    end = text.rfind("'", start)
    if end < 0:
        raise SystemExit("could not find blob closing in source m4")

    blob_text = text[start:end]
    prefix = text[:m.start()]
    suffix = text[end:]

    # Extract hex bytes
    nums = re.findall(r"0x([0-9a-fA-F]{1,2})", blob_text)
    raw = bytes(int(n, 16) for n in nums)
    return prefix, raw, suffix


def emit_blob_text(raw: bytes, bytes_per_line: int = 8, indent: str = "\t") -> str:
    """Format raw bytes back into m4 quoted lines using `bytes "..."` syntax.

    First line opens with `\\tbytes "0xNN,...,'  (single m4 quote + bytes keyword
    + double quote opening). Intermediate lines continue inside the double-quoted
    string. Last line closes with `0xNN"'  (close double quote + close m4 quote).
    """
    n = len(raw)
    lines = []
    for i in range(0, n, bytes_per_line):
        chunk = raw[i:i + bytes_per_line]
        hex_str = ",".join(f"0x{b:02x}" for b in chunk)
        is_first = (i == 0)
        is_last = (i + bytes_per_line >= n)

        if is_first:
            prefix = f"`{indent}bytes \""
        else:
            prefix = f"`{indent}"

        if is_last:
            suffix = "\"'"
        else:
            suffix = ",'"

        lines.append(f"{prefix}{hex_str}{suffix}")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--channels", type=int, default=8,
                    help="number of channel copies per band (default 8)")
    args = ap.parse_args()

    if not SRC_M4.exists():
        raise SystemExit(f"missing source : {SRC_M4}")

    prefix, raw, suffix = parse_m4_blob(SRC_M4)
    print(f"source blob : {len(raw)} bytes")

    if len(raw) < SOF_ABI_HDR_SIZE + 12:
        raise SystemExit("blob too short to hold abi_hdr + multiband_drc header")

    # Parse sof_abi_hdr (32 bytes prefix)
    magic = struct.unpack_from("<I", raw, 0)[0]
    abi_type = struct.unpack_from("<I", raw, 4)[0]
    abi_size = struct.unpack_from("<I", raw, 8)[0]   # size of payload (excl. abi_hdr)
    abi_ver = struct.unpack_from("<I", raw, 12)[0]
    print(f"abi_hdr : magic=0x{magic:08x} type=0x{abi_type:08x} "
          f"size={abi_size} abi=0x{abi_ver:08x}")
    if magic != 0x00464F53:
        raise SystemExit(f"unexpected magic 0x{magic:08x} (expected 0x00464F53 'SOF\\0')")

    payload = raw[SOF_ABI_HDR_SIZE:]
    if abi_size != len(payload):
        print(f"warn: abi_size {abi_size} != payload bytes {len(payload)} — using actual")
        abi_size = len(payload)

    # struct sof_multiband_drc_config :
    #   uint32_t size; uint32_t num_bands; uint32_t enable_emp_deemp;
    cfg_size = struct.unpack_from("<I", payload, 0)[0]
    cfg_num_bands = struct.unpack_from("<I", payload, 4)[0]
    cfg_enable = struct.unpack_from("<I", payload, 8)[0]
    print(f"cfg.size       = {cfg_size}")
    print(f"cfg.num_bands  = {cfg_num_bands}")
    print(f"cfg.enable     = {cfg_enable}")

    if cfg_size != len(payload):
        print(f"warn: cfg.size {cfg_size} != payload {len(payload)} — using actual")
        cfg_size = len(payload)

    # Compute header_fixed (offset of drc_coef) from legacy layout :
    # drc_coef[] = cfg_num_bands * 1 * DRC_PARAMS_SIZE bytes
    legacy_drc_total = cfg_num_bands * 1 * DRC_PARAMS_SIZE
    header_fixed = cfg_size - legacy_drc_total
    print(f"derived header_fixed (offsetof drc_coef) = {header_fixed}")
    print(f"legacy drc_coef total                    = {legacy_drc_total}")

    if header_fixed <= 0:
        raise SystemExit("could not derive header_fixed — blob shape unexpected")

    # Split payload : header / drc_coef
    header = bytearray(payload[:header_fixed])
    legacy_drc = payload[header_fixed:]
    if len(legacy_drc) != legacy_drc_total:
        raise SystemExit(f"length mismatch : {len(legacy_drc)} vs {legacy_drc_total}")

    # Replicate per-band params N times
    N = args.channels
    new_drc = bytearray()
    for band in range(cfg_num_bands):
        band_off = band * DRC_PARAMS_SIZE
        band_params = legacy_drc[band_off:band_off + DRC_PARAMS_SIZE]
        for ch in range(N):
            new_drc.extend(band_params)
    print(f"new drc_coef total = {len(new_drc)} bytes ({cfg_num_bands} bands × {N} ch × {DRC_PARAMS_SIZE})")

    # New payload size (struct sof_multiband_drc_config)
    new_payload_size = header_fixed + len(new_drc)
    new_total_size = SOF_ABI_HDR_SIZE + new_payload_size
    print(f"new payload size = {new_payload_size} bytes")
    print(f"new total size   = {new_total_size} bytes (incl. abi_hdr)")

    # Update cfg.size field in header (struct field at offset 0 of payload)
    struct.pack_into("<I", header, 0, new_payload_size)

    new_payload = bytes(header) + bytes(new_drc)

    # Update abi_hdr.size field at offset 8 (uint32 size of payload excl. abi_hdr)
    abi_hdr_bytes = bytearray(raw[:SOF_ABI_HDR_SIZE])
    struct.pack_into("<I", abi_hdr_bytes, 8, new_payload_size)

    new_raw = bytes(abi_hdr_bytes) + new_payload

    blob_text = emit_blob_text(new_raw)

    # Build output m4 file : replace name + bytes block, keep CONTROLBYTES_PRIV macro
    out = (
        "# Generated by gen_multiband_drc_coef_8ch.py — V7.0-E2 per-channel-per-band\n"
        "# Derived from multiband_drc_coef_default.m4 :\n"
        f"#   num_bands = {cfg_num_bands}, params_per_band = {N} (replicated)\n"
        f"#   payload size = {new_payload_size} bytes (was {cfg_size})\n"
        f"#   total size (with abi_hdr) = {new_total_size} bytes (was {len(raw)})\n"
        "# The replication is identical per-channel (no differentiation yet).\n"
        "# Edit individual drc_params at offset (band*N + ch) * 88 for T2.5/T2.6.\n"
        "\n"
        "CONTROLBYTES_PRIV(MULTIBAND_DRC_priv_8ch,\n"
        f"{blob_text}\n)\n"
    )

    DST_M4.write_text(out)
    print(f"wrote {DST_M4}")


if __name__ == "__main__":
    main()
