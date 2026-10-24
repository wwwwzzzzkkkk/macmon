import SwiftUI
import DiskArbitration
import ChipBarCore

/// Uses the boot APFS Data volume rather than summing mounted APFS volumes:
/// System, Data and Preboot can all share the same physical container.
/// Disk Arbitration confirms that the selected volume is on an internal disk.
/// External boot volumes are deliberately not described as internal storage.
actor InternalStorageSampler {
    func read() -> InternalStorageCapacity? {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return nil }
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        for path in ["/System/Volumes/Data", "/"] {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            guard FileManager.default.fileExists(atPath: path),
                  let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
                  let details = DADiskCopyDescription(disk) as? [String: Any],
                  details[kDADiskDescriptionDeviceInternalKey as String] as? Bool == true,
                  details[kDADiskDescriptionVolumeNetworkKey as String] as? Bool != true,
                  let values = try? url.resourceValues(forKeys: keys),
                  let total = values.volumeTotalCapacity,
                  let available = values.volumeAvailableCapacity,
                  let capacity = InternalStorageCapacity(totalBytes: Int64(total),
                                                         availableBytes: Int64(available)) else { continue }
            return capacity
        }
        return nil
    }
}

@MainActor final class InternalStorageModel: ObservableObject {
    @Published private(set) var capacity: InternalStorageCapacity?
    @Published private(set) var sampled = false

    func watch() async {
        let sampler = InternalStorageSampler()
        while !Task.isCancelled {
            let value = await sampler.read()
            guard !Task.isCancelled else { return }
            capacity = value
            sampled = true
            // Capacity is not a fast-changing performance metric. Recheck
            // without polling every chip power sample or launching subprocesses.
            do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
        }
    }
}

struct InternalStorageSection: View {
    @StateObject private var model = InternalStorageModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Label("内置储存", systemImage: "internaldrive")
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 4)
                if let capacity = model.capacity {
                    Text("可用 \(capacity.availableText)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } else {
                    Text(model.sampled ? "不可用" : "读取中…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    if let capacity = model.capacity {
                        Capsule().fill(Color(red: 0.22, green: 0.65, blue: 0.79).opacity(0.7))
                            .frame(width: max(0, geometry.size.width * capacity.usedFraction))
                    }
                }
            }
            .frame(height: 4)
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88),
                       value: model.capacity?.usedFraction)
            HStack {
                if let capacity = model.capacity {
                    Text("已使用 \(ByteCountFormatter.string(fromByteCount: capacity.totalBytes - capacity.availableBytes, countStyle: .decimal))")
                    Spacer()
                    Text("总容量 \(capacity.totalText)")
                } else {
                    Text(model.sampled ? "无法确认内置启动磁盘；不计入外置盘" : "正在读取系统数据卷容量…")
                    Spacer(minLength: 0)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .padding(11)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 11))
        .task { await model.watch() }
        .accessibilityElement(children: .combine)
    }
}
