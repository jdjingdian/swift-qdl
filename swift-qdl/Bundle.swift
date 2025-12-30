//
//  Bundle.swift
//  swift-qdl
//
//  Created by 经典 on 2025/12/30.
//

import Foundation

extension Bundle {
    var appVersion: String {
        (object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0.0.0"
    }

    var appBuild: String {
        (object(forInfoDictionaryKey: "CFBundleVersion") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
    }
}
