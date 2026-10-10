import SwiftUI
import CoreBluetooth

struct ScanView: View {
    var bleManager: BLEManager
    
    var body: some View {
        List {
            if bleManager.bluetoothState != .poweredOn {
                Section {
                    bluetoothStatusView
                }
            }
            
            if bleManager.discoveredDevices.isEmpty && bleManager.isScanning {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Scanning for pods…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else if bleManager.discoveredDevices.isEmpty && !bleManager.isScanning {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No devices found")
                            .font(.headline)
                        Text("Tap Scan to discover nearby BlazePods")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
            } else {
                Section("Discovered Devices (\(bleManager.discoveredDevices.count))") {
                    ForEach(bleManager.discoveredDevices) { device in
                        DiscoveredDeviceRow(device: device) {
                            bleManager.connectPod(device)
                        }
                    }
                }
            }
        }
        .navigationTitle("Scan")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if bleManager.isScanning {
                        bleManager.stopScanning()
                    } else {
                        bleManager.startScanning()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if bleManager.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(bleManager.isScanning ? "Stop" : "Scan")
                    }
                }
                .disabled(bleManager.bluetoothState != .poweredOn)
            }
        }
    }
    
    @ViewBuilder
    private var bluetoothStatusView: some View {
        VStack(spacing: 8) {
            Image(systemName: "bluetooth")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            switch bleManager.bluetoothState {
            case .poweredOff:
                Text("Bluetooth is turned off")
                    .font(.headline)
                Text("Enable Bluetooth in Settings to scan for pods.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .unauthorized:
                Text("Bluetooth permission denied")
                    .font(.headline)
                Text("Allow Bluetooth access in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .unsupported:
                Text("Bluetooth not supported")
                    .font(.headline)
            default:
                Text("Bluetooth is not available")
                    .font(.headline)
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

struct DiscoveredDeviceRow: View {
    var device: PodDevice
    var onAdd: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                if let mfr = device.manufacturerData {
                    Text(mfr.map { String(format: "%02X", $0) }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
            }
            
            Spacer()
            
            rssiView
            
            Button("Add") {
                onAdd()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
    
    private var rssiView: some View {
        HStack(spacing: 2) {
            Image(systemName: rssiIcon)
                .foregroundStyle(rssiColor)
            Text("\(device.rssi)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
    
    private var rssiIcon: String {
        if device.rssi > -50 { return "wifi.circle.fill" }
        if device.rssi > -70 { return "wifi.circle" }
        return "wifi.exclamationmark.circle"
    }
    
    private var rssiColor: Color {
        if device.rssi > -50 { return .green }
        if device.rssi > -70 { return .yellow }
        return .red
    }
}
