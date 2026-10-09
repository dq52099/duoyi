# Widget publication Dart client source review

2026-10-09。只读检查 `/home/ubuntu/duoyi-worktrees/widget-publication-client-20261009/lib/services/widget_publication_client.dart`，对照此前已经审阅的 Kotlin Bridge/Envelope/Transition request、read与ack形状。未修改源码、添加/执行测试、运行 SDK/构建/Git/网络。该 client 尚未接入现有 publisher。

本轮未发现可定位的通道形状或不可变捕获缺陷。

- `read` 发出无参数 `readWidgetStore`，符合 Bridge 的 null/empty-map许可。ready/sealed 要求精确九字段形状、合法完整 document、binding/state/epoch/presentation 关联，且不包含 writer capability。非健康状态不能被当作 absent。
- request factories 与 Kotlin parser 的精确字段集合一致：open 的 mode/binding/presentation；invalidate 的 presentation；advance 的 writerLeaseId/desiredPresentation；publish 的 writerLeaseId/expectedPublicationRevision/document。protocol=1与期望 revision/epoch一致；只有已确认 absent initialize 产生 null expectations。
- `_freeze` 对所有嵌套 map 防御复制；请求内容来自已经严格验证的 primitive DTO、binding及snapshot，故没有未复制的可变 list/value。同一个 request保留原method/operationId/expectations/document，native负责digest，client不提供digest权限。
- 成功 ack 的精确字段集合与 Bridge的refreshRequested=false及Store的non-open lease删除一致；operationId、storeRevision+1及各操作的epoch/pub/desired/applied/state结果被核对。open才能返回lease。`alreadyApplied`使用原request的expectations检查原receipt，符合原样retry；不会接受给旧内容换最新revision的ack。
- failure 同时兼容 Store 的operationId失败形状、Bridge的parse/queue失败status-only形状和refreshRequested=false追加；未知或不匹配的响应为invalidResponse，不能推进committed缓存。
- PlatformException返回responseUnknown，MissingPlugin返回unavailable；client不自动重试、不重建expectations、不从read授予lease。请求仍由调用方持有，可原样retry。最终修订为 read/submit 加了默认15秒、必须为正的 responseTimeout（351–407）：read超时返回unavailable，mutation超时返回responseUnknown。Dart Future.timeout只限制等待，不取消 native transaction；timeout不能被判为未提交，仍需保留原request和当前context才能决定retry/read恢复。

结果仅限源代码协议审阅。auth/cleaner generation、当前lease/presentation重新校验、bootstrap、clear barrier以及失联后的恢复由后续controller负责；不能把client.committed当作当前auth有效或launcher已经显示。这里没有新增native API或自动恢复行为，也没有runtime/跨平台验证声明。

最终 timeout 分支已做有限只读复审，未发现新增问题。最终源 SHA-256：`c56250f6776106e4941a70ebb2d0127b0566372d249c5928e89abb8243d6d126`。该指纹对应上列 client 文件；旧的“无内置 timeout”观察已替换，不能用于此最终版本。
