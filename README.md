# Afterimage

A tiny macOS menu-bar app that adds an **Afterimage** virtual camera. Pick it once in Zoom, then switch between your live webcam and a looping clip of yourself without Zoom ever changing cameras.

- **Live**: passes your real webcam through.
- **Loop**: plays today's clip on repeat. Clips are saved as forward-then-reverse "ping-pong" loops, so there's no visible jump.
- **Record Loop**: records 10 s from your webcam and builds the loop. Each new loop replaces the previous one, so only one file is ever kept.
- The real webcam only runs while some app is actually using Afterimage.

## Build & install

Requires Xcode signed in to the team in `project.yml` (Camera Extensions need a paid developer team).

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Afterimage.xcodeproj -scheme Afterimage -configuration Release -derivedDataPath build -allowProvisioningUpdates build
cp -R build/Build/Products/Release/Afterimage.app /Applications/
open /Applications/Afterimage.app
```

The first launch asks you to approve the camera in **System Settings → General → Login Items & Extensions → Camera Extensions**. Then choose **Afterimage** under Zoom → Settings → Video → Camera. If Zoom (or any video app) was already open, quit it completely and reopen it first: apps only look for cameras when they start.

Loops are stored in the app's sandbox container, under `~/Library/Containers/com.leohanon.Afterimage/`.

## License

The code is released under the [MIT License](LICENSE). The Afterimage name and app icon are not covered by it: if you publish your own build, please give it a different name and icon.

