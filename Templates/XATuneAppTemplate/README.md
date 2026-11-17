# XATune iOS 通用应用工程模板

Copyright © 2026 Kelejun。保留所有权利。

**本框架仅限获得书面授权的一名自然人本人使用，授权不得转让、出借或与他人共享。禁止以任何形式向第三方再次分享、转发、分发或提供本框架、其副本或基于本框架整理、修改形成的框架及模板。** 可下载、可查看或可编译不代表获得使用授权。具体条件见 [使用条款](USAGE_TERMS.md) 和 [版权声明](LICENSE)。

## 1. 框架定位

这是从 XATune iOS 应用中裁剪得到的独立 Xcode 应用工程，供获授权的个人作为其他 iOS 项目的起点。复制整个目录后即可独立编译，不需要原 XATune 仓库、校园账号、公告后端、Android 工程或第三方包。

它是应用源码模板，不是 `.framework`、`.xcframework`、Swift Package 或可直接导入已有项目的 SDK。当前工程保留导航、设置和少量本地工具；校园业务已经删除，不提供现成的校园服务。

来源为 `Kelejun/XATUHelper` 的提交 `85723f5` 所在版本；完整来源提交号及文件对应关系见 [导出说明](EXPORT_NOTES.md)。

## 2. 适用系统与开发环境

| 项目 | 要求或边界 |
| --- | --- |
| 运行系统 | iOS 17.0 及以上、iPadOS 17.0 及以上；保留原工程部署下限 |
| 设备 | iPhone、iPad；真机沿用 arm64 要求 |
| 开发主机 | 能运行相应 Xcode 的 Mac；不能直接在 Windows、Linux 上构建此应用 |
| Xcode 与 SDK | Xcode 26 或更新版本，包含 iOS 26 或更新 SDK；设置按钮沿用原有 `glassEffect`，编译时需要对应 SDK |
| Swift | Xcode 自带 Swift 编译器，工程语言模式为 Swift 5 |
| 模拟器 | 安装所选设备对应的 iOS Simulator runtime；无需开发团队或签名即可构建 |
| 真机 | 自己的 Bundle Identifier、Apple 开发签名配置及可用设备 |
| iOS 17～25 | 保留原有系统版本判断，设置按钮使用原有 Material 分支；不是将运行下限提高到 iOS 26 |
| Apple Watch | 不包含 Watch App、复杂功能或同步代码 |
| 其他系统 | 不提供 Android、原生 macOS、Mac Catalyst、tvOS、visionOS 工程或适配 |
| 联网与后端 | 当前模板启动不发起业务网络请求，不需要任何服务器 |

“部署下限”是工程配置，不代表已在全部历史系统和设备上逐一运行验证。实际完成的验证见 [验证记录](VALIDATION.md)。模板界面文案为简体中文，没有新增多语言支持。

## 3. 适用于什么情况

适合以下场景，均以取得书面授权并遵守单人使用限制为前提：

- 为 iPhone、iPad 建立一个以 SwiftUI 为主的原生应用起点。
- 复用 XATune 已有的窄屏导航、宽屏侧栏、设置弹窗和版本展示方式。
- 在同一获授权项目内使用简单 JSON 本地缓存、钥匙串密码存取、文本诊断文件分享工具。
- 阅读或维护裁剪后的应用结构，并自行开发已获许可范围内的业务。

不适合直接承担以下工作：

- 作为可即装即用的教务、校园、电费或统一身份认证系统。CAS、EAMS、支付及学校网页适配均已删除，替换域名不会恢复这些能力。
- 直接对接其他学校、企业门户或后端。这里没有通用认证协议层、接口适配层或多学校配置系统。
- 给已有 App 安装一个 SDK。若自行选取工具文件加入现有工程，仍须遵守本框架授权限制并处理类型重名及工程归属。
- 自动获得 Watch、Widget、后台任务、通知、定位或跨平台支持。这些能力不在导出范围内。
- 需要数据库、缓存迁移、并发事务、远程同步、完善错误报告或安全审计保证的产品。现有工具只有下述能力。

## 4. 当前包含的内容

| 部分 | 实际行为 |
| --- | --- |
| 应用入口 | 一个 `WindowGroup`，直接进入主界面，不经过登录 |
| 窄屏导航 | 首页、设置两个入口，使用原有 `TabView` 方式 |
| 宽屏导航 | 继承原有 iPad／regular size class 分支、侧栏折叠和底部设置入口；设置以 sheet 展示 |
| 首页 | 保留日期、按时间段变化的问候语和每分钟更新时间；无课程或业务卡片 |
| 设置 | 显示应用版本号和构建号；不显示原项目提交号、账号、备案号或外部链接 |
| 本地 JSON | `Codable` 文件读写、原子保存、清理，可选择 ISO 8601 日期策略 |
| 钥匙串 | 按账号保存、读取、删除密码；service 随当前 Bundle Identifier 隔离 |
| 诊断分享 | 调用方提供文本后生成临时 `.txt`，打开系统分享面板，关闭面板后清理临时文件 |

诊断分享只是保留的组件，没有放入首页或设置，也不会自动收集或导出日志。使用者应只向它提供获准导出的内容；它不自动去除隐私或凭据。组件的系统分享能力不构成分享本框架的许可。

## 5. 目录结构

```text
XATuneAppTemplate/
  AppTemplate.xcodeproj/
    project.pbxproj
    xcshareddata/xcschemes/AppTemplate.xcscheme
  AppTemplate/
    AppTemplateApp.swift
    Services/
      CampusGreeting.swift
      Keychain.swift
      LocalJSONFile.swift
    Views/
      MainTabView.swift
      HomeView.swift
      SettingsView.swift
      DiagnosticExportButton.swift
  Info.plist
  README.md
  EXPORT_NOTES.md
  VALIDATION.md
  USAGE_TERMS.md
  LICENSE
  .gitignore
```

项目只有一个 App target，没有依赖原工程的相对路径、构建脚本、App Group、扩展 target、包依赖或签名团队。所有 Swift 文件都在 `AppTemplate` 同步目录下，Xcode 按目录自动纳入编译。

`CampusPage`、`CampusSidebarToolbar`、`CampusGreeting` 等内部类型名沿用原源码；名称不表示还保留校园接口。

## 6. 第一次打开与运行

1. 在授权范围内，将整个 `XATuneAppTemplate` 目录复制到自己的工作位置。不要只复制 `.xcodeproj`。
2. 用 Xcode 打开 `AppTemplate.xcodeproj`，scheme 选择 `AppTemplate`。
3. 选择已安装 runtime 的 iPhone 或 iPad 模拟器，执行 Run。
4. 启动后首页显示日期和问候语。窄屏可切换设置，宽屏可使用侧栏底部设置按钮。设置中显示 `1.0.0（1）`。

仅构建模拟器应用，可在模板根目录运行：

```sh
xcodebuild -project AppTemplate.xcodeproj \
  -scheme AppTemplate \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/AppTemplate-DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

此命令只构建，不会自动安装或启动应用。

真机使用时，在 target 的 **Signing & Capabilities** 设置自己的 Team，替换 `com.example.apptemplate` 为自己可签名的唯一标识，再选择设备运行。模板不包含原作者的开发团队、证书、描述文件或共享容器能力。

## 7. 项目身份与后续修改位置

| 要修改的内容 | 位置与注意事项 |
| --- | --- |
| Bundle Identifier | target → Signing & Capabilities；Debug、Release 均需一致设置 |
| App 显示名称 | target 的 `INFOPLIST_KEY_CFBundleDisplayName`；当前为 `AppTemplate` |
| 版本与构建号 | 工程 Build Settings → `MARKETING_VERSION`、`CURRENT_PROJECT_VERSION` |
| 侧栏标题 | `MainTabView.swift` 中的 `navigationTitle("AppTemplate")` |
| 首页内容 | `HomeView.swift`；现有问候语由 `CampusGreeting.swift` 提供 |
| 页面与导航 | `MainTabView.swift` 的页面枚举、`page(_:)`、窄屏 `tabs` 和宽屏列表；按实际项目维护对应入口 |
| 设置内容 | `SettingsView.swift` 的 `SettingsContent`；同一内容供导航页与 sheet 复用 |
| 全局生命周期 | `AppTemplateApp.swift`；当前不注册后台任务、登录状态或设备桥接 |
| 应用图标 | 未附带 XATune 品牌图标；发布前自行准备已获授权的 AppIcon 并设置 `ASSETCATALOG_COMPILER_APPICON_NAME` |
| 权限及系统能力 | `Info.plist` 与 target 的能力配置；当前没有定位、后台刷新或 App Group 的业务声明 |

工程名称和内部文件名不影响 Bundle Identifier，不必为了运行而整体重命名。若后续自行重命名工程，需要同时维护 scheme 中的 target 名、产品名及工程引用；复制模板本身不需要此操作。

修改 Bundle Identifier 会改变钥匙串 service，新标识不会自动读取旧标识保存的密码。模板没有身份迁移逻辑。

## 8. 本地工具用法与限制

以下片段用于说明调用方式，不会在模板内自动执行，也没有为此添加示例页面。

### JSON 文件

```swift
struct SavedOptions: Codable {
    var title: String
}

let store = LocalJSONFile<SavedOptions>(name: "options.json")
store.save(SavedOptions(title: "个人项目"))
let saved = store.load()
store.clear()
```

数据位置为当前应用沙箱的 `Library/Application Support/<name>`。`save` 自动建立目录并原子写入；读写失败、损坏或解码失败会静默处理，`load()` 返回 `nil`，`save()` 不返回成功状态。它适合可替换的小型缓存，不适合以其作为关键数据保存成功的依据。

默认使用 `JSONEncoder`／`JSONDecoder` 的日期策略。如需 ISO 8601，在第一次读写前保持同一配置：

```swift
let store = LocalJSONFile<SavedOptions>(name: "options.json", usesISO8601: true)
```

由调用方维护文件名、模型版本、归属、清理和迁移。工具没有加密、多账号隔离、并发读写协调或自动备份逻辑。文件名应由应用自己确定，不直接接收未经处理的外部路径。

### 钥匙串

```swift
try Keychain.savePassword("password", account: "account-id")
let password = Keychain.loadPassword(account: "account-id")
Keychain.deletePassword(account: "account-id")
```

存储类型为系统钥匙串的 Generic Password；service 为 `<Bundle Identifier>.credential`，账号字符串作为 account。保留原有 `kSecAttrAccessibleAfterFirstUnlock` 可访问性设置，不启用 iCloud 钥匙串同步或跨 App 共享。

`savePassword` 失败时抛出系统状态错误；读取失败或不存在均返回 `nil`；删除不返回状态。调用方负责错误呈现、账号管理、退出清理和秘密生命周期。卸载重装不应视为可靠的钥匙串清理方式。模板不自动登录或保存任何账号密码。

### 诊断文件分享组件

在需要该能力的已授权页面中，可自行使用现有组件：

```swift
DiagnosticExportButton(filenamePrefix: "MyApp-diagnostics") {
    "由调用方生成的诊断文本"
}
```

组件通过 `UIActivityViewController` 分享纯文本文件，显示导出错误，并在分享面板关闭后清理此次临时目录。生成与文件写入在按钮动作中同步执行，适合较小文本。进程异常退出时不保证执行关闭回调或立即清理临时文件。

该工具没有自动采集、脱敏、压缩或上传服务。当前主界面没有实例化该按钮。

## 9. 网络、隐私与发布

模板删除了校园 HTTP 的 ATS 例外、公告地址、局域网说明、定位说明、后台任务标识和后台模式，不连接原学校或 XATune 的服务。当前没有统计 SDK 或第三方依赖，也不自动请求权限。

若后续在授权范围内自行增加联网、账号或设备能力，需要由该项目自行实现，并据实际行为填写权限、隐私说明和平台发布资料。原 XATune 的隐私政策、备案号、商店链接及品牌资源没有随模板复制，不应当作为另一个 App 的声明或身份信息使用。

模板没有 AppIcon 和发布签名。通过编译不表示可以直接提交商店；发布还受本框架的授权范围、素材权利及平台审核要求约束。运行系统要求不授予发行或商用权。

## 10. 常见问题

**能直接换学校域名使用吗？**

不能。模板没有学校接口、HTML 解析、认证流程或课表模型。适用于搭建应用基础结构，校园接入需要另行实现并取得相应授权。

**为什么没有登录、通知、课表或小组件？**

这些实现与原应用状态、学校业务或共享容器存在依赖，因此未包含在独立模板中。完整删除范围见导出说明。

**为什么旧 Xcode 编译不过？**

保留的设置按钮引用 iOS 26 SDK API，即使有运行时版本判断，编译器仍需认识该 API。使用包含 iOS 26 SDK 的 Xcode 26 或更新版本。没有为旧 Xcode 额外改写代码。

**模拟器提示缺少 runtime 或 destination 不可用？**

在 Xcode 的平台组件中安装相应 iOS Simulator runtime，并选择本机实际可用的设备。SDK 与可运行的模拟器系统是不同组件。

**为什么真机签名失败？**

检查自己的 Team、Bundle Identifier、设备可用性和签名配置。`CODE_SIGNING_ALLOWED=NO` 只用于无签名构建检查，不会生成可直接安装到真机的有效签名应用。

**能复制进已有工程吗？**

这不是插件式 SDK。若授权允许在该项目使用，可按依赖关系选取内部文件；已有工程只能保留一个 `@main` 入口，不能把整个应用入口再次加入同一 target。工具类型默认是 internal，不提供跨模块公共 API。

**可以把模板、修改版或压缩包发给别人吗？**

不可以。本框架仅限获得书面授权的一名自然人本人使用，禁止二次分享、转发、分发、转售、转授权或通过共享仓库提供给第三方。改名、删减、修改或重新打包不解除这些限制。详见 [使用条款](USAGE_TERMS.md)。
