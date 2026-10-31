# 迁移验证记录

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
