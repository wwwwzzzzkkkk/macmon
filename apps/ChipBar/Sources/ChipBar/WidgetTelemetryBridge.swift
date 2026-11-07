import Foundation
import WidgetKit
import ChipBarCore

/// Widgets use a system-controlled timeline, not an extra process sampler.
/// ChipBar publishes a small, read-only summary to its shared app-group
/// preferences. This stays local to the Mac.
@MainActor final class WidgetTelemetryBridge {
    static let shared = WidgetTelemetryBridge()

    // Ad-hoc releases cannot claim an Apple Team ID app-group entitlement.
    // Use the extension's own sandbox file and avoid unentitled group access.
    private static let extensionID = "local.chipbar.monitor.widgets"

    private var lastWrite: Date?
    private var lastReload: Date?

    /// Never update preference storage on every 1-second macmon tick.
    /// WidgetKit has its own refresh budget and is not a live display.
    func publish(_ sample: Sample, history: [Sample]) {
        let now = Date()
        if let lastWrite, now.timeIntervalSince(lastWrite) < 60 { return }
        var values: [String: Any] = [
            "timestamp": now.timeIntervalSince1970
        ]
        func write(_ name: String, _ number: Double?) {
            if let number, number.isFinite && number >= 0 { values[name] = number }
        }
        write("chip", sample.total)
        write("cpuPower", sample.cpu)
        write("gpuPower", sample.gpu)
        write("anePower", sample.ane)
        write("cpuUsage", sample.cpuUtilization)
        write("gpuUsage", sample.gpuUtilization)
        write("cpuTemperature", sample.cpuTemperature)
        write("gpuTemperature", sample.gpuTemperature)
        write("fanRPM", sample.fans.map(\.rpm).max())
        write("ramPercentage", sample.memory?.usedPercent)
        write("ramUsed", sample.memory?.usedGiB)
        write("ramTotal", sample.memory?.totalGiB)
        write("internalPower", ChipBarPowerFlowModel.shared.reading.systemWatts)

        // Keep at most 24 real historical samples from the recent 10 minutes.
        let recent = history.filter { now.timeIntervalSince($0.date) <= 600 }
        let strideBy = max(1, (recent.count + 23) / 24)
        values["powerHistory"] = Swift.stride(from: 0, to: recent.count, by: strideBy)
            .compactMap { recent[$0].total }.filter { $0.isFinite && $0 >= 0 }

        let cores = CPUCoreLoadModel.shared.values
        if !cores.isEmpty {
            values["coreUsage"] = cores.map { min(100, max(0, $0)) }
        }

        if let availableBytes = InternalStorageModel.shared.capacity?.availableBytes,
           availableBytes >= 0 {
            values["storageFreeGB"] = Double(availableBytes) / 1_000_000_000
        }
        if let totalBytes = InternalStorageModel.shared.capacity?.totalBytes,
           totalBytes > 0 {
            values["storageTotalGB"] = Double(totalBytes) / 1_000_000_000
        }

        if let snapshot = ApplicationActivityModel.shared.snapshot {
            let top = snapshot.rows
                .filter { ($0.cpuPercent ?? 0) > 0 }
                .sorted { ($0.cpuPercent ?? 0) > ($1.cpuPercent ?? 0) }
                .prefix(3)
            values["applicationNames"] = top.map(\.name)
            values["applicationCPU"] = top.map { $0.cpuPercent ?? 0 }
        }

        // The unsandboxed host writes only non-sensitive, read-only telemetry
        // to the widget extension's sandbox Application Support directory.
        // Never request an App Group without a matching Team ID entitlement.
        let destination = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(Self.extensionID)/Data/Library/Application Support/ChipBar")
            .appendingPathComponent("telemetry.json")
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: values, options: [])
            try data.write(to: destination, options: .atomic)
        } catch {
            // The user may not yet have installed/activated the extension.
            // Keep the widget path best-effort; do not interrupt monitoring.
        }
        lastWrite = now

        // Each of the ten widget kinds has an independent timeline; update
        // them as a group, respecting WidgetKit's OS-controlled budget.
        if lastReload.map({ now.timeIntervalSince($0) >= 15 * 60 }) ?? true {
            lastReload = now
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
