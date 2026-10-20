import AppKit
import SwiftUI
import Combine
import ChipBarCore

@MainActor final class Monitor: ObservableObject {
    @Published private(set) var sample: Sample?
    @Published private(set) var history: [Sample] = []
    @Published private(set) var status = "正在连接 macmon…"
    @Published private(set) var error: String?
    @Published private(set) var paused = false
    @Published private(set) var sleeping = false
    @Published private(set) var connected = false
    @Published var menuItems: Set<MenuContent> {
        didSet {
            UserDefaults.standard.set(menuItems.map(\.rawValue), forKey: "menuItems")
            if oldValue.contains(.disk) != menuItems.contains(.disk) { restartMenuDisk() }
        }
    }
    @Published private(set) var menuDisk: DiskActivitySnapshot?
    private var menuDiskTask: Task<Void, Never>?
    @Published var interval: Int {
        didSet { UserDefaults.standard.set(interval, forKey: "interval"); restart() }
    }
    @Published var menuMetric: PowerMetric {
        didSet { UserDefaults.standard.set(menuMetric.rawValue, forKey: "menuMetric") }
    }
    @Published private(set) var executablePath = ""
    private var customPath: String
    private var client: StreamClient?
    private var generation = UUID()
    private var retry: Task<Void, Never>?
    private var watchdog: Timer?
    private var startedAt = Date()
    private var lastReceived: Date?
    private var failureCount = 0
    private var observers: [NSObjectProtocol] = []
    let ssd: ExternalSSDMonitor
    let network: NetworkMonitor
    private var networkSubscription: AnyCancellable?
    private var ssdSubscription: AnyCancellable?
    let hardware: String

    init(start: Bool = true, ssdDefaults: UserDefaults = .standard, initialSample: Sample? = nil) {
        ssd = ExternalSSDMonitor(defaults: ssdDefaults, start: start)
        network = NetworkMonitor(start: start)
        menuItems = UserDefaults.standard.stringArray(forKey: "menuItems")
            .map { Set($0.compactMap(MenuContent.init(rawValue:))) } ?? [.logo, .power]
        let saved = UserDefaults.standard.integer(forKey: "interval")
        interval = [1000, 2000, 5000, 10000].contains(saved) ? saved : 2000
        menuMetric = PowerMetric(rawValue: UserDefaults.standard.string(forKey: "menuMetric") ?? "") ?? .total
        customPath = UserDefaults.standard.string(forKey: "macmonPath") ?? ""
        hardware = Self.sysctlString("machdep.cpu.brand_string") ?? "未知芯片"
        sample = initialSample
        connected = initialSample != nil
        history = initialSample.map { [$0] } ?? []
        if initialSample != nil { status = "预览 · 已有真实采样" }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = true; self?.network.setPaused(true); self?.restartMenuDisk(); self?.stop(); self?.status = "睡眠期间暂停" }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sleeping = false; self.network.setPaused(self.paused); self.restartMenuDisk(); self.restart()
            }
        })
        ssdSubscription = ssd.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        networkSubscription = network.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        if start { restart(); restartMenuDisk() }
    }

    var menuReadouts: [MenuReadout] {
        var items: [MenuReadout] = []
        if menuItems.contains(.power) {
            items.append(MenuReadout("power-" + menuMetric.rawValue, powerMenuText.replacingOccurrences(of: " W", with: "W"),
                                     menuMetric == .total ? "POWER" : menuMetric.rawValue.uppercased() + " W"))
        }
        if menuItems.contains(.utilization) {
            for (name, value) in [("CPU", sample?.cpuUtilization), ("GPU", sample?.gpuUtilization)] {
                let text = connected ? value.map { String(format: "%.0f%%", $0) } ?? "—" : "—"
                items.append(MenuReadout(name, text, name))
            }
        }
        if ssd.enabled, ssd.showInMenu {
            items.append(MenuReadout("ssd", ssd.menuTemperature.map { String(format: "%.0f°C", $0) } ?? "—", "SSD"))
        }
        if menuItems.contains(.fans) {
            let rpm = connected ? sample?.fans.map(\.rpm).max() : nil
            items.append(MenuReadout("fans", rpm.map { String(format: "%.0f", $0) } ?? "—", "RPM"))
        }
        if menuItems.contains(.network) {
            items.append(MenuReadout("network", "↓" + MenuReadout.rate(network.rate?.download),
                                     "↑" + MenuReadout.rate(network.rate?.upload), pairedValues: true))
        }
        if menuItems.contains(.disk) {
            let rates = diskMenuRates
            items.append(MenuReadout("disk", "R " + MenuReadout.rate(rates.read),
                                     "W " + MenuReadout.rate(rates.write), pairedValues: true))
        }
        return items
    }

    private var diskMenuRates: (read: Double?, write: Double?) {
        guard let snapshot = menuDisk, Date().timeIntervalSince(snapshot.date) <= 6, !snapshot.rates.isEmpty else {
            return (nil, nil)
        }
        return (snapshot.rates.values.reduce(0) { $0 + $1.readMB } * 1_000_000,
                snapshot.rates.values.reduce(0) { $0 + $1.writeMB } * 1_000_000)
    }

    var menuText: String {
        var parts: [String] = []
        if menuItems.contains(.power) { parts.append(powerMenuText) }
        if menuItems.contains(.utilization) {
            func percent(_ value: Double?) -> String {
                guard connected, let value else { return "—" }
                return String(format: "%.0f%%", value)
            }
            parts.append("CPU \(percent(sample?.cpuUtilization)) GPU \(percent(sample?.gpuUtilization))")
        }
        if menuItems.contains(.fans) {
            let fans = connected ? sample?.fans ?? [] : []
            parts.append(fans.isEmpty ? "风扇 —" : fans.map { String(format: "%.0f", $0.rpm) }.joined(separator: "/") + " RPM")
        }
        if menuItems.contains(.network) {
            parts.append("↓\(NetworkRate.text(network.rate?.download)) ↑\(NetworkRate.text(network.rate?.upload))")
        }
        if menuItems.contains(.disk) {
            let rates = diskMenuRates
            parts.append("读\(NetworkRate.text(rates.read)) 写\(NetworkRate.text(rates.write))")
        }
        let temperature = ssd.menuSuffix
        if !temperature.isEmpty { parts.append(String(temperature.dropFirst(3))) }
        return parts.joined(separator: " · ")
    }

    private func restartMenuDisk() {
        menuDiskTask?.cancel(); menuDiskTask = nil; menuDisk = nil
        guard menuItems.contains(.disk), !paused, !sleeping else { return }
        menuDiskTask = Task { [weak self] in
            let sampler = DiskActivitySampler()
            while !Task.isCancelled {
                let next = await sampler.sampleAll()
                guard !Task.isCancelled else { return }
                self?.menuDisk = next
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            }
        }
    }

    private var powerMenuText: String {
        if paused || sleeping { return "暂停" }
        guard connected, let power = sample?.power(menuMetric) else { return "— W" }
        return String(format: "%.1f W", power)
    }

    func stop(forQuit: Bool = false) {
        if forQuit { ssd.shutdown(); network.setPaused(true); menuDiskTask?.cancel(); menuDiskTask = nil; menuDisk = nil }
        generation = UUID()
        retry?.cancel(); retry = nil
        watchdog?.invalidate(); watchdog = nil
        client?.stop(wait: forQuit); client = nil
        connected = false
    }

    func restart() {
        stop()
        guard !paused, !sleeping else { return }
        error = nil
        status = "正在连接 macmon…"
        sample = nil
        lastReceived = nil
        startedAt = Date()
        guard let path = resolvePath() else {
            error = "找不到可执行的 macmon。请在设置中选择已安装的 macmon 文件。常见位置：/opt/homebrew/bin/macmon。"
            status = "需要设置 macmon 路径"
            return
        }
        executablePath = path
        let token = generation
        let next = StreamClient(path: path, interval: interval, onSample: { [weak self] sample in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.sample = sample
                self.lastReceived = Date()
                self.connected = true
                self.error = nil
                self.failureCount = 0
                self.status = "实时采样 · \(self.interval / 1000) 秒"
                self.history.append(sample)
                let cutoff = Date().addingTimeInterval(-600)
                self.history.removeAll { $0.date < cutoff }
                if self.history.count > 600 { self.history.removeFirst(self.history.count - 600) }
            }
        }, onFailure: { [weak self] message in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.fail(message)
            }
        })
        client = next
        do { try next.start() }
        catch { fail("无法启动 macmon：\(error.localizedDescription)"); return }
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if Date().timeIntervalSince(self.lastReceived ?? self.startedAt) > max(10, Double(self.interval) / 1000 * 4) {
                    self.fail("macmon 长时间没有返回有效数据。请检查硬件支持或重新选择程序。")
                }
            }
        }
    }

    private func fail(_ message: String) {
        stop()
        error = message
        failureCount += 1
        let delay = min(60, 2 * Int(pow(2.0, Double(min(failureCount - 1, 5)))))
        status = "采样中断 · \(delay) 秒后重试"
        retry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.restart()
        }
    }

    func togglePause() {
        paused.toggle()
        network.setPaused(paused || sleeping)
        restartMenuDisk()
        ssd.setPaused(paused)
        if paused { stop(); status = "采样已暂停"; error = nil } else { restart() }
    }

    func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.title = "选择 macmon 可执行文件"
        panel.message = "通常位于 /opt/homebrew/bin/macmon，可按 ⌘⇧G 输入路径。"
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                error = "所选文件不能执行，请选择 macmon 程序。"
                return
            }
            customPath = url.path
            UserDefaults.standard.set(customPath, forKey: "macmonPath")
            restart()
        }
    }

    func useDefaultPath() {
        customPath = ""
        UserDefaults.standard.removeObject(forKey: "macmonPath")
        restart()
    }

    private func resolvePath() -> String? {
        #if arch(arm64)
        let candidates = customPath.isEmpty ? ["/opt/homebrew/bin/macmon", "/usr/local/bin/macmon"] : [customPath]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        #else
        return nil
        #endif
    }

    private static func sysctlString(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
