# Mousecape 光标核心许可 / 署名说明

本目录中的 Objective-C 光标核心代码来自 [alexzielenski/Mousecape](https://github.com/alexzielenski/Mousecape)，
版权归 Alex Zielenski 所有，遵循本目录 `LICENSE` 中所列的 BSD 风格条款（含「仅限个人非商业用途」限制）。

XSpace 集成时做了以下最小适配，不改变原功能逻辑：

1. 为原本缺少 include guard 的 `CGSInternal/*.h` 添加头文件保护宏；
2. 为头文件补充 `AppKit` 引用，以便与 Swift 一起编译；
3. 将私有头引用路径统一为 `CGSInternal/...`；
4. 新增 `MousecapeBridge.h/.m`，向 Swift 设置页提供精简接口。

XSpace 的「全局设置 → 光标」页面、Windows `.ani/.cur` 转换器均为本项目自行实现。
功能形态参考了 [sdmj76/Mousecape-swiftUI](https://github.com/sdmj76/Mousecape-swiftUI) 1.2.0；
由于该仓库的许可明确禁止再分发（包括编译后的二进制），XSpace 未复制其 SwiftUI 源码、
资源或编译产物，仅使用上游可再分发的核心代码并自行实现界面与转换逻辑。
