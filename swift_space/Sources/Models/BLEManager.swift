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

@Observable
class BLEManager: NSObject {
    private let logger = Logger(subsystem: "com.hejuno.lightpods", category: "BLE")
    
    private var centralManager: CBCentralManager!
    
    var isScanning = false
    var bluetoothState: CBManagerState = .unknown
    var discoveredDevices: [PodDevice] = []
    var connectedPods: [PodDevice] = []
    
    /// Callback when a tap is received from any pod
    var onTapReceived: ((PodDevice, UInt8, UInt32) -> Void)?
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Scanning
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
        logger.info("Started BLE scanning")
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        logger.info("Stopped BLE scanning")
    }
    
    // MARK: - Connection
    func connectPod(_ device: PodDevice) {
        // Move from discovered to connected
        if let idx = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices.remove(at: idx)
        }
        device.connectionState = .connecting
        if !connectedPods.contains(where: { $0.id == device.id }) {
            connectedPods.append(device)
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
    }
    
    // MARK: - Pod Commands
    func lightUp(_ pod: PodDevice, color: PodColor) {
        guard pod.connectionState == .authenticated,
              let char = pod.colorCharacteristic else {
            logger.warning("Cannot light up \(pod.name): not authenticated or no characteristic")
            return
        }
        var bytes = color.gbrBytes
        bytes.append(0x01) // auto-off on tap
        let data = Data(bytes)
        pod.peripheral.writeValue(data, for: char, type: .withResponse)
        logger.info("Sent color \(color.rawValue) to \(pod.name)")
    }
    
    // MARK: - Auth
    private func authenticate(_ pod: PodDevice) {
        guard let mfrData = pod.manufacturerData, mfrData.count >= 5 else {
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
        
        let last5 = [UInt8](mfrData.suffix(5))
        let offset = UInt32(last5[0])
        let authBytes = Array(last5[1...])
        
        var val: UInt32 = 0
        for (i, b) in authBytes.enumerated() {
            val ^= UInt32(b) << (i * 8)
        }
        val = val &+ offset  // wrapping add
        
        // "sea" prefix + 4 byte LE auth value
        var payload: [UInt8] = [0x73, 0x65, 0x61]
        payload.append(UInt8(val & 0xFF))
        payload.append(UInt8((val >> 8) & 0xFF))
        payload.append(UInt8((val >> 16) & 0xFF))
        payload.append(UInt8((val >> 24) & 0xFF))
        
        let data = Data(payload)
        pod.peripheral.writeValue(data, for: uartRX, type: .withResponse)
        logger.info("Sent auth payload to \(pod.name): \(payload.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        // Auth is considered successful after write completes
        // (we'll set authenticated in didWriteValueFor)
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
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let mfrData = advertisementData["kCBAdvDataManufacturerData"] as? Data
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        
        // Skip devices already connected
        if connectedPods.contains(where: { $0.id == peripheral.identifier }) { return }
        
        if let idx = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            // Update existing
            discoveredDevices[idx].rssi = RSSI.intValue
            if let data = mfrData { discoveredDevices[idx].manufacturerData = data }
            if let n = name { discoveredDevices[idx].name = n }
        } else {
            // Only show devices with a name or manufacturer data (filter noise)
            guard name != nil || mfrData != nil else { return }
            let device = PodDevice(peripheral: peripheral, name: name, rssi: RSSI.intValue, manufacturerData: mfrData)
            discoveredDevices.append(device)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let pod = connectedPods.first(where: { $0.id == peripheral.identifier }) else { return }
        pod.connectionState = .connected
        peripheral.delegate = self
        peripheral.discoverServices([uartServiceUUID, colorServiceUUID, tapServiceUUID])
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
            default:
                break
            }
        }
        
        // Try to authenticate once we have UART RX
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
                logger.info("Authenticated \(pod.name)")
            }
        } else if characteristic.uuid == colorCharUUID {
            if let error = error {
                logger.error("Color write failed for \(pod.name): \(error.localizedDescription)")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == tapCharUUID,
              let data = characteristic.value,
              data.count >= 5,
              let pod = connectedPods.first(where: { $0.id == peripheral.identifier }) else { return }
        
        let state = data[0]
        let ms = UInt32(data[1]) | (UInt32(data[2]) << 8) | (UInt32(data[3]) << 16) | (UInt32(data[4]) << 24)
        
        pod.lastReactionTimeMs = ms
        logger.info("Tap from \(pod.name): state=0x\(String(format: "%02X", state)) time=\(ms)ms")
        
        onTapReceived?(pod, state, ms)
    }
}
