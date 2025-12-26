# SwiftUI for QDL (Qualcomm Download Loader)

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)

这是一个基于 SwiftUI 开发的 macOS 平台 Qualcomm 9008 模式刷机工具。

English version: see `README_EN.txt`.

## 本地编译

### 安装编译工具链

```
brew install cmake autoconf automake libtool pkg-config
```

### 更新子模块（submodules）

```
git submodule update --init --recursive
```

### 编译依赖库

```
chmod +x /scripts/build_submodules.sh && ./scripts/build_submodules.sh
```

脚本执行完成后，将会生成 `third_party` 和 `third_party_build` 目录，并在其中生成 `libusb`、`libxml2` 和 `libqdl` 等相关的 `.dylib` 动态库文件。

### 打包与运行

使用 Xcode 打开项目根目录下的 `swift-qdl.xcodeproj`，选择目标后进行编译并运行。

## 致谢

本项目使用并感谢以下开源项目：

- [qdl (linux-msm/qdl)](https://github.com/linux-msm/qdl)
- [libusb (libusb/libusb)](https://github.com/libusb/libusb)
- [libxml2 (GNOME/libxml2)](https://github.com/GNOME/libxml2)