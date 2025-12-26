import SwiftUI

struct DownloadModeView: View {
    @ObservedObject var viewModel: DeviceViewModel

    var body: some View {
        GroupBox(label: Label("操作", systemImage: "gearshape")) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Mode", selection: Binding(get: { viewModel.mode == .download ? 0 : 1 }, set: { viewModel.mode = $0 == 0 ? .download : .provision })) {
                    Text("Download").tag(0)
                    Text("Provision").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())

                Picker("Storage Type", selection: $viewModel.storageType) {
                    ForEach(DeviceViewModel.StorageType.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("选择 固件主目录") { selectFirmwareDirectory(viewModel: viewModel) }
                        .buttonStyle(.bordered)
                        Spacer()
                        Text(viewModel.firmwareDirectory ?? "未选择主目录").font(.caption).foregroundColor(.secondary)
                    }

                    HStack {
                        Button("选择 Programmer (.elf)") {
                            if let path = openSingleFiltered(allowed: ["elf"], filterPattern: "*firehose*.elf", startDir: viewModel.firmwareDirectory) {
                                viewModel.programmerPath = path
                            }
                        }
                        Spacer()
                        Text(viewModel.programmerPath ?? "未选择").font(.caption).foregroundColor(.secondary)
                    }

                    if viewModel.mode == .download {
                        HStack {
                            Button("选择 rawprogram(s).xml") {
                                let paths = openFiles(allowed: ["xml"], filterPattern: "*rawprogram*", startDir: viewModel.firmwareDirectory)
                                viewModel.rawprogramPaths = paths
                            }
                            Spacer()
                            Text(viewModel.rawprogramPaths.joined(separator: ", ")).font(.caption).foregroundColor(.secondary)
                        }

                        HStack {
                            Button("选择 patch(es).xml") {
                                let paths = openFiles(allowed: ["xml"], filterPattern: "patch*", startDir: viewModel.firmwareDirectory)
                                viewModel.patchPaths = paths
                            }
                            Spacer()
                            Text(viewModel.patchPaths.joined(separator: ", ")).font(.caption).foregroundColor(.secondary)
                        }
                    } else {
                        HStack {
                            Button("选择 provision(s).xml") {
                                let paths = openFiles(allowed: ["xml"], filterPattern: "provision*", startDir: viewModel.firmwareDirectory)
                                viewModel.provisionPaths = paths
                            }
                            Spacer()
                            Text(viewModel.provisionPaths.joined(separator: ", ")).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                HStack {
                    Button(action: { viewModel.start() }) { Label("Start", systemImage: "play.fill") }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!viewModel.canStart)
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }

                if viewModel.isRunning {
                    VStack(alignment: .leading) {
                        Text(viewModel.progressTask).font(.subheadline)
                        ProgressView(value: viewModel.progressPercent) { Text(String(format: "%.1f%%", viewModel.progressPercent * 100)) }
                            .progressViewStyle(LinearProgressViewStyle())
                    }
                }

                if let res = viewModel.runResult {
                    HStack {
                        Image(systemName: res == 0 ? "checkmark.seal.fill" : "xmark.seal.fill").foregroundColor(res == 0 ? .green : .red)
                        Text("Run result: \(res)")
                    }
                }

                // Terminal log area
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Terminal").font(.headline)
                        Spacer()
                        Button("Clear") { viewModel.clearTerminal() }.buttonStyle(.bordered)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(viewModel.terminalLog, forType: .string)
                        }.buttonStyle(.bordered)
                    }

                    // use a scrollview with Text; show last lines and support auto-scroll
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(viewModel.terminalLines.enumerated()), id: \.0) { idx, line in
                                    Text(line).font(.system(.body, design: .monospaced)).foregroundColor(.primary).id(idx)
                                }
                            }
                            .padding(6)
                        }
                        .frame(minHeight: 120, maxHeight: 300)
                        .background(Color(.windowBackgroundColor))
                        .cornerRadius(6)
                        .onChange(of: viewModel.terminalLines.count) { _ in
                            // scroll to bottom when new lines appended
                            if let last = viewModel.terminalLines.indices.last {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    proxy.scrollTo(last, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .padding(.top)
    }
}

struct DownloadModeView_Previews: PreviewProvider {
    static var previews: some View {
        DownloadModeView(viewModel: DeviceViewModel())
    }
}
