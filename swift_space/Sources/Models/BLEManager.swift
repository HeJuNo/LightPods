import Foundation
import CoreBluetooth
import os.log

// MARK: - BLE UUIDs
private let uartServiceUUID      = CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca9e")
private let uartRXCharUUID       = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9e")
private let colorServiceUUID     = CBUUID(string: "50c97bfa-4cb8-4c84-b745-0e58a0280cd6")
private let colorCharUUID        = CBUUID(string: "50c912a2-4cb8-4c84-b745-0e58a0280cd6")
private let tapServiceUUID       = CBUUID(string: "50c928bd-4cb8-4c84-b745-0e58a0280cd6")
private let tapCharUUID          = CBUUID(string: "50c9727e-4cb8-4c84-b745-0e58a0280cd6")

// Standard BLE services
private let batteryServiceUUID   = CBUUID(string: "180F")
private let batteryLevelCharUUID = CBUUID(string: "2A19")
private let disServiceUUID       = CBUUID(string: "180A")   // Device Information Service
private let disSerialCharUUID    = CBUUID(string: "2A25")
private let disFwRevCharUUID     = CBUUID(string: "2A26")
private let disHwRevCharUUID     = CBUUID(string: "2A27")
private let disSwRevCharUUID     = CBUUID(string: "2A28")
private let disModelCharUUID     = CBUUID(string: "2A24")
private let disMfrCharUUID       = CBUUID(string: "2A29")

/// BlazePod company ID bytes (little-endian in manufacturer data)
private let blazePodCompanyID: [UInt8] = [0xD7, 0x09]

@Observable
class BLEManager: NSObject {
    private let logger = Logger(subsystem: "com.hejuno.lightpods", category: "BLE")

    private var centralManager: CBCentralManager!

    var isScanning = false
    var bluetoothState: CBManagerState = .unknown
    var discoveredDevices: [PodDevice] = []
    var connectedPods: [PodDevice] = []

    /// Authenticated pods ready for drills
    var authenticatedPods: [PodDevice] {
        connectedPods.filter { $0.connectionState == .authenticated }
    }

    /// Callback when a tap is received from any pod
    var onTapReceived: ((PodDevice, TapEvent) -> Void)?

    /// Auto-detect: automatically connect discovered pods
    var autoDetectEnabled = false

    /// Callback when a pod is auto-connected and authenticated (for auto-saving)
    var onPodAutoConnected: ((PodDevice) -> Void)?

    /// Stored manufacturer data for reconnection (peripheralUUID -> Data)
    private var storedMfrData: [UUID: Data] = [:]

    /// Pending reconnect UUIDs (set before BT is ready)
    private var pendingReconnectUUIDs: [(uuid: UUID, mfrData: Data?)] = []

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Scanning (BlazePods only)
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            logger.warning("Cannot scan: Bluetooth not powered on (state: \(self.centralManager.state.rawValue))")
            return
        }
        discoveredDevices.removeAll()
        isScanning = true
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
        logger.info("Started BLE scanning (BlazePod filter active)")
    }

    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        logger.info("Stopped BLE scanning")
    }

    // MARK: - BlazePod identification
    private func isBlazePod(manufacturerData: Data?, name: String?) -> Bool {
        if let data = manufacturerData, data.count >= 5 {
            if data[0] == blazePodCompanyID[0] && data[1] == blazePodCompanyID[1] {
                return true
            }
        }
        if let n = name?.lowercased() {
            if n.contains("blazepod") || n.contains("blaze pod") {
                return true
            }
        }
        return false
    }

    // MARK: - Connection
    func connectPod(_ device: PodDevice) {
        if let idx = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices.remove(at: idx)
        }
        device.connectionState = .connecting
        if !connectedPods.contains(where: { $0.id == device.id }) {
            connectedPods.append(device)
        }
        if let mfr = device.manufacturerData {
            storedMfrData[device.id] = mfr
        }
        centralManager.connect(device.peripheral, options: nil)
        logger.info("Connecting to \(device.name)")
    }

    func disconnectPod(_ device: PodDevice) {
        centralManager.cancelPeripheralConnection(device.peripheral)
        device.connectionState = .disconnected
        device.uartRXCharacteristic = nil
        device.colorCharacteristic = nil
        device.tapCharacteristic = nil
        logger.info("Disconnecting \(device.name)")
    }

    func reconnectPod(_ device: PodDevice) {
        device.connectionState = .connecting
        device.errorMessage = nil
        centralManager.connect(device.peripheral, options: nil)
    }

    func removePod(_ device: PodDevice) {
        if device.connectionState != .disconnected {
            centralManager.cancelPeripheralConnection(device.peripheral)
        }
        connectedPods.removeAll { $0.id == device.id }
        storedMfrData.removeValue(forKey: device.id)
    }

    // MARK: - Reconnect saved pods
    func reconnectSavedPods(_ infos: [(uuid: UUID, mfrData: Data?)]) {
        guard centralManager.state == .poweredOn else {
            pendingReconnectUUIDs = infos
            return
        }
        performReconnect(infos)
    }

    private func performReconnect(_ infos: [(uuid: UUID, mfrData: Data?)]) {
        let uuids = infos.map { $0.uuid }
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: uuids)

        for peripheral in peripherals {
            guard !connectedPods.contains(where: { $0.id == peripheral.identifier }) else { continue }

            let info = infos.first { $0.uuid == peripheral.identifier }
            let mfrData = info?.mfrData
            if let mfr = mfrData {
                storedMfrData[peripheral.identifier] = mfr
            }

            let device = PodDevice(
                peripheral: peripheral,
                name: peripheral.name,
                rssi: 0,
                manufacturerData: mfrData
            )
            device.connectionState = .connecting
            connectedPods.append(device)
            centralManager.connect(peripheral, options: nil)
            logger.info("Reconnecting saved pod: \(device.name)")
        }
    }

    // MARK: - Pod Commands

    /// Set a pod's LED to an RGB color
    /// - Parameters:
    ///   - pod: The target pod (must be authenticated)
    ///   - r: Red 0-255
    ///   - g: Green 0-255
    ///   - b: Blue 0-255
    ///   - offOnTap: If true, the pod auto-extinguishes when tapped
    func setColor(_ pod: PodDevice, r: UInt8, g: UInt8, b: UInt8, offOnTap: Bool = false) {
        guard pod.connectionState == .authenticated,
              let char = pod.colorCharacteristic else {
            logger.warning("Cannot set color on \(pod.name): not authenticated or no characteristic")
            return
        }
        // BlazePod expects channels in G B R order
        var bytes: [UInt8] = [g, b, r]
        if offOnTap {
            bytes.append(0x01)
        }
        let data = Data(bytes)
        let writeType: CBCharacteristicWriteType = char.properties.contains(.write) ? .withResponse : .withoutResponse
        pod.peripheral.writeValue(data, for: char, type: writeType)
        logger.info("Set color (\(r),\(g),\(b)) offOnTap=\(offOnTap) on \(pod.name)")
    }

    /// Set a pod's color using a PodColor preset
    func setColor(_ pod: PodDevice, color: PodColor, offOnTap: Bool = false) {
        let c = color.rgb
        setColor(pod, r: c.r, g: c.g, b: c.b, offOnTap: offOnTap)
    }

    /// Convenience: light up with a preset color (always offOnTap = true for backward compat)
    func lightUp(_ pod: PodDevice, color: PodColor) {
        setColor(pod, color: color, offOnTap: true)
    }

    /// Turn off a pod's LED
    func turnOff(_ pod: PodDevice) {
        guard pod.connectionState == .authenticated,
              let char = pod.colorCharacteristic else { return }
        let data = Data([0x00, 0x00, 0x00])
        let writeType: CBCharacteristicWriteType = char.properties.contains(.write) ? .withResponse : .withoutResponse
        pod.peripheral.writeValue(data, for: char, type: writeType)
        logger.info("Turned off \(pod.name)")
    }

    /// Turn off all authenticated pods
    func allOff() {
        for pod in authenticatedPods {
            turnOff(pod)
        }
    }

    /// Flash a pod N times (useful for identification)
    func flash(_ pod: PodDevice, color: PodColor = .white, count: Int = 3, onMs: Int = 250, offMs: Int = 200) {
        Task { @MainActor in
            for i in 0..<count {
                setColor(pod, color: color)
                try? await Task.sleep(for: .milliseconds(onMs))
                turnOff(pod)
                if i < count - 1 {
                    try? await Task.sleep(for: .milliseconds(offMs))
                }
            }
        }
    }

    // MARK: - Auth (CRC32 variant from protocol.py)
    private func authenticate(_ pod: PodDevice) {
        let mfrData = pod.manufacturerData ?? storedMfrData[pod.id]
        guard let mfrData = mfrData else {
            pod.connectionState = .error
            pod.errorMessage = "No manufacturer data for auth"
            logger.error("Auth failed for \(pod.name): no manufacturer data")
            return
        }
        guard let uartRX = pod.uartRXCharacteristic else {
            pod.connectionState = .error
            pod.errorMessage = "UART RX characteristic not found"
            logger.error("Auth failed for \(pod.name): no UART RX")
            return
        }

        pod.connectionState = .authenticating

        let suffix = computeAuthSuffix(mfrData: mfrData)
        guard suffix.count == 4 else {
            pod.connectionState = .error
            pod.errorMessage = "Auth computation failed (data too short)"
            logger.error("Auth failed for \(pod.name): could not compute suffix")
            return
        }

        var payload: [UInt8] = [0x73, 0x65, 0x61] // "sea"
        payload.append(contentsOf: suffix)

        let data = Data(payload)
        pod.peripheral.writeValue(data, for: uartRX, type: .withResponse)
        logger.info("Sent auth payload to \(pod.name): \(payload.map { String(format: "%02X", $0) }.joined(separator: " "))")
    }

    private func computeAuthSuffix(mfrData: Data) -> [UInt8] {
        let dataWithoutCompanyID: Data
        if mfrData.count > 2 {
            dataWithoutCompanyID = mfrData.dropFirst(2)
        } else {
            dataWithoutCompanyID = mfrData
        }

        guard dataWithoutCompanyID.count >= 5 else {
            logger.error("Manufacturer data too short for auth: \(dataWithoutCompanyID.count) bytes (need >= 5)")
            return []
        }

        let tail = [UInt8](dataWithoutCompanyID.suffix(5))
        let offset = tail[0]
        let byteArray = Array(tail[1..<5])

        let poly: UInt32 = (0xEDB88321 &+ UInt32(offset % 50)) & 0xFFFFFFFF

        var crc: UInt32 = 0xFFFFFFFF
        for b in byteArray {
            crc ^= UInt32(b)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = ((crc >> 1) ^ poly) & 0xFFFFFFFF
                } else {
                    crc = (crc >> 1) & 0xFFFFFFFF
                }
            }
        }

        crc ^= 0xFFFFFFFF
        crc &= 0xFFFFFFFF

        crc = (crc &+ ((crc << 3) & 0xFFFFFFFF)) & 0xFFFFFFFF
        crc = (crc ^ (crc >> 11)) & 0xFFFFFFFF
        crc = (crc &+ ((crc << 15) & 0xFFFFFFFF)) & 0xFFFFFFFF

        return [
            UInt8(crc & 0xFF),
            UInt8((crc >> 8) & 0xFF),
            UInt8((crc >> 16) & 0xFF),
            UInt8((crc >> 24) & 0xFF)
        ]
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        logger.info("Bluetooth state: \(central.state.rawValue)")
        if central.state != .poweredOn && isScanning {
            isScanning = false
        }
        if central.state == .poweredOn && !pendingReconnectUUIDs.isEmpty {
            let pending = pendingReconnectUUIDs
            pendingReconnectUUIDs = []
            performReconnect(pending)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let mfrData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String

        if connectedPods.contains(where: { $0.id == peripheral.identifier }) { return }

        guard isBlazePod(manufacturerData: mfrData, name: name) else { return }

        if let idx = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            discoveredDevices[idx].rssi = RSSI.intValue
            if let data = mfrData { discoveredDevices[idx].manufacturerData = data }
            if let n = name { discoveredDevices[idx].name = n }
        } else {
            let device = PodDevice(peripheral: peripheral, name: name, rssi: RSSI.intValue, manufacturerData: mfrData)
            discoveredDevices.append(device)
            logger.info("Discovered BlazePod: \(device.name) RSSI=\(RSSI.intValue)")

            // Auto-detect: connect immediately
            if autoDetectEnabled {
                connectPod(device)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let pod = connectedPods.first(where: { $0.id == peripheral.identifier }) else { return }
        pod.connectionState = .connected
        peripheral.delegate = self
        peripheral.discoverServices([uartServiceUUID, colorServiceUUID, tapServiceUUID,
                                      batteryServiceUUID, disServiceUUID])
        logger.info("Connected to \(pod.name), discovering services")
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard let pod = connectedPods.first(where: { $0.id == peripheral.identifier }) else { return }
        pod.connectionState = .error
        pod.errorMessage = error?.localizedDescription ?? "Connection failed"
        logger.error("Failed to connect \(pod.name): \(error?.localizedDescription ?? "unknown")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let pod = connectedPods.first(where: { $0.id == peripheral.identifier }) else { return }
        pod.connectionState = .disconnected
        pod.uartRXCharacteristic = nil
        pod.colorCharacteristic = nil
        pod.tapCharacteristic = nil
        logger.info("Disconnected from \(pod.name)")
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            switch service.uuid {
            case uartServiceUUID:
                peripheral.discoverCharacteristics([uartRXCharUUID], for: service)
            case colorServiceUUID:
                peripheral.discoverCharacteristics([colorCharUUID], for: service)
            case tapServiceUUID:
                peripheral.discoverCharacteristics([tapCharUUID], for: service)
            case batteryServiceUUID:
                peripheral.discoverCharacteristics([batteryLevelCharUUID], for: service)
            case disServiceUUID:
                peripheral.discoverCharacteristics([disSerialCharUUID, disFwRevCharUUID,
                                                     disHwRevCharUUID, disSwRevCharUUID,
                                                     disModelCharUUID, disMfrCharUUID], for: service)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let pod = connectedPods.first(where: { $0.id == peripheral.identifier }),
              let chars = service.characteristics else { return }

        for char in chars {
            switch char.uuid {
            case uartRXCharUUID:
                pod.uartRXCharacteristic = char
                logger.info("Found UART RX for \(pod.name)")
            case colorCharUUID:
                pod.colorCharacteristic = char
                logger.info("Found Color char for \(pod.name)")
            case tapCharUUID:
                pod.tapCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
                logger.info("Found Tap char for \(pod.name), subscribing")
            case batteryLevelCharUUID:
                peripheral.readValue(for: char)
                peripheral.setNotifyValue(true, for: char)
                logger.info("Found Battery Level for \(pod.name), reading")
            case disSerialCharUUID, disFwRevCharUUID, disHwRevCharUUID,
                 disSwRevCharUUID, disModelCharUUID, disMfrCharUUID:
                peripheral.readValue(for: char)
                logger.info("Reading DIS char \(char.uuid.uuidString) for \(pod.name)")
            default:
                break
            }
        }

        if pod.uartRXCharacteristic != nil && pod.connectionState == .connected {
            authenticate(pod)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let pod = connectedPods.first(where: { $0.id == peripheral.identifier }) else { return }

        if characteristic.uuid == uartRXCharUUID {
            if let error = error {
                pod.connectionState = .error
                pod.errorMessage = "Auth write failed: \(error.localizedDescription)"
                logger.error("Auth write failed for \(pod.name): \(error.localizedDescription)")
            } else {
                pod.connectionState = .authenticated
                logger.info("Authenticated \(pod.name) ✓")
                onPodAutoConnected?(pod)
            }
        } else if characteristic.uuid == colorCharUUID {
            if let error = error {
                logger.error("Color write failed for \(pod.name): \(error.localizedDescription)")
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let pod = connectedPods.first(where: { $0.id == peripheral.identifier }) else { return }

        switch characteristic.uuid {
        case tapCharUUID:
            guard let data = characteristic.value, let event = TapEvent(data: data) else {
                if let data = characteristic.value {
                    logger.warning("Bad tap payload from \(pod.name): \(data.map { String(format: "%02X", $0) }.joined())")
                }
                return
            }
            pod.lastTapEvent = event
            logger.info("Tap from \(pod.name): state=0x\(String(format: "%02X", event.state.rawValue)) time=\(event.elapsedMs)ms")
            onTapReceived?(pod, event)

        case batteryLevelCharUUID:
            if let data = characteristic.value, let level = data.first {
                pod.batteryLevel = Int(level)
                logger.info("Battery \(pod.name): \(level)%")
            }

        case disSerialCharUUID:
            pod.bleSerialNumber = characteristic.value.flatMap { String(data: $0, encoding: .utf8) }
            logger.info("Serial \(pod.name): \(pod.bleSerialNumber ?? "nil")")
        case disFwRevCharUUID:
            pod.firmwareRevision = characteristic.value.flatMap { String(data: $0, encoding: .utf8) }
        case disHwRevCharUUID:
            pod.hardwareRevision = characteristic.value.flatMap { String(data: $0, encoding: .utf8) }
        case disSwRevCharUUID:
            pod.softwareRevision = characteristic.value.flatMap { String(data: $0, encoding: .utf8) }
        case disModelCharUUID:
            pod.modelNumber = characteristic.value.flatMap { String(data: $0, encoding: .utf8) }
        case disMfrCharUUID:
            pod.manufacturerName = characteristic.value.flatMap { String(data: $0, encoding: .utf8) }

        default:
            break
        }
    }
}
