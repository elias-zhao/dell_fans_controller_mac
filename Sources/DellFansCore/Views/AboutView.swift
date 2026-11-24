import SwiftUI

public struct AboutView: View {
    @ObservedObject private var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                compatibilityCard
                safetyWarningCard
                ipmitoolCard
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
        }
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "fanblades.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
                .frame(width: 52, height: 52)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Dell Fans Controller")
                        .font(.title2.weight(.semibold))
                    Text("v1.0.0")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                Text("适用于 macOS 菜单栏的 Dell PowerEdge 服务器 iDRAC 风扇调速与传感器监控工具。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var compatibilityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("支持的 iDRAC 平台与固件", systemImage: "cpu")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                platformRow(
                    platform: "iDRAC 6 / 7 / 8",
                    status: "✅ 支持",
                    detail: "支持手动固定风扇转速与恢复自动调速",
                    tint: .green
                )
                Divider()
                platformRow(
                    platform: "iDRAC 9（≤ 3.30.30.30）",
                    status: "✅ 支持",
                    detail: "支持手动固定风扇转速与恢复自动调速",
                    tint: .green
                )
                Divider()
                platformRow(
                    platform: "iDRAC 9（≥ 3.34.34.34）/ iDRAC 10",
                    status: "❌ 不支持调速",
                    detail: "官方固件已封禁 raw 0x30 0x30 命令，仅支持传感器监控",
                    tint: .red
                )
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func platformRow(platform: String, status: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(platform)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(status)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
        }
    }

    private var safetyWarningCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text("过热安全提示")
                    .font(.subheadline.weight(.semibold))
                Text("手动降低风扇转速（尤其是低于 20%）会减少服务器散热量，可能导致 CPU、内存或 PCIe 设备过热甚至触发保护关机。请在高负载场景下密切观察温度传感器读数。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var ipmitoolCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("ipmitool 依赖状态", systemImage: "gearshape")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                if let path = appState.detectedIPMIToolPath {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("已就绪：\(path)")
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("未检测到 ipmitool，请使用 Homebrew 安装：")
                            .font(.callout)
                    }
                }

                Text("brew install ipmitool")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
