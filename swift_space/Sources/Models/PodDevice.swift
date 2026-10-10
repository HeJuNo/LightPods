import Foundation
import CoreBluetooth
import SwiftUI

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
    var lastReactionTimeMs: UInt32?
    var selectedColor: PodColor = .white

    // BLE characteristics
    var uartRXCharacteristic: CBCharacteristic?
    var colorCharacteristic: CBCharacteristic?
    var tapCharacteristic: CBCharacteristic?

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
}

enum PodColor: String, CaseIterable, Identifiable {
    case red, green, blue, white, yellow, purple, orange

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    /// Returns bytes in [G, B, R] order for the BlazePod color characteristic
    var gbrBytes: [UInt8] {
        switch self {
        case .red:    return [0x00, 0x00, 0xFF]
        case .green:  return [0xFF, 0x00, 0x00]
        case .blue:   return [0x00, 0xFF, 0x00]
        case .white:  return [0xFF, 0xFF, 0xFF]
        case .yellow: return [0xFF, 0x00, 0xFF]
        case .purple: return [0x00, 0xFF, 0xFF]
        case .orange: return [0x80, 0x00, 0xFF]
        }
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
        }
    }
}
