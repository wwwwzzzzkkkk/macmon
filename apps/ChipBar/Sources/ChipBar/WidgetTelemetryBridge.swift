import Foundation
import WidgetKit
import ChipBarCore

/// Widgets have OS-budgeted timelines. The host app publishes recent metrics
/// to the extension sandbox; it does not create any widget-side SMC reader or
/// long-lived background process.
@MainActor final class WidgetTelemetryBridge {
    static let shared = WidgetTelemetryBridge()

    // Ad-hoc releases cannot claim an Apple Team ID app-group entitlement.
    // Use the extension's own sandbox file and avoid unentitled group access.
    private static let extensionID = "local.chipbar.monitor.widgets"

    private var lastWrite: Date?
    private var lastReload: Date?
    private var lastCoreSample: Date?
    private var cores: [Double] = []
    private let coreSampler = CPUCoreSampler()
    private var coreSampling = false
    private var lastPayload: [String: Any]?

    // Persist a fresh payload approximately every 15 seconds while the host
    // runs. The operating system may still postpone displaying the new image.
    // No busy timer: calls arrive from the existing macmon stream.
    func publish(_ sample: Sample, history: [Sample]) {
        let now = Date()
        updateCoreReadingsIfNeeded(now: now)
        if let lastWrite, now.timeIntervalSince(lastWrite) < 15 { return }
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
        // Descriptive labels and aggregates for the high-density glass
        // dashboard. These are real measurements, not design-mock values.
        if let chip = sample.chip, !chip.isEmpty {
            values["chipName"] = String(chip.prefix(56))
        }
        if let model = sample.model, !model.isEmpty {
            values["macModel"] = String(model.prefix(56))
        }

        // Keep at most 24 real historical samples from the recent 10 minutes.
        let recent = history.filter { now.timeIntervalSince($0.date) <= 600 }
        let strideBy = max(1, (recent.count + 23) / 24)
        let realPowers = recent.compactMap(\.total).filter { $0.isFinite && $0 >= 0 }
        if !realPowers.isEmpty {
            write("averagePower", realPowers.reduce(0, +) / Double(realPowers.count))
            write("peakPower", realPowers.max())
        }
        values["powerHistory"] = Swift.stride(from: 0, to: recent.count, by: strideBy)
            .compactMap { recent[$0].total }.filter { $0.isFinite && $0 >= 0 }

        // CPUCoreLoadModel is only active when the dashboard is open.
        // For widgets use the independently sampled Mach utilization cache,
        // collected on a low-frequency background actor instead.
        mergeCoreReadings(into: &values)

        if let availableBytes = InternalStorageModel.shared.capacity?.availableBytes,
           availableBytes >= 0 {
            values["storageFreeGB"] = Double(availableBytes) / 1_000_000_000
        }
        if let totalBytes = InternalStorageModel.shared.capacity?.totalBytes,
           totalBytes > 0 {
            values["storageTotalGB"] = Double(totalBytes) / 1_000_000_000
        }

        // Same disk model as ChipBar Home. Rates are stored only while the
        // sampler's physical-disk snapshot is fresh; never invent a speed.
        let external = ExternalStorageCapacityModel.shared
        if let drive = external.volumes.first {
            values["externalName"] = String(drive.volume.name.prefix(40))
            write("externalFreeGB", Double(drive.volume.available) / 1_000_000_000)
            write("externalTotalGB", Double(drive.volume.total) / 1_000_000_000)
        }
        if let activity = external.activity,
           now.timeIntervalSince(activity.date) >= 0,
           now.timeIntervalSince(activity.date) <= 10 {
            let internalRates = activity.rates.filter {
                activity.connected.contains($0.key) && !activity.external.contains($0.key)
            }.map(\.value)
            if !internalRates.isEmpty {
                write("storageReadMB", internalRates.reduce(0) { $0 + $1.readMB })
                write("storageWriteMB", internalRates.reduce(0) { $0 + $1.writeMB })
            }
            if let drive = external.volumes.first,
               activity.connected.contains(drive.diskID),
               let rate = activity.rates[drive.diskID] {
                write("externalReadMB", rate.readMB)
                write("externalWriteMB", rate.writeMB)
            }
        }

        if let snapshot = ApplicationActivityModel.shared.snapshot {
            let top = snapshot.rows
                .filter { ($0.cpuPercent ?? 0) > 0 }
                .sorted { ($0.cpuPercent ?? 0) > ($1.cpuPercent ?? 0) }
                .prefix(3)
            values["applicationNames"] = top.map(\.name)
            values["applicationCPU"] = top.map { $0.cpuPercent ?? 0 }
        }

        writePayload(values, now: now)
    }

    private func mergeCoreReadings(into values: inout [String: Any]) {
        guard let lastCoreSample,
              Date().timeIntervalSince(lastCoreSample) <= 90,
              !cores.isEmpty else { return }
        values["coreUsage"] = cores.map { min(100, max(0, $0)) }
        let verified = CPUCoreTopology.current.namesByLogicalID
        if verified.count == cores.count {
            values["coreTiers"] = cores.indices.map { verified[$0] ?? "" }
        }
    }

    private func updateCoreReadingsIfNeeded(now: Date) {
        guard !coreSampling,
              lastCoreSample.map({ now.timeIntervalSince($0) >= 20 }) ?? true else { return }
        coreSampling = true
        Task { [weak self] in
            guard let self else { return }
            // host_processor_info exposes cumulative ticks: discard the
            // baseline, then calculate utilization across a real interval.
            _ = await self.coreSampler.read()
            do { try await Task.sleep(for: .milliseconds(650)) }
            catch { self.coreSampling = false; return }
            guard let percentages = await self.coreSampler.read(),
                  !percentages.isEmpty else {
                self.coreSampling = false
                return
            }
            let at = Date()
            self.cores = percentages
            self.lastCoreSample = at
            self.coreSampling = false
            // First successful CPU-core sample should reach disk immediately,
            // not require the user to open the home dashboard.
            if var payload = self.lastPayload {
                self.mergeCoreReadings(into: &payload)
                payload["timestamp"] = at.timeIntervalSince1970
                self.writePayload(payload, now: at)
            }
        }
    }

    private func writePayload(_ payload: [String: Any], now: Date) {
        // The unsandboxed host writes only non-sensitive, read-only telemetry
        // to the WidgetKit extension's own Application Support container.
        let destination = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(Self.extensionID)/Data/Library/Application Support/ChipBar")
            .appendingPathComponent("telemetry.json")
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            try data.write(to: destination, options: .atomic)
            lastWrite = now
            lastPayload = payload
            if lastReload.map({ now.timeIntervalSince($0) >= 120 }) ?? true {
                lastReload = now
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            // A missing extension container is not a reason to interrupt
            // ChipBar's main monitoring.
        }
    }
}
