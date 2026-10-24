#!/usr/bin/env python3
"""
patch-vbios.py
Automates stripping the vendor header from dumped NVIDIA GPU ROMs.
Identifies the standard 0x55 0xAA ('U\xAA') PCI ROM signature immediately
preceding the 'VIDEO' identifier string and extracts the pure vBIOS.
"""

import sys
import os

def patch_rom(input_path, output_path):
    if not os.path.isfile(input_path):
        print(f"[ERROR] Input file '{input_path}' not found!")
        sys.exit(1)

    with open(input_path, "rb") as f:
        data = f.read()

    video_offset = data.find(b"VIDEO")
    if video_offset == -1:
        print("[WARNING] 'VIDEO' string not found in the ROM file.")
        print("This file may already be patched, or it is not a standard NVIDIA vBIOS.")
        choice = input("Do you want to copy it as-is? [y/N]: ").strip().lower()
        if choice == 'y':
            with open(output_path, "wb") as f:
                f.write(data)
            print(f"[OK] Saved to {output_path}")
            return
        else:
            sys.exit(1)

    # Search backwards from VIDEO offset to find 0x55 0xAA (ASCII 'U\xaa')
    rom_start = -1
    search_start = max(0, video_offset - 2048)
    for idx in range(video_offset, search_start, -1):
        if data[idx:idx+2] == b"\x55\xaa":
            rom_start = idx
            break

    if rom_start == -1:
        print("[ERROR] Could not locate PCI ROM signature (0x55 0xAA) preceding 'VIDEO'.")
        sys.exit(1)

    print(f"[INFO] Found 'VIDEO' at offset: 0x{video_offset:X} ({video_offset})")
    print(f"[INFO] Found ROM header signature (0x55 0xAA) at offset: 0x{rom_start:X} ({rom_start})")
    print(f"[INFO] Stripping 0x{rom_start:X} ({rom_start}) bytes of leading header.")

    pure_rom = data[rom_start:]

    with open(output_path, "wb") as f:
        f.write(pure_rom)

    print(f"[SUCCESS] Patched ROM saved to: {output_path}")
    print(f"Original size: {len(data):,} bytes | Patched size: {len(pure_rom):,} bytes")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 patch-vbios.py <input_vbios.rom> [output_patched.rom]")
        print("Example: python3 patch-vbios.py vbios.rom patched.rom")
        sys.exit(1)

    inp = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else "patched.rom"
    patch_rom(inp, out)
