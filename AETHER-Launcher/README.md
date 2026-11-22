# AETHER Launcher

A native SwiftUI launcher for the **official Minecraft Bedrock app on iOS**. It does not contain, copy, patch or replace Minecraft. It opens the Minecraft you already have installed and hands it your pack files.

## What it does

| Screen | What it does |
| --- | --- |
| Home | Install status, a Play button, shortcuts |
| Installation | Detects Minecraft via its `minecraft://` URL scheme, shows what iOS can and can't tell us |
| Play | Opens Minecraft (optional confirmation), or the App Store page if it's missing |
| Packs | Imports `.mcpack`, `.mcaddon`, `.mcworld`, `.mctemplate` and pack `.zip` files from Files, reads pack names from `manifest.json` / `levelname.txt`, sends them to Minecraft via the system Open In menu, exports via the share sheet |
| Settings | Haptics, confirm-before-launch, auto re-check, library folder tools |
| About | How it works, iOS limits, disclaimer |

UI: dark, rounded, green accent. On iOS 26 builds the cards use Liquid Glass (`glassEffect`); older systems and older Xcode fall back to blur materials.

## What the supplied ZIP told us

`minecraftpe_2_1.zip` contains an unpacked, unsigned `.app` folder (no `Payload/`, no `_CodeSignature`, no provisioning profile):

- Bundle ID `com.mojang.minecraftpe`, version `1.26.32` (build `1.26.32.02`), minimum iOS 15.0, arm64, iPhone + iPad
- URL scheme **`minecraft`** (plus `ms-xal-...` and a Facebook scheme)
- Document types and exported UTIs for `.mcworld`, `.mcpack`, `.mctemplate`, `.mcaddon`
- `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` set
- Frameworks: `xsapi-c`, `HttpClient`, `PlayFabMultiplayerFramework_iOS`, `Xal`, `MinecraftSwift`
- The main executable is a FairPlay-origin build; `cryptid` is 0

Only these metadata facts were used. **No Minecraft file is bundled, modified or redistributed**, and `.gitignore` blocks `.app` and `Payload/` folders so one can't be committed by accident. Install Minecraft from the App Store; the launcher targets that installation.

## Repository layout

```
AETHER-Launcher/
  project.yml                 XcodeGen spec (single source of truth for the Xcode project and Info.plist)
  Sources/
    App/                      @main, tab routing
    Core/                     Theme, MinecraftBridge, PackInspector (ZIP reader), PackLibrary
    Components/               Shared views, Open In menu helper
    Views/                    Home, Installation, Play, Packs, Settings, About
  Resources/Assets.xcassets/  App icon + accent colour
  Assets/AppIcon-1024.png     Icon master (regenerate with Scripts/generate_icon.py)
  Configuration/Base.xcconfig Build settings (Info.plist is generated here by XcodeGen)
  Scripts/                    build_ipa.sh, preflight.py, generate_icon.py
  .github/workflows/build-ios.yml
```

Deployment target: **iOS 16.0** (NavigationStack, ShareLink). iPhone and iPad.

## Upload to GitHub

Web UI:
1. Create an empty repository on github.com (no README/licence).
2. Unzip `AETHER-Launcher.zip`, open the repo's **Add file > Upload files**, drag in everything **inside** the `AETHER-Launcher` folder (including the hidden `.github` folder; if your file picker hides it, use the git commands below), and commit.

Git:
```bash
cd AETHER-Launcher
git init -b main
git add .
git commit -m "Initial commit: AETHER Launcher"
git remote add origin https://github.com/<you>/<repo>.git
git push -u origin main
```

## Build and download the IPA

1. Open the repository's **Actions** tab. Pushing to `main` starts **Build iOS IPA**; you can also pick it and press **Run workflow**.
2. When the run is green, open it and download the **AETHERLauncher-unsigned-ipa** artifact (a zip containing `AETHERLauncher-unsigned.ipa`). The **xcodebuild-log** artifact is always uploaded, and compiler errors are surfaced as annotations on the run.

The workflow runs on `macos-15`: installs XcodeGen, runs `Scripts/preflight.py`, generates the project, archives with signing disabled, packs `Payload/` into an IPA. No local Mac is needed. To build locally on a Mac: `brew install xcodegen && ./Scripts/build_ipa.sh`.

## Signing

The IPA is **unsigned**. iOS will refuse to install it until it is signed. Options:
- Re-sign and install with a tool that uses your own Apple ID (for example Sideloadly or AltStore). Free accounts expire after 7 days.
- Paid Apple Developer Program: add a signing step to the workflow with your certificate and provisioning profile stored as GitHub secrets, or archive in Xcode on a Mac.

Nothing in AETHER needs special entitlements.

## Known iOS limitations

- AETHER cannot read or write Minecraft's sandbox, inject code, or change its settings. That is by design in iOS.
- Install detection means "something answers to `minecraft://`". It can't read the version, and it can be briefly stale after an install until Minecraft has been opened once.
- Packs and worlds reach Minecraft only when you pick Minecraft in the Open In menu. AETHER can't see whether the import succeeded; Minecraft shows its own progress.
- The pack inspector reads only the ZIP central directory and small entries. ZIP64 archives and unusual compression fall back to the file name.
- Packs whose manifest name is a localisation key (for example `pack.name`) show the file name instead.
- `Show in Files` uses the `shareddocuments://` link, which iOS may refuse in some configurations.

## Assumptions and verification status

- Swift 5 language mode, SwiftUI, no third-party packages.
- The App Store link uses Minecraft's id `479516143`; check it opens the right page on first run.
- **This project was written and statically checked (YAML/JSON validity, icon size, brace balance) in a Linux sandbox. It has not been compiled or run on a device.** The first GitHub Actions run is the real compile test; if it fails, the `xcodebuild-log` artifact shows the exact error.

## Disclaimer

AETHER is an unofficial companion app, not affiliated with or endorsed by Mojang Studios or Microsoft. Minecraft is a trademark of Mojang Synergies AB. See the [Minecraft usage guidelines](https://www.minecraft.net/en-us/usage-guidelines).

Licence: MIT (see `LICENSE`).
