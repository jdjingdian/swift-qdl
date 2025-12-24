//
// DeviceModel.swift
// qdl
//

import Foundation

struct DeviceInfo: Identifiable, Equatable {
    let id = UUID()
    let serial: String
    let product: String
}
