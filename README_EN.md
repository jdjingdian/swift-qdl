# SwiftUI for QDL (Qualcomm Download Loader)

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)

This is a macOS Qualcomm 9008 mode flashing tool built with SwiftUI.

Chinese version: see `README.txt`.

## Build from source

### Install build toolchain

On macOS, install the required tools via Homebrew:

```bash
brew install cmake autoconf automake libtool pkg-config
```

### Update submodules

Make sure all git submodules are pulled:

```bash
git submodule update --init --recursive
```

### Build third-party libraries

Run the helper script to build the dependencies:

```bash
chmod +x ./scripts/build_submodules.sh
./scripts/build_submodules.sh
```

After the script finishes, you should see the `third_party` and `third_party_build` directories, containing the built `.dylib` libraries for `libusb`, `libxml2`, and `libqdl`.

### Build and run the app

Open `swift-qdl.xcodeproj` in Xcode, select the `swift-qdl` target, then build and run the project.

## Acknowledgements

This project uses and gratefully acknowledges the following open source projects:
- [qdl (linux-msm/qdl)](https://github.com/linux-msm/qdl)
- [libusb (libusb/libusb)](https://github.com/libusb/libusb)
- [libxml2 (GNOME/libxml2)](https://github.com/GNOME/libxml2)