# 最终账号边界复审

本记录汇总 Sol 对最终源码的只读复审。复审未修改代码或运行 Flutter；测试由主会话执行，结果保存在同目录日志。

## 已关闭的路径

- 通知页在 Cleaner 代次失效时立即清空，不提前读 registry；Auth 切换开始和结束均可观察，同 key/generation 的恢复仍会重新加载。
- 列表、队列、延迟自动详情和弹层返回导航复验原账号及 readiness；旧详情解除 objectKey 绑定，不能显示新账号的同名对象。
- ThemeProvider 使用操作入口捕获的 storage/account generation，在异步落盘后复验，覆盖计数、事件、后续写入、确认标记和通知。事件后再复验，覆盖同步监听器触发 reset。
- AchievementProvider 在 snapshot 落盘后、读取缓存修改内存前复验；消费操作在保存后复验再更新 revision、通知或返回成功。
- Auth 尾链先排空当前回调，后执行清理；请求使用捕获的 client/身份/代次，旧响应不能使用下一账号的 client 重试。

对最新两个 provider 差异的结论：可接受，未发现新的阻断项。

## 实际回归

- `transition-boundary-final.log`：79 项通过，含真实 Auth hydration 的 `[true, false]` 切换通知以及不改变账号 key/generation 的通知页恢复。
- `theme-provider-boundary-final.log`：21 项通过，含首轮缓存写已发生后 reset 的主题计数、主题确认、奖励内存和消费结果保护。
- 真机及杀进程场景仍按 `pending-device-acceptance.md` 验收；这些测试不能证明系统队列或进程在批次所有权落盘前被杀的窗口。
