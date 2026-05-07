# 多仪 部署与发布

## 总体架构

- **APK / Web 客户端**：编译时把服务器地址写死，运行期不可修改；
- **后端 (FastAPI)**：单一 SQLite，自持全部数据；
- **管理员**：登录后进入"管理员后台"远程配置 AI / 云端备份 / 公告 / 用户；
- **普通用户**：注册登录后直接用，看不到任何技术细节。

```
┌─────────────────────┐         ┌────────────────────┐
│  APK / Web 客户端   │         │  FastAPI (SQLite)  │
│  DUOYI_SERVER_URL   │────────▶│  /api/auth         │
│   已锁死，不可改    │         │  /api/sync         │
│                     │         │  /api/ai/chat (代理)│
└─────────────────────┘         │  /api/admin/*      │
         ▲                      └────────────────────┘
         │  管理员登录同一个 APP 进入"管理员后台"
         │  → 改 AI key / 开关云备份 / 维护模式 …
```

## 1. 后端

```bash
cd backend
pip install -r requirements.txt

# 环境变量(首次启动生效；后续通过管理员后台随时改)
#   ADMIN_BOOTSTRAP_USER=admin
#   ADMIN_BOOTSTRAP_PASSWORD=admin123
#   INVITE_CODE_REQUIRED=false
#   AI_BASE_URL=https://api.openai.com
#   AI_API_KEY=sk-…
#   AI_MODEL=gpt-4o-mini
#   CORS_ORIGINS=https://duoyi.example.com

uvicorn main:app --host 0.0.0.0 --port 8000
```

首次启动会自动创建 `fingertip_time.db` 与一个 admin 账号。

### 管理员登录后可做什么

进入 "我的 → 管理员后台" → 8 个 Tab：

| Tab | 内容 |
|---|---|
| 概览 | 用户 / 反馈 / 公告 / 邀请码 KPI + 7 日注册趋势 + 当前连接的服务器地址提示 |
| 全站设置 | 允许注册 · 是否需要邀请码 · 维护模式 + 维护文案 |
| **AI 配置** | 启用开关 · Base URL · API Key · 模型 · 每日限额 · **一键测试连接** |
| **云端备份** | 启用开关 · 单用户最大 payload · 最小自动同步间隔 · 保留天数 + **按用户看备份大小 / 清空某用户云端数据** |
| 用户 | 搜索 / 提权 / 禁用 / 重置密码 / 删除 |
| 公告 | 发布 · 编辑 · 草稿 / 上下架 |
| 反馈 | 过滤状态 · 回复 · 删除 |
| 邀请码 | 批量生成 · 复制 · 删除未使用 |

API Key / 其他敏感字段都只驻留后端 SQLite，读出时返回掩码 (`sk-***xyz`)；前端永远拿不到明文。

## 2. APK 客户端

**服务器地址必须在编译时决定**：

```bash
# 推荐：--dart-define 覆盖 (不改源码)
flutter build apk --release \
  --dart-define=DUOYI_SERVER_URL=https://duoyi.example.com

# 或者：直接修改 lib/core/app_config.dart 里的 defaultServerUrl
```

构建产物里这个地址已被常量替换，普通用户无法修改。

## 3. Web 客户端

### 独立域名部署

```bash
flutter build web --release \
  --dart-define=DUOYI_SERVER_URL=https://duoyi-api.example.com
```

把 `build/web/` 放到任何静态 host；注意后端 `CORS_ORIGINS` 要带上前端域。

### 同域反代部署 (推荐)

```bash
# 留空: 走相对路径
flutter build web --release --dart-define=DUOYI_SERVER_URL=
```

nginx 配置：

```nginx
server {
  listen 443 ssl;
  server_name duoyi.example.com;

  root /var/www/duoyi/web;
  index index.html;

  location /api/ {
    proxy_pass http://127.0.0.1:8000;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $remote_addr;
  }
  location / {
    try_files $uri $uri/ /index.html;
  }
}
```

同域时 CORS 不用配，前端直接打 `/api/…`。

## 4. 普通用户视角

登录 → 用。完。

他们在 APP 里**看不到**任何：
- 服务器地址
- AI Key / Base URL / 模型
- 云同步地址 / Token

他们可以使用：
- 所有功能模块 (待办/习惯/日历/专注/笔记/日记/纪念日/目标/课程表/黄历/倒数日)
- 每天登录后在后台自动同步(管理员未关闭的话)
- "我的 → 立即同步" 一键按钮
- 当 AI 可用时，任务拆解 + 每周 AI 回顾

如果管理员关掉云备份或关掉 AI，对应入口就不会显示，用户也不会看到"未配置"之类的提示。

## 5. 数据迁移与安全

- `sync_data` 表启动时自动 `ALTER TABLE ADD COLUMN` 补齐字段；
- 最后一位活跃管理员不能被降权/禁用/删除(服务端兜底)；
- 禁用用户或重置密码会立刻吊销其 token；
- 同步 payload 默认限制 2048 KB，防止恶意用户塞满磁盘；
- AI 调用按 `user_id + 当天` 计数，超限 HTTP 429；
- API Key 读接口只返回掩码，且写入时如传入包含 `***` 的旧值会被视为"不修改"。
