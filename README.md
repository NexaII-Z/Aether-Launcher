# TweenSlop

Puppet/tween animator for iOS (SwiftUI, iOS 16+).

## Get the IPA
1. Create a GitHub repo and push this folder to `main`.
2. Open the Actions tab. "Build IPA" runs on every push, or run it manually.
3. When it finishes, download the `TweenSlop-ipa` artifact (a zip containing `TweenSlop.ipa`).
4. Install it with AltStore, Sideloadly or TrollStore. The IPA is unsigned; your sideloading tool signs it.

Change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` if you want a different bundle ID.

## Workflow in the app
1. New project, then Rig tab, then New Body (humanoid: torso, head, arms, legs).
2. Select a part, import its image (Photos or Files).
3. Set Pivot tool: drag to move the pivot (joint) of the selected part. Move Part tool: reposition it.
4. Animate tab: scrub the timeline, rotate/move parts. Children follow their parents. Keys are created automatically.
5. Media tab: FPS, length, canvas size, import audio or MP4 (audio is extracted), import a background video.
