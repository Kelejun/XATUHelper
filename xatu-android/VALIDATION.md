# 迁移验证记录

## 当前状态（2026-10-31）

现有 Android 版本功能基本能用，但用户反馈实机运行不到 10 FPS，性能问题仍未解决。计划使用 Kotlin + Jetpack Compose 重构，当前仓库保留 Skip Fuse 实现。以下为各版本历史验证记录；测试通过及模拟器优化结果不代表实机体验合格，也不表示所有业务场景均已验收。

## 独立工作区同步复核（2026-10-31）

使用完整 Xcode 工具链执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path xatu-android/Verification`：17 项核心测试通过，0 失败。默认 Command Line Tools 工具链无法解析 XCTest，切换工具链后通过；本轮未重新构建 Android APK，也未重跑设备测试或测量真机帧率。

## 初始迁移验证

2026-10-31，Skip 1.9.20，Swift Android SDK 6.4.2。

- `skip verify --project xatu-android --no-fastlane`：通过。
- `skip android build --package-path xatu-android`：ARM64 Android 原生 Swift 编译通过。
- `./xatu-android/scripts/build-android.sh`：Gradle `assembleDebug` 通过。
- `apksigner verify dist/XatuHelper-debug.apk`：通过。
- `xcodebuild`：迁移工程的 arm64 iOS Simulator 构建通过。
- `swift test --package-path xatu-android/Verification`：3 项测试通过，0 失败。

安装包：`dist/XatuHelper-debug.apk`；应用 ID `com.cell.xatuapp`；版本 1.0.0 (1)；最低 Android API 28，目标 API 36；ARM64；调试签名。

核心回归覆盖：AES-CBC/PKCS7 与 OpenSSL 对照、课表周次掩码与连排合并、线上课程过滤。

尚未使用学校账号验证：CAS API/验证码登录、课程/成绩/考试/电费接口、网页签到定位、通知到达及重启恢复、小组件数据呈现。需要校园网络的功能需在相应网络下验证。

APK ABI 已核验为 `arm64-v8a`，调试包约 256 MB。

## 模拟器启动验证

Android 16 / API 36，ARM64，AVD `XatuHelper_API36`：APK 安装成功；`am start -W` 返回 `Status: ok`，冷启动耗时约 1.06 秒；应用进程保持存活，前台 Activity 为 `xatu.android.MainActivity`，崩溃日志为空。未输入学校账号或密码。

## 1.0.1 网页登录崩溃修复

原因：SkipWeb 0.12.0 的 `androidRequestHeaders` 遍历了 WebView 返回的 null 请求头，认证页面导航时发生 `NullPointerException`。已固定至官方修复提交 `4ae9b16f5835d37ab63dc4cb4064df4fef3574a4`。

修复前在旧版运行回归：正常请求头通过，空请求头稳定复现同一空指针异常。

修复后在 Android 16 / ARM64 设备运行 3 项 instrumentation 测试，全部通过（13.602 秒）：

- 打开实际网页登录、等待异步跳转、取消并返回登录页。
- null 请求头按空集合处理，无崩溃。
- 正常请求头完整保留。

Gradle 调试包和测试包构建通过；修复包签名通过；包版本 1.0.1 (2)，ABI 为 arm64-v8a。未输入学校账号密码，未验证提交凭据后的学校业务流程。

修复版：`dist/XatuHelper-1.0.1-debug.apk`；`dist/XatuHelper-debug.apk` 同步更新。

设备连接后可运行：`./xatu-android/scripts/build-android.sh :app:connectedDebugAndroidTest`。

## 2026-10-31：1.0.3 界面与校历修复

- 崩溃证据：Android 原生堆栈显示 `ClosedRange<Int>.Index` 到 `Int` 的强制转换失败，调用来自 `SkipSwiftUI.ForEach.Java_view`。所有课表区间遍历已转换成数组。
- macOS 核心测试：15 项通过，覆盖原有 AES、课表、登录/Cookie，以及新增校历链接、原图优先级、标题和日期解析。
- 设备手工检查：Android 16 / ARM64 上课程表正常显示；校园入口的图标、设置、菜单、刷新均正常；校历完成网络下载、原生中文 OCR、日期解析及界面展示，两学期与公开原图一致。沿用现有会话，未输入或导出用户凭据。
- 构建：Gradle `assembleDebug` 与 `assembleDebugAndroidTest` 通过；`apksigner verify` 通过；安装包 `com.cell.xatuapp`，版本 1.0.3 (4)，minSdk 28。
- OCR 测试素材来自学校公开 2026–2027 校历，仅进入测试 APK；生产 APK 不含该测试图片。
- 最终设备回归：5 项通过、0 失败；网页登录界面测试因模拟器已有登录会话而跳过，未退出用户账号。通过项包括课程表打开后存活、公开校历离线 OCR、两项 WebView 请求头及 HttpOnly Cookie 导出。

## 2026-10-31：1.1.0 MD3 与渲染优化

- MD3 范围：登录、首页、校园服务、课表与课程详情、成绩、考试、学业进度、电费、宿舍选择、历史记录、校历、设置、通知及自有网页容器。统一动态语义色、字号、边距、色调卡片、列表和原生控件；学校网页正文保持学校提供的内容。
- 核心回归：17 项通过、0 失败，包括索引结果与原始课表筛选/连排的逐周等价性，以及空课表替换。
- 最终 Debug 设备回归：6 项通过、0 失败；1 项网页登录界面测试因已有登录会话跳过。通过项为课表存活、公开校历中文 OCR、浅/深色主要语义色对比度、两项 WebView 请求头与 HttpOnly Cookie 导出。
- 设备视觉检查：首页、校园服务、课表和设置页已在 Android 16 ARM64 模拟器检查；未退出或清除用户账号。
- Release：Swift 优化编译、R8 与资源缩减启用，非 debuggable，profileable；约 170 MiB；签名校验通过，版本 1.1.0 (5)，minSdk 28，arm64-v8a，可覆盖旧调试签名安装。
- 性能采用独立进程的系统 HWUI `framestats`，避免 Android 测试库与 R8 重命名后的应用类冲突。真实 Release APK 不加入测试运行器或测试代码。
- 同一模拟器、相同课表、2 秒预热后 8 组左右翻周，旧版 1.0.3 Debug 与新版 1.1.0 Release 的采样结果见 `PERFORMANCE.md`。最终 P95 从 71.57 ms 降至 33.56 ms，系统卡顿帧比例从 15.80% 降至 5.11%；这是长帧改善，不能解释为稳定 60 FPS。
- 最终交付二进制复测：独立系统帧测试通过（14.315 秒），587 个有效帧；Release 签名与非 debuggable 属性复核通过，11 个 SVG 图标资源完整；最终包已覆盖安装到模拟器，账号数据保留。
