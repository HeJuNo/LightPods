import BlazePodProtocol
@testable import BlazePodDrills
import XCTest

/// Records what the engine asks the pods to do.
final class FakePods: DrillPodDriver {
    var lit: [Int: PodColor] = [:]
    var offOnHit: [Int: Bool] = [:]
    var lightCount = 0

    func light(pod: Int, color: PodColor, offOnHit flag: Bool) {
        lit[pod] = color
        offOnHit[pod] = flag
        lightCount += 1
    }

    func off(pod: Int) { lit[pod] = nil }
}

/// Deterministic generator (SplitMix64).
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class DrillSessionTests: XCTestCase {
    private var pods: FakePods!
    private var clock: ManualScheduler!
    private var events: [DrillEvent] = []

    override func setUp() {
        pods = FakePods()
        clock = ManualScheduler()
        events = []
    }

    private func makeSession(_ def: DrillDefinition, seed: UInt64 = 1) -> DrillSession {
        let s = DrillSession(definition: def, driver: pods, scheduler: clock, rng: SeededRNG(state: seed))
        s.onEvent = { [unowned self] in events.append($0) }
        return s
    }

    private func startRunning(_ s: DrillSession) {
        s.start()
        clock.advance(by: 3)
        XCTAssertEqual(s.phase, .running(cycle: 1))
    }

    func testCountdownThenFirstPodLights() {
        let s = makeSession(.fastFeet)
        s.start()
        XCTAssertEqual(s.phase, .countdown(3))
        XCTAssertTrue(pods.lit.isEmpty)
        clock.advance(by: 3)
        XCTAssertEqual(events.prefix(4), [.countdown(3), .countdown(2), .countdown(1), .cycleStarted(1)])
        XCTAssertEqual(pods.lit.count, 1)
        XCTAssertEqual(pods.lit.values.first, .lightBlue)
        XCTAssertEqual(pods.offOnHit.values.first, true, "random + hit uses the pod's own off-on-hit")
    }

    func testRandomHitMovesToAnotherPodAndScores() {
        let s = makeSession(.fastFeet)
        startRunning(s)
        for _ in 0..<20 {
            let pod = pods.lit.keys.first!
            s.handleHit(pod: pod, reactionMs: 400)
            clock.advance(by: 0.02)
            XCTAssertEqual(pods.lit.count, 1)
            XCTAssertNotEqual(pods.lit.keys.first, pod, "no delay: never the same pod twice in a row")
        }
        XCTAssertEqual(s.players[0].stats.hitCount, 20)
        XCTAssertEqual(s.players[0].stats.averageMs, 400)
    }

    func testHitOnUnlitPodIsIgnored() {
        let s = makeSession(.fastFeet)
        startRunning(s)
        let unlit = (0..<4).first { pods.lit[$0] == nil }!
        s.handleHit(pod: unlit, reactionMs: 300)
        XCTAssertEqual(s.players[0].stats.hitCount, 0)
    }

    func testTimedCycleEndsAndTurnsEverythingOff() {
        let s = makeSession(.fastFeet)
        startRunning(s)
        clock.advance(by: 25.5)
        XCTAssertTrue(events.contains(.endingSoon))
        clock.advance(by: 5)
        XCTAssertEqual(s.phase, .finished)
        XCTAssertTrue(pods.lit.isEmpty)
        XCTAssertEqual(events.last, .finished)
    }

    func testHitCountEndsCycle() {
        var def = DrillDefinition.random
        def.duration = .hitCount(5)
        let s = makeSession(def)
        startRunning(s)
        for _ in 0..<5 {
            s.handleHit(pod: pods.lit.keys.first!, reactionMs: 250)
            clock.advance(by: 0.02)
        }
        XCTAssertEqual(s.phase, .finished)
        XCTAssertEqual(s.players[0].stats.hitCount, 5)
    }

    func testCyclesWithRest() {
        var def = DrillDefinition.random
        def.duration = .time(seconds: 10)
        def.cycles = 2
        def.cycleRest = 5
        let s = makeSession(def)
        startRunning(s)
        clock.advance(by: 10)
        XCTAssertEqual(s.phase, .resting(nextCycle: 2))
        XCTAssertTrue(pods.lit.isEmpty)
        XCTAssertEqual(s.restRemaining ?? -1, 5, accuracy: 0.001)
        clock.advance(by: 5)
        XCTAssertEqual(s.phase, .running(cycle: 2))
        XCTAssertEqual(pods.lit.count, 1)
        clock.advance(by: 10)
        XCTAssertEqual(s.phase, .finished)
    }

    func testTimeoutModeCountsTimeoutsAndIgnoresHits() {
        var def = DrillDefinition.random
        def.lightsOut = .timeout
        def.lightsOutTimeout = 1
        let s = makeSession(def)
        startRunning(s)
        XCTAssertEqual(pods.offOnHit.values.first, false)
        s.handleHit(pod: pods.lit.keys.first!, reactionMs: 200)
        XCTAssertEqual(s.players[0].stats.hitCount, 0)
        clock.advance(by: 1.005)
        XCTAssertEqual(s.players[0].stats.timeouts, 1)
        XCTAssertEqual(s.players[0].stats.misses, 0)
    }

    func testHitOrTimeoutCountsMisses() {
        var def = DrillDefinition.random
        def.lightsOut = .hitOrTimeout
        def.lightsOutTimeout = 1
        let s = makeSession(def)
        startRunning(s)
        clock.advance(by: 1.005)
        XCTAssertEqual(s.players[0].stats.misses, 1)
        clock.advance(by: 0.02)
        s.handleHit(pod: pods.lit.keys.first!, reactionMs: 300)
        XCTAssertEqual(s.players[0].stats.hitCount, 1)
    }

    func testFixedDelayKeepsPodDarkBeforeNextLight() {
        var def = DrillDefinition.random
        def.lightDelay = .fixed(2)
        let s = makeSession(def)
        startRunning(s)
        s.handleHit(pod: pods.lit.keys.first!, reactionMs: 300)
        clock.advance(by: 1.9)
        XCTAssertTrue(pods.lit.isEmpty)
        clock.advance(by: 0.2)
        XCTAssertEqual(pods.lit.count, 1)
    }

    func testRandomDelayStaysInRange() {
        var def = DrillDefinition.random
        def.lightDelay = .random(from: 1, to: 3)
        let s = makeSession(def, seed: 42)
        for _ in 0..<200 {
            let d = s.randomDelay()
            XCTAssertTrue((1...3).contains(d))
            XCTAssertEqual(d.truncatingRemainder(dividingBy: 0.5), 0)
        }
    }

    func testMultiplePlayersGetDistinctPodsInTheirColours() {
        var def = DrillDefinition.random
        def.podsPerStation = 6
        def.players = 3
        def.playerColors = [[.red], [.green], [.blue]]
        let s = makeSession(def)
        startRunning(s)
        XCTAssertEqual(pods.lit.count, 3)
        XCTAssertEqual(Set(pods.lit.values), [.red, .green, .blue])
        let redPod = pods.lit.first { $0.value == .red }!.key
        s.handleHit(pod: redPod, reactionMs: 500)
        XCTAssertEqual(s.players[0].stats.hitCount, 1)
        XCTAssertEqual(s.players[1].stats.hitCount, 0)
        clock.advance(by: 0.02)
        XCTAssertEqual(pods.lit.count, 3)
        XCTAssertEqual(Set(pods.lit.keys).count, 3)
    }

    func testFirstToHitRound() {
        var def = DrillDefinition.random
        def.podsPerStation = 4
        def.players = 2
        def.playerColors = [[.red], [.green]]
        def.competition = .firstToHit
        let s = makeSession(def)
        startRunning(s)
        XCTAssertEqual(pods.offOnHit.values.allSatisfy { !$0 }, true)
        let green = pods.lit.first { $0.value == .green }!.key
        s.handleHit(pod: green, reactionMs: 350)
        XCTAssertTrue(pods.lit.isEmpty, "the round ends for everybody")
        XCTAssertEqual(s.players[1].stats.hitCount, 1)
        XCTAssertEqual(s.players[0].stats.misses, 1)
        clock.advance(by: 0.02)
        XCTAssertEqual(pods.lit.count, 2)
    }

    func testStationsUseTheirOwnPods() {
        var def = DrillDefinition.fastFeet
        def.stations = 3
        let s = makeSession(def)
        startRunning(s)
        XCTAssertEqual(s.players.count, 3)
        XCTAssertEqual(pods.lit.count, 3)
        for station in 0..<3 {
            let range = station * 4 ..< station * 4 + 4
            XCTAssertEqual(pods.lit.keys.filter(range.contains).count, 1)
        }
    }

    func testFocusTargetAndDistractors() {
        var def = DrillDefinition.plankFocusChallenge
        def.playerColors = [[.blue]]
        def.distractingPods = 2
        def.distractingColors = [.red, .green]
        let s = makeSession(def)
        startRunning(s)
        XCTAssertEqual(pods.lit.count, 3, "1 target + 2 distracting pods")
        XCTAssertEqual(pods.lit.values.filter { $0 == .blue }.count, 1)
        XCTAssertTrue(pods.offOnHit.values.allSatisfy { !$0 })
        let distractor = pods.lit.first { $0.value != .blue }!.key
        s.handleHit(pod: distractor, reactionMs: 200)
        XCTAssertEqual(s.players[0].stats.strikes, 1)
        XCTAssertEqual(pods.lit.count, 3, "distracting pods stay lit")
        let target = pods.lit.first { $0.value == .blue }!.key
        s.handleHit(pod: target, reactionMs: 450)
        XCTAssertEqual(s.players[0].stats.hitCount, 1)
        XCTAssertTrue(pods.lit.isEmpty)
        clock.advance(by: 0.02)
        XCTAssertEqual(pods.lit.count, 3)
        let newTarget = pods.lit.first { $0.value == .blue }!.key
        XCTAssertNotEqual(newTarget, target)
    }

    func testFocusStrikeOutEndsCycle() {
        var def = DrillDefinition.plankFocusChallenge
        def.playerColors = [[.blue]]
        def.strikeOut = 2
        let s = makeSession(def)
        startRunning(s)
        for _ in 0..<2 {
            s.handleHit(pod: pods.lit.first { $0.value != .blue }!.key, reactionMs: 200)
        }
        XCTAssertEqual(s.phase, .finished)
    }

    func testStopKeepsResults() {
        let s = makeSession(.fastFeet)
        startRunning(s)
        s.handleHit(pod: pods.lit.keys.first!, reactionMs: 321)
        s.stop()
        XCTAssertEqual(s.phase, .finished)
        XCTAssertTrue(s.stoppedEarly)
        XCTAssertTrue(pods.lit.isEmpty)
        XCTAssertEqual(s.players[0].stats.bestMs, 321)
        clock.advance(by: 60)
        XCTAssertTrue(pods.lit.isEmpty, "no timers survive stop()")
    }

    func testNormalizeKeepsDefinitionValid() {
        var def = DrillDefinition.plankFocusChallenge
        def.playerColors = [[.blue]]
        def.podsPerStation = 3
        def.distractingPods = 5
        def.distractingColors = [.blue]
        def.lightsOut = .timeout
        def.normalize()
        XCTAssertEqual(def.distractingPods, 2)
        XCTAssertFalse(def.distractingColors.contains(.blue))
        XCTAssertEqual(def.lightsOut, .hit)

        var random = DrillDefinition.random
        random.setLayout(players: 4, podsPerStation: 2)
        XCTAssertEqual(random.players, 2)
        XCTAssertEqual(random.playerColors.count, 2)
        XCTAssertNotEqual(random.playerColors[0], random.playerColors[1])
    }

    func testColoursPerStationAndPlayer() {
        var def = DrillDefinition.random
        def.setLayout(stations: 2, players: 2, podsPerStation: 3)
        XCTAssertEqual(def.playerColors.count, 4)
        def.setColors([.red], station: 0, index: 0)
        def.setColors([.green], station: 0, index: 1)
        def.setColors([.yellow], station: 1, index: 0)
        def.setColors([.pink], station: 1, index: 1)
        def.setPlayerName("Ben", station: 1, index: 1)
        let s = makeSession(def)
        startRunning(s)
        XCTAssertEqual(Set(pods.lit.filter { $0.key < 3 }.values), [.red, .green])
        XCTAssertEqual(Set(pods.lit.filter { $0.key >= 3 }.values), [.yellow, .pink])
        XCTAssertEqual(s.players.map(\.primaryColor), [.red, .green, .yellow, .pink])

        // Adding a player keeps everyone's colours and names in place.
        def.setLayout(players: 3)
        XCTAssertEqual(def.colors(station: 1, index: 0), [.yellow])
        XCTAssertEqual(def.colors(station: 1, index: 1), [.pink])
        XCTAssertEqual(def.playerName(station: 1, index: 1), "Ben")
        XCTAssertEqual(def.playerColors.count, 6)
        // Removing a station drops its players.
        def.setLayout(stations: 1)
        XCTAssertEqual(def.playerColors.count, 3)
        XCTAssertNil(def.playerNames)
    }

    func testOldDrillsWithSharedColoursStillWork() {
        var def = DrillDefinition.random
        def.stations = 2
        def.players = 2
        def.podsPerStation = 3
        def.playerColors = [[.red], [.green]]   // old layout: per player, all stations
        XCTAssertEqual(def.colors(station: 1, index: 1), [.green])
        def.normalize()
        XCTAssertEqual(def.playerColors, [[.red], [.green], [.red], [.green]])
    }

    func testPlayerNames() throws {
        var def = DrillDefinition.random
        def.stations = 2
        def.players = 2
        def.setPlayerName("Anna", station: 1, index: 0)
        def.normalize()
        XCTAssertEqual(def.playerName(station: 1, index: 0), "Anna")
        XCTAssertNil(def.playerName(station: 0, index: 0))
        // Older saved drills have no names and must still decode.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DrillDefinition.fastFeet)) as! [String: Any]
        json["playerNames"] = nil
        let old = try JSONDecoder().decode(DrillDefinition.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.playerNames)
        def.stations = 1
        def.normalize()
        XCTAssertNil(def.playerNames, "names of removed players are dropped")
    }

    func testProblemReportsMissingPods() {
        XCTAssertNotNil(DrillDefinition.fastFeet.problem(readyPods: 3))
        XCTAssertNil(DrillDefinition.fastFeet.problem(readyPods: 4))
    }

    func testDefinitionRoundTripsThroughJSON() throws {
        var def = DrillDefinition.random.duplicated(named: "Mine")
        def.lightDelay = .random(from: 0.5, to: 2)
        def.duration = .timeOrHitCount(seconds: 45, hits: 20)
        def.strikeOut = 3
        let data = try JSONEncoder().encode(def)
        let back = try JSONDecoder().decode(DrillDefinition.self, from: data)
        XCTAssertEqual(back, def)
        XCTAssertFalse(back.isBuiltIn)
        XCTAssertNotEqual(back.id, DrillDefinition.random.id)
    }
}
