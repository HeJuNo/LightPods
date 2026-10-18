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

/// Bridges `PodManager` delegate callbacks (delivered on the main queue) into SwiftUI state.
/// `BlazePod` is a reference type mutated on the kit's queue; views read it on refresh,
/// which is good enough for a test harness.
final class PodController: ObservableObject {
    @Published private(set) var pods: [BlazePod] = []
    @Published private(set) var bluetoothOn = false
    @Published private(set) var isScanning = false
    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var hits: [HitEntry] = []
    @Published private(set) var autoConnect: Set<UUID>
    @Published var verboseLog = true

    @Published var intensity: LightIntensity = .max {
        didSet { manager.intensity = intensity }
    }
    @Published var chargerPolling = false {
        didSet { chargerPolling ? manager.startChargerPolling() : manager.stopChargerPolling() }
    }

    let store = UserDefaultsPodStore()
    let manager: PodManager
    /// Extra hit consumer (reaction test).
    var hitObserver: ((BlazePod, Int) -> Void)?

    private static let maxLogEntries = 2000

    init() {
        manager = PodManager(store: store)
        autoConnect = store.autoConnect
        manager.delegate = self
        manager.logHandler = { [weak self] in self?.append($0, verbose: true) }
    }

    var readyPods: [BlazePod] { pods.filter(\.isReady) }

    func pod(_ id: UUID) -> BlazePod? { pods.first { $0.id == id } }

    // MARK: Actions

    func setScanning(_ on: Bool) {
        on ? manager.startScanning() : manager.stopScanning()
        isScanning = on
        append(on ? "Scan started" : "Scan stopped")
    }

    func toggleConnection(_ pod: BlazePod) {
        if pod.intent == .connect {
            manager.disconnect(pod)
        } else if !manager.connect(pod) {
            append("\(pod.name): pod limit reached")
        }
    }

    func connectAll() { pods.filter { $0.intent != .connect }.forEach { _ = manager.connect($0) } }
    func disconnectAll() { manager.disconnectAll() }
    func allOff() { readyPods.forEach { $0.lightOff() } }
    func identifyAll() { readyPods.forEach { $0.lightOn(.default, for: 30) } }

    func setAutoConnect(_ pod: BlazePod, _ on: Bool) {
        if on { autoConnect.insert(pod.id) } else { autoConnect.remove(pod.id) }
        store.autoConnect = autoConnect
    }

    func setMaxPods(_ limit: Int?) {
        manager.maxConnectedPods = limit
        append("Pod limit: \(limit.map(String.init) ?? "unlimited")")
    }

    func clearLog() { log.removeAll() }
    func clearHits() { hits.removeAll() }

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
    }

    func podManager(_ m: PodManager, pod: BlazePod, didHit reactionMs: Int) {
        hits.insert(HitEntry(podID: pod.id, podName: pod.name, reactionMs: reactionMs), at: 0)
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

extension PodColor {
    var swatch: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .lightBlue: .cyan
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .random: .gray
        }
    }

    var title: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
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

    var color: Color {
        switch self {
        case .disconnected: .gray
        case .connected: .yellow
        case .ready: .green
        case .error: .red
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
