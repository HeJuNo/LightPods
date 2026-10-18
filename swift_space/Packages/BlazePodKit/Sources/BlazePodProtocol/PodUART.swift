import Foundation

/// ASCII commands written to NUS RX (`6E400002`).
public enum UARTCommand: Equatable, Sendable {
    /// Authentication response, see `PodAuthenticator`.
    case authenticate([UInt8])
    /// Poll charger status; answered with `chgs=` on NUS TX. App polls every 300 ms.
    case chargerStatus
    /// First half of the shutdown sequence.
    case shutdownPrepare
    /// Second half of the shutdown sequence (pod powers off).
    case shutdownReset

    public var payload: [UInt8] {
        switch self {
        case .authenticate(let r): return Array("sea".utf8) + r
        case .chargerStatus: return Array("chgs".utf8)
        case .shutdownPrepare: return Array("tp7".utf8)
        case .shutdownReset: return Array("xrs".utf8)
        }
    }
}

public enum ChargerStatus: UInt16, Sendable {
    case noCharger = 0, powerNotCharging = 1, charging = 2, fullyCharged = 3, powerNoBattery = 4
    public var isOnCharger: Bool { self != .noCharger }
}

/// Notifications on NUS TX (`6E400003`): 5-char ASCII prefix + UInt16 LE at offset 5.
public enum UARTEvent: Equatable, Sendable {
    case charger(ChargerStatus?)
    /// `rsea=` – auth result code (only logged by the app).
    case authResult(UInt16)
    /// `disf=` – disconnect reason/fault code (forwarded to analytics as an event).
    case disconnectReason(UInt16)
    case unknown(String)

    public init(payload: [UInt8]) {
        let prefix = String(decoding: payload.prefix(5), as: UTF8.self)
        let value: UInt16? = payload.count >= 7 ? UInt16(payload[5]) | UInt16(payload[6]) << 8 : nil
        switch (prefix, value) {
        case ("chgs=", let v?): self = .charger(ChargerStatus(rawValue: v))
        case ("rsea=", let v?): self = .authResult(v)
        case ("disf=", let v?): self = .disconnectReason(v)
        default: self = .unknown(String(decoding: payload, as: UTF8.self))
        }
    }
}
