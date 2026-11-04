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

/// Information density without a long five-row table. Hardware and CPU tier
/// metadata are cached by the existing static samplers (no periodic sysctl).
struct MacHardwareInformationSection: View {
    let chip: String
    private let info = MacHardwareInformation.current
    private let tiers = CPUCoreTopology.current.levels
    private let accent = Color(red: 0.22, green: 0.65, blue: 0.79)

    private var coreDescription: String {
        guard !tiers.isEmpty else { return "\(info.logicalCPUCount) 逻辑核" }
        return tiers.map { "\($0.shortTitle) \($0.count)" }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)
                    .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(chip.isEmpty ? "Apple Silicon" : chip)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.80)
                    Text(info.modelIdentifier)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 7),
                                GridItem(.flexible(), spacing: 7)], spacing: 7) {
                fact("系统版本", info.macOSVersion, symbol: "apple.logo")
                fact("统一内存", info.installedMemory, symbol: "memorychip")
                fact("CPU 核心", "\(info.logicalCPUCount) 核", symbol: "cpu")
                fact("核心结构", coreDescription, symbol: "square.grid.3x3")
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private func fact(_ title: String, _ value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(accent.opacity(0.8))
                .frame(width: 15)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 39, alignment: .topLeading)
        .padding(8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .combine)
    }
}
