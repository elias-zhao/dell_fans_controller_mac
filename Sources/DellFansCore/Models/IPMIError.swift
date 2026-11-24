import Foundation

public enum IPMIError: LocalizedError, Equatable, Sendable {
    case notConfigured
    case ipmitoolNotFound(searchedPaths: [String])
    case invalidHost(String)
    case invalidFanSpeed(Int)
    case authenticationFailed(detail: String)
    case connectionTimeout(host: String)
    case connectionFailed(host: String, detail: String)
    case manualControlUnsupported(detail: String)
    case commandFailed(exitCode: Int32, stderr: String)
    case parseFailed(detail: String)
    case processLaunchFailed(detail: String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "尚未配置 iDRAC 连接信息"
        case .ipmitoolNotFound:
            return "未找到 ipmitool 命令"
        case .invalidHost(let host):
            return "无效的 iDRAC 地址：\(host)"
        case .invalidFanSpeed(let percent):
            return "风扇转速百分比必须在 0%–100% 之间（当前：\(percent)%）"
        case .authenticationFailed(let detail):
            return "iDRAC 认证失败：\(detail)"
        case .connectionTimeout(let host):
            return "连接 iDRAC（\(host)）超时"
        case .connectionFailed(let host, let detail):
            return "无法连接到 iDRAC（\(host)）：\(detail)"
        case .manualControlUnsupported(let detail):
            return "当前 iDRAC 固件不支持手动风扇调速（\(detail)）"
        case .commandFailed(let exitCode, let stderr):
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return msg.isEmpty ? "ipmitool 执行失败（退出码 \(exitCode)）" : "ipmitool 执行失败：\(msg)"
        case .parseFailed(let detail):
            return "解析 IPMI 输出失败：\(detail)"
        case .processLaunchFailed(let detail):
            return "启动 ipmitool 进程失败：\(detail)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notConfigured:
            return "请在“连接设置”中填写 iDRAC IP、用户名和密码。"
        case .ipmitoolNotFound(let searchedPaths):
            let paths = searchedPaths.joined(separator: ", ")
            return "请运行 `brew install ipmitool` 安装，或在连接设置中指定路径（已查找：\(paths)）。"
        case .invalidHost:
            return "请输入合法的 IP 地址或主机名（不含空格或协议头）。"
        case .invalidFanSpeed:
            return "请将风扇转速滑块调整到合理范围。"
        case .authenticationFailed:
            return "请检查 iDRAC 用户名、密码及 IPMI 用户权限。"
        case .connectionTimeout, .connectionFailed:
            return "请检查网络连通性、iDRAC IP 是否正确，以及是否已开启“IPMI over LAN”。"
        case .manualControlUnsupported:
            return "iDRAC9 ≥ 3.34.34.34 或 iDRAC10 已封禁 raw 0x30 0x30 命令，需降级固件或使用 iDRAC 自带策略。"
        case .commandFailed, .parseFailed, .processLaunchFailed:
            return "请检查 ipmitool 安装状态与 iDRAC 连接状态后重试。"
        }
    }
}
