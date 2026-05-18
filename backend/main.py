from fastapi import FastAPI, HTTPException, Depends, Header, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
import asyncio
import base64
import sqlite3
import hashlib
import secrets
import json
import os
import shutil
import smtplib
import urllib.error
import urllib.request
import zipfile
from datetime import datetime, timedelta, timezone
from email.message import EmailMessage
from pathlib import Path

app = FastAPI(title="指尖时光 Sync API", version="3.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "*").split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_PATH = os.path.join(os.path.dirname(__file__), "fingertip_time.db")
BACKUP_DIR = os.getenv(
    "SERVER_BACKUP_DIR", os.path.join(os.path.dirname(__file__), "backups")
)
SERVER_BACKUP_TASK: Optional[asyncio.Task] = None

# Feature flags (loaded from DB after init)
ADMIN_BOOTSTRAP_USER = os.getenv("ADMIN_BOOTSTRAP_USER", "admin")
ADMIN_BOOTSTRAP_PASSWORD = os.getenv("ADMIN_BOOTSTRAP_PASSWORD", "admin123")

TOKENS: dict[str, str] = {}  # user_id -> token
TOKEN_LAST_ACTIVE: dict[str, datetime] = {}
SESSION_ONLINE_SECONDS = int(os.getenv("SESSION_ONLINE_SECONDS", "300"))


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _format_utc(value: Optional[datetime]) -> Optional[str]:
    if value is None:
        return None
    return value.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace(
        "+00:00", "Z"
    )


def _touch_session(user_id: str) -> None:
    TOKEN_LAST_ACTIVE[user_id] = _utc_now()


def _drop_session(user_id: str) -> None:
    TOKENS.pop(user_id, None)
    TOKEN_LAST_ACTIVE.pop(user_id, None)


def _online_user_ids() -> set[str]:
    cutoff = _utc_now() - timedelta(seconds=SESSION_ONLINE_SECONDS)
    return {
        user_id
        for user_id in TOKENS.keys()
        if TOKEN_LAST_ACTIVE.get(user_id) is not None
        and TOKEN_LAST_ACTIVE[user_id] >= cutoff
    }


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
            time_entries TEXT DEFAULT '[]',
            course_settings TEXT DEFAULT '{}',
            achievement_states TEXT DEFAULT '{}',
            updated_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS workspaces (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            owner_user_id TEXT NOT NULL,
            is_private INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS workspace_members (
            workspace_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            role TEXT NOT NULL DEFAULT 'viewer',
            joined_at TEXT DEFAULT (datetime('now')),
            PRIMARY KEY(workspace_id, user_id),
            FOREIGN KEY(workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS workspace_invites (
            id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL,
            code TEXT UNIQUE NOT NULL,
            role TEXT NOT NULL DEFAULT 'viewer',
            created_by TEXT NOT NULL,
            expires_at TEXT,
            revoked INTEGER DEFAULT 0,
            used_by TEXT,
            used_at TEXT,
            created_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
            FOREIGN KEY(created_by) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY(used_by) REFERENCES users(id) ON DELETE SET NULL
        );
        CREATE TABLE IF NOT EXISTS workspace_data (
            workspace_id TEXT PRIMARY KEY,
            todos TEXT DEFAULT '[]',
            goals TEXT DEFAULT '[]',
            courses TEXT DEFAULT '[]',
            time_entries TEXT DEFAULT '[]',
            updated_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
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
        CREATE TABLE IF NOT EXISTS server_backups (
            id TEXT PRIMARY KEY,
            filename TEXT NOT NULL,
            size_bytes INTEGER DEFAULT 0,
            status TEXT DEFAULT 'created',
            detail TEXT DEFAULT '',
            local_path TEXT DEFAULT '',
            remote_url TEXT DEFAULT '',
            created_at TEXT DEFAULT (datetime('now'))
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
        ("sync_data", "time_entries", "'[]'"),
        ("sync_data", "course_settings", "'{}'"),
        ("sync_data", "achievement_states", "'{}'"),
        ("users", "is_disabled", "0"),
        ("users", "last_login_at", "NULL"),
        ("invite_codes", "note", "''"),
        ("announcements", "updated_at", "datetime('now')"),
    ]:
        cur = conn.execute(f"PRAGMA table_info({table})")
        cols = {r["name"] for r in cur.fetchall()}
        if col not in cols:
            column_type = (
                "INTEGER"
                if isinstance(default, str) and default.isdigit()
                else "TEXT"
            )
            if default == "datetime('now')":
                conn.execute(f"ALTER TABLE {table} ADD COLUMN {col} {column_type}")
                conn.execute(
                    f"UPDATE {table} SET {col}=datetime('now') WHERE {col} IS NULL"
                )
            else:
                conn.execute(
                    f"ALTER TABLE {table} ADD COLUMN {col} {column_type} DEFAULT {default}"
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
        "ai_base_url": os.getenv("AI_BASE_URL", "https://www.boxying.com"),
        "ai_api_key": os.getenv("AI_API_KEY", ""),
        "ai_model": os.getenv("AI_MODEL", "gpt-5.4-mini"),
        "ai_daily_quota": 100,
        # 云端备份/同步
        "backup_enabled": True,
        "backup_max_size_kb": 2048,          # 单用户同步 payload 上限
        "backup_interval_minutes": 30,       # 客户端 autoSync 最小间隔
        "backup_retain_days": 0,             # 0=永久保留
        # 服务器数据库定期备份：本地打包 + 可选 OpenList WebDAV + 可选邮件通知
        "server_backup_enabled": os.getenv("SERVER_BACKUP_ENABLED", "true").lower() in {"1", "true", "yes"},
        "server_backup_interval_minutes": int(os.getenv("SERVER_BACKUP_INTERVAL_MINUTES", "720")),
        "server_backup_retain_days": int(os.getenv("SERVER_BACKUP_RETAIN_DAYS", "14")),
        "openlist_backup_enabled": os.getenv("OPENLIST_BACKUP_ENABLED", "false").lower() in {"1", "true", "yes"},
        "openlist_webdav_url": os.getenv("OPENLIST_WEBDAV_URL", "").rstrip("/"),
        "openlist_public_url": os.getenv("OPENLIST_PUBLIC_URL", "").rstrip("/"),
        "openlist_username": os.getenv("OPENLIST_USERNAME", ""),
        "openlist_password": os.getenv("OPENLIST_PASSWORD", ""),
        "openlist_backup_path": os.getenv("OPENLIST_BACKUP_PATH", "/duoyi-backups"),
        "backup_email_enabled": os.getenv("BACKUP_EMAIL_ENABLED", "false").lower() in {"1", "true", "yes"},
        "backup_email_to": os.getenv("BACKUP_EMAIL_TO", ""),
        "backup_email_from": os.getenv("BACKUP_EMAIL_FROM", os.getenv("EMAIL_SMTP_USERNAME", "")),
        "backup_email_smtp_host": os.getenv("EMAIL_SMTP_HOST", ""),
        "backup_email_smtp_port": int(os.getenv("EMAIL_SMTP_PORT", "465")),
        "backup_email_smtp_username": os.getenv("EMAIL_SMTP_USERNAME", ""),
        "backup_email_smtp_password": os.getenv("EMAIL_SMTP_PASSWORD", ""),
        "backup_email_smtp_use_ssl": os.getenv("EMAIL_SMTP_USE_SSL", "true").lower() in {"1", "true", "yes"},
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
    for row in conn.execute("SELECT id FROM users").fetchall():
        _ensure_private_workspace(conn, row["id"])
    conn.commit()
    conn.close()


def _private_workspace_id(user_id: str) -> str:
    return f"private:{user_id}"


def _ensure_private_workspace(db, user_id: str) -> None:
    workspace_id = _private_workspace_id(user_id)
    db.execute(
        "INSERT OR IGNORE INTO workspaces(id, name, owner_user_id, is_private) "
        "VALUES(?, '个人空间', ?, 1)",
        (workspace_id, user_id),
    )
    db.execute(
        "INSERT OR IGNORE INTO workspace_members(workspace_id, user_id, role) "
        "VALUES(?, ?, 'owner')",
        (workspace_id, user_id),
    )
    db.execute(
        "INSERT OR IGNORE INTO workspace_data(workspace_id) VALUES(?)",
        (workspace_id,),
    )


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
    db = get_db()
    try:
        row = db.execute(
            "SELECT is_disabled FROM users WHERE id=?", (user_id,)
        ).fetchone()
        if row is None:
            _drop_session(user_id)
            raise HTTPException(status_code=401, detail="Invalid or expired token")
        if row["is_disabled"]:
            _drop_session(user_id)
            raise HTTPException(status_code=403, detail="Account disabled")
    finally:
        db.close()
    _touch_session(user_id)
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
    time_entries: list = []
    course_settings: dict = {}
    achievement_states: dict = {}
    workspace_payloads: dict = {}


class WorkspaceCreate(BaseModel):
    name: str


class WorkspaceUpdate(BaseModel):
    name: Optional[str] = None


class WorkspaceInviteCreate(BaseModel):
    role: str = "viewer"
    expires_at: Optional[str] = None


class WorkspaceMemberUpdate(BaseModel):
    role: str


class FeedbackCreate(BaseModel):
    category: str = "feature"
    content: str


class FeedbackReply(BaseModel):
    feedback_id: int
    reply: str
    status: str = "resolved"


FEEDBACK_CATEGORIES = {"feature", "bug", "wish", "other"}
FEEDBACK_STATUSES = {"open", "in_progress", "resolved", "closed"}


def _clean_feedback_category(value: str) -> str:
    category = (value or "feature").strip()
    if category not in FEEDBACK_CATEGORIES:
        raise HTTPException(status_code=400, detail="无效的反馈分类")
    return category


def _clean_feedback_content(value: str) -> str:
    content = (value or "").strip()
    if not content:
        raise HTTPException(status_code=400, detail="反馈内容不能为空")
    if len(content) > 2000:
        raise HTTPException(status_code=400, detail="反馈内容不能超过 2000 字")
    return content


def _clean_feedback_status(value: str) -> str:
    status = (value or "resolved").strip()
    if status not in FEEDBACK_STATUSES:
        raise HTTPException(status_code=400, detail="无效的反馈状态")
    return status


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
    # AI
    ai_enabled: Optional[bool] = None
    ai_base_url: Optional[str] = None
    ai_api_key: Optional[str] = None
    ai_model: Optional[str] = None
    ai_daily_quota: Optional[int] = None
    # 云端备份
    backup_enabled: Optional[bool] = None
    backup_max_size_kb: Optional[int] = None
    backup_interval_minutes: Optional[int] = None
    backup_retain_days: Optional[int] = None
    # 服务器备份 / OpenList / 邮件通知
    server_backup_enabled: Optional[bool] = None
    server_backup_interval_minutes: Optional[int] = None
    server_backup_retain_days: Optional[int] = None
    openlist_backup_enabled: Optional[bool] = None
    openlist_webdav_url: Optional[str] = None
    openlist_public_url: Optional[str] = None
    openlist_username: Optional[str] = None
    openlist_password: Optional[str] = None
    openlist_backup_path: Optional[str] = None
    backup_email_enabled: Optional[bool] = None
    backup_email_to: Optional[str] = None
    backup_email_from: Optional[str] = None
    backup_email_smtp_host: Optional[str] = None
    backup_email_smtp_port: Optional[int] = None
    backup_email_smtp_username: Optional[str] = None
    backup_email_smtp_password: Optional[str] = None
    backup_email_smtp_use_ssl: Optional[bool] = None


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


@app.post("/api/admin/ai/test")
def admin_ai_test(_: str = Depends(_require_admin)):
    """调一个极短 prompt 验证当前 AI 配置连通。"""
    import urllib.request
    import urllib.error

    db = get_db()
    try:
        if not _setting_get(db, "ai_enabled", False):
            raise HTTPException(status_code=503, detail="AI 未启用")
        api_key = str(_setting_get(db, "ai_api_key", "")).strip()
        if not api_key:
            raise HTTPException(status_code=503, detail="尚未配置 API Key")
        base_url = str(
            _setting_get(db, "ai_base_url", "https://api.openai.com")
        ).rstrip("/")
        model = str(_setting_get(db, "ai_model", "gpt-4o-mini"))
        payload = json.dumps(
            {
                "model": model,
                "messages": [
                    {"role": "user", "content": "回复一个 'ok' 即可"},
                ],
                "temperature": 0,
                "max_tokens": 8,
            },
            ensure_ascii=False,
        ).encode("utf-8")
        req = urllib.request.Request(
            f"{base_url}/v1/chat/completions",
            data=payload,
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {api_key}",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                body = resp.read().decode("utf-8", errors="replace")
                data = json.loads(body)
        except urllib.error.HTTPError as e:
            text = e.read().decode("utf-8", errors="replace")
            raise HTTPException(status_code=e.code, detail=text[:200])
        except Exception as e:
            raise HTTPException(status_code=502, detail=f"不可达: {e}")

        content = ""
        choices = data.get("choices") or []
        if choices:
            content = (choices[0].get("message") or {}).get("content", "")
        return {"ok": True, "model": model, "sample": content}
    finally:
        db.close()


@app.get("/api/admin/backups")
def admin_backups(_: str = Depends(_require_admin)):
    """列出每个用户最近一次备份的时间 + 估算大小。"""
    db = get_db()
    try:
        rows = db.execute(
            """
            SELECT u.id, u.username, sd.updated_at,
                   (length(sd.todos) + length(sd.habits) + length(sd.pomodoro_sessions)
                    + length(sd.pomodoro_config) + length(sd.user_profile)
                    + length(sd.notes) + length(sd.countdowns) + length(sd.anniversaries)
                    + length(sd.diaries) + length(sd.goals) + length(sd.courses)
                    + length(sd.time_entries) + length(sd.course_settings)
                    + length(sd.achievement_states)) AS bytes
            FROM users u LEFT JOIN sync_data sd ON sd.user_id = u.id
            ORDER BY sd.updated_at DESC
            """
        ).fetchall()
        return [
            {
                "user_id": r["id"],
                "username": r["username"],
                "updated_at": r["updated_at"],
                "size_kb": ((r["bytes"] or 0) + 1023) // 1024,
            }
            for r in rows
        ]
    finally:
        db.close()


@app.delete("/api/admin/backups/{user_id}")
def admin_backup_wipe(user_id: str, actor: str = Depends(_require_admin)):
    """清空某用户的所有云端备份(账号保留)。"""
    db = get_db()
    try:
        db.execute(
            "UPDATE sync_data SET todos='[]', habits='[]', pomodoro_sessions='[]', "
            "pomodoro_config='{}', user_profile='{}', notes='[]', countdowns='[]', "
            "anniversaries='[]', diaries='[]', goals='[]', courses='[]', "
            "time_entries='[]', course_settings='{}', achievement_states='{}', "
            "updated_at=datetime('now') WHERE user_id=?",
            (user_id,),
        )
        _audit(
            db, actor, _get_username(db, actor),
            "backup.wipe", target=user_id,
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


# ---- Server backup / OpenList / email notice ----


def _setting_bool(db, key: str, default: bool = False) -> bool:
    return bool(_setting_get(db, key, default))


def _backup_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")


def _backup_filename(stamp: str) -> str:
    return f"duoyi_backup_{stamp}.zip"


def _backup_zip(stamp: str) -> tuple[Path, int]:
    backup_dir = Path(BACKUP_DIR)
    backup_dir.mkdir(parents=True, exist_ok=True)
    filename = _backup_filename(stamp)
    zip_path = backup_dir / filename
    db_path = Path(DB_PATH)
    snapshot_path = backup_dir / f"fingertip_time_{stamp}.db"
    shutil.copy2(db_path, snapshot_path)
    try:
        metadata = {
            "app": "duoyi",
            "created_at": datetime.now(timezone.utc).isoformat(),
            "source_db": str(db_path),
            "filename": filename,
        }
        with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            zf.write(snapshot_path, "fingertip_time.db")
            zf.writestr(
                "metadata.json",
                json.dumps(metadata, ensure_ascii=False, indent=2),
            )
    finally:
        try:
            snapshot_path.unlink()
        except FileNotFoundError:
            pass
    return zip_path, zip_path.stat().st_size


def _openlist_headers(username: str, password: str) -> dict[str, str]:
    headers = {"Content-Type": "application/zip"}
    if username or password:
        token = base64.b64encode(f"{username}:{password}".encode()).decode()
        headers["Authorization"] = f"Basic {token}"
    return headers


def _openlist_url(base_url: str, remote_path: str, filename: str) -> str:
    clean_base = base_url.rstrip("/")
    parts = [p.strip("/") for p in [remote_path, filename] if p.strip("/")]
    return clean_base + "/" + "/".join(parts)


def _openlist_mkcol(base_url: str, remote_path: str, headers: dict[str, str]) -> None:
    clean_base = base_url.rstrip("/")
    current = clean_base
    for part in [p for p in remote_path.strip("/").split("/") if p]:
        current = f"{current}/{part}"
        req = urllib.request.Request(current, headers=headers, method="MKCOL")
        try:
            urllib.request.urlopen(req, timeout=15).close()
        except urllib.error.HTTPError as e:
            if e.code not in {405, 409}:
                raise


def _upload_openlist(db, zip_path: Path) -> str:
    if not _setting_bool(db, "openlist_backup_enabled", False):
        return ""
    base_url = str(_setting_get(db, "openlist_webdav_url", "") or "").rstrip("/")
    if not base_url:
        raise RuntimeError("OpenList WebDAV URL 未配置")
    remote_path = str(_setting_get(db, "openlist_backup_path", "/duoyi-backups") or "")
    username = str(_setting_get(db, "openlist_username", "") or "")
    password = str(_setting_get(db, "openlist_password", "") or "")
    headers = _openlist_headers(username, password)
    _openlist_mkcol(base_url, remote_path, headers)
    upload_url = _openlist_url(base_url, remote_path, zip_path.name)
    with zip_path.open("rb") as fh:
        req = urllib.request.Request(
            upload_url,
            data=fh.read(),
            headers=headers,
            method="PUT",
        )
        urllib.request.urlopen(req, timeout=60).close()
    public = str(_setting_get(db, "openlist_public_url", "") or "").rstrip("/")
    return _openlist_url(public or base_url, remote_path, zip_path.name)


def _send_backup_email(db, subject: str, body: str) -> None:
    if not _setting_bool(db, "backup_email_enabled", False):
        return
    to_addr = str(_setting_get(db, "backup_email_to", "") or "").strip()
    host = str(_setting_get(db, "backup_email_smtp_host", "") or "").strip()
    username = str(_setting_get(db, "backup_email_smtp_username", "") or "").strip()
    password = str(_setting_get(db, "backup_email_smtp_password", "") or "")
    if not (to_addr and host and username and password):
        raise RuntimeError("邮件通知 SMTP 未完整配置")
    from_addr = str(_setting_get(db, "backup_email_from", "") or "").strip() or username
    port = int(_setting_get(db, "backup_email_smtp_port", 465) or 465)
    use_ssl = _setting_bool(db, "backup_email_smtp_use_ssl", True)
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = from_addr
    msg["To"] = to_addr
    msg.set_content(body)
    if use_ssl:
        with smtplib.SMTP_SSL(host, port, timeout=30) as smtp:
            smtp.login(username, password)
            smtp.send_message(msg)
    else:
        with smtplib.SMTP(host, port, timeout=30) as smtp:
            smtp.starttls()
            smtp.login(username, password)
            smtp.send_message(msg)


def _cleanup_old_backups(db) -> None:
    retain_days = int(_setting_get(db, "server_backup_retain_days", 14) or 0)
    if retain_days <= 0:
        return
    cutoff = datetime.now(timezone.utc).timestamp() - retain_days * 86400
    for path in Path(BACKUP_DIR).glob("duoyi_backup_*.zip"):
        if path.stat().st_mtime < cutoff:
            try:
                path.unlink()
            except FileNotFoundError:
                pass


def run_server_backup(actor: Optional[str] = None) -> dict:
    stamp = _backup_stamp()
    backup_id = f"server:{stamp}"
    db = get_db()
    remote_url = ""
    detail = ""
    status = "created"
    try:
        zip_path, size_bytes = _backup_zip(stamp)
        try:
            remote_url = _upload_openlist(db, zip_path)
            status = "uploaded" if remote_url else "local_only"
        except Exception as e:
            status = "local_created_remote_failed"
            detail = f"OpenList 上传失败: {e}"
        db.execute(
            "INSERT INTO server_backups(id, filename, size_bytes, status, detail, local_path, remote_url) "
            "VALUES(?,?,?,?,?,?,?)",
            (
                backup_id,
                zip_path.name,
                size_bytes,
                status,
                detail,
                str(zip_path),
                remote_url,
            ),
        )
        _audit(
            db,
            actor,
            _get_username(db, actor) if actor else "system",
            "server_backup.run",
            target=backup_id,
            detail=detail or remote_url,
        )
        db.commit()
        _cleanup_old_backups(db)
        try:
            _send_backup_email(
                db,
                f"多仪服务器备份: {status}",
                f"文件: {zip_path.name}\n大小: {size_bytes} bytes\n状态: {status}\n远端: {remote_url or '-'}\n详情: {detail or '-'}",
            )
        except Exception as e:
            detail = f"{detail}; 邮件通知失败: {e}" if detail else f"邮件通知失败: {e}"
            db.execute(
                "UPDATE server_backups SET detail=? WHERE id=?",
                (detail, backup_id),
            )
            db.commit()
        return {
            "id": backup_id,
            "filename": zip_path.name,
            "size_bytes": size_bytes,
            "status": status,
            "detail": detail,
            "local_path": str(zip_path),
            "remote_url": remote_url,
        }
    finally:
        db.close()


async def _server_backup_loop() -> None:
    while True:
        db = get_db()
        try:
            enabled = _setting_bool(db, "server_backup_enabled", True)
            interval = int(_setting_get(db, "server_backup_interval_minutes", 720) or 720)
        finally:
            db.close()
        await asyncio.sleep(max(interval, 10) * 60)
        if not enabled:
            continue
        try:
            await asyncio.to_thread(run_server_backup, None)
        except Exception:
            pass


@app.on_event("startup")
async def _start_server_backup_loop():
    global SERVER_BACKUP_TASK
    if SERVER_BACKUP_TASK is None or SERVER_BACKUP_TASK.done():
        SERVER_BACKUP_TASK = asyncio.create_task(_server_backup_loop())


@app.on_event("shutdown")
async def _stop_server_backup_loop():
    global SERVER_BACKUP_TASK
    if SERVER_BACKUP_TASK is not None:
        SERVER_BACKUP_TASK.cancel()
        SERVER_BACKUP_TASK = None


@app.get("/api/admin/server-backups")
def admin_server_backups(_: str = Depends(_require_admin)):
    db = get_db()
    try:
        rows = db.execute(
            "SELECT * FROM server_backups ORDER BY created_at DESC LIMIT 100"
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        db.close()


@app.post("/api/admin/server-backups/run")
def admin_run_server_backup(actor: str = Depends(_require_admin)):
    return run_server_backup(actor)


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
                "INSERT INTO users(id, username, password_hash, last_login_at) "
                "VALUES(?,?,?,datetime('now'))",
                (user_id, req.username, _hash_password(req.password)),
            )
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=409, detail="Username already exists")

        db.execute("INSERT INTO sync_data(user_id) VALUES(?)", (user_id,))
        _ensure_private_workspace(db, user_id)

        if _setting_get(db, "invite_code_required", False):
            db.execute(
                "UPDATE invite_codes SET used_by=?, used_at=datetime('now') WHERE code=?",
                (user_id, (req.invite_code or "").strip()),
            )

        _audit(db, user_id, req.username, "register", user_id)
        db.commit()
        token = secrets.token_hex(32)
        TOKENS[user_id] = token
        _touch_session(user_id)
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
        _touch_session(row["id"])
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
    _drop_session(user_id)
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


def _merge_state_dict(server: dict, client: dict) -> dict:
    result = dict(server or {})
    for key, value in (client or {}).items():
        current = result.get(key)
        if current is None or str(value) > str(current):
            result[key] = value
    return result


def _require_workspace_member(db, workspace_id: str, user_id: str) -> sqlite3.Row:
    row = db.execute(
        """
        SELECT wm.role, w.name, w.owner_user_id, w.is_private
        FROM workspace_members wm
        JOIN workspaces w ON w.id = wm.workspace_id
        WHERE wm.workspace_id=? AND wm.user_id=?
        """,
        (workspace_id, user_id),
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=403, detail="No workspace access")
    return row


def _require_workspace_editor(db, workspace_id: str, user_id: str) -> sqlite3.Row:
    row = _require_workspace_member(db, workspace_id, user_id)
    if row["role"] not in {"owner", "editor"}:
        raise HTTPException(status_code=403, detail="Editor role required")
    return row


def _workspace_to_dict(row: sqlite3.Row, members: list[sqlite3.Row]) -> dict:
    return {
        "id": row["id"],
        "name": row["name"],
        "owner_user_id": row["owner_user_id"],
        "is_private": bool(row["is_private"]),
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
        "members": [
            {
                "workspace_id": m["workspace_id"],
                "user_id": m["user_id"],
                "username": m["username"],
                "role": m["role"],
                "joined_at": m["joined_at"],
            }
            for m in members
        ],
    }


def _workspace_data(db, workspace_id: str) -> dict:
    row = db.execute(
        "SELECT todos, goals, courses, time_entries FROM workspace_data WHERE workspace_id=?",
        (workspace_id,),
    ).fetchone()
    if row is None:
        return {
            "todos": [],
            "goals": [],
            "courses": [],
            "time_entries": [],
        }
    return {
        "todos": json.loads(row["todos"] or "[]"),
        "goals": json.loads(row["goals"] or "[]"),
        "courses": json.loads(row["courses"] or "[]"),
        "time_entries": json.loads(row["time_entries"] or "[]"),
    }


def _visible_workspace_ids(db, user_id: str) -> set[str]:
    rows = db.execute(
        "SELECT workspace_id FROM workspace_members WHERE user_id=?",
        (user_id,),
    ).fetchall()
    return {r["workspace_id"] for r in rows}


def _merge_workspace_payloads(db, user_id: str, payloads: dict) -> dict:
    visible = _visible_workspace_ids(db, user_id)
    merged: dict = {}
    if not isinstance(payloads, dict):
        payloads = {}
    for workspace_id in visible:
        if workspace_id.startswith("private:"):
            continue
        role = _require_workspace_member(db, workspace_id, user_id)["role"]
        server = _workspace_data(db, workspace_id)
        client = payloads.get(workspace_id) if isinstance(payloads, dict) else None
        if not isinstance(client, dict) or role == "viewer":
            merged_data = server
        else:
            merged_data = {
                "todos": _merge_by_timestamp(server.get("todos", []), client.get("todos", [])),
                "goals": _merge_by_timestamp(server.get("goals", []), client.get("goals", [])),
                "courses": _merge_by_timestamp(server.get("courses", []), client.get("courses", [])),
                "time_entries": _merge_by_timestamp(
                    server.get("time_entries", []), client.get("time_entries", [])
                ),
            }
            db.execute(
                """
                INSERT INTO workspace_data(workspace_id, todos, goals, courses, time_entries, updated_at)
                VALUES(?,?,?,?,?,datetime('now'))
                ON CONFLICT(workspace_id) DO UPDATE SET
                    todos=excluded.todos,
                    goals=excluded.goals,
                    courses=excluded.courses,
                    time_entries=excluded.time_entries,
                    updated_at=datetime('now')
                """,
                (
                    workspace_id,
                    json.dumps(merged_data["todos"], ensure_ascii=False),
                    json.dumps(merged_data["goals"], ensure_ascii=False),
                    json.dumps(merged_data["courses"], ensure_ascii=False),
                    json.dumps(merged_data["time_entries"], ensure_ascii=False),
                ),
            )
        merged[workspace_id] = merged_data
    return merged


@app.post("/api/sync")
def sync(req: SyncRequest, user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        if _setting_get(db, "maintenance_mode", False):
            raise HTTPException(status_code=503, detail="Maintenance mode")
        if not _setting_get(db, "backup_enabled", True):
            raise HTTPException(status_code=503, detail="云端备份已被管理员关闭")

        # 简单的 payload 大小保护
        max_kb = int(_setting_get(db, "backup_max_size_kb", 2048) or 2048)
        if max_kb > 0:
            payload_size = len(
                json.dumps(req.model_dump(), ensure_ascii=False).encode("utf-8")
            )
            if payload_size > max_kb * 1024:
                raise HTTPException(
                    status_code=413,
                    detail=f"同步数据过大 ({payload_size // 1024}KB > {max_kb}KB)",
                )

        _ensure_private_workspace(db, user_id)
        row = db.execute(
            "SELECT todos, habits, pomodoro_sessions, pomodoro_config, user_profile, "
            "notes, countdowns, anniversaries, diaries, goals, courses, time_entries, "
            "course_settings, achievement_states "
            "FROM sync_data WHERE user_id=?",
            (user_id,),
        ).fetchone()

        def _list(col):
            return json.loads(row[col]) if row and row[col] else []

        def _obj(col):
            value = json.loads(row[col]) if row and row[col] else {}
            return value if isinstance(value, dict) else {}

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
        server_time_entries = _list("time_entries")
        server_course_settings = _obj("course_settings")
        server_achievement_states = _obj("achievement_states")

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
        merged_time_entries = _merge_by_timestamp(
            server_time_entries, req.time_entries
        )
        merged_course_settings = _merge_dict(
            server_course_settings, req.course_settings
        )
        merged_achievement_states = _merge_state_dict(
            server_achievement_states, req.achievement_states
        )
        merged_workspace_payloads = _merge_workspace_payloads(
            db, user_id, req.workspace_payloads
        )

        db.execute(
            """
            INSERT OR REPLACE INTO sync_data
            (user_id, todos, habits, pomodoro_sessions, pomodoro_config, user_profile,
             notes, countdowns, anniversaries, diaries, goals, courses, time_entries,
             course_settings, achievement_states, updated_at)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,datetime('now'))
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
                json.dumps(merged_time_entries, ensure_ascii=False),
                json.dumps(merged_course_settings, ensure_ascii=False),
                json.dumps(merged_achievement_states, ensure_ascii=False),
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
            "time_entries": merged_time_entries,
            "course_settings": merged_course_settings,
            "achievement_states": merged_achievement_states,
            "workspace_payloads": merged_workspace_payloads,
        }
    finally:
        db.close()


# ---- Workspaces ----


@app.get("/api/workspaces")
def list_workspaces(user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        _ensure_private_workspace(db, user_id)
        rows = db.execute(
            """
            SELECT w.*
            FROM workspaces w
            JOIN workspace_members wm ON wm.workspace_id = w.id
            WHERE wm.user_id=?
            ORDER BY w.is_private DESC, w.updated_at DESC
            """,
            (user_id,),
        ).fetchall()
        result = []
        for row in rows:
            members = db.execute(
                """
                SELECT wm.workspace_id, wm.user_id, u.username, wm.role, wm.joined_at
                FROM workspace_members wm
                JOIN users u ON u.id = wm.user_id
                WHERE wm.workspace_id=?
                ORDER BY wm.role='owner' DESC, wm.joined_at
                """,
                (row["id"],),
            ).fetchall()
            item = _workspace_to_dict(row, members)
            item["data"] = _workspace_data(db, row["id"])
            result.append(item)
        return result
    finally:
        db.close()


@app.post("/api/workspaces")
def create_workspace(req: WorkspaceCreate, user_id: str = Depends(_verify_token)):
    name = req.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Workspace name required")
    db = get_db()
    try:
        workspace_id = secrets.token_hex(12)
        db.execute(
            "INSERT INTO workspaces(id, name, owner_user_id, is_private) VALUES(?,?,?,0)",
            (workspace_id, name, user_id),
        )
        db.execute(
            "INSERT INTO workspace_members(workspace_id, user_id, role) VALUES(?,?, 'owner')",
            (workspace_id, user_id),
        )
        db.execute("INSERT INTO workspace_data(workspace_id) VALUES(?)", (workspace_id,))
        _audit(db, user_id, _get_username(db, user_id), "workspace.create", workspace_id)
        db.commit()
        return {"id": workspace_id, "name": name}
    finally:
        db.close()


@app.patch("/api/workspaces/{workspace_id}")
def update_workspace(
    workspace_id: str, req: WorkspaceUpdate, user_id: str = Depends(_verify_token)
):
    db = get_db()
    try:
        row = _require_workspace_editor(db, workspace_id, user_id)
        if row["is_private"]:
            raise HTTPException(status_code=400, detail="Private workspace is immutable")
        changed = {}
        if req.name is not None and req.name.strip():
            db.execute(
                "UPDATE workspaces SET name=?, updated_at=datetime('now') WHERE id=?",
                (req.name.strip(), workspace_id),
            )
            changed["name"] = req.name.strip()
        _audit(
            db,
            user_id,
            _get_username(db, user_id),
            "workspace.update",
            workspace_id,
            json.dumps(changed, ensure_ascii=False),
        )
        db.commit()
        return {"status": "ok", "changed": changed}
    finally:
        db.close()


@app.post("/api/workspaces/{workspace_id}/invites")
def create_workspace_invite(
    workspace_id: str,
    req: WorkspaceInviteCreate,
    user_id: str = Depends(_verify_token),
):
    if req.role not in {"editor", "viewer"}:
        raise HTTPException(status_code=400, detail="Invalid role")
    db = get_db()
    try:
        row = _require_workspace_editor(db, workspace_id, user_id)
        if row["is_private"]:
            raise HTTPException(status_code=400, detail="Private workspace cannot invite")
        invite_id = secrets.token_hex(12)
        code = secrets.token_urlsafe(8).replace("-", "").replace("_", "")[:10]
        db.execute(
            """
            INSERT INTO workspace_invites(id, workspace_id, code, role, created_by, expires_at)
            VALUES(?,?,?,?,?,?)
            """,
            (invite_id, workspace_id, code, req.role, user_id, req.expires_at),
        )
        _audit(db, user_id, _get_username(db, user_id), "workspace.invite", workspace_id)
        db.commit()
        return {
            "id": invite_id,
            "workspace_id": workspace_id,
            "code": code,
            "role": req.role,
            "expires_at": req.expires_at,
        }
    finally:
        db.close()


@app.post("/api/invites/{code}/accept")
def accept_workspace_invite(code: str, user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        row = db.execute(
            """
            SELECT wi.*, w.name
            FROM workspace_invites wi
            JOIN workspaces w ON w.id = wi.workspace_id
            WHERE wi.code=?
            """,
            (code.strip(),),
        ).fetchone()
        if row is None or row["revoked"]:
            raise HTTPException(status_code=404, detail="Invite not found")
        if row["expires_at"] and row["expires_at"] < datetime.now(timezone.utc).isoformat():
            raise HTTPException(status_code=400, detail="Invite expired")
        db.execute(
            "INSERT INTO workspace_members(workspace_id, user_id, role) VALUES(?,?,?) "
            "ON CONFLICT(workspace_id, user_id) DO UPDATE SET role=excluded.role",
            (row["workspace_id"], user_id, row["role"]),
        )
        db.execute(
            "UPDATE workspace_invites SET used_by=?, used_at=datetime('now') WHERE id=?",
            (user_id, row["id"]),
        )
        _audit(
            db,
            user_id,
            _get_username(db, user_id),
            "workspace.invite.accept",
            row["workspace_id"],
        )
        db.commit()
        return {
            "workspace_id": row["workspace_id"],
            "name": row["name"],
            "role": row["role"],
        }
    finally:
        db.close()


@app.patch("/api/workspaces/{workspace_id}/members/{member_user_id}")
def update_workspace_member(
    workspace_id: str,
    member_user_id: str,
    req: WorkspaceMemberUpdate,
    user_id: str = Depends(_verify_token),
):
    if req.role not in {"editor", "viewer"}:
        raise HTTPException(status_code=400, detail="Invalid role")
    db = get_db()
    try:
        owner = _require_workspace_member(db, workspace_id, user_id)
        if owner["role"] != "owner":
            raise HTTPException(status_code=403, detail="Owner role required")
        if member_user_id == owner["owner_user_id"]:
            raise HTTPException(status_code=400, detail="Owner role cannot change")
        db.execute(
            "UPDATE workspace_members SET role=? WHERE workspace_id=? AND user_id=?",
            (req.role, workspace_id, member_user_id),
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


@app.delete("/api/workspaces/{workspace_id}/members/{member_user_id}")
def remove_workspace_member(
    workspace_id: str,
    member_user_id: str,
    user_id: str = Depends(_verify_token),
):
    db = get_db()
    try:
        owner = _require_workspace_member(db, workspace_id, user_id)
        if owner["role"] != "owner" and user_id != member_user_id:
            raise HTTPException(status_code=403, detail="Owner role required")
        if member_user_id == owner["owner_user_id"]:
            raise HTTPException(status_code=400, detail="Owner cannot be removed")
        db.execute(
            "DELETE FROM workspace_members WHERE workspace_id=? AND user_id=?",
            (workspace_id, member_user_id),
        )
        db.commit()
        return {"status": "ok"}
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
    category = _clean_feedback_category(req.category)
    content = _clean_feedback_content(req.content)
    db = get_db()
    try:
        cur = db.execute(
            "INSERT INTO feedback(user_id, category, content) VALUES(?,?,?)",
            (user_id, category, content),
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
            "tokens_online": len(_online_user_ids()),
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
        for secret_key in ("openlist_password", "backup_email_smtp_password"):
            raw = str(result.get(secret_key) or "")
            result[f"{secret_key}_set"] = bool(raw)
            result[secret_key] = (
                f"{raw[:2]}***{raw[-2:]}" if len(raw) > 4 else ("***" if raw else "")
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
        online_user_ids = _online_user_ids()
        return [
            {
                "user_id": r["id"],
                "username": r["username"],
                "is_admin": bool(r["is_admin"]),
                "is_disabled": bool(r["is_disabled"]),
                "created_at": r["created_at"],
                "last_login_at": r["last_login_at"],
                "last_active_at": _format_utc(TOKEN_LAST_ACTIVE.get(r["id"])),
                "feedback_count": r["fb_count"],
                "online": r["id"] in online_user_ids,
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
                _drop_session(user_id)
        if req.new_password:
            db.execute(
                "UPDATE users SET password_hash=? WHERE id=?",
                (_hash_password(req.new_password), user_id),
            )
            _drop_session(user_id)  # force re-login

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
        _drop_session(user_id)
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
    reply = _clean_feedback_content(req.reply)
    status = _clean_feedback_status(req.status)
    db = get_db()
    try:
        cur = db.execute(
            "UPDATE feedback SET admin_reply=?, status=?, updated_at=datetime('now') WHERE id=?",
            (reply, status, req.feedback_id),
        )
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="反馈不存在")
        _audit(
            db, actor, _get_username(db, actor),
            "feedback.reply", target=str(req.feedback_id), detail=status
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


@app.delete("/api/admin/feedback/{fb_id}")
def delete_feedback(fb_id: int, actor: str = Depends(_require_admin)):
    db = get_db()
    try:
        cur = db.execute("DELETE FROM feedback WHERE id=?", (fb_id,))
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="反馈不存在")
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
