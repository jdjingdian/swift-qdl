//
// DeviceModel.swift
// qdl
//

import Foundation

struct DeviceInfo: Identifiable, Equatable, Hashable {
    let id = UUID()
    let serial: String
    let product: String

    // Synthesized Hashable is fine, but provide explicit implementation
    // to ensure stability across runs (hash only uses id)
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DeviceInfo, rhs: DeviceInfo) -> Bool {
        return lhs.id == rhs.id
    }
}
