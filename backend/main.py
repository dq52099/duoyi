from fastapi import FastAPI, HTTPException, Depends, Header, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
import sqlite3
import hashlib
import secrets
import json
import os
from datetime import datetime, timezone

app = FastAPI(title="指尖时光 Sync API", version="3.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "*").split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_PATH = os.path.join(os.path.dirname(__file__), "fingertip_time.db")

# Feature flags (loaded from DB after init)
ADMIN_BOOTSTRAP_USER = os.getenv("ADMIN_BOOTSTRAP_USER", "admin")
ADMIN_BOOTSTRAP_PASSWORD = os.getenv("ADMIN_BOOTSTRAP_PASSWORD", "admin123")

TOKENS: dict[str, str] = {}  # user_id -> token


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db():
    conn = get_db()
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            avatar TEXT DEFAULT '',
            is_admin INTEGER DEFAULT 0,
            is_disabled INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now')),
            last_login_at TEXT
        );
        CREATE TABLE IF NOT EXISTS sync_data (
            user_id TEXT PRIMARY KEY,
            todos TEXT DEFAULT '[]',
            habits TEXT DEFAULT '[]',
            pomodoro_sessions TEXT DEFAULT '[]',
            pomodoro_config TEXT DEFAULT '{}',
            user_profile TEXT DEFAULT '{}',
            notes TEXT DEFAULT '[]',
            countdowns TEXT DEFAULT '[]',
            anniversaries TEXT DEFAULT '[]',
            diaries TEXT DEFAULT '[]',
            goals TEXT DEFAULT '[]',
            courses TEXT DEFAULT '[]',
            course_settings TEXT DEFAULT '{}',
            updated_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS invite_codes (
            code TEXT PRIMARY KEY,
            used_by TEXT,
            used_at TEXT,
            created_at TEXT DEFAULT (datetime('now')),
            note TEXT DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS announcements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            level TEXT DEFAULT 'info',
            published INTEGER DEFAULT 1,
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS feedback (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            category TEXT DEFAULT 'feature',
            content TEXT NOT NULL,
            status TEXT DEFAULT 'open',
            admin_reply TEXT DEFAULT '',
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS audit_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            actor_id TEXT,
            actor_name TEXT,
            action TEXT NOT NULL,
            target TEXT DEFAULT '',
            detail TEXT DEFAULT '',
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS ai_usage (
            user_id TEXT NOT NULL,
            day TEXT NOT NULL,
            calls INTEGER DEFAULT 0,
            PRIMARY KEY(user_id, day)
        );
        """
    )

    # Schema migrations
    for table, col, default in [
        ("sync_data", "pomodoro_sessions", "'[]'"),
        ("sync_data", "pomodoro_config", "'{}'"),
        ("sync_data", "user_profile", "'{}'"),
        ("sync_data", "notes", "'[]'"),
        ("sync_data", "countdowns", "'[]'"),
        ("sync_data", "anniversaries", "'[]'"),
        ("sync_data", "diaries", "'[]'"),
        ("sync_data", "goals", "'[]'"),
        ("sync_data", "courses", "'[]'"),
        ("sync_data", "course_settings", "'{}'"),
        ("users", "is_disabled", "0"),
        ("users", "last_login_at", "NULL"),
        ("invite_codes", "note", "''"),
        ("announcements", "updated_at", "datetime('now')"),
    ]:
        cur = conn.execute(f"PRAGMA table_info({table})")
        cols = {r["name"] for r in cur.fetchall()}
        if col not in cols:
            conn.execute(
                f"ALTER TABLE {table} ADD COLUMN {col} {'INTEGER' if isinstance(default, str) and default.isdigit() else 'TEXT'} DEFAULT {default}"
            )

    # Default settings
    default_settings = {
        "invite_code_required": os.getenv(
            "INVITE_CODE_REQUIRED", "false"
        ).lower() in {"1", "true", "yes"},
        "registration_enabled": True,
        "maintenance_mode": False,
        "maintenance_message": "",
        # AI 由管理员统一在服务端配置，用户端仅调用 /api/ai/chat 代理
        "ai_enabled": False,
        "ai_base_url": os.getenv("AI_BASE_URL", "https://api.openai.com"),
        "ai_api_key": os.getenv("AI_API_KEY", ""),
        "ai_model": os.getenv("AI_MODEL", "gpt-4o-mini"),
        "ai_daily_quota": 100,  # 每用户每日调用上限(0=不限)
    }
    for k, v in default_settings.items():
        conn.execute(
            "INSERT OR IGNORE INTO settings(key, value) VALUES(?, ?)",
            (k, json.dumps(v)),
        )

    # Bootstrap admin
    cur = conn.execute(
        "SELECT 1 FROM users WHERE username=?", (ADMIN_BOOTSTRAP_USER,)
    ).fetchone()
    if cur is None:
        admin_id = secrets.token_hex(16)
        conn.execute(
            "INSERT INTO users(id, username, password_hash, is_admin) VALUES(?,?,?,1)",
            (admin_id, ADMIN_BOOTSTRAP_USER, _hash_password(ADMIN_BOOTSTRAP_PASSWORD)),
        )
        conn.execute("INSERT INTO sync_data(user_id) VALUES(?)", (admin_id,))
    conn.commit()
    conn.close()


def _hash_password(password: str) -> str:
    salt = "fingertip_time_2026"
    return hashlib.sha256((salt + password).encode()).hexdigest()


def _setting_get(db, key: str, default=None):
    row = db.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
    if row is None:
        return default
    try:
        return json.loads(row["value"])
    except Exception:
        return row["value"]


def _setting_set(db, key: str, value) -> None:
    db.execute(
        "INSERT INTO settings(key, value) VALUES(?, ?) "
        "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        (key, json.dumps(value)),
    )


def _audit(db, actor_id: Optional[str], actor_name: Optional[str], action: str,
           target: str = "", detail: str = "") -> None:
    db.execute(
        "INSERT INTO audit_log(actor_id, actor_name, action, target, detail) VALUES(?,?,?,?,?)",
        (actor_id, actor_name, action, target, detail),
    )


def _verify_token(authorization: Optional[str] = Header(None)) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing token")
    token = authorization[7:]
    user_id = next((uid for uid, t in TOKENS.items() if t == token), None)
    if user_id is None:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return user_id


def _require_admin(user_id: str = Depends(_verify_token)) -> str:
    db = get_db()
    try:
        row = db.execute(
            "SELECT is_admin, is_disabled, username FROM users WHERE id=?", (user_id,)
        ).fetchone()
        if row is None or not row["is_admin"]:
            raise HTTPException(status_code=403, detail="Admin only")
        if row["is_disabled"]:
            raise HTTPException(status_code=403, detail="Account disabled")
        return user_id
    finally:
        db.close()


def _get_username(db, user_id: str) -> str:
    row = db.execute("SELECT username FROM users WHERE id=?", (user_id,)).fetchone()
    return row["username"] if row else "?"


init_db()


# ---- Schemas ----


class RegisterRequest(BaseModel):
    username: str
    password: str
    invite_code: Optional[str] = None


class LoginRequest(BaseModel):
    username: str
    password: str


class SyncRequest(BaseModel):
    todos: list = []
    habits: list = []
    pomodoro_sessions: list = []
    pomodoro_config: dict = {}
    user_profile: dict = {}
    # —— 对齐指尖时光的新数据类型 ——
    notes: list = []
    countdowns: list = []
    anniversaries: list = []
    diaries: list = []
    goals: list = []
    courses: list = []
    course_settings: dict = {}


class FeedbackCreate(BaseModel):
    category: str = "feature"
    content: str


class FeedbackReply(BaseModel):
    feedback_id: int
    reply: str
    status: str = "resolved"


class AnnouncementCreate(BaseModel):
    title: str
    body: str
    level: str = "info"
    published: bool = True


class AnnouncementUpdate(BaseModel):
    title: Optional[str] = None
    body: Optional[str] = None
    level: Optional[str] = None
    published: Optional[bool] = None


class InviteCodeCreate(BaseModel):
    count: int = 1
    note: Optional[str] = ""


class UserUpdate(BaseModel):
    is_admin: Optional[bool] = None
    is_disabled: Optional[bool] = None
    new_password: Optional[str] = None


class SettingsUpdate(BaseModel):
    invite_code_required: Optional[bool] = None
    registration_enabled: Optional[bool] = None
    maintenance_mode: Optional[bool] = None
    maintenance_message: Optional[str] = None
    # AI 相关(仅管理员可改)
    ai_enabled: Optional[bool] = None
    ai_base_url: Optional[str] = None
    ai_api_key: Optional[str] = None
    ai_model: Optional[str] = None
    ai_daily_quota: Optional[int] = None


class AiChatRequest(BaseModel):
    system: str = ""
    user: str
    temperature: float = 0.4
    max_tokens: int = 512


# ---- Public ----


@app.get("/api/health")
def health():
    db = get_db()
    try:
        return {
            "status": "ok",
            "version": "3.1.0",
            "invite_required": _setting_get(db, "invite_code_required", False),
            "maintenance": _setting_get(db, "maintenance_mode", False),
            "time": datetime.now(timezone.utc).isoformat(),
        }
    finally:
        db.close()


@app.get("/api/config")
def public_config():
    db = get_db()
    try:
        return {
            "invite_code_required": _setting_get(db, "invite_code_required", False),
            "registration_enabled": _setting_get(db, "registration_enabled", True),
            "maintenance_mode": _setting_get(db, "maintenance_mode", False),
            "maintenance_message": _setting_get(db, "maintenance_message", ""),
            "ai_enabled": bool(
                _setting_get(db, "ai_enabled", False)
                and str(_setting_get(db, "ai_api_key", "")).strip() != ""
            ),
            "ai_model": _setting_get(db, "ai_model", ""),
        }
    finally:
        db.close()


# ---- AI proxy ----


def _today_str():
    return datetime.now().strftime("%Y-%m-%d")


@app.post("/api/ai/chat")
def ai_chat(req: AiChatRequest, user_id: str = Depends(_verify_token)):
    import urllib.request
    import urllib.error

    db = get_db()
    try:
        if not _setting_get(db, "ai_enabled", False):
            raise HTTPException(status_code=503, detail="AI 功能未启用")
        api_key = str(_setting_get(db, "ai_api_key", "")).strip()
        if not api_key:
            raise HTTPException(status_code=503, detail="管理员尚未配置 AI API Key")

        # 配额限制
        quota = int(_setting_get(db, "ai_daily_quota", 0) or 0)
        if quota > 0:
            today = _today_str()
            row = db.execute(
                "SELECT calls FROM ai_usage WHERE user_id=? AND day=?",
                (user_id, today),
            ).fetchone()
            used = row["calls"] if row else 0
            if used >= quota:
                raise HTTPException(status_code=429, detail=f"今日 AI 额度已用尽 ({used}/{quota})")

        base_url = str(
            _setting_get(db, "ai_base_url", "https://api.openai.com")
        ).rstrip("/")
        model = str(_setting_get(db, "ai_model", "gpt-4o-mini"))

        messages = []
        if req.system:
            messages.append({"role": "system", "content": req.system})
        messages.append({"role": "user", "content": req.user})

        payload = json.dumps(
            {
                "model": model,
                "messages": messages,
                "temperature": req.temperature,
                "max_tokens": req.max_tokens,
            },
            ensure_ascii=False,
        ).encode("utf-8")

        upstream = urllib.request.Request(
            f"{base_url}/v1/chat/completions",
            data=payload,
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {api_key}",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(upstream, timeout=60) as resp:
                body = resp.read().decode("utf-8", errors="replace")
                data = json.loads(body)
        except urllib.error.HTTPError as e:
            text = e.read().decode("utf-8", errors="replace")
            raise HTTPException(status_code=e.code, detail=f"上游错误: {text[:200]}")
        except Exception as e:
            raise HTTPException(status_code=502, detail=f"上游不可达: {e}")

        # 记录额度
        today = _today_str()
        db.execute(
            "INSERT INTO ai_usage(user_id, day, calls) VALUES(?, ?, 1) "
            "ON CONFLICT(user_id, day) DO UPDATE SET calls=calls+1",
            (user_id, today),
        )
        db.commit()

        content = ""
        choices = data.get("choices") or []
        if choices:
            content = (choices[0].get("message") or {}).get("content", "")
        return {"content": content, "model": model}
    finally:
        db.close()


@app.get("/api/ai/usage")
def ai_usage(user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        today = _today_str()
        row = db.execute(
            "SELECT calls FROM ai_usage WHERE user_id=? AND day=?",
            (user_id, today),
        ).fetchone()
        quota = int(_setting_get(db, "ai_daily_quota", 0) or 0)
        return {
            "used": row["calls"] if row else 0,
            "quota": quota,
            "day": today,
        }
    finally:
        db.close()


# ---- Auth ----


@app.post("/api/auth/register")
def register(req: RegisterRequest):
    db = get_db()
    try:
        if not _setting_get(db, "registration_enabled", True):
            raise HTTPException(status_code=403, detail="Registration disabled")

        if _setting_get(db, "invite_code_required", False):
            code = (req.invite_code or "").strip()
            if not code:
                raise HTTPException(status_code=400, detail="Invite code required")
            row = db.execute(
                "SELECT used_by FROM invite_codes WHERE code=?", (code,)
            ).fetchone()
            if row is None:
                raise HTTPException(status_code=400, detail="Invalid invite code")
            if row["used_by"]:
                raise HTTPException(status_code=400, detail="Invite code already used")

        user_id = secrets.token_hex(16)
        try:
            db.execute(
                "INSERT INTO users(id, username, password_hash) VALUES(?,?,?)",
                (user_id, req.username, _hash_password(req.password)),
            )
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=409, detail="Username already exists")

        db.execute("INSERT INTO sync_data(user_id) VALUES(?)", (user_id,))

        if _setting_get(db, "invite_code_required", False):
            db.execute(
                "UPDATE invite_codes SET used_by=?, used_at=datetime('now') WHERE code=?",
                (user_id, (req.invite_code or "").strip()),
            )

        _audit(db, user_id, req.username, "register", user_id)
        db.commit()
        token = secrets.token_hex(32)
        TOKENS[user_id] = token
        return {
            "user_id": user_id,
            "token": token,
            "username": req.username,
            "is_admin": False,
        }
    finally:
        db.close()


@app.post("/api/auth/login")
def login(req: LoginRequest):
    db = get_db()
    try:
        row = db.execute(
            "SELECT id, password_hash, is_admin, is_disabled FROM users WHERE username=?",
            (req.username,),
        ).fetchone()
        if row is None or row["password_hash"] != _hash_password(req.password):
            raise HTTPException(status_code=401, detail="Invalid credentials")
        if row["is_disabled"]:
            raise HTTPException(status_code=403, detail="Account disabled")
        token = secrets.token_hex(32)
        TOKENS[row["id"]] = token
        db.execute(
            "UPDATE users SET last_login_at=datetime('now') WHERE id=?", (row["id"],)
        )
        _audit(db, row["id"], req.username, "login")
        db.commit()
        return {
            "user_id": row["id"],
            "token": token,
            "username": req.username,
            "is_admin": bool(row["is_admin"]),
        }
    finally:
        db.close()


@app.get("/api/auth/me")
def me(user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        row = db.execute(
            "SELECT id, username, avatar, is_admin, is_disabled, created_at, last_login_at "
            "FROM users WHERE id=?",
            (user_id,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="User not found")
        return {
            "user_id": row["id"],
            "username": row["username"],
            "avatar": row["avatar"] or "",
            "is_admin": bool(row["is_admin"]),
            "is_disabled": bool(row["is_disabled"]),
            "created_at": row["created_at"],
            "last_login_at": row["last_login_at"],
        }
    finally:
        db.close()


@app.post("/api/auth/logout")
def logout(user_id: str = Depends(_verify_token)):
    TOKENS.pop(user_id, None)
    return {"status": "ok"}


# ---- Sync ----


def _merge_by_timestamp(server: list, client: list) -> list:
    merged = {item.get("id"): item for item in server if isinstance(item, dict)}
    for item in client:
        if not isinstance(item, dict):
            continue
        item_id = item.get("id")
        if item_id is None:
            continue
        if item_id not in merged:
            merged[item_id] = item
        else:
            server_ts = merged[item_id].get("updatedAt", "")
            client_ts = item.get("updatedAt", "")
            if client_ts and client_ts > server_ts:
                merged[item_id] = item
    return list(merged.values())


def _merge_dict(server: dict, client: dict) -> dict:
    server_ts = server.get("updatedAt") if isinstance(server, dict) else None
    client_ts = client.get("updatedAt") if isinstance(client, dict) else None
    if client_ts and (not server_ts or client_ts > server_ts):
        return client
    return server or client


@app.post("/api/sync")
def sync(req: SyncRequest, user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        if _setting_get(db, "maintenance_mode", False):
            raise HTTPException(status_code=503, detail="Maintenance mode")

        row = db.execute(
            "SELECT todos, habits, pomodoro_sessions, pomodoro_config, user_profile, "
            "notes, countdowns, anniversaries, diaries, goals, courses, course_settings "
            "FROM sync_data WHERE user_id=?",
            (user_id,),
        ).fetchone()

        def _list(col):
            return json.loads(row[col]) if row and row[col] else []

        def _obj(col):
            return json.loads(row[col]) if row and row[col] else {}

        server_todos = _list("todos")
        server_habits = _list("habits")
        server_sessions = _list("pomodoro_sessions")
        server_config = _obj("pomodoro_config")
        server_profile = _obj("user_profile")
        server_notes = _list("notes")
        server_countdowns = _list("countdowns")
        server_annis = _list("anniversaries")
        server_diaries = _list("diaries")
        server_goals = _list("goals")
        server_courses = _list("courses")
        server_course_settings = _obj("course_settings")

        merged_todos = _merge_by_timestamp(server_todos, req.todos)
        merged_habits = _merge_by_timestamp(server_habits, req.habits)
        merged_sessions = _merge_by_timestamp(server_sessions, req.pomodoro_sessions)
        merged_config = _merge_dict(server_config, req.pomodoro_config)
        merged_profile = _merge_dict(server_profile, req.user_profile)
        merged_notes = _merge_by_timestamp(server_notes, req.notes)
        merged_countdowns = _merge_by_timestamp(server_countdowns, req.countdowns)
        merged_annis = _merge_by_timestamp(server_annis, req.anniversaries)
        merged_diaries = _merge_by_timestamp(server_diaries, req.diaries)
        merged_goals = _merge_by_timestamp(server_goals, req.goals)
        merged_courses = _merge_by_timestamp(server_courses, req.courses)
        merged_course_settings = _merge_dict(
            server_course_settings, req.course_settings
        )

        db.execute(
            """
            INSERT OR REPLACE INTO sync_data
            (user_id, todos, habits, pomodoro_sessions, pomodoro_config, user_profile,
             notes, countdowns, anniversaries, diaries, goals, courses, course_settings,
             updated_at)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,datetime('now'))
            """,
            (
                user_id,
                json.dumps(merged_todos, ensure_ascii=False),
                json.dumps(merged_habits, ensure_ascii=False),
                json.dumps(merged_sessions, ensure_ascii=False),
                json.dumps(merged_config, ensure_ascii=False),
                json.dumps(merged_profile, ensure_ascii=False),
                json.dumps(merged_notes, ensure_ascii=False),
                json.dumps(merged_countdowns, ensure_ascii=False),
                json.dumps(merged_annis, ensure_ascii=False),
                json.dumps(merged_diaries, ensure_ascii=False),
                json.dumps(merged_goals, ensure_ascii=False),
                json.dumps(merged_courses, ensure_ascii=False),
                json.dumps(merged_course_settings, ensure_ascii=False),
            ),
        )
        db.commit()

        return {
            "todos": merged_todos,
            "habits": merged_habits,
            "pomodoro_sessions": merged_sessions,
            "pomodoro_config": merged_config,
            "user_profile": merged_profile,
            "notes": merged_notes,
            "countdowns": merged_countdowns,
            "anniversaries": merged_annis,
            "diaries": merged_diaries,
            "goals": merged_goals,
            "courses": merged_courses,
            "course_settings": merged_course_settings,
        }
    finally:
        db.close()


# ---- Announcements (public) ----


@app.get("/api/announcements")
def list_announcements(limit: int = Query(20, ge=1, le=100)):
    db = get_db()
    try:
        rows = db.execute(
            "SELECT id, title, body, level, created_at FROM announcements "
            "WHERE published=1 ORDER BY id DESC LIMIT ?",
            (limit,),
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        db.close()


# ---- Feedback (user) ----


@app.post("/api/feedback")
def create_feedback(req: FeedbackCreate, user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        cur = db.execute(
            "INSERT INTO feedback(user_id, category, content) VALUES(?,?,?)",
            (user_id, req.category, req.content),
        )
        db.commit()
        return {"id": cur.lastrowid, "status": "open"}
    finally:
        db.close()


@app.get("/api/feedback/me")
def my_feedback(user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        rows = db.execute(
            "SELECT id, category, content, status, admin_reply, created_at, updated_at "
            "FROM feedback WHERE user_id=? ORDER BY id DESC",
            (user_id,),
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        db.close()


# =====================================================================
# ADMIN API
# =====================================================================


# ---- Dashboard / stats ----


@app.get("/api/admin/stats")
def admin_stats(_: str = Depends(_require_admin)):
    db = get_db()
    try:
        users_total = db.execute("SELECT COUNT(*) AS c FROM users").fetchone()["c"]
        users_admin = db.execute(
            "SELECT COUNT(*) AS c FROM users WHERE is_admin=1"
        ).fetchone()["c"]
        users_disabled = db.execute(
            "SELECT COUNT(*) AS c FROM users WHERE is_disabled=1"
        ).fetchone()["c"]
        users_today = db.execute(
            "SELECT COUNT(*) AS c FROM users WHERE date(created_at)=date('now')"
        ).fetchone()["c"]
        users_active_7d = db.execute(
            "SELECT COUNT(*) AS c FROM users WHERE last_login_at >= datetime('now','-7 days')"
        ).fetchone()["c"]

        fb_total = db.execute("SELECT COUNT(*) AS c FROM feedback").fetchone()["c"]
        fb_open = db.execute(
            "SELECT COUNT(*) AS c FROM feedback WHERE status='open'"
        ).fetchone()["c"]

        ann_total = db.execute(
            "SELECT COUNT(*) AS c FROM announcements"
        ).fetchone()["c"]
        ann_published = db.execute(
            "SELECT COUNT(*) AS c FROM announcements WHERE published=1"
        ).fetchone()["c"]

        invite_total = db.execute(
            "SELECT COUNT(*) AS c FROM invite_codes"
        ).fetchone()["c"]
        invite_used = db.execute(
            "SELECT COUNT(*) AS c FROM invite_codes WHERE used_by IS NOT NULL"
        ).fetchone()["c"]

        # 近 7 天注册
        rows = db.execute(
            "SELECT date(created_at) AS d, COUNT(*) AS c FROM users "
            "WHERE created_at >= datetime('now','-7 days') "
            "GROUP BY d ORDER BY d"
        ).fetchall()
        reg_series = [{"date": r["d"], "count": r["c"]} for r in rows]

        return {
            "users": {
                "total": users_total,
                "admin": users_admin,
                "disabled": users_disabled,
                "new_today": users_today,
                "active_7d": users_active_7d,
            },
            "feedback": {"total": fb_total, "open": fb_open},
            "announcements": {"total": ann_total, "published": ann_published},
            "invites": {"total": invite_total, "used": invite_used},
            "registration_series": reg_series,
            "tokens_online": len(TOKENS),
        }
    finally:
        db.close()


# ---- Settings ----


@app.get("/api/admin/settings")
def admin_get_settings(_: str = Depends(_require_admin)):
    db = get_db()
    try:
        rows = db.execute("SELECT key, value FROM settings").fetchall()
        result: dict = {}
        for r in rows:
            try:
                result[r["key"]] = json.loads(r["value"])
            except Exception:
                result[r["key"]] = r["value"]
        # 敏感信息脱敏：只返回是否已配置 + 掩码
        raw_key = str(result.get("ai_api_key") or "")
        result["ai_api_key_set"] = bool(raw_key)
        result["ai_api_key"] = (
            f"{raw_key[:3]}***{raw_key[-3:]}" if len(raw_key) > 6 else ("***" if raw_key else "")
        )
        return result
    finally:
        db.close()


@app.patch("/api/admin/settings")
def admin_update_settings(
    req: SettingsUpdate, actor: str = Depends(_require_admin)
):
    db = get_db()
    try:
        changed = {}
        for key, value in req.model_dump(exclude_none=True).items():
            _setting_set(db, key, value)
            changed[key] = value
        _audit(
            db,
            actor,
            _get_username(db, actor),
            "settings.update",
            detail=json.dumps(changed, ensure_ascii=False),
        )
        db.commit()
        return {"status": "ok", "changed": changed}
    finally:
        db.close()


# ---- Users ----


@app.get("/api/admin/users")
def admin_list_users(
    _: str = Depends(_require_admin),
    q: Optional[str] = None,
    limit: int = Query(100, ge=1, le=500),
    offset: int = 0,
):
    db = get_db()
    try:
        if q:
            rows = db.execute(
                "SELECT u.id, u.username, u.is_admin, u.is_disabled, u.created_at, u.last_login_at, "
                "(SELECT COUNT(*) FROM feedback WHERE user_id=u.id) AS fb_count "
                "FROM users u WHERE u.username LIKE ? ORDER BY u.created_at DESC LIMIT ? OFFSET ?",
                (f"%{q}%", limit, offset),
            ).fetchall()
        else:
            rows = db.execute(
                "SELECT u.id, u.username, u.is_admin, u.is_disabled, u.created_at, u.last_login_at, "
                "(SELECT COUNT(*) FROM feedback WHERE user_id=u.id) AS fb_count "
                "FROM users u ORDER BY u.created_at DESC LIMIT ? OFFSET ?",
                (limit, offset),
            ).fetchall()
        return [
            {
                "user_id": r["id"],
                "username": r["username"],
                "is_admin": bool(r["is_admin"]),
                "is_disabled": bool(r["is_disabled"]),
                "created_at": r["created_at"],
                "last_login_at": r["last_login_at"],
                "feedback_count": r["fb_count"],
                "online": any(uid == r["id"] for uid in TOKENS.keys()),
            }
            for r in rows
        ]
    finally:
        db.close()


@app.patch("/api/admin/users/{user_id}")
def admin_update_user(
    user_id: str, req: UserUpdate, actor: str = Depends(_require_admin)
):
    db = get_db()
    try:
        row = db.execute(
            "SELECT id, username, is_admin FROM users WHERE id=?", (user_id,)
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="User not found")

        # Safeguard: can't demote or disable the last admin
        if req.is_admin is False and row["is_admin"]:
            admins = db.execute(
                "SELECT COUNT(*) AS c FROM users WHERE is_admin=1"
            ).fetchone()["c"]
            if admins <= 1:
                raise HTTPException(
                    status_code=400, detail="Cannot demote the last admin"
                )
        if req.is_disabled is True and row["is_admin"]:
            admins = db.execute(
                "SELECT COUNT(*) AS c FROM users WHERE is_admin=1 AND is_disabled=0"
            ).fetchone()["c"]
            if admins <= 1:
                raise HTTPException(
                    status_code=400, detail="Cannot disable the last active admin"
                )

        if req.is_admin is not None:
            db.execute(
                "UPDATE users SET is_admin=? WHERE id=?",
                (1 if req.is_admin else 0, user_id),
            )
        if req.is_disabled is not None:
            db.execute(
                "UPDATE users SET is_disabled=? WHERE id=?",
                (1 if req.is_disabled else 0, user_id),
            )
            if req.is_disabled:
                TOKENS.pop(user_id, None)
        if req.new_password:
            db.execute(
                "UPDATE users SET password_hash=? WHERE id=?",
                (_hash_password(req.new_password), user_id),
            )
            TOKENS.pop(user_id, None)  # force re-login

        _audit(
            db,
            actor,
            _get_username(db, actor),
            "user.update",
            target=user_id,
            detail=json.dumps(req.model_dump(exclude_none=True)),
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


@app.delete("/api/admin/users/{user_id}")
def admin_delete_user(user_id: str, actor: str = Depends(_require_admin)):
    if user_id == actor:
        raise HTTPException(status_code=400, detail="Cannot delete yourself")
    db = get_db()
    try:
        row = db.execute(
            "SELECT username, is_admin FROM users WHERE id=?", (user_id,)
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="User not found")
        if row["is_admin"]:
            admins = db.execute(
                "SELECT COUNT(*) AS c FROM users WHERE is_admin=1"
            ).fetchone()["c"]
            if admins <= 1:
                raise HTTPException(
                    status_code=400, detail="Cannot delete the last admin"
                )
        db.execute("DELETE FROM users WHERE id=?", (user_id,))
        TOKENS.pop(user_id, None)
        _audit(
            db, actor, _get_username(db, actor),
            "user.delete", target=user_id, detail=row["username"]
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


# ---- Announcements (admin) ----


@app.get("/api/admin/announcements")
def admin_list_announcements(_: str = Depends(_require_admin)):
    db = get_db()
    try:
        rows = db.execute(
            "SELECT id, title, body, level, published, created_at, updated_at "
            "FROM announcements ORDER BY id DESC"
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        db.close()


@app.post("/api/admin/announcements")
def create_announcement(req: AnnouncementCreate, actor: str = Depends(_require_admin)):
    db = get_db()
    try:
        cur = db.execute(
            "INSERT INTO announcements(title, body, level, published) VALUES(?,?,?,?)",
            (req.title, req.body, req.level, 1 if req.published else 0),
        )
        _audit(
            db, actor, _get_username(db, actor),
            "announcement.create", target=str(cur.lastrowid), detail=req.title
        )
        db.commit()
        return {"id": cur.lastrowid}
    finally:
        db.close()


@app.patch("/api/admin/announcements/{ann_id}")
def update_announcement(
    ann_id: int, req: AnnouncementUpdate, actor: str = Depends(_require_admin)
):
    db = get_db()
    try:
        data = req.model_dump(exclude_none=True)
        if not data:
            return {"status": "ok"}
        fields = []
        values: list = []
        for k, v in data.items():
            if k == "published":
                fields.append("published=?")
                values.append(1 if v else 0)
            else:
                fields.append(f"{k}=?")
                values.append(v)
        fields.append("updated_at=datetime('now')")
        values.append(ann_id)
        db.execute(
            f"UPDATE announcements SET {', '.join(fields)} WHERE id=?", values
        )
        _audit(
            db, actor, _get_username(db, actor),
            "announcement.update", target=str(ann_id),
            detail=json.dumps(data, ensure_ascii=False)
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


@app.delete("/api/admin/announcements/{ann_id}")
def delete_announcement(ann_id: int, actor: str = Depends(_require_admin)):
    db = get_db()
    try:
        db.execute("DELETE FROM announcements WHERE id=?", (ann_id,))
        _audit(
            db, actor, _get_username(db, actor),
            "announcement.delete", target=str(ann_id)
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


# ---- Feedback (admin) ----


@app.get("/api/admin/feedback")
def list_all_feedback(_: str = Depends(_require_admin), status: Optional[str] = None):
    db = get_db()
    try:
        if status:
            rows = db.execute(
                "SELECT f.*, u.username FROM feedback f JOIN users u ON u.id=f.user_id "
                "WHERE f.status=? ORDER BY f.id DESC",
                (status,),
            ).fetchall()
        else:
            rows = db.execute(
                "SELECT f.*, u.username FROM feedback f JOIN users u ON u.id=f.user_id "
                "ORDER BY f.id DESC"
            ).fetchall()
        return [dict(r) for r in rows]
    finally:
        db.close()


@app.post("/api/admin/feedback/reply")
def reply_feedback(req: FeedbackReply, actor: str = Depends(_require_admin)):
    db = get_db()
    try:
        db.execute(
            "UPDATE feedback SET admin_reply=?, status=?, updated_at=datetime('now') WHERE id=?",
            (req.reply, req.status, req.feedback_id),
        )
        _audit(
            db, actor, _get_username(db, actor),
            "feedback.reply", target=str(req.feedback_id), detail=req.status
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


@app.delete("/api/admin/feedback/{fb_id}")
def delete_feedback(fb_id: int, actor: str = Depends(_require_admin)):
    db = get_db()
    try:
        db.execute("DELETE FROM feedback WHERE id=?", (fb_id,))
        _audit(
            db, actor, _get_username(db, actor),
            "feedback.delete", target=str(fb_id)
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


# ---- Invite codes (admin) ----


@app.post("/api/admin/invite-codes")
def create_invite_codes(req: InviteCodeCreate, actor: str = Depends(_require_admin)):
    db = get_db()
    try:
        codes: list[str] = []
        for _i in range(max(1, min(req.count, 100))):
            code = secrets.token_urlsafe(8)
            db.execute(
                "INSERT INTO invite_codes(code, note) VALUES(?, ?)",
                (code, req.note or ""),
            )
            codes.append(code)
        _audit(
            db, actor, _get_username(db, actor),
            "invite.create", detail=f"count={len(codes)}"
        )
        db.commit()
        return {"codes": codes}
    finally:
        db.close()


@app.get("/api/admin/invite-codes")
def list_invite_codes(_: str = Depends(_require_admin)):
    db = get_db()
    try:
        rows = db.execute(
            "SELECT ic.code, ic.used_by, ic.used_at, ic.created_at, ic.note, u.username AS used_by_name "
            "FROM invite_codes ic LEFT JOIN users u ON u.id=ic.used_by "
            "ORDER BY ic.created_at DESC LIMIT 200"
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        db.close()


@app.delete("/api/admin/invite-codes/{code}")
def delete_invite_code(code: str, actor: str = Depends(_require_admin)):
    db = get_db()
    try:
        row = db.execute(
            "SELECT used_by FROM invite_codes WHERE code=?", (code,)
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Code not found")
        if row["used_by"]:
            raise HTTPException(status_code=400, detail="Code already used")
        db.execute("DELETE FROM invite_codes WHERE code=?", (code,))
        _audit(
            db, actor, _get_username(db, actor),
            "invite.delete", target=code
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


# ---- Audit log ----


@app.get("/api/admin/audit-log")
def admin_audit_log(
    _: str = Depends(_require_admin),
    limit: int = Query(200, ge=1, le=1000),
    action: Optional[str] = None,
):
    db = get_db()
    try:
        if action:
            rows = db.execute(
                "SELECT * FROM audit_log WHERE action=? ORDER BY id DESC LIMIT ?",
                (action, limit),
            ).fetchall()
        else:
            rows = db.execute(
                "SELECT * FROM audit_log ORDER BY id DESC LIMIT ?", (limit,)
            ).fetchall()
        return [dict(r) for r in rows]
    finally:
        db.close()
