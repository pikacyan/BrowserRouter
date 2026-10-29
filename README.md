# BrowserRouter · 链接分流

一个轻量的原生 macOS 菜单栏应用，按**发起链接的应用**选择浏览器。
例如：邮件 → Safari、工作应用 → Chrome，其他来源 → 默认浏览器。

使用 Swift、SwiftUI 和 AppKit 编写，无第三方依赖、无服务器、无遥测。
当前界面为简体中文，发布包支持 Apple Silicon Mac、macOS 13 及更新版本。

## 使用

1. 解压发布包，将 `BrowserRouter.app` 拖到“应用程序”，然后打开。
2. 选择“默认打开方式”，用于未匹配规则或无法识别来源的链接。
3. 在“按来源应用分配”中点击“添加应用”，选择来源应用及目标浏览器。
4. 点击“设为默认浏览器”，在系统提示中确认。
5. 在来源应用中点击网页链接；通过菜单栏的分叉箭头可重新打开设置。

启用“每次打开链接时，让我选择浏览器”会优先显示选择弹窗，覆盖自动规则。
规则可启用、禁用和删除。目标浏览器不可用或打开失败时，链接会保留在“未打开的链接”中，
可以重试、换浏览器、复制完整链接或手动移除。重试成功后自动移除失败记录，取消更换浏览器不会丢掉原失败链接。
失败链接仅保留在内存中，退出应用后清除。

“最近一次来源与规则”显示实际来源应用、命中或回退原因、打开目标与结果。
可从最近识别到的来源直接添加规则；若已有规则，请直接修改对应条目。辅助进程会按实际识别到的标识显示。

发布包使用 ad-hoc 签名，未经过 Apple 开发者公证，macOS 可能阻止首次打开。
请确认下载来源；也可以按下文从源码自行构建。

## 已知限制

- 只处理交给系统默认浏览器的 HTTP / HTTPS 链接。应用内置网页或强制指定浏览器的链接无法接管。
- 部分应用通过辅助进程打开链接，可能无法识别成主应用，此时使用默认浏览器。
- 按来源应用匹配，不按网址域名、当前前台应用或正在运行的应用列表匹配。
- 选择整个浏览器，暂不支持 Chrome / Safari 的不同用户资料。
- 当前构建脚本仅生成 arm64 应用，不包含 Intel 版本。

## 本地数据

设置保存在 `~/Library/Application Support/BrowserRouter/preferences.json`。
应用不将浏览历史写入磁盘；来源诊断和待重试的失败链接仅存在于本次运行的内存中。
诊断界面显示来源、目标和域名；“复制链接”由用户点击后将完整 URL 写入剪贴板。

配置带有版本号，兼容 v1.0 的无版本配置。读取损坏配置时，先在同目录生成
`preferences-backup-<UUID>.json` 备份，再使用默认设置。备份失败或检测到更新版本的配置时，
本次运行禁止保存，避免覆盖原文件。窗口会保留恢复提示，并提供“打开配置文件夹”。
修复文件或升级应用后需重启，重新加载配置。

支持导入和导出 JSON 设置。导入前先验证内容，再备份现有配置；无效导入不会替换当前设置。
备份保留在本机，不自动上传或清理。
完整链接交给用户选定的本机浏览器打开，应用自身不向服务器上传链接。

## 构建与测试

在 macOS 上安装 Apple Command Line Tools（`xcode-select --install`），然后在源码目录执行：

```sh
bash test.sh
bash build.sh
open build/BrowserRouter.app
```

产物为 `build/BrowserRouter.app`。也可使用 `bash build.sh /absolute/output/directory` 指定输出目录。
构建脚本使用 Swift 5 语言模式，最低部署目标为 macOS 13，并执行 ad-hoc 签名。

`test.sh` 检查来源匹配、默认回退、禁用规则、手动选择优先级、无效链接、防止转发给自身、配置迁移与备份、导入导出、失败重试和串行队列。
GitHub Actions 在推送和 Pull Request 时自动运行这些测试、编译应用并检查签名和应用元数据。
测试不修改系统默认浏览器。真实应用的来源识别及系统默认浏览器确认流程需要人工验证。

## 实现

- `Sources/Routing.swift`：规则、设置数据结构和路由决策。
- `Sources/main.swift`：设置界面、菜单栏、URL 事件处理和浏览器转发。
- `Sources/Configuration.swift`：配置迁移、备份保护和导入导出。
- `Sources/Delivery.swift`：串行链接队列与失败重试状态。
- `Tests/main.swift`：路由、配置文件及队列的回归测试。
- `Info.plist`：HTTP / HTTPS 处理器注册和应用元数据。

收到 macOS URL Apple Event 后，应用读取发送者进程 ID，再获取其 bundle identifier 匹配规则。
无法识别时回退到默认浏览器，不猜测前台应用。

## 停用

先在 macOS“系统设置 → 桌面与程序坞 → 默认网页浏览器”切回其他浏览器，再退出并移除应用。
如需清除设置，可删除上述 `BrowserRouter` 设置文件夹。

## 贡献与许可证

欢迎提交 Issue 和 Pull Request。报告问题时请提供 macOS 版本、来源应用及预期行为，
并使用不含个人信息或令牌的示例网址。提交前请运行 `bash test.sh` 和 `bash build.sh`。

采用 [MIT 许可证](LICENSE)。

---

BrowserRouter is a small native macOS menu bar app that routes web links to browsers
based on the source application. Built with Swift, SwiftUI and AppKit, with no
third-party dependencies or telemetry. The current UI is in Simplified Chinese.
Requires macOS 13+ on Apple Silicon. Run `bash test.sh` and `bash build.sh` to build
from source. Releases are ad-hoc signed and not notarized by Apple.
