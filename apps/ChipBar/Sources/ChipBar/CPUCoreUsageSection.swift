import SwiftUI

struct CPUCoreUsageSection: View {
    let samplingInterval: Int
    let active: Bool
    @StateObject private var model = CPUCoreLoadModel.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("CPU 各核心占用", systemImage: "cpu")
                    .font(.caption.weight(.medium))
                Spacer()
                Text(model.hasSample ? "\(model.values.count) 个逻辑核心" : "正在采样…")
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
                            Text("\(index + 1)").font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .help("逻辑核心 \(index + 1)：\(Int(percent.rounded()))%")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("逻辑核心 \(index + 1)")
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
