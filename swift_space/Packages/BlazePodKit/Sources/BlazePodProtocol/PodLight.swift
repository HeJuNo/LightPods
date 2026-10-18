import Foundation

/// Pod colours as exposed in the app (`ie.h`). `.random` is resolved by the caller.
public enum PodColor: String, CaseIterable, Sendable {
    case red = "RED", orange = "ORANGE", yellow = "YELLOW", green = "GREEN"
    case lightBlue = "LIGHT_BLUE", blue = "BLUE", purple = "PURPLE", pink = "PINK"
    case random = "RANDOM"

    public static let `default`: PodColor = .blue
    /// Real colours (picker order).
    public static let palette: [PodColor] = [.red, .orange, .yellow, .green, .lightBlue, .blue, .purple, .pink]
    /// Order used when auto-assigning colours to players/stations.
    public static let assignmentOrder: [PodColor] = [.blue, .red, .green, .pink, .lightBlue, .orange, .yellow, .purple]

    /// Single-channel colours; switching between them quickly needs a re-send (see `LightGlitchGuard`).
    public var isPrimary: Bool { self == .red || self == .green || self == .blue }

    public static func next(after color: PodColor?, offset: Int) -> PodColor {
        let base = assignmentOrder.firstIndex(of: color ?? .default) ?? 0
        return assignmentOrder[(base + offset) % assignmentOrder.count]
    }
}

/// Global brightness setting (`ie.e`). Raw values match the server-side user setting.
public enum LightIntensity: String, CaseIterable, Sendable {
    case max = "high", medium = "medium", low = "low"
}

/// LED drive levels per colour/intensity, scale 0...100 (`yp.k`).
public struct RGBLevel: Equatable, Sendable {
    public let r: UInt8, g: UInt8, b: UInt8

    public static let off = RGBLevel(r: 0, g: 0, b: 0)

    public init(r: UInt8, g: UInt8, b: UInt8) { self.r = r; self.g = g; self.b = b }

    public init(_ color: PodColor, _ intensity: LightIntensity) {
        let t: (UInt8, UInt8, UInt8)
        switch (color, intensity) {
        case (.red, .max): t = (100, 0, 0)
        case (.orange, .max): t = (100, 15, 0)
        case (.yellow, .max): t = (100, 78, 0)
        case (.green, .max): t = (0, 100, 0)
        case (.lightBlue, .max): t = (0, 100, 100)
        case (.blue, .max): t = (0, 0, 100)
        case (.purple, .max): t = (27, 0, 47)
        case (.pink, .max): t = (100, 0, 39)
        case (.red, .medium): t = (35, 0, 0)
        case (.orange, .medium): t = (35, 5, 0)
        case (.yellow, .medium): t = (35, 27, 0)
        case (.green, .medium): t = (0, 35, 0)
        case (.lightBlue, .medium): t = (0, 35, 35)
        case (.blue, .medium): t = (0, 0, 35)
        case (.purple, .medium): t = (16, 0, 27)
        case (.pink, .medium): t = (35, 0, 15)
        case (.red, .low): t = (7, 0, 0)
        case (.orange, .low): t = (11, 2, 0)
        case (.yellow, .low): t = (7, 5, 0)
        case (.green, .low): t = (0, 7, 0)
        case (.lightBlue, .low): t = (0, 7, 7)
        case (.blue, .low): t = (0, 0, 7)
        case (.purple, .low): t = (5, 0, 9)
        case (.pink, .low): t = (7, 0, 3)
        case (.random, _): t = (0, 0, 0)
        }
        self.init(r: t.0, g: t.1, b: t.2)
    }
}

/// Payload for the light characteristic. Byte order on the wire is **G, B, R**.
/// The optional 4th byte (`1`) asks the pod to switch itself off when hit;
/// the app only sets it for firmware >= 3.2 (`zp.f`).
public enum LightCommand {
    public static func payload(_ level: RGBLevel, offOnHit: Bool = false) -> [UInt8] {
        offOnHit ? [level.g, level.b, level.r, 1] : [level.g, level.b, level.r]
    }

    public static let off: [UInt8] = payload(.off)
}

/// Why a light ended, notified on `lightStatusCharacteristic` (`yp.h`).
public enum LightEndReason: UInt8, Sendable {
    case none = 0, completed = 1, overridden = 2, autoTurnOff = 3
}

/// Firmware quirk workaround (`je.i.g`/`je.i.k`): when switching between two different
/// primary colours less than 50 ms after the light was turned off, the app re-sends
/// the colour 30 ms later (up to 2 times) while the pod is still ON with that colour.
public struct LightGlitchGuard {
    public static let offWindow: TimeInterval = 0.050
    public static let resendDelay: TimeInterval = 0.030
    public static let maxResends = 2

    public static func needsResend(previous: PodColor?, next: PodColor, lastOffAt: Date?, now: Date = Date()) -> Bool {
        guard let previous, let lastOffAt, previous != next, previous.isPrimary, next.isPrimary else { return false }
        return now.timeIntervalSince(lastOffAt) < offWindow
    }
}
