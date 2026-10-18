import BlazePodProtocol
import CoreBluetooth
import Foundation

enum UUIDs {
    static let touchService = CBUUID(string: PodGATT.touchService)
    static let touch = CBUUID(string: PodGATT.touchCharacteristic)
    static let lightService = CBUUID(string: PodGATT.lightService)
    static let light = CBUUID(string: PodGATT.lightCharacteristic)
    static let nusService = CBUUID(string: PodGATT.nusService)
    static let nusRX = CBUUID(string: PodGATT.nusRX)
    static let nusTX = CBUUID(string: PodGATT.nusTX)
    static let batteryService = CBUUID(string: PodGATT.batteryService)
    static let battery = CBUUID(string: PodGATT.batteryLevel)
    static let deviceInfo = CBUUID(string: PodGATT.deviceInfo)
    static let model = CBUUID(string: PodGATT.modelNumber)
    static let serial = CBUUID(string: PodGATT.serialNumber)
    static let firmware = CBUUID(string: PodGATT.firmwareRevision)
}

/// Mirrors `je.i.f`.
public enum PodLinkState: Sendable { case disconnected, connected, ready, error }
/// Mirrors `je.i.b` – what the app *wants* for this pod.
public enum PodConnectionIntent: Sendable { case notSet, connect, disconnectAndClose }

public protocol BlazePodDelegate: AnyObject {
    func pod(_ pod: BlazePod, didHit reactionMs: Int)
    func podDidChange(_ pod: BlazePod)
}

/// One physical pod (`je.i` model + `je.q` GATT manager).
/// All mutation happens on the owning `PodManager.queue`.
public final class BlazePod: NSObject {
    public let id: UUID
    public internal(set) var name: String
    public internal(set) var rssi: Int = 0
    public internal(set) var lastSeen: Date = .distantPast
    public internal(set) var isVisible = true
    public internal(set) var advertisement: PodAdvertisement?
    public internal(set) var linkState: PodLinkState = .disconnected { didSet { delegate?.podDidChange(self) } }
    public internal(set) var intent: PodConnectionIntent = .notSet
    public internal(set) var battery: Int?
    public internal(set) var charger: ChargerStatus?
    public internal(set) var info = PodInfo()
    public internal(set) var connectAttempts = 0
    /// The user disconnected this pod; global auto-connect leaves it alone until it is connected again.
    public internal(set) var userDisconnected = false

    public internal(set) var isLightOn = false
    public internal(set) var currentColor: PodColor?
    public internal(set) var lastColor: PodColor?

    public weak var delegate: BlazePodDelegate?

    let peripheral: CBPeripheral
    let ops: GATTOperationQueue
    unowned let manager: PodManager

    private var lightStart: Date?
    private var offOnHit = false
    private var lastOffAt: Date?
    private var autoOffWork: DispatchWorkItem?

    init(peripheral: CBPeripheral, name: String, manager: PodManager) {
        self.id = peripheral.identifier
        self.peripheral = peripheral
        self.name = name
        self.manager = manager
        self.ops = GATTOperationQueue(queue: manager.queue)
        super.init()
        peripheral.delegate = self
        ops.peripheral = peripheral
    }

    public var isReady: Bool { linkState == .ready && intent == .connect }
    var elapsedMs: Int { lightStart.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0 }

    // MARK: Light API (je.i h0 / i0 / k0 / V)

    /// Turn the light on. `offOnHit` lets the pod switch itself off on touch (fw >= 3.2 only).
    public func lightOn(_ color: PodColor, offOnHit: Bool = false) {
        manager.queue.async { [self] in
            guard linkState == .ready else { return }
            autoOffWork?.cancel()
            let useOffOnHit = offOnHit && info.supportsTouchV2
            sendColor(color, offOnHit: useOffOnHit)
            setLocal(on: true, color: color, offOnHit: useOffOnHit)
        }
    }

    /// Turn on and automatically off after `duration` (used by "identify pod", 30 s).
    public func lightOn(_ color: PodColor, for duration: TimeInterval) {
        lightOn(color)
        manager.queue.async { [self] in
            let work = DispatchWorkItem { [weak self] in self?.lightOffNow() }
            autoOffWork = work
            manager.queue.asyncAfter(deadline: .now() + duration, execute: work)
        }
    }

    public func lightOff() { manager.queue.async { [self] in lightOffNow() } }

    func lightOffNow() {
        guard isLightOn else { return }
        autoOffWork?.cancel()
        write(UUIDs.lightService, UUIDs.light, LightCommand.off)
        setLocal(on: false, color: nil, offOnHit: false)
        lastOffAt = Date()
    }

    /// Re-sends the current colour, e.g. after the brightness changed. Runs on the manager queue.
    func reapplyLight() {
        guard linkState == .ready, isLightOn, let color = currentColor else { return }
        sendColor(color, offOnHit: offOnHit)
    }

    private func sendColor(_ color: PodColor, offOnHit: Bool) {
        let payload = LightCommand.payload(RGBLevel(color, manager.lightIntensity), offOnHit: offOnHit)
        write(UUIDs.lightService, UUIDs.light, payload)
        if LightGlitchGuard.needsResend(previous: lastColor, next: color, lastOffAt: lastOffAt) {
            resend(color, payload, remaining: LightGlitchGuard.maxResends)
        }
        lastColor = color
    }

    private func resend(_ color: PodColor, _ payload: [UInt8], remaining: Int) {
        guard remaining > 0 else { return }
        manager.queue.asyncAfter(deadline: .now() + LightGlitchGuard.resendDelay) { [self] in
            guard isLightOn, currentColor == color else { return }
            write(UUIDs.lightService, UUIDs.light, payload)
            resend(color, payload, remaining: remaining - 1)
        }
    }

    private func setLocal(on: Bool, color: PodColor?, offOnHit: Bool) {
        isLightOn = on
        currentColor = color
        self.offOnHit = offOnHit
        lightStart = on ? Date() : nil
        delegate?.podDidChange(self)
    }

    // MARK: Pod commands

    /// Blink red 3× (100 ms on / 200 ms off) then power the pod down (`je.i.n` + `je.p0.k`).
    public func shutDown() {
        manager.queue.async { [self] in
            func blink(_ n: Int) {
                guard n < 3 else {
                    uart(.shutdownPrepare)
                    uart(.shutdownReset)
                    manager.queue.asyncAfter(deadline: .now() + 0.1) { self.manager.drop(self) }
                    return
                }
                lightOn(.red)
                manager.queue.asyncAfter(deadline: .now() + 0.1) {
                    self.lightOffNow()
                    self.manager.queue.asyncAfter(deadline: .now() + 0.2) { blink(n + 1) }
                }
            }
            blink(0)
        }
    }

    func uart(_ cmd: UARTCommand) { write(UUIDs.nusService, UUIDs.nusRX, cmd.payload) }

    func write(_ s: CBUUID, _ c: CBUUID, _ bytes: [UInt8]) {
        manager.log("\(name) TX \(c.uuidString.prefix(8)) \(bytes.hex)")
        ops.enqueue(.write(service: s, characteristic: c, value: Data(bytes)))
    }

    // MARK: Session bring-up (je.e0 READY branch)

    func didBecomeReady() {
        if let ad = advertisement {
            manager.log("\(name) auth: key=\(ad.key.hex) version=\(ad.version)")
            uart(.authenticate(PodAuthenticator.response(key: ad.key, version: ad.version)))
        }
        ops.enqueue(.enableNotify(service: UUIDs.batteryService, characteristic: UUIDs.battery))
        ops.enqueue(.enableNotify(service: UUIDs.touchService, characteristic: UUIDs.touch))
        ops.enqueue(.enableNotify(service: UUIDs.nusService, characteristic: UUIDs.nusTX))
        readBattery()
        manager.queue.asyncAfter(deadline: .now() + 0.5) { [self] in
            guard isReady else { return }
            ops.enqueue(.read(service: UUIDs.deviceInfo, characteristic: UUIDs.model) { [weak self] d in
                self?.info.model = d.map { String(decoding: $0, as: UTF8.self) }
            })
            ops.enqueue(.read(service: UUIDs.deviceInfo, characteristic: UUIDs.firmware) { [weak self] d in
                self?.info.firmwareRaw = d.map { String(decoding: $0, as: UTF8.self) }
            })
            ops.enqueue(.read(service: UUIDs.deviceInfo, characteristic: UUIDs.serial) { [weak self] d in
                guard let self else { return }
                info.serial = d.map { String(decoding: $0, as: UTF8.self) }
                delegate?.podDidChange(self)
            })
        }
    }

    func readBattery() {
        ops.enqueue(.read(service: UUIDs.batteryService, characteristic: UUIDs.battery) { [weak self] d in
            if let b = d?.first { self?.battery = Int(b) }
        })
    }

    func resetSession() {
        ops.clear()
        isLightOn = false
        currentColor = nil
        battery = nil
    }

    // MARK: Notifications

    func handleTouch(_ data: Data) {
        let event = info.supportsTouchV2 ? (TouchEvent(payload: [UInt8](data)) ?? .legacy) : .legacy
        let state = HitFilter.LightState(isOn: isLightOn, offOnHit: offOnHit, elapsedMs: elapsedMs)
        let decision = HitFilter.evaluate(event, state: state)
        manager.log("\(name) RX touch \([UInt8](data).hex) phone=\(state.elapsedMs)ms → \(decision)")
        guard case let .hit(ms, turnOff) = decision else { return }
        if turnOff { setLocal(on: false, color: nil, offOnHit: false) }
        delegate?.pod(self, didHit: ms)
    }

    func handleUART(_ data: Data) {
        manager.log("\(name) RX uart \(UARTEvent(payload: [UInt8](data))) [\([UInt8](data).hex)]")
        switch UARTEvent(payload: [UInt8](data)) {
        case .charger(let s): charger = s; delegate?.podDidChange(self)
        case .authResult, .disconnectReason, .unknown: break // logged/analytics only in the original
        }
    }
}

extension BlazePod: CBPeripheralDelegate {
    public func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return manager.linkFailed(self) }
        p.services?.forEach { p.discoverCharacteristics(nil, for: $0) }
    }

    public func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        // READY once every service has its characteristics (Android: onServicesDiscovered).
        guard linkState == .connected,
              p.services?.allSatisfy({ $0.characteristics != nil }) == true else { return }
        manager.linkReady(self)
    }

    public func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        // CoreBluetooth reports reads and notifications through the same callback.
        if c.isNotifying, let v = c.value {
            switch c.uuid {
            case UUIDs.touch: handleTouch(v)
            case UUIDs.nusTX: handleUART(v)
            case UUIDs.battery: if let b = v.first, b > 0 { battery = Int(b) }
            default: break
            }
        }
        ops.didRead(c, error: error)
    }

    public func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) { ops.didWrite(c) }
    public func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        ops.didUpdateNotificationState(c)
    }
}

extension Array where Element == UInt8 {
    var hex: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}
