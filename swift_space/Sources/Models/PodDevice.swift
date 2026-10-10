import Foundation
import CoreBluetooth
import SwiftUI

// MARK: - Tap Event

/// State reported by the pod when tapped
enum TapState: UInt8 {
    case off      = 0x00  // tap on a pod that was off
    case litStay  = 0x21  // tap on a lit pod that stayed lit
    case litOff   = 0x25  // tap on a lit pod that turned off

    var hitLitPod: Bool {
        self == .litStay || self == .litOff
    }
}

/// A decoded tap notification from a BlazePod
struct TapEvent {
    let state: TapState
    let elapsedMs: UInt32  // ms since the pod was last lit (hardware-timed)
    let raw: Data          // full payload

    var hitLitPod: Bool { state.hitLitPod }

    init?(data: Data) {
        guard data.count >= 5 else { return nil }
        guard let st = TapState(rawValue: data[0]) else { return nil }
        self.state = st
        self.elapsedMs = UInt32(data[1])
            | (UInt32(data[2]) << 8)
            | (UInt32(data[3]) << 16)
            | (UInt32(data[4]) << 24)
        self.raw = data
    }
}

// MARK: - Pod Color

enum PodColor: String, CaseIterable, Identifiable, Sendable {
    case red, green, blue, white, yellow, purple, orange, cyan, off

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var rgb: (r: UInt8, g: UInt8, b: UInt8) {
        switch self {
        case .red:    return (255, 0, 0)
        case .green:  return (0, 255, 0)
        case .blue:   return (0, 0, 255)
        case .white:  return (255, 255, 255)
        case .yellow: return (255, 255, 0)
        case .purple: return (255, 0, 255)
        case .orange: return (255, 128, 0)
        case .cyan:   return (0, 255, 255)
        case .off:    return (0, 0, 0)
        }
    }

    /// Bytes in [G, B, R] order for the BlazePod color characteristic
    var gbrBytes: [UInt8] {
        let c = rgb
        return [c.g, c.b, c.r]
    }

    var swiftUIColor: Color {
        switch self {
        case .red:    return .red
        case .green:  return .green
        case .blue:   return .blue
        case .white:  return .white
        case .yellow: return .yellow
        case .purple: return .purple
        case .orange: return .orange
        case .cyan:   return .cyan
        case .off:    return Color(.systemGray4)
        }
    }

    /// All colors except .off for UI selectors
    static var selectableColors: [PodColor] {
        allCases.filter { $0 != .off }
    }
}

// MARK: - Pod Device

/// Represents a discovered or connected BlazePod (runtime BLE state)
@Observable
class PodDevice: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    var name: String
    var rssi: Int
    var manufacturerData: Data?

    enum ConnectionState: String {
        case disconnected = "Disconnected"
        case connecting = "Connecting"
        case connected = "Connected"
        case authenticating = "Authenticating"
        case authenticated = "Authenticated"
        case error = "Error"
    }

    var connectionState: ConnectionState = .disconnected
    var errorMessage: String?
    var lastTapEvent: TapEvent?
    var selectedColor: PodColor = .white

    // BLE characteristics
    var uartRXCharacteristic: CBCharacteristic?
    var colorCharacteristic: CBCharacteristic?
    var tapCharacteristic: CBCharacteristic?

    // Device information (read from BLE DIS / Battery services)
    var batteryLevel: Int?          // 0-100 %
    var firmwareRevision: String?
    var hardwareRevision: String?
    var softwareRevision: String?
    var bleSerialNumber: String?    // serial from Device Information Service
    var modelNumber: String?
    var manufacturerName: String?

    init(peripheral: CBPeripheral, name: String?, rssi: Int, manufacturerData: Data?) {
        self.id = peripheral.identifier
        self.peripheral = peripheral
        self.name = name ?? "BlazePod"
        self.rssi = rssi
        self.manufacturerData = manufacturerData
    }

    /// Manufacturer data as hex string for persistence
    var manufacturerDataHex: String? {
        manufacturerData?.map { String(format: "%02X", $0) }.joined()
    }

    /// Last reaction time in ms (convenience)
    var lastReactionTimeMs: UInt32? {
        lastTapEvent?.elapsedMs
    }

    /// Battery icon name based on level
    var batteryIconName: String {
        guard let level = batteryLevel else { return "battery.0percent" }
        switch level {
        case 75...100: return "battery.100percent"
        case 50..<75: return "battery.75percent"
        case 25..<50: return "battery.50percent"
        case 1..<25: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    var batteryColor: Color {
        guard let level = batteryLevel else { return .gray }
        if level > 50 { return .green }
        if level > 20 { return .yellow }
        return .red
    }
}
