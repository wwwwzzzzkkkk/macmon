import SwiftUI

struct CPUCoreUsageSection: View {
    let samplingInterval: Int
    let active: Bool
    @StateObject private var model = CPUCoreLoadModel.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let topology = CPUCoreTopology.current

    private var coreSummary: String {
        let names = topology.levels.map { "\($0.shortTitle) \($0.count)" }
        return names.isEmpty
            ? (model.hasSample ? "\(model.values.count) 个逻辑核心" : "正在采样…")
            : names.joined(separator: " · ")
    }

    private func coreShortName(_ id: Int) -> String {
        switch topology.namesByLogicalID[id] {
        case "超级核": return "超"
        case "性能核": return "大"
        case "能效核": return "能"
        default: return "\(id + 1)"
        }
    }

    private func fullCoreName(_ id: Int) -> String {
        topology.namesByLogicalID[id] ?? "类型未确认"
    }


    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("CPU 各核心占用", systemImage: "cpu")
                    .font(.caption.weight(.medium))
                Spacer()
                Text(coreSummary)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 2) {
                if model.values.isEmpty {
                    Text("等待两次 CPU 计数器采样")
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).frame(height: 47)
                } else {
                    ForEach(Array(model.values.enumerated()), id: \.offset) { index, percent in
                        VStack(spacing: 3) {
                            GeometryReader { geo in
                                ZStack(alignment: .bottom) {
                                    Capsule().fill(Color.primary.opacity(0.075))
                                    Capsule().fill(Color.accentColor.opacity(0.72))
                                        .frame(height: geo.size.height * min(1, max(0, percent / 100)))
                                        .animation(reduceMotion ? nil : .easeOut(duration: 0.23), value: percent)
                                }
                                .frame(maxWidth: 9)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }.frame(height: 30)
                            Text(coreShortName(index))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.secondary).lineLimit(1)
                                .help("逻辑核心 \(index + 1) · \(fullCoreName(index))")
                        }
                        .frame(maxWidth: .infinity)
                        .help("逻辑核心 \(index + 1) · \(fullCoreName(index))：\(Int(percent.rounded()))%")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("逻辑核心 \(index + 1) · \(fullCoreName(index))")
                        .accessibilityValue("\(Int(percent.rounded()))%")
                    }
                }
            }.frame(height: 47)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .task(id: "\(samplingInterval)-\(active)") {
            guard active else { return }
            await model.watch(intervalMillis: samplingInterval)
        }
    }
}
