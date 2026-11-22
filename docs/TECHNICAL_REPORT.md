# Technical report: can Minecraft Bedrock run inside AETHER on iOS?

**Short answer: no, not on stock iOS, and not through any mechanism AETHER is allowed to use.**
Evidence below comes from static inspection only (`Scripts/inspect_macho.py`, raw output in
`docs/investigation-minecraftpe-1.26.32.txt`). Nothing was executed, patched or re-signed.

## 1. What was inspected

`minecraftpe_2_1.zip`: an unpacked `.app` for `com.mojang.minecraftpe` 1.26.32 (build 1.26.32.02).

| Fact | Value | Why it matters |
| --- | --- | --- |
| Mach-O type | `MH_EXECUTE`, arm64, PIE | It is a program, not a library. See blocker 1. |
| Platform / minimum OS | iOS, minos 13.0 (Info.plist says 15.0), SDK 26.1 | Runs on iOS 15+; irrelevant to the blockers. |
| Linked frameworks | Metal, MetalKit, OpenGLES, UIKit, GameController, CoreHaptics, AVFoundation, StoreKit, WebKit, Photos, UserNotifications, Security, plus bundled `Xal`, `xsapi-c`, `HttpClient`, `PlayFabMultiplayerFramework_iOS`, `MinecraftSwift` | Rendering is OpenGLES/Metal into its own UIKit window. No embedding API. |
| rpath | `@executable_path/Frameworks` | Expects to sit inside its own bundle. |
| Code signature | Present. Identifier `com.mojang.minecraftpe`, **Team ID `HR992ZEAE6`** | Signed by Mojang's team, not by whoever installs AETHER. |
| Entitlements | `application-identifier`, `com.apple.developer.team-identifier`, `keychain-access-groups` (`HR992ZEAE6.com.microsoft.xal`, `.sso`, `.oneauth`, ...), `aps-environment`, `networking.multicast`, `pass-type-identifiers` | Tied to Mojang's team and provisioning. Xbox sign-in, push and multiplayer discovery depend on them. |
| FairPlay | `LC_ENCRYPTION_INFO_64 cryptid=0` | See section 3. |
| Lifecycle | `NSMainNibFile`, `UILaunchStoryboardName`, owns `UIApplicationMain` | It expects to be the process's application, window owner and delegate. |
| Bundled dylibs | 5 frameworks, all `MH_DYLIB`, all signed by the same team | Loadable only by an app signed by that same team. |

## 2. Exact technical blockers

1. **`dlopen` refuses executables.** dyld loads `MH_DYLIB` and `MH_BUNDLE` images. `minecraftpe` is `MH_EXECUTE`, so loading it into another process fails no matter how it is signed. There is no supported API to "run another app's main binary inside my process".
2. **Code-signing / library validation.** iOS maps executable pages only if they are signed by a trusted identity, and an app may only load additional code signed with its own team. The Minecraft binary and its five frameworks carry Mojang's team ID. AETHER, built by you, has a different team. Changing that means stripping or replacing the signature, which is a code-signing bypass and is out of scope.
3. **DRM.** The copy supplied has `cryptid=0`, meaning its FairPlay layer has already been removed. Removing it is itself a DRM circumvention step, so AETHER does not build on that copy, and the conclusions here do not depend on it: blockers 1, 2, 4 and 5 hold for a legitimately obtained binary too.
4. **Entitlements.** `application-identifier` and the Keychain access groups are granted per provisioning profile. AETHER cannot hold Mojang's identifiers, so even a hypothetically loaded game would lose Xbox/Microsoft sign-in (`com.microsoft.xal`), push and its Keychain data.
5. **No embedding or overlay surface.** iOS has no mechanism for one app to host another app's UI or draw above it (no system overlay window, no app extension that hosts a foreign app, Picture-in-Picture is video-only). `UIApplication` is a singleton per process, and Minecraft's startup assumes it owns it.
6. **No camera integration point.** The camera/FOV lives inside Minecraft's private C++ state. The binary exports no public API for it. Reaching it would need memory patching or function hooking inside the running game, which is injection, not an integration.

Consequences for the zoom button: the button can be built, but **drawing it over real Minecraft gameplay is impossible** (blocker 5), and **changing the real camera is impossible** (blocker 6). The prototype below is therefore an overlay test harness, and it reports "not applied" when no camera backend exists.

## 3. Legitimate alternatives

| Option | Status |
| --- | --- |
| Launcher + hand-off (current): open the installed app via `minecraft://`, deliver content via Open In | Works. This is what AETHER does. |
| Mojang/Microsoft partnership or SDK that exposes an embeddable runtime or camera API | None is public. This is the only route to the original goal, and it requires their agreement. |
| In-game camera control through Minecraft's own supported extension surface (Add-ons / Script API; the `/camera` command family) | The only supported way to affect the real camera. It is a behavior pack, which you excluded for the zoom feature, so it is documented here but not implemented. Check Microsoft's current docs for which FOV controls exist in your target version. |
| Run on a jailbroken or developer-modified device with its own tooling | Not stock iOS, not authorised, not part of AETHER. |
| Minecraft Bedrock on desktop / Android with their supported mod and launcher ecosystems | Different platform. |

## 4. What AETHER 2.0 implements because of this

- A static **Runtime Investigation** screen that reports the same facts (file type, signature, team, entitlements, encryption flag, linked libraries) for any binary you import, and derives the blockers from them rather than hard-coding a verdict.
- Version records are **metadata + isolated AETHER storage**, not installations. Only the App Store copy can launch, and nothing claims otherwise.
- Client features are a real feature manager with persisted configuration, but every in-game feature is labelled **Requires runtime integration (blocked)**.
- The zoom button is a real, configurable, draggable control with a `CameraBackend` seam. The only backend shipped is `UnavailableCameraBackend`.

## 5. Unverified items

- The CurseForge, Microsoft/Xbox OAuth and Download flows follow the documented public APIs but could not be run here (no network, no credentials, no Xcode). They are untested.
- Whether a free Azure app registration is accepted for the `XboxLive.signin` scope can differ by tenant and over time.
