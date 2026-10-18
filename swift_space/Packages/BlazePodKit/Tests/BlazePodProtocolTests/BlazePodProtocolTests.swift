import XCTest
@testable import BlazePodProtocol

final class BlazePodProtocolTests: XCTestCase {
    func testAdvertisementParsing() {
        // battery 87 %, charging, version 7, key DE AD BE EF
        let ad = PodAdvertisement(manufacturerData: Data([0xD7, 0x09, (87 << 1) | 1, 7, 0xDE, 0xAD, 0xBE, 0xEF]))
        XCTAssertEqual(ad?.batteryPercent, 87)
        XCTAssertEqual(ad?.isCharging, true)
        XCTAssertEqual(ad?.version, 7)
        XCTAssertEqual(ad?.key, [0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertNil(PodAdvertisement(manufacturerData: Data([0x4C, 0x00, 0, 0, 0, 0, 0, 0])))
    }

    /// Reference values were produced by a literal Java port of `je.e0` (see docs/ble-pod-protocol.md §5).
    func testAuthMatchesJavaReference() {
        let vectors: [([UInt8], Int8, [UInt8])] = loadVectors()
        XCTAssertFalse(vectors.isEmpty)
        for (key, version, expected) in vectors {
            XCTAssertEqual(PodAuthenticator.response(key: key, version: version), expected, "key \(key) v \(version)")
        }
    }

    func testAuthCommandPrefix() {
        let ad = PodAdvertisement(payload: [0, 1, 1, 2, 3, 4])!
        XCTAssertEqual(Array(PodAuthenticator.command(for: ad).prefix(3)), Array("sea".utf8))
        XCTAssertEqual(PodAuthenticator.command(for: ad).count, 7)
    }

    func testLightPayloadIsGBR() {
        XCTAssertEqual(LightCommand.payload(RGBLevel(.orange, .max)), [15, 0, 100])
        XCTAssertEqual(LightCommand.payload(RGBLevel(.purple, .low), offOnHit: true), [0, 9, 5, 1])
        XCTAssertEqual(LightCommand.off, [0, 0, 0])
    }

    func testTouchParsingAndFilter() {
        let e = TouchEvent(payload: [0b100, 0x2C, 0x01, 0, 0])! // interrupt, light off, 300 ms
        XCTAssertEqual(e.detection, .interrupt)
        XCTAssertEqual(e.podTurnedLightOff, true)
        XCTAssertEqual(e.podReactionMs, 300)

        let on = HitFilter.LightState(isOn: true, offOnHit: false, elapsedMs: 400)
        XCTAssertEqual(HitFilter.evaluate(e, state: on), .hit(reactionMs: 300, turnLightOffLocally: true))
        XCTAssertEqual(HitFilter.evaluate(e, state: .init(isOn: true, offOnHit: false, elapsedMs: 100)), .ignore)
        XCTAssertEqual(HitFilter.evaluate(.legacy, state: on), .hit(reactionMs: 400, turnLightOffLocally: false))
        let polling = TouchEvent(detection: .polling, podTurnedLightOff: false, podReactionMs: 0)
        XCTAssertEqual(HitFilter.evaluate(polling, state: .init(isOn: false, offOnHit: false, elapsedMs: 0)), .ignore)
    }

    func testUARTEvents() {
        XCTAssertEqual(UARTEvent(payload: Array("chgs=".utf8) + [2, 0]), .charger(.charging))
        XCTAssertEqual(UARTEvent(payload: Array("disf=".utf8) + [5, 1]), .disconnectReason(261))
    }

    func testFirmwareGate() {
        XCTAssertTrue(PodInfo(firmwareRaw: "3.2/1.0").supportsTouchV2)
        XCTAssertFalse(PodInfo(firmwareRaw: "3.1.9/1.0").supportsTouchV2)
        XCTAssertEqual(PodInfo(model: "Pod Mama").hardware, .v2)
    }

    private func loadVectors() -> [([UInt8], Int8, [UInt8])] {
        AuthVectors.all
    }
}
