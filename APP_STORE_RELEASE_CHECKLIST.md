# App Store 正式发布清单

本项目的 GitHub Actions 产物是用于验证和后续签名的未签名 IPA，不是可直接
提交 App Store Connect 的发行归档。

## 已自动验证

- Release 配置能够完成原生 arm64 构建。
- AppIcon 包含 iPhone、iPad 和 1024×1024 App Store 图标。
- `Assets.car` 已进入应用包。
- `PrivacyInfo.xcprivacy` 格式有效并进入应用包。
- 隐私清单声明本地设置和应用容器文件元数据用途。
- 单元测试和可稳定执行的 UI 测试通过。
- 未签名 IPA 能通过 ZIP 完整性校验。

## 提交前必须由发布账号完成

- 在 Xcode 设置真实 Apple Developer Team、发行证书和 App Store 描述文件。
- 确认 Bundle ID `com.vidsniffer.pro` 已在开发者后台注册且归发布者所有。
- 使用 Product > Archive 生成签名归档，并执行 Validate App。
- 在 App Store Connect 填写隐私政策公开网址、支持网址和使用条款。
- 根据实际服务器、账号系统和第三方服务填写 App Privacy 营养标签。
- 准备不同设备尺寸的真实 App Store 截图、描述、关键词和年龄分级。
- 检查下载功能只用于用户有权保存的内容，并准备审核说明和演示路径。
- 若接入账号注册，提供应用内账号删除；若接入第三方登录，按审核规则提供
  Sign in with Apple。
- 在真机验证签名安装、后台下载、画中画、后台音频、AirPlay、分享、文件导出、
  摄像头、麦克风、网络切换、低存储空间、内存压力和长时间下载。

## 禁止做法

- 不通过填充无用图片、视频或随机文件来虚增安装包体积。
- 不把开发证书、私钥、App Store Connect 密钥或账号写入仓库和 Actions 日志。
- 未通过真机及 App Store Connect Validate 前，不标记为“可正式上线”。
