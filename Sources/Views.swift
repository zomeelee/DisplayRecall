import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DisplayRecall")
                        .font(.headline)
                    Text(model.phase.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            Label(model.topologySummary, systemImage: model.hasExternalDisplay ? "display.2" : "laptopcomputer")
                .font(.subheadline)

            if model.permissionGranted {
                Label("辅助功能权限已启用", systemImage: "checkmark.shield.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Label("需要辅助功能权限才能移动窗口", systemImage: "exclamationmark.shield.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    Button("请求辅助功能权限") {
                        model.requestAccessibilityPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("打开辅助功能设置") {
                        model.openAccessibilitySettings()
                    }
                }
            }

            GroupBox("已保存布局") {
                HStack {
                    if let summary = model.snapshotSummary {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(summary.windowCount) 个窗口")
                                .font(.subheadline.weight(.medium))
                            Text(snapshotDescription(summary))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("尚未保存。连接外接显示器并排好窗口后保存一次。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }

            HStack {
                Button("保存当前双屏布局") {
                    model.saveCurrentLayout()
                }
                .disabled(!model.permissionGranted || !model.hasExternalDisplay || model.phase != .idle)

                Button("立即恢复") {
                    model.restoreManually()
                }
                .disabled(!model.permissionGranted || !model.hasExternalDisplay || model.snapshotSummary == nil)
            }

            Toggle("接入外接显示器后自动恢复", isOn: $model.autoRestore)
                .toggleStyle(.switch)

            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Button("刷新") {
                    model.refresh()
                }
                Button("设置…") {
                    openSettings()
                }
                Spacer()
                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 350)
        .onAppear {
            model.refresh()
        }
    }

    private func snapshotDescription(_ summary: SnapshotSummary) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let display = summary.externalDisplayName.map { " · \($0)" } ?? ""
        return formatter.string(from: summary.savedAt) + display
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("自动恢复") {
                Toggle("接入外接显示器后自动恢复", isOn: $model.autoRestore)
                Toggle("DisplayRecall 启动时恢复", isOn: $model.restoreOnLaunch)
                Toggle("Mac 从睡眠中唤醒后恢复", isOn: $model.restoreOnWake)
                Toggle(
                    "登录时启动 DisplayRecall",
                    isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
            }

            Section("权限与数据") {
                LabeledContent("辅助功能") {
                    Text(model.permissionGranted ? "已允许" : "未允许")
                        .foregroundStyle(model.permissionGranted ? .green : .orange)
                }
                HStack {
                    Button("请求辅助功能权限") {
                        model.requestAccessibilityPermission()
                    }
                    Button("打开辅助功能设置") {
                        model.openAccessibilitySettings()
                    }
                    Button("打开本地数据目录") {
                        model.revealDataFolder()
                    }
                }
            }

            Section("第一版限制") {
                Text("仅恢复当前可访问桌面中的普通窗口。系统全屏窗口、最小化窗口、弹窗和模态面板会被忽略；不会启动已经关闭的 App。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 420)
        .onAppear {
            model.refresh()
        }
    }
}
