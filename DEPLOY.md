# 多仪 部署与发布

## 1. 后端

### 启动

```bash
cd backend
pip install -r requirements.txt
# 可选环境变量：
#   ADMIN_BOOTSTRAP_USER=admin
#   ADMIN_BOOTSTRAP_PASSWORD=admin123
#   INVITE_CODE_REQUIRED=false
#   AI_BASE_URL=https://api.openai.com
#   AI_API_KEY=sk-...           (管理员首次登录后也可在后台改)
#   AI_MODEL=gpt-4o-mini
#   CORS_ORIGINS=https://duoyi.example.com,https://app.duoyi.example.com
uvicorn main:app --host 0.0.0.0 --port 8000
```

首次启动会自动创建 `fingertip_time.db`，并根据环境变量创建一个 admin 账号。

### 管理员初次使用

1. 用 `ADMIN_BOOTSTRAP_USER / ADMIN_BOOTSTRAP_PASSWORD` 登录任一客户端；
2. 进入"我的 → 管理员后台"；
3. 在"AI 配置"里填写上游 Base URL、API Key、模型、每用户每日限额；
4. 在"全站设置"里决定是否开启注册 / 邀请码；
5. 在"邀请码"里批量生成邀请码。

API Key 只在服务端保存，**永远不会下发给客户端**。

## 2. Android 客户端

构建时把服务器地址写死：

```bash
flutter build apk --release \
  --dart-define=DUOYI_SERVER_URL=https://duoyi.example.com
```

或者把 `lib/core/app_config.dart` 里的 `defaultServerUrl` 直接改掉后再 build。

普通用户登录时**看不到服务器地址**；管理员登录后可在"管理员后台 → 全站设置"里临时覆盖（保存到本地 SharedPreferences）。

## 3. Web 客户端

### 构建

```bash
flutter build web --release \
  --dart-define=DUOYI_SERVER_URL=https://duoyi.example.com
```

输出在 `build/web/`，用任何静态 host（nginx / cloudflare pages / vercel）托管即可。

### CORS

后端要把前端域加进 `CORS_ORIGINS`。例如：

```
CORS_ORIGINS=https://duoyi-web.example.com
```

同源部署（后端 + 前端同一域名）不用配。

### 同域反代（推荐）

用 nginx 把 `/` 指到 `build/web`，`/api` 指到 `uvicorn`：

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

同域后前端不需要 `DUOYI_SERVER_URL`（留空即可走相对路径，需要把 `defaultServerUrl` 改为空字符串，`ApiClient` 会自动用相对路径——见 TODO）。

## 4. 数据迁移

`sync_data` 表启动时会自动 `ALTER TABLE ADD COLUMN` 补齐所有新字段；无需手动操作。想彻底重置就删 `backend/fingertip_time.db`。

## 5. 安全要点

- 上游 AI Key 仅在数据库内，读接口返回掩码；
- 管理员接口全部 `Depends(_require_admin)`；
- 最后一位活跃管理员不能被降权/禁用/删除（服务端兜底）；
- 禁用用户 / 改密会立即把其 token 从内存中移除。
