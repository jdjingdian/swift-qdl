//
//  ContentView.swift
//  Created by 经典 on 2025/12/24.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @StateObject private var vm = DeviceViewModel()
    @State private var version: String = ""

    var body: some View {
        NavigationSplitView {
            // Sidebar: device list with refresh
            VStack {
                HStack {
                    Text("devices_title")
                        .font(.headline)
                    Spacer()
                    Button(action: { vm.queryDevices() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(Text("devices_refresh"))
                }
                .padding([.horizontal, .top])

                if vm.isQuerying {
                    ProgressView("devices_querying")
                        .padding()
                } else if vm.devices.isEmpty {
                    VStack { Spacer(); Text("devices_none").foregroundColor(.secondary); Spacer() }
                } else {
                    List {
                        ForEach(vm.devices) { d in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(d.product).font(.subheadline)
                                    Text(d.serial).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if vm.selected?.id == d.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
                                }
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                vm.selected = d
                            }
                        }
                    }
                    // removed automatic firmware selection on device change; user picks directory manually
                    .listStyle(SidebarListStyle())
                }

                Spacer()
                Text(String(format: "%@ %@", NSLocalizedString("qdl_version", comment: "QDL version label"), version))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding()
            }
        } detail: {
            // Detail: selected device and controls
            VStack(alignment: .leading, spacing: 16) {
                if let sel = vm.selected {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(sel.product).font(.title2.bold())
                            Text(sel.serial).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    }

                    DownloadModeView(viewModel: vm)
                } else {
                    VStack(alignment: .center) {
                        Spacer()
                        Text("no_device_selected").font(.title3).foregroundColor(.secondary)
                        Button("refresh_devices") { vm.queryDevices() }
                            .buttonStyle(.bordered)
                        Spacer()
                    }
                }
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { vm.queryDevices() }) { Image(systemName: "arrow.clockwise") }
                }
                ToolbarItem(placement: .status) {
                    if vm.isRunning { ProgressView().scaleEffect(0.8) }
                }
            }
            .onAppear {
                version = String(cString: qdl_version())
            }
            // Note: port picker sheet removed; choose device from sidebar
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
