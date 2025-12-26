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
        let destName = "\(String(format: "%03d", idx))_\(src.lastPathComponent)"
        let dest = tmpDir.appendingPathComponent(destName)
        do {
            try fm.createSymbolicLink(at: dest, withDestinationURL: src)
            created.append(dest)
        } catch {
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
            let resolved = (try? URL(resolvingAliasFileAt: url)) ?? url.resolvingSymlinksInPath()
            results.append(resolved.path)
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

// Orchestrate firmware selection (full flow) - kept for convenience if needed elsewhere
func runFirmwareSelection(viewModel: DeviceViewModel) {
    #if os(macOS)
    let fm = FileManager.default

    // 1) choose firmware directory
    let dirPanel = NSOpenPanel()
    dirPanel.canChooseDirectories = true
    dirPanel.canChooseFiles = false
    dirPanel.allowsMultipleSelection = false
    dirPanel.title = NSLocalizedString("firmware_dir_panel_title", comment: "firmware directory panel title")
    dirPanel.prompt = NSLocalizedString("firmware_dir_panel_prompt", comment: "firmware directory panel prompt")
    dirPanel.message = NSLocalizedString("firmware_dir_panel_message", comment: "firmware directory panel message")
    if let last = viewModel.firmwareDirectory, FileManager.default.fileExists(atPath: last) {
        dirPanel.directoryURL = URL(fileURLWithPath: last)
    } else {
        dirPanel.directoryURL = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    var dirResp: NSApplication.ModalResponse = .cancel
    if Thread.isMainThread { dirResp = dirPanel.runModal() } else { DispatchQueue.main.sync { dirResp = dirPanel.runModal() } }
    guard dirResp == .OK, let dirURL = dirPanel.url else { return }

    // remember chosen directory for reuse
    viewModel.firmwareDirectory = dirURL.path

    // 2) enumerate matches and create tmp dir with subfolders
    var elfMatches: [URL] = []
    var xmlMatches: [URL] = []
    if let enumerator = fm.enumerator(at: dirURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: nil) {
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "elf" { elfMatches.append(fileURL) }
            else if ext == "xml" { xmlMatches.append(fileURL) }
        }
    }
    if elfMatches.isEmpty && xmlMatches.isEmpty { return }

    let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("qdl_tmp_\(UUID().uuidString)")
    do { try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true) } catch { return }

    var mapping: [URL: URL] = [:]
    func makeLinks(_ sources: [URL], into subfolder: String) {
        let folder = tmpDir.appendingPathComponent(subfolder)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for (idx, src) in sources.enumerated() {
            let dest = folder.appendingPathComponent("\(String(format: "%03d", idx))_\(src.lastPathComponent)")
            do { try fm.createSymbolicLink(at: dest, withDestinationURL: src); mapping[dest] = src } catch { do { try fm.copyItem(at: src, to: dest); mapping[dest] = src } catch { } }
        }
    }

    makeLinks(elfMatches, into: "elfs")
    makeLinks(xmlMatches, into: "xmls")

    // 3) ask user to choose programmer (.elf) if any
    if !elfMatches.isEmpty {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["elf"]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = tmpDir.appendingPathComponent("elfs")

        var resp: NSApplication.ModalResponse = .cancel
        if Thread.isMainThread { resp = panel.runModal() } else { DispatchQueue.main.sync { resp = panel.runModal() } }
        if resp == .OK, let sel = panel.url { viewModel.programmerPath = sel.path }
    }

    // 4) xml selection depending on mode
    if viewModel.mode == .download {
        let rawPanel = NSOpenPanel()
        rawPanel.allowedFileTypes = ["xml"]
        rawPanel.allowsMultipleSelection = true
        rawPanel.canChooseFiles = true
        rawPanel.canChooseDirectories = false
        rawPanel.directoryURL = tmpDir.appendingPathComponent("xmls")

        var rawResp: NSApplication.ModalResponse = .cancel
        if Thread.isMainThread { rawResp = rawPanel.runModal() } else { DispatchQueue.main.sync { rawResp = rawPanel.runModal() } }
        if rawResp == .OK {
            var rawpaths: [String] = []
            var patchpaths: [String] = []
            var origDirForFirstRaw: URL? = nil
            for u in rawPanel.urls {
                let selPath = u.path
                let orig = mapping[u]
                let origName = orig?.lastPathComponent ?? u.resolvingSymlinksInPath().lastPathComponent
                let name = origName.lowercased()
                if name.hasPrefix("rawprogram") {
                    rawpaths.append(selPath)
                    if origDirForFirstRaw == nil { origDirForFirstRaw = orig?.deletingLastPathComponent() ?? URL(fileURLWithPath: selPath).resolvingSymlinksInPath().deletingLastPathComponent() }
                } else if name.hasPrefix("patch") { patchpaths.append(selPath) }
            }

            if patchpaths.isEmpty, let origDir = origDirForFirstRaw {
                if let xmls = try? fm.contentsOfDirectory(at: origDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for f in xmls where f.pathExtension.lowercased() == "xml" {
                        let name = f.lastPathComponent.lowercased()
                        if name.hasPrefix("patch") {
                            let dest = tmpDir.appendingPathComponent("auto_patch_\(f.lastPathComponent)")
                            if !fm.fileExists(atPath: dest.path) { try? fm.createSymbolicLink(at: dest, withDestinationURL: f); mapping[dest] = f; patchpaths.append(dest.path) }
                        }
                    }
                }
            }

            viewModel.rawprogramPaths = rawpaths
            viewModel.patchPaths = patchpaths
        }
    } else {
        let provPanel = NSOpenPanel()
        provPanel.allowedFileTypes = ["xml"]
        provPanel.allowsMultipleSelection = true
        provPanel.canChooseFiles = true
        provPanel.canChooseDirectories = false
        provPanel.directoryURL = tmpDir.appendingPathComponent("xmls")

        var provResp: NSApplication.ModalResponse = .cancel
        if Thread.isMainThread { provResp = provPanel.runModal() } else { DispatchQueue.main.sync { provResp = provPanel.runModal() } }
        if provResp == .OK { viewModel.provisionPaths = provPanel.urls.map { $0.path } }
    }

    try? fm.removeItem(at: tmpDir)

    DispatchQueue.main.async {
        print("Selected programmer: \(viewModel.programmerPath ?? "(nil)")")
        print("Selected rawprograms: \(viewModel.rawprogramPaths)")
        print("Selected patches: \(viewModel.patchPaths)")
        print("Selected provisions: \(viewModel.provisionPaths)")
    }
    #endif
}
