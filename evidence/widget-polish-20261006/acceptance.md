# 多仪 1.1.44 小组件与界面验收

## 本次改动

- Android 原生启动图：沿用多仪图标，提供浅深背景、透明圆角和 Android 12 安全画布。
- 手机后台：局部收敛标题、正文与控件字重，并适配窄屏指标卡。
- App 待办、习惯：统一空状态宽度与最小高度；今日和逾期统计支持筛选；习惯周卡支持查看过去或今日明细，未来日期禁用。
- Android 桌面：所有小组件提供刷新入口；尺寸不足时减少次要内容；待办完成、习惯打卡后立即刷新。
- 专注桌面卡：正计时、倒计时、暂停、结束分别展示。无精确闹钟权限时显示预计结束时间，避免负数倒计时。
- 数据边界：发布期间隐藏未完成快照，跨日/时区提示刷新，账号切换拒绝旧动作。绝对时间专注会话可跨午夜继续。

## GitHub 整合与小组件重点

本轮拉取 `origin/main` 到 `0921b03`，整合 6 个新增提交；本地改动先保存为 `68363d5`，合并提交为 `0e8c4ed`，主仓库 `main` 已快进到该提交。尚未推送 GitHub。
新提交包含液态玻璃主题、品牌文案国际化、备份覆盖语义和番茄运行恢复。
整合时补上运行快照账号清理键、恢复与写入代次检查、清理等待和失败重试；云同步只加载持久数据，避免重复恢复当前计时相位。
App 与桌面计时共用绝对时间锚点；稳定会话 ID 防止残留快照在冷启动后重复结算。

## 已取得证据

- GitHub 整合后后端隔离回归：154 项通过，包含液态玻璃主题价格契约，日志 `upstream-backend-isolated-regression.log`。
- 整合后小组件核心回归：88 项通过，日志 `upstream-widget-core-regression-clean.log`，涵盖专注快照、恢复竞态、失败重试、稳定会话去重、绝对时间锚点、账号清理、原生资源和今日筛选。
- 44 个受影响 Flutter 测试文件分批通过，共 521 个不同用例。43 个文件的 511 项通过；交互截图文件修正测试视口后 10 项全部通过。核心 88 项属于这些回归，不另行叠加计数。
- 首轮 44 文件运行有 519 项通过和 2 项失败。失败源于 `setSurfaceSize` 未同步改变 `MediaQuery` 宽度，测试误入桌面布局；改用 `tester.view.physicalSize` 和 `devicePixelRatio` 并增加实际视口断言。日志分别为 `upstream-affected-flutter-isolated.log`、`widget-polish-final-viewport.log`。未取得单次 44 文件全绿记录。
- 启动资源：五档密度尺寸与四角透明度检查通过；浅深预览已人工查看。
- 空态：320、390 宽度与 1.0、1.3 字体尺度的同尺寸断言和截图；手机后台覆盖 1.3、1.6 字体尺度，习惯明细覆盖 320、390 宽度。
- 最终 22 个相关 Dart 文件分析无问题，日志 `upstream-final-analyze-all.log`；视口 fixture 更新后再次分析无问题，日志 `widget-polish-final-viewport-analyze.log`。
- 合并前 Flutter 全量检查中断时有 1,387 项通过、3 个失败标记，未取得完整全量结果。缺少导入、旧版本断言已修；设备证据脚本的 30 秒超时用例在隔离回归中已通过。此次交付不声称全仓库 Flutter 全量通过。

### 截图证据

截图位于 `../screenshots/widget-polish-20261006/`。已人工查看启动资源、`widget-preview-todo-calendar.png`、`empty-cards-320-1.3.png`、`admin-overview-320-1.6.png`、`habit-day-detail-320.png`：预览数字正常，空态尺寸一致，窄屏后台无溢出，习惯明细可读。长指标标签按设计省略。

这些是资源预览与 Flutter 合成测试截图，不是 Launcher 或真机运行证据。

## 构建与部署

- Web `1.1.44+140010` 构建成功并部署到 `/home/ubuntu/www/duoyi/`。构建副本的 `lib/`、`assets/`、`web/` 和依赖清单与合并工作树逐文件 hash 一致。
- 地址：<https://work.6688667.xyz/duoyi/>。本机及原域名的 `version.json` 返回 200 和新版本；规范地址匿名请求仍返回 401，保留既有认证边界。
- 已部署 `main.dart.js` 的 SHA256 为 `e1aef12799cb9774b8fb8c37c6ac8fca851a1ab58a6f4735ccd0311c9b33d9e4`；`flutter_bootstrap.js` 为 `951df4635310328c1b4fe0cbd6f43d1a57cc149e7a4688c41abf9d6c3cfb665e`。验证记录为 `web-delivery-verification.json`。
- 后端仅重启一次以加载新主题目录，服务恢复 `active/running`，健康检查 200；原生版本策略仍为 `1.1.43 / 140009`，记录为 `backend-delivery-verification.json`。
- 既有 APK 下载文件保持原 SHA256，未用调试构建替换正式下载。
- Android ARM64 debug 构建成功，真实退出码 0；包内版本为 `1.1.44 / 140010`，APK 签名验证通过，33 个小组件相关接收器均存在。APK 为 149,190,999 字节，SHA256 为 `d97440a2e7df637e59011d8681f8580ba6ee6c04961b605ec1991cf497d1094c`。记录为 `android-final-debug-isolated-status.json`、`android-apk-verification.json`。
- 调试包与既有 debug 下载的证书一致；这仅确认调试包之间的签名兼容性，不证明与正式安装包兼容。新包仅保留在私有产物目录，未替换公开下载或提高原生更新策略。

### 构建环境事件

`disk-safe-cleanup.service` 于 10:21:26–10:21:55 UTC 清理共享 Gradle 缓存及 `/tmp/flutter_tools.*`，造成缓存消失和 Flutter 临时目录错误。后续回归、Web 与 Android 构建分别使用私有 `GRADLE_USER_HOME`、`TMPDIR` 和 `java.io.tmpdir` 避开清理范围，未修改清理服务或其他项目。更早的 exit 143 原因未证实，中断记录不计为通过。

## 待真机验收

当前主机无可用 Android/iOS 设备，未取得桌面运行证据。

- [ ] Android 11 与 12+ 冷启动、浅深主题切换，启动图正常消失。
- [ ] MIUI/HyperOS 与至少一个其他 Launcher：添加、缩放、删除、升级、重启后恢复。
- [ ] 待办完成与多次数习惯单次点击只执行一次，刷新可重试。
- [ ] 运行/暂停/恢复/到期、正计时超过一小时，桌面时间不截断。
- [ ] 有/无精确闹钟权限、省电/锁屏下的计时到期刷新。
- [ ] 跨午夜、改时间/时区后旧今日统计不误报；持续专注保持正确。
- [ ] 切换账号、退出、清理失败时旧小组件动作不能写入新账号。

## Android 正式发布前置条件

现有正式 keystore 的密码/alias 配置未提供，`android/key.properties` 和签名环境变量缺失。
正式新 APK 尚未发布；debug 编译证据不能替代正式签名或真机验收。

## 发布保护

网页版与原生 APK 分别交付。正式 1.1.44 APK 发布前，后端原生更新策略保持 1.1.43 / 140009。
主机已添加 `/etc/systemd/system/duoyi-backend.service.d/95-native-version-pin.conf`，设置 `APP_CURRENT_VERSION` 和 `APP_CURRENT_VERSION_CODE`；已随本轮后端部署加载并核验生效。
正式签名 APK 发布并确认下载地址可用后，再更新或移除此版本固定配置。

本次私有构建和回归日志保存在主机 `duoyi_deploy_backups/android-startup-admin-20261006T073922Z/`，不随网页公开。
