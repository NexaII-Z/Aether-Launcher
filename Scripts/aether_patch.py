#!/usr/bin/env python3
"""AETHER patcher: adds the AetherZoom overlay library to your own Minecraft install.

What it does (and nothing else):
  1. Reads an .ipa, a .zip of an .app, or an .app folder you provide.
  2. Copies AetherZoom.dylib into <app>/Frameworks/.
  3. Adds one LC_LOAD_DYLIB command to the main executable so iOS loads that library at launch.
  4. Drops the old code signature (it is invalid after step 3) and writes aether_zoom.json.
  5. Writes a new .ipa. The result is UNSIGNED: sign it with Scripts/sign_ipa.sh or a tool such as Sideloadly.

It never decrypts anything. A binary that is still FairPlay-encrypted (cryptid=1) is refused.
It does not touch worlds, resource packs, behavior packs or game data.
"""
import argparse, json, os, plistlib, shutil, stat, struct, sys, tempfile, zipfile

MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
CPU_ARM64 = 0x0100000C
LC_SEGMENT_64 = 0x19
LC_LOAD_DYLIB = 0x0C
LC_LOAD_WEAK_DYLIB = 0x80000018
LC_REEXPORT_DYLIB = 0x8000001F
LC_CODE_SIGNATURE = 0x1D
LC_ENCRYPTION_INFO_64 = 0x2C
DYLIB_NAME = "@rpath/AetherZoom.dylib"
PAGE = 0x4000


class PatchError(Exception):
    pass


def align(n, a):
    return (n + a - 1) // a * a


def arm64_slice(f):
    f.seek(0)
    head = f.read(8)
    if len(head) < 8:
        raise PatchError("File is too small to be a Mach-O binary.")
    magic = struct.unpack(">I", head[:4])[0]
    if magic == FAT_MAGIC:
        count = struct.unpack(">I", head[4:8])[0]
        for i in range(count):
            f.seek(8 + i * 20)
            cpu, _sub, off, size, _al = struct.unpack(">5I", f.read(20))
            if cpu == CPU_ARM64:
                return off, size
        raise PatchError("Fat binary has no arm64 slice.")
    if struct.unpack("<I", head[:4])[0] == MH_MAGIC_64:
        f.seek(0, os.SEEK_END)
        return 0, f.tell()
    raise PatchError("Main executable is not a 64-bit Mach-O.")


def inject(binary, dylib_name=DYLIB_NAME, check_only=False):
    """Returns a list of human-readable report lines. Edits `binary` in place unless check_only."""
    report = []
    with open(binary, "r+b") as f:
        base, slice_size = arm64_slice(f)
        f.seek(0, os.SEEK_END)
        file_end = f.tell()
        f.seek(base)
        magic, cpu, _sub, ftype, ncmds, sizeofcmds, flags, _res = struct.unpack("<8I", f.read(32))
        if magic != MH_MAGIC_64 or cpu != CPU_ARM64:
            raise PatchError("Slice is not arm64.")
        cmds = bytearray(f.read(sizeofcmds))

        off = 0
        entries = []  # (cmd, size, offset_in_cmds)
        first_section = None
        linkedit = None
        sig = None
        cryptid = None
        already = False
        for _ in range(ncmds):
            cmd, size = struct.unpack_from("<II", cmds, off)
            if cmd == LC_SEGMENT_64:
                segname = bytes(cmds[off + 8:off + 24]).split(b"\0")[0]
                fileoff, filesize = struct.unpack_from("<QQ", cmds, off + 40)
                nsects = struct.unpack_from("<I", cmds, off + 64)[0]
                if segname == b"__LINKEDIT":
                    linkedit = (off, fileoff, filesize)
                p = off + 72
                for _s in range(nsects):
                    soff = struct.unpack_from("<I", cmds, p + 48)[0]
                    ssize = struct.unpack_from("<Q", cmds, p + 40)[0]
                    if soff and ssize and (first_section is None or soff < first_section):
                        first_section = soff
                    p += 80
            elif cmd in (LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB):
                nameoff = struct.unpack_from("<I", cmds, off + 8)[0]
                name = bytes(cmds[off + nameoff:off + size]).split(b"\0")[0].decode("utf-8", "replace")
                if name == dylib_name:
                    already = True
            elif cmd == LC_CODE_SIGNATURE:
                sig = (off, *struct.unpack_from("<II", cmds, off + 8))
            elif cmd == LC_ENCRYPTION_INFO_64:
                cryptid = struct.unpack_from("<I", cmds, off + 16)[0]
            entries.append((cmd, size, off))
            off += size

        if ftype != 2:
            raise PatchError("Main executable is not MH_EXECUTE (filetype %d)." % ftype)
        if cryptid:
            raise PatchError("The executable is still FairPlay-encrypted (cryptid=%d). AETHER does not decrypt apps, and patching an encrypted binary would corrupt it." % cryptid)
        report.append("arm64 slice at offset %d, %d load commands, %d bytes of commands" % (base, ncmds, sizeofcmds))
        report.append("encryption: cryptid=%s" % ("n/a" if cryptid is None else cryptid))
        if already:
            report.append("already patched: %s is present, nothing to do" % dylib_name)
            return report

        raw = dylib_name.encode() + b"\0"
        new_size = align(24 + len(raw), 8)
        new_cmd = struct.pack("<6I", LC_LOAD_DYLIB, new_size, 24, 2, 0x10000, 0x10000) + raw
        new_cmd += b"\0" * (new_size - len(new_cmd))

        sig_size = 0
        if sig:
            sig_size = next(s for c, s, o in entries if o == sig[0])
        free = (first_section or 0) - (32 + sizeofcmds) + sig_size
        report.append("header room: %d bytes free, need %d" % (free, new_size))
        if first_section is None or new_size > free:
            raise PatchError("Not enough free space in the Mach-O header for one more load command.")

        sig_note = "none"
        shrink = False
        if sig:
            _o, sig_off, sig_len = sig
            at_end = (base + sig_off + sig_len == file_end) and linkedit and (linkedit[1] + linkedit[2] == sig_off + sig_len)
            shrink = bool(at_end)
            sig_note = "%d bytes at end of file (%s)" % (sig_len, "removed" if shrink else "left in place; run codesign to replace")
        report.append("old code signature: " + sig_note)
        if check_only:
            report.append("check only: file not modified")
            return report

        kept = bytearray()
        count = 0
        for cmd, size, o in entries:
            if sig and o == sig[0]:
                continue
            kept += cmds[o:o + size]
            count += 1
        kept += new_cmd
        count += 1
        if shrink:
            lo, lfileoff, _lfs = linkedit
            _o, sig_off, sig_len = sig
            # locate the LINKEDIT command inside `kept` again and shrink it
            p = 0
            for _ in range(count):
                cmd, size = struct.unpack_from("<II", kept, p)
                if cmd == LC_SEGMENT_64 and bytes(kept[p + 8:p + 24]).split(b"\0")[0] == b"__LINKEDIT":
                    new_fs = sig_off - lfileoff
                    struct.pack_into("<Q", kept, p + 32, align(new_fs, PAGE))  # vmsize
                    struct.pack_into("<Q", kept, p + 48, new_fs)               # filesize
                    break
                p += size
        pad = b"\0" * max(0, sizeofcmds - len(kept))
        f.seek(base + 32)
        f.write(bytes(kept) + pad)
        f.seek(base + 16)
        f.write(struct.pack("<II", count, len(kept)))
        if shrink:
            f.truncate(base + sig_off)
        report.append("patched: added LC_LOAD_DYLIB %s (%d commands now)" % (dylib_name, count))
    return report


def find_app(root):
    payload = os.path.join(root, "Payload")
    if os.path.isdir(payload):
        for n in sorted(os.listdir(payload)):
            if n.endswith(".app"):
                return os.path.join(payload, n)
    best = None
    for dp, dn, fn in os.walk(root):
        if "__MACOSX" in dp:
            continue
        if "Info.plist" in fn:
            try:
                with open(os.path.join(dp, "Info.plist"), "rb") as fh:
                    info = plistlib.load(fh)
            except Exception:
                continue
            exe = info.get("CFBundleExecutable")
            if exe and os.path.isfile(os.path.join(dp, exe)):
                depth = dp.count(os.sep)
                if best is None or depth < best[0]:
                    best = (depth, dp)
    if not best:
        raise PatchError("No app bundle (Info.plist + executable) found in the input.")
    return best[1]


def write_ipa(app, out):
    name = os.path.basename(app.rstrip("/"))
    if not name.endswith(".app"):
        name = (json_name(app) or "Minecraft") + ".app"
    exe_paths = set()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for dp, dn, fn in os.walk(app):
            dn.sort()
            for n in sorted(fn):
                full = os.path.join(dp, n)
                rel = os.path.relpath(full, app)
                arc = "Payload/%s/%s" % (name, rel.replace(os.sep, "/"))
                info = zipfile.ZipInfo.from_file(full, arc)
                mode = os.stat(full).st_mode
                is_exec = bool(mode & stat.S_IXUSR) or rel.endswith(".dylib")
                info.external_attr = ((0o755 if is_exec else 0o644) | stat.S_IFREG) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                with open(full, "rb") as src, z.open(info, "w", force_zip64=True) as dst:
                    shutil.copyfileobj(src, dst, 1 << 20)
    return name


def json_name(app):
    try:
        with open(os.path.join(app, "Info.plist"), "rb") as fh:
            return plistlib.load(fh).get("CFBundleExecutable")
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser(description="Add the AETHER zoom overlay to your own Minecraft IPA.")
    ap.add_argument("input", help=".ipa, .zip containing the .app, or an .app folder")
    ap.add_argument("--dylib", default="build/AetherZoom.dylib", help="built AetherZoom.dylib")
    ap.add_argument("--out", default="build/Minecraft-AETHER-unsigned.ipa")
    ap.add_argument("--zoom", type=float, default=3.0, help="zoom strength, 1.25 to 8")
    ap.add_argument("--button-size", type=float, default=54)
    ap.add_argument("--opacity", type=float, default=0.9)
    ap.add_argument("--no-smooth", action="store_true")
    ap.add_argument("--check", action="store_true", help="inspect only, write nothing")
    a = ap.parse_args()

    tmp = tempfile.mkdtemp(prefix="aether-")
    try:
        if os.path.isdir(a.input):
            src = os.path.join(tmp, "src")
            shutil.copytree(a.input, src, symlinks=True)
        else:
            src = os.path.join(tmp, "src")
            with zipfile.ZipFile(a.input) as z:
                z.extractall(src)
        app = find_app(src)
        with open(os.path.join(app, "Info.plist"), "rb") as fh:
            info = plistlib.load(fh)
        exe = os.path.join(app, info["CFBundleExecutable"])
        print("App: %s %s (%s)" % (info.get("CFBundleIdentifier"), info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")))
        for line in inject(exe, check_only=True):
            print("  " + line)
        if a.check:
            return 0
        if not os.path.isfile(a.dylib):
            raise PatchError("Dylib not found: %s (run Scripts/build_zoom_dylib.sh on macOS first)." % a.dylib)
        for line in inject(exe):
            print("  " + line)
        os.chmod(exe, 0o755)
        fw = os.path.join(app, "Frameworks")
        os.makedirs(fw, exist_ok=True)
        shutil.copyfile(a.dylib, os.path.join(fw, "AetherZoom.dylib"))
        os.chmod(os.path.join(fw, "AetherZoom.dylib"), 0o755)
        cfg = {"strength": max(1.25, min(8.0, a.zoom)), "buttonSize": max(32, min(96, a.button_size)),
               "opacity": max(0.25, min(1.0, a.opacity)), "smooth": not a.no_smooth, "patchedBy": "AETHER 3.0"}
        with open(os.path.join(app, "aether_zoom.json"), "w") as fh:
            json.dump(cfg, fh, indent=2)
        shutil.rmtree(os.path.join(app, "_CodeSignature"), ignore_errors=True)
        prof = os.path.join(app, "embedded.mobileprovision")
        if os.path.exists(prof):
            os.remove(prof)
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        if os.path.exists(a.out):
            os.remove(a.out)
        name = write_ipa(app, a.out)
        print("Wrote %s (%.1f MB), bundle %s. Unsigned: sign it before installing." % (a.out, os.path.getsize(a.out) / 1e6, name))
        return 0
    except PatchError as e:
        print("error: %s" % e, file=sys.stderr)
        return 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
