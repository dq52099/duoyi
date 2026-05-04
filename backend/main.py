from fastapi import FastAPI, HTTPException, Depends, Header, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional, List
import sqlite3
import hashlib
import secrets
import json
import os
from datetime import datetime, timezone

app = FastAPI(title="指尖时光 Sync API", version="3.0.0")

app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

DB_PATH = os.path.join(os.path.dirname(__file__), "fingertip_time.db")

# Feature flags
INVITE_CODE_REQUIRED = os.getenv("INVITE_CODE_REQUIRED", "false").lower() in {"1", "true", "yes"}
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
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS sync_data (
            user_id TEXT PRIMARY KEY,
            todos TEXT DEFAULT '[]',
            habits TEXT DEFAULT '[]',
            pomodoro_sessions TEXT DEFAULT '[]',
            pomodoro_config TEXT DEFAULT '{}',
            user_profile TEXT DEFAULT '{}',
            updated_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS invite_codes (
            code TEXT PRIMARY KEY,
            used_by TEXT,
            used_at TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS announcements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            level TEXT DEFAULT 'info',
            published INTEGER DEFAULT 1,
            created_at TEXT DEFAULT (datetime('now'))
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
        """
    )

    # Migration helper for older sync_data schemas
    cur = conn.execute("PRAGMA table_info(sync_data)")
    cols = {r["name"] for r in cur.fetchall()}
    for col in ("pomodoro_sessions", "pomodoro_config", "user_profile"):
        if col not in cols:
            default = "'[]'" if col == "pomodoro_sessions" else "'{}'"
            conn.execute(f"ALTER TABLE sync_data ADD COLUMN {col} TEXT DEFAULT {default}")

    # Bootstrap an admin user once
    cur = conn.execute("SELECT 1 FROM users WHERE username=?", (ADMIN_BOOTSTRAP_USER,)).fetchone()
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
        row = db.execute("SELECT is_admin FROM users WHERE id=?", (user_id,)).fetchone()
        if row is None or not row["is_admin"]:
            raise HTTPException(status_code=403, detail="Admin only")
        return user_id
    finally:
        db.close()


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


class InviteCodeCreate(BaseModel):
    count: int = 1


# ---- Public ----

@app.get("/api/health")
def health():
    return {
        "status": "ok",
        "version": "3.0.0",
        "invite_required": INVITE_CODE_REQUIRED,
        "time": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/api/config")
def public_config():
    return {"invite_code_required": INVITE_CODE_REQUIRED}


# ---- Auth ----

@app.post("/api/auth/register")
def register(req: RegisterRequest):
    db = get_db()
    try:
        if INVITE_CODE_REQUIRED:
            code = (req.invite_code or "").strip()
            if not code:
                raise HTTPException(status_code=400, detail="Invite code required")
            row = db.execute("SELECT used_by FROM invite_codes WHERE code=?", (code,)).fetchone()
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

        if INVITE_CODE_REQUIRED:
            db.execute(
                "UPDATE invite_codes SET used_by=?, used_at=datetime('now') WHERE code=?",
                (user_id, (req.invite_code or "").strip()),
            )

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
            "SELECT id, password_hash, is_admin FROM users WHERE username=?",
            (req.username,),
        ).fetchone()
        if row is None or row["password_hash"] != _hash_password(req.password):
            raise HTTPException(status_code=401, detail="Invalid credentials")
        token = secrets.token_hex(32)
        TOKENS[row["id"]] = token
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
            "SELECT id, username, avatar, is_admin, created_at FROM users WHERE id=?",
            (user_id,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="User not found")
        return {
            "user_id": row["id"],
            "username": row["username"],
            "avatar": row["avatar"] or "",
            "is_admin": bool(row["is_admin"]),
            "created_at": row["created_at"],
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
        row = db.execute(
            "SELECT todos, habits, pomodoro_sessions, pomodoro_config, user_profile FROM sync_data WHERE user_id=?",
            (user_id,),
        ).fetchone()

        server_todos = json.loads(row["todos"]) if row else []
        server_habits = json.loads(row["habits"]) if row else []
        server_sessions = json.loads(row["pomodoro_sessions"]) if row else []
        server_config = json.loads(row["pomodoro_config"] or "{}") if row else {}
        server_profile = json.loads(row["user_profile"] or "{}") if row else {}

        merged_todos = _merge_by_timestamp(server_todos, req.todos)
        merged_habits = _merge_by_timestamp(server_habits, req.habits)
        merged_sessions = _merge_by_timestamp(server_sessions, req.pomodoro_sessions)
        merged_config = _merge_dict(server_config, req.pomodoro_config)
        merged_profile = _merge_dict(server_profile, req.user_profile)

        db.execute(
            """
            INSERT OR REPLACE INTO sync_data
            (user_id, todos, habits, pomodoro_sessions, pomodoro_config, user_profile, updated_at)
            VALUES(?,?,?,?,?,?,datetime('now'))
            """,
            (
                user_id,
                json.dumps(merged_todos, ensure_ascii=False),
                json.dumps(merged_habits, ensure_ascii=False),
                json.dumps(merged_sessions, ensure_ascii=False),
                json.dumps(merged_config, ensure_ascii=False),
                json.dumps(merged_profile, ensure_ascii=False),
            ),
        )
        db.commit()

        return {
            "todos": merged_todos,
            "habits": merged_habits,
            "pomodoro_sessions": merged_sessions,
            "pomodoro_config": merged_config,
            "user_profile": merged_profile,
        }
    finally:
        db.close()


# ---- Announcements ----

@app.get("/api/announcements")
def list_announcements(limit: int = Query(20, ge=1, le=100)):
    db = get_db()
    try:
        rows = db.execute(
            "SELECT id, title, body, level, created_at FROM announcements WHERE published=1 ORDER BY id DESC LIMIT ?",
            (limit,),
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        db.close()


@app.post("/api/admin/announcements")
def create_announcement(req: AnnouncementCreate, _: str = Depends(_require_admin)):
    db = get_db()
    try:
        cur = db.execute(
            "INSERT INTO announcements(title, body, level, published) VALUES(?,?,?,?)",
            (req.title, req.body, req.level, 1 if req.published else 0),
        )
        db.commit()
        return {"id": cur.lastrowid}
    finally:
        db.close()


# ---- Feedback ----

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
            "SELECT id, category, content, status, admin_reply, created_at, updated_at FROM feedback WHERE user_id=? ORDER BY id DESC",
            (user_id,),
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        db.close()


@app.get("/api/admin/feedback")
def list_all_feedback(_: str = Depends(_require_admin), status: Optional[str] = None):
    db = get_db()
    try:
        if status:
            rows = db.execute(
                "SELECT f.*, u.username FROM feedback f JOIN users u ON u.id=f.user_id WHERE f.status=? ORDER BY f.id DESC",
                (status,),
            ).fetchall()
        else:
            rows = db.execute(
                "SELECT f.*, u.username FROM feedback f JOIN users u ON u.id=f.user_id ORDER BY f.id DESC"
            ).fetchall()
        return [dict(r) for r in rows]
    finally:
        db.close()


@app.post("/api/admin/feedback/reply")
def reply_feedback(req: FeedbackReply, _: str = Depends(_require_admin)):
    db = get_db()
    try:
        db.execute(
            "UPDATE feedback SET admin_reply=?, status=?, updated_at=datetime('now') WHERE id=?",
            (req.reply, req.status, req.feedback_id),
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


# ---- Invite codes (admin) ----

@app.post("/api/admin/invite-codes")
def create_invite_codes(req: InviteCodeCreate, _: str = Depends(_require_admin)):
    db = get_db()
    try:
        codes: list[str] = []
        for _i in range(max(1, min(req.count, 100))):
            code = secrets.token_urlsafe(8)
            db.execute("INSERT INTO invite_codes(code) VALUES(?)", (code,))
            codes.append(code)
        db.commit()
        return {"codes": codes}
    finally:
        db.close()


@app.get("/api/admin/invite-codes")
def list_invite_codes(_: str = Depends(_require_admin)):
    db = get_db()
    try:
        rows = db.execute(
            "SELECT code, used_by, used_at, created_at FROM invite_codes ORDER BY created_at DESC LIMIT 200"
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        db.close()
