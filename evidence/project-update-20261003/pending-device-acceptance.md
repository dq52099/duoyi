# 真机待验收项（2026-10-03）

用户确认目前没有可连接设备或既有材料。本清单保持待验收；单元测试、模拟截图和 APK 构建不能替代真机证据。

## Android

- [ ] 通知栏显示今日进度，关闭设置后移除；持续进度通知不计入提醒次数。
- [ ] 同一提醒分别以普通通知、应用内弹窗、闹钟/全屏方式触发，声音与震动符合设置；拒绝权限时给出准确失败提示。
- [ ] 默认铃声为「柔和晨铃」，内置及自定义铃声可播放；重复保存、冷启动与提醒重排后只触发一次，无重复声音。
- [ ] 10 个独立桌面小组件均可添加，紧凑/标准/详细模式或系统支持的尺寸布局正常。
- [ ] 修改应用数据后小组件刷新；完成待办、快速添加、习惯打卡动作生效。
- [ ] 今日聚合/日历中的倒数日深链打开正确详情。
- [ ] A 账号提醒已注册时退出并登录 B：旧通知、弹窗、闹钟和地理围栏均取消，B 的新文件与新提醒保留；清理失败应阻止切换并允许重试。
- [ ] 提醒批次中断后重启，残留队列可清理；额外检查进程在批次所有权落盘前被杀的窗口。
- [ ] Android 地理围栏退出账号、拒绝权限、部分注册失败及恢复流程；失败恢复不能覆盖后续清空。
- [ ] 冷启动、后台恢复、杀进程重启，以及 `integration_test/app_alignment_smoke_test.dart`。

## iOS / iPadOS

- [ ] 在 macOS/Xcode 配置签名，使用受信任的实体 iPhone/iPad 构建并运行。
- [ ] 系统组件库中展示 10 个独立 WidgetKit 组件，各支持的 family/尺寸布局正常。
- [ ] Runner 与 Widget Extension 使用 `group.com.duoyi.duoyi`，应用数据改变后组件刷新。
- [ ] 待办完成、快速添加、习惯打卡、开始专注和底部导航动作均生效。
- [ ] 日历聚合中的倒数日深链正确；通知及适用的时间敏感提醒正常。
- [ ] 切换账号后旧组件内容及旧提醒清除，新账号资料/奖励/主题不被旧请求覆盖。
- [ ] 冷启动、后台恢复、杀进程重启及集成冒烟检查。

## 证据与执行

按照 `docs/device-regression-evidence.md` 收集设备信息、安装/启动日志、队列与小组件系统输出，以及非空截图/录屏。Android 的 12 个、iOS 的 10 个 manual manifest 键须逐项填写真实证据路径。

```bash
scripts/device_regression_check.sh
scripts/validate_device_evidence.sh android
scripts/validate_device_evidence.sh ios
scripts/alignment_regression_gate.sh
scripts/validate_goal_closure.sh
```

当前主机为 Linux aarch64：没有可用 Android 运行设备，现有 adb/emulator 为 x86-64，缺少 KVM 与可用 AVD 系统镜像；此环境不能提供 macOS/Xcode 的 iOS 验收。完整通知与组件验收仍待完成。
