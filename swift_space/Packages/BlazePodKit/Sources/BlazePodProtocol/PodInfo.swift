import Foundation

/// Semantic version compare used for firmware gates (`me.b`).
public struct FirmwareVersion: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]
    public init?(_ s: String) {
        let p = s.trimmingCharacters(in: .whitespaces).split(separator: ".").map { Int($0) }
        guard !p.isEmpty, !p.contains(where: { $0 == nil }) else { return nil }
        parts = p.compactMap { $0 }
    }
    public static func < (a: Self, b: Self) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }
    public var description: String { parts.map(String.init).joined(separator: ".") }

    /// Touch payload + "off on hit" need at least this application firmware.
    public static let touchV2 = FirmwareVersion("3.2")!
}

/// Device Information as read after connection.
public struct PodInfo: Equatable, Sendable {
    public enum Hardware: String, Sendable { case v1 = "POD_V1", v2 = "POD_V2" }

    /// Raw 2A26 string, format "<app>/<bootloader>", e.g. "3.4/1.0".
    public var firmwareRaw: String?
    public var model: String?
    public var serial: String?

    public init(firmwareRaw: String? = nil, model: String? = nil, serial: String? = nil) {
        self.firmwareRaw = firmwareRaw; self.model = model; self.serial = serial
    }

    public var appFirmware: FirmwareVersion? {
        firmwareRaw.flatMap { $0.split(separator: "/").first.map(String.init) }.flatMap(FirmwareVersion.init)
    }
    public var bootloaderFirmware: FirmwareVersion? {
        guard let parts = firmwareRaw?.split(separator: "/"), parts.count > 1 else { return nil }
        return FirmwareVersion(String(parts[1]))
    }
    public var supportsTouchV2: Bool { (appFirmware ?? FirmwareVersion("0")!) >= .touchV2 }

    /// "PodPapa" → V1, "PodMama" → V2 (spaces stripped, case-insensitive).
    public var hardware: Hardware? {
        switch model?.replacingOccurrences(of: " ", with: "").lowercased() {
        case "podpapa": return .v1
        case "podmama": return .v2
        default: return nil
        }
    }
}
