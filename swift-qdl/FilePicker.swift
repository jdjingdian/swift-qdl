//
//  FilePicker.swift
//  Helpers for firmware file selection and filtering moved out of ContentView
//

import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

// open a single file using the filtered tmp-dir approach
func openSingleFiltered(allowed: [String], filterPattern: String = "*", startDir: String? = nil) -> String? {
    #if os(macOS)
    let results = openFiles(allowed: allowed, filterPattern: filterPattern, startDir: startDir)
    return results.first
    #else
    return nil
    #endif
}

// openFiles: enumerate files under a firmware directory matching a glob-style pattern,
// create a temporary directory with symlinks to matched files and present an NSOpenPanel
func openFiles(allowed: [String], filterPattern: String = "*", startDir: String? = nil) -> [String] {
    #if os(macOS)
    let fm = FileManager.default

    // Step 1: determine firmware directory (either provided or ask user)
    var chosenDir: URL? = nil
    if let sd = startDir {
        chosenDir = URL(fileURLWithPath: sd)
    } else {
        let dirPanel = NSOpenPanel()
        dirPanel.canChooseDirectories = true
        dirPanel.canChooseFiles = false
        dirPanel.allowsMultipleSelection = false
    dirPanel.title = NSLocalizedString("firmware_dir_panel_title", comment: "firmware directory panel title")
    dirPanel.prompt = NSLocalizedString("firmware_dir_panel_prompt", comment: "firmware directory panel prompt")
    dirPanel.message = NSLocalizedString("firmware_dir_panel_message", comment: "firmware directory panel message")
        dirPanel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())

        var dirResp: NSApplication.ModalResponse = .cancel
        if Thread.isMainThread {
            dirResp = dirPanel.runModal()
        } else {
            DispatchQueue.main.sync { dirResp = dirPanel.runModal() }
        }
        guard dirResp == .OK, let picked = dirPanel.url else { return [] }
        chosenDir = picked
    }

    guard let dirURL = chosenDir else { return [] }

    // Step 2: enumerate matching files using glob-style filterPattern
    var matches: [URL] = []
    let lowerAllowed = allowed.map { $0.lowercased() }
    let pattern = filterPattern
    let regex: NSRegularExpression? = {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let pat = escaped.replacingOccurrences(of: "\\*", with: ".*").replacingOccurrences(of: "\\?", with: ".")
        return try? NSRegularExpression(pattern: "^\(pat)$", options: [.caseInsensitive])
    }()
    if let enumerator = fm.enumerator(at: dirURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: nil) {
        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            if lowerAllowed.contains(fileURL.pathExtension.lowercased()) {
                if pattern == "*" {
                    matches.append(fileURL)
                } else if let r = regex {
                    let range = NSRange(location: 0, length: name.utf16.count)
                    if r.firstMatch(in: name, options: [], range: range) != nil {
                        matches.append(fileURL)
                    }
                }
            }
        }
    }

    if matches.isEmpty { return [] }

    // Step 3: create temporary folder with symlinks to matches
    let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("qdl_tmp_\(UUID().uuidString)")
    do { try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true) } catch { return [] }

    var created: [URL] = []
    for (idx, src) in matches.enumerated() {
        /*
         Use this syntax to avoid file name conflicts.
         let destName = "\(String(format: "%03d", idx))_\(src.lastPathComponent)"
         */
        let destName = "\(src.lastPathComponent)"
        let dest = tmpDir.appendingPathComponent(destName)
        // Create a macOS bookmark (alias) file pointing to the original file.
        // This allows the open panel to resolve back to the original path and supports multi-selection.
        if FileManager.default.createFile(atPath: dest.path, contents: nil, attributes: nil) {
            do {
                let bookmark = try src.bookmarkData(options: [.suitableForBookmarkFile], includingResourceValuesForKeys: nil, relativeTo: nil)
                try URL.writeBookmarkData(bookmark, to: dest)
                created.append(dest)
            } catch {
                // fallback: try copying the file if bookmark creation fails
                do {
                    try fm.removeItem(at: dest)
                } catch { }
                do { try fm.copyItem(at: src, to: dest); created.append(dest) } catch { }
            }
        } else {
            // couldn't create placeholder file, fallback to copy
            do { try fm.copyItem(at: src, to: dest); created.append(dest) } catch { }
        }
    }

    // Step 4: present open panel pointing to tmpDir so user sees only matched files
    let panel = NSOpenPanel()
    panel.allowedFileTypes = allowed
    panel.allowsMultipleSelection = true
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.directoryURL = tmpDir
    var resp: NSApplication.ModalResponse = .cancel
    if Thread.isMainThread { resp = panel.runModal() } else { DispatchQueue.main.sync { resp = panel.runModal() } }
    var results: [String] = []
    if resp == .OK {
        for url in panel.urls {
            var resolvedURL: URL? = nil
            // 1. try resolving Finder alias file (older API)
            if let aliasResolved = try? URL(resolvingAliasFileAt: url) {
                resolvedURL = aliasResolved
            }

            // 2. try resolving bookmark data if present
            if resolvedURL == nil {
                // attempt to read bookmark file and resolve it
                if let bookmark = try? URL.bookmarkData(withContentsOf: url) {
                    var isStale: Bool = false
                    if let bmResolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                        resolvedURL = bmResolved
                    }
                } else {
                    // attempt to read raw bookmark data directly from file as fallback
                    if let bmData = try? Data(contentsOf: url) {
                        var isStale2: Bool = false
                        if let bmResolved2 = try? URL(resolvingBookmarkData: bmData, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &isStale2) {
                            resolvedURL = bmResolved2
                        }
                    }
                }
            }

            // 3. last resort: resolve symlinks in path
            if resolvedURL == nil {
                resolvedURL = url.resolvingSymlinksInPath()
            }

            if let r = resolvedURL {
                results.append(r.path)
            }
        }
    }

    // cleanup
    try? fm.removeItem(at: tmpDir)
    return results
    #else
    return []
    #endif
}

// helper: let user pick a firmware directory and store it into the view model
func selectFirmwareDirectory(viewModel: DeviceViewModel) {
    #if os(macOS)
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.title = NSLocalizedString("firmware_root_panel_title", comment: "firmware root panel title")
    panel.prompt = NSLocalizedString("firmware_root_panel_prompt", comment: "firmware root panel prompt")
    if let last = viewModel.firmwareDirectory, FileManager.default.fileExists(atPath: last) {
        panel.directoryURL = URL(fileURLWithPath: last)
    } else {
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    var resp: NSApplication.ModalResponse = .cancel
    if Thread.isMainThread { resp = panel.runModal() } else { DispatchQueue.main.sync { resp = panel.runModal() } }
    if resp == .OK, let url = panel.url {
        DispatchQueue.main.async { viewModel.firmwareDirectory = url.path }
    }
    #endif
}
