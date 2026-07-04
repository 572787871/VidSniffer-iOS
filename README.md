# VidSniffer Pro

Native iOS video utility app for web video parsing, browser sniffing, m3u8/mp4 download tasks, and local video file management.

## Features

- Native UIKit interface using system background colors and Dynamic Type fonts.
- Larger native UIKit interface with a stronger blue/teal theme and explicit download controls.
- Home parser that scans page source for mp4, m4v, mov, m3u8, and ts media URLs.
- Built-in WKWebView browser with DOM, fetch, XHR, performance, and navigation sniffing.
- Download task screen for detected resources. HLS/m3u8 resources are exported through AVFoundation instead of saving the playlist text directly.
- Local file screen for saved videos and manifests.
- GitHub Actions workflow that builds an unsigned IPA for self-signing.

## Local Run

```bash
open ios/Runner.xcodeproj
```

## iOS Build

```bash
xcodebuild \
  -project ios/Runner.xcodeproj \
  -scheme Runner \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The GitHub Actions workflow packages `Runner.app` into `VidSniffer-Pro-unsigned.ipa` for later signing.
