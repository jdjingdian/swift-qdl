//
//  ContentView.swift
//  qdl
//
//  Created by 经典 on 2025/12/24.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @StateObject private var vm = DeviceViewModel()
    @State private var version: String = ""
    @State private var showPortPicker = false

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("QDL Version: \(version)")

            if let sel = vm.selected {
                VStack(alignment: .leading) {
                    Text("Selected:")
                        .font(.subheadline)
                    Text("Serial: \(sel.serial)")
                    Text("Product: \(sel.product)")
                }
                .padding()

                // Mode picker and file selection in main view
                Picker("Mode", selection: Binding(get: { vm.mode == .download ? 0 : 1 }, set: { vm.mode = $0 == 0 ? .download : .provision })) {
                    Text("Download").tag(0)
                    Text("Provision").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.vertical)

                VStack(alignment: .leading, spacing: 8) {
                    Button("选择 Programmer (.elf)") {
                        if let path = openFile(allowed: ["elf"], allowsMultiple: false) {
                            vm.programmerPath = path
                        }
                    }
                    Text(vm.programmerPath ?? "未选择")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if vm.mode == .download {
                        Button("选择 rawprogram(s).xml") {
                            let paths = openFiles(allowed: ["xml"], filterPrefix: "rawprogram")
                            vm.rawprogramPaths = paths
                        }
                        Text(vm.rawprogramPaths.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("选择 patch(es).xml") {
                            let paths = openFiles(allowed: ["xml"], filterPrefix: "patch")
                            vm.patchPaths = paths
                        }
                        Text(vm.patchPaths.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Button("选择 provision(s).xml") {
                            let paths = openFiles(allowed: ["xml"], filterPrefix: "provision")
                            vm.provisionPaths = paths
                        }
                        Text(vm.provisionPaths.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Button("Start") {
                            vm.start()
                        }
                        .disabled(!vm.canStart)
                        Button("选择端口") {
                            showPortPicker = true
                        }
                    }
                    // Progress and status in main view
                    if vm.isRunning {
                        VStack(alignment: .leading) {
                            Text(vm.progressTask).font(.subheadline)
                            ProgressView(value: vm.progressPercent)
                            HStack {
                                Text(String(format: "%.1f%%", vm.progressPercent * 100))
                                Spacer()
                                Button("Cancel") {
                                    // TODO: cancellation support if qdl supports it
                                }
                            }
                        }
                        .padding(.top)
                    }

                    if let res = vm.runResult {
                        Text("Run result: \(res)").foregroundColor(res == 0 ? .green : .red)
                    }
                }
                .padding(.top)
            } else {
                Button("选择端口") {
                    showPortPicker = true
                }
            }
        }
        .padding()
        .onAppear {
            version = String(cString: qdl_version())
        }
        .sheet(isPresented: $showPortPicker) {
            PortPickerView(viewModel: vm, isPresented: $showPortPicker)
                .onAppear { vm.queryDevices() }
        }
    }
}

struct PortPickerView: View {
    @ObservedObject var viewModel: DeviceViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("可用设备列表")
                .font(.headline)
            if viewModel.isQuerying {
                ProgressView("查询中...")
            } else if viewModel.devices.isEmpty {
                Text("无设备")
                    .foregroundColor(.secondary)
            } else {
                            // Progress and status
                            if viewModel.isRunning {
                                VStack(alignment: .leading) {
                                    Text(viewModel.progressTask).font(.subheadline)
                                    ProgressView(value: viewModel.progressPercent)
                                    HStack {
                                        Text(String(format: "%.1f%%", viewModel.progressPercent * 100))
                                        Spacer()
                                        Button("Cancel") {
                                            // TODO: cancellation support if qdl supports it
                                        }
                                    }
                                }
                                .padding(.top)
                            }

                            if let res = viewModel.runResult {
                                Text("Run result: \(res)").foregroundColor(res == 0 ? .green : .red)
                            }
                ForEach(viewModel.devices) { d in
                    Button("\(d.serial) (\(d.product))") {
                        viewModel.selected = d
                        isPresented = false
                    }
                    .padding(.vertical, 4)
                }
            }
            HStack {
                Button("刷新设备列表") { viewModel.queryDevices() }
                    .disabled(viewModel.isQuerying)
                Button("关闭") { isPresented = false }
            }
        }
        .padding()
    }
}

// MARK: - File open helpers (macOS)
fileprivate func openFile(allowed: [String], allowsMultiple: Bool) -> String? {
    #if os(macOS)
    let panel = NSOpenPanel()
    panel.allowedFileTypes = allowed
    panel.allowsMultipleSelection = allowsMultiple
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    let resp = panel.runModal()
    if resp == .OK, let url = panel.urls.first {
        return url.path
    }
    #endif
    return nil
}

fileprivate func openFiles(allowed: [String], filterPrefix: String) -> [String] {
    #if os(macOS)
    let panel = NSOpenPanel()
    panel.allowedFileTypes = allowed
    panel.allowsMultipleSelection = true
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    let resp = panel.runModal()
    if resp == .OK {
        return panel.urls.map { $0.path }.filter { url in
            let name = URL(fileURLWithPath: url).lastPathComponent.lowercased()
            return name.hasPrefix(filterPrefix.lowercased())
        }
    }
    #endif
    return []
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
