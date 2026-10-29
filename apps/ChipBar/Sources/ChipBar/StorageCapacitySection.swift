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

    /// Display filesystem capacity per mounted external volume, never sum
    /// APFS sharing members. Identical APFS capacity/free records on one
    /// physical disk represent shared capacity and need one compact bar.
    static func displayRows(from snapshot: DiskActivitySnapshot) -> [ExternalVolumeCapacity] {
        snapshot.external.sorted().flatMap { diskID -> [ExternalVolumeCapacity] in
            var knownShared: Set<String> = []
            return (snapshot.volumes[diskID] ?? []).compactMap { volume in
                if volume.apfs {
                    let key = "\(volume.total):\(volume.available)"
                    guard knownShared.insert(key).inserted else { return nil }
                }
                return ExternalVolumeCapacity(diskID: diskID, volume: volume)
            }
        }
    }

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
                volumes = Self.displayRows(from: result)
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

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("储存空间", systemImage: "internaldrive")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("可用容量")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                StorageVolumeCard(
                    title: "Macintosh HD",
                    symbol: "internaldrive",
                    total: internalStorage.capacity?.totalBytes,
                    available: internalStorage.capacity?.availableBytes,
                    placeholder: internalStorage.sampled ? "不可用" : "读取中…")

                if !externalStorage.sampled {
                    StorageVolumeCard(title: "外接储存", symbol: "externaldrive",
                                      total: nil, available: nil, placeholder: "读取中…")
                } else if externalStorage.volumes.isEmpty {
                    StorageVolumeCard(title: "外接储存", symbol: "externaldrive",
                                      total: nil, available: nil, placeholder: "未接入磁盘")
                } else {
                    ForEach(externalStorage.volumes) { item in
                        StorageVolumeCard(
                            title: item.volume.name.isEmpty ? "外接储存" : item.volume.name,
                            symbol: "externaldrive",
                            total: item.volume.total,
                            available: item.volume.available,
                            placeholder: "不可用")
                    }
                }
            }
        }
        .task {
            // Retain the existing non-blocking 30-second capacity sources.
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

/// Clean volume summary: one readable available-space number and a restrained
/// usage runway. No repeated full-width capacity bars or redundant subtitles.
/// Capacity values are macOS file-system values, never invented telemetry.
private struct StorageVolumeCard: View {
    let title: String
    let symbol: String
    let total: Int64?
    let available: Int64?
    let placeholder: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let accent = Color(red: 0.22, green: 0.65, blue: 0.79)

    private var capacity: (total: Int64, available: Int64)? {
        guard let total, let available, total > 0,
              available >= 0 && available <= total else { return nil }
        return (total, available)
    }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal)
    }

    private var usedFraction: Double {
        guard let capacity else { return 0 }
        return 1 - Double(capacity.available) / Double(capacity.total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(accent)
                    .frame(width: 17)
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }

            if let capacity {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatted(capacity.available))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                Text("总计 \(formatted(capacity.total))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(placeholder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(height: 26, alignment: .leading)
                Text("容量暂不可用")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 7) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.10))
                        Capsule().fill(accent.opacity(0.82))
                            .frame(width: geometry.size.width * usedFraction)
                    }
                }
                .frame(height: 5)
                .animation(reduceMotion ? nil : ChipBarMotion.disclosure, value: usedFraction)

                Text(capacity.map { String(format: "%.0f%%", usedFraction * 100) } ?? "—")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 96, alignment: .top)
        .padding(11)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，" +
            (capacity.map { "可用 \(formatted($0.available))，总计 \(formatted($0.total))，已用 \(Int((usedFraction * 100).rounded()))%" } ?? placeholder))
    }
}
