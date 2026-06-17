# Local FFmpeg Framework

Place the offline enterprise/self-signed FFmpegKit-compatible binary here:

```text
ios/FFmpeg/FFmpeg.xcframework
```

The framework must expose the Swift/Objective-C FFmpegKit API used by `Runner/AppDelegate.swift`:

```swift
FFmpegKit.executeAsync(...)
ReturnCode.isSuccess(...)
```

This directory is referenced by `ios/Podfile` through the local `FFmpeg.podspec`, so `pod install` does not fetch FFmpeg from GitHub, CocoaPods trunk, or any CDN.
