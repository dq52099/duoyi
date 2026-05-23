# 多仪 (Duoyi)

一款跨平台效率工具，整合 **待办四象限 / 习惯打卡热力图 / 番茄专注 / 日历 / 个人中心** 五大模块，支持 8 套主题切换（含背景图）、AI 助手、云同步、Android 小米桌面小组件。

> Flutter 客户端 + 自托管 FastAPI 后端，开源、可自部署。

## 功能特性

### 核心模块
- **待办** — 四象限矩阵（重要/紧急），清单分组，子任务，AI 一句话拆解
- **习惯** — 每日打卡，连续天数，GitHub 风格热力图，本周日丸概览
- **日历** — 月/周/日三视图，聚合所有事件，作为主枢纽
- **专注** — 圆环计时，番茄/短休/长休自动切换，白噪音开关，会话历史
- **我的** — 综合评分、AI 周报、公告、反馈、检查更新、主题、云同步

### 主题
8 套可切换主题（含 7 张背景图）：
- **多仪**（默认 / 暖橙）
- **从零开始**（RE0）/ **原神** / **星穹铁道** / **鸣潮** / **绝区零** / **燕云十六声** / **希卡之石**

每套主题不仅切换颜色，还会切换背景图、文案（待办→咒文/委托/符文…）、问候语和通知话术。

### 平台特性
- **桌面**：Linux 系统托盘 + DBus 桌面通知
- **Android**：MIUI/通用桌面小组件（待办/习惯/番茄三栏，深链 `duoyi://`）
- **多端云同步**：Python FastAPI 后端，按时间戳合并

### AI 助手
- 兼容 OpenAI `chat/completions` 协议，可对接任意网关（默认指向 boxying-image-gateway）
- AI 任务拆解：新建待办时一键将一句话变成结构化子任务
- AI 每周回顾：基于本周完成数据生成总结与建议

### 用户系统
- 注册/登录/JWT，邀请码可选（环境变量 `INVITE_CODE_REQUIRED` 默认关闭）
- 公告系统、反馈与许愿（用户提交，管理员回复）
- 应用内自动检查 GitHub Release 更新

## 项目结构

```
lib/
├── core/                  # AppBrand / BrandStrings 主题系统
├── models/                # Todo / Habit / Pomodoro / CalendarEvent / UserProfile
├── providers/             # Provider 状态管理
├── services/              # ApiClient / AiService / AppUpdateService / 桌面集成
├── screens/               # 5 个 Tab + 详情页 + 登录/反馈/公告/AI 设置
└── widgets/               # 复用 widget (eisenhower / heatmap / brand_background ...)

backend/                   # FastAPI 后端 (auth / sync / announcements / feedback)
android/app/src/main/      # MIUI 桌面小组件 (Kotlin AppWidgetProvider + XML)
linux/                     # Linux 桌面入口 + .desktop
assets/backgrounds/        # 7 张主题背景图
```

## 快速开始

### 客户端
```bash
flutter pub get
flutter run -d linux            # Linux 桌面
flutter build apk --release     # Android (需安装 Android SDK)
```

### 后端
```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
# 默认管理员：admin / admin123 (env: ADMIN_BOOTSTRAP_USER / ADMIN_BOOTSTRAP_PASSWORD)
# 启用邀请码：export INVITE_CODE_REQUIRED=true
```

## 发布

### GitHub Actions

`.github/workflows/build-apk.yml` 定义了 4 个作业：

| 触发 | 作业 | 产物 |
|---|---|---|
| 每次 push / PR | `analyze` | `flutter analyze` + `dart format` + 可选 `flutter test` |
| 每次 push / PR | `android` | 通用 APK + 分 ABI APK (armeabi-v7a / arm64-v8a / x86_64) |
| 推 tag / 手动触发指定 | `web` | `duoyi-web-*.tar.gz` 可直接解压到 nginx |
| 推 `v*` tag | `release` | 汇总 APK + AAB + web 打包，自动建 GitHub Release |

#### 需要的仓库 Secrets
- `DUOYI_KEYSTORE_BASE64` — keystore 文件的 base64，用于正式签名。**不设置时发布构建会直接失败，不会降级为 debug 签名**。
- `DUOYI_KEYSTORE_PASSWORD` / `DUOYI_KEY_ALIAS` / `DUOYI_KEY_PASSWORD`

生成 keystore 并编码：

```bash
keytool -genkey -v -keystore duoyi-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias duoyi
base64 -w0 duoyi-release.jks | pbcopy   # 或 | xclip -selection clipboard
```

#### 可选的仓库 Variables
- `DUOYI_SERVER_URL` — 构建期注入的后端地址，不设置时回退到 `lib/core/app_config.dart` 的 `defaultServerUrl`。
- 手动触发时在 `workflow_dispatch` 表单里填 `server_url` 可临时覆盖。

#### 发版

```bash
git tag v1.0.3
git push origin v1.0.3
```

Release 页面会自动生成并附带：
- `duoyi-v1.0.3.apk`（通用）
- `duoyi-v1.0.3-arm64-v8a.apk` / `-armeabi-v7a.apk` / `-x86_64.apk`
- `duoyi-v1.0.3.aab`（上架 Play Store 用）
- `duoyi-web-v1.0.3.tar.gz`

App 内 "我的 → 检查更新" 会拉取最新 Release。

## 许可

MIT
