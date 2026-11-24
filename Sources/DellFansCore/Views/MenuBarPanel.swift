import SwiftUI
import AppKit

public struct MenuBarPanel: View {
    @ObservedObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            bannersSection
            sensorSummarySection
            Divider()
            fanControlSection
            Divider()
            footerSection
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.serverDisplayTitle)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectionStatusColor)
                        .frame(width: 8, height: 8)
                    Text(appState.connectionStatus.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if appState.isRefreshing || appState.isTestingConnection || appState.isApplyingFanSpeed {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Banners

    @ViewBuilder
    private var bannersSection: some View {
        if let supportStatus = appState.firmwareInfo?.supportStatus {
            switch supportStatus {
            case .unsupported(let reason):
                bannerView(
                    icon: "exclamationmark.triangle.fill",
                    text: reason,
                    tint: .red
                )
            case .warning(let reason):
                bannerView(
                    icon: "exclamationmark.triangle.fill",
                    text: reason,
                    tint: .orange
                )
            case .supported, .unknown:
                EmptyView()
            }
        }

        if let error = appState.lastError, !error.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.top, 1)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button {
                    appState.clearError()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("关闭错误提示")
            }
            .padding(8)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }

        if let statusMessage = appState.statusMessage, !statusMessage.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func bannerView(icon: String, text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.caption)
                .padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Sensor Quick Summary

    @ViewBuilder
    private var sensorSummarySection: some View {
        if !appState.config.isConfigured {
            VStack(alignment: .leading, spacing: 8) {
                Text("尚未配置 iDRAC 连接信息")
                    .font(.subheadline.weight(.medium))
                Text("请打开详情窗口中的“连接设置”填写 iDRAC IP、用户名与密码。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("前往设置…") {
                    openDetailWindow()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "thermometer.medium")
                        .foregroundStyle(.secondary)
                    Text("传感器概览")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if let lastUpdated = appState.lastUpdated {
                        Text(lastUpdated, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                VStack(spacing: 6) {
                    if !appState.sensorSummary.cpuTemperatures.isEmpty {
                        ForEach(appState.sensorSummary.cpuTemperatures) { cpu in
                            metricRow(
                                label: cpu.label,
                                value: "\(Int(cpu.value.rounded())) °C",
                                icon: "cpu"
                            )
                        }
                    } else if let inlet = appState.sensorSummary.inletTemperature {
                        metricRow(
                            label: "进风口温度",
                            value: "\(Int(inlet.rounded())) °C",
                            icon: "thermometer.medium"
                        )
                    } else if let highest = appState.sensorSummary.highestTemperature {
                        metricRow(
                            label: "最高温度",
                            value: "\(Int(highest.rounded())) °C",
                            icon: "thermometer.medium"
                        )
                    } else {
                        metricRow(
                            label: "温度",
                            value: "-- °C",
                            icon: "thermometer.medium"
                        )
                    }

                    metricRow(
                        label: "平均风扇转速",
                        value: appState.sensorSummary.averageFanRPM.map { "\($0) RPM" } ?? "-- RPM",
                        icon: "fanblades.fill"
                    )

                    metricRow(
                        label: "整机功耗",
                        value: appState.sensorSummary.powerWatts.map { "\(Int($0.rounded())) W" } ?? "-- W",
                        icon: "bolt.fill"
                    )
                }
            }
        }
    }

    private func metricRow(label: String, value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
    }

    // MARK: - Fan Control

    private var fanControlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("风扇控制")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(appState.fanControlMode.displayText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(fanModeTextColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(fanModeBadgeColor, in: Capsule())
                    .help(fanModeHelpText)
            }

            HStack(spacing: 8) {
                Text("转速")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { appState.fanSpeedPercent },
                        set: { appState.fanSpeedPercent = $0.rounded() }
                    ),
                    in: 5...100
                )
                .disabled(!appState.config.isConfigured || appState.isApplyingFanSpeed)
                Text("\(Int(appState.fanSpeedPercent))%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)
            }

            if appState.fanSpeedPercent < 20 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption2)
                    Text("转速低于 20% 存在过热风险，请留意温度")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task { await appState.applyFanSpeed() }
                } label: {
                    Text("应用")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isFanActionDisabled)

                Button {
                    Task { await appState.restoreAutoFanControl() }
                } label: {
                    Text("恢复自动")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isFanActionDisabled)
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 8) {
            Button("打开详情…") {
                openDetailWindow()
            }
            .buttonStyle(.borderless)
            .font(.caption)

            Spacer()

            Button {
                appState.openWebConsole()
            } label: {
                Image(systemName: "globe")
            }
            .buttonStyle(.borderless)
            .help("打开 iDRAC 网页控制台")
            .disabled(!appState.config.isConfigured)

            Button {
                Task { await appState.refreshSensors() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("立即刷新传感器")
            .disabled(!appState.config.isConfigured || appState.isRefreshing)

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var isFanActionDisabled: Bool {
        appState.isApplyingFanSpeed || appState.isTestingConnection || !appState.config.isConfigured
    }

    private var connectionStatusColor: Color {
        switch appState.connectionStatus {
        case .online:
            return .green
        case .offline:
            return .red
        case .connecting:
            return .orange
        case .unconfigured, .idle:
            return .gray
        }
    }

    private var fanModeTextColor: Color {
        switch appState.fanControlMode {
        case .unknown:
            return .secondary
        case .automatic:
            return .green
        case .manual:
            return .accentColor
        }
    }

    private var fanModeBadgeColor: Color {
        switch appState.fanControlMode {
        case .unknown:
            return Color.secondary.opacity(0.12)
        case .automatic:
            return Color.green.opacity(0.14)
        case .manual:
            return Color.accentColor.opacity(0.14)
        }
    }

    private var fanModeHelpText: String {
        switch appState.fanControlMode {
        case .unknown:
            return "Dell IPMI 协议不支持反向读取当前 PWM 百分比；点击「应用」或「恢复自动」后将记录并保持当前状态。"
        case .automatic, .manual:
            return "记录自本应用上次下发的风扇控制状态（Dell IPMI 不支持从 iDRAC 反向读取 PWM 百分比）。"
        }
    }

    private func openDetailWindow() {
        openWindow(id: "detail")
        NSApp.activate(ignoringOtherApps: true)
    }
}
