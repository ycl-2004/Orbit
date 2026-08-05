<p align="center">
  <img src="Orbit/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" alt="Orbit logo" width="144" height="144">
</p>

<h1 align="center">Orbit</h1>

<p align="center">
  <strong>面向 macOS 的环形应用切换器与文件中转工具。</strong>
</p>

<p align="center">
  <a href="README.md">English</a> · 简体中文
</p>

<p align="center">
  <a href="https://github.com/ycl-2004/Orbit/releases/latest/download/Orbit-macOS.zip"><strong>下载 Orbit for macOS</strong></a>
</p>

Orbit 是一个原生菜单栏工具：把正在运行的应用环绕在鼠标附近，
让你不用离开当前工作流就能切换、管理应用并分享文件。所有数据都在本机处理。

## 关于 Orbit

Orbit 是一个独立的原生 macOS 项目，围绕环形、手势优先的工作流打造。
本仓库包含：

- 完整的 SwiftUI/AppKit 源码、资源、测试和共享 Xcode 工程。
- 使用 `app.orbit.local` 作为可替换的 bundle identifier。
- 不包含开发者 Team ID、签名证书或机器专属的 Xcode 状态文件。
- 默认提供英文 README，并单独提供这份简体中文 README。
- App 默认使用英文界面，同时保留简体中文、繁体中文及其他本地化资源。

## 下载

[下载最新版 Orbit for macOS](https://github.com/ycl-2004/Orbit/releases/latest/download/Orbit-macOS.zip)。
需要 macOS 26.0 或更高版本。解压后将 `Orbit.app` 移到 `/Applications`，
然后打开应用。

下载包采用 ad-hoc 签名，尚未经过 Apple 公证。如果 macOS 阻止首次启动，
请按住 Control 点按 `Orbit.app`，选择**打开**并确认。如果没有该选项，请运行：

```bash
xattr -dr com.apple.quarantine /Applications/Orbit.app
open /Applications/Orbit.app
```

Orbit 会为全局触发键请求辅助功能权限；只有启用窗口预览时才会请求屏幕录制权限。

## 功能

- 长按修饰键呼出环形应用切换器，默认触发键为 Option（⌥）。
- 默认使用方向键导航；可在设置中按需启用字母和数字快捷键。
- 可选的环旁窗口预览：在设置中打开“显示窗口预览”，并授予屏幕录制权限；macOS 授权后需要重启 Orbit。
- 将应用拖到中心目标即可退出，并显示像素消散动画。
- 将文件拖到中心即可 AirDrop；持续停留后可改为移入废纸篓。
- 支持调整触发键、取消选择键、字母/数字快捷键、长按阈值、环出现位置、卡片大小/材质和开机启动。

## 截图

| Orbit 环 | 文件分享 | 文件删除 |
| --- | --- | --- |
| ![Orbit 环](photos/01-orbit-ring.png) | ![文件分享](photos/02-file-share.png) | ![文件删除](photos/03-file-delete.png) |

| 退出应用 | 设置 | 欢迎页 |
| --- | --- | --- |
| ![退出应用](photos/04-app-exit.png) | ![设置](photos/05-settings.png) | ![欢迎页](photos/06-welcome.png) |

这些截图展示了当前 macOS 版本的 Orbit 功能流程。真实 PNG 保存在 `photos/` 中，
README 与仓库内的产品截图保持同步。

| 窗口预览 | 选择具体窗口 |
| --- | --- |
| ![窗口预览](photos/07-window-preview.png) | ![窗口选择](photos/08-window-selection.png) |

## 从源码构建

环境要求：

- macOS 26.0 或更高版本（当前重建 Xcode 工程的部署目标）。
- Xcode 26 或更高版本。
- Accessibility 权限，用于全局修饰键触发。
- 如果启用实时窗口预览，还需要 Screen Recording 权限。

仓库的 **Code → Download ZIP** 下载的是源码树；“下载”章节中的链接则提供可直接
使用的 `.app`。你也可以使用 Xcode（或下面的命令）自行构建；若要在本机正常签名
或分发，请选择自己的 Team，并将本地 Bundle Identifier 改成你账号下的唯一值。
项目没有第三方依赖。

使用 Xcode 打开 `Orbit.xcodeproj`，选择 **My Mac**，然后点击 **Run**。
共享工程不会保存开发者 Team ID。如果 Xcode 要求签名，请选择你自己的 Team，
并把本地 bundle identifier 改成你账号下唯一的标识。

无需签名身份即可验证构建：

```bash
xcodebuild -project Orbit.xcodeproj -scheme Orbit -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/xcode \
  CODE_SIGNING_ALLOWED=NO build
```

运行单元测试：

```bash
xcodebuild -project Orbit.xcodeproj -scheme Orbit -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/xcode \
  CODE_SIGNING_ALLOWED=NO test -only-testing:OrbitTests
```

仓库会排除构建产物、DerivedData、Xcode 用户状态、本地环境文件、密钥、日志和本地工作流状态。
源码、资源、测试、工程文件、workspace 数据和公开文档都会保留在 Git 中。

## 使用方式

- 长按触发键，在鼠标附近打开 Orbit。
- 悬停或点击卡片进行选择；松开触发键或按 Enter 确认。
- 按 Escape 或点击中心取消。
- 默认使用方向键（以及 Tab）导航应用；可在设置中启用数字键 `1`–`9` 或首字母匹配作为额外快捷键。
- 启用窗口预览且应用有多个窗口时，使用左/右方向键选择窗口；松开触发键或按 Enter 打开它。
- 按取消选择键（默认 Shift）清除高亮；随后松开触发键会关闭 Orbit 且不切换应用。
- 将应用卡片拖到中心并释放即可退出应用。
- Orbit 打开后，把文件拖到中心目标并立即松手会触发 AirDrop；在中心停留 0.9 秒，目标变成废纸篓后再松手，会把文件移入 macOS 废纸篓。文件处理完成前 Orbit 会保持打开。
- 点击菜单栏图标可以打开设置、权限页面或退出应用。

## 项目结构

- `Orbit/` — 应用源码、配置、资源和 asset catalog。
- `OrbitTests/` — 交互与选择逻辑的单元测试。
- `OrbitUITests/` — UI 测试目标。
- `Orbit.xcodeproj/` — 共享 Xcode 工程和 workspace 数据。
- `photos/` — README 截图和辅助图片。
- `docs/decisions/` — 产品与工程决策记录。

## 许可证

编译后的 App 可供个人免费、非商业使用；源码按 [LICENSE](LICENSE) 中的条款
开放查看。

## 链接

- [Issues](https://github.com/ycl-2004/Orbit/issues)
- [English README](README.md)
