# 导出来源与裁剪说明

## 来源

- 原工程：XATune iOS（`Kelejun/XATUHelper`）。
- 基准提交：`85723f5d2847a43834cef9a89b5bdbfbdb2c8560`。
- 导出日期：2026-11-17。
- 交付形式：一个独立 Xcode App 工程、中文使用说明、版权与使用条款。

导出以已提交的基准源码为依据，不复制原工作目录内未提交的工程配置变动、自动生成的 BuildInfo 或 Xcode Cloud 配置。原 App 源码未被替换或删除。

## 保留文件与对应关系

| 导出文件 | 原文件 | 处理 |
| --- | --- | --- |
| `AppTemplate/AppTemplateApp.swift` | `XatuHelper/XatuHelperApp.swift` | 保留 SwiftUI App／WindowGroup 入口，直接进入主界面；移除登录、公告、后台任务、设备桥接及业务 sheet |
| `AppTemplate/Views/MainTabView.swift` | `XatuHelper/Views/MainTabView.swift` | 保留 TabView、宽屏侧栏、折叠控制、设置按钮和 sheet；删除业务路由与刷新，只保留首页、设置入口 |
| `AppTemplate/Views/HomeView.swift` | `XatuHelper/Views/HomeView.swift` | 仅保留日期、问候语、计时更新和基本页面容器；删除课程、电费、考试、假期卡片及业务状态依赖 |
| `AppTemplate/Views/SettingsView.swift` | `XatuHelper/Views/SettingsView.swift` | 保留设置表单、sheet 和版本读取；版本展示使用构建号，移除构建脚本依赖及业务设置 |
| `AppTemplate/Services/CampusGreeting.swift` | `Shared/CampusGreeting.swift` | 时间段与文案不变，移入当前 target；删除不再适用的 Watch 共享注释 |
| `AppTemplate/Services/LocalJSONFile.swift` | `XatuHelper/Services/LocalJSONFile.swift` | 原样保留 |
| `AppTemplate/Services/Keychain.swift` | `XatuHelper/Services/Keychain.swift` | 保留密码存取实现；删除同文件中的校园 Preferences，service 改用当前 Bundle Identifier |
| `AppTemplate/Views/DiagnosticExportButton.swift` | `XatuHelper/Views/DiagnosticExportButton.swift` | 保留原实现；默认文件名前缀由 XATune 改为 App；未增加页面入口 |
| `Info.plist` | 根目录 `Info.plist` | 保留基本 App 信息、单窗口、横竖屏及设备声明；移除学校服务、定位与后台相关键 |
| `AppTemplate.xcodeproj` | `XatuHelper.xcodeproj` | 裁剪为单 App target，删除扩展、依赖和写入源码的 Build Info 脚本；使用中性名称和占位 Bundle Identifier |
| `LICENSE` | 根目录 `LICENSE` | 原样保留，另附严格的 `USAGE_TERMS.md` |
| `.gitignore` | 根目录 `.gitignore` | 原样保留 |

工程 Debug／Release 仍使用 iOS 17.0 部署下限、Swift 5 语言模式和 iPhone／iPad 设备族。版本号初始化为 `1.0.0`、构建号初始化为 `1`，移除原开发团队、App Group 及 AppIcon 引用，并显式关闭 Mac／XR 兼容分发开关；没有为这些平台编写适配。

## 未包含的原工程部分

以下“删除”均指不纳入导出模板，原 XATune 文件保持原状。

- `AppState`、学校账号、登录页、演示账号、CAS 认证、凭据自动登录、Cookie 业务管理。
- EAMS 请求和 HTML 解析、课程与课表、考试、成绩、学业计划、相关模型、缓存策略和历史记录。
- 宿舍、电费余额与历史曲线、校园支付和校园网充值。
- 学校校历、OCR、签到、定位桥接与脚本、请销假、校园门户和学校专用 WebView。
- 公告服务、公告历史、图片与 Markdown 处理、公告弹窗和公告设置。
- 应用内业务横幅、课程／考试提醒、本地通知、后台电费刷新、退出提醒、App Intent。
- App Group、Widget 快照、iOS Widget、Watch App、Watch Widget 与 WatchConnectivity 桥接。
- 原学校 HTTP 例外、后台标识、定位和局域网用途说明。
- XATune 标志、商店与交流群链接、备案号、原隐私政策、发布签名、构建产物。
- 原业务回归样例和脚本：这些检查依赖已移除的校园模型与服务，不适用于模板。

## 独立性与同步边界

导出目录不引用目录外的源码、资源、配置、服务或 Git 元数据。移动整个目录、解压交付包后仍可编译。没有构建时写回源码的脚本。

这次交付只增加独立模板，不改变原 iOS App 的运行行为，也没有需要 Android 同步的业务变更。工作区外层的 `feature.md` 与 `feature-complete.md` 不属于模板，未复制、提交或打包。

模板的保留项、调用限制和运行要求见 [README.md](README.md)，构建与运行验证见 [VALIDATION.md](VALIDATION.md)。所有使用同时受 [USAGE_TERMS.md](USAGE_TERMS.md) 和 [LICENSE](LICENSE) 约束。
