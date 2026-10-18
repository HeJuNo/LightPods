import Foundation

/// Touch notification payload (firmware >= 3.2, `je.q.onCharacteristicChanged`).
///
///     byte 0      : bits0-1 detection mode (0 interrupt, 1 polling), bit2 = pod turned its light off
///     bytes 1...4 : UInt32 LE – reaction time measured by the pod, in ms
///
/// Firmware < 3.2 sends a notification without usable content; it is treated as a
/// hit timed by the phone.
public struct TouchEvent: Equatable, Sendable {
    public enum Detection: UInt8, Sendable { case interrupt = 0, polling = 1 }

    public let detection: Detection?
    public let podTurnedLightOff: Bool?
    public let podReactionMs: UInt32

    public static let legacy = TouchEvent(detection: nil, podTurnedLightOff: nil, podReactionMs: 0)

    public init(detection: Detection?, podTurnedLightOff: Bool?, podReactionMs: UInt32) {
        self.detection = detection
        self.podTurnedLightOff = podTurnedLightOff
        self.podReactionMs = podReactionMs
    }

    public init?(payload: [UInt8]) {
        guard payload.count >= 5 else { return nil }
        detection = Detection(rawValue: payload[0] & 0x03)
        podTurnedLightOff = (payload[0] >> 2) & 1 == 1
        podReactionMs = UInt32(payload[1]) | UInt32(payload[2]) << 8 | UInt32(payload[3]) << 16 | UInt32(payload[4]) << 24
    }
}

/// Decides whether a touch notification is a valid hit (`je.i.l`). Pure function of
/// the local light state, so it can be unit tested.
public struct HitFilter {
    public struct LightState {
        public var isOn: Bool
        /// Light was started with "off on hit" (firmware >= 3.2 4th byte).
        public var offOnHit: Bool
        /// Phone-side stopwatch since light ON (0 when OFF and never started).
        public var elapsedMs: Int

        public init(isOn: Bool, offOnHit: Bool, elapsedMs: Int) {
            self.isOn = isOn; self.offOnHit = offOnHit; self.elapsedMs = elapsedMs
        }
    }

    public enum Decision: Equatable {
        case ignore
        /// Valid hit. `turnLightOffLocally` mirrors that the pod already went dark.
        case hit(reactionMs: Int, turnLightOffLocally: Bool)
    }

    public static let interruptDebounceMs = 250
    public static let pollingMinimumMs = 200
    public static let offOnHitGuardMs = 1000

    public static func evaluate(_ e: TouchEvent, state s: LightState) -> Decision {
        let podMs = Int(e.podReactionMs)
        let interruptLike = e.detection == nil || e.detection == .interrupt
        let turnedOff = e.podTurnedLightOff ?? false

        // Interrupt hit too soon after the light came on – bounce.
        if s.isOn && interruptLike && s.elapsedMs < interruptDebounceMs { return .ignore }
        // Polling hit with implausibly small pod time while still lit.
        if s.isOn && e.podTurnedLightOff == false && e.detection == .polling && podMs < pollingMinimumMs { return .ignore }
        // In "off on hit" mode, the pod must confirm it went dark within the first second.
        if s.offOnHit && e.podTurnedLightOff == false && s.elapsedMs < offOnHitGuardMs { return .ignore }
        // Polling reports while the light is off are noise.
        if e.detection == .polling && !s.isOn { return .ignore }
        // Pod time newer than our own stopwatch → stale notification.
        if podMs > 0 && podMs > s.elapsedMs { return .ignore }

        return .hit(reactionMs: podMs > 0 ? podMs : s.elapsedMs, turnLightOffLocally: turnedOff)
    }
}
