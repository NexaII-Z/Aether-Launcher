# AETHER Launcher 3.0

A native SwiftUI launcher and companion for the **official Minecraft Bedrock app on iOS**, plus a patcher that adds an **in-game zoom button** to your own Minecraft IPA.

> **Honest summary.** Running Minecraft *inside* AETHER is impossible on stock iOS (`docs/TECHNICAL_REPORT.md`, sections 1-2). A button *inside the game* is possible only by adding a small library to your own copy of the game before you sign it. 3.0 does exactly that and nothing more: no mods, no resource packs, no behavior packs, no game-memory access.

## What's new in 3.0
| Item | Status |
| --- | --- |
| `AetherZoom` overlay (Objective-C dylib): draggable button above gameplay, tap = zoom in/out, hold = change strength | Written, **not compiled or run on a device** |
| `Scripts/aether_patch.py`: injects the library into an IPA / zipped `.app` / `.app` folder | **Tested** on your `minecraftpe` 1.26.32 binary (header room, signature removal, load command, re-parse, idempotency) |
| `Scripts/sign_ipa.sh` + workflow `patch-ipa.yml` | Written, **untested** (needs macOS runner and your certificate) |
| Patch Studio screen (Client tab): settings, copy values, open workflow | Written, **not compiled** |
| Everything from 2.0 (Home, Versions, Client, Discover, Library, Settings, CurseForge, Microsoft sign-in) | Unchanged; see "Known limits" |

The zoom is a **screen magnification**, not a field-of-view change. See the report for side effects.

## Quick start (no Mac)
1. Upload the contents of this folder to the root of a **new private** GitHub repository.
2. **Build the launcher:** Actions > *Build iOS IPA* > Run workflow. Download `AETHERLauncher-unsigned-ipa`, sign it with Sideloadly/AltStore.
3. **Patch Minecraft:**
   1. Repository > Releases > Draft a new release, tag `minecraft-ipa`, attach your own Minecraft `.ipa` (or a `.zip` of the `.app`, like the one you gave me). Keep the repo private.
   2. Actions > *Patch Minecraft IPA (AETHER Zoom)* > Run workflow. Set strength, size, opacity.
   3. Download `Minecraft-AETHER-unsigned-ipa`, sign it (`docs/SIGNING.md`), install, launch.
   Tick **sign** only after adding the three secrets described in `docs/SIGNING.md`.

## Signing requirements
Apple requires every installed app to be signed by you. Unsigned IPAs need Sideloadly/AltStore, or the workflow with your own `.p12` + `.mobileprovision`. Re-signing replaces Mojang's entitlements, so Xbox sign-in, Realms and push may not work. Details: `docs/SIGNING.md`.

## Layout
```
Injection/AetherZoom/AetherZoom.m      overlay library
Scripts/aether_patch.py                Mach-O injector and IPA writer
Scripts/sign_ipa.sh, build_zoom_dylib.sh, build_ipa.sh, preflight.py, inspect_macho.py
.github/workflows/build-ios.yml        launcher build
.github/workflows/patch-ipa.yml        Minecraft patch (+ optional signing)
Sources/                               SwiftUI launcher (iOS 16+)
docs/                                  TECHNICAL_REPORT.md, SIGNING.md
```

## Known limits
- Nothing here was compiled or run on a device: no Xcode, network or iPhone was available. The first Actions runs are the real compile test; expect to fix small errors.
- Minecraft can't run inside AETHER. Version downloads and side-by-side installs are not provided.
- Zoom limits (blur, scaled controls, unknown view hierarchy): report section 6.
- AETHER does not decrypt apps and refuses encrypted binaries. Your uploaded build is already decrypted (`cryptid=0`); use only a copy you're entitled to. Servers may restrict client tools.
- Microsoft sign-in and CurseForge need your own Azure app ID / API key (2.0 notes unchanged). Version metadata doesn't prove which version is installed.

Unofficial; not affiliated with Mojang Studios or Microsoft. MIT licence.
