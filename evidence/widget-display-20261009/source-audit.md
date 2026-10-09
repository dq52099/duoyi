# Widget display final source audit — 2026-10-09

## 范围与结论

只读复审 `/home/ubuntu/duoyi-worktrees/widget-display-20261009` 的已结束 AGY revision3，依据私有 `widget-display-contract-oct9.md`、revision2 的延续要求与 `agy-widget-display-oct9-revision3.md`。本审没有改生产文件或 fixtures，没有运行 tests / compiler / Flutter / Gradle / Git；只生成此私有报告。主审告知 revision3 writer 已结束；收到主审准备限定返工的通知后，已停止生产源码读取，后续复审须等待停写通知。

审阅的生产路径限于以下 9 个：

1. `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetContent.kt`
2. `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiAnniversaryWidgetProvider.kt`
3. `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCalendarWidgetProvider.kt`
4. `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetCopy.kt`
5. `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetSnapshot.kt`
6. `android/app/src/main/res/layout/duoyi_calendar_widget.xml`
7. `android/app/src/main/res/values/strings.xml`
8. `android/app/src/main/res/values-en/strings.xml`
9. `ios/DuoyiWidgets/DuoyiWidgets.swift`

**终态源码复审仍有三项必须修复：Swift 原始 malformed percent 被 Foundation 修复后接受、空 port 的原 authority 漏检、Swift String canonical equivalence 合并不同 opaque ID。**前两项属于 revision3 要求的严格当前 URI 解析；第三项属于按真实对象身份去重、保留 opaque ID 的契约。三项都可限定在 Swift pure display helper 内修复，无需扩大生产范围或改 fixture 规避。

本报告提供静态路径与供主审 runner 复现的输入，**不把尚未执行的运行结果写成实测**。主审计划用真实 Swift container runner 确认后限定返工。

## 1. Must-fix F1：原始 malformed percent 检查在 URLComponents 之前缺失

**位置：** `DuoyiWidgets.swift:439–455`、`:510–542`、`:624–672`。

`hasIllegalUriCharacters` 检查空白、control、反斜杠、quote / braces / pipe / brackets 等字符，但是不检查 `%` 后是否恰好有两位 ASCII hex。两个当前 URI parser 均在这项检查之后直接调用 `URLComponents(string: raw)`，随后把 `components.percentEncodedPath` 交给 `strictPercentDecode`。

问题是 Foundation 可将原始非法 percent 修复为 `%25`。后面的 decoder 检查的是修复后的 path，原始非法输入已丢失，因而不能完成 revision3 的预校验要求。

| 供 runner 复现的输入 | 契约期望 | 源码路径将检查的修复值 / 风险 |
| --- | --- | --- |
| `duoyi://anniversary/bad%ZZ` | `(duoyi://anniversary, nil)` | path 中的 `%ZZ` 可成为 `%25ZZ`；解码得到 `bad%ZZ` 并作为有效 identity。 |
| `duoyi://anniversary/%2` | safe anniversary root，nil identity | `%2` 可成为 `%252`；后续 strict decoding 成功。 |
| `duoyi://todo/bad%ZZ` | `duoyi://calendar` | Calendar parser 检查修复后的 path 后返回原 raw target；`linkedText:1662` 再次用 URLComponents，使它可成为实际可点击 detail URL。 |
| `duoyi://todo/%2` / `duoyi://todo/%` | `duoyi://calendar` | 同样没有原始 `%HH` 校验。 |

Anniversary parser 返回修复后的 encoded segment，Calendar parser返回 raw，但两条路径均接受本应拒绝的 current URI。`snapshot.actionURL:334–337` 对非 action host 直接返回 `components.url`，不会在点击层补做该检查。

**限定修复：**在 Foundation parse 前扫描当前 URI 的原始字符串 / 原始 encoded segment；每个 `%` 必须跟随恰好两位 ASCII `[0-9A-Fa-f]`。保留 actual URLComponents scheme / authority / path 校验与当前 strict UTF8 decoder。不要对 legacy opaque ID 使用当前 URI 的 malformed-percent 禁令：legacy `bad%ZZ` 本身可以是一个真实 ID，应 encode 为 `bad%25ZZ`；只有以当前 URI 形态输入的非法 `%` 应回退。

**防回归：**`%25`、`%2F`、`%2B`、中文 / emoji 的正确 UTF8 escape、literal `+`、decoded-once 的 `%252F` 必须仍合法；不要反复 decode，也不要用修复后的 Foundation 字符串冒充原输入已合法。

## 2. Must-fix F2：port=nil 不能证明原始 authority 没有 port 分隔符

**位置：** `DuoyiWidgets.swift:520–529`、`:640–649`。

Swift parser 只检查 `components.user/password/port == nil` 和解析出的 host allowlist，没有校验原始 authority。空 port 语法可能有明确 `:` 但 `components.port` 仍为 nil，因而落入允许分支。Kotlin 的对应 parser 在 `DuoyiWidgetContent.kt:162–167` 和 `:282–286` 额外检查 authority 中的 `@` / `:`，已挡住此形态。

| 供 runner 复现的输入 | 契约期望 | Swift 漏检分支 |
| --- | --- | --- |
| `duoyi://anniversary:/x` | safe anniversary root，nil identity | host 为 anniversary / port nil 时，返回 `duoyi://anniversary/x` 和 identity `x`，把非法 authority 正规化为合法目标。 |
| `duoyi://todo:/x` | `duoyi://calendar` | host allowlist 通过、single path通过，返回 raw。 |
| `duoyi://focus:` | `duoyi://calendar` | focus root path 空且 port nil 时直接返回 raw。 |

**限定修复：**只对 `://` 与第一个后续 `/` 之间的原 authority 做校验；拒绝 userinfo / port 分隔符及与允许 host 形态不符的 authority，再使用 URLComponents 解析验证。不能扫描整条 URI 找 `@` / `:` 并拒绝，否则会误伤合法 path ID，例如 `duoyi://anniversary/a@b`、`duoyi://anniversary/record:42`。更不能把 legacy `record:42` 一概归为外部 URI。

这项是“没有端口”的 shape 契约缺口；不能仅把 `components.port == nil` 的代码存在视为已经满足原 authority 校验。

## 3. Must-fix F3：Set<String> 的相等语义不是 opaque ID 的字节身份

**位置：** `DuoyiWidgets.swift:580–597`；对照 Kotlin `DuoyiWidgetContent.kt:219–237`。

Swift 用 `Set<String>` 保存 strict decode 后的 identity。Swift String 相等包含 Unicode canonical equivalence；两个保留了不同 scalar / UTF8 序列的 opaque ID 可能被判相等。Kotlin String 相等比较其实际序列，因此二者跨平台结果不同。

**供 runner 复现：**fresh union 输入：

```text
A1: text="precomposed", target="duoyi://anniversary/%C3%A9"
A2: text="decomposed",  target="duoyi://anniversary/e%CC%81"
```

strict decoding 得到 U+00E9 与 U+0065 U+0301，分别是两个不同的 opaque item ID。契约要求保留两行及各自 target，不能按“显示字符看起来相同”去重。当前 Swift `seenIdentities.contains` 会把第二条视为已见 identity，Kotlin保留二者。

**限定修复：**以 decoded identity 的实际 UTF8 bytes（例如 `Data(id.utf8)` 或等价 Hashable byte key）进行去重，继续向调用者返回原 String identity 与原 target。不要做 Unicode normalization、lowercase、trim 后再作为 identity；trim 只能判断空白 ID 无效。无需修改 helper 对外 API。

**防回归：**同一确切 ID 的 literal `+` 与 `%2B`、raw legacy与 URI、同一 encoded slash 应去重；不同大小写、不同 byte identity、同标题不同 ID 必须保留。

## 4. 已通过源码核对的有界行为

### 4.1 Kotlin actual URI / strict UTF8 / opaque legacy

- 当前 Anniversary 与 Calendar 目标均使用 `java.net.URI`，不是手工拆出 host 代替实际解析。
- 拒绝 userinfo、port、query、fragment、非法 raw whitespace / control / backslash / quote / braces / pipe / brackets、多 path segments和空 segment。URI 构造也会拒绝 malformed raw percent。
- `strictPercentDecode:92–123` 检查 ASCII hex、按完整 code point 复制 raw Unicode，再使用 REPORT decoder 拒绝非法 UTF8；已修复逐 UTF16 Char 导致 supplementary emoji 变为 `?` 的问题。`+` 不作表单空格解码。
- legacy branch `:184–199` 保留 `record:42`、内部空白、emoji与其他 opaque punctuation，以单个 segment encode；没有添加 add / create / new 保留 ID 词。
- current targets只有支持的详情 / root形态进入安全只读目标；非支持 action / 外部 URI 回退，不触发 mutation。

Swift strict decoder `:457–487` 本身同样检查 ASCII hex与UTF8，literal `+`保留，legacy branch保留 `record:42`。其剩余问题是 **decoder 输入来自已正规化的 Foundation path** 和 **Set<String> 去重**，不是 UTF8 decoder 缺失。

### 4.2 Anniversary union 与行可见性

- Android provider `:77–84` 和 Swift entry `:1257–1264` 均按 A1 → A2 → M1 → M2 → M3 建立 text / target 同源记录；没有使用不存在的 A3。
- helper先选有意义候选再按 identity去重，first wins；无 ID bare bullet / 空白 / 已知 placeholder跳过，有 ID且text恰等于placeholder保留；无有效identity的真实legacy文本保留各自行和safe root。
- Android从同一个selected item填text与click target，第二 / 第三行由 item存在与standard/detailed密度决定（`:86–109,139–161`）。
- Snapshot `optionalRows:120–136` 已移除 Anniversary 的 A2/A3旧判空，因此A2为空而实际第二行选M1时不会再被finishRender误隐藏。其他family判空逻辑继续存在。
- 空数据只剩一条localized empty，stale只剩日期待刷新与root；Swift stale entry rows为空。除F3所列byte identity差异外，没有发现union顺序/配对/旧槽位隐藏的 must-fix。

### 4.3 Calendar summary / target 语义绑定

- Android `DuoyiCalendarWidgetProvider.kt:114–131`、Swift entry `:1228–1238` 从同一 display source读取 `today_event_summary` 与 `schedule_highlight_1_id`，调用成对语义helper。
- 缺失 / 空白摘要隐藏；已知no-events摘要本地化并用Calendar root；stale提示用root，不附旧schedule1详情；真实摘要原样展示，目标经过readonly shape allowlist。
- 未读取不存在的 `today_event_summary_id`；month-summary没有冒充event。Android root / title / month / today / grid / month-summary保持原通用Calendar点击，只有事件行绑定所选目标。
- `duoyi_calendar_widget.xml:119–129` 事件TextView为one-line / ellipsize，初始gone；values与values-en在`:63` 提供对应空态，不需要新publication字段。

### 4.4 iOS Calendar day / locale / accessibility

- `calendarContent:1508–1512` 使用 `entry.date` 建Gregorian网格；helper `:745–782`按同一Calendar取得月事实与Monday-first offset，不用固定86400秒递增。
- 年/月标题本地化，weekday顺序一致；真实日期cell具完整年月日label，today trait selected，空白cell hidden；没有伪造消费者不支持的per-date链接。
- accessory仍走原generic入口；theme、header、medium/footer navigation保留。此结论是源码范围核对，不是iOS设备视觉验收。

## 5. Height / Small：revision3 算术修正已完成，设备验收仍必要

**已修正：**`budgetedVisibleWeekRange:864–877` 的基础overhead为 `monthTitleHeight + weekdayHeaderHeight + 2*contentSpacing`，有summary再加 `eventSummaryHeight + contentSpacing`。这对应actual内层VStack的month→weekday→grid两个gap，及grid→summary第三个gap。

caller `:1515–1523` 先确定真正的 `showEventSummary`：stale始终提示、fresh Small不显示、其他fresh family仅有实际摘要才显示。`:1545`把同一条件传给budget helper，`:1613`用它控制实际view；fresh Small不再因raw摘要存在被错误限制为一周。

`calendarBody:1452–1465` 用GeometryReader的实际remaining `proxy.size.height`调用calendarContent，不再与一个额外outer Spacer分享剩余高度。week range保留today并遵守density上限。

**remaining acceptance，不能由pure fixture代替：**

- monthTitle / weekdayHeader / eventSummary 的高度参数是预算值；actual VStack 的Text / HStack / linkedText并没有 `.frame(height:...)` 固定为这些值。实际font metrics、family/container尺寸与layout测量仍须Apple设备 / simulator验证。
- 需要核对Small fresh（standard / detailed）、Small stale、Medium有摘要 / 无摘要、各语言、4/5/6周月份，确认today可见、摘要无截断到不可读、header/footer不挤出、实际内容高度不溢出。
- 纯helper在比minimum one-week更低的availableHeight下仍至少返回一周，不能把这个值当作“任何高度都保证fits”。实际受支持family尺寸必须验收；不据此把本批扩大为任意极小window adaptive改造。
- 主审的Swift container / purefixtures可以确认budget公式与阈值、URI / identity语义；它不能证明WidgetKit设备布局或点击区域已经成功。

本审不将设备布局尚待验收升级为已确认source must-fix，也不称已完成platform视觉验证。

## 6. 本批不阻断的已知外部边界

Android `forDisplay` 仍委托live prefs、freshness/commit仍未统一冻结，是已另开 snapshot atomicity batch 的问题。按主审范围要求，本报告不以该既有gap阻断presentation交付，也不要求AGY扩改immutable frame / Dart publication / registry / day scheduler。

本批的presentation配对与stale路径已经核对；不能因此反向宣称Android snapshot原子性已解决。day / timer timeline调度、producer排序、业务倒计时、账号publication协议继续由各自batch持有。

## 7. 建议限定返工与交付门槛

只修F1 raw percent prevalidation、F2 raw authority empty-port检查、F3 UTF8 byte dedup key；保留已完成的actual URI parse、paired summary helper、height预算修正与union / visibility行为。无需更改9文件之外的production、fixtures或helper公开API。

主审真实Swift runner确认三项输入及防回归case；AGY返工结束、writers停后再复读限定变更，并由主审继续平台验收。本审已经停止生产读取。

STOP。

## 8. Final revision4 — 限定三项修复的终态源码复审

主审通知 revision4 success、worker 已不存在、所有 writers 停止后，本审只读复审同一工作树的 Swift display core。工作树已 fast-forward main `75d72d2` 的信息来自主审；本审未调用 Git。新增 DayBoundary 代码不在本次复审范围，没有重新审阅。只追加本节，保留前文 revision3 缺陷与当时判断作为历史记录。

主审提供的 `widget-display-revision3-swift-defects-reproduced-oct9.json` 已真实复现旧 frozen core 的三项缺陷：bad percent 被变成 `bad%25ZZ`、空 port Calendar target 留为 `duoyi://todo:/x`、两个 byte-distinct Unicode opaque ID 只保留一条。本审只读取该已有证据，没有执行 probe。

### 三项均通过本次源码核对

| 历史项 | revision4 源码位置 | 已确认修复 |
| --- | --- | --- |
| F1 原始 malformed percent | `DuoyiWidgets.swift:439–467`；调用 `:524`、`:651` | `hasIllegalUriCharacters` 改为扫描原始 UTF8 bytes；每个 `%` 在 Foundation parse 前检查后续两位存在且均通过 ASCII hexValue，合法后前进三 byte。`bad%ZZ`、`%2`、尾 `%` 直接回退，不再让 URLComponents 修复后通过。 |
| F2 空 port 原 authority | `:527–533`、`:654–660` | 从 scheme 后至首个 `/` 取得 rawAuthority，在 URLComponents 前拒绝空 authority、`@`、`:`。保留后续 parsed scheme / host / user / port / query / fragment guards。 |
| F3 opaque ID byte identity | `:599–617` | seen set 为 `Set<[UInt8]>`；以 `Array(id.utf8)` contains / insert。不同 Unicode byte identity 不再被 String canonical equivalence 合并；返回的 identity String / target 保持原值。 |

### 在该修复范围内的兼容性检查

- raw `%HH` 扫描只由 current `duoyi://` parser 调用，legacy anniversary ID 分支 `:562–579` 仍直接 encode opaque ID。因此 legacy `bad%ZZ` 可以成为真实 ID，而 current URI `duoyi://anniversary/bad%ZZ` 会拒绝；没有误套规则。
- ASCII hex 检查不会拒绝合法 `%25`、`%2F`、`%2B` 与中文 / emoji escaped UTF8；strict decoder `:470–501` 继续只 decode 一次，literal `+`不变、非法 UTF8仍拒绝。
- authority切片截止首个raw `/`，不会因path中的 `@` / `:` 错判userinfo / port；`record:42` opaque legacy也不被新authority规则影响。encoded path punctuation仍由原strict decode与shape规则处理。
- byte set只改变去重key，没有改变union输入順序、first-wins、sourceKey/text/target绑定、placeholder判定或 helper public signature。同一 decoded exact ID 的多种合法encoding仍会形成同一byte key；不同字节 ID 保留。

**本次限定源码复审结论：F1 / F2 / F3 均已修复，无剩余 must-fix。**这不是整个widget batch的运行/平台验收结论。主审正在运行的Foundation display checks与pure Kotlin checks由主审收集；本审没有运行或宣布其结果。第5节的实际WidgetKit height/font/layout与点击区域设备验收继续保留，Android immutable snapshot gap仍由另批持有。

已完成本次指定报告更新并停止生产读取。

STOP。
