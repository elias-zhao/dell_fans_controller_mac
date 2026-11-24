import SwiftUI

public struct ConnectionSettingsView: View {
    @ObservedObject private var appState: AppState

    @State private var host: String
    @State private var username: String
    @State private var password: String
    @State private var rememberPassword: Bool
    @State private var refreshInterval: Int
    @State private var ipmitoolPath: String

    public init(appState: AppState) {
        self.appState = appState
        _host = State(initialValue: appState.config.host)
        _username = State(initialValue: appState.config.username)
        _password = State(initialValue: appState.password)
        _rememberPassword = State(initialValue: appState.rememberPassword)
        _refreshInterval = State(initialValue: appState.config.refreshIntervalSeconds)
        _ipmitoolPath = State(initialValue: appState.config.ipmitoolPath)
    }

    public var body: some View {
        Form {
            Section("iDRAC 连接") {
                TextField("主机 / IP 地址", text: $host, prompt: Text("例如 192.168.1.100"))
                TextField("用户名", text: $username, prompt: Text("例如 root"))
                SecureField("密码", text: $password, prompt: Text("输入 iDRAC 密码"))
                Toggle("记住密码", isOn: $rememberPassword)
                Text(
                    rememberPassword
                        ? "密码以 AES-GCM 加密保存在本地应用支持目录（0600 仅当前用户可读），升级应用不弹钥匙串授权框。"
                        : "关闭后密码仅保存在内存中，退出应用即清除。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("刷新与工具") {
                Stepper(value: $refreshInterval, in: 3...300, step: 1) {
                    HStack {
                        Text("自动刷新间隔")
                        Spacer()
                        Text("\(refreshInterval) 秒")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                TextField("自定义 ipmitool 路径（可选）", text: $ipmitoolPath, prompt: Text("留空则自动探测"))

                HStack(spacing: 8) {
                    if let detectedPath = appState.detectedIPMIToolPath {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("已检测到 ipmitool：\(detectedPath)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("未检测到 ipmitool，请运行 `brew install ipmitool`")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                HStack(spacing: 10) {
                    Button("保存配置") {
                        saveSettings()
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        saveSettings()
                        Task { await appState.testConnection() }
                    } label: {
                        HStack(spacing: 6) {
                            if appState.isTestingConnection {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("测试连接")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.isTestingConnection)

                    Spacer()

                    Button {
                        appState.openWebConsole()
                    } label: {
                        Label("打开 iDRAC 网页控制台", systemImage: "globe")
                    }
                    .buttonStyle(.bordered)
                    .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let statusMessage = appState.statusMessage, !statusMessage.isEmpty {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text(statusMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let error = appState.lastError, !error.isEmpty {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("关闭") {
                            appState.clearError()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            }

            if let firmware = appState.firmwareInfo {
                Section("固件与兼容性") {
                    LabeledContent("固件版本", value: firmware.firmwareRevision)
                    if let manufacturer = firmware.manufacturerName, !manufacturer.isEmpty {
                        LabeledContent("厂商", value: manufacturer)
                    }
                    if let model = firmware.serverModel, !model.isEmpty {
                        LabeledContent("服务器型号", value: model)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        supportIcon(for: firmware.supportStatus)
                        Text(firmware.supportStatus.message)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func saveSettings() {
        appState.saveConnectionSettings(
            host: host,
            username: username,
            password: password,
            refreshInterval: refreshInterval,
            ipmitoolPath: ipmitoolPath,
            rememberPassword: rememberPassword
        )
    }

    @ViewBuilder
    private func supportIcon(for status: FirmwareSupportStatus) -> some View {
        switch status {
        case .supported:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .unsupported:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .unknown:
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
    }
}
