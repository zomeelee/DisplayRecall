# DisplayRecall

[English](README.md)

DisplayRecall 是一个本地运行的 macOS 菜单栏工具。它保存 Mac 内置屏与一台外接显示器上的普通窗口布局，并在另一台外接显示器接入后，按屏幕可用区域的比例自动恢复窗口。

## 主要功能

- 支持当前桌面中的普通、非最小化、非全屏窗口。
- 在显示器接入、分辨率变化或睡眠唤醒后自动恢复，并重试较晚才向辅助功能接口暴露窗口的 App。
- 保存公开的 Core Graphics 运行时窗口 ID，在 ID 仍然有效时维持多个相似窗口的左右顺序。
- 适配菜单栏、左侧/右侧/底部 Dock，以及 App 强制采用的最小窗口尺寸。
- 窗口标题和文档地址只保存 SHA-256 摘要，不保存明文。
- 所有数据保存在本机，不访问网络，也不需要屏幕录制权限。
- 只使用公开 macOS API，不使用私有 Spaces API。

具体保存字段参见[隐私说明](PRIVACY.md)。

## 环境要求

- macOS 14 或更高版本
- Xcode 26 或兼容版本
- 运行 App 时授予辅助功能权限
- 只有修改工程结构时才需要 XcodeGen 2.45 或更高版本

仓库已经提交生成后的 `DisplayRecall.xcodeproj`，普通构建和测试不要求安装 XcodeGen。

## 构建与测试

克隆仓库后打开 `DisplayRecall.xcodeproj`，选择你自己的开发团队，然后运行 `DisplayRecall` Scheme。

无签名 CI 测试：

```sh
xcodebuild \
  -project DisplayRecall.xcodeproj \
  -scheme DisplayRecall \
  -configuration Debug \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

修改 `project.yml` 后重新生成并提交 Xcode 工程：

```sh
xcodegen generate
```

macOS 会把辅助功能授权与 App 的签名身份绑定。自行构建的版本在签名身份改变后可能需要重新授权；官方版本将使用稳定的 Developer ID 身份。

## 使用方法

1. 连接外接显示器并排好窗口。
2. 点击菜单栏中的 DisplayRecall 图标。
3. 点击“保存当前双屏布局”。
4. 以后接入另一台外接显示器时，DisplayRecall 会按相对位置恢复窗口。

## 本地命令接口

DisplayRecall 0.1.8 起支持本地 URL 命令，供 Codex Skill、快捷指令或其他本机自动化调用：

    open -g "displayrecall://save?request=my-save"
    open -g "displayrecall://restore?request=my-restore"
    open -g "displayrecall://status?request=my-status"

命令会由已经获得辅助功能权限的 DisplayRecall App 执行。结果写入：

    ~/Library/Application Support/com.zomeelee.DisplayRecall/command-status-v1.json

接口不会开放网络端口，也不会绕过 macOS 辅助功能授权。

### 安装 Codex Skill

仓库内包含一个按需控制 DisplayRecall 的 Skill，可安装到个人 Codex Skill 目录：

    mkdir -p ~/.codex/skills
    cp -R skills/displayrecall-window-layout ~/.codex/skills/

之后可调用 `$displayrecall-window-layout` 检查状态、保存当前布局或恢复已保存布局。辅助功能权限和显示器热插拔后的自动恢复仍由原生菜单栏 App 负责。

## 已知限制

- 第一版只支持 Mac 内置屏加一台外接屏。
- macOS 没有公开接口让第三方可靠地把其他 App 的窗口移动到指定 Space，因此只保证当前可访问桌面。
- 系统全屏、最小化、模态窗口及过小的工具窗口会被忽略。
- 少数 App 可能拒绝移动或强制最小窗口尺寸。
- 不会自动启动已经关闭的 App，也不会恢复窗口前后层级。

## 项目原则

- 未经公开设计讨论，不增加遥测或网络访问。
- 不使用私有 macOS API。
- 涉及隐私的改动必须同时补充测试和文档。

贡献方式、安全策略和架构说明分别参见 [CONTRIBUTING.md](CONTRIBUTING.md)、[SECURITY.md](SECURITY.md) 和 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 发布

当前可以从源码构建。只有在使用本项目 Developer ID 签名并完成 Apple 公证后，才会发布官方二进制；第三方未签名构建不代表官方版本。

## 许可证

DisplayRecall 使用 [MIT License](LICENSE)。
