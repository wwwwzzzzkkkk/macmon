import Foundation

public enum MenuContent: String, CaseIterable, Identifiable {
    case logo, power, utilization, fans, network, disk
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .logo: return "显示 Logo"
        case .power: return "功率"
        case .utilization: return "CPU / GPU 占用率"
        case .fans: return "风扇转速"
        case .network: return "实时上传 / 下载速度"
        case .disk: return "硬盘读取 / 写入速度"
        }
    }
}
