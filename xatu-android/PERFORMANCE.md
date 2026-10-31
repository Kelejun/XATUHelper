# Android 渲染验证

## 当前结论（2026-10-31）

用户实机反馈：现有 Android 版本功能基本能用，但运行不到 **10 FPS**，性能问题尚未解决，不建议日常使用。后续计划使用 **Kotlin + Jetpack Compose** 重构；当前代码仍为 Skip Fuse 实现。

以下数据是此前模拟器上的历史采样，不能替代实机结果，也不能据此认定性能已达可用水平。实机型号、测量工具和完整采样条件尚未记录，低于 10 FPS 为用户实机反馈，不应与下方 HWUI 帧耗时直接换算比较。

## 历史模拟器采样

设备：Android 16 / API 36，ARM64，`XatuHelper_API36`，1080×2400。

方法：同一模拟器、现有相同课表；打开课表后预热 2 秒；左右各一次为一组，共 8 组，手势 18 步、间隔 300 ms。独立测试进程读取系统 HWUI `framestats`；按 IntendedVsync 去重，仅统计 Flags=0 的有效帧。没有在测量期间并行编译。

| 安装包 | 有效采样帧 | P50（ms） | P95（ms） | 超过 32 ms 的帧 |
| --- | ---: | ---: | ---: | ---: |
| 1.0.3 Debug（原交付包） | 595 | 19.12 | 71.57 | 132 |
| 1.1.0 Release（最终交付包） | 587 | 25.62 | 33.56 | 44 |

最终验收采样中 P95 长帧耗时下降约 53.1%，超过 32 ms 的帧数由 132 降至 44。中位帧耗时没有改善。系统同步报告的卡顿帧比例由旧版 94/595（15.80%）降至新版 30/587（5.11%），下降约 67.7%。以上是模拟器的一次成对采样，不代表所有帧区间都变快，FrameCompleted 包含 GPU 排队等待，不能直接把其倒数当作 FPS；也不能据此保证真机固定 60/120 FPS；实际帧率还取决于设备 GPU、温控和刷新率。对比包含 UI 改动、缓存与 Release 优化的共同结果，不是单因素实验。

代码中已减少的开销：课表索引/连排重复计算、远处周页面构建、未变化周网格的 Swift/JNI 重复求值、多节点网格线、首页长入场动画和 Debug 运行成本。

## 复测

```sh
# 应用
XATU_BUILD_VARIANT=Release ./xatu-android/scripts/build-android.sh
# 独立性能测试 APK（不会更改 Release 应用）
./xatu-android/scripts/build-device-tests.sh
adb install -r xatu-android/.build/Android/app/outputs/apk/release/app-release.apk
adb install -r xatu-android/.build/Android/device-tests/outputs/apk/debug/device-tests-debug.apk
adb shell am instrument -w -r -e class xatu.android.ReleaseFrameTimingTest com.cell.xatuapp.test/androidx.test.runner.AndroidJUnitRunner
```

测试需要现有登录会话；缺少会话会跳过，不会输入账号密码或清除数据。指标输出标签为 `XATU_HWUI_TIMING` 与 `XATU_HWUI_SUMMARY`。初次采样中新版 P95 曾为 43.38 ms；补测与最终交付包分别为 33.72 / 33.56 ms，体现模拟器运行状态与缓存带来的波动。

最终安装包 SHA-256：`4114516572c40649e715f9c0c0b6b6a1cc9a1477de4eae2b5275c8a8049c9832`。
