import BlazePodProtocol
import Foundation

extension PodColor: Codable {}

/// Activity engine (`fe.e`). Only the engines needed so far are implemented.
public enum DrillEngine: String, Codable, CaseIterable, Sendable {
    /// Each player chases a randomly placed pod in their colour (`g8.l`).
    case random
    /// One target pod in the player's colour among distracting pods in other colours (`g8.d`).
    case focus
}

/// `competitionMode` (`ie.b`).
public enum CompetitionMode: String, Codable, CaseIterable, Sendable {
    /// Every player has their own pod and keeps going independently.
    case regular
    /// All players get a pod at once; the first hit wins the round.
    case firstToHit
}

/// `lightsOutType` (`ie.f`).
public enum LightsOut: String, Codable, CaseIterable, Sendable {
    case hit, timeout, hitOrTimeout

    public var endsOnHit: Bool { self != .timeout }
    public var endsOnTimeout: Bool { self != .hit }
}

/// `lightDelayTimeType` (`ie.d`); values in seconds.
public enum LightDelay: Codable, Hashable, Sendable {
    case none
    case fixed(Double)
    case random(from: Double, to: Double)

    /// The original uses a 10 ms gap for "none" so a pod is never re-lit in the same tick.
    static let noneGap: TimeInterval = 0.010
}

/// `activityLengthType` (`ie.a`) for the Random/Focus engines.
public enum DrillDuration: Codable, Hashable, Sendable {
    case time(seconds: Int)
    case hitCount(Int)
    case timeOrHitCount(seconds: Int, hits: Int)

    public var seconds: Int? {
        switch self {
        case .time(let s), .timeOrHitCount(let s, _): s
        case .hitCount: nil
        }
    }

    public var hits: Int? {
        switch self {
        case .hitCount(let h), .timeOrHitCount(_, let h): h
        case .time: nil
        }
    }
}

/// A configurable drill (the app's activity settings model `fe.d` + `EngineSettings-V2.json`).
public struct DrillDefinition: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var summary: String
    /// SF Symbol shown on the drill card.
    public var symbol: String
    public var isBuiltIn: Bool
    public var engine: DrillEngine

    // Setup
    public var stations: Int
    public var podsPerStation: Int
    /// Players per station (Random only; Focus always has one player per station).
    public var players: Int
    /// Colours per player; a lit pod uses a random colour from the player's list.
    public var playerColors: [[PodColor]]
    public var competition: CompetitionMode

    // Lights
    public var lightsOut: LightsOut
    /// Seconds a pod stays lit when `lightsOut` includes a timeout.
    public var lightsOutTimeout: Double
    public var lightDelay: LightDelay

    // Length
    public var duration: DrillDuration
    public var cycles: Int
    /// Rest between cycles in seconds (`delayCycles`).
    public var cycleRest: Int

    // Focus engine
    public var distractingPods: Int
    public var distractingColors: [PodColor]
    /// End the cycle after this many hits on distracting pods (`strikeOut`); nil = off.
    public var strikeOut: Int?

    public init(id: UUID = UUID(), name: String, summary: String = "", symbol: String = "bolt.fill",
                isBuiltIn: Bool = false, engine: DrillEngine,
                stations: Int = 1, podsPerStation: Int = 3, players: Int = 1,
                playerColors: [[PodColor]] = [[.blue]], competition: CompetitionMode = .regular,
                lightsOut: LightsOut = .hit, lightsOutTimeout: Double = 2, lightDelay: LightDelay = .none,
                duration: DrillDuration = .time(seconds: 30), cycles: Int = 1, cycleRest: Int = 30,
                distractingPods: Int = 1, distractingColors: [PodColor] = [.red], strikeOut: Int? = nil) {
        self.id = id
        self.name = name
        self.summary = summary
        self.symbol = symbol
        self.isBuiltIn = isBuiltIn
        self.engine = engine
        self.stations = stations
        self.podsPerStation = podsPerStation
        self.players = players
        self.playerColors = playerColors
        self.competition = competition
        self.lightsOut = lightsOut
        self.lightsOutTimeout = lightsOutTimeout
        self.lightDelay = lightDelay
        self.duration = duration
        self.cycles = cycles
        self.cycleRest = cycleRest
        self.distractingPods = distractingPods
        self.distractingColors = distractingColors
        self.strikeOut = strikeOut
    }

    public var playersPerStation: Int { engine == .focus ? 1 : players }
    public var totalPods: Int { stations * podsPerStation }
    public var totalPlayers: Int { stations * playersPerStation }

    /// Colours of a player, padded with the auto-assignment order if the list is short.
    public func colors(forPlayer index: Int) -> [PodColor] {
        if index < playerColors.count, !playerColors[index].isEmpty { return playerColors[index] }
        return [PodColor.assignmentOrder[index % PodColor.assignmentOrder.count]]
    }

    /// Adjusts dependent values after an edit so the definition stays valid.
    public mutating func normalize() {
        stations = stations.clamped(to: Limits.stations)
        let minPods = engine == .focus ? Limits.focusMinPods : Limits.pods.lowerBound
        podsPerStation = podsPerStation.clamped(to: minPods...Limits.pods.upperBound)
        players = players.clamped(to: 1...min(Limits.players.upperBound, podsPerStation))
        let count = playersPerStation
        if playerColors.count < count {
            for i in playerColors.count..<count {
                let used = Set(playerColors.flatMap { $0 })
                let next = PodColor.assignmentOrder.first { !used.contains($0) }
                    ?? PodColor.assignmentOrder[i % PodColor.assignmentOrder.count]
                playerColors.append([next])
            }
        } else if playerColors.count > count {
            playerColors.removeLast(playerColors.count - count)
        }
        playerColors = playerColors.map { $0.isEmpty ? [.default] : Array($0.prefix(Limits.colorsPerPlayer.upperBound)) }
        if engine == .focus {
            distractingPods = distractingPods.clamped(to: 1...max(1, podsPerStation - 1))
            let targets = Set(playerColors.first ?? [])
            distractingColors.removeAll { targets.contains($0) }
            if distractingColors.isEmpty {
                distractingColors = [PodColor.palette.first { !targets.contains($0) } ?? .red]
            }
            if lightsOut == .timeout { lightsOut = .hit }
        }
        cycles = cycles.clamped(to: Limits.cycles)
    }

    /// Why the drill can't run with the given number of ready pods, or nil.
    public func problem(readyPods: Int) -> String? {
        if engine == .focus, distractingPods >= podsPerStation {
            return "Distracting pods must be fewer than the pods per station."
        }
        if engine == .random, players > podsPerStation {
            return "Each player needs their own pod: use at least \(players) pods per station."
        }
        if readyPods < totalPods {
            return "Needs \(totalPods) connected pod\(totalPods == 1 ? "" : "s"), \(readyPods) ready."
        }
        return nil
    }

    /// Copy suitable for "save as new drill".
    public func duplicated(named name: String) -> DrillDefinition {
        var copy = self
        copy.id = UUID()
        copy.name = name
        copy.isBuiltIn = false
        return copy
    }
}

/// Ranges from `EngineSettings-V2.json`.
public enum Limits {
    public static let stations = 1...20
    public static let pods = 1...24
    public static let focusMinPods = 3
    public static let players = 1...24
    public static let colorsPerPlayer = 1...7
    public static let cycles = 1...20
    /// Rest between cycles, seconds (step 5).
    public static let cycleRest = 5...60
    /// Activity duration, seconds (step 5).
    public static let durationSeconds = 10...3600
    public static let hitCount = 1...100
    /// Lights-out timeout, seconds (step 0.25).
    public static let lightsOut = 0.5...10.0
    /// Fixed light delay, seconds (step 0.5).
    public static let lightDelay = 0.5...10.0
    public static let strikeOut = 1...100
    public static let distractingPods = 1...24
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

// MARK: Built-in drills

public extension DrillDefinition {
    // Stable identifiers so edits to built-ins can be matched up.
    private static func builtInID(_ n: UInt8) -> UUID {
        UUID(uuid: (0x4C, 0x50, 0x44, 0x52, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n))
    }

    /// 1 player, 4 pods, 30 s. Every player owns a colour and only catches pods in that colour.
    static let colorCatch = DrillDefinition(
        id: builtInID(1), name: "Color Catch",
        summary: "Pods light up in each player's colour. Catch yours before anyone else does. Add players for a colour duel.",
        symbol: "paintpalette.fill", isBuiltIn: true, engine: .random,
        podsPerStation: 4, players: 1, playerColors: [[.blue]],
        lightsOut: .hit, duration: .time(seconds: 30))

    /// Plank position with 4 pods within reach: tap your colour, keep the core stable.
    static let plankFocusChallenge = DrillDefinition(
        id: builtInID(2), name: "Plank Focus Challenge",
        summary: "Hold a plank with the pods in front of you. Tap the pod in your colour, leave the distracting colour alone.",
        symbol: "figure.core.training", isBuiltIn: true, engine: .focus,
        podsPerStation: 4, playerColors: [[.green]],
        lightsOut: .hit, duration: .time(seconds: 30),
        distractingPods: 1, distractingColors: [.red])

    /// 4 pods in a line, 30 cm apart: tap the lit pod with your foot as fast as you can.
    static let fastFeet = DrillDefinition(
        id: builtInID(3), name: "Fast Feet",
        summary: "Four pods in a line, 30 cm apart. Tap the pod that lights up with your foot, as fast as you can.",
        symbol: "figure.run", isBuiltIn: true, engine: .random,
        podsPerStation: 4, playerColors: [[.lightBlue]],
        lightsOut: .hit, duration: .time(seconds: 30))

    /// The open Random engine with every option exposed.
    static let random = DrillDefinition(
        id: builtInID(4), name: "Random",
        summary: "Pods light up at random. Set stations, players, colours, lights out, delay and duration yourself.",
        symbol: "shuffle", isBuiltIn: true, engine: .random,
        podsPerStation: 3, playerColors: [[.blue]],
        lightsOut: .hit, duration: .time(seconds: 30))

    static let builtIns: [DrillDefinition] = [.colorCatch, .plankFocusChallenge, .fastFeet, .random]
}
