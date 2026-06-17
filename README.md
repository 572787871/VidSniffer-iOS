# VidSniffer Pro

Flutter iOS video utility app for web video parsing, browser sniffing, m3u8 download tasks, and local video file management.

## Features

- Dark iOS-style interface with glass cards and blue-purple accent lighting.
- Home parser with video result cards and one-tap download actions.
- Built-in browser shell with address bar, navigation controls, and sniffed media download card.
- Download task screen with speed, pause/resume/delete controls, progress bar, and progress ring.
- Local file screen with play, share, delete, and export actions.
- Settings screen for cache, download path, app info, and dark mode.

## Local Run

```bash
flutter pub get
flutter run
```

## iOS Build

```bash
flutter build ios --release --no-codesign
```

The existing Codemagic workflow can package `Runner.app` into an unsigned IPA artifact for later signing.
