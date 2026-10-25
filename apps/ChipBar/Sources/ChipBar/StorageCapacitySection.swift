import SwiftUI
import ChipBarCore

/// File-system capacities for mounted external drives. This is deliberately
/// independent of the optional smartctl/SMART feature and never needs sudo.
/// DiskActivitySampler caches APFS volume checks for 30 seconds.
struct ExternalVolumeCapacity: Identifiable {
    let diskID: String
    let volume: DiskVolumeSpace

    var id: String { volume.id }
}

/// Shared across Home and page round-trips; no repeated Disk Arbitration
/// scans when a SwiftUI page is remounted during a transition.
@MainActor final class ExternalStorageCapacityModel: ObservableObject {
    static let shared = ExternalStorageCapacityModel()

    @Published private(set) var volumes: [ExternalVolumeCapacity] = []
    @Published private(set) var sampled = false

    private let sampler = DiskActivitySampler()
    private var lastSampleAt: Date?
    private var scanning = false

    func watch() async {
        while !Task.isCancelled {
            if !scanning &&
                (lastSampleAt.map { Date().timeIntervalSince($0) >= 30 } ?? true) {
                scanning = true
                let result = await sampler.sampleAll(includeVolumes: true)
                scanning = false
                guard !Task.isCancelled else { return }

                // Never add APFS System/Data partitions or several volumes
                // together: each mounted volume gets its own space bar.
                volumes = result.external.sorted().flatMap { diskID in
                    (result.volumes[diskID] ?? []).map {
                        ExternalVolumeCapacity(diskID: diskID, volume: $0)
                    }
                }
                sampled = true
                lastSampleAt = Date()
            }
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
        }
    }
}

/// The capacity overview belongs on Home, not behind System Details or an
/// SSD disclosure. Temperatures, fan telemetry and SMART stay on that page.
struct StorageCapacitySection: View {
    @StateObject private var internalStorage = InternalStorageModel.shared
    @StateObject private var externalStorage = ExternalStorageCapacityModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("储存空间", systemImage: "internaldrive")
                .font(.subheadline.weight(.medium))

            VStack(alignment: .leading, spacing: 11) {
                StorageVolumeRow(title: "内置储存", symbol: "internaldrive",
                                 total: internalStorage.capacity?.totalBytes,
                                 available: internalStorage.capacity?.availableBytes,
                                 placeholder: internalStorage.sampled ? "不可用" : "读取中…")

                Divider().opacity(0.55)

                if !externalStorage.sampled {
                    StorageVolumeRow(title: "外接储存", symbol: "externaldrive",
                                     total: nil, available: nil, placeholder: "读取中…")
                } else if externalStorage.volumes.isEmpty {
                    StorageVolumeRow(title: "外接储存", symbol: "externaldrive",
                                     total: nil, available: nil, placeholder: "未检测到已挂载磁盘")
                } else {
                    ForEach(externalStorage.volumes) { item in
                        StorageVolumeRow(
                            title: item.volume.name.isEmpty ? "外接储存" : item.volume.name,
                            symbol: "externaldrive",
                            total: item.volume.total,
                            available: item.volume.available,
                            subtitle: item.volume.apfs ? "外接 SSD / 磁盘 · APFS 共享空间" : "外接 SSD / 磁盘",
                            placeholder: "暂不可用")
                    }
                }
            }
            .padding(11)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
        .task {
            // Avoid expensive first reads in the first frame of the glass popup.
            do { try await Task.sleep(for: .milliseconds(320)) }
            catch { return }
            await internalStorage.watch()
        }
        .task {
            do { try await Task.sleep(for: .milliseconds(320)) }
            catch { return }
            await externalStorage.watch()
        }
    }
}

/// Fixed-height mini capacity bar. All capacity values are file-system values
/// from macOS; an empty value is shown as unavailable, never fabricated.
private struct StorageVolumeRow: View {
    let title: String
    let symbol: String
    let total: Int64?
    let available: Int64?
    var subtitle: String? = nil
    let placeholder: String

    private var valid: (total: Int64, available: Int64)? {
        guard let total, let available, total > 0,
              available >= 0, available <= total else { return nil }
        return (total, available)
    }

    private func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .decimal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .frame(width: 15)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let value = valid {
                    Text("可用 \(bytes(value.available))")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text(placeholder)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            CapacityProgressTrack(usedFraction:
                valid.map { 1 - Double($0.available) / Double($0.total) })

            if let value = valid {
                HStack {
                    Text("已使用 \(bytes(value.total - value.available))")
                    Spacer()
                    Text("总容量 \(bytes(value.total))")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
