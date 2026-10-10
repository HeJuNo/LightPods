import Foundation
import SwiftData

// MARK: - Competition Mode

enum CompetitionMode: String, CaseIterable, Identifiable, Codable {
    case regular = "Regular"
    case firstToHit = "First to Hit"

    var id: String { rawValue }
}

// MARK: - Lights Out Mode (extended)

enum LightsOutMode: String, CaseIterable, Identifiable, Codable {
    case hit = "On Tap"
    case timeout = "After Timeout"
    case hitAndTimeout = "Tap or Timeout"

    var id: String { rawValue }
}

// MARK: - Light Delay Mode

enum LightDelayMode: String, CaseIterable, Identifiable, Codable {
    case none = "None"
    case fixed = "Fixed"
    case random = "Random"

    var id: String { rawValue }
}

// MARK: - Duration Mode

enum DurationMode: String, CaseIterable, Identifiable, Codable {
    case time = "Time Limit"
    case hitCount = "Hit Count"
    case timeOrHitCount = "Time or Hits"

    var id: String { rawValue }
}

// MARK: - Start Mode

enum StartMode: String, CaseIterable, Identifiable, Codable {
    case startOnHit = "Start on Hit"
    case startNow = "Start Now"

    var id: String { rawValue }
}

// MARK: - Player Config

struct PlayerConfig: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var color: String  // PodColor.rawValue

    var podColor: PodColor {
        PodColor(rawValue: color) ?? .white
    }

    static func guest(index: Int, color: PodColor) -> PlayerConfig {
        PlayerConfig(name: "Guest \(index + 1)", color: color.rawValue)
    }
}

// MARK: - Drill Configuration (full 6-section config)

@Observable
class DrillConfiguration {
    // Section 1: General Setup
    var lightIntensity: Double = 1.0           // 0.0 - 1.0
    var stationCount: Int = 1
    var podsPerStation: Int = 1
    var playersPerStation: Int = 1
    var competitionMode: CompetitionMode = .regular

    // Section 2: Colors and Light Rules
    var players: [PlayerConfig] = [PlayerConfig.guest(index: 0, color: .white)]
    var lightsOutMode: LightsOutMode = .hit
    var lightsOutTimeout: Double = 3.0         // seconds, in 0.25s steps

    // Section 3: Light Delay Time
    var lightDelayMode: LightDelayMode = .none
    var lightDelayFixed: Double = 0.5          // seconds, in 0.25s steps
    var lightDelayRandomMin: Double = 0.25     // seconds
    var lightDelayRandomMax: Double = 2.0      // seconds

    // Section 4: Duration
    var durationMode: DurationMode = .hitCount
    var durationTimeMinutes: Double = 1.0
    var durationHitCount: Int = 10

    // Section 5: Cycles
    var cycleCount: Int = 1
    var timeBetweenCycles: Double = 5.0        // seconds

    // Section 6: Start Mode
    var startMode: StartMode = .startNow

    // Computed
    var totalPodsNeeded: Int {
        stationCount * podsPerStation
    }

    /// Apply intensity to a color's RGB values
    func adjustedRGB(for color: PodColor) -> (r: UInt8, g: UInt8, b: UInt8) {
        let c = color.rgb
        let factor = max(0, min(1, lightIntensity))
        return (
            r: UInt8(Double(c.r) * factor),
            g: UInt8(Double(c.g) * factor),
            b: UInt8(Double(c.b) * factor)
        )
    }

    func lightDelay() async {
        switch lightDelayMode {
        case .none:
            return
        case .fixed:
            try? await Task.sleep(for: .seconds(lightDelayFixed))
        case .random:
            let delay = Double.random(in: lightDelayRandomMin...lightDelayRandomMax)
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    var timeoutSeconds: Double? {
        switch lightsOutMode {
        case .hit:
            return nil
        case .timeout, .hitAndTimeout:
            return lightsOutTimeout
        }
    }

    var offOnTap: Bool {
        lightsOutMode == .hit || lightsOutMode == .hitAndTimeout
    }
}

// MARK: - Drill Preset (SwiftData)

@Model
class DrillPreset {
    var name: String
    var drillTypeID: String       // references DrillCatalog.Entry.id
    var createdAt: Date = Date()

    // Stored as JSON
    var configJSON: Data?

    init(name: String, drillTypeID: String) {
        self.name = name
        self.drillTypeID = drillTypeID
    }

    func loadConfig() -> DrillConfiguration {
        guard let data = configJSON else { return DrillConfiguration() }
        let decoder = JSONDecoder()
        if let stored = try? decoder.decode(StoredDrillConfig.self, from: data) {
            return stored.toConfig()
        }
        return DrillConfiguration()
    }

    func saveConfig(_ config: DrillConfiguration) {
        let stored = StoredDrillConfig(from: config)
        let encoder = JSONEncoder()
        configJSON = try? encoder.encode(stored)
    }
}

// MARK: - Codable bridge (since @Observable doesn't auto-conform to Codable)

struct StoredDrillConfig: Codable {
    var lightIntensity: Double
    var stationCount: Int
    var podsPerStation: Int
    var playersPerStation: Int
    var competitionMode: CompetitionMode
    var players: [PlayerConfig]
    var lightsOutMode: LightsOutMode
    var lightsOutTimeout: Double
    var lightDelayMode: LightDelayMode
    var lightDelayFixed: Double
    var lightDelayRandomMin: Double
    var lightDelayRandomMax: Double
    var durationMode: DurationMode
    var durationTimeMinutes: Double
    var durationHitCount: Int
    var cycleCount: Int
    var timeBetweenCycles: Double
    var startMode: StartMode

    init(from c: DrillConfiguration) {
        lightIntensity = c.lightIntensity
        stationCount = c.stationCount
        podsPerStation = c.podsPerStation
        playersPerStation = c.playersPerStation
        competitionMode = c.competitionMode
        players = c.players
        lightsOutMode = c.lightsOutMode
        lightsOutTimeout = c.lightsOutTimeout
        lightDelayMode = c.lightDelayMode
        lightDelayFixed = c.lightDelayFixed
        lightDelayRandomMin = c.lightDelayRandomMin
        lightDelayRandomMax = c.lightDelayRandomMax
        durationMode = c.durationMode
        durationTimeMinutes = c.durationTimeMinutes
        durationHitCount = c.durationHitCount
        cycleCount = c.cycleCount
        timeBetweenCycles = c.timeBetweenCycles
        startMode = c.startMode
    }

    func toConfig() -> DrillConfiguration {
        let c = DrillConfiguration()
        c.lightIntensity = lightIntensity
        c.stationCount = stationCount
        c.podsPerStation = podsPerStation
        c.playersPerStation = playersPerStation
        c.competitionMode = competitionMode
        c.players = players
        c.lightsOutMode = lightsOutMode
        c.lightsOutTimeout = lightsOutTimeout
        c.lightDelayMode = lightDelayMode
        c.lightDelayFixed = lightDelayFixed
        c.lightDelayRandomMin = lightDelayRandomMin
        c.lightDelayRandomMax = lightDelayRandomMax
        c.durationMode = durationMode
        c.durationTimeMinutes = durationTimeMinutes
        c.durationHitCount = durationHitCount
        c.cycleCount = cycleCount
        c.timeBetweenCycles = timeBetweenCycles
        c.startMode = startMode
        return c
    }
}
