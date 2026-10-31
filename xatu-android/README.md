# XATU Helper · Skip Fuse

从 `../XatuHelper` 迁移的独立双平台工程。原来的 iOS 项目和 Widget 扩展保留。迁移后的 Swift 源码位于 `Sources/XatuAndroid`，Android 入口位于 `Android/`，新 iOS 入口位于 `Darwin/`。

> **状态：迁移早期版本，不可用。** 目前只验证到「能编译、能装、能启动」，没有用真实学校账号在校园网下跑通过任何业务流程，APK 是未优化的调试包（约 280 MB）。日常使用请看原 iOS 工程，不要把这个版本装到主力机上。

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

当前构建：Android Swift 交叉编译通过、Gradle `assembleDebug` 通过、APK 签名校验通过、iOS Simulator 编译通过；三项核心回归测试通过；已在 Android 16 ARM64 模拟器完成安装和冷启动，未发现启动崩溃。

交付安装包：`dist/XatuHelper-debug.apk`，ARM64，Android 9+，版本 1.0.2。调试包约 271 MB，使用调试签名，不用于商店发布。学校账号和校园网络下的功能仍需设备端验收。

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
