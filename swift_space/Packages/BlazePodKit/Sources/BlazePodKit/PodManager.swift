@_exported import BlazePodProtocol
import CoreBluetooth
import Foundation

public protocol PodManagerDelegate: AnyObject {
    /// Equivalent of the app's LiveData streams (all visible pods / ready pods / summary).
    func podManager(_ m: PodManager, didUpdate pods: [BlazePod])
    func podManager(_ m: PodManager, pod: BlazePod, didHit reactionMs: Int)
    func podManager(_ m: PodManager, bluetoothAvailable: Bool)
    /// A pod that was READY dropped while the app still wanted it.
    func podManager(_ m: PodManager, unexpectedDisconnect pod: BlazePod)
}

/// Persistent pod bookkeeping (`com.blazepod.blazepodcore.repositories.e`).
public protocol PodStore: AnyObject {
    func name(for id: UUID) -> String?
    func setName(_ name: String, for id: UUID)
    func nextNameIndex() -> Int
    var autoConnect: Set<UUID> { get set }
    func setLastConnected(_ date: Date, for id: UUID)
    /// Pods that have been connected at least once ("my pods").
    var knownPods: [UUID] { get }
    func forget(_ id: UUID)
}

/// Singleton-style pod manager (`je.p0`): scanning, discovery, connection policy.
public final class PodManager: NSObject {
    public enum Timing {
        public static let visibilityTimeout: TimeInterval = 30
        public static let retryDelay: TimeInterval = 3
        public static let maxRetries = 10
        public static let reconnectDelay: TimeInterval = 0.3
        public static let chargerPollInterval: TimeInterval = 0.3
        public static let backgroundDisconnect: TimeInterval = 15 * 60
    }

    public weak var delegate: PodManagerDelegate?
    /// Debug hook: raw protocol traffic and state transitions, delivered on the main queue.
    public var logHandler: ((String) -> Void)?
    public let queue = DispatchQueue(label: "pods")
    /// Global brightness. Lit pods are re-sent their colour so the change shows immediately.
    public var intensity: LightIntensity = .max {
        didSet {
            let value = intensity
            queue.async { [self] in
                lightIntensity = value
                pods.values.forEach { $0.reapplyLight() }
            }
        }
    }
    /// Queue-confined copy of `intensity` used when building LED payloads.
    var lightIntensity: LightIntensity = .max

    /// Membership gate (`BPMembershipFeatureType.CONNECT_PODS`): nil = unlimited.
    public var maxConnectedPods: Int? { didSet { queue.async { self.enforcePodLimit() } } }
    /// While a workout is running, backgrounding does not disconnect pods.
    public var workoutActive = false
    /// Connect every pod that is seen (known or new), except ones the user disconnected.
    public var autoConnectAll = false {
        didSet { queue.async { [self] in if autoConnectAll { pods.values.forEach(autoConnectIfWanted) } } }
    }

    private let store: PodStore
    private var central: CBCentralManager!
    private var pods: [UUID: BlazePod] = [:]
    private var visibilityTimers: [UUID: DispatchWorkItem] = [:]
    private var chargerTimer: DispatchSourceTimer?
    private var backgroundWork: DispatchWorkItem?
    private var wantsScan = false

    public init(store: PodStore) {
        self.store = store
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    public var allPods: [BlazePod] { pods.values.filter(\.isVisible).sorted { $0.name < $1.name } }
    public var readyPods: [BlazePod] { pods.values.filter { $0.linkState == .ready }.sorted { $0.name < $1.name } }
    var connectingOrConnected: Int { pods.values.filter { $0.intent == .connect }.count }

    // MARK: Scanning (p0.A / p0.z)

    public func startScanning() {
        queue.async { [self] in
            wantsScan = true
            guard central.state == .poweredOn else { return }
            central.scanForPeripherals(withServices: [UUIDs.touchService],
                                       options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }

    public func stopScanning() {
        queue.async { [self] in wantsScan = false; central.stopScan() }
    }

    // MARK: Connection (je.i.p / q / s)

    /// Returns false when the membership pod limit is reached.
    @discardableResult
    public func connect(_ pod: BlazePod) -> Bool {
        queue.sync { connectNow(pod, resetAttempts: true) }
    }

    public func disconnect(_ pod: BlazePod) {
        queue.async { [self] in
            pod.userDisconnected = true
            close(pod)
        }
    }

    public func disconnectAll() {
        queue.async { [self] in pods.values.filter { $0.intent == .connect }.forEach(disconnect) }
    }

    /// Disconnects and removes the pod from "my pods".
    public func forget(_ id: UUID) {
        queue.async { [self] in
            store.forget(id)
            store.autoConnect.remove(id)
            if let pod = pods[id] { pod.userDisconnected = true; close(pod) }
            publish()
        }
    }

    private func close(_ pod: BlazePod) {
        pod.intent = .disconnectAndClose
        pod.resetSession()
        central.cancelPeripheralConnection(pod.peripheral)
    }

    /// Removes a powered-down pod from the registry; it is re-created when it advertises again.
    func drop(_ pod: BlazePod) {
        close(pod)
        pods[pod.id] = nil
        publish()
    }

    private func autoConnectIfWanted(_ pod: BlazePod) {
        guard pod.intent != .connect, pod.isVisible, !pod.userDisconnected,
              autoConnectAll || store.autoConnect.contains(pod.id) else { return }
        connectNow(pod, resetAttempts: true)
    }

    @discardableResult
    func connectNow(_ pod: BlazePod, resetAttempts: Bool) -> Bool {
        if pod.intent != .connect, let limit = maxConnectedPods, connectingOrConnected >= limit { return false }
        if resetAttempts { pod.connectAttempts = 0 }
        pod.userDisconnected = false
        log("\(pod.name): connect (attempt \(pod.connectAttempts))")
        pod.intent = .connect
        if pod.linkState == .disconnected || pod.linkState == .error {
            central.connect(pod.peripheral, options: nil)
        }
        return true
    }

    private func enforcePodLimit() {
        guard let limit = maxConnectedPods else { return }
        while connectingOrConnected > limit {
            let candidates = pods.values.filter { $0.intent == .connect }
            let victim = candidates.first { $0.linkState != .ready } ?? candidates.last!
            victim.intent = .disconnectAndClose
            central.cancelPeripheralConnection(victim.peripheral)
        }
    }

    // MARK: Link state machine (je.e0 msg 1)

    func linkReady(_ pod: BlazePod) {
        pod.linkState = .ready
        log("\(pod.name): READY")
        guard pod.intent == .connect else { return disconnect(pod) }
        pod.didBecomeReady()
        store.setLastConnected(Date(), for: pod.id)
        publish()
    }

    func linkFailed(_ pod: BlazePod) {
        let wasReady = pod.linkState == .ready
        log("\(pod.name): link error, retry in \(Timing.retryDelay)s")
        pod.linkState = .error
        pod.resetSession()
        if wasReady { delegate?.podManager(self, unexpectedDisconnect: pod) }
        guard pod.intent == .connect else { return publish() }
        queue.asyncAfter(deadline: .now() + Timing.retryDelay) { [self] in
            guard pod.intent == .connect else { return }
            if pod.connectAttempts < Timing.maxRetries {
                pod.connectAttempts += 1
                connectNow(pod, resetAttempts: false)
            } else {
                pod.intent = .disconnectAndClose
                armVisibilityTimer(pod)
            }
            publish()
        }
        publish()
    }

    // MARK: Charger polling (p0.J – "chgs" every 300 ms)

    public func startChargerPolling() {
        queue.async { [self] in
            chargerTimer?.cancel()
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: Timing.chargerPollInterval)
            t.setEventHandler { [weak self] in
                self?.readyPods.filter { $0.advertisement != nil }.forEach { $0.uart(.chargerStatus) }
            }
            t.resume()
            chargerTimer = t
        }
    }

    public func stopChargerPolling() { queue.async { self.chargerTimer?.cancel(); self.chargerTimer = nil } }

    // MARK: App lifecycle (je.j + DisconnectJobService)

    public func appDidEnterBackground() {
        queue.async { [self] in
            guard !workoutActive else { return }
            central.stopScan()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                pods.values.filter { $0.intent == .connect }.forEach(close)
            }
            backgroundWork = work
            queue.asyncAfter(deadline: .now() + Timing.backgroundDisconnect, execute: work)
        }
    }

    public func appWillEnterForeground() {
        queue.async { [self] in backgroundWork?.cancel(); backgroundWork = nil }
        startScanning()
    }

    // MARK: Helpers

    private func armVisibilityTimer(_ pod: BlazePod) {
        visibilityTimers[pod.id]?.cancel()
        let work = DispatchWorkItem { [weak self, weak pod] in
            guard let self, let pod, pod.intent != .connect else { return }
            pod.isVisible = false
            publish()
        }
        visibilityTimers[pod.id] = work
        queue.asyncAfter(deadline: .now() + Timing.visibilityTimeout, execute: work)
    }

    private func podName(for id: UUID) -> String {
        if let n = store.name(for: id) { return n }
        let n = String(format: "Pod %03d", store.nextNameIndex())
        store.setName(n, for: id)
        return n
    }

    func log(_ message: @autoclosure () -> String) {
        guard let handler = logHandler else { return }
        let m = message()
        DispatchQueue.main.async { handler(m) }
    }

    private func publish() {
        let list = allPods
        DispatchQueue.main.async { self.delegate?.podManager(self, didUpdate: list) }
    }
}

extension PodManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ c: CBCentralManager) {
        let on = c.state == .poweredOn
        DispatchQueue.main.async { self.delegate?.podManager(self, bluetoothAvailable: on) }
        if on {
            if wantsScan { startScanning() }
        } else {
            pods.values.forEach { $0.linkState = .disconnected; $0.resetSession() }
            publish()
        }
    }

    public func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                               advertisementData ad: [String: Any], rssi: NSNumber) {
        let pod: BlazePod
        if let existing = pods[p.identifier] {
            pod = existing
        } else {
            pod = BlazePod(peripheral: p, name: podName(for: p.identifier), manager: self)
            pod.delegate = self
            pods[p.identifier] = pod
        }
        pod.rssi = rssi.intValue
        pod.lastSeen = Date()
        if !pod.isVisible { pod.isVisible = true }
        if let data = ad[CBAdvertisementDataManufacturerDataKey] as? Data, let parsed = PodAdvertisement(manufacturerData: data) {
            pod.advertisement = parsed
            if pod.battery == nil { pod.battery = parsed.batteryPercent }
        }
        armVisibilityTimer(pod)
        autoConnectIfWanted(pod)
        publish()
    }

    public func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        guard let pod = pods[p.identifier] else { return }
        pod.linkState = .connected
        log("\(pod.name): CONNECTED, discovering services")
        guard pod.intent == .connect else { return c.cancelPeripheralConnection(p) }
        p.discoverServices(nil)
    }

    public func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        pods[p.identifier].map(linkFailed)
    }

    public func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard let pod = pods[p.identifier] else { return }
        if error != nil { return linkFailed(pod) }
        let wasReady = pod.linkState == .ready
        log("\(pod.name): DISCONNECTED")
        pod.linkState = .disconnected
        pod.resetSession()
        if wasReady && pod.intent == .connect { delegate?.podManager(self, unexpectedDisconnect: pod) }
        if pod.intent == .connect {
            queue.asyncAfter(deadline: .now() + Timing.reconnectDelay) { [self] in
                if pod.intent == .connect { connectNow(pod, resetAttempts: false) }
            }
        }
        publish()
    }
}

extension PodManager: BlazePodDelegate {
    public func pod(_ pod: BlazePod, didHit reactionMs: Int) {
        DispatchQueue.main.async { self.delegate?.podManager(self, pod: pod, didHit: reactionMs) }
    }
    public func podDidChange(_ pod: BlazePod) { publish() }
}

/// Simple `UserDefaults` store using the original preference semantics.
public final class UserDefaultsPodStore: PodStore {
    private let d: UserDefaults
    public init(_ d: UserDefaults = .standard) { self.d = d }

    private var names: [String: String] {
        get { d.dictionary(forKey: "key_pod_names") as? [String: String] ?? [:] }
        set { d.set(newValue, forKey: "key_pod_names") }
    }
    public func name(for id: UUID) -> String? { names[id.uuidString] }
    public func setName(_ name: String, for id: UUID) { names[id.uuidString] = name }
    public func nextNameIndex() -> Int {
        let i = d.integer(forKey: "key_pod_names_index") + 1
        d.set(i, forKey: "key_pod_names_index")
        return i
    }
    public var autoConnect: Set<UUID> {
        get { Set((d.stringArray(forKey: "key_connect_automatically_pods") ?? []).compactMap(UUID.init)) }
        set { d.set(newValue.map(\.uuidString), forKey: "key_connect_automatically_pods") }
    }
    public func setLastConnected(_ date: Date, for id: UUID) {
        d.set(date, forKey: "pod_last_connected_\(id.uuidString)")
        if !knownPods.contains(id) { d.set((knownPods + [id]).map(\.uuidString), forKey: "key_known_pods") }
    }
    public func lastConnected(for id: UUID) -> Date? { d.object(forKey: "pod_last_connected_\(id.uuidString)") as? Date }
    public var knownPods: [UUID] { (d.stringArray(forKey: "key_known_pods") ?? []).compactMap(UUID.init) }
    public func forget(_ id: UUID) {
        d.set(knownPods.filter { $0 != id }.map(\.uuidString), forKey: "key_known_pods")
        d.removeObject(forKey: "pod_last_connected_\(id.uuidString)")
    }
}
