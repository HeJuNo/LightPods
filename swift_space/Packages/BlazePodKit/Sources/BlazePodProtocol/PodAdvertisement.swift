import Foundation

/// Manufacturer-specific advertisement payload (6 bytes after the company ID).
///
///     byte 0      : bit0 = charger connected, bits1..7 = battery %
///     byte 1      : "version" – seeds the auth polynomial
///     bytes 2...5 : 4-byte challenge ("advertise key")
///
/// Source: scan callback `je.y.onScanResult`, model `je.k` ("AdvertiseData").
public struct PodAdvertisement: Equatable, Sendable {
    public let batteryPercent: Int
    public let isCharging: Bool
    public let version: Int8
    public let key: [UInt8]

    /// Parse the 6-byte payload (company ID already stripped).
    public init?(payload: [UInt8]) {
        guard payload.count == 6 else { return nil }
        batteryPercent = Int((payload[0] >> 1) & 0x7F)
        isCharging = payload[0] & 0x01 == 1
        version = Int8(bitPattern: payload[1])
        key = Array(payload[2...5])
    }

    /// Parse CoreBluetooth's `CBAdvertisementDataManufacturerDataKey` value,
    /// which is prefixed with the little-endian company ID.
    public init?(manufacturerData data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count == 8,
              UInt16(bytes[0]) | UInt16(bytes[1]) << 8 == PodGATT.companyID else { return nil }
        self.init(payload: Array(bytes[2...]))
    }
}
