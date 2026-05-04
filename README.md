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

GitHub Actions 在 `.github/workflows/build-apk.yml`：
- `main` 推送 → 出 `duoyi-apk` artifact
- 推送 `v*` tag → 自动创建 GitHub Release，带 APK

```bash
git tag v1.0.0
git push origin v1.0.0
```

App 内 "我的 → 检查更新" 会拉取最新 Release。

## 许可

MIT
