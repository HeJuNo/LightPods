import SwiftUI
import SwiftData
import VisionKit

/// Edit form for a saved pod's metadata
struct PodEditView: View {
    @Bindable var saved: SavedPod
    var bleManager: BLEManager?
    @Environment(\.dismiss) private var dismiss

    @State private var alias: String = ""
    @State private var serialNumber: String = ""
    @State private var comment: String = ""
    @State private var podDescription: String = ""
    @State private var showQRScanner = false

    private var connectedPod: PodDevice? {
        bleManager?.connectedPods.first { $0.id.uuidString == saved.peripheralUUID }
    }

    var body: some View {
        Form {
            Section("Identity") {
                LabeledContent("BLE Name", value: saved.name)
                    .foregroundStyle(.secondary)
                LabeledContent("UUID") {
                    Text(saved.peripheralUUID)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let pod = connectedPod {
                    if let battery = pod.batteryLevel {
                        LabeledContent("Battery") {
                            HStack(spacing: 4) {
                                Image(systemName: pod.batteryIconName)
                                    .foregroundStyle(pod.batteryColor)
                                Text("\(battery)%")
                            }
                        }
                    }
                    if let fw = pod.firmwareRevision {
                        LabeledContent("Firmware", value: fw)
                    }
                    if let hw = pod.hardwareRevision {
                        LabeledContent("Hardware", value: hw)
                    }
                    if let sw = pod.softwareRevision {
                        LabeledContent("Software", value: sw)
                    }
                    if let model = pod.modelNumber {
                        LabeledContent("Model", value: model)
                    }
                    if let mfr = pod.manufacturerName {
                        LabeledContent("Manufacturer", value: mfr)
                    }
                    if let serial = pod.bleSerialNumber {
                        LabeledContent("BLE Serial", value: serial)
                    }
                }
            }

            Section("Pod Details") {
                editField("Alias", text: $alias, icon: "tag")
                HStack {
                    editField("Serial Number", text: $serialNumber, icon: "number")
                    if DataScannerViewController.isSupported {
                        Button {
                            showQRScanner = true
                        } label: {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title3)
                        }
                    }
                }
                editField("Description", text: $podDescription, icon: "text.alignleft")
            }

            Section("Notes") {
                TextField("Comment", text: $comment, axis: .vertical)
                    .lineLimit(3...6)
            }

            if let ble = bleManager,
               let pod = ble.connectedPods.first(where: { $0.id.uuidString == saved.peripheralUUID }),
               pod.connectionState == .authenticated {
                Section("Identify") {
                    Button {
                        ble.flash(pod, color: .white, count: 5, onMs: 300, offMs: 200)
                    } label: {
                        Label("Flash Pod", systemImage: "light.max")
                    }
                }
            }
        }
        .navigationTitle("Edit Pod")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    applyChanges()
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showQRScanner) {
            NavigationStack {
                QRScannerView { code in
                    serialNumber = code
                }
                .navigationTitle("Scan QR Code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { showQRScanner = false }
                    }
                }
                .ignoresSafeArea()
            }
        }
        .onAppear {
            alias = saved.alias ?? ""
            serialNumber = saved.serialNumber ?? ""
            comment = saved.comment ?? ""
            podDescription = saved.podDescription ?? ""
        }
    }

    private func editField(_ placeholder: String, text: Binding<String>, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            TextField(placeholder, text: text)
        }
    }

    private func applyChanges() {
        saved.alias = alias.isEmpty ? nil : alias
        saved.serialNumber = serialNumber.isEmpty ? nil : serialNumber
        saved.comment = comment.isEmpty ? nil : comment
        saved.podDescription = podDescription.isEmpty ? nil : podDescription
    }
}
