# XATU Helper · Skip Fuse

从 `../XatuHelper` 迁移的独立双平台工程。原来的 iOS 项目和 Widget 扩展保留。迁移后的 Swift 源码位于 `Sources/XatuAndroid`，Android 入口位于 `Android/`，新 iOS 入口位于 `Darwin/`。

> **当前状态（2026-10-31）：现有版本功能基本能用，但实机运行不到 10 FPS，性能问题严重，不建议日常使用。** 下一步计划使用 **Kotlin + Jetpack Compose** 重构 Android 版本；当前目录仍是 Skip Fuse 实现，重构尚未完成。

## 后续计划

使用 Kotlin + Jetpack Compose 重构 Android 版本，重点改善实机性能与交互体验。现有迁移代码、功能测试和性能记录作为重构参考；不将模拟器长帧改善等同于实机性能问题已解决。具体历史数据与局限见 [PERFORMANCE.md](PERFORMANCE.md)。

## 构建

需要 Xcode、Skip 1.9.20、Swift 6.4.2 Android SDK、Android SDK/NDK 和 Java/Gradle。

```sh
./xatu-android/scripts/build-android.sh
```

APK 生成在 `Android/app/build/outputs/apk/debug/`（Skip 可能重定向到 `.build/Android/app/outputs/apk/debug/`）。也可用 Android Studio 打开 `Android/`，或用 Xcode 打开 `Project.xcworkspace`。

## 已移植

- 课程表、考试、成绩、培养计划、电费查询及本地缓存，复用原 Swift 业务逻辑。
- Observation 状态管理和 Skip Fuse SwiftUI 页面。
- CAS AES-CBC/PKCS7：CryptoSwift；网页登录：SkipWeb，双向同步 WebView 与 URLSession cookie。
- 密码及会话使用 SkipKeychain；Android 使用 Keystore 支持的加密存储，关闭应用备份。
- Android 本地课程/考试提醒：AlarmManager、通知频道、Android 13+ 权限、重启恢复。
- Android 校历 OCR：ML Kit 中文模型，在设备本地识别。
- 旧教务系统 HTTP 仅对 `xatu.edu.cn` 及子域名放行。

## 平台差异与待验证事项

- Android 电费用量使用每日金额列表；Apple 平台继续使用 Charts。
- Android 桌面小组件使用原生 RemoteViews，显示课程及电费快照；iOS WidgetKit 扩展保留。
- Android 提醒使用无需特殊授权的非精确闹钟，省电模式可能延迟；需要在设备上验证厂商后台限制。
- 网页签到使用 Android WebView 定位权限，仅允许学校 HTTPS 域名；定位、跳转、验证码登录和校园网访问仍需使用学校账号在设备上实测。
- 原 iOS 代码与此工程目前是独立源码；后续业务修改需同步到此工程。

历史构建与验证：Android Swift 交叉编译、Gradle `assembleDebug`、APK 签名校验及 iOS Simulator 编译通过；1.1.0 已记录 17 项核心回归测试通过，Android 16 ARM64 模拟器安装和冷启动正常。各版本记录见 [VALIDATION.md](VALIDATION.md)，这些结果不代表实机性能合格。

交付安装包：`dist/XatuHelper-1.1.0-release.apk`（另有 `dist/XatuHelper.apk`），ARM64，Android 9+，版本 1.1.0。Release 优化包约 170 MiB，沿用本地调试签名，供覆盖试用；学校业务功能仍需实际设备验收。

## 验证

`swift test --package-path xatu-android/Verification` 在 macOS 上运行核心回归测试。测试通过符号链接直接引用迁移源码，覆盖 OpenSSL AES 对照、课表周次与连排、线上课程过滤。

## 1.0.1 修复

修复“需要验证码？用网页登录”在学校认证页面跳转时崩溃。原 SkipWeb 0.12.0 直接遍历 Android WebView 的空请求头映射，触发 `NullPointerException`；现固定到官方修复提交 `4ae9b16f5835d37ab63dc4cb4064df4fef3574a4`，将缺失请求头按空集合处理。

修复版安装包：`dist/XatuHelper-1.0.1-debug.apk`；通用文件名 `dist/XatuHelper-debug.apk` 同步更新。

## 1.0.2 登录会话修复

- 网页会话按 `/authserver`、`/eams` 等实际路径同步，优先使用 Android CookieManagerCompat 保留 Domain、Path、HttpOnly、Secure 等属性，并替换旧版保存的错误作用域 Cookie。
- URLSession 请求及每次 302 跳转显式匹配 Cookie 的域名、路径和 Secure 属性，避免 Android FoundationNetworking 的路径匹配差异。
- 直接登录按学校 `checkNeedCaptcha.htl` 的账号判断处理图片/滑块验证；无法确认登录失败原因时不再默认报告账号密码错误。
- 网页登录仅在接口验证成功后关闭；会话同步失败可保留网页重试。
- 修复后台通知清理等原生线程调用 JNI 时缺少上下文的问题。

修复包：`dist/XatuHelper-1.0.2-debug.apk`，版本 1.0.2 (3)。测试不使用真实账号密码；学校账号完整认证仍需实际验收。

## 1.0.3 课程表、图标与校历修复

- 课程表的闭区间 `ForEach` 改用数组，避免 Skip Fuse 将 `ClosedRange.Index` 强制转换成 `Int` 时崩溃。
- 图标统一经过 `AppIcon`：使用 Skip 支持的 Material 映射，学校、校园网、电费等图标使用随包 SVG；工具栏图标为 22 dp，区域为 44 dp。
- 校历优先读取原始清晰图片，修正标题大小写、导航链接过滤及 OCR 日期的空白、横线和跨年处理；Android OCR 的区域参数显式转换为 Double。
- 已在 Android 16 ARM64 模拟器检查课程表、校园图标和校历完整显示。校历显示第一学期 2026-08-31 至 2027-01-15、第二学期 2027-03-01 至 2027-07-16。

安装包：`dist/XatuHelper-1.0.3-debug.apk`（版本 1.0.3 / build 4）；`dist/XatuHelper-debug.apk` 同步更新。使用原调试签名，可覆盖安装并保留数据。

## 1.1.0 Material Design 3 与性能调整

Android 自有界面统一为 MD3：动态浅/深色、标准字号、色调卡片、平面列表、原生操作控件和 48 dp 工具栏点击区域；首页、校园服务和登录页重新布局。课表增加数据索引、临近周构建、网格内容复用及合并绘制，移除首页长入场动画。

本地测试包为 `dist/XatuHelper-1.1.0-release.apk`（或 `dist/XatuHelper.apk`），约 170 MiB，Swift Release + R8 优化，保留原签名，可直接覆盖并保留数据。由于实机运行不到 10 FPS，当前包仅供开发验证，不建议日常使用；APK 不随源码入库。

验证：17 项核心测试通过；6 项设备功能测试通过，1 项网页登录界面测试为保留会话而跳过。最终相同模拟器连续翻周 P95 帧耗时由 71.57 ms 降至 33.56 ms，系统卡顿帧比例由 15.80% 降至 5.11%；中位帧耗时未改善，不保证真机固定帧率。详见 `DESIGN.md` 与 `PERFORMANCE.md`。
