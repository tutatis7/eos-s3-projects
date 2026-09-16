#!/usr/bin/env python3
"""Enable EOS S3 internal pull-ups in a built FPGA .bin.

The QuickLogic toolchain always writes FPGA pad settings with no pull resistor.
A pin file can ask for one with a comment line such as:

    // pullup: IO_6

This rewrites the pull field of those pads in the IO mux section of the .bin.

.bin layout (bitstream_to_binary.py):
    header: 8 x uint32 LE = version, bitstream size, bitstream crc,
            meminit size, meminit crc, iomux size, iomux crc, reserved
    bitstream, meminit, then iomux as (address, value) uint32 LE pairs
The header CRC fields are written as 0 by the toolchain and not checked by the
bootloader, so they are left alone.

Pad register (eos_s3_iomux_config.py): bits 7:6 = pull (0 none, 1 up, 2 down, 3 keeper),
bit 11 = input enable.

usage: apply_pullups.py <top.bin> <pins.pcf>
"""
import re
import struct
import sys

IOMUX_BASE = 0x40004C00
PULL_MASK = 0b11 << 6
PULL_UP = 0b01 << 6
INPUT_EN = 1 << 11


def main():
    bin_path, pcf_path = sys.argv[1], sys.argv[2]

    pads = []
    with open(pcf_path) as f:
        for line in f:
            m = re.match(r"\s*(//|#)\s*pullup:\s*(.+)", line)
            if m:
                pads += [int(p) for p in re.findall(r"IO_(\d+)", m.group(2))]
    if not pads:
        return

    data = bytearray(open(bin_path, "rb").read())
    header = struct.unpack_from("<8I", data, 0)
    bitstream_size, meminit_size, iomux_size = header[1], header[3], header[5]
    iomux_start = 32 + bitstream_size + meminit_size
    if iomux_start + iomux_size != len(data) or iomux_size % 8:
        sys.exit(f"apply_pullups: unexpected layout in {bin_path}")

    for pad in pads:
        addr = IOMUX_BASE + 4 * pad
        for off in range(iomux_start, iomux_start + iomux_size, 8):
            reg_addr, value = struct.unpack_from("<II", data, off)
            if reg_addr == addr:
                if not value & INPUT_EN:
                    sys.exit(f"apply_pullups: IO_{pad} is not an input in this design")
                new = (value & ~PULL_MASK) | PULL_UP
                struct.pack_into("<I", data, off + 4, new)
                print(f">> Pull-up enabled on IO_{pad} (pad register 0x{value:03x} -> 0x{new:03x})")
                break
        else:
            sys.exit(f"apply_pullups: IO_{pad} is not used by this design")

    open(bin_path, "wb").write(data)


if __name__ == "__main__":
    main()
