# VidSniffer 原生浏览器迁移计划

## 重构前架构基线

- 应用主体为 Flutter，浏览器由 `flutter_inappwebview` 提供。
- iOS 原生层目前只负责 Flutter 插件注册和短时后台任务桥接。
- 当前没有原生浏览器模型、原生标签页生命周期管理或 XCTest Target。
- 原工作流依赖 Flutter 工具链生成 Xcode 构建文件。

## 迁移原则

1. 应用只保留 Swift + UIKit；Flutter 源码、插件注册、Pods 和构建脚本全部退出。
2. 普通和无痕标签从创建时就使用不同的 `WKWebsiteDataStore`。
3. 标签切换只移动现有 `WKWebView`，不重建页面；超过资源上限才按最近最少使用策略休眠。
4. 永久用户文件、应用状态、缓存分别使用 Documents、Application Support 和 Caches。
5. 不使用定时器轮询 WKWebView；页面状态由 KVO 和 delegate 推送。
6. 每阶段保持可编译、提交独立 Commit，并明确真机未验证项目。

## 阶段

### 阶段 1：核心模型

- 建立 `BrowserTab`、`BrowserTabManager` 和会话快照。
- 建立浏览器控制器、地址栏、工具栏和标签切换器的原生边界。
- 建立历史、书签、网站数据和下载协调器的单一职责边界。
- UIKit 的 `AppDelegate` 和 `BrowserViewController` 直接成为应用启动入口。

### 阶段 2：浏览与多标签

- 原生地址栏、工具栏和多标签页成为可交互主流程。
- 完整实现 `WKNavigationDelegate`、`WKUIDelegate`、KVO、查找和错误恢复。

### 阶段 3：个人浏览数据

- 使用一套可靠持久化方案承载书签、历史和会话。
- 增加无痕标签隔离、恢复策略和最近关闭标签。

### 阶段 4：系统下载

- 使用 `WKDownload`、后台 `URLSession`、持久化任务和 resume data。
- 只保留一套原生下载任务仓库，避免多套任务状态长期并存。

### 阶段 5：资料库与播放器

- UUID 文件模型、文件夹、多选、移动/复制/导出。
- AVPlayer、画中画、AirPlay、字幕、音轨和播放进度。

### 阶段 6：隐私与设置

- `WKContentRuleListStore`、网站数据、权限和完整设置页。

### 阶段 7：质量与交付

- 性能审计、单元测试、UI 测试、手动测试清单和 CI 工件。

## 阶段完成定义

每一阶段必须同时具备：修改清单、完成/未完成说明、静态检查、Xcode
编译、可执行测试结果、独立 Commit，以及未签名 IPA（需要交付时）。
