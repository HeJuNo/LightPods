import Foundation
import SwiftData

@Model
class SavedPod {
    @Attribute(.unique) var peripheralUUID: String
    var name: String
    var alias: String?
    var serialNumber: String?
    var comment: String?
    var podDescription: String?
    var manufacturerDataHex: String?
    var groups: [PodGroup]? = []

    init(peripheralUUID: String, name: String, manufacturerDataHex: String? = nil) {
        self.peripheralUUID = peripheralUUID
        self.name = name
        self.manufacturerDataHex = manufacturerDataHex
    }

    /// Display name: alias if set, otherwise BLE name
    var displayName: String {
        if let a = alias, !a.isEmpty { return a }
        return name
    }
}

@Model
class PodGroup {
    var name: String
    @Relationship(deleteRule: .nullify, inverse: \SavedPod.groups)
    var pods: [SavedPod]? = []
    var createdAt: Date = Date()

    init(name: String) {
        self.name = name
    }
}
