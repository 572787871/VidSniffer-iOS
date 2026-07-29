# VidSniffer iOS

VidSniffer 正在重构为纯 Swift + UIKit iOS 应用。项目不再使用 Flutter。

## 技术栈

- Swift 5
- UIKit
- WebKit / WKWebView
- URLSession / WKDownload（下载阶段逐步接入）
- AVFoundation（播放器阶段逐步接入）

最低系统版本为 iOS 15。

## 当前阶段

阶段 1 正在建立原生浏览器核心模型、标签页生命周期和 UIKit 启动入口。
详细范围与未完成项目见 [NATIVE_BROWSER_MIGRATION_PLAN.md](NATIVE_BROWSER_MIGRATION_PLAN.md)。

## 构建

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

GitHub Actions 会生成未签名 `VidSniffer-Pro-unsigned.ipa`。未签名 IPA
仍需用户自行签名，CI 构建通过不代表已经在真机验证。
