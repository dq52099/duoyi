# duoyi 项目更新报告（2026-10-03）

本轮修复已整合到 `/home/ubuntu/duoyi`。基于任务开始时的源码快照，增量为 51 个文件：19 个 Dart 源文件、1 个 Android 源文件、2 个后端文件、2 个脚本和 27 个测试文件。用户随后授权本地提交，提交范围包含已验证的相关源码、已有必要依赖、测试、脚本及本轮验收记录；51 个文件的补丁仍用于区分本轮新增修复。`/home/ubuntu/AGENTS.md` 和仓库已有 `AGENTS.md` 保持原样。

## 修复内容

- **共享删除同步**：客户端和后端按 workspace、集合及对象 ID 保存删除标记；支持仅含删除的同步请求，检查成员权限，保留同 ID 私有副本，并允许更新的重建覆盖旧删除。
- **账号隔离**：Auth 写回尾链先排空再清理；旧请求使用捕获的身份和 client，不能在新账号下重试或落盘。启动清理失败时阻止加载旧数据；旧头像、声音目录先移入隔离目录再异步删除。
- **提醒与围栏**：清理先暂停并排空调度批次，失败保留待取消 ID；原生围栏注销失败保留元数据，失败注册的恢复完成后再返回结果。
- **通知页面**：补齐失败重试、详情刷新/关闭和对象路由；账号切换立即清空列表及详情，同账号恢复重新加载，旧弹层不能绑定新账号同名对象。
- **主题与样式**：主题兑换及 provider 每个异步步骤复验原账号代次，保护计数、奖励、事件和反馈；移除违规粗体，统一边框，纪念日失败提示使用既有国际化键。
- **验收脚本**：累积失败时返回失败；报告时效检查排除 Gradle/Python 构建缓存，同时保留真实源码过期检查。

## 验证结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| Flutter 完整回归覆盖 | 242 个文件，1,617 项通过 | [覆盖说明](flutter-final-summary.md) |
| 最后一次主题相关回归 | 21 项通过 | `theme-final-explicit-context.log` |
| 后端全套回归 | 153 项通过 | `backend-current-final.log` |
| 最终 Flutter analyzer | No issues found | `alignment-final-complete/6_8_flutter_analyzer.log` |
| 调试 APK | 构建成功，包含三个 ABI | [产物信息](apk-final-metadata.json) |
| 最终 alignment gate | 前七组通过；设备组 failed(2)，整体 exit 1 | [gate 汇总](alignment-final-complete/summary.md) |
| 最终 closure validator | 报告、时效及映射通过；三项设备证据问题，exit 1 | [验收汇总](goal-closure-final/summary.md) |

Flutter 全套首段在 1,528 项通过后收到外部 SIGTERM，剩余 16 个文件续跑 89 项通过，覆盖集合没有重复。随后仅补写主题页八处等价的显式 mounted 检查，并重跑主题测试、分析器和完整 gate；上述 1,617 项不是一次未中断执行的结果，也不叠加重复的 gate 测试数量。

前两次 APK 构建只有通用 kernel 异常。最终使用临时 Gradle 2GB heap、1GB metaspace、两个 worker 和详细日志，Dart 内核、Kotlin/Java、资源及打包均通过；仓库 Gradle 配置未修改。构建耗时约 21 分钟，Gradle JVM RSS 峰值约 2.77GiB。现有证据未证明前两次异常是 OOM。

APK：`build/app/outputs/flutter-apk/app-debug.apk`，217,438,528 字节；ABI 为 `armeabi-v7a`、`arm64-v8a`、`x86_64`。本地环境为 Linux aarch64、Flutter 3.41.9、Dart 3.11.5、Java 17；未执行 CI 或 iOS 构建。

## 仍待真机验收

用户确认目前没有设备或已有材料。通知、桌面组件和设备要求保持 `open(device_evidence)`；详见 [逐项清单](pending-device-acceptance.md) 和 [需求状态](requirement-status-final/status.md)。包含 Android/iOS 通知与十个组件、账号切换、围栏清理、冷启动，以及提醒批次所有权落盘前杀进程的窗口。

六张 AGY 截图来自真实字体的合成 Flutter web 预览，不能替代原生触发或真机账号切换证据；范围见 [UI 审阅](ui-review.md)。账号边界结论见 [最终复审](final-account-boundary-review.md)。

## 审阅与后续执行

[增量补丁](incremental-changes.patch) 和 [文件清单](incremental-files.json) 使用任务开始时的快照，包含本轮改动；补丁已通过反向应用检查，源码 `git diff --check` 通过。提交保留两个补丁附件的上下文空白及两个设备命令输出的原始空白；这些附件不参与空白检查，具体路径记录在验证记录中。

[验证记录](verification.json) 保存测试结果、最终 gate 状态和原始日志的 SHA-256。原始 `*.log` 按仓库忽略规则保留在本机；提交中的报告、状态表、源码指纹和 APK 校验信息供后续审阅。调试 APK 由构建目录提供。

设备可用后，按清单采集真实材料，并重跑：

```bash
scripts/device_regression_check.sh
scripts/validate_device_evidence.sh android
scripts/validate_device_evidence.sh ios
scripts/alignment_regression_gate.sh
scripts/validate_goal_closure.sh
```
