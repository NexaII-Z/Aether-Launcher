# AETHER Launcher 2.0

A native SwiftUI launcher and companion for the **official Minecraft Bedrock app on iOS**. It does not contain, copy, patch or run Minecraft.

> **Read this first: running the real Minecraft engine inside AETHER is not possible on stock iOS.**
> `docs/TECHNICAL_REPORT.md` has the evidence (Mach-O type, signing team, entitlements, lifecycle) and the exact blockers. Because of them, the in-game zoom button cannot be drawn over real gameplay and cannot touch the real camera. AETHER 2.0 builds everything that *can* legitimately exist and labels the rest as blocked.

## Status of every requested item

| Area | Status | Notes |
| --- | --- | --- |
| Launch the installed Minecraft (`minecraft://`) | Implemented (1.0) | Carried over unchanged. |
| Run Minecraft inside AETHER | **Blocked** | `MH_EXECUTE` binary, Mojang team signature, identity-bound entitlements, no embedding API. See report. |
| Runtime investigation module | Implemented, untested on device | `Settings > Runtime investigation` reads any binary's Mach-O/signature facts and derives blockers. Python twin: `Scripts/inspect_macho.py`. |
| Zoom button over real gameplay | **Blocked** | No overlay or hosting surface on iOS. |
| Zoom changes the real camera | **Blocked** | No camera integration point. Only `UnavailableCameraBackend` exists; the UI reports "Not applied". |
| Zoom overlay prototype | Implemented, experimental, untested on device | Draggable button on a neutral test stage: size, strength, opacity, persisted position, tap/pointer/keyboard (Z). |
| Client feature manager (10 features) | Implemented; every in-game feature marked "Requires runtime integration" | Real persistence and config screens. Settings are saved but have no effect on Minecraft. |
| Version manager | Implemented as metadata + isolated storage | Add from Info.plist or manually, set active, repair, delete AETHER data, device compatibility check. **No version downloads or side-by-side installs**: there is no legitimate source or mechanism. |
| Independent storage | Implemented | `Application Support/AETHER/{Versions,Downloads,Worlds,ResourcePacks,BehaviorPacks,Settings,Cache,Clients}` plus the Files-visible library from 1.0. |
| CurseForge browser | Implemented, untested (needs your API key) | Search, classes discovered from the API, sort, version filter, thumbnails, screenshots, description, files, changelogs. |
| Download manager | Implemented, untested | Progress, cancel, retry, history, duplicate detection (URL/file ID and SHA-1), SHA-1 check, ZIP and manifest validation. Foreground session: pauses when iOS suspends AETHER. |
| Library | Implemented | Filters, favourites, rename (display name), details, export, share, delete, import. "Downloaded" is kept separate from "sent to Minecraft menu", which AETHER can't confirm. |
| Microsoft / Xbox sign-in | Implemented, untested (needs your Azure app ID) | OAuth + PKCE, Xbox Live/XSTS exchange, gamertag, Keychain refresh token, sign out, error mapping. Not an ownership check. |
| Redesigned UI | Implemented | Home, Versions, Client, Discover, Library, Settings with a custom tab bar; Settings covers appearance, downloads, storage, cache, notifications, account, about. |

"Untested" means written against the documented APIs but never compiled or run: this was produced in a Linux sandbox without Xcode, network or credentials. Static checks only (`Scripts/preflight.py`). The first Actions run is the compile test.

## Secrets

AETHER ships **no** CurseForge key and no Microsoft secret. Any key inside an IPA can be extracted.
- CurseForge: paste your own key (Keychain) in Settings, or set a proxy address you control that adds the key server-side.
- Microsoft: enter your own Azure *application (client) ID* (public, not secret). Register redirect URI `aether://auth` as "Mobile and desktop applications" and allow public client flows. Whether the `XboxLive.signin` scope is accepted for a given app registration can vary; this is unverified.

## Project layout (unchanged structure, new files added)

```
project.yml                  XcodeGen spec (version 2.0.0, iOS 16.0)
Sources/App, Core, Components, Views, Services
docs/TECHNICAL_REPORT.md     Executable investigation and blockers
docs/investigation-minecraftpe-1.26.32.txt
Scripts/                     build_ipa.sh, preflight.py, inspect_macho.py, generate_icon.py
.github/workflows/build-ios.yml   (unchanged)
```

## Build (no Mac needed)

Push to GitHub; **Actions > Build iOS IPA** produces the `AETHERLauncher-unsigned-ipa` artifact and an `xcodebuild-log` artifact. In Codespaces you can only run `python3 Scripts/preflight.py`; compiling needs the macOS runner. Unsigned IPAs must be signed (for example Sideloadly or AltStore) before iOS will install them.

Upgrading from 1.0: replace the sources with this tree. The library folder, URL scheme detection and Open In flow are unchanged, and existing imported files keep working.

## Known limits

- Everything in the blocked rows above.
- Version records don't prove which version is installed.
- Downloads and CurseForge/Microsoft flows need network access and your credentials.
- Files whose author disables third-party distribution can't be downloaded in-app; AETHER links to CurseForge instead.
- The release-notes link on the Versions screen points at Mojang's feedback site and hasn't been verified.

## Disclaimer

Unofficial; not affiliated with or endorsed by Mojang Studios or Microsoft. Minecraft is a trademark of Mojang Synergies AB. MIT licence.
