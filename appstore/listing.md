# Afterimage: App Store listing

Everything to paste into App Store Connect. Screenshots are in `screenshots/` (2880×1800; regenerate from `shot.html?n=1..4` with headless Chrome at 1440×900, scale 2).

## App information

| Field | Value |
|---|---|
| Name | Afterimage: Loop Camera ("Afterimage" alone was taken) |
| Subtitle | Stay on camera while away |
| Bundle ID | com.leohanon.Afterimage |
| SKU | afterimage-mac |
| Primary category | Video |
| Secondary category | Productivity |
| Price | Free |
| Age rating | 4+ (answer "None" to every question) |
| Copyright | 2026 Leonardo Hanon |
| Support URL | https://leohanon.github.io/afterimage/support.html |
| Marketing URL | https://leohanon.github.io/afterimage/ |
| Privacy Policy URL | https://leohanon.github.io/afterimage/privacy.html |
| App Privacy | Data Not Collected |
| Encryption | None (ITSAppUsesNonExemptEncryption = NO is in Info.plist) |

## Promotional text

Need a moment away from a video call? Switch to a looping clip of yourself from the menu bar, then back to live, without ever turning your camera off.

## Description

Afterimage adds a camera to your Mac that shows either your live webcam or a short looping clip of yourself. Choose it once in Zoom, Google Meet, FaceTime, Teams, or any video app, then switch between Live and Loop from the menu bar whenever you need a moment away. The call never sees a camera change.

HOW IT WORKS
1. Record a 10-second loop of yourself from the menu bar.
2. In your video app, choose Afterimage as your camera.
3. Switch between Live and Loop anytime.

TIP
For the most convincing loop, record a new one right before each call, so your lighting, clothes, and background match.

DETAILS
• Smooth loops: your clip plays forward, then backward, so it never jumps.
• Honest webcam light: your real webcam only turns on while a video app is using Afterimage, or while you're recording.
• One loop, kept small: each new recording replaces the last.
• Lives in your menu bar and can open at login.

PRIVATE BY DESIGN
Afterimage has no accounts, no analytics, and never connects to the internet. Your video stays on your Mac.

Free and open source.

## Keywords (100 characters max)

virtual camera,webcam,loop,zoom,meet,teams,video call,meeting,away,break,remote work,facetime

## What's New (version 1.0)

First release.

## App Review notes

Afterimage installs a Camera Extension (CoreMediaIO system extension) that appears as a camera named "Afterimage" in other apps. No account or sign-in is needed.

To test:
1. Open Afterimage. Its icon appears in the menu bar and a settings window opens.
2. macOS asks to approve the camera extension. Click "Approve in System Settings…" in the window, click ⓘ next to Camera Extensions, and turn on Afterimage. Allow webcam access when asked.
3. From the menu bar icon, choose "Record Loop". It records 10 seconds from the webcam and builds the loop.
4. Open FaceTime or Photo Booth and choose "Afterimage" as the camera (in FaceTime: Video menu → Afterimage).
5. From the menu bar icon, switch between "Live" (webcam passthrough) and "Loop" (the recorded clip).

The webcam is only used while another app is streaming from the Afterimage camera, or while recording. Nothing is sent over the network.
