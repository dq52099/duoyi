# 持续目标核对（2026-10-06）

目标：重点完善小组件，默认 iOS 风格，全局国际化，以及“我的”和设置的功能、样式与操作流畅度。

## 当前证据与缺口

- **小组件**：`c6b4f04` 改进目录、预览、动作与空状态；57 个定向用例通过，Kotlin/资源编译通过。Android Launcher 和 iOS WidgetKit 仍缺真机证据，不能据此关闭功能完整性要求。
- **默认 iOS 风格**：`lib/core/app_brand.dart` 已有 `_SharedFeel.ios` 与 `AppSurfaceStyle.ios`，`ThemeProvider` 默认选择 `AppBrands.defaultBrand`。但 `WidgetScreen` 的预览和控制卡仍有大量显式 8/12 圆角，应按默认主题的设计参数核对，而不能只凭主题名称称全部统一。
- **全局国际化**：未完成。`lib/screens/widget_screen.dart` 中目录类别、十类名称与说明、添加/检测提示、显示模式和示例均有中文字符串；`WidgetDisplayMode` 的 label/description 仍是固定字符串。日历和专注的本轮状态文案已支持中英，但页面其他操作与后台仍有固定中文。全局检查必须包括弹窗、错误、工具提示、空状态、动态统计和原生小组件。
- **我的/设置**：本轮已改账号状态、无数据与真实零值、头像/密码错误、窄屏卡片；仍需覆盖语言切换后整个设置流程、通知权限入口、备份导入/导出、主题切换与退出登录。用户页截图不能代替这些流程的验收。
- **流畅度**：已保持细粒度 provider 订阅、列表按需构建并补异步状态保护；没有当前版本的真实设备帧耗时、冷启动和滑动 trace，不能声称性能目标已全部达成。

## 后续实施边界

1. **优先小组件**：`lib/screens/widget_screen.dart`、`lib/core/i18n.dart`、Android/WidgetKit 对应渲染资源；按主题参数统一默认样式，补中英文目录/示例/操作反馈和语言切换刷新测试。
2. **我的与设置流程**：`mine_screen.dart`、`profile_screen.dart`、`lock_settings_screen.dart`、通知/偏好/主题设置相关界面；补双语交互和窄屏状态验收，保留账号切换保护。
3. **全局范围与运行证据**：逐路由清点其余中文字符串，覆盖中英和放大字体；已有 `docs/goal-requirement-matrix.md` 未单独列全局国际化与默认 iOS 风格，需补明确要求与对应证据。设备可用后采集 Launcher、WidgetKit 和性能证据。

本文件是当前源码的缺口清单，不是完成证明。本轮用户页/后台回归、构建和部署结果另记；持续目标保持进行中。
