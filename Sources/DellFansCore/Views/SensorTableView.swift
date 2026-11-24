import SwiftUI

public struct SensorTableView: View {
    @ObservedObject private var appState: AppState
    @State private var selectedCategory: SensorCategory? = nil
    @State private var searchText: String = ""

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            bannersSection
            filterBar
            Divider()
            tableContent
            Divider()
            bottomControlBar
        }
    }

    // MARK: - Banners

    @ViewBuilder
    private var bannersSection: some View {
        let hasFirmwareBanner: Bool = {
            switch appState.firmwareInfo?.supportStatus {
            case .unsupported, .warning:
                return true
            default:
                return false
            }
        }()
        let hasErrorBanner = !(appState.lastError?.isEmpty ?? true)

        if hasFirmwareBanner || hasErrorBanner {
            VStack(spacing: 8) {
                if let supportStatus = appState.firmwareInfo?.supportStatus {
                    switch supportStatus {
                    case .unsupported(let reason):
                        bannerRow(icon: "exclamationmark.triangle.fill", text: reason, tint: .red)
                    case .warning(let reason):
                        bannerRow(icon: "exclamationmark.triangle.fill", text: reason, tint: .orange)
                    case .supported, .unknown:
                        EmptyView()
                    }
                }

                if let error = appState.lastError, !error.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button {
                            appState.clearError()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("关闭错误提示")
                    }
                    .padding(10)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding([.horizontal, .top], 12)
            .padding(.bottom, 4)
        }
    }

    private func bannerRow(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("分类", selection: $selectedCategory) {
                Text("全部").tag(SensorCategory?.none)
                ForEach(SensorCategory.allCases) { category in
                    Text(category.rawValue).tag(SensorCategory?.some(category))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 160)

            TextField("搜索传感器名称…", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if selectedCategory != nil || !searchText.isEmpty {
                Button("清除") {
                    selectedCategory = nil
                    searchText = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Table / Empty State

    @ViewBuilder
    private var tableContent: some View {
        if !appState.config.isConfigured {
            emptyStateView(
                icon: "gearshape",
                title: "尚未配置 iDRAC 连接",
                subtitle: "请先在左侧“连接设置”中填写 iDRAC 地址、用户名与密码。"
            )
        } else if appState.sensors.isEmpty {
            emptyStateView(
                icon: "thermometer.medium",
                title: appState.isRefreshing ? "正在读取传感器数据…" : "暂无传感器数据",
                subtitle: appState.isRefreshing ? "正在通过 ipmitool 查询 iDRAC 传感器。" : "点击右下角“刷新”按钮获取服务器传感器信息。"
            )
        } else if filteredSensors.isEmpty {
            emptyStateView(
                icon: "magnifyingglass",
                title: "没有匹配的传感器",
                subtitle: "请尝试更改分类筛选或清空搜索关键词。"
            )
        } else {
            Table(filteredSensors) {
                TableColumn("名称") { sensor in
                    Text(sensor.displayName)
                }
                TableColumn("数值") { sensor in
                    Text(sensor.formattedValue)
                        .monospacedDigit()
                }
                TableColumn("单位") { sensor in
                    Text(sensor.unit.isEmpty ? "—" : sensor.unit)
                        .foregroundStyle(.secondary)
                }
                TableColumn("状态") { sensor in
                    Text(sensor.status.displayText)
                        .foregroundStyle(statusColor(for: sensor.status))
                }
            }
        }
    }

    private func emptyStateView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Bottom Bar

    private var bottomControlBar: some View {
        HStack(spacing: 12) {
            if let lastUpdated = appState.lastUpdated {
                HStack(spacing: 4) {
                    Text("上次更新：")
                        .foregroundStyle(.secondary)
                    Text(lastUpdated, style: .time)
                        .monospacedDigit()
                }
                .font(.caption)
            } else {
                Text("尚未刷新")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle(
                "自动刷新",
                isOn: Binding(
                    get: { appState.autoRefreshEnabled },
                    set: { appState.setAutoRefresh(enabled: $0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)

            Stepper(
                value: Binding(
                    get: { appState.config.refreshIntervalSeconds },
                    set: { appState.updateRefreshInterval($0) }
                ),
                in: 3...300,
                step: 1
            ) {
                Text("间隔 \(appState.config.refreshIntervalSeconds) 秒")
                    .font(.caption)
                    .monospacedDigit()
            }
            .controlSize(.small)

            Button {
                Task { await appState.refreshSensors() }
            } label: {
                HStack(spacing: 4) {
                    if appState.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("刷新")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!appState.config.isConfigured || appState.isRefreshing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var filteredSensors: [SensorReading] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return appState.sensors.filter { sensor in
            if let selectedCategory, sensor.category != selectedCategory {
                return false
            }
            if !query.isEmpty {
                let matchesDisplay = sensor.displayName.localizedCaseInsensitiveContains(query)
                let matchesRaw = sensor.name.localizedCaseInsensitiveContains(query)
                return matchesDisplay || matchesRaw
            }
            return true
        }
    }

    private func statusColor(for status: SensorStatus) -> Color {
        switch status {
        case .ok:
            return .green
        case .nonCritical:
            return .orange
        case .critical, .nonRecoverable:
            return .red
        case .notAvailable, .unknown:
            return .secondary
        }
    }
}
