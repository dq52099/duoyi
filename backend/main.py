from fastapi import FastAPI, HTTPException, Depends, Header, Query, WebSocket, WebSocketDisconnect, UploadFile, File, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, FileResponse
from pydantic import BaseModel
from typing import Iterable, Optional
import asyncio
import base64
import csv
import io
import sqlite3
import hashlib
import html
import secrets
import json
import os
import re
import shutil
import smtplib
import subprocess
import urllib.parse
import urllib.error
import urllib.request
import zipfile
from datetime import datetime, timedelta, timezone
from email.message import EmailMessage
from email.utils import formataddr
from pathlib import Path

app = FastAPI(title="多仪 Sync API", version="3.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "*").split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def _legacy_db_filename() -> str:
    return base64.b64decode("ZmluZ2VydGlwX3RpbWUuZGI=").decode()


def _db_counts(path: str) -> tuple[int, int]:
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return (0, 0)
    conn = sqlite3.connect(path)
    try:
        tables = {
            row[0]
            for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        }
        users = (
            conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
            if "users" in tables
            else 0
        )
        feedback = (
            conn.execute("SELECT COUNT(*) FROM feedback").fetchone()[0]
            if "feedback" in tables
            else 0
        )
        return (int(users or 0), int(feedback or 0))
    except sqlite3.DatabaseError:
        return (0, 0)
    finally:
        conn.close()


def _default_db_path() -> str:
    base_dir = os.path.dirname(__file__)
    current = os.path.join(base_dir, "duoyi.db")
    legacy = os.path.join(base_dir, _legacy_db_filename())
    if os.path.exists(current) and os.path.exists(legacy):
        current_users, current_feedback = _db_counts(current)
        legacy_users, legacy_feedback = _db_counts(legacy)
        if legacy_feedback > current_feedback:
            return legacy
        if current_users <= 1 and legacy_users > current_users:
            return legacy
        return current
    if os.path.exists(current) or not os.path.exists(legacy):
        return current
    return legacy


DB_PATH = os.getenv("DUOYI_DB_PATH", _default_db_path())
BACKUP_DIR = os.getenv(
    "SERVER_BACKUP_DIR", os.path.join(os.path.dirname(__file__), "backups")
)
AVATAR_UPLOAD_DIR = os.getenv(
    "DUOYI_AVATAR_UPLOAD_DIR",
    os.path.join(os.path.dirname(__file__), "uploads", "avatars"),
)
SERVER_BACKUP_TASK: Optional[asyncio.Task] = None
REMINDER_EMAIL_TASK: Optional[asyncio.Task] = None

# Feature flags (loaded from DB after init)
ADMIN_BOOTSTRAP_USER = os.getenv("ADMIN_BOOTSTRAP_USER", "admin")
ADMIN_BOOTSTRAP_PASSWORD = os.getenv("ADMIN_BOOTSTRAP_PASSWORD", "admin123")

TOKENS: dict[str, str] = {}  # user_id -> token
TOKEN_LAST_ACTIVE: dict[str, datetime] = {}
SESSION_ONLINE_SECONDS = int(os.getenv("SESSION_ONLINE_SECONDS", "300"))
FOCUS_ROOM_ONLINE_SECONDS = int(os.getenv("FOCUS_ROOM_ONLINE_SECONDS", "180"))
FOCUS_ROOM_MAX_WEEKLY_SECONDS = 12 * 60 * 60 * 7
FOCUS_ROOM_MAX_SESSION_COUNT = 1000
FOCUS_ROOM_HEARTBEAT_THROTTLE_SECONDS = 10
FOCUS_ROOM_SESSION_JUMP_WINDOW_SECONDS = 5 * 60
FOCUS_ROOM_MAX_SESSION_COUNT_JUMP = 20
FOCUS_FRIEND_REQUEST_LIMIT_PER_DAY = int(
    os.getenv("FOCUS_FRIEND_REQUEST_LIMIT_PER_DAY", "20")
)
EMAIL_CODE_PROVIDERS = {"claw163", "openclaw", "openclaw_mail", "resend", "smtp", "none"}
EMAIL_CODE_SLOTS = {"primary", "backup"}
DEFAULT_EMAIL_SENDER_NAME = os.getenv("EMAIL_SENDER_NAME", "多仪")
DEFAULT_RESEND_FROM = os.getenv("RESEND_FROM", "多仪 <noreply@mail.6688667.xyz>")


def _env_any(*names: str, default: str = "") -> str:
    for name in names:
        value = os.getenv(name)
        if value is not None:
            return value
    return default


def _env_bool(*names: str, default: bool = False) -> bool:
    raw = _env_any(*names, default="true" if default else "false")
    return str(raw).strip().lower() in {"1", "true", "yes", "on"}


def _env_int(*names: str, default: int) -> int:
    raw = _env_any(*names, default=str(default))
    try:
        return int(raw)
    except (TypeError, ValueError):
        return default


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _format_utc(value: Optional[datetime]) -> Optional[str]:
    if value is None:
        return None
    return value.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace(
        "+00:00", "Z"
    )


def _utc_now_text() -> str:
    return _format_utc(_utc_now()) or ""


def _touch_session(user_id: str) -> None:
    now = _utc_now()
    TOKEN_LAST_ACTIVE[user_id] = now
    db = get_db()
    try:
        db.execute(
            "UPDATE users SET last_active_at=? WHERE id=?",
            (_format_utc(now), user_id),
        )
        db.commit()
    finally:
        db.close()


def _drop_session(user_id: str) -> None:
    TOKENS.pop(user_id, None)
    TOKEN_LAST_ACTIVE.pop(user_id, None)


def _online_user_ids(candidate_ids: Optional[Iterable[str]] = None) -> set[str]:
    cutoff = _utc_now() - timedelta(seconds=SESSION_ONLINE_SECONDS)
    ids = set(candidate_ids) if candidate_ids is not None else set(TOKENS.keys())
    return {
        user_id
        for user_id in ids
        if user_id in TOKENS
        and TOKEN_LAST_ACTIVE.get(user_id) is not None
        and TOKEN_LAST_ACTIVE[user_id] >= cutoff
    }


def _parse_server_time(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    text = str(value).strip()
    if not text:
        return None
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    elif "T" not in text:
        text = text.replace(" ", "T") + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _has_recent_user_activity(row, cutoff: datetime) -> bool:
    return any(
        parsed is not None and parsed >= cutoff
        for parsed in (
            _parse_server_time(row["last_active_at"]),
            _parse_server_time(row["last_login_at"]),
        )
    )


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def _admin_page_window(limit, offset, default_limit: int = 50, max_limit: int = 500) -> tuple[int, int]:
    try:
        next_limit = int(limit)
    except (TypeError, ValueError):
        next_limit = default_limit
    try:
        next_offset = int(offset)
    except (TypeError, ValueError):
        next_offset = 0
    next_limit = max(1, min(next_limit, max_limit))
    next_offset = max(0, next_offset)
    return next_limit, next_offset


def _admin_page_response(items: list, total: int, limit: int, offset: int) -> dict:
    return {
        "items": items,
        "total": int(total or 0),
        "limit": limit,
        "offset": offset,
        "has_more": offset + len(items) < int(total or 0),
    }


def _feedback_admin_filters(
    status: Optional[str] = None,
    q: Optional[str] = None,
    category: Optional[str] = None,
) -> tuple[str, list]:
    where_parts: list[str] = []
    params: list = []
    if status:
        where_parts.append("f.status=?")
        params.append(status)
    if category:
        where_parts.append("f.category=?")
        params.append(category)
    if q:
        where_parts.append(
            "(f.content LIKE ? OR f.admin_reply LIKE ? OR u.username LIKE ?)"
        )
        like = f"%{q}%"
        params.extend([like, like, like])
    where = f"WHERE {' AND '.join(where_parts)}" if where_parts else ""
    return where, params


def _feedback_admin_order_by(sort: str) -> str:
    return {
        "created_desc": "f.id DESC",
        "updated_desc": "f.updated_at DESC, f.id DESC",
        "status_asc": (
            "CASE f.status WHEN 'open' THEN 0 WHEN 'in_progress' THEN 1 "
            "WHEN 'resolved' THEN 2 ELSE 3 END, f.id DESC"
        ),
        "user_asc": "lower(u.username) ASC, f.id DESC",
    }.get(sort, "f.id DESC")


def _csv_safe(value) -> str:
    text = "" if value is None else str(value)
    if text and text[0] in ("=", "+", "-", "@", "\t", "\r", "\n"):
        return "'" + text
    return text


_BACKUP_BYTES_SQL = """
(length(sd.todos) + length(sd.habits) + length(sd.pomodoro_sessions)
 + length(sd.focus_penalties)
 + length(sd.pomodoro_config) + length(sd.user_profile)
 + length(sd.notes) + length(sd.countdowns) + length(sd.anniversaries)
 + length(sd.diaries) + length(sd.goals) + length(sd.calendar_events)
 + length(sd.courses) + length(sd.time_entries) + length(sd.course_settings)
 + length(sd.achievement_states) + length(sd.virtual_rewards)
 + length(sd.focus_rooms) + length(sd.theme_shop_state))
"""


def _backup_admin_filters(
    q: Optional[str] = None,
    status: Optional[str] = None,
) -> tuple[str, list]:
    where_parts: list[str] = []
    params: list = []
    if q:
        where_parts.append(
            "(u.username LIKE ? OR u.email LIKE ? OR u.display_name LIKE ? OR u.id LIKE ?)"
        )
        like = f"%{q}%"
        params.extend([like, like, like, like])
    if status == "synced":
        where_parts.append("sd.sync_version > 0")
    elif status == "empty":
        where_parts.append("(sd.user_id IS NULL OR sd.sync_version=0)")
    where = f"WHERE {' AND '.join(where_parts)}" if where_parts else ""
    return where, params


def _backup_admin_order_by(sort: str) -> str:
    return {
        "updated_desc": "sd.updated_at IS NULL, sd.updated_at DESC, u.created_at DESC",
        "username_asc": "lower(u.username) ASC",
        "size_desc": "bytes DESC, sd.updated_at DESC",
        "size_asc": "bytes ASC, sd.updated_at DESC",
        "version_desc": "sd.sync_version DESC, sd.updated_at DESC",
    }.get(sort, "sd.updated_at IS NULL, sd.updated_at DESC, u.created_at DESC")


def _server_backup_admin_filters(
    q: Optional[str] = None,
    status: Optional[str] = None,
) -> tuple[str, list]:
    where_parts: list[str] = []
    params: list = []
    if q:
        where_parts.append(
            "(filename LIKE ? OR status LIKE ? OR detail LIKE ? OR remote_url LIKE ? OR local_path LIKE ?)"
        )
        like = f"%{q}%"
        params.extend([like, like, like, like, like])
    if status:
        where_parts.append("status=?")
        params.append(status)
    where = f"WHERE {' AND '.join(where_parts)}" if where_parts else ""
    return where, params


def _server_backup_admin_order_by(sort: str) -> str:
    return {
        "created_desc": "created_at DESC, id DESC",
        "size_desc": "size_bytes DESC, created_at DESC",
        "size_asc": "size_bytes ASC, created_at DESC",
        "status_asc": "status ASC, created_at DESC",
        "filename_asc": "lower(filename) ASC, created_at DESC",
    }.get(sort, "created_at DESC, id DESC")


def _user_admin_filters(
    q: Optional[str] = None,
    status: Optional[str] = None,
) -> tuple[str, list]:
    where_parts: list[str] = []
    params: list = []
    if q:
        where_parts.append(
            "(u.username LIKE ? OR u.email LIKE ? OR u.display_name LIKE ? OR u.id LIKE ?)"
        )
        like = f"%{q}%"
        params.extend([like, like, like, like])
    if status == "admin":
        where_parts.append("u.is_admin=1")
    elif status == "disabled":
        where_parts.append("u.is_disabled=1")
    elif status == "active":
        where_parts.append("u.is_disabled=0")
    elif status == "normal":
        where_parts.append("u.is_admin=0 AND u.is_disabled=0")
    elif status == "unverified_email":
        where_parts.append("u.email<>'' AND u.email_verified=0")
    elif status == "verified_email":
        where_parts.append("u.email<>'' AND u.email_verified=1")
    elif status == "no_email":
        where_parts.append("u.email=''")
    elif status == "has_feedback":
        where_parts.append(
            "EXISTS (SELECT 1 FROM feedback f_filter WHERE f_filter.user_id=u.id)"
        )
    where = f"WHERE {' AND '.join(where_parts)}" if where_parts else ""
    return where, params


def _user_admin_order_by(sort: str) -> str:
    return {
        "created_desc": "u.created_at DESC",
        "last_active_desc": "u.last_active_at IS NULL, u.last_active_at DESC",
        "last_login_desc": "u.last_login_at IS NULL, u.last_login_at DESC",
        "feedback_desc": "fb_count DESC, u.created_at DESC",
        "username_asc": "lower(u.username) ASC",
        "email_asc": "u.email='', lower(u.email) ASC, lower(u.username) ASC",
    }.get(sort, "u.created_at DESC")


def init_db():
    conn = get_db()
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            username TEXT UNIQUE NOT NULL,
            email TEXT DEFAULT '',
            email_verified INTEGER DEFAULT 0,
            password_hash TEXT NOT NULL,
            avatar TEXT DEFAULT '',
            display_name TEXT DEFAULT '',
            bio TEXT DEFAULT '',
            is_admin INTEGER DEFAULT 0,
            is_disabled INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now')),
            last_login_at TEXT,
            last_active_at TEXT
        );
        CREATE TABLE IF NOT EXISTS sync_data (
            user_id TEXT PRIMARY KEY,
            todos TEXT DEFAULT '[]',
            habits TEXT DEFAULT '[]',
            pomodoro_sessions TEXT DEFAULT '[]',
            focus_penalties TEXT DEFAULT '[]',
            pomodoro_config TEXT DEFAULT '{}',
            user_profile TEXT DEFAULT '{}',
            notes TEXT DEFAULT '[]',
            countdowns TEXT DEFAULT '[]',
            anniversaries TEXT DEFAULT '[]',
            diaries TEXT DEFAULT '[]',
            goals TEXT DEFAULT '[]',
            calendar_events TEXT DEFAULT '[]',
            courses TEXT DEFAULT '[]',
            time_entries TEXT DEFAULT '[]',
            course_settings TEXT DEFAULT '{}',
            achievement_states TEXT DEFAULT '{}',
            virtual_rewards TEXT DEFAULT '{}',
            focus_rooms TEXT DEFAULT '{}',
            theme_shop_state TEXT DEFAULT '{}',
            deleted_items TEXT DEFAULT '{}',
            sync_version INTEGER DEFAULT 0,
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
            calendar_events TEXT DEFAULT '[]',
            updated_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS workspace_comments (
            id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL,
            target_id TEXT DEFAULT '',
            author_user_id TEXT NOT NULL,
            body TEXT NOT NULL,
            created_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
            FOREIGN KEY(author_user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS workspace_mentions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            workspace_id TEXT NOT NULL,
            comment_id TEXT NOT NULL,
            target_user_id TEXT NOT NULL,
            mentioned_by_user_id TEXT NOT NULL,
            read_at TEXT,
            created_at TEXT DEFAULT (datetime('now')),
            UNIQUE(comment_id, target_user_id),
            FOREIGN KEY(workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
            FOREIGN KEY(comment_id) REFERENCES workspace_comments(id) ON DELETE CASCADE,
            FOREIGN KEY(target_user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY(mentioned_by_user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS workspace_activity (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            workspace_id TEXT NOT NULL,
            actor_user_id TEXT NOT NULL,
            actor_name TEXT NOT NULL,
            action TEXT NOT NULL,
            detail TEXT DEFAULT '',
            created_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
            FOREIGN KEY(actor_user_id) REFERENCES users(id) ON DELETE CASCADE
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
        CREATE TABLE IF NOT EXISTS reminder_email_jobs (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            reminder_id INTEGER NOT NULL,
            schedule_kind TEXT NOT NULL,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            payload TEXT DEFAULT '',
            when_at TEXT,
            hour INTEGER,
            minute INTEGER,
            weekdays_json TEXT DEFAULT '[]',
            next_send_at TEXT,
            sent_at TEXT,
            cancelled INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS password_reset_tokens (
            token_hash TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            used_at TEXT,
            created_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS email_verification_codes (
            id TEXT PRIMARY KEY,
            user_id TEXT,
            email TEXT NOT NULL,
            purpose TEXT NOT NULL,
            code_hash TEXT NOT NULL,
            failure_count INTEGER DEFAULT 0,
            expires_at TEXT NOT NULL,
            consumed_at TEXT,
            locked_until TEXT,
            ip_address TEXT DEFAULT '',
            created_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS focus_room_presence (
            room_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            display_name TEXT DEFAULT '',
            raw_weekly_seconds INTEGER DEFAULT 0,
            weekly_seconds INTEGER DEFAULT 0,
            session_count INTEGER DEFAULT 0,
            active INTEGER DEFAULT 1,
            started_at TEXT,
            last_seen_at TEXT,
            risk_flags TEXT DEFAULT '[]',
            risk_summary TEXT DEFAULT '',
            updated_at TEXT DEFAULT (datetime('now')),
            PRIMARY KEY(room_id, user_id),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS focus_room_invites (
            id TEXT PRIMARY KEY,
            room_id TEXT NOT NULL,
            code TEXT UNIQUE NOT NULL,
            room_name TEXT NOT NULL,
            description TEXT DEFAULT '',
            weekly_target_seconds INTEGER DEFAULT 18000,
            accent_color INTEGER DEFAULT 3762608,
            created_by TEXT NOT NULL,
            expires_at TEXT,
            max_uses INTEGER DEFAULT 0,
            used_count INTEGER DEFAULT 0,
            last_used_at TEXT,
            revoked INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(created_by) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS focus_friends (
            user_id TEXT NOT NULL,
            friend_user_id TEXT NOT NULL,
            status TEXT DEFAULT 'accepted',
            created_at TEXT DEFAULT (datetime('now')),
            PRIMARY KEY(user_id, friend_user_id),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY(friend_user_id) REFERENCES users(id) ON DELETE CASCADE,
            CHECK(user_id <> friend_user_id)
        );
        CREATE TABLE IF NOT EXISTS focus_friend_request_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            friend_user_id TEXT NOT NULL,
            created_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY(friend_user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        """
    )

    # Schema migrations
    for table, col, default in [
        ("sync_data", "pomodoro_sessions", "'[]'"),
        ("sync_data", "focus_penalties", "'[]'"),
        ("sync_data", "pomodoro_config", "'{}'"),
        ("sync_data", "user_profile", "'{}'"),
        ("sync_data", "notes", "'[]'"),
        ("sync_data", "countdowns", "'[]'"),
        ("sync_data", "anniversaries", "'[]'"),
        ("sync_data", "diaries", "'[]'"),
        ("sync_data", "goals", "'[]'"),
        ("sync_data", "calendar_events", "'[]'"),
        ("sync_data", "courses", "'[]'"),
        ("sync_data", "time_entries", "'[]'"),
        ("sync_data", "course_settings", "'{}'"),
        ("sync_data", "achievement_states", "'{}'"),
        ("sync_data", "virtual_rewards", "'{}'"),
        ("sync_data", "focus_rooms", "'{}'"),
        ("sync_data", "theme_shop_state", "'{}'"),
        ("sync_data", "deleted_items", "'{}'"),
        ("sync_data", "sync_version", "0"),
        ("workspace_data", "calendar_events", "'[]'"),
        ("users", "is_disabled", "0"),
        ("users", "last_login_at", "NULL"),
        ("users", "last_active_at", "NULL"),
        ("users", "email", "''"),
        ("users", "email_verified", "0"),
        ("users", "display_name", "''"),
        ("users", "bio", "''"),
        ("invite_codes", "note", "''"),
        ("announcements", "updated_at", "datetime('now')"),
        ("focus_room_presence", "display_name", "''"),
        ("focus_room_presence", "raw_weekly_seconds", "0"),
        ("focus_room_presence", "weekly_seconds", "0"),
        ("focus_room_presence", "session_count", "0"),
        ("focus_room_presence", "active", "1"),
        ("focus_room_presence", "started_at", "NULL"),
        ("focus_room_presence", "last_seen_at", "NULL"),
        ("focus_room_presence", "risk_flags", "'[]'"),
        ("focus_room_presence", "risk_summary", "''"),
        ("focus_room_presence", "updated_at", "datetime('now')"),
        ("focus_room_invites", "description", "''"),
        ("focus_room_invites", "weekly_target_seconds", "18000"),
        ("focus_room_invites", "accent_color", "3762608"),
        ("focus_room_invites", "expires_at", "NULL"),
        ("focus_room_invites", "max_uses", "0"),
        ("focus_room_invites", "used_count", "0"),
        ("focus_room_invites", "last_used_at", "NULL"),
        ("focus_room_invites", "revoked", "0"),
        ("focus_friends", "status", "'accepted'"),
        ("focus_friends", "created_at", "datetime('now')"),
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

    conn.execute(
        "UPDATE users SET email=username WHERE email='' AND username LIKE '%@%'"
    )
    conn.execute(
        "UPDATE users SET email_verified=1 WHERE email<>'' AND username=email AND email_verified=0"
    )
    conn.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_nonempty "
        "ON users(email) WHERE email <> ''"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_email_verification_codes_email_purpose "
        "ON email_verification_codes(email, purpose, created_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_email_verification_codes_user_purpose "
        "ON email_verification_codes(user_id, purpose, created_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_users_created_at "
        "ON users(created_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_users_admin_disabled_created "
        "ON users(is_admin, is_disabled, created_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_users_last_login_at "
        "ON users(last_login_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_users_last_active_at "
        "ON users(last_active_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_feedback_status_category_id "
        "ON feedback(status, category, id)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_feedback_user_id "
        "ON feedback(user_id)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_announcements_published_level_id "
        "ON announcements(published, level, id)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_invite_codes_used_created "
        "ON invite_codes(used_by, created_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_audit_log_action_id "
        "ON audit_log(action, id)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_server_backups_status_created "
        "ON server_backups(status, created_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_sync_data_updated_at "
        "ON sync_data(updated_at)"
    )

    default_registration_enabled = _env_bool("ALLOW_PUBLIC_REGISTRATION", default=True)
    existing_registration_enabled = conn.execute(
        "SELECT value FROM settings WHERE key=?", ("registration_enabled",)
    ).fetchone()
    if existing_registration_enabled is not None:
        try:
            default_registration_enabled = bool(json.loads(existing_registration_enabled["value"]))
        except Exception:
            default_registration_enabled = str(
                existing_registration_enabled["value"]
            ).strip().lower() in {"1", "true", "yes", "on"}
    default_invite_code_required = os.getenv(
        "INVITE_CODE_REQUIRED", "false"
    ).lower() in {"1", "true", "yes"}
    existing_invite_code_required = conn.execute(
        "SELECT value FROM settings WHERE key=?", ("invite_code_required",)
    ).fetchone()
    if existing_invite_code_required is not None:
        try:
            default_invite_code_required = bool(json.loads(existing_invite_code_required["value"]))
        except Exception:
            default_invite_code_required = str(
                existing_invite_code_required["value"]
            ).strip().lower() in {"1", "true", "yes", "on"}

    # Default settings
    default_settings = {
        "invite_code_required": default_invite_code_required,
        "allow_public_registration": default_registration_enabled,
        "registration_invite_required": _env_bool(
            "REGISTRATION_INVITE_REQUIRED",
            default=default_invite_code_required,
        ),
        "registration_enabled": default_registration_enabled,
        "registration_email_required": _env_bool("REGISTRATION_EMAIL_REQUIRED", default=False),
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
        # 用户邮件提醒：优先投递到用户登录名中的 email；否则使用 reminder_email_to。
        "reminder_email_enabled": os.getenv("REMINDER_EMAIL_ENABLED", "false").lower() in {"1", "true", "yes"},
        "reminder_email_to": os.getenv("REMINDER_EMAIL_TO", ""),
        "reminder_email_from": os.getenv("REMINDER_EMAIL_FROM", os.getenv("EMAIL_SMTP_USERNAME", "")),
        "reminder_email_smtp_host": os.getenv("REMINDER_EMAIL_SMTP_HOST", os.getenv("EMAIL_SMTP_HOST", "")),
        "reminder_email_smtp_port": int(os.getenv("REMINDER_EMAIL_SMTP_PORT", os.getenv("EMAIL_SMTP_PORT", "465"))),
        "reminder_email_smtp_username": os.getenv("REMINDER_EMAIL_SMTP_USERNAME", os.getenv("EMAIL_SMTP_USERNAME", "")),
        "reminder_email_smtp_password": os.getenv("REMINDER_EMAIL_SMTP_PASSWORD", os.getenv("EMAIL_SMTP_PASSWORD", "")),
        "reminder_email_smtp_use_ssl": os.getenv("REMINDER_EMAIL_SMTP_USE_SSL", os.getenv("EMAIL_SMTP_USE_SSL", "true")).lower() in {"1", "true", "yes"},
        # 账号邮箱验证码：兼容 RE0/网关的 openclaw/resend/smtp/email_code 配置，同时保留上面的 duoyi 备份/提醒邮件配置。
        "email_service_enabled": _env_bool("EMAIL_SERVICE_ENABLED", default=True),
        "email_sender_name": _env_any("EMAIL_SENDER_NAME", default=DEFAULT_EMAIL_SENDER_NAME),
        "email_code_primary_provider": _env_any("EMAIL_CODE_PRIMARY_PROVIDER", default="claw163"),
        "email_code_backup_provider": _env_any("EMAIL_CODE_BACKUP_PROVIDER", default="resend"),
        "email_code_active_slot": _env_any("EMAIL_CODE_ACTIVE_SLOT", default="primary"),
        "email_auto_switch_enabled": _env_bool("EMAIL_AUTO_SWITCH_ENABLED", default=False),
        "openclaw_mail_enabled": _env_bool("OPENCLAW_MAIL_ENABLED", default=False),
        "openclaw_mail_user": _env_any("OPENCLAW_MAIL_USER", "OPENCLAW_MAIL_USERNAME"),
        "openclaw_mail_api_key": _env_any("OPENCLAW_MAIL_API_KEY", "OPENCLAW_MAIL_KEY"),
        "resend_base_url": _env_any("RESEND_BASE_URL", default="https://api.resend.com"),
        "resend_api_key": _env_any("RESEND_API_KEY"),
        "resend_from": _env_any("RESEND_FROM", default=DEFAULT_RESEND_FROM),
        "hermes_base_url": _env_any("HERMES_BASE_URL"),
        "hermes_api_key": _env_any("HERMES_API_KEY"),
        "system_notice_email_to": _env_any("SYSTEM_NOTICE_EMAIL_TO"),
        "email_smtp_host": _env_any("EMAIL_SMTP_HOST"),
        "email_smtp_port": _env_int("EMAIL_SMTP_PORT", default=465),
        "email_smtp_username": _env_any("EMAIL_SMTP_USERNAME", "EMAIL_ADDRESS"),
        "email_smtp_password": _env_any("EMAIL_SMTP_PASSWORD", "EMAIL_PASSWORD"),
        "email_smtp_use_ssl": _env_bool("EMAIL_SMTP_USE_SSL", default=True),
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


PASSWORD_HASH_SALT = os.getenv("PASSWORD_HASH_SALT", "duoyi_2026")


def _legacy_password_salt() -> str:
    return base64.b64decode("ZmluZ2VydGlwX3RpbWVfMjAyNg==").decode()


def _hash_password(password: str, salt: str = PASSWORD_HASH_SALT) -> str:
    return hashlib.sha256((salt + password).encode()).hexdigest()


def _legacy_hash_password(password: str) -> str:
    return _hash_password(password, _legacy_password_salt())


def _hash_reset_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _hash_email_code(code: str) -> str:
    return _hash_reset_token((code or "").strip())


def _normalize_email_code_provider(value: Optional[str]) -> str:
    provider = (value or "none").strip().lower()
    if provider == "openclaw":
        provider = "claw163"
    if provider == "openclaw_mail":
        provider = "claw163"
    return provider if provider in EMAIL_CODE_PROVIDERS else "none"


def _normalize_email_code_slot(value: Optional[str]) -> str:
    slot = (value or "primary").strip().lower()
    return slot if slot in EMAIL_CODE_SLOTS else "primary"


def _registration_enabled(db) -> bool:
    return bool(
        _setting_get(
            db,
            "allow_public_registration",
            _setting_get(db, "registration_enabled", True),
        )
    )


def _registration_invite_required(db) -> bool:
    return bool(
        _setting_get(
            db,
            "registration_invite_required",
            _setting_get(db, "invite_code_required", False),
        )
    )


def _looks_like_email(value: str) -> bool:
    return bool(re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", value.strip()))


def _clean_username(value: str) -> str:
    username = (value or "").strip()
    if not 3 <= len(username) <= 64:
        raise HTTPException(status_code=400, detail="用户名需为 3-64 个字符")
    if re.search(r"\s", username):
        raise HTTPException(status_code=400, detail="用户名不能包含空白字符")
    return username


def _clean_password(value: str) -> str:
    password = value or ""
    if len(password) < 6:
        raise HTTPException(status_code=400, detail="密码至少 6 位")
    if len(password) > 128:
        raise HTTPException(status_code=400, detail="密码过长")
    return password


def _clean_email(value: Optional[str]) -> str:
    email = (value or "").strip().lower()
    if not email:
        return ""
    if not _looks_like_email(email):
        raise HTTPException(status_code=400, detail="邮箱格式不正确")
    if len(email) > 128:
        raise HTTPException(status_code=400, detail="邮箱过长")
    return email


def _clean_short_text(value: Optional[str], max_len: int, field: str) -> str:
    text = (value or "").strip()
    if len(text) > max_len:
        raise HTTPException(status_code=400, detail=f"{field}不能超过 {max_len} 字")
    return text


def _find_user_by_identifier(db, identifier: str):
    value = (identifier or "").strip()
    if not value:
        return None
    lowered = value.lower()
    return db.execute(
        "SELECT * FROM users WHERE username=? OR lower(username)=? OR lower(email)=?",
        (value, lowered, lowered),
    ).fetchone()


def _ensure_account_unique(
    db,
    *,
    username: Optional[str] = None,
    email: Optional[str] = None,
    exclude_user_id: Optional[str] = None,
) -> None:
    checks = []
    params: list = []
    if username:
        checks.append("lower(username)=?")
        params.append(username.lower())
        checks.append("lower(email)=?")
        params.append(username.lower())
    if email:
        checks.append("lower(email)=?")
        params.append(email.lower())
        checks.append("lower(username)=?")
        params.append(email.lower())
    if not checks:
        return
    sql = "SELECT id FROM users WHERE (" + " OR ".join(checks) + ")"
    if exclude_user_id:
        sql += " AND id<>?"
        params.append(exclude_user_id)
    row = db.execute(sql, params).fetchone()
    if row is not None:
        raise HTTPException(status_code=409, detail="用户名或邮箱已被使用")


def _user_response(row, *, token: Optional[str] = None) -> dict:
    result = {
        "user_id": row["id"],
        "username": row["username"],
        "email": row["email"] or "",
        "email_verified": bool(row["email_verified"]),
        "avatar": row["avatar"] or "",
        "display_name": row["display_name"] or "",
        "bio": row["bio"] or "",
        "is_admin": bool(row["is_admin"]),
        "is_disabled": bool(row["is_disabled"]),
        "created_at": row["created_at"],
        "last_login_at": row["last_login_at"],
    }
    if token is not None:
        result["token"] = token
    return result


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


def _first_setting(db, keys: list[str], default=""):
    for key in keys:
        value = _setting_get(db, key, None)
        if value is not None and str(value).strip() != "":
            return value
    return default


def _account_mail_runtime(db) -> dict:
    smtp_host = _first_setting(
        db,
        [
            "email_smtp_host",
            "reminder_email_smtp_host",
            "backup_email_smtp_host",
        ],
        "",
    )
    smtp_port = _first_setting(
        db,
        [
            "email_smtp_port",
            "reminder_email_smtp_port",
            "backup_email_smtp_port",
        ],
        465,
    )
    smtp_username = _first_setting(
        db,
        [
            "email_smtp_username",
            "reminder_email_smtp_username",
            "backup_email_smtp_username",
        ],
        "",
    )
    smtp_password = _first_setting(
        db,
        [
            "email_smtp_password",
            "reminder_email_smtp_password",
            "backup_email_smtp_password",
        ],
        "",
    )
    smtp_use_ssl = _setting_get(db, "email_smtp_use_ssl", None)
    if smtp_use_ssl is None:
        smtp_use_ssl = _setting_get(db, "reminder_email_smtp_use_ssl", None)
    if smtp_use_ssl is None:
        smtp_use_ssl = _setting_get(db, "backup_email_smtp_use_ssl", True)
    return {
        "email_service_enabled": bool(
            _setting_get(db, "email_service_enabled", True)
        ),
        "email_sender_name": str(
            _setting_get(db, "email_sender_name", DEFAULT_EMAIL_SENDER_NAME)
            or DEFAULT_EMAIL_SENDER_NAME
        ),
        "email_code_primary_provider": _normalize_email_code_provider(
            _setting_get(db, "email_code_primary_provider", "claw163")
        ),
        "email_code_backup_provider": _normalize_email_code_provider(
            _setting_get(db, "email_code_backup_provider", "resend")
        ),
        "email_code_active_slot": _normalize_email_code_slot(
            _setting_get(db, "email_code_active_slot", "primary")
        ),
        "email_auto_switch_enabled": bool(
            _setting_get(db, "email_auto_switch_enabled", False)
        ),
        "openclaw_mail_enabled": bool(_setting_get(db, "openclaw_mail_enabled", False)),
        "openclaw_mail_user": str(_setting_get(db, "openclaw_mail_user", "") or ""),
        "openclaw_mail_api_key": str(_setting_get(db, "openclaw_mail_api_key", "") or ""),
        "resend_base_url": str(
            _setting_get(db, "resend_base_url", "https://api.resend.com")
            or "https://api.resend.com"
        ).rstrip("/"),
        "resend_api_key": str(_setting_get(db, "resend_api_key", "") or ""),
        "resend_from": str(_setting_get(db, "resend_from", DEFAULT_RESEND_FROM) or ""),
        "hermes_base_url": str(_setting_get(db, "hermes_base_url", "") or "").rstrip("/"),
        "hermes_api_key": str(_setting_get(db, "hermes_api_key", "") or ""),
        "system_notice_email_to": str(_setting_get(db, "system_notice_email_to", "") or ""),
        "email_smtp_host": str(smtp_host or ""),
        "email_smtp_port": int(smtp_port or 465),
        "email_smtp_username": str(smtp_username or ""),
        "email_smtp_password": str(smtp_password or ""),
        "email_smtp_use_ssl": bool(smtp_use_ssl),
        "email_smtp_from": str(
            _first_setting(
                db,
                [
                    "email_smtp_from",
                    "reminder_email_from",
                    "backup_email_from",
                ],
                "",
            )
            or ""
        ),
    }


def _audit(db, actor_id: Optional[str], actor_name: Optional[str], action: str,
           target: str = "", detail: str = "") -> None:
    db.execute(
        "INSERT INTO audit_log(actor_id, actor_name, action, target, detail) VALUES(?,?,?,?,?)",
        (actor_id, actor_name, action, target, detail),
    )


def _workspace_activity(
    db,
    actor_id: str,
    action: str,
    workspace_id: str,
    detail: str = "",
) -> None:
    db.execute(
        """
        INSERT INTO workspace_activity(workspace_id, actor_user_id, actor_name, action, detail)
        VALUES(?,?,?,?,?)
        """,
        (workspace_id, actor_id, _get_username(db, actor_id), action, detail),
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


def _verify_token_value(token: Optional[str]) -> str:
    if not token:
        raise HTTPException(status_code=401, detail="Missing token")
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
    email: Optional[str] = None
    email_code: Optional[str] = None
    display_name: Optional[str] = None
    invite_code: Optional[str] = None
    invitation_code: Optional[str] = None


class LoginRequest(BaseModel):
    username: Optional[str] = None
    account: Optional[str] = None
    email: Optional[str] = None
    password: str


class ProfileUpdate(BaseModel):
    username: Optional[str] = None
    email: Optional[str] = None
    email_code: Optional[str] = None
    display_name: Optional[str] = None
    avatar: Optional[str] = None
    bio: Optional[str] = None


class EmailCodeRequest(BaseModel):
    email: str
    purpose: str = "login"


class EmailLoginRequest(BaseModel):
    email: str
    code: str


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: Optional[str] = None
    password: Optional[str] = None


class PasswordResetRequest(BaseModel):
    username: Optional[str] = None
    identifier: Optional[str] = None
    account: Optional[str] = None
    email: Optional[str] = None


class PasswordResetConfirm(BaseModel):
    token: Optional[str] = None
    code: Optional[str] = None
    username: Optional[str] = None
    identifier: Optional[str] = None
    account: Optional[str] = None
    email: Optional[str] = None
    password: Optional[str] = None
    new_password: Optional[str] = None


class SyncRequest(BaseModel):
    todos: list = []
    habits: list = []
    pomodoro_sessions: list = []
    focus_penalties: list = []
    pomodoro_config: dict = {}
    user_profile: dict = {}
    # —— 对齐竞品能力所需的新数据类型 ——
    notes: list = []
    countdowns: list = []
    anniversaries: list = []
    diaries: list = []
    goals: list = []
    calendar_events: list = []
    courses: list = []
    time_entries: list = []
    course_settings: dict = {}
    achievement_states: dict = {}
    virtual_rewards: dict = {}
    focus_rooms: dict = {}
    theme_shop_state: dict = {}
    deleted_items: dict = {}
    workspace_payloads: dict = {}


class SyncPullRequest(BaseModel):
    collection_hashes: dict = {}


class SyncDeltaRequest(BaseModel):
    collections: dict = {}
    collection_hashes: dict = {}


class SyncItemDeltaRequest(BaseModel):
    items: dict = {}
    objects: dict = {}
    deleted_items: dict = {}
    collection_hashes: dict = {}


class FocusRoomHeartbeatRequest(BaseModel):
    display_name: Optional[str] = None
    weekly_seconds: int = 0
    session_count: int = 0
    active: bool = True
    started_at: Optional[str] = None


class FocusRoomInviteCreate(BaseModel):
    room_name: str
    description: str = ""
    weekly_target_seconds: int = 18000
    accent_color: int = 0xFF3949AB
    expires_at: Optional[str] = None
    max_uses: Optional[int] = None


class FocusRoomInviteAccept(BaseModel):
    display_name: Optional[str] = None


class FocusFriendCreate(BaseModel):
    username: Optional[str] = None
    user_id: Optional[str] = None


class WorkspaceCreate(BaseModel):
    name: str


class WorkspaceUpdate(BaseModel):
    name: Optional[str] = None


class WorkspaceInviteCreate(BaseModel):
    role: str = "viewer"
    expires_at: Optional[str] = None


class WorkspaceMemberUpdate(BaseModel):
    role: str


class WorkspaceCommentCreate(BaseModel):
    body: str
    target_id: Optional[str] = None


class FeedbackCreate(BaseModel):
    category: str = "feature"
    content: str


class FeedbackReply(BaseModel):
    feedback_id: int
    reply: str
    status: str = "resolved"


class FeedbackBulkStatus(BaseModel):
    feedback_ids: list[int]
    reply: str
    status: str = "in_progress"


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


class UserBulkStatus(BaseModel):
    user_ids: list[str]
    is_disabled: bool


class BackupBulkWipe(BaseModel):
    user_ids: list[str]


class SettingsUpdate(BaseModel):
    invite_code_required: Optional[bool] = None
    allow_public_registration: Optional[bool] = None
    registration_invite_required: Optional[bool] = None
    registration_enabled: Optional[bool] = None
    registration_email_required: Optional[bool] = None
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
    # 邮件提醒
    reminder_email_enabled: Optional[bool] = None
    reminder_email_to: Optional[str] = None
    reminder_email_from: Optional[str] = None
    reminder_email_smtp_host: Optional[str] = None
    reminder_email_smtp_port: Optional[int] = None
    reminder_email_smtp_username: Optional[str] = None
    reminder_email_smtp_password: Optional[str] = None
    reminder_email_smtp_use_ssl: Optional[bool] = None
    # 账号邮箱验证码邮件通道，兼容 RE0/boxying-image-gateway 字段
    email_service_enabled: Optional[bool] = None
    email_sender_name: Optional[str] = None
    email_code_primary_provider: Optional[str] = None
    email_code_backup_provider: Optional[str] = None
    email_code_active_slot: Optional[str] = None
    email_auto_switch_enabled: Optional[bool] = None
    openclaw_mail_enabled: Optional[bool] = None
    openclaw_mail_user: Optional[str] = None
    openclaw_mail_api_key: Optional[str] = None
    resend_base_url: Optional[str] = None
    resend_api_key: Optional[str] = None
    resend_from: Optional[str] = None
    hermes_base_url: Optional[str] = None
    hermes_api_key: Optional[str] = None
    system_notice_email_to: Optional[str] = None
    email_smtp_host: Optional[str] = None
    email_smtp_port: Optional[int] = None
    email_smtp_username: Optional[str] = None
    email_smtp_password: Optional[str] = None
    email_smtp_use_ssl: Optional[bool] = None


class AiChatRequest(BaseModel):
    system: str = ""
    user: str
    temperature: float = 0.4
    max_tokens: int = 512


class ReminderEmailOnceRequest(BaseModel):
    id: int
    title: str
    body: str
    when: str
    payload: Optional[str] = None


class ReminderEmailRepeatingRequest(BaseModel):
    id: int
    title: str
    body: str
    hour: int
    minute: int
    weekdays: Optional[list[int]] = None
    payload: Optional[str] = None


# ---- Public ----


@app.get("/api/health")
def health():
    db = get_db()
    try:
        return {
            "status": "ok",
            "version": "3.1.0",
            "invite_required": _registration_invite_required(db),
            "maintenance": _setting_get(db, "maintenance_mode", False),
            "time": datetime.now(timezone.utc).isoformat(),
        }
    finally:
        db.close()


@app.get("/api/config")
def public_config():
    db = get_db()
    try:
        registration_enabled = _registration_enabled(db)
        invite_required = _registration_invite_required(db)
        return {
            "invite_code_required": invite_required,
            "registration_invite_required": invite_required,
            "registration_enabled": registration_enabled,
            "allow_public_registration": registration_enabled,
            "registration_email_required": _setting_get(db, "registration_email_required", False),
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


@app.get("/api/bootstrap")
def bootstrap_config():
    cfg = public_config()
    return {
        "app_name": "多仪",
        "ui_title": "多仪",
        **cfg,
    }


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


@app.post("/api/admin/reminders/email/test")
def admin_reminder_email_test(actor: str = Depends(_require_admin)):
    """发送一封极短测试邮件，验证邮件提醒 SMTP 配置可用。"""
    db = get_db()
    try:
        _send_reminder_email(
            db,
            actor,
            "多仪邮件提醒测试",
            "如果你收到这封邮件，说明多仪邮件提醒 SMTP 投递配置可用。",
        )
        return {"ok": True, "recipient": _reminder_email_recipient(db, actor)}
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"邮件提醒测试失败: {e}")
    finally:
        db.close()


@app.post("/api/admin/account-email/test")
def admin_account_email_test(actor: str = Depends(_require_admin)):
    """发送一封极短测试邮件，验证账号验证码邮件主备通道可用。"""
    db = get_db()
    try:
        recipient = _account_email_test_recipient(db, actor)
        if not recipient:
            raise HTTPException(
                status_code=503,
                detail="管理员账号未绑定邮箱，也未配置系统通知收件人",
            )
        result = _send_account_email(
            db,
            to_addr=recipient,
            subject="多仪账号邮件测试",
            body="如果你收到这封邮件，说明多仪账号验证码邮件通道可用。",
            html="<p>如果你收到这封邮件，说明多仪账号验证码邮件通道可用。</p>",
        )
        if not result.get("sent"):
            raise HTTPException(
                status_code=503,
                detail=str(
                    result.get("detail")
                    or result.get("message")
                    or "账号邮件测试失败",
                ),
            )
        _audit(
            db,
            actor,
            _get_username(db, actor),
            "account_email.test",
            target=recipient,
            detail=f"{result.get('slot') or ''}/{result.get('provider') or ''}",
        )
        db.commit()
        return {
            "ok": True,
            "recipient": recipient,
            "provider": result.get("provider") or "",
            "slot": result.get("slot") or "",
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"账号邮件测试失败: {e}")
    finally:
        db.close()


@app.get("/api/admin/backups")
def admin_backups(
    _: str = Depends(_require_admin),
    q: Optional[str] = None,
    status: Optional[str] = None,
    sort: str = "updated_desc",
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    """列出每个用户最近一次备份的时间 + 估算大小。"""
    limit, offset = _admin_page_window(limit, offset)
    db = get_db()
    try:
        where, params = _backup_admin_filters(q=q, status=status)
        order_by = _backup_admin_order_by(sort)
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM users u LEFT JOIN sync_data sd ON sd.user_id = u.id {where}",
            params,
        ).fetchone()["c"]
        rows = db.execute(
            f"""
            SELECT u.id, u.username, u.email, u.display_name,
                   sd.updated_at, COALESCE(sd.sync_version, 0) AS sync_version,
                   {_BACKUP_BYTES_SQL} AS bytes
            FROM users u LEFT JOIN sync_data sd ON sd.user_id = u.id
            {where}
            ORDER BY {order_by}
            LIMIT ? OFFSET ?
            """
            ,
            (*params, limit, offset),
        ).fetchall()
        items = [
            {
                "user_id": r["id"],
                "username": r["username"],
                "email": r["email"],
                "display_name": r["display_name"],
                "updated_at": r["updated_at"],
                "sync_version": r["sync_version"],
                "has_snapshot": int(r["sync_version"] or 0) > 0,
                "size_kb": ((r["bytes"] or 0) + 1023) // 1024,
            }
            for r in rows
        ]
        return _admin_page_response(items, total, limit, offset)
    finally:
        db.close()


@app.get("/api/admin/backups/export.csv")
def export_backups_csv(
    actor: str = Depends(_require_admin),
    q: Optional[str] = None,
    status: Optional[str] = None,
    sort: str = "updated_desc",
    limit: int = Query(5000, ge=1, le=20000),
):
    """导出当前筛选下的用户云端备份索引，便于大量用户离线审计。"""
    limit, _offset = _admin_page_window(limit, 0, default_limit=5000, max_limit=20000)
    db = get_db()
    try:
        where, params = _backup_admin_filters(q=q, status=status)
        order_by = _backup_admin_order_by(sort)
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM users u LEFT JOIN sync_data sd ON sd.user_id = u.id {where}",
            params,
        ).fetchone()["c"]
        rows = db.execute(
            f"""
            SELECT u.id, u.username, u.email, u.display_name,
                   sd.updated_at, COALESCE(sd.sync_version, 0) AS sync_version,
                   {_BACKUP_BYTES_SQL} AS bytes
            FROM users u LEFT JOIN sync_data sd ON sd.user_id = u.id
            {where}
            ORDER BY {order_by}
            LIMIT ?
            """,
            (*params, limit),
        ).fetchall()
        buffer = io.StringIO()
        writer = csv.writer(buffer)
        writer.writerow(
            [
                "user_id",
                "username",
                "email",
                "display_name",
                "updated_at",
                "sync_version",
                "has_snapshot",
                "size_kb",
            ]
        )
        for row in rows:
            sync_version = int(row["sync_version"] or 0)
            size_kb = ((row["bytes"] or 0) + 1023) // 1024
            writer.writerow(
                [
                    _csv_safe(row["id"]),
                    _csv_safe(row["username"]),
                    _csv_safe(row["email"]),
                    _csv_safe(row["display_name"]),
                    _csv_safe(row["updated_at"]),
                    sync_version,
                    int(sync_version > 0),
                    size_kb,
                ]
            )
        _audit(
            db,
            actor,
            _get_username(db, actor),
            "backup.export",
            detail=json.dumps(
                {
                    "status": status or "",
                    "q": q or "",
                    "sort": sort,
                    "rows": len(rows),
                    "total": int(total or 0),
                },
                ensure_ascii=False,
            ),
        )
        db.commit()
        content = "\ufeff" + buffer.getvalue()
        filename = f"duoyi_backups_{_utc_now().strftime('%Y%m%d_%H%M%S')}.csv"
        headers = {
            "Content-Disposition": f'attachment; filename="{filename}"',
            "X-Total-Count": str(int(total or 0)),
            "X-Exported-Count": str(len(rows)),
        }
        return StreamingResponse(
            iter([content]),
            media_type="text/csv; charset=utf-8",
            headers=headers,
        )
    finally:
        db.close()


@app.delete("/api/admin/backups/{user_id}")
def admin_backup_wipe(user_id: str, actor: str = Depends(_require_admin)):
    """清空某用户的所有云端备份(账号保留)。"""
    db = get_db()
    try:
        db.execute(
            "UPDATE sync_data SET todos='[]', habits='[]', pomodoro_sessions='[]', "
            "focus_penalties='[]', pomodoro_config='{}', user_profile='{}', "
            "notes='[]', countdowns='[]', "
            "anniversaries='[]', diaries='[]', goals='[]', calendar_events='[]', "
            "courses='[]', time_entries='[]', course_settings='{}', achievement_states='{}', "
            "virtual_rewards='{}', focus_rooms='{}', theme_shop_state='{}', deleted_items='{}', "
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


def _smtp_send(
    *,
    host: str,
    port: int,
    username: str,
    password: str,
    use_ssl: bool,
    from_addr: str,
    to_addr: str,
    subject: str,
    body: str,
) -> None:
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


def _email_smtp_send(
    *,
    runtime: dict,
    to_addr: str,
    subject: str,
    body: str,
    html: str = "",
) -> dict:
    host = str(runtime.get("email_smtp_host") or "").strip()
    username = str(runtime.get("email_smtp_username") or "").strip()
    password = str(runtime.get("email_smtp_password") or "")
    if not (host and username and password):
        return {"sent": False, "detail": "SMTP 未完整配置"}
    from_addr = str(runtime.get("email_smtp_from") or "").strip() or username
    sender_name = str(runtime.get("email_sender_name") or "").strip()
    _smtp_send(
        host=host,
        port=int(runtime.get("email_smtp_port") or 465),
        username=username,
        password=password,
        use_ssl=bool(runtime.get("email_smtp_use_ssl", True)),
        from_addr=formataddr((sender_name, from_addr)) if sender_name else from_addr,
        to_addr=to_addr,
        subject=subject,
        body=body,
    )
    return {"sent": True, "provider": "smtp"}


def _hermes_send_email(
    *,
    runtime: dict,
    to_addr: str,
    subject: str,
    body: str,
    html: str = "",
) -> dict:
    base_url = str(runtime.get("hermes_base_url") or "").strip().rstrip("/")
    api_key = str(runtime.get("hermes_api_key") or "").strip()
    if not (base_url and api_key):
        return {"sent": False, "detail": "Hermes 未完整配置"}
    parsed = urllib.parse.urlparse(base_url)
    if parsed.path.rstrip("/").endswith(
        ("/send", "/email/send", "/api/send", "/api/email/send", "/api/notifications/email")
    ):
        urls = [base_url]
    elif parsed.path and parsed.path != "/":
        urls = [
            base_url,
            f"{base_url}/send",
            f"{base_url}/email/send",
            f"{base_url}/api/send",
            f"{base_url}/api/email/send",
            f"{base_url}/api/notifications/email",
        ]
    else:
        urls = [
            f"{base_url}/send",
            f"{base_url}/email/send",
            f"{base_url}/api/send",
            f"{base_url}/api/email/send",
            f"{base_url}/api/notifications/email",
            base_url,
        ]
    headers = {"Content-Type": "application/json"}
    if ":" in api_key and not api_key.lower().startswith("bearer "):
        headers["Authorization"] = "Basic " + base64.b64encode(
            api_key.encode("utf-8")
        ).decode("ascii")
    else:
        token = api_key[7:].strip() if api_key.lower().startswith("bearer ") else api_key
        headers["Authorization"] = f"Bearer {token}"
    payload = json.dumps(
        {
            "to": to_addr,
            "email": to_addr,
            "subject": subject,
            "title": subject,
            "text": body,
            "body": body,
            "html": html or body,
        },
        ensure_ascii=False,
    ).encode("utf-8")
    errors: list[str] = []
    for url in dict.fromkeys(urls):
        req = urllib.request.Request(
            url,
            data=payload,
            headers=headers,
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                if 200 <= resp.status < 300:
                    return {"sent": True, "provider": "hermes"}
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", errors="replace")[:500]
            errors.append(f"{url}: HTTP {e.code}: {detail}")
            if e.code not in {404, 405}:
                break
        except Exception as e:
            errors.append(f"{url}: {e}")
    return {"sent": False, "detail": "; ".join(errors)}


def _resend_send_email(
    *,
    runtime: dict,
    to_addr: str,
    subject: str,
    body: str,
    html: str = "",
) -> dict:
    base_url = str(runtime.get("resend_base_url") or "https://api.resend.com").strip().rstrip("/")
    api_key = str(runtime.get("resend_api_key") or "").strip()
    from_addr = str(runtime.get("resend_from") or "").strip()
    if not (base_url and api_key and from_addr):
        return {"sent": False, "detail": "Resend 未完整配置"}
    if "<" not in from_addr and "@" in from_addr:
        sender_name = str(runtime.get("email_sender_name") or "").strip()
        if sender_name:
            from_addr = f"{sender_name} <{from_addr}>"
    payload = json.dumps(
        {
            "from": from_addr,
            "to": [to_addr],
            "subject": subject,
            "text": body,
            "html": html or body,
        },
        ensure_ascii=False,
    ).encode("utf-8")
    req = urllib.request.Request(
        f"{base_url}/emails",
        data=payload,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            data = json.loads(raw) if raw else {}
            return {"sent": True, "provider": "resend", "message_id": data.get("id")}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")[:500]
        return {"sent": False, "detail": f"Resend HTTP {e.code}: {detail}"}


def _openclaw_mail_send_email(
    *,
    runtime: dict,
    to_addr: str,
    subject: str,
    body: str,
    html: str = "",
) -> dict:
    if not bool(runtime.get("openclaw_mail_enabled", False)):
        return {"sent": False, "detail": "OpenClaw 邮件通道未启用"}
    user = str(runtime.get("openclaw_mail_user") or "").strip()
    api_key = str(runtime.get("openclaw_mail_api_key") or "").strip()
    if not (user and api_key):
        return {"sent": False, "detail": "OpenClaw 邮件未完整配置"}
    script = Path(
        os.getenv(
            "OPENCLAW_MAIL_SCRIPT",
            "/opt/migrate/code_workspace/boxying-image-gateway/scripts/send_claw_email.mjs",
        )
    )
    if not script.exists():
        return {"sent": False, "detail": f"OpenClaw 邮件脚本不存在: {script}"}
    env = {
        **os.environ,
        "OPENCLAW_MAIL_USER": user,
        "OPENCLAW_MAIL_API_KEY": api_key,
        "OPENCLAW_MAIL_FROM_NAME": str(runtime.get("email_sender_name") or "").strip(),
        "OPENCLAW_MAIL_TO": to_addr,
        "OPENCLAW_MAIL_SUBJECT": subject,
        "OPENCLAW_MAIL_TEXT": body,
        "OPENCLAW_MAIL_HTML": html,
        "NODE_OPTIONS": "--dns-result-order=ipv4first",
    }
    try:
        completed = subprocess.run(
            ["node", str(script)],
            check=False,
            capture_output=True,
            text=True,
            timeout=60,
            env=env,
        )
    except Exception as e:
        return {"sent": False, "detail": f"OpenClaw 邮件执行失败: {e}"}
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout or "").strip()[:500]
        return {"sent": False, "detail": f"OpenClaw 邮件失败: {detail}"}
    try:
        data = json.loads(completed.stdout or "{}")
    except json.JSONDecodeError:
        data = {}
    if data.get("ok") is True or str(data.get("status") or "").lower() == "sent":
        return {
            "sent": True,
            "provider": "claw163",
            "message_id": data.get("messageId"),
        }
    return {"sent": False, "detail": str(data.get("error") or "OpenClaw 邮件未返回 sent")}


def _email_code_payload(code: str, purpose: str) -> tuple[str, str, str]:
    label = {
        "bind": "绑定邮箱",
        "login": "邮箱验证码登录",
        "reset": "找回密码",
    }.get(purpose, "邮箱验证")
    subject = f"多仪账号{label}验证码"
    body = f"你的验证码是 {code}，5 分钟内有效。若不是本人操作，请忽略本邮件。"
    html = (
        "<p>你好，</p>"
        f"<p>你的验证码是 <strong>{code}</strong>，5 分钟内有效。</p>"
        "<p>若不是本人操作，请忽略本邮件。</p>"
    )
    return subject, body, html


def _reset_email_payload(code: str) -> tuple[str, str, str]:
    subject = "多仪账号找回密码验证码"
    body = (
        f"重置验证码：{code}\n"
        "验证码 30 分钟内有效。如非本人操作，请忽略本邮件。"
    )
    html = (
        "<p>你好，</p>"
        f"<p>重置验证码：<strong>{code}</strong></p>"
        "<p>验证码 30 分钟内有效。如非本人操作，请忽略本邮件。</p>"
    )
    return subject, body, html


def _email_code_provider_configured(runtime: dict, provider: str) -> bool:
    provider = _normalize_email_code_provider(provider)
    if provider == "claw163":
        return bool(
            runtime.get("openclaw_mail_enabled")
            and runtime.get("openclaw_mail_user")
            and runtime.get("openclaw_mail_api_key")
        )
    if provider == "resend":
        return bool(runtime.get("resend_api_key") and runtime.get("resend_from"))
    if provider == "smtp":
        return bool(
            runtime.get("email_smtp_host")
            and runtime.get("email_smtp_username")
            and runtime.get("email_smtp_password")
        )
    return False


def _account_email_runtime_status(runtime: dict) -> dict:
    primary_provider = _normalize_email_code_provider(
        runtime.get("email_code_primary_provider", "none")
    )
    backup_provider = _normalize_email_code_provider(
        runtime.get("email_code_backup_provider", "none")
    )
    active_slot = _normalize_email_code_slot(runtime.get("email_code_active_slot"))
    effective_provider = primary_provider if active_slot == "primary" else backup_provider
    return {
        "email_service_enabled": bool(runtime.get("email_service_enabled", True)),
        "email_sender_name": runtime.get("email_sender_name", DEFAULT_EMAIL_SENDER_NAME),
        "email_code_primary_provider": primary_provider,
        "email_code_backup_provider": backup_provider,
        "email_code_active_slot": active_slot,
        "email_code_effective_provider": effective_provider,
        "email_auto_switch_enabled": bool(runtime.get("email_auto_switch_enabled", False)),
        "openclaw_mail_configured": _email_code_provider_configured(runtime, "claw163"),
        "resend_configured": _email_code_provider_configured(runtime, "resend"),
        "smtp_configured": _email_code_provider_configured(runtime, "smtp"),
        "hermes_configured": bool(
            runtime.get("hermes_base_url") and runtime.get("hermes_api_key")
        ),
    }


def _any_account_email_provider_configured(runtime: dict) -> bool:
    return any(
        _email_code_provider_configured(
            runtime,
            runtime.get(f"email_code_{slot}_provider", "none"),
        )
        for slot in ("primary", "backup")
    )


def _send_account_email(
    db,
    *,
    to_addr: str,
    subject: str,
    body: str,
    html: str = "",
) -> dict:
    runtime = _account_mail_runtime(db)
    if not runtime.get("email_service_enabled", True):
        return {"sent": False, "provider": "none", "detail": "账号邮件服务未启用"}
    active_slot = _normalize_email_code_slot(runtime.get("email_code_active_slot"))
    slots = [active_slot, "backup" if active_slot == "primary" else "primary"]
    errors: list[str] = []
    attempted_providers: set[str] = set()
    for slot in dict.fromkeys(slots):
        provider = _normalize_email_code_provider(
            runtime.get(f"email_code_{slot}_provider", "none")
        )
        if provider != "none":
            attempted_providers.add(provider)
        if provider == "none":
            errors.append(f"{slot}: 邮件通道关闭")
            continue
        if not _email_code_provider_configured(runtime, provider):
            errors.append(f"{slot}/{provider}: 未配置")
            continue
        try:
            if provider == "claw163":
                result = _openclaw_mail_send_email(
                    runtime=runtime,
                    to_addr=to_addr,
                    subject=subject,
                    body=body,
                    html=html,
                )
            elif provider == "resend":
                result = _resend_send_email(
                    runtime=runtime,
                    to_addr=to_addr,
                    subject=subject,
                    body=body,
                    html=html,
                )
            elif provider == "smtp":
                result = _email_smtp_send(
                    runtime=runtime,
                    to_addr=to_addr,
                    subject=subject,
                    body=body,
                    html=html,
                )
            else:
                result = {"sent": False, "detail": "邮件通道关闭"}
        except Exception as e:
            result = {"sent": False, "detail": str(e)}
        if result.get("sent"):
            if slot != active_slot and runtime.get("email_auto_switch_enabled"):
                _setting_set(db, "email_code_active_slot", slot)
            result["slot"] = slot
            result["provider"] = provider
            result.setdefault("message", "验证码已发送，请查看邮箱。")
            return result
        errors.append(str(result.get("detail") or result.get("message") or f"{provider} 发送失败"))
    if (
        "smtp" not in attempted_providers
        and _email_code_provider_configured(runtime, "smtp")
    ):
        try:
            result = _email_smtp_send(
                runtime=runtime,
                to_addr=to_addr,
                subject=subject,
                body=body,
                html=html,
            )
        except Exception as e:
            result = {"sent": False, "detail": str(e)}
        if result.get("sent"):
            result["slot"] = "smtp_fallback"
            result["provider"] = "smtp"
            result.setdefault("message", "验证码已发送，请查看邮箱。")
            return result
        errors.append(str(result.get("detail") or result.get("message") or "smtp 兜底发送失败"))
    if runtime.get("hermes_base_url") and runtime.get("hermes_api_key"):
        try:
            result = _hermes_send_email(
                runtime=runtime,
                to_addr=to_addr,
                subject=subject,
                body=body,
                html=html,
            )
        except Exception as e:
            result = {"sent": False, "detail": str(e)}
        if result.get("sent"):
            result["slot"] = "hermes_fallback"
            result["provider"] = "hermes"
            result.setdefault("message", "验证码已发送，请查看邮箱。")
            return result
        errors.append(str(result.get("detail") or result.get("message") or "Hermes 兜底发送失败"))
    return {
        "sent": False,
        "provider": "none",
        "message": "验证码已生成，但邮件服务暂不可用。",
        "detail": "; ".join(errors),
    }


def _reminder_email_recipient(db, user_id: str) -> str:
    row = db.execute(
        "SELECT username, email FROM users WHERE id=?", (user_id,)
    ).fetchone()
    email = str(row["email"] if row else "").strip()
    if email:
        return email
    username = str(row["username"] if row else "").strip()
    if _looks_like_email(username):
        return username
    return str(_setting_get(db, "reminder_email_to", "") or "").strip()


def _send_reminder_email(db, user_id: str, subject: str, body: str) -> None:
    if not _setting_bool(db, "reminder_email_enabled", False):
        raise RuntimeError("邮件提醒未启用")
    to_addr = _reminder_email_recipient(db, user_id)
    host = str(_setting_get(db, "reminder_email_smtp_host", "") or "").strip()
    username = str(_setting_get(db, "reminder_email_smtp_username", "") or "").strip()
    password = str(_setting_get(db, "reminder_email_smtp_password", "") or "")
    if not (to_addr and host and username and password):
        raise RuntimeError("邮件提醒 SMTP 未完整配置")
    from_addr = str(_setting_get(db, "reminder_email_from", "") or "").strip() or username
    _smtp_send(
        host=host,
        port=int(_setting_get(db, "reminder_email_smtp_port", 465) or 465),
        username=username,
        password=password,
        use_ssl=_setting_bool(db, "reminder_email_smtp_use_ssl", True),
        from_addr=from_addr,
        to_addr=to_addr,
        subject=subject,
        body=body,
    )


def _account_email_recipient(row) -> str:
    email = str(row["email"] or "").strip()
    if email:
        return email
    username = str(row["username"] or "").strip()
    return username if _looks_like_email(username) else ""


def _user_account_email_recipient(db, user_id: str) -> str:
    row = db.execute(
        "SELECT username, email FROM users WHERE id=?",
        (user_id,),
    ).fetchone()
    return _account_email_recipient(row) if row else ""


def _account_email_test_recipient(db, actor: str) -> str:
    row = db.execute(
        "SELECT username, email FROM users WHERE id=?",
        (actor,),
    ).fetchone()
    recipient = _account_email_recipient(row) if row else ""
    if recipient:
        return recipient
    configured = str(_setting_get(db, "system_notice_email_to", "") or "")
    for part in re.split(r"[,;\s]+", configured):
        candidate = part.strip()
        if _looks_like_email(candidate):
            return candidate
    return ""


def _send_password_reset_email(db, row, token: str) -> None:
    to_addr = _account_email_recipient(row)
    if not to_addr:
        raise RuntimeError("账号未绑定邮箱")
    subject, body, html = _reset_email_payload(token)
    result = _send_account_email(
        db,
        to_addr=to_addr,
        subject=subject,
        body=body,
        html=html,
    )
    if not result.get("sent"):
        raise RuntimeError(str(result.get("detail") or "账号邮件 SMTP 未完整配置"))


def _send_workspace_mention_email(
    db,
    *,
    target_user_id: str,
    author_name: str,
    workspace_name: str,
    target_id: str,
    body: str,
) -> None:
    to_addr = _user_account_email_recipient(db, target_user_id)
    if not to_addr:
        raise RuntimeError("被提及成员未绑定邮箱")
    comment = body.strip()
    if len(comment) > 600:
        comment = comment[:600] + "..."
    location = f"任务/对象：{target_id}\n" if target_id else ""
    text_body = (
        f"{author_name} 在「{workspace_name}」中 @ 了你。\n\n"
        f"{location}"
        f"评论：{comment}\n\n"
        "打开多仪的共享空间可查看并标记已读。"
    )
    html_body = (
        f"<p>{html.escape(author_name)} 在「{html.escape(workspace_name)}」中 @ 了你。</p>"
        + (f"<p>任务/对象：{html.escape(target_id)}</p>" if target_id else "")
        + f"<p>评论：{html.escape(comment)}</p>"
        + "<p>打开多仪的共享空间可查看并标记已读。</p>"
    )
    result = _send_account_email(
        db,
        to_addr=to_addr,
        subject=f"多仪共享空间提及：{workspace_name}",
        body=text_body,
        html=html_body,
    )
    if not result.get("sent"):
        raise RuntimeError(str(result.get("detail") or "账号邮件 SMTP 未完整配置"))


def _next_repeating_email_time(
    *,
    hour: int,
    minute: int,
    weekdays: list[int],
    after: Optional[datetime] = None,
) -> datetime:
    now = after or _utc_now()
    for day_offset in range(0, 8):
        candidate_date = now + timedelta(days=day_offset)
        candidate = candidate_date.replace(
            hour=hour,
            minute=minute,
            second=0,
            microsecond=0,
        )
        if candidate <= now:
            continue
        if weekdays and candidate.isoweekday() not in weekdays:
            continue
        return candidate
    return now + timedelta(days=1)


def _reminder_email_job_id(user_id: str, reminder_id: int) -> str:
    digest = hashlib.sha1(f"{user_id}:{reminder_id}".encode()).hexdigest()[:16]
    return f"reminder-email:{digest}"


def _upsert_reminder_email_job(
    db,
    *,
    user_id: str,
    reminder_id: int,
    schedule_kind: str,
    title: str,
    body: str,
    payload: str,
    when_at: Optional[datetime] = None,
    hour: Optional[int] = None,
    minute: Optional[int] = None,
    weekdays: Optional[list[int]] = None,
) -> dict:
    if schedule_kind not in {"once", "repeating"}:
        raise HTTPException(status_code=400, detail="Invalid schedule kind")
    if schedule_kind == "once":
        if when_at is None:
            raise HTTPException(status_code=400, detail="when is required")
        next_send_at = when_at
    else:
        if hour is None or minute is None or hour < 0 or hour > 23 or minute < 0 or minute > 59:
            raise HTTPException(status_code=400, detail="Invalid time")
        next_send_at = _next_repeating_email_time(
            hour=hour,
            minute=minute,
            weekdays=weekdays or [],
        )
    job_id = _reminder_email_job_id(user_id, reminder_id)
    db.execute(
        """
        INSERT INTO reminder_email_jobs(
            id, user_id, reminder_id, schedule_kind, title, body, payload,
            when_at, hour, minute, weekdays_json, next_send_at, sent_at,
            cancelled, updated_at
        )
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,0,?)
        ON CONFLICT(id) DO UPDATE SET
            schedule_kind=excluded.schedule_kind,
            title=excluded.title,
            body=excluded.body,
            payload=excluded.payload,
            when_at=excluded.when_at,
            hour=excluded.hour,
            minute=excluded.minute,
            weekdays_json=excluded.weekdays_json,
            next_send_at=excluded.next_send_at,
            sent_at=NULL,
            cancelled=0,
            updated_at=excluded.updated_at
        """,
        (
            job_id,
            user_id,
            reminder_id,
            schedule_kind,
            title,
            body,
            payload,
            _format_utc(when_at) if when_at else None,
            hour,
            minute,
            json.dumps(weekdays or []),
            _format_utc(next_send_at),
            None,
            _utc_now_text(),
        ),
    )
    return {
        "id": job_id,
        "reminder_id": reminder_id,
        "schedule_kind": schedule_kind,
        "next_send_at": _format_utc(next_send_at),
    }


def dispatch_due_reminder_emails(limit: int = 50) -> int:
    db = get_db()
    sent = 0
    try:
        if not _setting_bool(db, "reminder_email_enabled", False):
            return 0
        rows = db.execute(
            """
            SELECT * FROM reminder_email_jobs
            WHERE cancelled=0
              AND next_send_at IS NOT NULL
              AND next_send_at <= ?
            ORDER BY next_send_at ASC
            LIMIT ?
            """,
            (_utc_now_text(), limit),
        ).fetchall()
        for row in rows:
            try:
                _send_reminder_email(db, row["user_id"], row["title"], row["body"])
            except Exception as e:
                db.execute(
                    "UPDATE reminder_email_jobs SET updated_at=? WHERE id=?",
                    (_utc_now_text(), row["id"]),
                )
                _audit(
                    db,
                    row["user_id"],
                    _get_username(db, row["user_id"]),
                    "reminder_email.failed",
                    target=row["id"],
                    detail=str(e),
                )
                continue
            sent += 1
            if row["schedule_kind"] == "repeating":
                weekdays = json.loads(row["weekdays_json"] or "[]")
                next_send_at = _next_repeating_email_time(
                    hour=int(row["hour"]),
                    minute=int(row["minute"]),
                    weekdays=[int(v) for v in weekdays],
                    after=_utc_now(),
                )
                db.execute(
                    "UPDATE reminder_email_jobs SET sent_at=?, next_send_at=?, updated_at=? WHERE id=?",
                    (_utc_now_text(), _format_utc(next_send_at), _utc_now_text(), row["id"]),
                )
            else:
                db.execute(
                    "UPDATE reminder_email_jobs SET sent_at=?, next_send_at=NULL, updated_at=? WHERE id=?",
                    (_utc_now_text(), _utc_now_text(), row["id"]),
                )
            _audit(
                db,
                row["user_id"],
                _get_username(db, row["user_id"]),
                "reminder_email.sent",
                target=row["id"],
            )
        db.commit()
        return sent
    finally:
        db.close()


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
    snapshot_path = backup_dir / f"duoyi_snapshot_{stamp}.db"
    shutil.copy2(db_path, snapshot_path)
    try:
        metadata = {
            "app": "duoyi",
            "created_at": datetime.now(timezone.utc).isoformat(),
            "source_db": str(db_path),
            "filename": filename,
        }
        with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            zf.write(snapshot_path, "duoyi.db")
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
    _smtp_send(
        host=host,
        port=int(_setting_get(db, "backup_email_smtp_port", 465) or 465),
        username=username,
        password=password,
        use_ssl=_setting_bool(db, "backup_email_smtp_use_ssl", True),
        from_addr=from_addr,
        to_addr=to_addr,
        subject=subject,
        body=body,
    )


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


async def _reminder_email_loop() -> None:
    while True:
        await asyncio.sleep(int(os.getenv("REMINDER_EMAIL_POLL_SECONDS", "60")))
        try:
            await asyncio.to_thread(dispatch_due_reminder_emails)
        except Exception:
            pass


@app.on_event("startup")
async def _start_server_backup_loop():
    global SERVER_BACKUP_TASK, REMINDER_EMAIL_TASK
    if SERVER_BACKUP_TASK is None or SERVER_BACKUP_TASK.done():
        SERVER_BACKUP_TASK = asyncio.create_task(_server_backup_loop())
    if REMINDER_EMAIL_TASK is None or REMINDER_EMAIL_TASK.done():
        REMINDER_EMAIL_TASK = asyncio.create_task(_reminder_email_loop())


@app.on_event("shutdown")
async def _stop_server_backup_loop():
    global SERVER_BACKUP_TASK, REMINDER_EMAIL_TASK
    if SERVER_BACKUP_TASK is not None:
        SERVER_BACKUP_TASK.cancel()
        SERVER_BACKUP_TASK = None
    if REMINDER_EMAIL_TASK is not None:
        REMINDER_EMAIL_TASK.cancel()
        REMINDER_EMAIL_TASK = None


@app.get("/api/admin/server-backups")
def admin_server_backups(
    _: str = Depends(_require_admin),
    q: Optional[str] = None,
    status: Optional[str] = None,
    sort: str = "created_desc",
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    limit, offset = _admin_page_window(limit, offset)
    db = get_db()
    try:
        where, params = _server_backup_admin_filters(q=q, status=status)
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM server_backups {where}", params
        ).fetchone()["c"]
        order_by = _server_backup_admin_order_by(sort)
        rows = db.execute(
            f"SELECT * FROM server_backups {where} ORDER BY {order_by} LIMIT ? OFFSET ?",
            (*params, limit, offset),
        ).fetchall()
        return _admin_page_response([dict(r) for r in rows], total, limit, offset)
    finally:
        db.close()


@app.get("/api/admin/server-backups/export.csv")
def export_server_backups_csv(
    actor: str = Depends(_require_admin),
    q: Optional[str] = None,
    status: Optional[str] = None,
    sort: str = "created_desc",
    limit: int = Query(5000, ge=1, le=20000),
):
    """导出当前筛选下的服务器备份记录。"""
    limit, _offset = _admin_page_window(limit, 0, default_limit=5000, max_limit=20000)
    db = get_db()
    try:
        where, params = _server_backup_admin_filters(q=q, status=status)
        order_by = _server_backup_admin_order_by(sort)
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM server_backups {where}", params
        ).fetchone()["c"]
        rows = db.execute(
            f"SELECT * FROM server_backups {where} ORDER BY {order_by} LIMIT ?",
            (*params, limit),
        ).fetchall()
        buffer = io.StringIO()
        writer = csv.writer(buffer)
        writer.writerow(
            [
                "id",
                "filename",
                "size_bytes",
                "status",
                "created_at",
                "local_path",
                "remote_url",
                "detail",
            ]
        )
        for row in rows:
            writer.writerow(
                [
                    _csv_safe(row["id"]),
                    _csv_safe(row["filename"]),
                    int(row["size_bytes"] or 0),
                    _csv_safe(row["status"]),
                    _csv_safe(row["created_at"]),
                    _csv_safe(row["local_path"]),
                    _csv_safe(row["remote_url"]),
                    _csv_safe(row["detail"]),
                ]
            )
        _audit(
            db,
            actor,
            _get_username(db, actor),
            "server_backup.export",
            detail=json.dumps(
                {
                    "status": status or "",
                    "q": q or "",
                    "sort": sort,
                    "rows": len(rows),
                    "total": int(total or 0),
                },
                ensure_ascii=False,
            ),
        )
        db.commit()
        content = "\ufeff" + buffer.getvalue()
        filename = (
            f"duoyi_server_backups_{_utc_now().strftime('%Y%m%d_%H%M%S')}.csv"
        )
        headers = {
            "Content-Disposition": f'attachment; filename="{filename}"',
            "X-Total-Count": str(int(total or 0)),
            "X-Exported-Count": str(len(rows)),
        }
        return StreamingResponse(
            iter([content]),
            media_type="text/csv; charset=utf-8",
            headers=headers,
        )
    finally:
        db.close()


@app.post("/api/admin/server-backups/run")
def admin_run_server_backup(actor: str = Depends(_require_admin)):
    return run_server_backup(actor)


@app.post("/api/reminders/email/once")
def schedule_email_reminder_once(
    req: ReminderEmailOnceRequest,
    user_id: str = Depends(_verify_token),
):
    when_at = _parse_server_time(req.when)
    if when_at is None:
        raise HTTPException(status_code=400, detail="Invalid when")
    db = get_db()
    try:
        result = _upsert_reminder_email_job(
            db,
            user_id=user_id,
            reminder_id=req.id,
            schedule_kind="once",
            title=req.title,
            body=req.body,
            payload=req.payload or "",
            when_at=when_at,
        )
        db.commit()
        return result
    finally:
        db.close()


@app.post("/api/reminders/email/repeating")
def schedule_email_reminder_repeating(
    req: ReminderEmailRepeatingRequest,
    user_id: str = Depends(_verify_token),
):
    weekdays = [int(v) for v in (req.weekdays or []) if 1 <= int(v) <= 7]
    db = get_db()
    try:
        result = _upsert_reminder_email_job(
            db,
            user_id=user_id,
            reminder_id=req.id,
            schedule_kind="repeating",
            title=req.title,
            body=req.body,
            payload=req.payload or "",
            hour=req.hour,
            minute=req.minute,
            weekdays=weekdays,
        )
        db.commit()
        return result
    finally:
        db.close()


@app.delete("/api/reminders/email/{reminder_id}")
def cancel_email_reminder(reminder_id: int, user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        job_id = _reminder_email_job_id(user_id, reminder_id)
        db.execute(
            "UPDATE reminder_email_jobs SET cancelled=1, next_send_at=NULL, updated_at=? WHERE id=? AND user_id=?",
            (_utc_now_text(), job_id, user_id),
        )
        db.commit()
        return {"ok": True, "id": job_id}
    finally:
        db.close()


# ---- Auth ----


def _client_ip(request: Optional[Request]) -> str:
    if request is None:
        return ""
    forwarded = request.headers.get("x-forwarded-for", "")
    if forwarded:
        return forwarded.split(",", 1)[0].strip()
    return request.client.host if request.client else ""


def _create_email_code(
    db,
    *,
    email: str,
    purpose: str,
    user_id: Optional[str] = None,
    ip_address: str = "",
) -> dict:
    purpose = (purpose or "login").strip().lower()
    if purpose not in {"bind", "login", "reset"}:
        raise HTTPException(status_code=400, detail="验证码用途不受支持")
    normalized_email = _clean_email(email)
    if not normalized_email:
        raise HTTPException(status_code=400, detail="邮箱不能为空")
    now = _utc_now()
    latest = db.execute(
        """
        SELECT locked_until, created_at
        FROM email_verification_codes
        WHERE email=? AND purpose=? AND consumed_at IS NULL
        ORDER BY created_at DESC
        LIMIT 1
        """,
        (normalized_email, purpose),
    ).fetchone()
    if latest is not None:
        locked_until = _parse_server_time(latest["locked_until"])
        if locked_until is not None and locked_until > now:
            raise HTTPException(status_code=429, detail="验证码错误次数过多，请稍后再试")
        created_at = _parse_server_time(latest["created_at"])
        if created_at is not None and (now - created_at).total_seconds() < 60:
            raise HTTPException(status_code=429, detail="验证码发送过于频繁，请稍后再试")

    if purpose == "login":
        row = db.execute(
            """
            SELECT id FROM users
            WHERE lower(email)=? AND email_verified=1 AND is_disabled=0
            """,
            (normalized_email,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="该邮箱还没有绑定可用账号")
        user_id = row["id"]
    elif purpose == "reset":
        row = db.execute(
            """
            SELECT id FROM users
            WHERE lower(email)=? AND is_disabled=0
            """,
            (normalized_email,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="该邮箱还没有绑定可用账号")
        user_id = row["id"]
    elif user_id is not None:
        _ensure_account_unique(db, email=normalized_email, exclude_user_id=user_id)
    else:
        _ensure_account_unique(db, email=normalized_email)

    code = f"{secrets.randbelow(1_000_000):06d}"
    expires_at = _format_utc(now + timedelta(minutes=5))
    code_id = secrets.token_hex(16)
    db.execute(
        """
        INSERT INTO email_verification_codes(
            id, user_id, email, purpose, code_hash, expires_at, ip_address, created_at
        ) VALUES(?,?,?,?,?,?,?,?)
        """,
        (
            code_id,
            user_id,
            normalized_email,
            purpose,
            _hash_email_code(code),
            expires_at,
            ip_address[:128],
            _format_utc(now),
        ),
    )
    return {
        "id": code_id,
        "user_id": user_id,
        "email": normalized_email,
        "purpose": purpose,
        "code": code,
        "expires_at": expires_at,
    }


def _consume_email_code(
    db,
    *,
    email: str,
    purpose: str,
    code: str,
    user_id: Optional[str] = None,
) -> None:
    normalized_email = _clean_email(email)
    normalized_code = (code or "").strip()
    if not normalized_email or not normalized_code:
        raise HTTPException(status_code=400, detail="验证码无效或已过期")
    row = db.execute(
        """
        SELECT *
        FROM email_verification_codes
        WHERE email=? AND purpose=? AND consumed_at IS NULL
          AND (? IS NULL OR user_id IS NULL OR user_id=?)
        ORDER BY created_at DESC
        LIMIT 1
        """,
        (normalized_email, purpose, user_id, user_id),
    ).fetchone()
    now = _utc_now()
    if row is None:
        raise HTTPException(status_code=400, detail="验证码无效或已过期")
    locked_until = _parse_server_time(row["locked_until"])
    if locked_until is not None and locked_until > now:
        raise HTTPException(status_code=429, detail="验证码错误次数过多，请稍后再试")
    expires_at = _parse_server_time(row["expires_at"])
    if expires_at is None or expires_at < now:
        raise HTTPException(status_code=400, detail="验证码已过期")
    if _hash_email_code(normalized_code) != row["code_hash"]:
        failures = int(row["failure_count"] or 0) + 1
        locked = _format_utc(now + timedelta(hours=1)) if failures >= 5 else None
        db.execute(
            "UPDATE email_verification_codes SET failure_count=?, locked_until=? WHERE id=?",
            (failures, locked, row["id"]),
        )
        if locked:
            raise HTTPException(status_code=429, detail="验证码错误次数过多，请稍后再试")
        raise HTTPException(status_code=400, detail="验证码不正确")
    db.execute(
        "UPDATE email_verification_codes SET consumed_at=? WHERE id=?",
        (_format_utc(now), row["id"]),
    )


def _send_email_code_result(db, code_result: dict) -> dict:
    subject, body, html = _email_code_payload(
        code_result["code"],
        code_result["purpose"],
    )
    sent = _send_account_email(
        db,
        to_addr=code_result["email"],
        subject=subject,
        body=body,
        html=html,
    )
    runtime = _account_mail_runtime(db)
    payload = {
        "ok": True,
        "email": code_result["email"],
        "purpose": code_result["purpose"],
        "expires_at": code_result["expires_at"],
        "sent": bool(sent.get("sent")),
        "provider": sent.get("provider", "none"),
        "message": sent.get("message", "验证码已发送，请查看邮箱。"),
    }
    if sent.get("detail"):
        payload["detail"] = sent.get("detail")
    if not sent.get("sent") and not _any_account_email_provider_configured(runtime):
        payload["dev_code"] = code_result["code"]
    return payload


def _auth_payload(data: dict) -> dict:
    return {"user": data, **data}


def _issue_login_session(db, row, *, action: str) -> dict:
    token = secrets.token_hex(32)
    TOKENS[row["id"]] = token
    now = _utc_now()
    now_text = _format_utc(now)
    TOKEN_LAST_ACTIVE[row["id"]] = now
    db.execute(
        "UPDATE users SET last_login_at=?, last_active_at=? WHERE id=?",
        (now_text, now_text, row["id"]),
    )
    _audit(db, row["id"], row["username"], action)
    db.commit()
    fresh = db.execute("SELECT * FROM users WHERE id=?", (row["id"],)).fetchone()
    return _auth_payload(_user_response(fresh, token=token))


def _public_avatar_url(filename: str) -> str:
    return f"/api/uploads/avatars/{filename}"


def _external_avatar_url(request: Request, filename: str) -> str:
    return str(request.base_url).rstrip("/") + _public_avatar_url(filename)


def _avatar_file_path_from_url(value: str) -> Optional[Path]:
    text = (value or "").strip()
    marker = "/api/uploads/avatars/"
    if marker not in text:
        return None
    filename = text.rsplit(marker, 1)[-1].split("?", 1)[0].split("#", 1)[0]
    if not filename or filename != os.path.basename(filename):
        return None
    return Path(AVATAR_UPLOAD_DIR) / filename


def _avatar_bytes_match_suffix(raw: bytes, suffix: str) -> bool:
    if suffix == ".png":
        return raw.startswith(b"\x89PNG\r\n\x1a\n")
    if suffix in {".jpg", ".jpeg"}:
        return raw.startswith(b"\xff\xd8\xff")
    if suffix == ".gif":
        return raw.startswith((b"GIF87a", b"GIF89a"))
    if suffix == ".webp":
        return len(raw) >= 12 and raw[:4] == b"RIFF" and raw[8:12] == b"WEBP"
    return False


@app.post("/api/auth/register")
def register(req: RegisterRequest):
    db = get_db()
    try:
        if not _registration_enabled(db):
            raise HTTPException(status_code=403, detail="Registration disabled")

        username = _clean_username(req.username)
        password = _clean_password(req.password)
        email = _clean_email(req.email)
        if not email and _looks_like_email(username):
            email = username.lower()
        if _setting_get(db, "registration_email_required", False) and not email:
            raise HTTPException(status_code=400, detail="注册需要绑定邮箱")
        email_verified = 0
        if email and req.email_code:
            _consume_email_code(
                db,
                email=email,
                purpose="bind",
                code=req.email_code,
                user_id=None,
            )
            email_verified = 1
        if _setting_get(db, "registration_email_required", False) and not email_verified:
            raise HTTPException(status_code=400, detail="注册需要邮箱验证码")
        display_name = _clean_short_text(req.display_name, 64, "昵称")
        _ensure_account_unique(db, username=username, email=email)

        if _registration_invite_required(db):
            code = (req.invite_code or req.invitation_code or "").strip()
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
        now_text = _utc_now_text()
        try:
            db.execute(
                "INSERT INTO users(id, username, email, email_verified, password_hash, display_name, last_login_at, last_active_at) "
                "VALUES(?,?,?,?,?,?,?,?)",
                (
                    user_id,
                    username,
                    email,
                    email_verified,
                    _hash_password(password),
                    display_name,
                    now_text,
                    now_text,
                ),
            )
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=409, detail="用户名或邮箱已被使用")

        db.execute("INSERT INTO sync_data(user_id) VALUES(?)", (user_id,))
        _ensure_private_workspace(db, user_id)

        if _registration_invite_required(db):
            db.execute(
                "UPDATE invite_codes SET used_by=?, used_at=datetime('now') WHERE code=?",
                (user_id, (req.invite_code or req.invitation_code or "").strip()),
            )

        _audit(db, user_id, username, "register", user_id)
        db.commit()
        token = secrets.token_hex(32)
        TOKENS[user_id] = token
        TOKEN_LAST_ACTIVE[user_id] = _utc_now()
        row = db.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
        return _auth_payload(_user_response(row, token=token))
    finally:
        db.close()


@app.post("/api/me/profile")
def update_my_profile(req: ProfileUpdate, user_id: str = Depends(_verify_token)):
    return _auth_payload(update_profile(req, user_id=user_id))


@app.post("/api/me/email")
def bind_my_email(req: EmailLoginRequest, user_id: str = Depends(_verify_token)):
    return _auth_payload(update_profile(
        ProfileUpdate(email=req.email, email_code=req.code),
        user_id=user_id,
    ))


@app.post("/api/auth/login")
def login(req: LoginRequest):
    db = get_db()
    try:
        identifier = req.username or req.account or req.email or ""
        row = _find_user_by_identifier(db, identifier)
        password_hash = _hash_password(req.password)
        legacy_hash = _legacy_hash_password(req.password)
        if row is None or row["password_hash"] not in {password_hash, legacy_hash}:
            raise HTTPException(status_code=401, detail="Invalid credentials")
        if row["is_disabled"]:
            raise HTTPException(status_code=403, detail="Account disabled")
        if row["password_hash"] == legacy_hash:
            db.execute(
                "UPDATE users SET password_hash=? WHERE id=?",
                (password_hash, row["id"]),
            )
        return _issue_login_session(db, row, action="login")
    finally:
        db.close()


@app.post("/api/auth/email-code")
def auth_email_code(
    req: EmailCodeRequest,
    request: Request,
    authorization: Optional[str] = Header(None),
):
    user_id: Optional[str] = None
    if authorization and authorization.startswith("Bearer "):
        user_id = _verify_token_value(authorization[7:])
    db = get_db()
    try:
        result = _create_email_code(
            db,
            email=req.email,
            purpose=req.purpose,
            user_id=user_id,
            ip_address=_client_ip(request),
        )
        payload = _send_email_code_result(db, result)
        _audit(
            db,
            result.get("user_id"),
            _get_username(db, result["user_id"]) if result.get("user_id") else None,
            f"email_code.{result['purpose']}.request",
            target=result["email"],
            detail=str(payload.get("provider") or ""),
        )
        db.commit()
        return payload
    finally:
        db.close()


@app.post("/api/auth/email-login")
def email_login(req: EmailLoginRequest):
    email = _clean_email(req.email)
    db = get_db()
    try:
        row = db.execute(
            """
            SELECT * FROM users
            WHERE lower(email)=? AND email_verified=1 AND is_disabled=0
            """,
            (email,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=401, detail="邮箱验证码无效或已过期")
        _consume_email_code(
            db,
            email=email,
            purpose="login",
            code=req.code,
            user_id=row["id"],
        )
        return _issue_login_session(db, row, action="email_login")
    finally:
        db.close()


@app.get("/api/auth/me")
def me(user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        row = db.execute(
            "SELECT * FROM users WHERE id=?",
            (user_id,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="User not found")
        return _user_response(row)
    finally:
        db.close()


@app.get("/api/me")
def me_alias(user_id: str = Depends(_verify_token)):
    return me(user_id=user_id)


@app.patch("/api/auth/profile")
def update_profile(req: ProfileUpdate, user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        current = db.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
        if current is None:
            raise HTTPException(status_code=404, detail="User not found")
        username = (
            _clean_username(req.username)
            if req.username is not None
            else current["username"]
        )
        email = (
            _clean_email(req.email)
            if req.email is not None
            else (current["email"] or "")
        )
        email_verified = int(current["email_verified"] or 0)
        if req.email is not None and email != (current["email"] or ""):
            email_verified = 0
            if email and req.email_code:
                _consume_email_code(
                    db,
                    email=email,
                    purpose="bind",
                    code=req.email_code,
                    user_id=user_id,
                )
                email_verified = 1
        elif req.email_code and email:
            _consume_email_code(
                db,
                email=email,
                purpose="bind",
                code=req.email_code,
                user_id=user_id,
            )
            email_verified = 1
        display_name = (
            _clean_short_text(req.display_name, 64, "昵称")
            if req.display_name is not None
            else (current["display_name"] or "")
        )
        avatar = (
            _clean_short_text(req.avatar, 1024, "头像")
            if req.avatar is not None
            else (current["avatar"] or "")
        )
        bio = (
            _clean_short_text(req.bio, 280, "简介")
            if req.bio is not None
            else (current["bio"] or "")
        )
        _ensure_account_unique(
            db,
            username=username,
            email=email,
            exclude_user_id=user_id,
        )
        db.execute(
            "UPDATE users SET username=?, email=?, email_verified=?, display_name=?, avatar=?, bio=? WHERE id=?",
            (username, email, email_verified, display_name, avatar, bio, user_id),
        )
        _audit(db, user_id, username, "profile.update", user_id)
        db.commit()
        row = db.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
        return _user_response(row)
    finally:
        db.close()


@app.post("/api/auth/password-reset")
@app.post("/api/auth/password-reset/request")
def request_password_reset(req: PasswordResetRequest):
    identifier = (req.email or req.identifier or req.account or req.username or "").strip()
    payload = {"ok": True}
    db = get_db()
    try:
        row = _find_user_by_identifier(db, identifier)
        if row is not None and not row["is_disabled"]:
            raw_token = f"{secrets.randbelow(1_000_000):06d}"
            expires_at = _format_utc(_utc_now() + timedelta(minutes=30))
            recipient = _account_email_recipient(row)
            if not recipient:
                raise HTTPException(status_code=400, detail="账号未绑定邮箱，无法找回密码")
            db.execute(
                "INSERT INTO password_reset_tokens(token_hash, user_id, expires_at) VALUES(?,?,?)",
                (_hash_reset_token(raw_token), row["id"], expires_at),
            )
            db.execute(
                """
                INSERT INTO email_verification_codes(
                    id, user_id, email, purpose, code_hash, expires_at, ip_address, created_at
                ) VALUES(?,?,?,?,?,?,?,?)
                """,
                (
                    secrets.token_hex(16),
                    row["id"],
                    _clean_email(recipient),
                    "reset",
                    _hash_email_code(raw_token),
                    expires_at,
                    "",
                    _utc_now_text(),
                ),
            )
            try:
                _send_password_reset_email(db, row, raw_token)
                _audit(db, row["id"], row["username"], "password_reset.request")
            except Exception as e:
                _audit(
                    db,
                    row["id"],
                    row["username"],
                    "password_reset.email_failed",
                    detail=str(e),
                )
                runtime = _account_mail_runtime(db)
                if not _any_account_email_provider_configured(runtime):
                    payload["dev_code"] = raw_token
            db.commit()
        return payload
    finally:
        db.close()


@app.post("/api/auth/password-reset/confirm")
def confirm_password_reset(req: PasswordResetConfirm):
    password = _clean_password(req.new_password or req.password or "")
    db = get_db()
    try:
        identifier = (req.email or req.identifier or req.account or req.username or "").strip()
        if identifier and req.code:
            user = _find_user_by_identifier(db, identifier)
            if user is None:
                raise HTTPException(status_code=400, detail="验证码无效或已过期")
            if user["is_disabled"]:
                raise HTTPException(status_code=400, detail="验证码无效或已过期")
            recipient = _account_email_recipient(user)
            if not recipient:
                raise HTTPException(status_code=400, detail="验证码无效或已过期")
            _consume_email_code(
                db,
                email=recipient,
                purpose="reset",
                code=req.code,
                user_id=user["id"],
            )
            token_hash = _hash_reset_token(req.code.strip())
            token_row = db.execute(
                """
                SELECT *
                FROM password_reset_tokens
                WHERE token_hash=? AND user_id=?
                """,
                (token_hash, user["id"]),
            ).fetchone()
            if token_row is None or token_row["used_at"] is not None:
                raise HTTPException(status_code=400, detail="验证码无效或已使用")
            expires_at = _parse_server_time(token_row["expires_at"])
            if expires_at is None or expires_at < _utc_now():
                raise HTTPException(status_code=400, detail="验证码已过期")
            db.execute(
                """
                UPDATE password_reset_tokens
                SET used_at=?
                WHERE token_hash=? AND user_id=? AND used_at IS NULL
                """,
                (_utc_now_text(), token_hash, user["id"]),
            )
            db.execute(
                "UPDATE users SET password_hash=?, email_verified=1 WHERE id=?",
                (_hash_password(password), user["id"]),
            )
            _drop_session(user["id"])
            _audit(db, user["id"], user["username"], "password_reset.confirm")
            db.commit()
            return {"ok": True}

        token_hash = _hash_reset_token((req.token or req.code or "").strip())
        row = db.execute(
            """
            SELECT prt.*, u.username
            FROM password_reset_tokens prt
            JOIN users u ON u.id=prt.user_id
            WHERE prt.token_hash=?
            """,
            (token_hash,),
        ).fetchone()
        if row is None or row["used_at"] is not None:
            raise HTTPException(status_code=400, detail="验证码无效或已使用")
        expires_at = _parse_server_time(row["expires_at"])
        if expires_at is None or expires_at < _utc_now():
            raise HTTPException(status_code=400, detail="验证码已过期")
        db.execute(
            "UPDATE users SET password_hash=? WHERE id=?",
            (_hash_password(password), row["user_id"]),
        )
        db.execute(
            "UPDATE password_reset_tokens SET used_at=? WHERE token_hash=?",
            (_utc_now_text(), token_hash),
        )
        _drop_session(row["user_id"])
        _audit(db, row["user_id"], row["username"], "password_reset.confirm")
        db.commit()
        return {"ok": True}
    finally:
        db.close()


@app.post("/api/auth/change-password")
def change_password(req: ChangePasswordRequest, user_id: str = Depends(_verify_token)):
    new_password = _clean_password(req.new_password or req.password or "")
    db = get_db()
    try:
        row = db.execute(
            "SELECT * FROM users WHERE id=?",
            (user_id,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="User not found")
        password_hash = _hash_password(req.current_password or "")
        legacy_hash = _legacy_hash_password(req.current_password or "")
        if row["password_hash"] not in {password_hash, legacy_hash}:
            raise HTTPException(status_code=403, detail="当前密码不正确")
        db.execute(
            "UPDATE users SET password_hash=? WHERE id=?",
            (_hash_password(new_password), user_id),
        )
        _audit(db, user_id, row["username"], "password.change")
        db.commit()
        return {"ok": True}
    finally:
        db.close()


@app.post("/api/auth/avatar")
@app.post("/api/me/avatar")
async def upload_avatar(
    request: Request,
    avatar: UploadFile = File(...),
    user_id: str = Depends(_verify_token),
):
    raw = await avatar.read()
    if not raw:
        raise HTTPException(status_code=400, detail="头像文件不能为空")
    if len(raw) > 3 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="头像不能超过 3MB")
    content_type = (avatar.content_type or "").lower()
    suffix = Path(avatar.filename or "").suffix.lower()
    if suffix not in {".jpg", ".jpeg", ".png", ".webp", ".gif"}:
        if "png" in content_type:
            suffix = ".png"
        elif "jpeg" in content_type or "jpg" in content_type:
            suffix = ".jpg"
        elif "webp" in content_type:
            suffix = ".webp"
        elif "gif" in content_type:
            suffix = ".gif"
        else:
            raise HTTPException(status_code=400, detail="仅支持 jpg/png/webp/gif 头像")
    if not _avatar_bytes_match_suffix(raw, suffix):
        raise HTTPException(status_code=400, detail="头像文件内容与格式不匹配")
    upload_dir = Path(AVATAR_UPLOAD_DIR)
    upload_dir.mkdir(parents=True, exist_ok=True)
    filename = f"{user_id}_{secrets.token_hex(12)}{suffix}"
    path = upload_dir / filename
    path.write_bytes(raw)
    avatar_url = _external_avatar_url(request, filename)
    db = get_db()
    try:
        row = db.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
        if row is None:
            try:
                path.unlink()
            except FileNotFoundError:
                pass
            raise HTTPException(status_code=404, detail="User not found")
        previous_path = _avatar_file_path_from_url(row["avatar"] or "")
        db.execute("UPDATE users SET avatar=? WHERE id=?", (avatar_url, user_id))
        _audit(db, user_id, row["username"], "profile.avatar_upload", user_id)
        db.commit()
        if previous_path and previous_path != path:
            try:
                previous_path.unlink()
            except FileNotFoundError:
                pass
        fresh = db.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
        return _auth_payload(_user_response(fresh))
    finally:
        db.close()


@app.get("/api/uploads/avatars/{filename}")
def get_avatar_upload(filename: str):
    if filename != os.path.basename(filename):
        raise HTTPException(status_code=404, detail="Not found")
    path = Path(AVATAR_UPLOAD_DIR) / filename
    if not path.exists() or not path.is_file():
        raise HTTPException(status_code=404, detail="Not found")
    return FileResponse(path)


@app.post("/api/auth/logout")
def logout(user_id: str = Depends(_verify_token)):
    _drop_session(user_id)
    return {"status": "ok"}


# ---- Focus Rooms ----


def _clean_focus_room_id(room_id: str) -> str:
    clean = (room_id or "").strip()
    if not clean or len(clean) > 128:
        raise HTTPException(status_code=400, detail="Invalid focus room id")
    return clean


def _clean_focus_display_name(value: Optional[str], fallback: str) -> str:
    clean = (value or "").strip()
    if not clean:
        clean = fallback
    return clean[:32]


def _clean_focus_metric(value: int, upper: int) -> int:
    try:
        number = int(value)
    except Exception:
        number = 0
    return max(0, min(number, upper))


def _parse_focus_risk_flags(value: Optional[str]) -> list[str]:
    if not value:
        return []
    try:
        parsed = json.loads(value)
    except Exception:
        return []
    if not isinstance(parsed, list):
        return []
    return [str(item)[:64] for item in parsed if str(item).strip()]


def _focus_risk_summary(flags: list[str]) -> str:
    labels = {
        "weekly_seconds_capped": "weekly focus seconds exceeded server cap",
        "session_count_capped": "session count exceeded server cap",
        "session_count_jump_capped": "session count jumped too quickly and was capped",
        "heartbeat_throttled": "heartbeat arrived too soon and was throttled",
    }
    return "; ".join(labels.get(flag, flag) for flag in flags)


def _focus_risk_payload(flags: list[str]) -> tuple[str, str]:
    ordered = list(dict.fromkeys(flags))
    return json.dumps(ordered, ensure_ascii=False), _focus_risk_summary(ordered)


def _merge_focus_risk_flags(value: Optional[str]) -> list[str]:
    merged: list[str] = []
    for raw in (value or "").split("|"):
        merged.extend(_parse_focus_risk_flags(raw))
    return list(dict.fromkeys(merged))


def _clean_focus_room_name(value: str) -> str:
    clean = (value or "").strip()
    if not clean:
        raise HTTPException(status_code=400, detail="Focus room name required")
    return clean[:64]


def _focus_room_payload(
    room_id: str,
    room_name: str,
    description: str,
    weekly_target_seconds: int,
    accent_color: int,
) -> dict:
    return {
        "id": room_id,
        "name": room_name,
        "description": (description or "")[:200],
        "weekly_target_seconds": _clean_focus_metric(
            weekly_target_seconds,
            10080 * 60,
        )
        or 18000,
        "accent_color": int(accent_color or 0xFF3949AB),
    }


def _clean_focus_invite_max_uses(value: Optional[int]) -> int:
    if value is None:
        return 0
    return _clean_focus_metric(value, 9999)


def _focus_room_invite_payload(row) -> dict:
    return {
        "id": row["id"],
        "code": row["code"],
        "room": _focus_room_payload(
            row["room_id"],
            row["room_name"],
            row["description"],
            row["weekly_target_seconds"],
            row["accent_color"],
        ),
        "expires_at": row["expires_at"],
        "max_uses": int(row["max_uses"] or 0),
        "used_count": int(row["used_count"] or 0),
        "last_used_at": row["last_used_at"],
        "revoked": bool(row["revoked"]),
        "created_at": row["created_at"],
    }


def _focus_room_ranking(db, room_id: str, current_user_id: str) -> dict:
    cutoff = _utc_now() - timedelta(seconds=FOCUS_ROOM_ONLINE_SECONDS)
    rows = db.execute(
        """
        SELECT p.room_id, p.user_id, p.display_name, p.raw_weekly_seconds,
               p.weekly_seconds, p.session_count, p.active, p.started_at,
               p.last_seen_at, p.risk_flags, p.risk_summary, u.username
        FROM focus_room_presence p
        JOIN users u ON u.id = p.user_id
        WHERE p.room_id=?
        """,
        (room_id,),
    ).fetchall()
    entries = []
    for row in rows:
        last_seen = _parse_server_time(row["last_seen_at"])
        online = (
            bool(row["active"])
            and last_seen is not None
            and last_seen >= cutoff
            and row["user_id"] in TOKENS
        )
        entries.append(
            {
                "room_id": row["room_id"],
                "user_id": row["user_id"],
                "display_name": row["display_name"] or row["username"],
                "raw_weekly_seconds": int(row["raw_weekly_seconds"] or 0),
                "weekly_seconds": int(row["weekly_seconds"] or 0),
                "session_count": int(row["session_count"] or 0),
                "online": online,
                "active": bool(row["active"]),
                "is_current_user": row["user_id"] == current_user_id,
                "started_at": row["started_at"],
                "last_seen_at": row["last_seen_at"],
                "risk_flags": _parse_focus_risk_flags(row["risk_flags"]),
                "risk_summary": row["risk_summary"] or "",
                "rank": 0,
            }
        )

    entries.sort(
        key=lambda item: (
            -item["weekly_seconds"],
            -item["session_count"],
            item["display_name"],
            item["user_id"],
        )
    )
    for idx, item in enumerate(entries):
        item["rank"] = idx + 1
    return {
        "room_id": room_id,
        "online_count": sum(1 for item in entries if item["online"]),
        "updated_at": _utc_now_text(),
        "entries": entries,
    }


def _is_user_online(row) -> bool:
    parsed = _parse_server_time(row["last_active_at"])
    cutoff = _utc_now() - timedelta(seconds=SESSION_ONLINE_SECONDS)
    return parsed is not None and parsed >= cutoff and row["id"] in TOKENS


def _focus_friend_payload(row) -> dict:
    return {
        "user_id": row["id"],
        "username": row["username"],
        "status": row["status"] if "status" in row.keys() else "accepted",
        "online": _is_user_online(row),
        "last_active_at": row["last_active_at"],
        "created_at": row["created_at"],
    }


def _focus_friend_request_payload(row, current_user_id: str) -> dict:
    direction = "incoming" if row["friend_user_id"] == current_user_id else "outgoing"
    other_id = row["user_id"] if direction == "incoming" else row["friend_user_id"]
    other_username = (
        row["requester_username"]
        if direction == "incoming"
        else row["addressee_username"]
    )
    other_last_active_at = (
        row["requester_last_active_at"]
        if direction == "incoming"
        else row["addressee_last_active_at"]
    )
    return {
        "id": f"{row['user_id']}:{row['friend_user_id']}",
        "user_id": other_id,
        "username": other_username,
        "direction": direction,
        "status": row["status"],
        "online": _is_user_online(
            {
                "id": other_id,
                "last_active_at": other_last_active_at,
            }
        ),
        "created_at": row["created_at"],
    }


def _focus_friend_request_rows(db, current_user_id: str):
    return db.execute(
        """
        SELECT ff.user_id, ff.friend_user_id, ff.status, ff.created_at,
               requester.username AS requester_username,
               requester.last_active_at AS requester_last_active_at,
               addressee.username AS addressee_username,
               addressee.last_active_at AS addressee_last_active_at
        FROM focus_friends ff
        JOIN users requester ON requester.id = ff.user_id
        JOIN users addressee ON addressee.id = ff.friend_user_id
        WHERE ff.status='pending'
          AND (ff.user_id=? OR ff.friend_user_id=?)
        ORDER BY ff.created_at DESC
        """,
        (current_user_id, current_user_id),
    ).fetchall()


def _focus_friend_recent_request_count(db, user_id: str) -> int:
    since = _format_utc(_utc_now() - timedelta(days=1))
    row = db.execute(
        """
        SELECT COUNT(*) AS c
        FROM focus_friend_request_log
        WHERE user_id=? AND created_at>=?
        """,
        (user_id, since),
    ).fetchone()
    return int(row["c"] if row else 0)


def _focus_friend_ranking(db, current_user_id: str) -> dict:
    friend_rows = db.execute(
        """
        SELECT u.id, u.username, u.last_active_at, ff.created_at
        FROM focus_friends ff
        JOIN users u ON u.id = ff.friend_user_id
        WHERE ff.user_id=? AND ff.status='accepted'
        ORDER BY u.username COLLATE NOCASE ASC
        """,
        (current_user_id,),
    ).fetchall()
    current = db.execute(
        """
        SELECT id, username, last_active_at, created_at
        FROM users
        WHERE id=?
        """,
        (current_user_id,),
    ).fetchone()

    users = []
    if current is not None:
        users.append(current)
    users.extend(friend_rows)
    user_ids = [row["id"] for row in users]

    stats = {
        user_id: {
            "raw_weekly_seconds": 0,
            "weekly_seconds": 0,
            "session_count": 0,
        }
        for user_id in user_ids
    }
    if user_ids:
        placeholders = ",".join("?" for _ in user_ids)
        rows = db.execute(
            f"""
            SELECT user_id,
                   SUM(raw_weekly_seconds) AS raw_weekly_seconds,
                   SUM(weekly_seconds) AS weekly_seconds,
                   SUM(session_count) AS session_count,
                   GROUP_CONCAT(risk_flags, '|') AS risk_flags
            FROM focus_room_presence
            WHERE user_id IN ({placeholders})
            GROUP BY user_id
            """,
            tuple(user_ids),
        ).fetchall()
        for row in rows:
            stats[row["user_id"]] = {
                "raw_weekly_seconds": int(row["raw_weekly_seconds"] or 0),
                "weekly_seconds": min(
                    int(row["weekly_seconds"] or 0),
                    FOCUS_ROOM_MAX_WEEKLY_SECONDS,
                ),
                "session_count": min(
                    int(row["session_count"] or 0),
                    FOCUS_ROOM_MAX_SESSION_COUNT,
                ),
                "risk_flags": _merge_focus_risk_flags(row["risk_flags"]),
            }

    entries = []
    for row in users:
        score = stats.get(row["id"]) or {}
        weekly_seconds = int(score.get("weekly_seconds") or 0)
        raw_weekly_seconds = int(score.get("raw_weekly_seconds") or 0)
        session_count = int(score.get("session_count") or 0)
        risk_flags = score.get("risk_flags") or []
        entries.append(
            {
                "user_id": row["id"],
                "display_name": row["username"],
                "raw_weekly_seconds": raw_weekly_seconds,
                "weekly_seconds": weekly_seconds,
                "session_count": session_count,
                "online": _is_user_online(row),
                "active": True,
                "is_current_user": row["id"] == current_user_id,
                "last_seen_at": row["last_active_at"],
                "risk_flags": risk_flags,
                "risk_summary": _focus_risk_summary(risk_flags),
                "rank": 0,
            }
        )

    entries.sort(
        key=lambda item: (
            -item["weekly_seconds"],
            -item["session_count"],
            item["display_name"],
            item["user_id"],
        )
    )
    for idx, item in enumerate(entries):
        item["rank"] = idx + 1
    return {
        "scope": "friends",
        "online_count": sum(1 for item in entries if item["online"]),
        "updated_at": _utc_now_text(),
        "entries": entries,
    }


def _focus_global_ranking(db, current_user_id: str) -> dict:
    rows = db.execute(
        """
        SELECT u.id, u.username, u.last_active_at,
               COALESCE(SUM(p.raw_weekly_seconds), 0) AS raw_weekly_seconds,
               COALESCE(SUM(p.weekly_seconds), 0) AS weekly_seconds,
               COALESCE(SUM(p.session_count), 0) AS session_count,
               GROUP_CONCAT(p.risk_flags, '|') AS risk_flags
        FROM users u
        LEFT JOIN focus_room_presence p ON p.user_id = u.id
        WHERE u.is_disabled=0
          AND (p.user_id IS NOT NULL OR u.id=?)
        GROUP BY u.id, u.username, u.last_active_at
        """,
        (current_user_id,),
    ).fetchall()

    entries = []
    for row in rows:
        raw_weekly_seconds = int(row["raw_weekly_seconds"] or 0)
        weekly_seconds = min(
            int(row["weekly_seconds"] or 0),
            FOCUS_ROOM_MAX_WEEKLY_SECONDS,
        )
        session_count = min(
            int(row["session_count"] or 0),
            FOCUS_ROOM_MAX_SESSION_COUNT,
        )
        risk_flags = _merge_focus_risk_flags(row["risk_flags"])
        entries.append(
            {
                "user_id": row["id"],
                "display_name": row["username"],
                "raw_weekly_seconds": raw_weekly_seconds,
                "weekly_seconds": weekly_seconds,
                "session_count": session_count,
                "online": _is_user_online(row),
                "active": True,
                "is_current_user": row["id"] == current_user_id,
                "last_seen_at": row["last_active_at"],
                "risk_flags": risk_flags,
                "risk_summary": _focus_risk_summary(risk_flags),
                "rank": 0,
            }
        )

    entries.sort(
        key=lambda item: (
            -item["weekly_seconds"],
            -item["session_count"],
            item["display_name"],
            item["user_id"],
        )
    )
    for idx, item in enumerate(entries):
        item["rank"] = idx + 1
    return {
        "scope": "global",
        "online_count": sum(1 for item in entries if item["online"]),
        "updated_at": _utc_now_text(),
        "entries": entries,
    }


@app.get("/api/focus-friends")
def list_focus_friends(user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        rows = db.execute(
            """
            SELECT u.id, u.username, u.last_active_at, ff.status, ff.created_at
            FROM focus_friends ff
            JOIN users u ON u.id = ff.friend_user_id
            WHERE ff.user_id=? AND ff.status='accepted'
            ORDER BY u.username COLLATE NOCASE ASC
            """,
            (user_id,),
        ).fetchall()
        return {"items": [_focus_friend_payload(row) for row in rows]}
    finally:
        db.close()


@app.get("/api/focus-friends/requests")
def list_focus_friend_requests(user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        items = [
            _focus_friend_request_payload(row, user_id)
            for row in _focus_friend_request_rows(db, user_id)
        ]
        return {
            "items": items,
            "incoming": [item for item in items if item["direction"] == "incoming"],
            "outgoing": [item for item in items if item["direction"] == "outgoing"],
        }
    finally:
        db.close()


@app.post("/api/focus-friends")
def add_focus_friend(
    req: FocusFriendCreate,
    user_id: str = Depends(_verify_token),
):
    username = (req.username or "").strip()
    requested_user_id = (req.user_id or "").strip()
    if not username and not requested_user_id:
        raise HTTPException(status_code=400, detail="Friend username required")
    db = get_db()
    try:
        if requested_user_id:
            friend = db.execute(
                """
                SELECT id, username, last_active_at, created_at
                FROM users
                WHERE id=?
                """,
                (requested_user_id,),
            ).fetchone()
        else:
            friend = db.execute(
                """
                SELECT id, username, last_active_at, created_at
                FROM users
                WHERE lower(username)=lower(?)
                """,
                (username,),
            ).fetchone()
        if friend is None:
            raise HTTPException(status_code=404, detail="Friend user not found")
        if friend["id"] == user_id:
            raise HTTPException(status_code=400, detail="Cannot add yourself")
        existing = db.execute(
            """
            SELECT status
            FROM focus_friends
            WHERE user_id=? AND friend_user_id=?
            """,
            (user_id, friend["id"]),
        ).fetchone()
        if existing is not None and existing["status"] == "accepted":
            created = db.execute(
                """
                SELECT u.id, u.username, u.last_active_at, ff.status, ff.created_at
                FROM focus_friends ff
                JOIN users u ON u.id = ff.friend_user_id
                WHERE ff.user_id=? AND ff.friend_user_id=?
                """,
                (user_id, friend["id"]),
            ).fetchone()
            return _focus_friend_payload(created or friend)

        incoming = db.execute(
            """
            SELECT status
            FROM focus_friends
            WHERE user_id=? AND friend_user_id=? AND status='pending'
            """,
            (friend["id"], user_id),
        ).fetchone()
        now_text = _utc_now_text()
        if incoming is not None:
            db.execute(
                """
                UPDATE focus_friends
                SET status='accepted'
                WHERE user_id=? AND friend_user_id=?
                """,
                (friend["id"], user_id),
            )
            db.execute(
                """
                INSERT INTO focus_friends(user_id, friend_user_id, status, created_at)
                VALUES(?,?,?,?)
                ON CONFLICT(user_id, friend_user_id) DO UPDATE SET
                    status='accepted'
                """,
                (user_id, friend["id"], "accepted", now_text),
            )
            db.commit()
            created = db.execute(
                """
                SELECT u.id, u.username, u.last_active_at, ff.status, ff.created_at
                FROM focus_friends ff
                JOIN users u ON u.id = ff.friend_user_id
                WHERE ff.user_id=? AND ff.friend_user_id=?
                """,
                (user_id, friend["id"]),
            ).fetchone()
            return _focus_friend_payload(created or friend)

        if (
            existing is None
            and _focus_friend_recent_request_count(db, user_id)
            >= FOCUS_FRIEND_REQUEST_LIMIT_PER_DAY
        ):
            raise HTTPException(
                status_code=429,
                detail="Focus friend request limit reached",
            )
        db.execute(
            """
            INSERT INTO focus_friends(user_id, friend_user_id, status, created_at)
            VALUES(?,?,?,?)
            ON CONFLICT(user_id, friend_user_id) DO UPDATE SET
                status='pending'
            """,
            (user_id, friend["id"], "pending", now_text),
        )
        if existing is None:
            db.execute(
                """
                INSERT INTO focus_friend_request_log(user_id, friend_user_id, created_at)
                VALUES(?,?,?)
                """,
                (user_id, friend["id"], now_text),
            )
        db.commit()
        created = db.execute(
            """
            SELECT u.id, u.username, u.last_active_at, ff.status, ff.created_at
            FROM focus_friends ff
            JOIN users u ON u.id = ff.friend_user_id
            WHERE ff.user_id=? AND ff.friend_user_id=?
            """,
            (user_id, friend["id"]),
        ).fetchone()
        return _focus_friend_payload(created or friend)
    finally:
        db.close()


@app.post("/api/focus-friend-requests/{requester_user_id}/accept")
def accept_focus_friend_request(
    requester_user_id: str,
    user_id: str = Depends(_verify_token),
):
    clean_requester_id = (requester_user_id or "").strip()
    if not clean_requester_id:
        raise HTTPException(status_code=400, detail="Invalid requester user id")
    db = get_db()
    try:
        row = db.execute(
            """
            SELECT 1 FROM focus_friends
            WHERE user_id=? AND friend_user_id=? AND status='pending'
            """,
            (clean_requester_id, user_id),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Focus friend request not found")
        now_text = _utc_now_text()
        db.execute(
            """
            UPDATE focus_friends SET status='accepted'
            WHERE user_id=? AND friend_user_id=?
            """,
            (clean_requester_id, user_id),
        )
        db.execute(
            """
            INSERT INTO focus_friends(user_id, friend_user_id, status, created_at)
            VALUES(?,?,?,?)
            ON CONFLICT(user_id, friend_user_id) DO UPDATE SET
                status='accepted'
            """,
            (user_id, clean_requester_id, "accepted", now_text),
        )
        db.commit()
        accepted = db.execute(
            """
            SELECT u.id, u.username, u.last_active_at, ff.status, ff.created_at
            FROM focus_friends ff
            JOIN users u ON u.id = ff.friend_user_id
            WHERE ff.user_id=? AND ff.friend_user_id=?
            """,
            (user_id, clean_requester_id),
        ).fetchone()
        return _focus_friend_payload(accepted)
    finally:
        db.close()


@app.post("/api/focus-friend-requests/{requester_user_id}/reject")
def reject_focus_friend_request(
    requester_user_id: str,
    user_id: str = Depends(_verify_token),
):
    clean_requester_id = (requester_user_id or "").strip()
    if not clean_requester_id:
        raise HTTPException(status_code=400, detail="Invalid requester user id")
    db = get_db()
    try:
        db.execute(
            """
            DELETE FROM focus_friends
            WHERE user_id=? AND friend_user_id=? AND status='pending'
            """,
            (clean_requester_id, user_id),
        )
        db.commit()
        return {"status": "ok", "user_id": clean_requester_id}
    finally:
        db.close()


@app.delete("/api/focus-friend-requests/{friend_user_id}")
def cancel_focus_friend_request(
    friend_user_id: str,
    user_id: str = Depends(_verify_token),
):
    clean_friend_user_id = (friend_user_id or "").strip()
    if not clean_friend_user_id:
        raise HTTPException(status_code=400, detail="Invalid friend user id")
    db = get_db()
    try:
        db.execute(
            """
            DELETE FROM focus_friends
            WHERE user_id=? AND friend_user_id=? AND status='pending'
            """,
            (user_id, clean_friend_user_id),
        )
        db.commit()
        return {"status": "ok", "user_id": clean_friend_user_id}
    finally:
        db.close()


@app.delete("/api/focus-friends/{friend_user_id}")
def remove_focus_friend(
    friend_user_id: str,
    user_id: str = Depends(_verify_token),
):
    clean_friend_user_id = (friend_user_id or "").strip()
    if not clean_friend_user_id:
        raise HTTPException(status_code=400, detail="Invalid friend user id")
    db = get_db()
    try:
        db.execute(
            """
            DELETE FROM focus_friends
            WHERE (user_id=? AND friend_user_id=?)
               OR (user_id=? AND friend_user_id=?)
            """,
            (user_id, clean_friend_user_id, clean_friend_user_id, user_id),
        )
        db.commit()
        return {"status": "ok", "user_id": clean_friend_user_id}
    finally:
        db.close()


@app.get("/api/focus-leaderboard/friends")
def focus_friend_leaderboard(user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        return _focus_friend_ranking(db, user_id)
    finally:
        db.close()


@app.get("/api/focus-leaderboard/global")
def focus_global_leaderboard(user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        return _focus_global_ranking(db, user_id)
    finally:
        db.close()


@app.get("/api/focus-leaderboard/global/events")
async def focus_global_leaderboard_events(
    interval_seconds: int = Query(15, ge=2, le=60),
    user_id: str = Depends(_verify_token),
):
    async def event_stream():
        while True:
            db = get_db()
            try:
                payload = _focus_global_ranking(db, user_id)
            finally:
                db.close()
            yield (
                "event: ranking\n"
                f"data: {json.dumps(payload, ensure_ascii=False)}\n\n"
            )
            await asyncio.sleep(interval_seconds)

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


@app.post("/api/focus-rooms/{room_id}/invites")
def create_focus_room_invite(
    room_id: str,
    req: FocusRoomInviteCreate,
    user_id: str = Depends(_verify_token),
):
    clean_room_id = _clean_focus_room_id(room_id)
    expires_at = _parse_server_time(req.expires_at)
    expires_at_text = _format_utc(expires_at) if expires_at is not None else None
    max_uses = _clean_focus_invite_max_uses(req.max_uses)
    room = _focus_room_payload(
        clean_room_id,
        _clean_focus_room_name(req.room_name),
        req.description,
        req.weekly_target_seconds,
        req.accent_color,
    )
    db = get_db()
    try:
        invite_id = secrets.token_hex(12)
        code = secrets.token_urlsafe(8).replace("-", "").replace("_", "")[:10]
        db.execute(
            """
            INSERT INTO focus_room_invites(
                id, room_id, code, room_name, description,
                weekly_target_seconds, accent_color, created_by, expires_at, max_uses
            ) VALUES(?,?,?,?,?,?,?,?,?,?)
            """,
            (
                invite_id,
                room["id"],
                code,
                room["name"],
                room["description"],
                room["weekly_target_seconds"],
                room["accent_color"],
                user_id,
                expires_at_text,
                max_uses,
            ),
        )
        db.commit()
        row = db.execute(
            "SELECT * FROM focus_room_invites WHERE id=?",
            (invite_id,),
        ).fetchone()
        return _focus_room_invite_payload(row)
    finally:
        db.close()


@app.get("/api/focus-rooms/{room_id}/invites")
def list_focus_room_invites(
    room_id: str,
    user_id: str = Depends(_verify_token),
):
    clean_room_id = _clean_focus_room_id(room_id)
    db = get_db()
    try:
        rows = db.execute(
            """
            SELECT *
            FROM focus_room_invites
            WHERE room_id=? AND created_by=?
            ORDER BY revoked ASC, created_at DESC, id DESC
            """,
            (clean_room_id, user_id),
        ).fetchall()
        return {"items": [_focus_room_invite_payload(row) for row in rows]}
    finally:
        db.close()


@app.delete("/api/focus-room-invites/{invite_id}")
def revoke_focus_room_invite(
    invite_id: str,
    user_id: str = Depends(_verify_token),
):
    clean_invite_id = (invite_id or "").strip()
    if not clean_invite_id:
        raise HTTPException(status_code=400, detail="Invalid focus room invite id")
    db = get_db()
    try:
        row = db.execute(
            "SELECT id FROM focus_room_invites WHERE id=? AND created_by=?",
            (clean_invite_id, user_id),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Focus room invite not found")
        db.execute(
            "UPDATE focus_room_invites SET revoked=1 WHERE id=?",
            (clean_invite_id,),
        )
        db.commit()
        return {"status": "ok", "id": clean_invite_id}
    finally:
        db.close()


@app.post("/api/focus-room-invites/{code}/accept")
def accept_focus_room_invite(
    code: str,
    req: FocusRoomInviteAccept,
    user_id: str = Depends(_verify_token),
):
    clean_code = (code or "").strip()
    db = get_db()
    try:
        row = db.execute(
            """
            SELECT id, room_id, room_name, description, weekly_target_seconds,
                   accent_color, expires_at, max_uses, used_count, revoked
            FROM focus_room_invites
            WHERE code=?
            """,
            (clean_code,),
        ).fetchone()
        if row is None or row["revoked"]:
            raise HTTPException(status_code=404, detail="Focus room invite not found")
        expires_at = _parse_server_time(row["expires_at"])
        if expires_at is not None and expires_at < _utc_now():
            raise HTTPException(status_code=400, detail="Focus room invite expired")
        existing_presence = db.execute(
            "SELECT 1 FROM focus_room_presence WHERE room_id=? AND user_id=?",
            (row["room_id"], user_id),
        ).fetchone()
        first_join = existing_presence is None
        max_uses = int(row["max_uses"] or 0)
        used_count = int(row["used_count"] or 0)
        if first_join and max_uses > 0 and used_count >= max_uses:
            raise HTTPException(
                status_code=400,
                detail="Focus room invite usage limit reached",
            )
        now_text = _utc_now_text()
        display_name = _clean_focus_display_name(
            req.display_name,
            _get_username(db, user_id),
        )
        if first_join:
            db.execute(
                """
                UPDATE focus_room_invites
                SET used_count=used_count+1, last_used_at=?
                WHERE id=?
                """,
                (now_text, row["id"]),
            )
        db.execute(
            """
            INSERT INTO focus_room_presence(
                room_id, user_id, display_name, raw_weekly_seconds,
                weekly_seconds, session_count, active, started_at,
                last_seen_at, updated_at
            )
            VALUES(?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(room_id, user_id) DO UPDATE SET
                display_name=excluded.display_name,
                active=1,
                started_at=excluded.started_at,
                last_seen_at=excluded.last_seen_at,
                updated_at=excluded.updated_at
            """,
            (
                row["room_id"],
                user_id,
                display_name,
                0,
                0,
                0,
                1,
                now_text,
                now_text,
                now_text,
            ),
        )
        db.commit()
        room = _focus_room_payload(
            row["room_id"],
            row["room_name"],
            row["description"],
            row["weekly_target_seconds"],
            row["accent_color"],
        )
        return {
            "code": clean_code,
            "room": room,
            "ranking": _focus_room_ranking(db, row["room_id"], user_id),
        }
    finally:
        db.close()


@app.post("/api/focus-rooms/{room_id}/heartbeat")
def focus_room_heartbeat(
    room_id: str,
    req: FocusRoomHeartbeatRequest,
    user_id: str = Depends(_verify_token),
):
    clean_room_id = _clean_focus_room_id(room_id)
    raw_weekly_seconds = _clean_focus_metric(
        req.weekly_seconds,
        FOCUS_ROOM_MAX_WEEKLY_SECONDS * 4,
    )
    weekly_seconds = min(raw_weekly_seconds, FOCUS_ROOM_MAX_WEEKLY_SECONDS)
    session_count = _clean_focus_metric(req.session_count, FOCUS_ROOM_MAX_SESSION_COUNT)
    now_text = _utc_now_text()
    started_at = _parse_server_time(req.started_at)
    started_at_text = _format_utc(started_at) if started_at is not None else now_text

    db = get_db()
    try:
        display_name = _clean_focus_display_name(
            req.display_name,
            _get_username(db, user_id),
        )
        existing = db.execute(
            """
            SELECT session_count, last_seen_at, risk_flags
            FROM focus_room_presence
            WHERE room_id=? AND user_id=?
            """,
            (clean_room_id, user_id),
        ).fetchone()
        risk_flags = (
            _parse_focus_risk_flags(existing["risk_flags"])
            if existing is not None
            else []
        )
        if raw_weekly_seconds > FOCUS_ROOM_MAX_WEEKLY_SECONDS:
            risk_flags.append("weekly_seconds_capped")
        if int(req.session_count or 0) > FOCUS_ROOM_MAX_SESSION_COUNT:
            risk_flags.append("session_count_capped")
        if existing is not None:
            previous_seen = _parse_server_time(existing["last_seen_at"])
            previous_session_count = int(existing["session_count"] or 0)
            if previous_seen is not None:
                seconds_since_seen = (_utc_now() - previous_seen).total_seconds()
                if seconds_since_seen < FOCUS_ROOM_HEARTBEAT_THROTTLE_SECONDS:
                    risk_flags.append("heartbeat_throttled")
                    now_text = existing["last_seen_at"] or now_text
                if (
                    seconds_since_seen < FOCUS_ROOM_SESSION_JUMP_WINDOW_SECONDS
                    and session_count - previous_session_count
                    > FOCUS_ROOM_MAX_SESSION_COUNT_JUMP
                ):
                    session_count = min(
                        previous_session_count + FOCUS_ROOM_MAX_SESSION_COUNT_JUMP,
                        FOCUS_ROOM_MAX_SESSION_COUNT,
                    )
                    risk_flags.append("session_count_jump_capped")
        risk_flags_text, risk_summary = _focus_risk_payload(risk_flags)
        db.execute(
            """
            INSERT INTO focus_room_presence(
                room_id, user_id, display_name, raw_weekly_seconds,
                weekly_seconds, session_count, active, started_at,
                last_seen_at, risk_flags, risk_summary, updated_at
            )
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(room_id, user_id) DO UPDATE SET
                display_name=excluded.display_name,
                raw_weekly_seconds=excluded.raw_weekly_seconds,
                weekly_seconds=excluded.weekly_seconds,
                session_count=excluded.session_count,
                active=excluded.active,
                started_at=excluded.started_at,
                last_seen_at=excluded.last_seen_at,
                risk_flags=excluded.risk_flags,
                risk_summary=excluded.risk_summary,
                updated_at=excluded.updated_at
            """,
            (
                clean_room_id,
                user_id,
                display_name,
                raw_weekly_seconds,
                weekly_seconds,
                session_count,
                1 if req.active else 0,
                started_at_text,
                now_text,
                risk_flags_text,
                risk_summary,
                now_text,
            ),
        )
        db.commit()
        return _focus_room_ranking(db, clean_room_id, user_id)
    finally:
        db.close()


@app.get("/api/focus-rooms/{room_id}/ranking")
def focus_room_ranking(room_id: str, user_id: str = Depends(_verify_token)):
    clean_room_id = _clean_focus_room_id(room_id)
    db = get_db()
    try:
        return _focus_room_ranking(db, clean_room_id, user_id)
    finally:
        db.close()


@app.get("/api/focus-rooms/{room_id}/events")
async def focus_room_events(
    room_id: str,
    interval_seconds: int = Query(15, ge=2, le=60),
    user_id: str = Depends(_verify_token),
):
    clean_room_id = _clean_focus_room_id(room_id)

    async def event_stream():
        while True:
            db = get_db()
            try:
                payload = _focus_room_ranking(db, clean_room_id, user_id)
            finally:
                db.close()
            yield (
                "event: ranking\n"
                f"data: {json.dumps(payload, ensure_ascii=False)}\n\n"
            )
            await asyncio.sleep(interval_seconds)

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


@app.websocket("/ws/focus-rooms/{room_id}/events")
async def focus_room_events_ws(websocket: WebSocket, room_id: str):
    clean_room_id = _clean_focus_room_id(room_id)
    token = websocket.query_params.get("token")
    try:
        user_id = _verify_token_value(token)
    except HTTPException:
        await websocket.close(code=1008)
        return
    await websocket.accept()
    interval_seconds = 15
    try:
        raw_interval = websocket.query_params.get("interval_seconds")
        if raw_interval is not None:
            interval_seconds = min(60, max(2, int(raw_interval)))
    except ValueError:
        interval_seconds = 15

    async def send_ranking():
        db = get_db()
        try:
            payload = _focus_room_ranking(db, clean_room_id, user_id)
        finally:
            db.close()
        await websocket.send_json({"event": "ranking", "data": payload})

    try:
        await send_ranking()
        while True:
            try:
                message = await asyncio.wait_for(
                    websocket.receive_json(),
                    timeout=interval_seconds,
                )
                event = message.get("event") if isinstance(message, dict) else None
                if event in ("ping", "ranking"):
                    await send_ranking()
            except asyncio.TimeoutError:
                await send_ranking()
    except WebSocketDisconnect:
        return


@app.websocket("/ws/focus-leaderboard/global/events")
async def focus_global_leaderboard_events_ws(websocket: WebSocket):
    token = websocket.query_params.get("token")
    try:
        user_id = _verify_token_value(token)
    except HTTPException:
        await websocket.close(code=1008)
        return
    await websocket.accept()
    interval_seconds = 15
    try:
        raw_interval = websocket.query_params.get("interval_seconds")
        if raw_interval is not None:
            interval_seconds = min(60, max(2, int(raw_interval)))
    except ValueError:
        interval_seconds = 15

    async def send_ranking():
        db = get_db()
        try:
            payload = _focus_global_ranking(db, user_id)
        finally:
            db.close()
        await websocket.send_json({"event": "ranking", "data": payload})

    try:
        await send_ranking()
        while True:
            try:
                message = await asyncio.wait_for(
                    websocket.receive_json(),
                    timeout=interval_seconds,
                )
                event = message.get("event") if isinstance(message, dict) else None
                if event in ("ping", "ranking"):
                    await send_ranking()
            except asyncio.TimeoutError:
                await send_ranking()
    except WebSocketDisconnect:
        return


@app.post("/api/focus-rooms/{room_id}/leave")
def leave_focus_room(room_id: str, user_id: str = Depends(_verify_token)):
    clean_room_id = _clean_focus_room_id(room_id)
    now_text = _utc_now_text()
    db = get_db()
    try:
        db.execute(
            """
            UPDATE focus_room_presence
            SET active=0, last_seen_at=?, updated_at=?
            WHERE room_id=? AND user_id=?
            """,
            (now_text, now_text, clean_room_id, user_id),
        )
        db.commit()
        return _focus_room_ranking(db, clean_room_id, user_id)
    finally:
        db.close()


# ---- Sync ----


TOMBSTONE_COLLECTIONS = {
    "todos",
    "habits",
    "pomodoro_sessions",
    "focus_penalties",
    "notes",
    "countdowns",
    "anniversaries",
    "diaries",
    "goals",
    "calendar_events",
    "courses",
    "time_entries",
}


def _timestamp_gte(left: str, right: str) -> bool:
    left_dt = _parse_server_time(left)
    right_dt = _parse_server_time(right)
    if left_dt is not None and right_dt is not None:
        return left_dt >= right_dt
    return str(left or "") >= str(right or "")


def _timestamp_gt(left: str, right: str) -> bool:
    left_dt = _parse_server_time(left)
    right_dt = _parse_server_time(right)
    if left_dt is not None and right_dt is not None:
        return left_dt > right_dt
    return str(left or "") > str(right or "")


def _item_updated_at(item: dict) -> str:
    for key in ("updatedAt", "updated_at", "modifiedAt", "endTime", "createdAt"):
        value = item.get(key)
        if value:
            return str(value)
    return ""


SYNC_PULL_COLLECTIONS = {
    "todos",
    "habits",
    "pomodoro_sessions",
    "focus_penalties",
    "pomodoro_config",
    "user_profile",
    "notes",
    "countdowns",
    "anniversaries",
    "diaries",
    "goals",
    "calendar_events",
    "courses",
    "time_entries",
    "course_settings",
    "achievement_states",
    "virtual_rewards",
    "focus_rooms",
    "theme_shop_state",
    "deleted_items",
    "workspace_payloads",
}

SYNC_OBJECT_COLLECTIONS = {
    "pomodoro_config",
    "user_profile",
    "course_settings",
    "achievement_states",
    "virtual_rewards",
    "focus_rooms",
    "theme_shop_state",
}

SYNC_STATE_OBJECT_COLLECTIONS = {
    "achievement_states",
    "virtual_rewards",
}


def _canonical_json(value) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _payload_hash(value) -> str:
    return hashlib.sha256(_canonical_json(value).encode("utf-8")).hexdigest()


def _sync_collection_hashes(payload: dict) -> dict[str, str]:
    return {key: _payload_hash(payload.get(key)) for key in SYNC_PULL_COLLECTIONS}


def _normalize_deleted_items(raw) -> dict:
    if not isinstance(raw, dict):
        return {}
    result: dict[str, dict[str, str]] = {}
    for collection, values in raw.items():
        collection_key = str(collection)
        if collection_key not in TOMBSTONE_COLLECTIONS:
            continue
        normalized: dict[str, str] = {}
        if isinstance(values, dict):
            iterable = values.items()
        elif isinstance(values, list):
            entries = []
            for item in values:
                if isinstance(item, dict):
                    entries.append(
                        (
                            item.get("id") or item.get("item_id"),
                            item.get("deletedAt") or item.get("deleted_at"),
                        )
                    )
                else:
                    entries.append((item, ""))
            iterable = entries
        else:
            continue
        for item_id, deleted_at in iterable:
            item_id_text = str(item_id or "").strip()
            if not item_id_text:
                continue
            deleted_at_text = str(deleted_at or "").strip() or _utc_now_text()
            current = normalized.get(item_id_text)
            if current is None or _timestamp_gte(deleted_at_text, current):
                normalized[item_id_text] = deleted_at_text
        if normalized:
            result[collection_key] = normalized
    return result


def _merge_deleted_items(server, client) -> dict:
    merged = _normalize_deleted_items(server)
    for collection, values in _normalize_deleted_items(client).items():
        bucket = merged.setdefault(collection, {})
        for item_id, deleted_at in values.items():
            current = bucket.get(item_id)
            if current is None or _timestamp_gte(deleted_at, current):
                bucket[item_id] = deleted_at
    return merged


def _merge_by_timestamp(
    server: list,
    client: list,
    *,
    collection: Optional[str] = None,
    deleted_items: Optional[dict] = None,
) -> list:
    merged = {
        str(item.get("id")): item
        for item in server
        if isinstance(item, dict) and item.get("id") is not None
    }
    for item in client:
        if not isinstance(item, dict):
            continue
        item_id = item.get("id")
        if item_id is None:
            continue
        item_id = str(item_id)
        if item_id not in merged:
            merged[item_id] = item
        else:
            server_ts = merged[item_id].get("updatedAt", "")
            client_ts = item.get("updatedAt", "")
            if client_ts and (not server_ts or _timestamp_gt(client_ts, server_ts)):
                merged[item_id] = item
    if collection and deleted_items:
        tombstones = deleted_items.get(collection, {})
        if isinstance(tombstones, dict):
            for item_id, deleted_at in tombstones.items():
                item = merged.get(item_id)
                if not isinstance(item, dict):
                    continue
                updated_at = _item_updated_at(item)
                if not updated_at or _timestamp_gte(str(deleted_at), updated_at):
                    merged.pop(item_id, None)
    return list(merged.values())


def _prune_deleted_items(deleted_items: dict, collections: dict[str, list]) -> dict:
    pruned = _normalize_deleted_items(deleted_items)
    for collection, items in collections.items():
        tombstones = pruned.get(collection)
        if not tombstones:
            continue
        by_id = {
            str(item.get("id")): item
            for item in items
            if isinstance(item, dict) and item.get("id") is not None
        }
        for item_id, deleted_at in list(tombstones.items()):
            item = by_id.get(item_id)
            if isinstance(item, dict) and _timestamp_gte(
                _item_updated_at(item), deleted_at
            ):
                tombstones.pop(item_id, None)
        if not tombstones:
            pruned.pop(collection, None)
    return pruned


def _merge_dict(server: dict, client: dict) -> dict:
    server_ts = server.get("updatedAt") if isinstance(server, dict) else None
    client_ts = client.get("updatedAt") if isinstance(client, dict) else None
    if client_ts and (not server_ts or _timestamp_gt(client_ts, server_ts)):
        return client
    return server or client


def _merge_state_dict(server: dict, client: dict) -> dict:
    result = dict(server or {})
    for key, value in (client or {}).items():
        current = result.get(key)
        if current is None or str(value) > str(current):
            result[key] = value
    return result


def _apply_item_delta_to_payload(payload: dict, req: SyncItemDeltaRequest) -> dict:
    next_payload = dict(payload)
    deleted_items = _merge_deleted_items(
        next_payload.get("deleted_items", {}), req.deleted_items
    )
    for collection, changes in (req.items or {}).items():
        collection_key = str(collection)
        if collection_key not in TOMBSTONE_COLLECTIONS:
            continue
        if not isinstance(changes, list):
            continue
        current = next_payload.get(collection_key)
        current_list = current if isinstance(current, list) else []
        next_payload[collection_key] = _merge_by_timestamp(
            current_list,
            changes,
            collection=collection_key,
            deleted_items=deleted_items,
        )
    for key, value in (req.objects or {}).items():
        key_text = str(key)
        if key_text not in SYNC_OBJECT_COLLECTIONS:
            continue
        current = next_payload.get(key_text)
        if key_text in SYNC_STATE_OBJECT_COLLECTIONS:
            next_payload[key_text] = _merge_state_dict(
                current if isinstance(current, dict) else {},
                value if isinstance(value, dict) else {},
            )
        else:
            next_payload[key_text] = _merge_dict(
                current if isinstance(current, dict) else {},
                value if isinstance(value, dict) else {},
            )
    next_payload["deleted_items"] = _prune_deleted_items(
        deleted_items,
        {
            collection: next_payload.get(collection, [])
            for collection in TOMBSTONE_COLLECTIONS
        },
    )
    return next_payload


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


def _workspace_comment_to_dict(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "workspace_id": row["workspace_id"],
        "target_id": row["target_id"] or "",
        "author_user_id": row["author_user_id"],
        "author_name": row["author_name"],
        "body": row["body"],
        "created_at": row["created_at"],
    }


def _workspace_mention_to_dict(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "workspace_id": row["workspace_id"],
        "workspace_name": row["workspace_name"],
        "comment_id": row["comment_id"],
        "target_id": row["target_id"] or "",
        "author_user_id": row["author_user_id"],
        "author_name": row["author_name"],
        "body": row["body"],
        "read_at": row["read_at"],
        "created_at": row["created_at"],
    }


def _workspace_activity_to_dict(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "workspace_id": row["workspace_id"],
        "actor_user_id": row["actor_user_id"],
        "actor_name": row["actor_name"],
        "action": row["action"],
        "detail": row["detail"] or "",
        "created_at": row["created_at"],
    }


def _extract_workspace_mentions(
    db, workspace_id: str, body: str, author_user_id: str
) -> list[str]:
    tokens = {
        match.group(1).strip().lower()
        for match in re.finditer(
            r"(?<![\w@])@([\w.\-+@/\u4e00-\u9fff]{1,96})",
            body,
        )
    }
    if not tokens:
        return []
    rows = db.execute(
        """
        SELECT wm.user_id, u.username, u.email, u.display_name
        FROM workspace_members wm
        JOIN users u ON u.id = wm.user_id
        WHERE wm.workspace_id=?
        """,
        (workspace_id,),
    ).fetchall()
    matched: list[str] = []
    seen: set[str] = set()
    for row in rows:
        if row["user_id"] == author_user_id:
            continue
        aliases = {
            row["user_id"].lower(),
            (row["username"] or "").lower(),
            (row["email"] or "").lower(),
            (row["display_name"] or "").lower(),
        }
        email = (row["email"] or "").strip().lower()
        if "@" in email:
            aliases.add(email.split("@", 1)[0])
        aliases = {alias for alias in aliases if alias}
        if tokens.intersection(aliases) and row["user_id"] not in seen:
            matched.append(row["user_id"])
            seen.add(row["user_id"])
    return matched


def _create_workspace_mentions_for_comment(
    db, workspace_id: str, comment_id: str, body: str, author_user_id: str
) -> list[str]:
    mentioned_user_ids = _extract_workspace_mentions(
        db, workspace_id, body, author_user_id
    )
    for target_user_id in mentioned_user_ids:
        db.execute(
            """
            INSERT OR IGNORE INTO workspace_mentions(
                workspace_id, comment_id, target_user_id, mentioned_by_user_id
            ) VALUES(?,?,?,?)
            """,
            (workspace_id, comment_id, target_user_id, author_user_id),
        )
    return mentioned_user_ids


def _workspace_leaderboard(db, workspace_id: str) -> list[dict]:
    members = db.execute(
        """
        SELECT wm.workspace_id, wm.user_id, u.username, wm.role, wm.joined_at
        FROM workspace_members wm
        JOIN users u ON u.id = wm.user_id
        WHERE wm.workspace_id=?
        """,
        (workspace_id,),
    ).fetchall()
    stats = {
        member["user_id"]: {
            "workspace_id": workspace_id,
            "user_id": member["user_id"],
            "username": member["username"],
            "role": member["role"],
            "assigned": 0,
            "completed": 0,
            "completion_rate": 0.0,
        }
        for member in members
    }
    for todo in _workspace_data(db, workspace_id).get("todos", []):
        if not isinstance(todo, dict):
            continue
        assignee_id = str(todo.get("assigneeId") or todo.get("assignee_id") or "")
        if assignee_id not in stats:
            continue
        stats[assignee_id]["assigned"] += 1
        if todo.get("isCompleted") is True or todo.get("completed") is True:
            stats[assignee_id]["completed"] += 1
    for item in stats.values():
        assigned = item["assigned"]
        item["completion_rate"] = (
            round(item["completed"] / assigned, 4) if assigned > 0 else 0.0
        )
    return sorted(
        stats.values(),
        key=lambda item: (
            item["completed"],
            item["completion_rate"],
            item["assigned"],
            item["username"],
        ),
        reverse=True,
    )


def _workspace_data(db, workspace_id: str) -> dict:
    row = db.execute(
        "SELECT todos, goals, courses, time_entries, calendar_events FROM workspace_data WHERE workspace_id=?",
        (workspace_id,),
    ).fetchone()
    if row is None:
        return {
            "todos": [],
            "goals": [],
            "courses": [],
            "time_entries": [],
            "calendar_events": [],
        }
    return {
        "todos": json.loads(row["todos"] or "[]"),
        "goals": json.loads(row["goals"] or "[]"),
        "courses": json.loads(row["courses"] or "[]"),
        "time_entries": json.loads(row["time_entries"] or "[]"),
        "calendar_events": json.loads(row["calendar_events"] or "[]"),
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
                "calendar_events": _merge_by_timestamp(
                    server.get("calendar_events", []), client.get("calendar_events", [])
                ),
            }
            db.execute(
                """
                INSERT INTO workspace_data(workspace_id, todos, goals, courses, time_entries, calendar_events, updated_at)
                VALUES(?,?,?,?,?,?,datetime('now'))
                ON CONFLICT(workspace_id) DO UPDATE SET
                    todos=excluded.todos,
                    goals=excluded.goals,
                    courses=excluded.courses,
                    time_entries=excluded.time_entries,
                    calendar_events=excluded.calendar_events,
                    updated_at=datetime('now')
                """,
                (
                    workspace_id,
                    json.dumps(merged_data["todos"], ensure_ascii=False),
                    json.dumps(merged_data["goals"], ensure_ascii=False),
                    json.dumps(merged_data["courses"], ensure_ascii=False),
                    json.dumps(merged_data["time_entries"], ensure_ascii=False),
                    json.dumps(merged_data["calendar_events"], ensure_ascii=False),
                ),
            )
        merged[workspace_id] = merged_data
    return merged


def _sync_payload_from_row(db, user_id: str, row: Optional[sqlite3.Row]) -> dict:
    def _list(col):
        return json.loads(row[col]) if row and row[col] else []

    def _obj(col):
        value = json.loads(row[col]) if row and row[col] else {}
        return value if isinstance(value, dict) else {}

    return {
        "todos": _list("todos"),
        "habits": _list("habits"),
        "pomodoro_sessions": _list("pomodoro_sessions"),
        "focus_penalties": _list("focus_penalties"),
        "pomodoro_config": _obj("pomodoro_config"),
        "user_profile": _obj("user_profile"),
        "notes": _list("notes"),
        "countdowns": _list("countdowns"),
        "anniversaries": _list("anniversaries"),
        "diaries": _list("diaries"),
        "goals": _list("goals"),
        "calendar_events": _list("calendar_events"),
        "courses": _list("courses"),
        "time_entries": _list("time_entries"),
        "course_settings": _obj("course_settings"),
        "achievement_states": _obj("achievement_states"),
        "virtual_rewards": _obj("virtual_rewards"),
        "focus_rooms": _obj("focus_rooms"),
        "theme_shop_state": _obj("theme_shop_state"),
        "deleted_items": _obj("deleted_items"),
        "workspace_payloads": _merge_workspace_payloads(db, user_id, {}),
    }


def _sync_response(
    *,
    server_updated_at: str,
    server_version: int,
    payload: dict,
    include_hashes: bool = False,
) -> dict:
    response = {
        "server_updated_at": server_updated_at,
        "server_version": server_version,
        **payload,
    }
    if include_hashes:
        response["collection_hashes"] = _sync_collection_hashes(payload)
    return response


def _sync_impl(
    req: SyncRequest,
    user_id: str,
    *,
    model_dump_payload: Optional[dict] = None,
) -> dict:
    db = get_db()
    try:
        if _setting_get(db, "maintenance_mode", False):
            raise HTTPException(status_code=503, detail="Maintenance mode")
        if not _setting_get(db, "backup_enabled", True):
            raise HTTPException(status_code=503, detail="云端备份已被管理员关闭")

        # 简单的 payload 大小保护
        max_kb = int(_setting_get(db, "backup_max_size_kb", 2048) or 2048)
        if max_kb > 0:
            dump_payload = model_dump_payload if model_dump_payload is not None else req.model_dump()
            payload_size = len(
                json.dumps(dump_payload, ensure_ascii=False).encode("utf-8")
            )
            if payload_size > max_kb * 1024:
                raise HTTPException(
                    status_code=413,
                    detail=f"同步数据过大 ({payload_size // 1024}KB > {max_kb}KB)",
                )

        _ensure_private_workspace(db, user_id)
        row = db.execute(
            "SELECT todos, habits, pomodoro_sessions, pomodoro_config, user_profile, "
            "notes, countdowns, anniversaries, diaries, goals, calendar_events, "
            "courses, time_entries, course_settings, achievement_states, virtual_rewards, focus_rooms, "
            "focus_penalties, theme_shop_state, deleted_items, sync_version "
            "FROM sync_data WHERE user_id=?",
            (user_id,),
        ).fetchone()
        next_sync_version = int(row["sync_version"] or 0) + 1 if row else 1
        sync_updated_at = _utc_now_text()

        def _list(col):
            return json.loads(row[col]) if row and row[col] else []

        def _obj(col):
            value = json.loads(row[col]) if row and row[col] else {}
            return value if isinstance(value, dict) else {}

        server_todos = _list("todos")
        server_habits = _list("habits")
        server_sessions = _list("pomodoro_sessions")
        server_focus_penalties = _list("focus_penalties")
        server_config = _obj("pomodoro_config")
        server_profile = _obj("user_profile")
        server_notes = _list("notes")
        server_countdowns = _list("countdowns")
        server_annis = _list("anniversaries")
        server_diaries = _list("diaries")
        server_goals = _list("goals")
        server_calendar_events = _list("calendar_events")
        server_courses = _list("courses")
        server_time_entries = _list("time_entries")
        server_course_settings = _obj("course_settings")
        server_achievement_states = _obj("achievement_states")
        server_virtual_rewards = _obj("virtual_rewards")
        server_focus_rooms = _obj("focus_rooms")
        server_theme_shop_state = _obj("theme_shop_state")
        server_deleted_items = _obj("deleted_items")
        merged_deleted_items = _merge_deleted_items(
            server_deleted_items, req.deleted_items
        )

        merged_todos = _merge_by_timestamp(
            server_todos,
            req.todos,
            collection="todos",
            deleted_items=merged_deleted_items,
        )
        merged_habits = _merge_by_timestamp(
            server_habits,
            req.habits,
            collection="habits",
            deleted_items=merged_deleted_items,
        )
        merged_sessions = _merge_by_timestamp(
            server_sessions,
            req.pomodoro_sessions,
            collection="pomodoro_sessions",
            deleted_items=merged_deleted_items,
        )
        merged_focus_penalties = _merge_by_timestamp(
            server_focus_penalties,
            req.focus_penalties,
            collection="focus_penalties",
            deleted_items=merged_deleted_items,
        )
        merged_config = _merge_dict(server_config, req.pomodoro_config)
        merged_profile = _merge_dict(server_profile, req.user_profile)
        merged_notes = _merge_by_timestamp(
            server_notes,
            req.notes,
            collection="notes",
            deleted_items=merged_deleted_items,
        )
        merged_countdowns = _merge_by_timestamp(
            server_countdowns,
            req.countdowns,
            collection="countdowns",
            deleted_items=merged_deleted_items,
        )
        merged_annis = _merge_by_timestamp(
            server_annis,
            req.anniversaries,
            collection="anniversaries",
            deleted_items=merged_deleted_items,
        )
        merged_diaries = _merge_by_timestamp(
            server_diaries,
            req.diaries,
            collection="diaries",
            deleted_items=merged_deleted_items,
        )
        merged_goals = _merge_by_timestamp(
            server_goals,
            req.goals,
            collection="goals",
            deleted_items=merged_deleted_items,
        )
        merged_calendar_events = _merge_by_timestamp(
            server_calendar_events,
            req.calendar_events,
            collection="calendar_events",
            deleted_items=merged_deleted_items,
        )
        merged_courses = _merge_by_timestamp(
            server_courses,
            req.courses,
            collection="courses",
            deleted_items=merged_deleted_items,
        )
        merged_time_entries = _merge_by_timestamp(
            server_time_entries,
            req.time_entries,
            collection="time_entries",
            deleted_items=merged_deleted_items,
        )
        merged_course_settings = _merge_dict(
            server_course_settings, req.course_settings
        )
        merged_achievement_states = _merge_state_dict(
            server_achievement_states, req.achievement_states
        )
        merged_virtual_rewards = _merge_state_dict(
            server_virtual_rewards, req.virtual_rewards
        )
        merged_focus_rooms = _merge_dict(server_focus_rooms, req.focus_rooms)
        merged_theme_shop_state = _merge_dict(
            server_theme_shop_state, req.theme_shop_state
        )
        merged_workspace_payloads = _merge_workspace_payloads(
            db, user_id, req.workspace_payloads
        )
        merged_deleted_items = _prune_deleted_items(
            merged_deleted_items,
            {
                "todos": merged_todos,
                "habits": merged_habits,
                "pomodoro_sessions": merged_sessions,
                "focus_penalties": merged_focus_penalties,
                "notes": merged_notes,
                "countdowns": merged_countdowns,
                "anniversaries": merged_annis,
                "diaries": merged_diaries,
                "goals": merged_goals,
                "calendar_events": merged_calendar_events,
                "courses": merged_courses,
                "time_entries": merged_time_entries,
            },
        )

        db.execute(
            """
            INSERT OR REPLACE INTO sync_data
            (user_id, todos, habits, pomodoro_sessions, pomodoro_config, user_profile,
             notes, countdowns, anniversaries, diaries, goals, calendar_events,
             courses, time_entries,
             course_settings, achievement_states, virtual_rewards, focus_rooms,
             focus_penalties, theme_shop_state, deleted_items, sync_version, updated_at)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
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
                json.dumps(merged_calendar_events, ensure_ascii=False),
                json.dumps(merged_courses, ensure_ascii=False),
                json.dumps(merged_time_entries, ensure_ascii=False),
                json.dumps(merged_course_settings, ensure_ascii=False),
                json.dumps(merged_achievement_states, ensure_ascii=False),
                json.dumps(merged_virtual_rewards, ensure_ascii=False),
                json.dumps(merged_focus_rooms, ensure_ascii=False),
                json.dumps(merged_focus_penalties, ensure_ascii=False),
                json.dumps(merged_theme_shop_state, ensure_ascii=False),
                json.dumps(merged_deleted_items, ensure_ascii=False),
                next_sync_version,
                sync_updated_at,
            ),
        )
        db.commit()

        return _sync_response(
            server_updated_at=sync_updated_at,
            server_version=next_sync_version,
            payload={
                "todos": merged_todos,
                "habits": merged_habits,
                "pomodoro_sessions": merged_sessions,
                "focus_penalties": merged_focus_penalties,
                "pomodoro_config": merged_config,
                "user_profile": merged_profile,
                "notes": merged_notes,
                "countdowns": merged_countdowns,
                "anniversaries": merged_annis,
                "diaries": merged_diaries,
                "goals": merged_goals,
                "calendar_events": merged_calendar_events,
                "courses": merged_courses,
                "time_entries": merged_time_entries,
                "course_settings": merged_course_settings,
                "achievement_states": merged_achievement_states,
                "virtual_rewards": merged_virtual_rewards,
                "focus_rooms": merged_focus_rooms,
                "theme_shop_state": merged_theme_shop_state,
                "deleted_items": merged_deleted_items,
                "workspace_payloads": merged_workspace_payloads,
            },
            include_hashes=True,
        )
    finally:
        db.close()


@app.post("/api/sync")
def sync(req: SyncRequest, user_id: str = Depends(_verify_token)):
    return _sync_impl(req, user_id)


@app.post("/api/sync/delta")
def sync_delta(req: SyncDeltaRequest, user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        _ensure_private_workspace(db, user_id)
        row = db.execute(
            "SELECT todos, habits, pomodoro_sessions, pomodoro_config, user_profile, "
            "notes, countdowns, anniversaries, diaries, goals, calendar_events, "
            "courses, time_entries, course_settings, achievement_states, virtual_rewards, focus_rooms, "
            "focus_penalties, theme_shop_state, deleted_items, sync_version "
            "FROM sync_data WHERE user_id=?",
            (user_id,),
        ).fetchone()
        payload = _sync_payload_from_row(db, user_id, row)
    finally:
        db.close()
    if isinstance(req.collections, dict):
        for key, value in req.collections.items():
            key_text = str(key)
            if key_text in payload:
                payload[key_text] = value
    return _sync_impl(
        SyncRequest(**payload),
        user_id,
        model_dump_payload=req.model_dump(),
    )


@app.post("/api/sync/item-delta")
def sync_item_delta(req: SyncItemDeltaRequest, user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        _ensure_private_workspace(db, user_id)
        row = db.execute(
            "SELECT todos, habits, pomodoro_sessions, pomodoro_config, user_profile, "
            "notes, countdowns, anniversaries, diaries, goals, calendar_events, "
            "courses, time_entries, course_settings, achievement_states, virtual_rewards, focus_rooms, "
            "focus_penalties, theme_shop_state, deleted_items, sync_version "
            "FROM sync_data WHERE user_id=?",
            (user_id,),
        ).fetchone()
        payload = _sync_payload_from_row(db, user_id, row)
    finally:
        db.close()
    payload = _apply_item_delta_to_payload(payload, req)
    return _sync_impl(
        SyncRequest(**payload),
        user_id,
        model_dump_payload=req.model_dump(),
    )


@app.post("/api/sync/pull")
def sync_pull(req: SyncPullRequest, user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        if _setting_get(db, "maintenance_mode", False):
            raise HTTPException(status_code=503, detail="Maintenance mode")
        if not _setting_get(db, "backup_enabled", True):
            raise HTTPException(status_code=503, detail="云端备份已被管理员关闭")

        _ensure_private_workspace(db, user_id)
        row = db.execute(
            "SELECT todos, habits, pomodoro_sessions, pomodoro_config, user_profile, "
            "notes, countdowns, anniversaries, diaries, goals, calendar_events, "
            "courses, time_entries, course_settings, achievement_states, virtual_rewards, focus_rooms, "
            "focus_penalties, theme_shop_state, deleted_items, sync_version, updated_at "
            "FROM sync_data WHERE user_id=?",
            (user_id,),
        ).fetchone()
        payload = _sync_payload_from_row(db, user_id, row)
        collection_hashes = _sync_collection_hashes(payload)
        client_hashes = req.collection_hashes if isinstance(req.collection_hashes, dict) else {}
        changed_payload = {
            key: payload[key]
            for key in SYNC_PULL_COLLECTIONS
            if str(client_hashes.get(key) or "") != collection_hashes[key]
        }
        changed_payload["collection_hashes"] = collection_hashes
        return {
            "server_updated_at": row["updated_at"] if row else "",
            "server_version": int(row["sync_version"] or 0) if row else 0,
            **changed_payload,
        }
    finally:
        db.close()


@app.get("/api/sync/status")
def sync_status(user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        row = db.execute(
            "SELECT updated_at, sync_version FROM sync_data WHERE user_id=?",
            (user_id,),
        ).fetchone()
        return {
            "server_updated_at": row["updated_at"] if row else "",
            "server_version": int(row["sync_version"] or 0) if row else 0,
        }
    finally:
        db.close()


@app.get("/api/sync/events")
async def sync_events(
    interval_seconds: int = Query(15, ge=2, le=60),
    user_id: str = Depends(_verify_token),
):
    def _sync_revision() -> dict:
        db = get_db()
        try:
            row = db.execute(
                "SELECT updated_at, sync_version FROM sync_data WHERE user_id=?",
                (user_id,),
            ).fetchone()
            return {
                "server_updated_at": row["updated_at"] if row else "",
                "server_version": int(row["sync_version"] or 0) if row else 0,
            }
        finally:
            db.close()

    async def event_stream():
        last_signature: Optional[tuple[int, str]] = None
        while True:
            payload = _sync_revision()
            signature = (
                int(payload.get("server_version") or 0),
                str(payload.get("server_updated_at") or ""),
            )
            if last_signature != signature:
                last_signature = signature
                yield (
                    "event: sync\n"
                    f"data: {json.dumps(payload, ensure_ascii=False)}\n\n"
                )
            await asyncio.sleep(interval_seconds)

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


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
        _workspace_activity(db, user_id, "workspace.create", workspace_id, name)
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
        _workspace_activity(db, user_id, "workspace.invite", workspace_id, req.role)
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
        _workspace_activity(
            db,
            user_id,
            "workspace.invite.accept",
            row["workspace_id"],
            row["role"],
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
        _workspace_activity(
            db,
            user_id,
            "workspace.member.role",
            workspace_id,
            json.dumps({"user_id": member_user_id, "role": req.role}, ensure_ascii=False),
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
        _workspace_activity(
            db,
            user_id,
            "workspace.member.remove",
            workspace_id,
            member_user_id,
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


@app.get("/api/workspaces/{workspace_id}/comments")
def list_workspace_comments(
    workspace_id: str,
    target_id: Optional[str] = None,
    user_id: str = Depends(_verify_token),
):
    db = get_db()
    try:
        _require_workspace_member(db, workspace_id, user_id)
        params: list = [workspace_id]
        where = "wc.workspace_id=?"
        if target_id:
            where += " AND wc.target_id=?"
            params.append(target_id)
        rows = db.execute(
            f"""
            SELECT wc.*, u.username AS author_name
            FROM workspace_comments wc
            JOIN users u ON u.id = wc.author_user_id
            WHERE {where}
            ORDER BY wc.created_at DESC
            LIMIT 100
            """,
            params,
        ).fetchall()
        return [_workspace_comment_to_dict(row) for row in rows]
    finally:
        db.close()


@app.post("/api/workspaces/{workspace_id}/comments")
def create_workspace_comment(
    workspace_id: str,
    req: WorkspaceCommentCreate,
    user_id: str = Depends(_verify_token),
):
    body = req.body.strip()
    if not body:
        raise HTTPException(status_code=400, detail="Comment body required")
    if len(body) > 1000:
        raise HTTPException(status_code=400, detail="Comment body too long")
    db = get_db()
    try:
        _require_workspace_member(db, workspace_id, user_id)
        comment_id = secrets.token_hex(12)
        target_id = (req.target_id or "").strip()
        db.execute(
            """
            INSERT INTO workspace_comments(id, workspace_id, target_id, author_user_id, body)
            VALUES(?,?,?,?,?)
            """,
            (comment_id, workspace_id, target_id, user_id, body),
        )
        _workspace_activity(
            db,
            user_id,
            "workspace.comment",
            workspace_id,
            json.dumps({"target_id": target_id, "body": body[:80]}, ensure_ascii=False),
        )
        mentioned_user_ids = _create_workspace_mentions_for_comment(
            db, workspace_id, comment_id, body, user_id
        )
        mention_count = len(mentioned_user_ids)
        if mention_count > 0:
            _workspace_activity(
                db,
                user_id,
                "workspace.mention",
                workspace_id,
                json.dumps(
                    {"target_id": target_id, "count": mention_count},
                    ensure_ascii=False,
                ),
            )
            author_name = _get_username(db, user_id)
            workspace_row = db.execute(
                "SELECT name FROM workspaces WHERE id=?",
                (workspace_id,),
            ).fetchone()
            workspace_name = workspace_row["name"] if workspace_row else workspace_id
            for target_user_id in mentioned_user_ids:
                try:
                    _send_workspace_mention_email(
                        db,
                        target_user_id=target_user_id,
                        author_name=author_name,
                        workspace_name=workspace_name,
                        target_id=target_id,
                        body=body,
                    )
                    _audit(
                        db,
                        user_id,
                        author_name,
                        "workspace.mention_email.sent",
                        target_user_id,
                        workspace_id,
                    )
                except Exception as e:
                    _audit(
                        db,
                        user_id,
                        author_name,
                        "workspace.mention_email.failed",
                        target_user_id,
                        str(e),
                    )
        db.commit()
        row = db.execute(
            """
            SELECT wc.*, u.username AS author_name
            FROM workspace_comments wc
            JOIN users u ON u.id = wc.author_user_id
            WHERE wc.id=?
            """,
            (comment_id,),
        ).fetchone()
        return _workspace_comment_to_dict(row)
    finally:
        db.close()


@app.get("/api/workspaces/mentions")
def list_workspace_mentions(
    unread_only: bool = False,
    user_id: str = Depends(_verify_token),
):
    db = get_db()
    try:
        where = "m.target_user_id=?"
        params: list = [user_id]
        if unread_only:
            where += " AND m.read_at IS NULL"
        rows = db.execute(
            f"""
            SELECT
                m.id,
                m.workspace_id,
                w.name AS workspace_name,
                m.comment_id,
                wc.target_id,
                wc.author_user_id,
                u.username AS author_name,
                wc.body,
                m.read_at,
                m.created_at
            FROM workspace_mentions m
            JOIN workspace_comments wc ON wc.id = m.comment_id
            JOIN workspaces w ON w.id = m.workspace_id
            JOIN users u ON u.id = wc.author_user_id
            JOIN workspace_members access
              ON access.workspace_id = m.workspace_id
             AND access.user_id = m.target_user_id
            WHERE {where}
            ORDER BY m.created_at DESC, m.id DESC
            LIMIT 100
            """,
            params,
        ).fetchall()
        return [_workspace_mention_to_dict(row) for row in rows]
    finally:
        db.close()


@app.post("/api/workspaces/mentions/{mention_id}/read")
def mark_workspace_mention_read(
    mention_id: int,
    user_id: str = Depends(_verify_token),
):
    db = get_db()
    try:
        row = db.execute(
            "SELECT id FROM workspace_mentions WHERE id=? AND target_user_id=?",
            (mention_id, user_id),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Mention not found")
        db.execute(
            "UPDATE workspace_mentions SET read_at=datetime('now') WHERE id=?",
            (mention_id,),
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


@app.get("/api/workspaces/{workspace_id}/activities")
def list_workspace_activities(
    workspace_id: str,
    user_id: str = Depends(_verify_token),
):
    db = get_db()
    try:
        _require_workspace_member(db, workspace_id, user_id)
        rows = db.execute(
            """
            SELECT *
            FROM workspace_activity
            WHERE workspace_id=?
            ORDER BY created_at DESC, id DESC
            LIMIT 100
            """,
            (workspace_id,),
        ).fetchall()
        return [_workspace_activity_to_dict(row) for row in rows]
    finally:
        db.close()


@app.get("/api/workspaces/{workspace_id}/leaderboard")
def workspace_leaderboard(workspace_id: str, user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        row = _require_workspace_member(db, workspace_id, user_id)
        if row["is_private"]:
            raise HTTPException(status_code=400, detail="Private workspace has no leaderboard")
        return _workspace_leaderboard(db, workspace_id)
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
        online_ids = sorted(_online_user_ids())
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
        active_cutoff = _format_utc(_utc_now() - timedelta(days=7))
        users_active_7d = db.execute(
            """
            SELECT COUNT(*) AS c
            FROM users
            WHERE (last_active_at IS NOT NULL AND last_active_at >= ?)
               OR (last_login_at IS NOT NULL AND last_login_at >= ?)
            """,
            (active_cutoff, active_cutoff),
        ).fetchone()["c"]
        users_unverified_email = db.execute(
            "SELECT COUNT(*) AS c FROM users WHERE email<>'' AND email_verified=0"
        ).fetchone()["c"]

        fb_total = db.execute("SELECT COUNT(*) AS c FROM feedback").fetchone()["c"]
        fb_open = db.execute(
            "SELECT COUNT(*) AS c FROM feedback WHERE status='open'"
        ).fetchone()["c"]
        fb_in_progress = db.execute(
            "SELECT COUNT(*) AS c FROM feedback WHERE status='in_progress'"
        ).fetchone()["c"]
        fb_resolved = db.execute(
            "SELECT COUNT(*) AS c FROM feedback WHERE status='resolved'"
        ).fetchone()["c"]
        fb_closed = db.execute(
            "SELECT COUNT(*) AS c FROM feedback WHERE status='closed'"
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
                "online": len(online_ids),
                "unverified_email": users_unverified_email,
            },
            "feedback": {
                "total": fb_total,
                "open": fb_open,
                "in_progress": fb_in_progress,
                "resolved": fb_resolved,
                "closed": fb_closed,
            },
            "announcements": {"total": ann_total, "published": ann_published},
            "invites": {"total": invite_total, "used": invite_used},
            "registration_series": reg_series,
            "tokens_online": len(online_ids),
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
        for secret_key in (
            "openlist_password",
            "backup_email_smtp_password",
            "reminder_email_smtp_password",
            "openclaw_mail_api_key",
            "resend_api_key",
            "hermes_api_key",
            "email_smtp_password",
        ):
            raw = str(result.get(secret_key) or "")
            result[f"{secret_key}_set"] = bool(raw)
            result[secret_key] = (
                f"{raw[:2]}***{raw[-2:]}" if len(raw) > 4 else ("***" if raw else "")
            )
        result.update(_account_email_runtime_status(_account_mail_runtime(db)))
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
            if key == "allow_public_registration":
                _setting_set(db, "registration_enabled", value)
                changed["registration_enabled"] = value
            elif key == "registration_enabled":
                _setting_set(db, "allow_public_registration", value)
                changed["allow_public_registration"] = value
            elif key == "registration_invite_required":
                _setting_set(db, "invite_code_required", value)
                changed["invite_code_required"] = value
            elif key == "invite_code_required":
                _setting_set(db, "registration_invite_required", value)
                changed["registration_invite_required"] = value
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
    status: Optional[str] = None,
    online: Optional[bool] = None,
    sort: str = "created_desc",
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    limit, offset = _admin_page_window(limit, offset)
    db = get_db()
    try:
        where, params = _user_admin_filters(q=q, status=status)
        if online is not None:
            online_ids = sorted(_online_user_ids())
            placeholders = ",".join("?" for _ in online_ids)
            online_clause = (
                f"u.id IN ({placeholders})"
                if online
                else (
                    f"u.id NOT IN ({placeholders})"
                    if online_ids
                    else "1=1"
                )
            )
            if online and not online_ids:
                online_clause = "1=0"
            where = (
                f"{where} AND {online_clause}"
                if where
                else f"WHERE {online_clause}"
            )
            params = [*params, *online_ids]
        order_by = _user_admin_order_by(sort)
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM users u {where}", params
        ).fetchone()["c"]
        rows = db.execute(
            "SELECT u.id, u.username, u.email, u.email_verified, u.display_name, "
            "u.is_admin, u.is_disabled, u.created_at, u.last_login_at, u.last_active_at, "
            "(SELECT COUNT(*) FROM feedback WHERE user_id=u.id) AS fb_count "
            f"FROM users u {where} ORDER BY {order_by} LIMIT ? OFFSET ?",
            (*params, limit, offset),
        ).fetchall()
        online_user_ids = _online_user_ids(r["id"] for r in rows)
        items = [
            {
                "user_id": r["id"],
                "username": r["username"],
                "email": r["email"],
                "email_verified": bool(r["email_verified"]),
                "display_name": r["display_name"],
                "is_admin": bool(r["is_admin"]),
                "is_disabled": bool(r["is_disabled"]),
                "created_at": r["created_at"],
                "last_login_at": r["last_login_at"],
                "last_active_at": r["last_active_at"],
                "feedback_count": r["fb_count"],
                "online": r["id"] in online_user_ids,
            }
            for r in rows
        ]
        return _admin_page_response(items, total, limit, offset)
    finally:
        db.close()


@app.get("/api/admin/users/export.csv")
def export_users_csv(
    actor: str = Depends(_require_admin),
    q: Optional[str] = None,
    status: Optional[str] = None,
    online: Optional[bool] = None,
    sort: str = "created_desc",
    limit: int = Query(5000, ge=1, le=20000),
):
    limit, _offset = _admin_page_window(limit, 0, default_limit=5000, max_limit=20000)
    db = get_db()
    try:
        where, params = _user_admin_filters(q=q, status=status)
        if online is not None:
            online_ids = sorted(_online_user_ids())
            placeholders = ",".join("?" for _ in online_ids)
            online_clause = (
                f"u.id IN ({placeholders})"
                if online
                else (
                    f"u.id NOT IN ({placeholders})"
                    if online_ids
                    else "1=1"
                )
            )
            if online and not online_ids:
                online_clause = "1=0"
            where = (
                f"{where} AND {online_clause}"
                if where
                else f"WHERE {online_clause}"
            )
            params = [*params, *online_ids]
        order_by = _user_admin_order_by(sort)
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM users u {where}", params
        ).fetchone()["c"]
        rows = db.execute(
            "SELECT u.id, u.username, u.email, u.display_name, "
            "u.is_admin, u.is_disabled, u.created_at, u.last_login_at, u.last_active_at, "
            "(SELECT COUNT(*) FROM feedback WHERE user_id=u.id) AS fb_count "
            f"FROM users u {where} ORDER BY {order_by} LIMIT ?",
            (*params, limit),
        ).fetchall()
        buffer = io.StringIO()
        writer = csv.writer(buffer)
        writer.writerow(
            [
                "user_id",
                "username",
                "email",
                "display_name",
                "is_admin",
                "is_disabled",
                "created_at",
                "last_login_at",
                "last_active_at",
                "feedback_count",
            ]
        )
        for row in rows:
            writer.writerow(
                [
                    row["id"],
                    _csv_safe(row["username"]),
                    _csv_safe(row["email"]),
                    _csv_safe(row["display_name"]),
                    int(bool(row["is_admin"])),
                    int(bool(row["is_disabled"])),
                    _csv_safe(row["created_at"]),
                    _csv_safe(row["last_login_at"]),
                    _csv_safe(row["last_active_at"]),
                    int(row["fb_count"] or 0),
                ]
            )
        _audit(
            db,
            actor,
            _get_username(db, actor),
            "user.export",
            detail=json.dumps(
                {
                    "status": status or "",
                    "online": online,
                    "q": q or "",
                    "sort": sort,
                    "rows": len(rows),
                    "total": int(total or 0),
                },
                ensure_ascii=False,
            ),
        )
        db.commit()
        content = "\ufeff" + buffer.getvalue()
        filename = f"duoyi_users_{_utc_now().strftime('%Y%m%d_%H%M%S')}.csv"
        headers = {
            "Content-Disposition": f'attachment; filename="{filename}"',
            "X-Total-Count": str(int(total or 0)),
            "X-Exported-Count": str(len(rows)),
        }
        return StreamingResponse(
            iter([content]),
            media_type="text/csv; charset=utf-8",
            headers=headers,
        )
    finally:
        db.close()


@app.post("/api/admin/users/bulk-status")
def admin_bulk_update_user_status(
    req: UserBulkStatus, actor: str = Depends(_require_admin)
):
    user_ids = list(dict.fromkeys(str(user_id).strip() for user_id in req.user_ids))
    user_ids = [user_id for user_id in user_ids if user_id]
    if not user_ids:
        raise HTTPException(status_code=400, detail="请选择要操作的用户")
    if actor in user_ids and req.is_disabled:
        raise HTTPException(status_code=400, detail="Cannot disable yourself")
    db = get_db()
    try:
        placeholders = ",".join("?" for _ in user_ids)
        rows = db.execute(
            f"SELECT id, username, is_admin, is_disabled FROM users WHERE id IN ({placeholders})",
            user_ids,
        ).fetchall()
        found_ids = {row["id"] for row in rows}
        missing_ids = [user_id for user_id in user_ids if user_id not in found_ids]
        if missing_ids:
            raise HTTPException(status_code=404, detail="User not found")
        if req.is_disabled:
            active_admins = db.execute(
                "SELECT COUNT(*) AS c FROM users WHERE is_admin=1 AND is_disabled=0"
            ).fetchone()["c"]
            disabling_active_admins = sum(
                1
                for row in rows
                if row["is_admin"] and not row["is_disabled"]
            )
            if active_admins - disabling_active_admins <= 0:
                raise HTTPException(
                    status_code=400,
                    detail="Cannot disable the last active admin",
                )
        db.execute(
            f"UPDATE users SET is_disabled=? WHERE id IN ({placeholders})",
            (1 if req.is_disabled else 0, *user_ids),
        )
        if req.is_disabled:
            for user_id in user_ids:
                _drop_session(user_id)
        _audit(
            db,
            actor,
            _get_username(db, actor),
            "user.bulk_status",
            target=",".join(user_ids[:20]),
            detail=json.dumps(
                {
                    "is_disabled": req.is_disabled,
                    "count": len(user_ids),
                },
                ensure_ascii=False,
            ),
        )
        db.commit()
        return {"status": "ok", "updated": len(user_ids)}
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
def admin_list_announcements(
    _: str = Depends(_require_admin),
    q: Optional[str] = None,
    status: Optional[str] = None,
    level: Optional[str] = None,
    sort: str = "created_desc",
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    limit, offset = _admin_page_window(limit, offset)
    db = get_db()
    try:
        where_parts: list[str] = []
        params: list = []
        if q:
            where_parts.append("(title LIKE ? OR body LIKE ?)")
            like = f"%{q}%"
            params.extend([like, like])
        if status == "published":
            where_parts.append("published=1")
        elif status == "draft":
            where_parts.append("published=0")
        if level:
            where_parts.append("level=?")
            params.append(level)
        where = f"WHERE {' AND '.join(where_parts)}" if where_parts else ""
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM announcements {where}", params
        ).fetchone()["c"]
        order_by = {
            "created_desc": "id DESC",
            "updated_desc": "updated_at DESC, id DESC",
            "title_asc": "lower(title) ASC, id DESC",
            "level_desc": "CASE level WHEN 'critical' THEN 0 WHEN 'warning' THEN 1 ELSE 2 END, id DESC",
        }.get(sort, "id DESC")
        rows = db.execute(
            "SELECT id, title, body, level, published, created_at, updated_at "
            f"FROM announcements {where} ORDER BY {order_by} LIMIT ? OFFSET ?",
            (*params, limit, offset),
        ).fetchall()
        return _admin_page_response([dict(r) for r in rows], total, limit, offset)
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
        cur = db.execute("DELETE FROM announcements WHERE id=?", (ann_id,))
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="公告不存在")
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
def list_all_feedback(
    _: str = Depends(_require_admin),
    status: Optional[str] = None,
    q: Optional[str] = None,
    category: Optional[str] = None,
    sort: str = "created_desc",
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    limit, offset = _admin_page_window(limit, offset)
    db = get_db()
    try:
        where, params = _feedback_admin_filters(
            status=status,
            q=q,
            category=category,
        )
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM feedback f JOIN users u ON u.id=f.user_id {where}",
            params,
        ).fetchone()["c"]
        order_by = _feedback_admin_order_by(sort)
        rows = db.execute(
            "SELECT f.*, u.username FROM feedback f JOIN users u ON u.id=f.user_id "
            f"{where} ORDER BY {order_by} LIMIT ? OFFSET ?",
            (*params, limit, offset),
        ).fetchall()
        return _admin_page_response([dict(r) for r in rows], total, limit, offset)
    finally:
        db.close()


@app.get("/api/admin/feedback/export.csv")
def export_feedback_csv(
    actor: str = Depends(_require_admin),
    status: Optional[str] = None,
    q: Optional[str] = None,
    category: Optional[str] = None,
    sort: str = "created_desc",
    limit: int = Query(5000, ge=1, le=20000),
):
    limit, _offset = _admin_page_window(limit, 0, default_limit=5000, max_limit=20000)
    db = get_db()
    try:
        where, params = _feedback_admin_filters(
            status=status,
            q=q,
            category=category,
        )
        order_by = _feedback_admin_order_by(sort)
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM feedback f JOIN users u ON u.id=f.user_id {where}",
            params,
        ).fetchone()["c"]
        rows = db.execute(
            """
            SELECT
                f.id, u.username, f.category, f.status, f.content,
                f.admin_reply, f.created_at, f.updated_at
            FROM feedback f
            JOIN users u ON u.id=f.user_id
            """
            f"{where} ORDER BY {order_by} LIMIT ?",
            (*params, limit),
        ).fetchall()
        buffer = io.StringIO()
        writer = csv.writer(buffer)
        writer.writerow(
            [
                "id",
                "username",
                "category",
                "status",
                "content",
                "admin_reply",
                "created_at",
                "updated_at",
            ]
        )
        for row in rows:
            writer.writerow(
                [
                    row["id"],
                    _csv_safe(row["username"]),
                    _csv_safe(row["category"]),
                    _csv_safe(row["status"]),
                    _csv_safe(row["content"]),
                    _csv_safe(row["admin_reply"]),
                    _csv_safe(row["created_at"]),
                    _csv_safe(row["updated_at"]),
                ]
            )
        _audit(
            db,
            actor,
            _get_username(db, actor),
            "feedback.export",
            detail=json.dumps(
                {
                    "status": status or "",
                    "category": category or "",
                    "q": q or "",
                    "sort": sort,
                    "rows": len(rows),
                    "total": int(total or 0),
                },
                ensure_ascii=False,
            ),
        )
        db.commit()
        content = "\ufeff" + buffer.getvalue()
        filename = f"duoyi_feedback_{_utc_now().strftime('%Y%m%d_%H%M%S')}.csv"
        headers = {
            "Content-Disposition": f'attachment; filename="{filename}"',
            "X-Total-Count": str(int(total or 0)),
            "X-Exported-Count": str(len(rows)),
        }
        return StreamingResponse(
            iter([content]),
            media_type="text/csv; charset=utf-8",
            headers=headers,
        )
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


@app.post("/api/admin/feedback/bulk-status")
def bulk_update_feedback_status(
    req: FeedbackBulkStatus,
    actor: str = Depends(_require_admin),
):
    ids = sorted({int(v) for v in req.feedback_ids if int(v) > 0})
    if not ids:
        raise HTTPException(status_code=400, detail="请选择要处理的反馈")
    if len(ids) > 100:
        raise HTTPException(status_code=400, detail="单次最多处理 100 条反馈")
    reply = _clean_feedback_content(req.reply)
    status = _clean_feedback_status(req.status)
    placeholders = ",".join("?" for _ in ids)
    db = get_db()
    try:
        existing = db.execute(
            f"SELECT id FROM feedback WHERE id IN ({placeholders})",
            ids,
        ).fetchall()
        existing_ids = [int(r["id"]) for r in existing]
        if len(existing_ids) != len(ids):
            raise HTTPException(status_code=404, detail="部分反馈不存在")
        db.execute(
            f"""
            UPDATE feedback
            SET admin_reply=?, status=?, updated_at=datetime('now')
            WHERE id IN ({placeholders})
            """,
            (reply, status, *ids),
        )
        _audit(
            db,
            actor,
            _get_username(db, actor),
            "feedback.bulk_status",
            target=",".join(str(v) for v in existing_ids),
            detail=f"{status}:{len(existing_ids)}",
        )
        db.commit()
        return {"status": "ok", "updated": len(existing_ids)}
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
        return {"status": "ok", "deleted": 1}
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
def list_invite_codes(
    _: str = Depends(_require_admin),
    q: Optional[str] = None,
    status: Optional[str] = None,
    sort: str = "created_desc",
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    limit, offset = _admin_page_window(limit, offset)
    db = get_db()
    try:
        where_parts: list[str] = []
        params: list = []
        if q:
            where_parts.append("(ic.code LIKE ? OR ic.note LIKE ? OR u.username LIKE ?)")
            like = f"%{q}%"
            params.extend([like, like, like])
        if status == "used":
            where_parts.append("ic.used_by IS NOT NULL")
        elif status == "unused":
            where_parts.append("ic.used_by IS NULL")
        where = f"WHERE {' AND '.join(where_parts)}" if where_parts else ""
        total = db.execute(
            "SELECT COUNT(*) AS c FROM invite_codes ic "
            f"LEFT JOIN users u ON u.id=ic.used_by {where}",
            params,
        ).fetchone()["c"]
        order_by = {
            "created_desc": "ic.created_at DESC, ic.code ASC",
            "used_desc": "ic.used_at IS NULL, ic.used_at DESC, ic.created_at DESC",
            "code_asc": "lower(ic.code) ASC",
            "note_asc": "lower(ic.note) ASC, ic.created_at DESC",
        }.get(sort, "ic.created_at DESC, ic.code ASC")
        rows = db.execute(
            "SELECT ic.code, ic.used_by, ic.used_at, ic.created_at, ic.note, u.username AS used_by_name "
            "FROM invite_codes ic LEFT JOIN users u ON u.id=ic.used_by "
            f"{where} ORDER BY {order_by} LIMIT ? OFFSET ?",
            (*params, limit, offset),
        ).fetchall()
        return _admin_page_response([dict(r) for r in rows], total, limit, offset)
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
    action: Optional[str] = None,
    q: Optional[str] = None,
    sort: str = "created_desc",
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    limit, offset = _admin_page_window(limit, offset, max_limit=500)
    db = get_db()
    try:
        where_parts: list[str] = []
        params: list = []
        if action:
            where_parts.append("action=?")
            params.append(action)
        if q:
            where_parts.append(
                "(actor_name LIKE ? OR actor_id LIKE ? OR action LIKE ? OR target LIKE ? OR detail LIKE ?)"
            )
            like = f"%{q}%"
            params.extend([like, like, like, like, like])
        where = f"WHERE {' AND '.join(where_parts)}" if where_parts else ""
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM audit_log {where}", params
        ).fetchone()["c"]
        order_by = {
            "created_desc": "id DESC",
            "actor_asc": "lower(actor_name) ASC, id DESC",
            "action_asc": "action ASC, id DESC",
            "target_asc": "target ASC, id DESC",
        }.get(sort, "id DESC")
        rows = db.execute(
            f"SELECT * FROM audit_log {where} ORDER BY {order_by} LIMIT ? OFFSET ?",
            (*params, limit, offset),
        ).fetchall()
        return _admin_page_response([dict(r) for r in rows], total, limit, offset)
    finally:
        db.close()
