![XATune](docs/assets/readme-header.png)

# XATune for iOS

仙宫小助手 iOS 版，从教务官网自动拉取课程表、考试安排、成绩及学分等信息，同时提供宿舍电费查询、签到与请销假等功能。使用 Swift、SwiftUI 和 WidgetKit，支持 iPhone、iPad、Apple Watch 与桌面小组件。

> Android 用户请前往 [XATUHelper-Android](https://github.com/Kelejun/XATUHelper-Android)

<a href="https://apps.apple.com/us/app/xatune/id6831484863"><img src="https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83" alt="Download on the App Store" height="40"></a>
<a href="https://testflight.apple.com/join/PbKpCUU6"><img src="docs/assets/testflight-badge.svg" alt="Download on TestFlight" height="40"></a>

App Store 下载不适用于中国大陆区，中国大陆区请使用 TestFlight 下载。

[隐私政策](PRIVACY.md)

## 编译

需要 macOS、Xcode 16 或更新版本，最低支持 iOS 17。

用 Xcode 打开 [XatuHelper.xcodeproj](XatuHelper.xcodeproj)，选择 `XatuHelper` scheme 运行。真机编译前需配置自己的开发团队、Bundle Identifier，以及 App 与 Widget 共用的 App Group；修改 App Group 时需同步更新 entitlements 和 [WidgetSnapshot.swift](XatuHelper/Services/WidgetSnapshot.swift) 中的标识。

```sh
xcodebuild -project XatuHelper.xcodeproj \
  -scheme XatuHelper \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Apple Watch 的编译、签名与同步说明见 [WATCH.md](WATCH.md)。

## 项目结构

```text
XatuHelper/
  AppState.swift        登录、业务状态与缓存协调
  Models/               课程、考试、成绩、学业与电费模型
  Services/             认证、教务、存储、通知与 Widget 桥接
  Views/                SwiftUI 页面、课表与校园 WebView
XatuHelperWidget/       iOS 课程、电费与假期小组件
Shared/                 Watch 同步模型与共享存储
XatuHelperWatch/        Watch App
XatuHelperWatchWidget/  Watch 表盘复杂功能与智能叠放
XatuHelper.xcodeproj/   Xcode 工程与共享 scheme
Config/                Widget 配置
Info.plist             App 配置与权限声明
```

密码存入系统钥匙串，业务数据缓存在本机，App 与 Widget 通过 App Group 共享快照；Apple Watch 接收 iPhone 同步的数据。

部分校园接口使用 HTTP，工程通过 ATS 例外兼容，其余连接使用 HTTPS。

## 许可

**保留所有权利（All Rights Reserved）**，详见 [LICENSE](LICENSE)。

本声明涵盖本仓库中的源代码、文档、界面设计、图标及其他资源，另有明确声明的内容除外。未经事先书面许可，不得使用、复制、修改、合并、发布、分发、再许可、销售或制作衍生作品，也不得用于商业用途；法律另有规定的除外。仓库公开可见不代表授予上述权利。如需授权，请联系仓库所有者。

第三方依赖及内容仍遵循各自的许可条款。

本项目由 DeepSeek 辅助开发。
