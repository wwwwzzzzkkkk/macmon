import SwiftUI
import Darwin

/// Hardware facts that do not require a privilege prompt, SMART probe, or
/// subprocess. Resolve them once; each sensor refresh should not run sysctl.
struct MacHardwareInformation: Sendable, Equatable {
    let modelIdentifier: String
    let macOSVersion: String
    let installedMemory: String
    let logicalCPUCount: Int

    static let current: MacHardwareInformation = {
        let process = ProcessInfo.processInfo
        let v = process.operatingSystemVersion
        let version = "macOS \(v.majorVersion).\(v.minorVersion)" +
            (v.patchVersion == 0 ? "" : ".\(v.patchVersion)")
        let ram = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: process.physicalMemory), countStyle: .decimal)
        return MacHardwareInformation(
            modelIdentifier: identifier("hw.model") ?? "不可用",
            macOSVersion: version,
            installedMemory: ram,
            logicalCPUCount: process.processorCount
        )
    }()

    private static func identifier(_ name: String) -> String? {
        var count = 0
        guard sysctlbyname(name, nil, &count, nil, 0) == 0,
              count > 1, count < 1024 else { return nil }
        var bytes = [CChar](repeating: 0, count: count)
        let result = bytes.withUnsafeMutableBufferPointer {
            sysctlbyname(name, $0.baseAddress, &count, nil, 0)
        }
        guard result == 0 else { return nil }
        let text = String(decoding: bytes.prefix { $0 != 0 }.map {
            UInt8(bitPattern: $0)
        }, as: UTF8.self)
        return text.isEmpty ? nil : text
    }
}

struct MacHardwareInformationSection: View {
    let chip: String
    private let info = MacHardwareInformation.current

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("电脑基本信息", systemImage: "desktopcomputer")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 0) {
                fact("设备型号", info.modelIdentifier)
                Divider().opacity(0.45)
                fact("芯片", chip.isEmpty ? "不可用" : chip)
                Divider().opacity(0.45)
                fact("系统版本", info.macOSVersion)
                Divider().opacity(0.45)
                fact("物理内存", info.installedMemory)
                Divider().opacity(0.45)
                fact("CPU 核心", "\(info.logicalCPUCount) 核")
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 11))
        }
        .accessibilityElement(children: .contain)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).foregroundStyle(.secondary)
                .frame(width: 63, alignment: .leading)
            Spacer(minLength: 4)
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .textSelection(.enabled)
        }
        .font(.caption)
        .frame(minHeight: 31)
        .accessibilityElement(children: .combine)
    }
}
