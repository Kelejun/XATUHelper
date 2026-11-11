# Apple Watch 支持

## 页面与交互

- 横向：课程首页 → 考试 → 电费 → 假期倒计时，保留课程栏目的纵向位置。
- 课程栏目采用原生 `verticalPage`：首页向上轻扫／转动数码表冠依次进入今日课表、明日课表。课表内部可继续滚动；点课程进入详情。
- 各页标题置于各自页面内容中，上下／左右翻页时随页面移动，避免动态增删导航栏导致高度跳动。
- 首页课程名为最大字号，附教室和起止时间。上课中显示当前课，课间显示下一节，今日结束后寻找下一次课程并标明日期。
- 首页底部只展示一条补充信息：未来七个自然日内的最近考试（含今日尚未结束的考试）替换下一节摘要；没有近期考试时显示下一节。不在课程上方额外展示考试。
- 考试页包含日期、时间、考场、座位和备注。结束时间无法解析时保留到当天结束。
- 电费展示手机最近查询的余额、宿舍和查询时间，不发起独立查询。
- 假期依据手机校历的学期起止日期，提供放假及开学倒计时；没有可靠日期时显示空状态。
- 课程、电费、假期各有 WidgetKit 复杂功能，支持圆形、矩形及行内位置；矩形也用于智能叠放。课程优先教室和课程名，有空间再展示开始／下课时间。

## 数据与同步

`Shared/WatchSnapshot.swift` 为有版本号的跨端模型和离线计算，`Shared/WatchStore.swift` 是 Watch App／Watch Widget 的本地共享存储。

手机展开所选学期整份课程，先按教学周筛选，再合并连续节次，沿用教3特殊作息。课程使用具体日期时间，手表按校园时区（Asia/Shanghai）计算状态，离线跨天、跨周无需手机在线。手机选择其他学期时同步该学期，课表页底部标明学期。手机同时同步课程配色下标，Watch 首页和今日课表沿用 iPhone 课表的浅色课程块与左侧色条；旧缓存缺少颜色下标时使用默认蓝色。

`PhoneWatchBridge` 在 App 初始化时激活 WatchConnectivity，订阅业务状态变化并去抖；前后台切换、Watch 请求、配对状态改变和校历解析完成会尝试同步。手表请求只读取手机当前缓存，不触发校园查询；业务数据仍按手机现有刷新策略获取。

小数据通过 `updateApplicationContext` 发送最新状态；较大快照通过文件发送，并用轻量描述同步账号状态。手表以生成时间拒绝乱序数据。退出登录或切换账号后，描述信息到达即清理旧账号；较大文件尚未抵达时，同账号保留离线内容。手机演示账号不参与同步。

App Group `group.com.cell.xatuapp` 在手表上只用于 Watch App 和 Watch Widget 共享文件，不能跨设备共享。Watch 不接收密码或 Cookie，不直接登录校园系统。同步受系统传输调度影响；手表断连时不能立即获知调课、手机退出登录或账号切换。

手表收到数据后更新本地缓存并请求重载复杂功能时间线，提前生成未来 48 小时的上下课及午夜节点。实际表盘绘制由系统调度；不承诺秒级刷新。首版不安排 Watch 本地通知，手机通知行为保持原有机制。

## 构建与运行

新增 targets：

- `XatuHelperWatch`：`com.cell.xatuapp.watchkitapp`
- `XatuHelperWatchWidget`：`com.cell.xatuapp.watchkitapp.widget`

最低 watchOS 10，使用 watchOS 27.2 SDK 构建验证。iPhone scheme `XatuHelper` 自动嵌入 Watch App，Watch App 自动嵌入其 Widget 扩展。可选择共享 scheme `XatuHelperWatch` 在 Watch 模拟器或配对真机运行。

真机需为四个 targets 配置同一开发团队和各自可用的 Bundle ID，为 Watch App／Watch Widget 开通相同 App Group。若修改 iPhone Bundle ID，同时修改 `Config/Watch-Info.plist` 的 `WKCompanionAppBundleIdentifier`、两个 Watch Bundle ID；若修改 App Group，同时修改 entitlements 与 `WatchStore.appGroup`（原 iOS Widget 的 `WidgetStore.appGroup` 也需一致配置）。

```sh
xcodebuild -project XatuHelper.xcodeproj -scheme XatuHelperWatch \
  -configuration Debug -destination 'generic/platform=watchOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project XatuHelper.xcodeproj -scheme XatuHelper \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Debug 模拟器启动参数：`--watch-preview` 使用内存示例数据；叠加 `--watch-preview-exam` 展示当天考试，`--watch-preview-long` 展示长课程名。这些参数不写入缓存、不连接手机，Release 构建不包含示例入口。

## 验证记录与真机验收

已通过：Watch 真机架构 Debug 构建、Watch 模拟器 Debug 构建、iPhone 连同两个 Widget 和 Watch 的 Debug／Release 无签名构建；56 项 Watch 模型与问候语断言；原有 169 项电费策略及 6 项终止通知检查。S9 45mm／watchOS 27.2 模拟器检查首页考试替换下一节摘要、纵向课表分页和四页横向切换。

仍需配对真机验证：首次同步、手机锁屏／后台／不在附近、较大课表文件传输、重新连接、退出登录清理、实际表盘槽位和刷新调度、数码表冠手感与耗电。这些依赖实际签名、配对和账号数据，不能用构建成功替代。
