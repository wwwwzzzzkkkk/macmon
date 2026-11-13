import AppKit
import ChipBarCore
import Combine
import Foundation
import Network
import Security

/// Opt-in, read-only LAN telemetry. Neither transport direction accepts task
/// commands or launches processes. The existing macmon sampling loop is reused.
@MainActor final class ClusterMonitorService: ObservableObject {
    static let shared = ClusterMonitorService()

    @Published private(set) var enabled: Bool
    @Published private(set) var hasKey: Bool
    @Published private(set) var peers: [ClusterNodeReadout] = []
    @Published private(set) var status: String = "未启用"

    private static let enabledKey = "chipbar.cluster.enabled.v1"
    private static let nodeIDKey = "chipbar.cluster.node-id.v1"
    private static let keychainService = "local.chipbar.monitor.cluster"
    private static let keychainAccount = "shared-key-v1"

    private weak var monitor: Monitor?
    private let nodeID: String
    private var key: Data?
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var tickTimer: Timer?
    private var incoming: [UUID: NWConnection] = [:]
    private var outgoing: [String: NWConnection] = [:]
    private var buffers: [String: Data] = [:]
    private var discovered: [String: NWEndpoint] = [:]
    private var lastSeen: [String: Date] = [:]

    private init() {
        let defaults = UserDefaults.standard
        let id = defaults.string(forKey: Self.nodeIDKey) ?? UUID().uuidString
        defaults.set(id, forKey: Self.nodeIDKey)
        nodeID = id
        let storedKey = Self.readKey()
        key = storedKey
        hasKey = storedKey?.count == 32
        enabled = defaults.bool(forKey: Self.enabledKey) && storedKey?.count == 32
    }

    func attach(monitor: Monitor) {
        self.monitor = monitor
        if enabled { start() }
    }

    /// Copy the same random 256-bit key onto both Macs. The Keychain stores
    /// the secret locally; never advertise or transmit it over Bonjour.
    func createKey() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            status = "无法生成安全密钥"
            return nil
        }
        let encoded = Data(bytes).base64EncodedString()
        return importKey(encoded) ? encoded : nil
    }

    @discardableResult
    func importKey(_ string: String) -> Bool {
        let candidate = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decoded = Data(base64Encoded: candidate), decoded.count == 32 else {
            status = "密钥格式不正确，应为 32 字节的 Base64 密钥"
            return false
        }
        guard Self.storeKey(decoded) else {
            status = "无法写入 macOS 钥匙串"
            return false
        }
        let wasEnabled = enabled
        stop()
        key = decoded
        hasKey = true
        peers = []
        lastSeen = [:]
        if wasEnabled { start() }
        else { status = "密钥已保存在本机钥匙串" }
        return true
    }

    func copyKeyToPasteboard() {
        guard let key else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key.base64EncodedString(), forType: .string)
        status = "密钥已复制；请仅在受信任的另一台 Mac 上导入"
    }

    func importKeyFromPasteboard() {
        guard let string = NSPasteboard.general.string(forType: .string) else {
            status = "剪贴板没有可用的密钥"
            return
        }
        _ = importKey(string)
    }

    func setEnabled(_ value: Bool) {
        guard !value || hasKey else {
            status = "请先生成或导入共享密钥"
            return
        }
        enabled = value
        UserDefaults.standard.set(value, forKey: Self.enabledKey)
        if value { start() } else {
            stop()
            peers = []
            status = "未启用"
        }
    }

    var localNode: ClusterNodeReadout {
        let sample = monitor?.connected == true ? monitor?.sample : nil
        return ClusterNodeReadout(
            id: nodeID,
            name: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            chip: sample?.chip ?? monitor?.hardware ?? "Apple Silicon",
            timestamp: Date(),
            cpu: sample?.cpuUtilization,
            gpu: sample?.gpuUtilization,
            memoryUsedGB: sample?.memory?.usedGiB,
            memoryTotalGB: sample?.memory?.totalGiB,
            chipWatts: sample?.total,
            cpuTemperatureC: sample?.cpuTemperature,
            tasks: Self.readExternalTasks()
        )
    }

    var onlinePeers: [ClusterNodeReadout] {
        peers.filter { $0.isOnline() }
    }

    private var bonjourName: String {
        "ChipBar-" + String(nodeID.prefix(8))
    }

    private func start() {
        guard enabled, key?.count == 32, listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(
                name: bonjourName, type: ClusterSecureWire.serviceType)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready: self.status = "已开启局域网加密监控"
                    case .failed(let error): self.status = "共享服务失败：\(error.localizedDescription)"
                    default: break
                    }
                }
            }
            self.listener = listener
            listener.start(queue: .main)

            let browser = NWBrowser(
                for: .bonjour(type: ClusterSecureWire.serviceType, domain: nil),
                using: .tcp)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor in self?.updateDiscovered(results) }
            }
            browser.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    if case .failed(let error) = state {
                        self?.status = "设备发现失败：\(error.localizedDescription)"
                    }
                }
            }
            self.browser = browser
            browser.start(queue: .main)

            tickTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) {
                [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            tickTimer?.tolerance = 0.5
            status = "正在发现局域网设备…"
            tick()
        } catch {
            status = "无法启动集群服务：\(error.localizedDescription)"
        }
    }

    private func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        browser?.cancel()
        browser = nil
        listener?.cancel()
        listener = nil
        incoming.values.forEach { $0.cancel() }
        outgoing.values.forEach { $0.cancel() }
        incoming.removeAll()
        outgoing.removeAll()
        buffers.removeAll()
        discovered.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        guard enabled, incoming.count < 8 else {
            connection.cancel()
            return
        }
        let id = UUID()
        incoming[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready: self.sendSnapshot(to: connection)
                case .cancelled, .failed:
                    self.incoming.removeValue(forKey: id)
                default: break
                }
            }
        }
        connection.start(queue: .main)
    }

    private func updateDiscovered(_ results: Set<NWBrowser.Result>) {
        var visible: [String: NWEndpoint] = [:]
        for result in results {
            if case .service(let name, _, _, _) = result.endpoint,
               name == bonjourName { continue }
            let identifier = String(describing: result.endpoint)
            visible[identifier] = result.endpoint
        }
        discovered = visible
        for (identifier, connection) in outgoing.filter({ visible[$0.key] == nil }) {
            connection.cancel()
            outgoing.removeValue(forKey: identifier)
            buffers.removeValue(forKey: identifier)
        }
        connectDiscovered()
    }

    private func connectDiscovered() {
        guard enabled else { return }
        for (identifier, endpoint) in discovered where outgoing[identifier] == nil {
            let connection = NWConnection(to: endpoint, using: .tcp)
            outgoing[identifier] = connection
            connection.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready: self.receive(on: connection, id: identifier)
                    case .failed, .cancelled:
                        if self.outgoing[identifier] === connection {
                            self.outgoing.removeValue(forKey: identifier)
                            self.buffers.removeValue(forKey: identifier)
                        }
                    default: break
                    }
                }
            }
            connection.start(queue: .main)
        }
    }

    private func receive(on connection: NWConnection, id: String) {
        connection.receive(minimumIncompleteLength: 1,
                           maximumLength: ClusterSecureWire.maximumFrameBytes) {
            [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.outgoing[id] === connection else { return }
                if let data, !data.isEmpty { self.process(data, from: id) }
                if complete || error != nil {
                    connection.cancel()
                    self.outgoing.removeValue(forKey: id)
                    self.buffers.removeValue(forKey: id)
                } else {
                    self.receive(on: connection, id: id)
                }
            }
        }
    }

    private func process(_ data: Data, from id: String) {
        guard let key else { return }
        var buffer = buffers[id] ?? Data()
        buffer.append(data)
        // Bound all unauthenticated input before attempting decryption.
        if buffer.count > ClusterSecureWire.maximumFrameBytes * 2 {
            outgoing[id]?.cancel()
            buffers.removeValue(forKey: id)
            return
        }
        while buffer.count >= 4 {
            let count = buffer.prefix(4).reduce(UInt32(0)) {
                ($0 << 8) | UInt32($1)
            }
            guard count >= 28, count <= ClusterSecureWire.maximumFrameBytes else {
                outgoing[id]?.cancel()
                buffers.removeValue(forKey: id)
                return
            }
            let end = Int(count) + 4
            guard buffer.count >= end else { break }
            let frame = Data(buffer[4..<end])
            buffer.removeSubrange(0..<end)
            guard let node = try? ClusterSecureWire.open(frame, key: key),
                  node.id != nodeID else { continue }
            // Ignore out-of-order frames from old connections or replays.
            if let last = lastSeen[node.id], node.timestamp <= last { continue }
            lastSeen[node.id] = node.timestamp
            if let index = peers.firstIndex(where: { $0.id == node.id }) {
                peers[index] = node
            } else if peers.count < 16 {
                peers.append(node)
            }
        }
        buffers[id] = buffer
    }

    private func tick() {
        guard enabled else { return }
        connectDiscovered()
        for connection in incoming.values { sendSnapshot(to: connection) }
        let cutoff = Date().addingTimeInterval(-60)
        peers.removeAll { $0.timestamp < cutoff }
        lastSeen = lastSeen.filter { $0.value >= cutoff }
    }

    private func sendSnapshot(to connection: NWConnection) {
        guard enabled, let key,
              let data = try? ClusterSecureWire.seal(localNode, key: key) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    /// External tools own simulation start/stop. They may optionally publish
    /// this small JSON file; ChipBar never writes it or launches a process.
    private static func readExternalTasks() -> [ClusterTaskReadout] {
        guard let folder = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first else { return [] }
        let url = folder.appendingPathComponent("ChipBar/cluster-status.json")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = (attributes[.size] as? NSNumber)?.intValue,
              fileSize <= 64 * 1024,
              let data = try? Data(contentsOf: url),
              data.count <= 64 * 1024 else { return [] }
        struct ExternalStatus: Decodable { let tasks: [ClusterTaskReadout] }
        guard let decoded = try? JSONDecoder().decode(ExternalStatus.self, from: data)
        else { return [] }
        return Array(decoded.tasks.prefix(12))
    }

    private static func readKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return item as? Data
    }

    private static func storeKey(_ data: Data) -> Bool {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(identity as CFDictionary)
        var entry = identity
        entry[kSecValueData as String] = data
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(entry as CFDictionary, nil) == errSecSuccess
    }
}
