# Local FFmpeg Binary

Place the offline enterprise/self-signed FFmpeg executable here:

```text
ios/FFmpeg/bin/ffmpeg
```

The executable is copied into `Runner.app` as a bundled resource and invoked by `Runner/AppDelegate.swift` through:

```text
/bin/sh -c "<bundled ffmpeg path> <arguments from Flutter>"
```

No CocoaPods video-processing pod, Flutter video-processing plugin API, xcframework API, GitHub download, or CDN dependency is used.

The checked-in `bin/ffmpeg` is a placeholder so CI can validate project wiring. Replace it with a real signed iOS FFmpeg executable before producing an enterprise IPA that performs m3u8/ts conversion.
