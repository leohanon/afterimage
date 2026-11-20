# LoopCam

A tiny macOS menu-bar app that adds a **LoopCam** virtual camera. Pick it once in Zoom, then switch between your live webcam and a looping clip of yourself without Zoom ever changing cameras.

- **Live**: passes your real webcam through.
- **Loop**: plays today's clip on repeat. Clips are saved as forward-then-reverse "ping-pong" loops, so there's no visible jump.
- **Record Loop**: records 10 s from your webcam and builds the loop. Each new loop replaces the previous one, so only one file is ever kept.
- **⌃⌥⌘L** toggles Live/Loop from anywhere.
- The real webcam only runs while some app is actually using LoopCam.

## Build & install

Requires Xcode signed in to the team in `project.yml` (Camera Extensions need a paid developer team).

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project LoopCam.xcodeproj -scheme LoopCam -configuration Release -derivedDataPath build -allowProvisioningUpdates build
cp -R build/Build/Products/Release/LoopCam.app /Applications/
open /Applications/LoopCam.app
```

The first launch asks you to approve the camera in **System Settings → General → Login Items & Extensions → Camera Extensions**. Then choose **LoopCam** under Zoom → Settings → Video → Camera.

Loops are stored in `~/Library/Application Support/LoopCam/`.
