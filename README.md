# Pixel Workspace

Native macOS MVP for a low-resource, 45° isometric office view of running apps. Each character represents an observed running app process; the app does not infer what a process is doing. Department assignment is a transparent bundle-ID/name rule with a persistent manual override.

The office view uses locally installed Antahonist isometric furniture, CC0 character sheets, and SpriteKit lighting. Sources and licenses are listed in [`docs/asset-credits.md`](docs/asset-credits.md).

## Run

Requirements: macOS 13 or newer and Xcode. Download the free [Office Desk 3D Pixel Art Kit](https://antahonist.itch.io/free-office-desk-3d-pixel-art-kit), then install its assets locally:

```sh
./scripts/install-office-art.sh /path/to/36-office-desk-3d-pixel-art-kit.zip
```

Open `PixelWorkspace.xcodeproj`, select the `PixelWorkspace` scheme, and run the macOS app. The vendor license permits these images in compiled apps but forbids redistributing the PNGs, so `Resources/Iso*.png` are intentionally absent from this Git repository. Run the install script after every fresh clone. The current Xcode project requires these files at build time.

The app uses AppKit for the window/menu bar and SpriteKit for the lightweight office scene. Process inventory comes from `NSWorkspace.runningApplications`; frontmost state comes from `frontmostApplication`. CPU and resident memory use public `libproc` process APIs. If macOS denies access or a process exits during sampling, the corresponding value is shown as unavailable (`—`); no synthetic values are substituted. CPU is unavailable for the first sample because a delta is needed.

## Local network pairing

On each Mac, enable “局域网同步”. Generate a key on one device, then copy the same key into the other device. A 32-byte random key is shown as hex. Bonjour advertises `_pixelworkspace._tcp`; the peer browser connects on the local network, and the payload uses AES-GCM authenticated encryption. Pairing is opt-in and no cloud relay is used. Keep the pairing key private. The synchronized snapshot contains device name, app display name, bundle ID, PID, department, frontmost flag, CPU, memory, and capture time. It excludes window titles, documents, URLs, keystrokes, and screen content.

This MVP uses a shared key entered by the user rather than an identity certificate or per-peer revocation UI. Re-enter a fresh key on both Macs to rotate it. Network availability depends on macOS Local Network permission and the network allowing Bonjour/peer traffic. Windows support is only a protocol direction: use the same versioned JSON message model and AES-GCM envelope, with platform-specific discovery and process collection.

## Limits

- App processes are obtained through `NSWorkspace` and restricted to regular GUI apps; background agents and helper processes are not shown.
- CPU values are per-process percentages capped at 100%, derived from process CPU time over the 2.5-second sampling interval. Memory is resident physical memory.
- Department heuristics are intentionally simple and inspect only bundle IDs and app names. They do not use AI or claim semantic activity.
- Remote records are snapshots; this build does not persist a remote event history.
- There is no signed/notarized distribution package yet. Run from Xcode/SwiftPM for this MVP.

## Verify

```sh
xcodebuild -project PixelWorkspace.xcodeproj -scheme PixelWorkspace -configuration Debug build
xcodebuild -project PixelWorkspace.xcodeproj -scheme PixelWorkspace -configuration Debug test
```
