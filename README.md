# AI 听书

Flutter iOS AI 听书 App，支持导入 TXT、自动章节识别、AI TTS、后台播放、锁屏控制、播放进度保存，以及 Codemagic 生成未签名 IPA。

## 本地运行

```bash
flutter pub get
flutter run
```

## Codemagic 构建

`codemagic.yaml` 会执行：

```bash
flutter build ios --release --no-codesign
```

随后把 `Runner.app` 打包到：

```text
build/ios/ipa/unsigned.ipa
```

下载该 artifact 后需要你自行签名再安装。

