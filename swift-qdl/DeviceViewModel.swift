import Foundation
import Combine

// Swift-side C callback signature
typealias QDLProgressCb = @convention(c) (UnsafePointer<CChar>?, UInt32, UInt32, UnsafeMutableRawPointer?) -> Void

final class DeviceViewModel: ObservableObject {
    @Published var devices: [DeviceInfo] = []
    @Published var isQuerying: Bool = false
    @Published var selected: DeviceInfo? = nil
    
    enum Mode {
        case download
        case provision
    }

    @Published var mode: Mode = .download

    // file selections
    @Published var programmerPath: String? = nil
    @Published var rawprogramPaths: [String] = []
    @Published var patchPaths: [String] = []
    @Published var provisionPaths: [String] = []

    // runtime state
    @Published var isRunning: Bool = false
    @Published var runResult: Int? = nil

    var canStart: Bool {
        switch mode {
        case .download:
            guard programmerPath != nil else { return false }
            return !rawprogramPaths.isEmpty
        case .provision:
            // programmer can be optional if previously selected
            return !provisionPaths.isEmpty || programmerPath != nil
        }
    }

    func start() {
    // register progress callback before starting long running work
    registerProgressCallback()
    isRunning = true
    runResult = nil

        DispatchQueue.global().async {
            // prepare arguments
            // todo: dynamic storage type
            let storageType = qdl_storage_type_t(QDL_STORAGE_UFS.rawValue)
            let prog = self.programmerPath
            var xmlPaths: [String] = []
            switch self.mode {
            case .download:
                xmlPaths = self.rawprogramPaths + self.patchPaths
            case .provision:
                xmlPaths = self.provisionPaths
            }

            // prepare C strings
            var cProg: UnsafeMutablePointer<CChar>? = nil
            if let p = prog { cProg = strdup(p) }

            // If app is sandboxed, files chosen via NSOpenPanel require
            // startAccessingSecurityScopedResource() before we open them.
            var startedURLs: [URL] = []
            if let p = prog {
                let u = URL(fileURLWithPath: p)
                if u.startAccessingSecurityScopedResource() {
                    startedURLs.append(u)
                }
            }

            var cSerial: UnsafeMutablePointer<CChar>? = nil
            if let s = self.selected?.serial, !s.isEmpty { cSerial = strdup(s) }

            var cStrings: [UnsafeMutablePointer<CChar>?] = xmlPaths.map { strdup($0) }

            // convert to UnsafePointer array for qdl_run
            var cPtrs: [UnsafePointer<CChar>?] = cStrings.map { UnsafePointer($0) }

            // determine include_dir: directory of first xmlPath if any
            var includeDirC: UnsafeMutablePointer<CChar>? = nil
            if let first = xmlPaths.first {
                let url = URL(fileURLWithPath: first)
                let dir = url.deletingLastPathComponent().path
                includeDirC = strdup(dir)
            }

            // start security-scoped access for xml files if needed
            for path in xmlPaths {
                let u = URL(fileURLWithPath: path)
                if u.startAccessingSecurityScopedResource() {
                    startedURLs.append(u)
                }
            }

            // qdl_run expects an UnsafeMutablePointer<UnsafePointer<CChar>?>? for the file list
            // Use defer to ensure cleanup of allocated C strings and unregistering callback
            var ret: Int32 = -1
            defer {
                // free allocated C strings
                if let p = cProg { free(p) }
                if let s = cSerial { free(s) }
                if let d = includeDirC { free(d) }
                for p in cStrings { if let pp = p { free(pp) } }
                // stop security-scoped access
                for u in startedURLs { u.stopAccessingSecurityScopedResource() }

                // update UI on main thread and unregister progress callback
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.runResult = Int(ret)
                    self.unregisterProgressCallback()
                }
            }

            ret = cPtrs.withUnsafeMutableBufferPointer { buf in
                let count = Int32(buf.count)
                // call qdl_run; convert cSerial to UnsafePointer if present
                return qdl_run(self.mode == .download ? QDL_MODE_FLASH : QDL_MODE_PROVISION,
                               cSerial != nil ? UnsafePointer(cSerial) : nil,
                               storageType,
                               cProg,
                               buf.baseAddress,
                               count,
                               false,
                               includeDirC,
                               0)
            }
        }
    }

    // MARK: - Progress integration
    @Published var progressTask: String = ""
    @Published var progressValue: UInt32 = 0
    @Published var progressTotal: UInt32 = 0
    @Published var progressPercent: Double = 0.0

    // keep a storage for the C function pointer so it won't be deallocated
    private var cbPointerStorage: qdl_progress_cb_t? = nil

    private static let progressClosure: QDLProgressCb = { taskPtr, value, total, userdata in
        let task = taskPtr != nil ? String(cString: taskPtr!) : ""
        if let userdata = userdata {
            let vm = Unmanaged<DeviceViewModel>.fromOpaque(userdata).takeUnretainedValue()
            DispatchQueue.main.async {
                vm.progressTask = task
                vm.progressValue = value
                vm.progressTotal = total
                // normalize to 0..1 for SwiftUI ProgressView
                vm.progressPercent = total == 0 ? 0.0 : Double(value) / Double(total)
            }
        } else {
            // fallback: just print
            DispatchQueue.main.async {
                print("Swift CB: task=\(task) value=\(value) total=\(total)")
            }
        }
    }

    func registerProgressCallback() {
        // create C function pointer and register with userdata pointing to self
        let cb = DeviceViewModel.progressClosure
        let fn = unsafeBitCast(cb, to: qdl_progress_cb_t.self)
        cbPointerStorage = fn
        let userdata = Unmanaged.passUnretained(self).toOpaque()
        qdl_set_progress_callback(fn, userdata)
    }

    func unregisterProgressCallback() {
        qdl_set_progress_callback(nil, nil)
        cbPointerStorage = nil
    }

    func queryDevices() {
        isQuerying = true
        DispatchQueue.global().async {
            var devArr = [qdl_device_info_t](repeating: qdl_device_info_t(serial: (CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0),
                                                                                   CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0),
                                                                                   CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0),
                                                                                   CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0),
                                                                                   CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0),
                                                                                   CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0),
                                                                                   CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0),
                                                                                   CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0)),
                                                       product: (CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0),
                                                                 CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0),
                                                                 CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0),
                                                                 CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0),
                                                                 CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0),
                                                                 CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0),
                                                                 CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0),
                                                                 CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0), CChar(0))),
                                          count: 16)
            let count = qdl_list_devices(&devArr, 16)
            var result: [DeviceInfo] = []
            for i in 0..<Int(count) {
                let serial = withUnsafePointer(to: devArr[i].serial) {
                    $0.withMemoryRebound(to: CChar.self, capacity: 64) { String(cString: $0) }
                }
                let product = withUnsafePointer(to: devArr[i].product) {
                    $0.withMemoryRebound(to: CChar.self, capacity: 64) { String(cString: $0) }
                }
                result.append(DeviceInfo(serial: serial, product: product))
            }
            DispatchQueue.main.async {
                self.devices = result
                self.isQuerying = false
            }
        }
    }
}
