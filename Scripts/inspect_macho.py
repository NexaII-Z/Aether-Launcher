#!/usr/bin/env python3
"""Static Mach-O / code-signature inspector (no execution, no modification).
Usage: inspect_macho.py <binary> [<binary> ...]
"""
import plistlib
import struct
import sys

FILETYPES = {1: "OBJECT", 2: "EXECUTE", 6: "DYLIB", 8: "BUNDLE"}
PLATFORMS = {1: "macOS", 2: "iOS", 3: "tvOS", 4: "watchOS", 7: "iOS Simulator"}
DYLIB_CMDS = {0xC: "LOAD_DYLIB", 0x80000018: "LOAD_WEAK_DYLIB", 0x8000001F: "REEXPORT_DYLIB", 0xD: "ID_DYLIB"}


def cstr(buf, off, end):
    return buf[off:end].split(b"\0")[0].decode(errors="replace")


def parse_signature(blob):
    magic, _length, count = struct.unpack(">III", blob[:12])
    if magic != 0xFADE0CC0:
        return None
    out = {"entitlements": None, "identifier": None, "team": None}
    for i in range(count):
        _slot, off = struct.unpack(">II", blob[12 + i * 8:20 + i * 8])
        m, length = struct.unpack(">II", blob[off:off + 8])
        if m == 0xFADE0C02 and out["identifier"] is None:
            ident = struct.unpack(">I", blob[off + 20:off + 24])[0]
            out["identifier"] = cstr(blob, off + ident, off + ident + 200)
            if struct.unpack(">I", blob[off + 8:off + 12])[0] >= 0x20200:
                team = struct.unpack(">I", blob[off + 48:off + 52])[0]
                if team:
                    out["team"] = cstr(blob, off + team, off + team + 32)
        elif m == 0xFADE7171:
            out["entitlements"] = plistlib.loads(blob[off + 8:off + length])
    return out


def inspect(path):
    with open(path, "rb") as f:
        head = f.read(8 * 1024 * 1024)
    if struct.unpack("<I", head[:4])[0] != 0xFEEDFACF:
        print(f"{path}: not a thin 64-bit little-endian Mach-O")
        return
    cpu, _sub, ftype, ncmds, _size, flags = struct.unpack("<6I", head[4:28])
    print(f"== {path.split('/')[-1]}")
    print(f"  cpu: {'arm64' if cpu == 0x0100000C else hex(cpu)}   filetype: {FILETYPES.get(ftype, ftype)}   PIE: {bool(flags & 0x200000)}")
    off, libs, rpaths, sig, enc, build = 32, [], [], None, None, None
    for _ in range(ncmds):
        cmd, size = struct.unpack("<II", head[off:off + 8])
        if cmd in DYLIB_CMDS:
            name_off = struct.unpack("<I", head[off + 8:off + 12])[0]
            libs.append((DYLIB_CMDS[cmd], cstr(head, off + name_off, off + size)))
        elif cmd == 0x8000001C:
            name_off = struct.unpack("<I", head[off + 8:off + 12])[0]
            rpaths.append(cstr(head, off + name_off, off + size))
        elif cmd == 0x1D:
            sig = struct.unpack("<II", head[off + 8:off + 16])
        elif cmd == 0x2C:
            enc = struct.unpack("<4I", head[off + 8:off + 24])
        elif cmd == 0x32:
            build = struct.unpack("<5I", head[off + 8:off + 28])
        off += size
    if build:
        print(f"  platform: {PLATFORMS.get(build[0], build[0])}   minos: {build[1] >> 16}.{(build[1] >> 8) & 255}   sdk: {build[2] >> 16}.{(build[2] >> 8) & 255}")
    if enc:
        print(f"  FairPlay encryption: cryptid={enc[2]} (cryptoff={enc[0]}, cryptsize={enc[1]})")
    else:
        print("  FairPlay encryption: no LC_ENCRYPTION_INFO_64")
    print(f"  rpaths: {rpaths}")
    if sig:
        with open(path, "rb") as f:
            f.seek(sig[0])
            parsed = parse_signature(f.read(sig[1]))
        print(f"  code signature: present ({sig[1]} bytes)")
        if parsed:
            print(f"    identifier: {parsed['identifier']}   team: {parsed['team']}")
            for key, value in (parsed["entitlements"] or {}).items():
                print(f"    entitlement {key} = {value}")
    else:
        print("  code signature: ABSENT")
    for kind, name in libs:
        print(f"  {kind:16s} {name}")


if __name__ == "__main__":
    for target in sys.argv[1:]:
        inspect(target)
        print()
