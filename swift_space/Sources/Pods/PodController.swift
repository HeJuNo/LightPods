import BlazePodKit
import SwiftUI

struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let text: String
}

struct HitEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let podID: UUID
    let podName: String
    let reactionMs: Int
}

/// A pod in "my pods": known from an earlier connection, nearby or not.
struct KnownPod: Identifiable {
    let id: UUID
    let name: String
    let pod: BlazePod?
    let lastConnected: Date?
}

/// Bridges `PodManager` delegate callbacks (delivered on the main queue) into SwiftUI state.
/// `BlazePod` is a reference type mutated on the kit's queue; views read it on refresh.
final class PodController: ObservableObject {
    @Published private(set) var pods: [BlazePod] = []
    @Published private(set) var bluetoothOn = false
    @Published private(set) var isScanning = false
    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var hits: [HitEntry] = []
    @Published private(set) var knownIDs: [UUID]
    @Published var verboseLog = true

    @Published var autoConnectAll: Bool {
        didSet {
            UserDefaults.standard.set(autoConnectAll, forKey: Keys.autoConnectAll)
            manager.autoConnectAll = autoConnectAll
            append("Auto-connect \(autoConnectAll ? "on" : "off")")
        }
    }
    @Published var intensity: LightIntensity {
        didSet {
            manager.intensity = intensity
            UserDefaults.standard.set(intensity.rawValue, forKey: Keys.intensity)
        }
    }
    @Published var chargerPolling = false {
        didSet { chargerPolling ? manager.startChargerPolling() : manager.stopChargerPolling() }
    }

    let store = UserDefaultsPodStore()
    let manager: PodManager
    /// Hit consumer of the running drill.
    var hitObserver: ((BlazePod, Int) -> Void)?

    private static let maxLogEntries = 2000
    private enum Keys {
        static let autoConnectAll = "lightpods.autoConnectAll"
        static let intensity = "lightpods.intensity"
    }

    init() {
        let defaults = UserDefaults.standard
        manager = PodManager(store: store)
        knownIDs = store.knownPods
        autoConnectAll = defaults.object(forKey: Keys.autoConnectAll) as? Bool ?? true
        intensity = defaults.string(forKey: Keys.intensity).flatMap(LightIntensity.init) ?? .max
        manager.delegate = self
        manager.intensity = intensity
        manager.autoConnectAll = autoConnectAll
        manager.logHandler = { [weak self] in self?.append($0, verbose: true) }
    }

    var readyPods: [BlazePod] { pods.filter(\.isReady) }
    /// Pods a drill can use (simulated in demo mode).
    var availablePodCount: Int { Demo.isOn ? 24 : readyPods.count }
    var connectingPods: [BlazePod] { pods.filter { $0.intent == .connect && !$0.isReady } }

    func pod(_ id: UUID) -> BlazePod? { pods.first { $0.id == id } }

    /// Pods connected before, in the order they were first added, plus any connected right now.
    var myPods: [KnownPod] {
        var ids = knownIDs
        for pod in pods where pod.intent == .connect && !ids.contains(pod.id) { ids.append(pod.id) }
        return ids.map { id in
            let pod = pod(id)
            return KnownPod(id: id, name: pod?.name ?? store.name(for: id) ?? "Pod",
                            pod: pod, lastConnected: store.lastConnected(for: id))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Pods in range that were never added.
    var nearbyPods: [BlazePod] {
        pods.filter { !knownIDs.contains($0.id) && $0.intent != .connect }
    }

    // MARK: Actions

    func setScanning(_ on: Bool) {
        on ? manager.startScanning() : manager.stopScanning()
        isScanning = on
        append(on ? "Scan started" : "Scan stopped")
    }

    func toggleConnection(_ pod: BlazePod) {
        if pod.intent == .connect {
            manager.disconnect(pod)
        } else {
            connect(pod)
        }
    }

    func connect(_ pod: BlazePod) {
        if !manager.connect(pod) { append("\(pod.name): pod limit reached") }
    }

    func forget(_ id: UUID) {
        manager.forget(id)
        knownIDs.removeAll { $0 == id }
    }

    func connectAll() { pods.filter { $0.intent != .connect }.forEach(connect) }
    func disconnectAll() { manager.disconnectAll() }
    func allOff() { readyPods.forEach { $0.lightOff() } }
    func identifyAll() { readyPods.forEach { $0.lightOn(.default, for: 30) } }

    /// Lights a pod for a few seconds so it can be found.
    func identify(_ pod: BlazePod) { pod.lightOn(.lightBlue, for: 3) }

    /// Pods a drill will use, in station order: the chosen pods that are connected first,
    /// then the other connected pods by name.
    func assignedPods(count: Int, selection: [UUID]) -> [BlazePod] {
        let ready = readyPods
        let chosen = selection.compactMap { id in ready.first { $0.id == id } }
        let rest = ready.filter { !selection.contains($0.id) }
        return Array((chosen + rest).prefix(count))
    }

    /// Blinks each pod three times in its colour (e.g. one colour per station).
    func flash(_ pods: [(BlazePod, PodColor)], times: Int = 3) {
        for i in 0..<times {
            let on = Double(i) * 0.6
            DispatchQueue.main.asyncAfter(deadline: .now() + on) {
                pods.forEach { $0.0.lightOn($0.1) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + on + 0.35) {
                pods.forEach { $0.0.lightOff() }
            }
        }
    }

    func setMaxPods(_ limit: Int?) {
        manager.maxConnectedPods = limit
        append("Pod limit: \(limit.map(String.init) ?? "unlimited")")
    }

    func clearLog() { log.removeAll() }

    var logText: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withTime, .withFractionalSeconds, .withColonSeparatorInTime]
        return log.map { "\(f.string(from: $0.date)) \($0.text)" }.joined(separator: "\n")
    }

    private func append(_ text: String, verbose: Bool = false) {
        guard !verbose || verboseLog else { return }
        log.append(LogEntry(text: text))
        if log.count > Self.maxLogEntries { log.removeFirst(log.count - Self.maxLogEntries) }
    }
}

extension PodController: PodManagerDelegate {
    func podManager(_ m: PodManager, didUpdate pods: [BlazePod]) {
        self.pods = pods
        let known = store.knownPods
        if known != knownIDs { knownIDs = known }
    }

    func podManager(_ m: PodManager, pod: BlazePod, didHit reactionMs: Int) {
        hits.insert(HitEntry(podID: pod.id, podName: pod.name, reactionMs: reactionMs), at: 0)
        if hits.count > 200 { hits.removeLast() }
        append("HIT \(pod.name) \(reactionMs) ms")
        hitObserver?(pod, reactionMs)
    }

    func podManager(_ m: PodManager, bluetoothAvailable: Bool) {
        bluetoothOn = bluetoothAvailable
        append("Bluetooth \(bluetoothAvailable ? "on" : "unavailable")")
    }

    func podManager(_ m: PodManager, unexpectedDisconnect pod: BlazePod) {
        append("Unexpected disconnect: \(pod.name)")
    }
}

// MARK: Display helpers

extension BlazePod {
    var batteryLevel: Int? { battery ?? advertisement?.batteryPercent }
    var isCharging: Bool { charger?.isOnCharger == true || advertisement?.isCharging == true }

    var statusText: String {
        if isReady { return "Connected" }
        if intent == .connect {
            return connectAttempts > 0 ? "Connecting… (retry \(connectAttempts))" : "Connecting…"
        }
        if linkState == .error { return "Connection failed" }
        return isVisible ? "Nearby" : "Not nearby"
    }

    var statusColor: Color {
        if isReady { return .green }
        if intent == .connect { return .orange }
        if linkState == .error { return .red }
        return .secondary
    }

    /// 0...3 signal bars from RSSI.
    var signalBars: Int {
        switch rssi {
        case -65...0: 3
        case -80 ..< -65: 2
        case -95 ..< -80: 1
        default: 0
        }
    }
}

extension PodLinkState {
    var title: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connected: "Connected"
        case .ready: "Ready"
        case .error: "Error"
        }
    }
}

extension ChargerStatus {
    var title: String {
        switch self {
        case .noCharger: "Not on charger"
        case .powerNotCharging: "Power, not charging"
        case .charging: "Charging"
        case .fullyCharged: "Fully charged"
        case .powerNoBattery: "Power, no battery"
        }
    }
}

extension Array where Element == UInt8 {
    var hexString: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}
