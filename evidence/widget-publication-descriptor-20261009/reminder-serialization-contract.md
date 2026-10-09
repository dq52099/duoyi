# ReminderDeliveryCopy v1 序列化契约

日期：2026-10-09
范围：只读主干 ReminderDeliveryCopy、既有 reminder_delivery_copy_test.dart，以及 pending locale refresh 私有契约。仅交付本报告；未修改生产/测试，未执行 Git、测试、SDK、build、网络或设备操作。

## 1. 接口与精确 schema

新增接口：

~~~dart
Map<String, Object?> toJson();
static ReminderDeliveryCopy? tryFromJson(Object? value);
~~~

tryFromJson 接受已经解码的 JSON object/普通 Map，不自行 jsonDecode 字符串。传入 JSON 字符串、fingerprint 字符串、数组、null 或其他非 Map 值，返回 null。

toJson 每次返回独立的新 map，字段及输出顺序固定如下：

~~~json
{
  "schemaVersion": 1,
  "subject": "countdown",
  "userTitle": "  考试日 🔔\n考试提醒  ",
  "type": "absolute",
  "kind": "push",
  "days": -1,
  "semanticPush": false
}
~~~

| 字段 | 必须满足 |
| --- | --- |
| schemaVersion | Dart int，严格等于 1。 |
| subject | String，精确为 todo / goal / habit / anniversary / countdown 之一。 |
| userTitle | String；允许空字符串及任意原始用户字符串。 |
| type | String，精确为 absolute / relativeToDue / dailyTime / weeklyTime 之一。 |
| kind | String，精确为 push / alarm / email / popup / off 之一。 |
| days | Dart int，范围 -9007199254740991 至 9007199254740991，含两端；另须满足 subject 约束。 |
| semanticPush | bool；另须满足 subject 约束。 |

七个字段全部必需。v1 只接受这七个 String key；缺失、null、额外字段及非 String key 都拒绝。解析时 map 字段顺序不影响结果。

不接受大小写变体、前后空格、枚举 ordinal、旧别名、String 化数字、0/1 bool、double 到 int 转换或任意 toString 转换。不要依赖将来 Enum.values 自动扩大 v1 的可接受值。

整数范围选用 JSON/JavaScript 精确整数边界，以保持 Dart VM、web JSON 及将来 native 存储之间的值一致；它不是业务天数范围。超出范围的 in-memory copy 仍保留原构造器行为，但 toJson 明确抛出 RangeError，不能 clamp、取绝对值或输出无法无损 round-trip 的 v1。tryFromJson 越界返回 null。以后原生直接解析此字段时须保留足够宽的整数，不能用 optInt 默认值或窄化转换。

类型判断以解码后的 Dart 值为准。VM 上 double 1.0 应被拒绝；web 运行时可能把整数形式的数值视作 int，Object? 接口不能证明原 JSON token 是 1 还是 1.0/1e0。此接口不承诺原始数字 token 的词法验证，也不为此增加有损转换。

## 2. subject 的完整约束

| subject | type | kind | days | semanticPush | 重建入口 |
| --- | --- | --- | --- | --- | --- |
| todo | 四种已知 type | 必须 push | 必须 0 | 必须 false | todo(userTitle, type) |
| goal | 四种已知 type | 五种已知 kind | 必须 0 | 必须 false | goal(userTitle, type, kind) |
| habit | 必须 absolute | 必须 push | 必须 0 | true 或 false | habit(userTitle, semanticPush: value) |
| anniversary | 必须 absolute | 五种已知 kind | 范围内有符号整数 | 必须 false | anniversary(userTitle, days, kind) |
| countdown | 必须 absolute | 必须 push | 范围内有符号整数 | 必须 false | countdown(userTitle, days) |

固定字段仍必须存在且正确。不能忽略 habit 的 dailyTime、todo 的 alarm 或 goal 的非零 days，然后依靠构造器默认值把它们修正为有效对象；这些组合返回 null。

[当前构造器](/home/ubuntu/duoyi/lib/services/reminder_delivery_copy.dart:9) 对 anniversary days 未加非负限制，因此 v1 保留负数。既有测试只覆盖纪念日 0/1/8，不能据此推导非法值规则。若以后产品要求非负，应另行明确业务校验/迁移，不在此次 serializer 中悄悄改变可表达事实。

goal/anniversary 的 email 和 off 是现有 renderer 及测试覆盖的有效语义值，serializer 必须接受。这里的 kind 是文案事实；todo/habit/countdown 的固定 push 不证明其实际物理 sink 是 push。真实渠道、归属和调度在物理注册账本中记录。

## 3. 安全解析与失败语义

tryFromJson 对普通解码 JSON/Map 的无效输入返回 null，不抛类型转换、未知枚举或 RangeError：

1. 确认外层 Map 及严格 key 集合。
2. 分别读取每个值，使用 is String / is int / is bool 检查。
3. 验证 schemaVersion 与固定的枚举白名单。
4. 验证 days 范围和 subject 的所有组合约束。
5. 仅在全部验证通过后调用对应公开构造器。

不要使用未经校验的 as Map<String, dynamic>、Map.cast、Map<String, dynamic>.from 或嵌套泛型 cast；它们可能在读取时才抛异常。不要把未知值交给 Enum.byName 后依赖异常补默认值。使用明确 switch/查表，未知项返回 null。

这里的非抛异常保证针对 JSON-compatible 普通 Map；不要求吞掉自定义恶意 Map getter 抛出的程序异常。无需 blanket catch 掩盖实现错误。

不接受 fingerprint 六元数组，不解析已经渲染的 title/body，不从当前 locale/brand、模型或调度数据补缺失字段。v1 没有 userBody 字段；以后物理账本中的独立 raw body 不得通过 userTitle 伪造恢复。

## 4. Literal 与 fingerprint 保真

必须成立：

~~~text
restored = tryFromJson(jsonDecode(jsonEncode(original.toJson())))

restored != null
restored.userTitle == original.userTitle
restored.userTitle.codeUnits 与 original.userTitle.codeUnits 逐项相等
restored.semanticFingerprint == original.semanticFingerprint
restored.toJson() 与 original.toJson() 的字段和值相等
~~~

所有有效字段都应保持，不仅是最终渲染恰好相同。保留 leading/trailing whitespace、空行、CR/LF、实际换行与字面反斜杠+n 的区别、引号、分隔符、emoji 及 Unicode 组合序列；不 trim、normalize、翻译或提取模板。

semanticFingerprint 继续使用[现有实现](/home/ubuntu/duoyi/lib/services/reminder_delivery_copy.dart:49)的六元数组：

~~~text
jsonEncode([subjectName, userTitle, typeName, kindName, days, semanticPush])
~~~

不加入 schemaVersion、locale、BrandStrings、渲染后的文案或 JSON map 顺序；不改成整个 toJson 的 JSON。现有 fingerprint 固定字符串及所有变化/稳定性测试应继续成立。

序列化和反序列化不调用 render、不修改 I18n.current 或 localeListenable。round-trip 后以显式 locale/BrandStrings 渲染的结果，与原对象在 zh/en、default/re0/liquidGlass 等既有测试条件下相同。

## 5. 向前兼容策略

v1 是封闭 schema。schemaVersion 缺失、0、2 或其他未知值返回 null；未知 subject/type/kind、新增字段也返回 null。不要“尝试当作 v1”或使用 defaults。

未来增加 subject、改变字段意义、扩大枚举或改变整数表达方式，升级 schemaVersion 并写显式迁移/对应 decoder。仅 JSON key 重排不需要版本变化。

旧 reader 遇到未知 descriptor 时，上层账本保留原始记录、物理注册归属及取消能力，将该节点标为不可做语义刷新；不要删除未知记录、覆盖为缺省 copy 或触发 resync。serializer 返回 null 不等价于注册不存在或可以重建。

## 6. 精确验收矩阵

[既有测试](/home/ubuntu/duoyi/test/services/reminder_delivery_copy_test.dart) 已覆盖五类 renderer、所有现有 type/kind、Habit 两种变体、literal、显式 locale/brand 和 fingerprint；尚无 toJson/tryFromJson 用例。本次未运行测试。

后续新增 serializer fixture 至少包括：

| 用例 | 断言 |
| --- | --- |
| todo 全部 4 type；goal 全部 4×5 组合；habit false/true；anniversary 全部 5 kind；countdown | toJson 七字段精确、严格 round-trip、fingerprint 与双语渲染均保持。 |
| anniversary/countdown 的 0、1、8、-1，以及范围两端 | 值和符号不变；纪念日负数保留当前表达能力。 |
| days 边界外 ±9007199254740992 | toJson RangeError；tryFromJson 返回 null，不截断。 |
| raw literal | 空字符串、全空格、前后空格、CR/LF、实际换行、字面反斜杠+n、引号、模板相似文本、emoji、不同 Unicode 组合序列都无损。 |
| 所有字段分别缺失/null/错误类型 | 返回 null；特别覆盖 version/days 的 String、double、bool，以及 semanticPush 的 String/0/1。 |
| schema/枚举错误 | 未知 version、大小写/空格/ordinal/未知 enum 值、未知 subject 均返回 null。 |
| 所有 subject 固定字段分别被篡改 | 如 todo kind=alarm、habit type=dailyTime、goal days=1、anniversary semanticPush=true、countdown kind=popup，均返回 null。 |
| 非 Map、数组、fingerprint 字符串/数组、额外/non-String key | 返回 null，不抛普通输入解析异常。 |
| map key 顺序变化、调用后修改返回 map | key 顺序不影响解析；修改某次输出不改变原 copy 或之后的新 toJson。 |
| global locale 设为 en 后做 serialize/deserialize 和 zh→en→zh render | I18n.current/listenable 不变，fingerprint 与原六元数组精确一致。 |

最小生产范围仅 [reminder_delivery_copy.dart](/home/ubuntu/duoyi/lib/services/reminder_delivery_copy.dart)；最小 fixture 范围仅既有 test 文件。无需在该基础项中接 listener、触碰 scheduler、调度或平台。

该基础项完成只证明 descriptor 可持久化。真正 pending ownership、同物理 ID 的归属/替换、准确时间、账号及 latest-locale fence、平台更新、fallback 去重和不重放 past-due，仍须按[完整 pending 契约](/home/ubuntu/duoyi_deploy_backups/widget-refinement-20261006/pending-reminder-locale-refresh-contract-oct9.md)继续实现与验收。
