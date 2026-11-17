# 验证记录

日期：2026-11-17。

## 已完成

- 开发环境：Xcode 27.2（27B52），iOS Simulator SDK 27.2。
- 模板的 Debug／通用 iOS Simulator 目标无签名构建通过；构建日志结果为 `BUILD SUCCEEDED`。
- 使用单独 DerivedData 目录，构建未依赖原 App 的产物。
- `Info.plist` 与工程文件通过 plist 格式检查。

Debug 构建过程中出现一条 App Intents 元数据提示：工程没有依赖 `AppIntents.framework`，因此跳过该元数据提取。模板没有 App Intent，此提示不影响构建结果。

## 尚未覆盖

- Release 构建、签名、归档与商店提交。
- 真机安装与运行。
- iOS／iPadOS 17 至 26 的逐版本运行检查。
- iPad 导航、分屏、横竖屏和完整交互回归。
- 钥匙串、JSON 工具及诊断分享在所有设备上的运行验证。

此前通过的构建针对模板源码。交付包内的后续整理涉及文档、空行和恢复原有 arm64 设备声明，未再执行完整构建。工程下限和 API 的版本分支见 README，不应将编译通过视为所有设备及系统上的兼容性保证。
