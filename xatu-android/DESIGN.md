# Android Material Design 3

本次调整针对独立 Skip Android 工程，原 `XatuHelper/` iOS 工程不变。

## 视觉与组件

- 配色：`MaterialDesign.swift` 使用 Android `MaterialTheme` 相同的语义色。Android 12+ 跟随系统动态色，旧系统使用 Material 3 默认色；浅色和深色各缓存一次，滚动过程不调用 JNI 查询色值。
- 字号：标题 28/22 sp、列表标题 16 sp、中等正文与标签 14 sp、辅助文字 12 sp；字体遵循系统缩放。
- 页面：使用左对齐 Material TopAppBar、Material NavigationBar、12 dp 圆角的色调卡片，主要页面边距 16 dp；移除原首页大面积渐变和延迟入场动画。
- 操作：工具栏图标 24 dp、点击区域 48 dp；主要操作使用原生 Filled/Outlined Button；设置继续使用原生 Switch、Picker 与对话框。
- 列表：考试、成绩、学业进度、电费、历史记录、校历、宿舍选择、课程详情和设置统一为平面列表；静态信息行内容最小高度 40 dp，加列表上下内边距后达到常规单行列表高度。
- 登录：Outlined TextField、Filled 主操作、Outlined 网页登录操作；凭据和验证码逻辑沿用原实现。
- 通知：应用内提示改为底部 Snackbar 风格，提供查看与关闭操作。
- 网页：统一 App 自有导航与提示容器；学校网页内部由学校提供。
- 自适应：校园服务卡片按可用宽度自动分列；课表纵向可滚动，单节课程块不再被压缩到过小高度。

## 渲染成本

- `TimetableIndex` 在原始课表变化时建立周次索引与连排结果，主页和课表复用。
- 分页只构建当前周及相邻周的真实内容，保留 30 周稳定标签。
- `androidEquatable` 复用未变化的周网格，缓存键包含数据修订、周次、学期起始日、周末设置、深浅色与当天日期。
- 网格线合并成一条 Path，减少 Swift/JNI/Compose 视图节点。
- 远距离选周直接跳转，避免经过大量中间页面的动画。
- 面向使用的 APK 使用 Swift Release 优化编译和 R8；Debug 包保留供开发使用。

依据：[Material 3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3)、[Compose performance](https://developer.android.com/develop/ui/compose/performance)、[Skip UI 定制与性能接口](https://skip.dev/docs/modules/skip-ui/)。
