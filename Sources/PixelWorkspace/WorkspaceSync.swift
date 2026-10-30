import CryptoKit
import Foundation
import Network

/// Local-network transport. Application payloads are authenticated and encrypted with a shared pairing secret.
final class WorkspaceSync {
    var onRemoteMessage: ((WorkspaceMessage) -> Void)?
    var onStatus: ((String) -> Void)?
    private let queue = DispatchQueue(label: "pixelworkspace.sync", qos: .utility)
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections: [String: NWConnection] = [:]
    private var receiveBuffers: [String: Data] = [:]
    private var peerEndpoints: [String: NWEndpoint] = [:]
    private var key: SymmetricKey?
    private var deviceID = Host.current().localizedName ?? UUID().uuidString
    private var latestSnapshot: DeviceSnapshot?
    private var lastPublished: [String: ProcessRecord] = [:]
    private var initializedPeers = Set<String>()

    func start(pairingCode: String) throws {
        stop()
        let normalized = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 16 else { throw SyncError.weakCode }
        key = SymmetricKey(data: Data(SHA256.hash(data: Data(("PixelWorkspace-v1|" + normalized).utf8))))
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let listener = try NWListener(using: params)
        listener.service = NWListener.Service(name: String(deviceID.prefix(50)), type: "_pixelworkspace._tcp")
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { [weak self] state in self?.onStatus?("同步服务：\(state)") }
        listener.start(queue: queue); self.listener = listener
        let browser = NWBrowser(for: .bonjour(type: "_pixelworkspace._tcp", domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            for result in results {
                if case let .service(name, _, _, _) = result.endpoint, name != self.deviceID { self.peerEndpoints[name] = result.endpoint; self.connect(result.endpoint, name: name) }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in self?.onStatus?("设备发现：\(state)") }
        browser.start(queue: queue); self.browser = browser
    }
    func stop() {
        browser?.cancel(); browser = nil; listener?.cancel(); listener = nil
        queue.sync { connections.values.forEach { $0.cancel() }; connections.removeAll(); receiveBuffers.removeAll(); peerEndpoints.removeAll(); initializedPeers.removeAll(); lastPublished.removeAll(); latestSnapshot = nil; key = nil }
    }
    func publish(_ snapshot: DeviceSnapshot) {
        queue.async {
            self.latestSnapshot = snapshot
            for (name, connection) in self.connections {
                if !self.initializedPeers.contains(name) {
                    self.send(.snapshot(snapshot), to: connection); self.initializedPeers.insert(name)
                    self.lastPublished = Dictionary(snapshot.apps.map { ($0.id, $0) }, uniquingKeysWith: { _, newest in newest })
                    continue
                }
                let current = Dictionary(snapshot.apps.map { ($0.id, $0) }, uniquingKeysWith: { _, newest in newest })
                for (id, record) in current where self.lastPublished[id].map({ !Self.sameState($0, record) }) ?? true { self.send(.upsert(record), to: connection) }
                for old in self.lastPublished.values where current[old.id] == nil { self.send(.remove(deviceID: old.deviceID, pid: old.pid, bundleID: old.bundleID), to: connection) }
                self.lastPublished = current
            }
        }
    }
    private static func sameState(_ a: ProcessRecord, _ b: ProcessRecord) -> Bool {
        a.name == b.name && a.department == b.department && a.isFrontmost == b.isFrontmost && a.cpuPercent == b.cpuPercent && a.memoryBytes == b.memoryBytes
    }
    private func send(_ message: WorkspaceMessage, to connection: NWConnection) {
        guard let data = try? encode(message) else { return }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in if let error { self?.onStatus?("同步发送失败：\(error.localizedDescription)") } })
    }
    private func accept(_ c: NWConnection) { register(c, name: UUID().uuidString) }
    private func connect(_ endpoint: NWEndpoint, name: String) {
        guard connections[name] == nil else { return }
        let c = NWConnection(to: endpoint, using: .tcp); register(c, name: name)
    }
    private func register(_ c: NWConnection, name: String) {
        connections[name] = c
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let self, let c else { return }
            if case .failed = state {
                self.connections.removeValue(forKey: name); self.initializedPeers.remove(name); self.receiveBuffers.removeValue(forKey: name); c.cancel()
                if let endpoint = self.peerEndpoints[name] { self.queue.asyncAfter(deadline: .now() + 3) { self.connect(endpoint, name: name) } }
            }
            if case .cancelled = state { self.connections.removeValue(forKey: name) }
        }
        c.start(queue: queue); receive(on: c, name: name)
        if let snapshot = latestSnapshot { send(.snapshot(snapshot), to: c); initializedPeers.insert(name); lastPublished = Dictionary(snapshot.apps.map { ($0.id, $0) }, uniquingKeysWith: { _, newest in newest }) }
    }
    private func receive(on c: NWConnection, name: String) {
        c.receive(minimumIncompleteLength: 4, maximumLength: 1_048_576) { [weak self, weak c] data, _, done, error in
            guard let self, let c else { return }
            if let data, !data.isEmpty {
                var buffer = self.receiveBuffers[name, default: Data()]; buffer.append(data)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let frame = buffer.prefix(upTo: newline); buffer.removeSubrange(...newline)
                    if let message = self.decode(Data(frame)) { self.onRemoteMessage?(message) }
                }
                if buffer.count > 1_048_576 { buffer.removeAll() }
                self.receiveBuffers[name] = buffer
            }
            if !done && error == nil { self.receive(on: c, name: name) } else { c.cancel() }
        }
    }
    private func encode(_ message: WorkspaceMessage) throws -> Data {
        guard let key else { throw SyncError.notPaired }
        let plain = try JSONEncoder().encode(message)
        let sealed = try AES.GCM.seal(plain, using: key)
        let envelope = WireEnvelope(protocolVersion: 1, nonce: sealed.nonce.withUnsafeBytes { Data($0) }, ciphertext: sealed.ciphertext, tag: sealed.tag)
        var data = try JSONEncoder().encode(envelope); data.append(0x0A); return data
    }
    private func decode(_ data: Data) -> WorkspaceMessage? {
        guard let key,
              let envelope = try? JSONDecoder().decode(WireEnvelope.self, from: data),
              envelope.protocolVersion == 1,
              let nonce = try? AES.GCM.Nonce(data: envelope.nonce),
              let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: envelope.ciphertext, tag: envelope.tag),
              let clear = try? AES.GCM.open(box, using: key) else { return nil }
        return try? JSONDecoder().decode(WorkspaceMessage.self, from: clear)
    }
    enum SyncError: Error { case weakCode, notPaired }
}
